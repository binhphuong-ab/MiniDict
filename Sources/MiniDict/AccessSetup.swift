import AppKit

/// Walks the user through granting macOS Accessibility (needed to read the
/// selected text and to hear ⌘⌘), notices the moment it is granted, and says so.
@MainActor
final class AccessSetup {
    static let shared = AccessSetup()

    /// Called once the permission flips from off to on (e.g. to install the ⌘⌘ monitor).
    var onGranted: (() -> Void)?

    private var timer: Timer?
    private var wasTrusted = Selection.isTrusted

    /// First launch without the permission: explain once, unprompted.
    func introduceIfNeeded() {
        guard !Selection.isTrusted, !Prefs.accessIntroShown else { return }
        Prefs.accessIntroShown = true
        start()
    }

    /// Explain → system prompt → open System Settings → wait for the grant.
    /// `explain: false` skips the explanation (the user already clicked a "set up" button).
    func start(explain: Bool = true) {
        if Selection.isTrusted { confirm(); return }
        if explain {
            let a = NSAlert()
            a.messageText = "Bật tra chữ đang bôi đen"
            a.informativeText = """
                Để đọc chữ bạn bôi đen và nhận phím ⌘⌘, MiniDict cần quyền Trợ năng (Accessibility) của macOS.

                1. Bấm "Mở Cài đặt".
                2. Trong Quyền riêng tư & Bảo mật ▸ Trợ năng, bật công tắc cạnh MiniDict. macOS có thể hỏi mật khẩu hoặc Touch ID.
                3. MiniDict tự nhận ra và báo ngay khi quyền đã bật.

                Đã bật mà MiniDict vẫn không nhận? Chọn MiniDict trong danh sách, bấm "−" để xoá, rồi bấm lại "Bật tra chữ đang bôi đen…" trong menu.
                """
            a.addButton(withTitle: "Mở Cài đặt")
            a.addButton(withTitle: "Để sau")
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        Selection.requestTrust()
        Selection.openSettings()
        watch()
    }

    /// Polls until the permission is granted. Cheap (one syscall), and macOS has
    /// no notification for this. Runs from launch while the permission is missing,
    /// so a grant made any way at all is noticed.
    func watch() {
        guard timer == nil, !Selection.isTrusted else { return }
        wasTrusted = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard Selection.isTrusted, !wasTrusted else { return }
        wasTrusted = true
        timer?.invalidate(); timer = nil
        confirm()
    }

    private func confirm() {
        onGranted?()
        let a = NSAlert()
        a.messageText = "Đã bật tra chữ đang bôi đen ✓"
        a.informativeText = "Bôi đen một chữ ở bất kỳ app nào rồi nhấn đúp ⌘ Command để tra ngay."
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
