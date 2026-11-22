import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private lazy var panel = LookupPanelController()
    private var hotKey: HotKey?                       // ⌥Space (optional)
    private lazy var doubleCommand = DoubleCommandTap { [weak self] in self?.hotKeyPressed() }
    private var trustTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        // minidict://lookup?q=word — lets Shortcuts, PopClip, Raycast… open a lookup.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let c = URLComponents(string: s) else { return }
        if c.host == "setup-selection" { enableSelection(); return }   // minidict://setup-selection
        let q = c.queryItems?.first { $0.name == "q" }?.value
        panel.show(query: q?.isEmpty == false ? q : nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = panel   // build the web view now so the first lookup is instant

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.book.closed",
                                   accessibilityDescription: "MiniDict")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        applyTriggers()
        Oxford.warmUp()
    }

    // MARK: triggers

    private func applyTriggers() {
        // ⌥Space — Carbon hotkey, works without Accessibility.
        if Prefs.optionSpace, hotKey == nil {
            hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
                self?.hotKeyPressed()
            }
        } else if !Prefs.optionSpace {
            hotKey = nil
        }

        // ⌘⌘ — global key monitor, needs Accessibility. A monitor installed before
        // the permission is granted never starts receiving events, so wait for
        // the grant and install it then.
        trustTimer?.invalidate(); trustTimer = nil
        if Prefs.doubleCommand {
            if Selection.isTrusted {
                if !doubleCommand.isRunning { doubleCommand.start() }
            } else {
                doubleCommand.stop()
                trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    if Selection.isTrusted { self?.applyTriggers() }
                }
            }
        } else {
            doubleCommand.stop()
        }
    }

    private func hotKeyPressed() {
        if panel.isShownAndKey { panel.hide(); return }
        // Without Accessibility we can't read the selection: say so instead of
        // silently opening an empty box.
        guard Selection.isTrusted else {
            panel.show(query: nil)
            panel.showNotice("noAccess")
            return
        }
        // Read the selection *before* the panel takes keyboard focus.
        Selection.grab { [weak self] text in self?.panel.show(query: text) }
    }

    // MARK: menu actions

    @objc private func openPanel() { panel.show(query: nil) }
    @objc private func openStats() { panel.showView("stats") }
    @objc private func openFixGuide() {
        NSWorkspace.shared.open(URL(string: "https://github.com/binhphuong-ab/MiniDict/blob/main/TECHNICAL.md")!)
    }
    @objc private func openSaved() { panel.showView("saved") }
    @objc private func toggleCelebrate() { Prefs.celebrate.toggle(); panel.pushPrefs() }
    @objc private func enableSelection() {
        Selection.requestTrust()
        Selection.openSettings()
    }
    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled) }

    @objc private func toggleDoubleCommand() {
        Prefs.doubleCommand.toggle()
        if !Prefs.doubleCommand && !Prefs.optionSpace { Prefs.optionSpace = true }   // never leave no shortcut
        applyTriggers()
    }

    @objc private func toggleOptionSpace() {
        Prefs.optionSpace.toggle()
        if !Prefs.doubleCommand && !Prefs.optionSpace { Prefs.doubleCommand = true }
        applyTriggers()
    }

    @objc private func chooseAutoplay(_ sender: NSMenuItem) {
        Prefs.autoplay = sender.representedObject as? String ?? "off"
        panel.pushPrefs()
    }

    @objc private func chooseTheme(_ sender: NSMenuItem) {
        Prefs.theme = sender.representedObject as? String ?? "system"
        panel.pushPrefs()
    }

    @objc private func chooseScreen(_ sender: NSMenuItem) {
        ScreenPref.choice = sender.representedObject as? String
        panel.hide()
        panel.show(query: nil)          // show it right away on the chosen display
    }

    // MARK: menu

    private func item(_ title: String, _ action: Selector?, on: Bool = false, enabled: Bool = true,
                      represented: Any? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.state = on ? .on : .off
        mi.isEnabled = enabled
        mi.representedObject = represented
        return mi
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach(sub.addItem)
        mi.submenu = sub
        return mi
    }

    private var shortcutLabel: String {
        [Prefs.doubleCommand ? "⌘⌘" : nil, Prefs.optionSpace ? "⌥Space" : nil]
            .compactMap { $0 }.joined(separator: " / ")
    }

    private func triggerMenu() -> NSMenuItem {
        var items = [
            item("Nhấn đúp ⌘ Command", #selector(toggleDoubleCommand), on: Prefs.doubleCommand),
            item("⌥ Option + Space", #selector(toggleOptionSpace), on: Prefs.optionSpace),
        ]
        if Prefs.doubleCommand && !Selection.isTrusted {
            items.append(.separator())
            items.append(item("⌘⌘ cần quyền Trợ năng", nil, enabled: false))
        }
        if Prefs.optionSpace && hotKey?.isRegistered == false {
            items.append(item("⚠︎ ⌥Space đang bị app khác chiếm", nil, enabled: false))
        }
        return submenu("Phím tắt", items)
    }

    private func autoplayMenu() -> NSMenuItem {
        let cur = Prefs.autoplay
        return submenu("Tự phát âm khi tra", [
            item("Tắt", #selector(chooseAutoplay(_:)), on: cur == "off", represented: "off"),
            item("Giọng Anh (UK)", #selector(chooseAutoplay(_:)), on: cur == "uk", represented: "uk"),
            item("Giọng Mỹ (US)", #selector(chooseAutoplay(_:)), on: cur == "us", represented: "us"),
        ])
    }

    private func themeMenu() -> NSMenuItem {
        let cur = Prefs.theme
        let opts: [(String, String)] = [
            ("Theo hệ thống", "system"), ("Sáng", "light"), ("Tối", "dark"), ("Vàng (dịu mắt)", "sepia"),
        ]
        return submenu("Giao diện", opts.map { title, key in
            item(title, #selector(chooseTheme(_:)), on: cur == key, represented: key)
        })
    }

    private func screenMenu() -> NSMenuItem {
        let target = ScreenPref.target()
        let following = ScreenPref.choice == ScreenPref.followMouse
        var items = NSScreen.screens.map { s in
            item(s.localizedName + (ScreenPref.isMain(s) ? " — chính" : " — phụ"),
                 #selector(chooseScreen(_:)), on: !following && s == target, represented: s.localizedName)
        }
        items.append(.separator())
        items.append(item("Màn hình đang có con trỏ chuột", #selector(chooseScreen(_:)),
                          on: following, represented: ScreenPref.followMouse))
        return submenu("Hiện trên màn hình", items)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if Prefs.oxfordBroken {
            menu.addItem(item("⚠︎ Oxford đã đổi giao diện, MiniDict cần cập nhật", #selector(openFixGuide)))
            menu.addItem(.separator())
        }

        menu.addItem(item("Tra từ…    \(shortcutLabel)", #selector(openPanel)))
        menu.addItem(item("Thống kê & thành tích…", #selector(openStats)))
        menu.addItem(item("Sổ từ đã lưu…", #selector(openSaved)))
        menu.addItem(.separator())

        menu.addItem(triggerMenu())
        menu.addItem(autoplayMenu())
        menu.addItem(themeMenu())
        menu.addItem(item("Ăn mừng khi đạt mốc", #selector(toggleCelebrate), on: Prefs.celebrate))
        if NSScreen.screens.count > 1 { menu.addItem(screenMenu()) }
        menu.addItem(.separator())

        if Selection.isTrusted {
            menu.addItem(item("Tra chữ đang bôi đen: đã bật", nil, on: true, enabled: false))
        } else {
            menu.addItem(item("Bật tra chữ đang bôi đen…", #selector(enableSelection)))
        }
        menu.addItem(item("Mở cùng macOS", #selector(toggleLogin), on: LoginItem.isEnabled))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Thoát MiniDict", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
