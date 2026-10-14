import Foundation

/// Tum antrenman verisinin dosya yedegi.
/// Sayfa her kayitta (localStorage) buraya da yazar. localStorage bir sekilde
/// silinirse uygulama acilista buradan geri yukler. Dosyalar uygulamasinda
/// "iPhone'umda > Antrenman" altinda gorunur; gunluk kopyalar "Yedekler" klasorunde.
enum Backup {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var mainFile: URL { documents.appendingPathComponent("antrenman-veri.json") }
    static var dailyFolder: URL { documents.appendingPathComponent("Yedekler", isDirectory: true) }

    private static let keepDays = 14

    static func load() -> String? {
        guard let text = try? String(contentsOf: mainFile, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static func save(_ json: String) {
        guard !json.isEmpty else { return }
        let data = Data(json.utf8)
        try? data.write(to: mainFile, options: .atomic)
        writeDailyCopy(data)
    }

    /// Gunde bir kopya, son 14 gun saklanir.
    private static func writeDailyCopy(_ data: Data) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dailyFolder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = dailyFolder.appendingPathComponent("antrenman-\(formatter.string(from: Date())).json")
        try? data.write(to: today, options: .atomic)

        guard let files = try? fm.contentsOfDirectory(at: dailyFolder, includingPropertiesForKeys: nil) else { return }
        let copies = files.filter { $0.lastPathComponent.hasPrefix("antrenman-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in copies.dropFirst(keepDays) {
            try? fm.removeItem(at: old)
        }
    }
}
