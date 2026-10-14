import SwiftUI
import UserNotifications

@main
struct AntremanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WebContainer()
                .ignoresSafeArea()
                .background(Color(red: 6 / 255, green: 7 / 255, blue: 8 / 255).ignoresSafeArea())
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await RestController.shared.appBecameActive() }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Mola bitis bildirimi icin izin. Telefon kilitliyken bildirim Apple Watch'a gecer.
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    /// Uygulama acikken de bildirim gorunsun ve ses calsin.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {}
}
