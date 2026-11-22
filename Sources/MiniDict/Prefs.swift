import Foundation

/// User settings shown in the menu bar menu.
enum Prefs {
    private static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "trigger.doubleCommand": true,
            "trigger.optionSpace": false,
            "autoplay": "uk",
            "theme": "system",
            "celebrate": true,
        ])
    }

    /// "system", "light", "dark" or "sepia" (the yellow reading theme).
    static var theme: String {
        get { d.string(forKey: "theme") ?? "system" }
        set { d.set(newValue, forKey: "theme") }
    }

    static var doubleCommand: Bool {
        get { d.bool(forKey: "trigger.doubleCommand") }
        set { d.set(newValue, forKey: "trigger.doubleCommand") }
    }

    static var optionSpace: Bool {
        get { d.bool(forKey: "trigger.optionSpace") }
        set { d.set(newValue, forKey: "trigger.optionSpace") }
    }

    /// "off", "uk" or "us": pronunciation played automatically after each lookup.
    static var autoplay: String {
        get { d.string(forKey: "autoplay") ?? "uk" }
        set { d.set(newValue, forKey: "autoplay") }
    }

    /// Confetti + a toast at the daily milestones (5, 25, 50, 100 words).
    static var celebrate: Bool {
        get { d.bool(forKey: "celebrate") }
        set { d.set(newValue, forKey: "celebrate") }
    }

    /// Set when an Oxford entry page no longer has the HTML MiniDict reads
    /// (Oxford redesigned its site); cleared by the next page that parses fine.
    static var oxfordBroken: Bool {
        get { d.bool(forKey: "oxford.broken") }
        set { d.set(newValue, forKey: "oxford.broken") }
    }

    /// The one-time "how to turn on Accessibility" explanation has been shown.
    static var accessIntroShown: Bool {
        get { d.bool(forKey: "access.introShown") }
        set { d.set(newValue, forKey: "access.introShown") }
    }

    /// What the web UI needs to know.
    static var forUI: [String: Any] { ["autoplay": autoplay, "theme": theme, "celebrate": celebrate] }
}
