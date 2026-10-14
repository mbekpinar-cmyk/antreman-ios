import ActivityKit
import Foundation

/// Mola sayacinin Live Activity verisi. Hem uygulama hem widget eklentisi derliyor.
struct RestAttributes: ActivityAttributes {
    /// Ekrandaki sabit yazilar — uygulamanin secili dilinden (TR/EN/FI) geliyor.
    struct Labels: Codable, Hashable {
        var rest: String
        var done: String
        var add: String
        var end: String

        static let tr = Labels(rest: "Dinlenme", done: "Mola bitti", add: "+30 sn", end: "Bitir")
    }

    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var exercise: String
    }

    var workout: String
    var labels: Labels
}

extension RestAttributes.ContentState {
    /// Text(timerInterval:) kapali aralik ister; bitis baslangictan once olamaz.
    var range: ClosedRange<Date> {
        start...max(start.addingTimeInterval(1), end)
    }
}
