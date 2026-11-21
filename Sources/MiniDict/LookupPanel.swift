import AppKit
import WebKit

/// A floating, *non-activating* panel: it takes keyboard focus but the app you
/// are reading in stays the active app, so closing the panel drops you straight
/// back where you were — the same trick Spotlight uses.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Transparent strip over the top of the web view so the panel can be dragged.
private final class DragStrip: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override var mouseDownCanMoveWindow: Bool { true }
}

final class LookupPanelController: NSObject, NSWindowDelegate, WKNavigationDelegate,
                                   WKScriptMessageHandlerWithReply {
    let panel: FloatingPanel
    private let webView: WKWebView
    private var uiReady = false
    private var pendingQuery: String?? = nil   // .some(nil) = "open with empty box"
    private var pendingView: String?
    private var pinned = false

    override init() {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "native")

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 340, height: 260)
        panel.delegate = self
        panel.isReleasedWhenClosed = false

        let blur = NSVisualEffectView()
        blur.material = .windowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        panel.contentView = blur

        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) { webView.isInspectable = true }   // Safari ▸ Develop for debugging
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(webView)

        let strip = DragStrip()
        strip.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(strip)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            webView.topAnchor.constraint(equalTo: blur.topAnchor),
            webView.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -64), // leave pin/open buttons clickable
            strip.topAnchor.constraint(equalTo: blur.topAnchor),
            strip.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Keep the size the user resized to in earlier versions; the position is
        // chosen per display at show time (see position(on:)).
        _ = panel.setFrameUsingName("MiniDictPanel")

        // Base URL = the dictionary site, so relative links and media in the
        // extracted entry HTML resolve exactly as on the website.
        webView.loadHTMLString(Self.loadUI(), baseURL: Oxford.base)
        applyAppearance()
    }

    /// Native side of the theme: scrollbars, the backdrop shown before the page
    /// paints, and what the web view reports as prefers-color-scheme.
    private func applyAppearance() {
        switch Prefs.theme {
        case "light", "sepia": panel.appearance = NSAppearance(named: .aqua)
        case "dark":           panel.appearance = NSAppearance(named: .darkAqua)
        default:               panel.appearance = nil          // follow macOS
        }
    }

    private static func loadUI() -> String {
        if let url = Bundle.main.url(forResource: "ui", withExtension: "html"),
           let s = try? String(contentsOf: url) { return s }
        // `swift run` during development: read straight from the source tree.
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources/ui.html")
        return (try? String(contentsOf: dev)) ?? "<p>ui.html missing</p>"
    }

    // MARK: placement — one remembered frame per display

    private func frameKey(_ screen: NSScreen) -> String { "frame." + screen.localizedName }

    private func position(on screen: NSScreen) {
        let vf = screen.visibleFrame
        let f = panel.frame
        if vf.contains(NSPoint(x: f.midX, y: f.midY)) { return }          // already there
        if let s = UserDefaults.standard.string(forKey: frameKey(screen)) {
            let saved = NSRectFromString(s)
            let overlap = vf.intersection(saved)
            if overlap.width * overlap.height >= saved.width * saved.height * 0.8 {
                panel.setFrame(saved, display: false); return
            }
        }
        // First time on this display: top-centre, clamped to fit.
        let w = min(f.width, vf.width - 40), h = min(f.height, vf.height - 40)
        panel.setFrame(NSRect(x: vf.midX - w / 2, y: vf.maxY - h - vf.height * 0.10, width: w, height: h),
                       display: false)
    }

    private func saveFrame() {
        guard let screen = panel.screen else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey(screen))
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { saveFrame() }

    // MARK: show / hide

    var isShownAndKey: Bool { panel.isVisible && panel.isKeyWindow }

    func show(query: String?) {
        if !panel.isVisible { position(on: ScreenPref.target()) }   // a pinned panel stays put
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
        guard uiReady else { pendingQuery = .some(query); return }
        send(query)
    }

    private func send(_ query: String?) {
        let arg: String
        if let query, let data = try? JSONSerialization.data(withJSONObject: [query]),
           let json = String(data: data, encoding: .utf8) {
            arg = String(json.dropFirst().dropLast())
        } else { arg = "null" }
        webView.evaluateJavaScript("MiniDict.open(\(arg))") { _, error in
            if let error { NSLog("MiniDict: JS open failed: \(error)") }
        }
    }

    func hide() { panel.orderOut(nil) }

    /// Open the panel on one of the UI's own pages ("stats", "saved", "history").
    func showView(_ name: String) {
        show(query: nil)
        guard uiReady else { pendingView = name; return }
        webView.evaluateJavaScript("MiniDict.view('\(name)')")
    }

    /// Re-send settings after the user changes them in the menu.
    func pushPrefs() {
        applyAppearance()
        guard uiReady, let data = try? JSONSerialization.data(withJSONObject: Prefs.forUI),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("MiniDict.setPrefs(\(json))")
    }

    func showNotice(_ kind: String) {
        guard uiReady else { return }
        webView.evaluateJavaScript("MiniDict.notice('\(kind)')")
    }

    func windowDidResignKey(_ notification: Notification) {
        if !pinned { hide() }
    }

    // MARK: JS bridge

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            replyHandler(nil, "bad message"); return
        }
        switch cmd {
        case "ready":
            uiReady = true
            replyHandler(Prefs.forUI, nil)
            if let q = pendingQuery { pendingQuery = nil; send(q) }
            if let v = pendingView { pendingView = nil; webView.evaluateJavaScript("MiniDict.view('\(v)')") }

        case "health":
            Prefs.oxfordBroken = !(body["ok"] as? Bool ?? true)
            replyHandler(nil, nil)

        case "loadData":
            replyHandler(Store.load(), nil)

        case "saveData":
            if let json = body["json"] as? String { Store.save(json) }
            replyHandler(nil, nil)

        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
            replyHandler(nil, nil)

        case "suggest":
            let q = body["q"] as? String ?? ""
            Task { @MainActor in
                do { replyHandler(try await Oxford.suggest(q), nil) }
                catch { replyHandler(nil, error.localizedDescription) }
            }

        case "page":
            guard let s = body["url"] as? String, let url = URL(string: s) else {
                replyHandler(nil, "bad url"); return
            }
            Task { @MainActor in
                do {
                    let r = try await Oxford.page(url)
                    replyHandler(["url": r.url.absoluteString, "html": r.html], nil)
                } catch { replyHandler(nil, error.localizedDescription) }
            }

        case "open":
            if let s = body["url"] as? String, let url = URL(string: s),
               url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            replyHandler(nil, nil)

        case "pin":
            pinned = body["on"] as? Bool ?? false
            replyHandler(nil, nil)

        case "setupSelection":
            Selection.requestTrust()
            Selection.openSettings()
            replyHandler(nil, nil)

        case "hide":
            hide()
            replyHandler(nil, nil)

        default:
            replyHandler(nil, "unknown cmd")
        }
    }

    // Links are handled in JS; anything that still tries to navigate opens in the browser.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("MiniDict: UI load failed: \(error)")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
