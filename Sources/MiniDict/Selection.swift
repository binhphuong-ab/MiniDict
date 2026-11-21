import AppKit
import ApplicationServices

/// Reads the text the user has selected in the frontmost app.
/// 1. Accessibility API (kAXSelectedTextAttribute) — silent, no clipboard touch.
/// 2. Fallback: synthesize ⌘C, read the pasteboard, then restore it.
/// Both need the Accessibility permission; without it we just return nil.
enum Selection {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func grab(completion: @escaping (String?) -> Void) {
        guard isTrusted else { completion(nil); return }
        if let s = axSelectedText(), let c = clean(s) { completion(c); return }
        copyViaPasteboard { completion($0.flatMap(clean)) }
    }

    /// Only short, single-line selections are treated as a lookup query —
    /// an accidental paragraph selection should not trigger a search.
    static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'“”‘’()[]{}«»…"))
        guard !t.isEmpty, t.count <= 60, !t.contains("\n") else { return nil }
        return t
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }

    private static func copyViaPasteboard(_ done: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        }
        let before = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let kC: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: src, virtualKey: kC, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: kC, keyDown: false)
        down?.flags = .maskCommand   // explicit flags so a held ⌥ from the hotkey doesn't leak in
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        var tries = 0
        func poll() {
            if pb.changeCount != before {
                let s = pb.string(forType: .string)
                pb.clearContents()
                if !saved.isEmpty { pb.writeObjects(saved) }
                done(s)
            } else if tries < 12 {
                tries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: poll)
            } else {
                done(nil)   // nothing selected: the app didn't touch the clipboard
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: poll)
    }
}
