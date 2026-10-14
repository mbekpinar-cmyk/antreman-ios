import Foundation
import UIKit

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

    static let shortcutName = "Antrenman Saglik"

    /// antrenman://health?d=<metin> — kestirmenin gonderdigi veriyi dosyaya yaz ve sayfaya ilet.
    @MainActor
    static func receive(_ url: URL) {
        guard url.host == "health",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let text = comps.queryItems?.first(where: { $0.name == "d" })?.value else { return }
        let target = documents.appendingPathComponent("saglik.txt")
        try? Data(text.utf8).write(to: target, options: .atomic)
        WebViewController.current?.send(read())
    }

    /// Kestirmeyi calistir (Kestirmeler bir an acilir, sonra veriyle uygulamaya geri doner).
    @MainActor
    static func runShortcut() {
        var c = URLComponents(string: "shortcuts://run-shortcut")!
        c.queryItems = [URLQueryItem(name: "name", value: shortcutName)]
        if let u = c.url { UIApplication.shared.open(u) }
    }

    static func status() -> String {
        guard let u = url() else { return "YOK — kestirme henüz dosya yazmamış" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
        guard let d = attrs?[.modificationDate] as? Date else { return u.lastPathComponent }
        let f = DateFormatter()
        f.dateFormat = "d.M HH:mm"
        let raw = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        return "\(f.string(from: d)) · \(raw.prefix(300))"
    }
}
