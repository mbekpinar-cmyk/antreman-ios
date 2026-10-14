import Foundation
import HealthKit

/// Apple Health'ten gunluk hazirlik verisi: uyku, gece HRV'si, dinlenik nabiz, solunum.
/// Pil icin: sadece uygulama acilinca/one gelince, en fazla 30 dakikada bir sorgular;
/// arka plan teslimati (background delivery) KULLANMAZ.
@MainActor
final class HealthManager {
    static let shared = HealthManager()

    private let store = HKHealthStore()
    private var cache: (date: Date, payload: [String: Any])?
    private let cacheSeconds: TimeInterval = 30 * 60
    private let baselineDays = 21

    /// Teshis ekrani icin.
    private(set) var lastStatus = "henüz sorgulanmadı"

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]
        s.insert(HKQuantityType(.heartRateVariabilitySDNN))
        s.insert(HKQuantityType(.restingHeartRate))
        s.insert(HKQuantityType(.respiratoryRate))
        return s
    }

    func fetch(force: Bool) async -> [String: Any] {
        if !force, let c = cache, Date().timeIntervalSince(c.date) < cacheSeconds {
            return c.payload
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            lastStatus = "bu cihazda Health yok"
            return ["type": "health", "status": "unavailable"]
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            lastStatus = "HATA (izin): \(error.localizedDescription)"
            return ["type": "health", "status": "error", "error": error.localizedDescription]
        }

        let cal = Calendar.current
        let now = Date()
        let todayKey = dayKey(now, cal)
        let from = cal.date(byAdding: .day, value: -(baselineDays + 2), to: cal.startOfDay(for: now))!

        async let sleepNights = sleepByNight(from: from, to: now, cal: cal)
        async let hrvDays = dailyAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: from, to: now, cal: cal, nightKey: true)
        async let rhrDays = dailyAverage(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: from, to: now, cal: cal, nightKey: false)
        async let respDays = dailyAverage(.respiratoryRate, unit: .count().unitDivided(by: .minute()), from: from, to: now, cal: cal, nightKey: true)

        let sleep = await sleepNights
        let hrv = await hrvDays
        let rhr = await rhrDays
        let resp = await respDays

        func split(_ m: [String: Double]) -> (today: Double?, base: Double?, n: Int) {
            let past = m.filter { $0.key != todayKey }.map(\.value)
            return (m[todayKey], median(past), past.count)
        }
        let s = split(sleep.mapValues { $0 / 3600 })
        let h = split(hrv)
        let r = split(rhr)
        let p = split(resp)

        var today: [String: Any] = [:]
        var base: [String: Any] = [:]
        if let v = s.today { today["sleepH"] = v }
        if let v = s.base { base["sleepH"] = v }
        if let v = h.today { today["hrv"] = v }
        if let v = h.base { base["hrv"] = v }
        if let v = r.today { today["rhr"] = v }
        if let v = r.base { base["rhr"] = v }
        if let v = p.today { today["resp"] = v }
        if let v = p.base { base["resp"] = v }

        // Izin reddedilse bile HealthKit hata vermez, sadece bos doner (gizlilik geregi).
        let empty = sleep.isEmpty && hrv.isEmpty && rhr.isEmpty && resp.isEmpty
        lastStatus = empty
            ? "veri yok (izin verilmemiş olabilir: Ayarlar › Sağlık › Veri Erişimi › Antrenman)"
            : "tamam — gece: \(sleep.count), HRV gün: \(hrv.count), nabız gün: \(rhr.count)"

        let payload: [String: Any] = [
            "type": "health",
            "status": empty ? "empty" : "ok",
            "date": todayKey,
            "today": today,
            "base": base,
            "days": max(s.n, h.n, r.n),
        ]
        cache = (now, payload)
        return payload
    }

    // MARK: - Sorgular

    /// Gece anahtari: baslangic + 12 saat. 23:00'te yatip 07:00'de kalkmak ayni gune (uyanilan gun) duser.
    private func dayKey(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func nightKey(_ start: Date, _ cal: Calendar) -> String {
        dayKey(start.addingTimeInterval(12 * 3600), cal)
    }

    /// Her gece icin uyku suresi (saniye). Saat + telefon ayni geceyi yazabildigi icin
    /// araliklar birlestirilir, cift sayilmaz.
    private func sleepByNight(from: Date, to: Date, cal: Calendar) async -> [String: Double] {
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        let pred = HKQuery.predicateForSamples(withStart: from, end: to)
        let desc = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: pred)],
                                           sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await desc.result(for: store) else { return [:] }
        var byNight: [String: [(Date, Date)]] = [:]
        for s in samples where asleep.contains(s.value) {
            byNight[nightKey(s.startDate, cal), default: []].append((s.startDate, s.endDate))
        }
        return byNight.mapValues { intervals in
            let sorted = intervals.sorted { $0.0 < $1.0 }
            var total: TimeInterval = 0
            var cur: (Date, Date)?
            for iv in sorted {
                if let c = cur, iv.0 <= c.1 {
                    cur = (c.0, max(c.1, iv.1))
                } else {
                    if let c = cur { total += c.1.timeIntervalSince(c.0) }
                    cur = iv
                }
            }
            if let c = cur { total += c.1.timeIntervalSince(c.0) }
            return total
        }
    }

    private func dailyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date,
                              cal: Calendar, nightKey useNight: Bool) async -> [String: Double] {
        let pred = HKQuery.predicateForSamples(withStart: from, end: to)
        let desc = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: pred)],
                                           sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await desc.result(for: store) else { return [:] }
        var buckets: [String: [Double]] = [:]
        for s in samples {
            let key = useNight ? nightKey(s.startDate, cal) : dayKey(s.startDate, cal)
            buckets[key, default: []].append(s.quantity.doubleValue(for: unit))
        }
        return buckets.compactMapValues { v in v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
    }

    private func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
