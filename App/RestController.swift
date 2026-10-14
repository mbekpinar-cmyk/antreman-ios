import ActivityKit
import Foundation
import UserNotifications

/// Mola sayacinin native tarafi: Live Activity (kilit ekrani + Dynamic Island
/// + Apple Watch Smart Stack) ve mola bitis bildirimi (kilitliyken saate duser).
/// Web sayfasi sayaci baslatir; Live Activity butonlari (+30 sn / Bitir)
/// buraya gelir ve sonuc sayfaya geri bildirilir.
@MainActor
final class RestController {
    static let shared = RestController()

    private let notificationID = "rest-end"

    /// Teshis ekrani icin: Live Activity son denemesinin sonucu.
    private(set) var lastActivityResult = "henüz denenmedi"
    private let infoKey = "rest.info.v1"

    struct RestInfo: Codable {
        var start: Date
        var end: Date
        var exercise: String
        var workout: String
        var sound: Bool
        var labels: RestAttributes.Labels
        var title: String
        var body: String
    }

    /// Uygulama kapanip acilsa da mola bilgisi kaybolmasin.
    private(set) var info: RestInfo? {
        get {
            guard let data = UserDefaults.standard.data(forKey: infoKey) else { return nil }
            return try? JSONDecoder().decode(RestInfo.self, from: data)
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: infoKey)
            } else {
                UserDefaults.standard.removeObject(forKey: infoKey)
            }
        }
    }

    // MARK: - Web sayfasindan gelenler

    func start(from body: [String: Any]) async {
        let now = Date()
        let startMs = (body["start"] as? Double) ?? now.timeIntervalSince1970 * 1000
        let endMs = (body["end"] as? Double) ?? (startMs + 90_000)
        let t = body["t"] as? [String: Any] ?? [:]
        func text(_ key: String, _ fallback: String) -> String {
            let v = (t[key] as? String) ?? ""
            return v.isEmpty ? fallback : v
        }
        let labels = RestAttributes.Labels(
            rest: text("rest", RestAttributes.Labels.tr.rest),
            done: text("done", RestAttributes.Labels.tr.done),
            add: text("add", RestAttributes.Labels.tr.add),
            end: text("end", RestAttributes.Labels.tr.end)
        )
        let exercise = (body["exercise"] as? String) ?? ""
        let next = RestInfo(
            start: Date(timeIntervalSince1970: startMs / 1000),
            end: Date(timeIntervalSince1970: endMs / 1000),
            exercise: exercise,
            workout: (body["workout"] as? String) ?? "",
            sound: (body["sound"] as? Bool) ?? true,
            labels: labels,
            title: text("done", labels.done),
            body: text("body", exercise)
        )
        info = next
        scheduleNotification(next)
        await upsertActivity(next)
    }

    /// Sayfada +30 sn'ye basildi — yeni bitis zamani sayfadan geliyor.
    func setEnd(milliseconds: Double, notifyWeb: Bool) async {
        guard var current = info else { return }
        let newEnd = Date(timeIntervalSince1970: milliseconds / 1000)
        if current.end <= Date() { current.start = Date() }   // bitmis molaya ekleme: yeni kisa mola
        current.end = newEnd
        info = current
        scheduleNotification(current)
        await upsertActivity(current)
        if notifyWeb {
            WebViewController.current?.send(["type": "restSync", "end": milliseconds])
        }
    }

    /// Kilit ekranindaki / adadaki "+30 sn" butonu.
    func add(seconds: Int) async {
        guard let current = info else { return }
        let base = max(current.end, Date())
        let newEnd = base.addingTimeInterval(TimeInterval(seconds))
        await setEnd(milliseconds: newEnd.timeIntervalSince1970 * 1000, notifyWeb: true)
    }

    /// Mola iptal ("Bitir" butonu ya da sayfadaki x).
    func stop(notifyWeb: Bool) async {
        info = nil
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        for activity in Activity<RestAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if notifyWeb {
            WebViewController.current?.send(["type": "restSync", "end": 0])
        }
    }

    /// Sayfa acikken mola kendiliginden bitti: "Mola bitti" birkac saniye gorunsun, sonra kaybolsun.
    func finished() async {
        let last = info
        info = nil
        for activity in Activity<RestAttributes>.activities {
            let state = last.map { RestAttributes.ContentState(start: $0.start, end: $0.end, exercise: $0.exercise) }
                ?? activity.content.state
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .after(Date().addingTimeInterval(8)))
        }
    }

    /// Uygulama on plana geldi ya da sayfa yeni yuklendi: sayfadaki sayaci native durumla esitle.
    func appBecameActive() async {
        if let current = info {
            if current.end <= Date() {
                await finished()
                WebViewController.current?.send(["type": "restSync", "end": 0])
            } else {
                WebViewController.current?.send(["type": "restSync",
                                                  "end": current.end.timeIntervalSince1970 * 1000])
            }
        } else {
            for activity in Activity<RestAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            WebViewController.current?.send(["type": "restSync", "end": 0])
        }
    }

    // MARK: - Live Activity

    private func upsertActivity(_ i: RestInfo) async {
        let state = RestAttributes.ContentState(start: i.start, end: i.end, exercise: i.exercise)
        let content = ActivityContent(state: state, staleDate: i.end)
        let attributes = RestAttributes(workout: i.workout, labels: i.labels)

        if let existing = Activity<RestAttributes>.activities.first {
            if existing.attributes.workout == i.workout && existing.attributes.labels == i.labels {
                await existing.update(content)
                lastActivityResult = "güncellendi (\(existing.activityState))"
                return
            }
            // Antrenman ya da dil degisti — sabit bilgiler degistirilemiyor, yenisini ac.
            for activity in Activity<RestAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastActivityResult = "Live Activities kapalı (Ayarlar › Antrenman)"
            return
        }
        do {
            let a = try Activity.request(attributes: attributes, content: content, pushType: nil)
            lastActivityResult = "başladı (\(a.activityState))"
        } catch {
            lastActivityResult = "HATA: \(error.localizedDescription) — \(String(describing: error))"
        }
    }

    // MARK: - Bildirim (Apple Watch)

    private func scheduleNotification(_ i: RestInfo) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        let seconds = i.end.timeIntervalSinceNow
        guard seconds > 0.5 else { return }

        let content = UNMutableNotificationContent()
        content.title = i.title
        content.body = i.body
        if i.sound { content.sound = .default }
        content.interruptionLevel = .active
        content.threadIdentifier = "rest"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }
}
