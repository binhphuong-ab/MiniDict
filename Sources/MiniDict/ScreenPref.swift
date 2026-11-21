import AppKit

/// Which display the lookup panel opens on.
/// Stored as the display's name ("Built-in Retina Display") or "mouse".
/// Names survive unplug/replug; CGDirectDisplayIDs don't always.
enum ScreenPref {
    private static let key = "displayChoice"
    static let followMouse = "mouse"

    static var choice: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Default with no choice made (or the chosen display unplugged):
    /// the extended display, i.e. the first one without the menu bar.
    static func target() -> NSScreen {
        let screens = NSScreen.screens
        if choice == followMouse {
            let p = NSEvent.mouseLocation
            if let s = screens.first(where: { NSMouseInRect(p, $0.frame, false) }) { return s }
        }
        if let name = choice, let s = screens.first(where: { $0.localizedName == name }) { return s }
        return screens.count > 1 ? screens[1] : (screens.first ?? NSScreen.main!)
    }

    static func isMain(_ s: NSScreen) -> Bool { s == NSScreen.screens.first }
}
