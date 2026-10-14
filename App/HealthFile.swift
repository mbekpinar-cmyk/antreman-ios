import Foundation

/// Kestirmeler (Shortcuts) uygulamasinin Health'ten okuyup yazdigi gunluk dosya.
/// Konum: Dosyalar › iPhone'umda › Antrenman › saglik.txt
/// Bicim serbest: her satir "anahtar=deger" (sleep, hrv, rhr, resp). Ayristirma sayfada yapilir.
enum HealthFile {
    static let names = ["saglik.txt", "saglık.txt", "health.txt", "saglik.txt.txt"]

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url() -> URL? {
        for n in names {
            let u = documents.appendingPathComponent(n)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    static func read() -> [String: Any] {
        guard let u = url(), let text = try? String(contentsOf: u, encoding: .utf8) else {
            return ["type": "healthFile", "status": "missing"]
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? Date()
        return ["type": "healthFile", "status": "ok", "text": String(text.prefix(4000)),
                "mtime": mtime.timeIntervalSince1970 * 1000]
    }

    static func status() -> String {
        guard let u = url() else { return "YOK — kestirme henüz dosya yazmamış" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
        guard let d = attrs?[.modificationDate] as? Date else { return u.lastPathComponent }
        let f = DateFormatter()
        f.dateFormat = "d.M HH:mm"
        return "\(u.lastPathComponent) · \(f.string(from: d))"
    }
}
