import ActivityKit
import UIKit
import UserNotifications
import WebKit

/// Uygulamanin govdesi: web uygulamasinin (Web/index.html) bire bir kopyasini
/// tam ekran WKWebView'da calistirir ve native ozelliklere kopru kurar.
@MainActor
final class WebViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    static weak var current: WebViewController?

    private var webView: WKWebView!
    private var lang = "tr"
    private static let background = UIColor(red: 6 / 255, green: 7 / 255, blue: 8 / 255, alpha: 1)

    override func loadView() {
        let config = WKWebViewConfiguration()
        // Sabit bir adres (antreman://app) — localStorage her acilista ayni yerde kalsin.
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = WKUserContentController()
        controller.add(WeakScriptHandler(self), name: "antreman")
        controller.addUserScript(WKUserScript(source: Self.bootScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = Self.background
        web.scrollView.backgroundColor = Self.background
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false
        web.isInspectable = true
        web.uiDelegate = self
        web.navigationDelegate = self
        webView = web
        view = web
        WebViewController.current = self

        web.load(URLRequest(url: URL(string: "\(BundleSchemeHandler.scheme)://app/index.html")!))
    }

    /// Sayfa yuklenmeden once calisir: native modu ve (varsa) dosyadaki yedegi sayfaya verir.
    private static func bootScript() -> String {
        var js = "window.__NATIVE__ = true;"
        if let backup = Backup.load(),
           let data = try? JSONSerialization.data(withJSONObject: [backup]),
           let literal = String(data: data, encoding: .utf8) {
            js += "window.__nativeBackup = \(literal)[0];"
        }
        return js
    }

    // MARK: - Sayfa -> native

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "restStart":
            Task { await RestController.shared.start(from: body) }
        case "restAdd":
            if let end = body["end"] as? Double {
                Task { await RestController.shared.setEnd(milliseconds: end, notifyWeb: false) }
            }
        case "restStop":
            Task { await RestController.shared.stop(notifyWeb: false) }
        case "restDone":
            Task { await RestController.shared.finished() }
        case "saveState":
            if let json = body["json"] as? String { Backup.save(json) }
        case "share":
            share(name: (body["name"] as? String) ?? "antrenman-yedek.json",
                  text: (body["text"] as? String) ?? "")
        case "haptic":
            let style = body["style"] as? String
            if style == "success" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: style == "medium" ? .medium : .light).impactOccurred()
            }
        case "health":
            // Kestirmeler uygulamasinin her sabah yazdigi saglik.txt (Dosyalar › Antrenman).
            // Ucretsiz imzada HealthKit yetkisi verilmedigi icin Health'e bu yoldan ulasiyoruz.
            send(HealthFile.read())
        case "runShortcut":
            HealthFile.runShortcut()
        case "diag":
            Task { await sendDiagnostics() }
        case "lang":
            if let l = body["lang"] as? String { lang = l }
        default:
            break
        }
    }

    // MARK: - Teshis (Ayarlar › iOS durumu)

    private func sendDiagnostics() async {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        let plugins = Bundle.main.builtInPlugInsURL
        let widgetURL = plugins?.appendingPathComponent("AntremanWidget.appex")
        let widgetBundle = widgetURL.flatMap { Bundle(url: $0) }
        let pluginList = (try? FileManager.default.contentsOfDirectory(atPath: plugins?.path ?? ""))?.joined(separator: ", ") ?? "yok"
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let notif: String
        switch settings.authorizationStatus {
        case .authorized: notif = "izin var"
        case .denied: notif = "REDDEDİLMİŞ"
        case .notDetermined: notif = "henüz sorulmadı"
        case .provisional: notif = "geçici"
        case .ephemeral: notif = "geçici"
        @unknown default: notif = "bilinmiyor"
        }
        let auth = ActivityAuthorizationInfo()
        send([
            "type": "diag",
            "rows": [
                ["iOS", UIDevice.current.systemVersion],
                ["Uygulama sürümü", version],
                ["Uygulama kimliği", Bundle.main.bundleIdentifier ?? "?"],
                ["Eklentiler (PlugIns)", pluginList],
                ["Widget kimliği", widgetBundle?.bundleIdentifier ?? "YOK — eklenti yüklenmemiş"],
                ["Live Activities izni", auth.areActivitiesEnabled ? "açık" : "KAPALI"],
                ["Aktif Live Activity", String(Activity<RestAttributes>.activities.count)],
                ["Son Live Activity denemesi", RestController.shared.lastActivityResult],
                ["Bildirim izni", notif],
                ["Kestirme dosyası", HealthFile.status()],
            ],
        ])
    }

    // MARK: - Native -> sayfa

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__fromNative && window.__fromNative(\(json));", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Uygulama mola sirasinda kapanip acildiysa sayaci geri getir.
        Task { await RestController.shared.appBecameActive() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    /// Dis baglantilar (http/https) Safari'de acilsin, uygulamanin icinde degil.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - Yedek paylasma (Dosyalar'a kaydet, AirDrop...)

    private func share(name: String, text: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        topPresenter().present(sheet, animated: true)
    }

    // MARK: - alert / confirm / prompt (WKWebView bunlari kendisi gostermiyor)

    private var okText: String { ["en": "OK", "fi": "OK"][lang] ?? "Tamam" }
    private var cancelText: String { ["en": "Cancel", "fi": "Peruuta"][lang] ?? "İptal" }

    private func topPresenter() -> UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard view.window != nil else { completionHandler(); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: okText, style: .default) { _ in completionHandler() })
        topPresenter().present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard view.window != nil else { completionHandler(false); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: cancelText, style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: okText, style: .default) { _ in completionHandler(true) })
        topPresenter().present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard view.window != nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = defaultText
            field.keyboardType = .decimalPad
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: cancelText, style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: okText, style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        topPresenter().present(alert, animated: true)
    }
}

/// WKUserContentController mesaj alicisini guclu tutar; dongu olmasin diye zayif aracı.
@MainActor
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
