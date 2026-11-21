import AppKit

/// Detects a double tap of the ⌘ key on its own (press–release, press–release
/// with no other key, modifier or click in between).
///
/// A modifier tap types nothing, so unlike a double Space it can't scroll the
/// page or overwrite the selected text in the app you're reading.
/// Global key monitors need the Accessibility permission.
final class DoubleCommandTap {
    private let action: () -> Void
    private var monitors: [Any] = []

    private var commandDownAt: TimeInterval?   // ⌘ is currently held, since…
    private var lastTapAt: TimeInterval = 0    // end of the previous clean tap

    /// A tap is a press shorter than this…
    private let maxPress: TimeInterval = 0.35
    /// …and two taps count as a double tap when this close together.
    private let maxGap: TimeInterval = 0.40

    init(action: @escaping () -> Void) { self.action = action }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Events going to other apps…
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) {
            monitors.append(m)
        }
        // …and to MiniDict itself, so ⌘⌘ also closes the panel.
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func reset() { commandDownAt = nil; lastTapAt = 0 }

    private func handle(_ e: NSEvent) {
        guard e.type == .flagsChanged else { reset(); return }   // any key or click breaks the sequence

        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let now = e.timestamp

        if mods == .command, commandDownAt == nil {
            commandDownAt = now                                   // ⌘ pressed alone
        } else if mods.isEmpty, let down = commandDownAt {
            commandDownAt = nil                                   // ⌘ released
            guard now - down < maxPress else { lastTapAt = 0; return }
            if lastTapAt > 0, now - lastTapAt < maxGap {
                lastTapAt = 0
                action()
            } else {
                lastTapAt = now
            }
        } else {
            reset()                                               // ⌘ with ⇧/⌥/⌃ etc.
        }
    }
}
