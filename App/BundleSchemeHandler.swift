import Foundation
import UniformTypeIdentifiers
import WebKit

/// antreman://app/... isteklerini uygulama paketindeki Web klasorunden karsilar.
/// file:// yerine sabit bir adres kullanmak localStorage'in kalici olmasi icin.
@MainActor
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "antreman"

    private let root: URL = {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Web", isDirectory: true)
    }()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL

        // Paket disina cikilmasin.
        guard file.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        var mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        if mime.hasPrefix("text/") || mime == "application/javascript" || mime == "application/json" {
            mime += "; charset=utf-8"
        }
        let headers = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-store",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            urlSchemeTask.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
