import AppIntents
import Foundation

// Live Activity / Dynamic Island butonlari.
// LiveActivityIntent'leri sistem UYGULAMANIN surecinde calistirir (uygulama
// kapaliysa arka planda acar). Widget eklentisi sadece butonu cizmek icin
// bu tipleri derler; perform() govdesi orada bos kalir.

struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Molaya 30 sn ekle"

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await RestController.shared.add(seconds: 30)
        #endif
        return .result()
    }
}

struct EndRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Molayi bitir"

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await RestController.shared.stop(notifyWeb: true)
        #endif
        return .result()
    }
}
