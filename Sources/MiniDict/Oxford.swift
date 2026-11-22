import AppKit
import WebKit

/// Thin client for the oxfordlearnersdictionaries.com website.
/// There is no public JSON API for entries; we load the HTML page and let the
/// lookup web view extract `#entryContent`.
///
/// Pages are loaded in a real WebKit view (stock Safari engine and user agent,
/// app-wide default cookie store) instead of URLSession. Oxford sits behind
/// Cloudflare's browser check, which a plain HTTP client cannot pass; WebKit runs
/// the check like any browser does. If the check ever needs a human, the page is
/// shown in a small window so the user can complete it themselves.
enum Oxford {
    static let host = "www.oxfordlearnersdictionaries.com"
    static let base = URL(string: "https://\(host)/")!

    enum Failure: LocalizedError {
        case badURL, http(Int), verification, cancelled
        var errorDescription: String? {
            switch self {
            case .badURL: return "URL không hợp lệ"
            case .http(let code): return "Oxford trả về lỗi HTTP \(code)"
            case .verification: return "Chưa qua bước xác minh của Oxford"
            case .cancelled: return "Đã huỷ"
            }
        }
    }

    static func isOxford(_ url: URL) -> Bool {
        url.scheme == "https" && (url.host == host || url.host == "oxfordlearnersdictionaries.com")
    }

    @MainActor static func suggest(_ q: String) async throws -> [String] {
        try await OxfordBrowser.shared.suggest(q)
    }

    /// Fetches a dictionary page, following redirects (search/direct → definition or spellcheck).
    @MainActor static func page(_ url: URL) async throws -> (url: URL, html: String) {
        guard isOxford(url) else { throw Failure.badURL }
        return try await OxfordBrowser.shared.page(url)
    }

    /// Loads the home page in the background so the browser check is done
    /// before the first lookup and suggestions work right away.
    @MainActor static func warmUp() { OxfordBrowser.shared.warmUp() }
}

@MainActor
final class OxfordBrowser: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = OxfordBrowser()

    private let webView: WKWebView
    private let window: NSWindow
    private var load: Load?
    private var ready = false          // a real Oxford page is loaded (check passed)

    /// One in-flight page load. A newer load supersedes it (the UI ignores stale replies).
    @MainActor private final class Load {
        let url: URL
        let interactive: Bool
        var continuation: CheckedContinuation<(url: URL, html: String), Error>?
        var status = 0
        var challenged = false
        var promptTimer: Timer?
        var giveUpTimer: Timer?
        init(url: URL, interactive: Bool) { self.url = url; self.interactive = interactive }
    }

    private override init() {
        let config = WKWebViewConfiguration()           // default data store: cookies persist
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 640), configuration: config)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        window.title = "Oxford: xác minh trình duyệt"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    // MARK: API

    func warmUp() {
        guard load == nil, !ready else { return }
        Task { _ = try? await start(Oxford.base, interactive: false) }
    }

    func page(_ url: URL) async throws -> (url: URL, html: String) {
        try await start(url, interactive: true)
    }

    func suggest(_ q: String) async throws -> [String] {
        // fetch() from inside an Oxford page: same origin, same cookies as the browser check.
        guard ready, load == nil, let cur = webView.url, Oxford.isOxford(cur) else { return [] }
        let js = """
            const u = new URL('/autocomplete/english/', location.origin);
            u.searchParams.set('q', q);
            u.searchParams.set('contentType', 'application/json; charset=utf-8');
            const r = await fetch(u, { credentials: 'include' });
            if (!r.ok) return [];
            const j = await r.json();
            return (j.results || []).map(x => x.searchtext);
            """
        let r = try await webView.callAsyncJavaScript(js, arguments: ["q": q], contentWorld: .defaultClient)
        return (r as? [Any])?.compactMap { $0 as? String } ?? []
    }

    // MARK: Loading

    private func start(_ url: URL, interactive: Bool) async throws -> (url: URL, html: String) {
        finish(load, .failure(Oxford.Failure.cancelled))
        let l = Load(url: url, interactive: interactive)
        load = l
        return try await withCheckedThrowingContinuation { c in
            l.continuation = c
            var req = URLRequest(url: url)
            if url.path.contains("/search/") { req.cachePolicy = .reloadIgnoringLocalCacheData }
            webView.load(req)
        }
    }

    private func finish(_ l: Load?, _ result: Result<(url: URL, html: String), Error>) {
        guard let l, let c = l.continuation else { return }
        l.continuation = nil
        l.promptTimer?.invalidate(); l.giveUpTimer?.invalidate()
        if load === l { load = nil }
        if window.isVisible { window.orderOut(nil) }
        c.resume(with: result)
    }

    /// The check is still showing after a few seconds: let the user see it.
    private func promptUser(_ l: Load) {
        guard load === l, l.continuation != nil else { return }
        guard l.interactive else { finish(l, .failure(Oxford.Failure.verification)); return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        l.giveUpTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(l, .failure(Oxford.Failure.verification)) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let l = load, l.challenged { finish(l, .failure(Oxford.Failure.verification)) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let h = response.response as? HTTPURLResponse, let l = load {
            l.status = h.statusCode
            l.challenged = h.value(forHTTPHeaderField: "cf-mitigated") != nil
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let l = load else { return }
        if l.challenged {
            ready = false
            // Cloudflare's page usually clears itself and reloads within a second or two.
            if l.promptTimer == nil {
                l.promptTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.promptUser(l) }
                }
            }
            return
        }
        let status = l.status
        guard status == 200 || status == 404 else {
            finish(l, .failure(Oxford.Failure.http(status))); return
        }
        ready = true
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] html, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let html = html as? String {
                    let final = webView.url ?? l.url
                    NSLog("MiniDict: \(status) \(l.url.path) -> \(final.path) (\(html.utf8.count) bytes)")
                    self.finish(l, .success((final, html)))
                } else {
                    self.finish(l, .failure(error ?? Oxford.Failure.http(0)))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        failed(error)
    }

    private func failed(_ error: Error) {
        // Superseded navigations report NSURLErrorCancelled; start() already settled those.
        if (error as NSError).code == NSURLErrorCancelled { return }
        finish(load, .failure(error))
    }
}
