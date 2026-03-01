import AppKit
import SwiftUI

/// 設定ウィンドウのシングルトン。⌘, またはメニュー「設定…」で開く。
/// ポップオーバー（.popUpMenu = 101）より前面に出すため、ウィンドウレベルを 200 にしている。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    /// ポップオーバーより前面に表示するためのレベル（popUpMenu が 101 のためそれより大きい値）
    private static let windowLevelAbovePopover = NSWindow.Level(rawValue: 200)

    private let hostingController: NSHostingController<AnyView>

    private init() {
        let placeholder = AnyView(Text("読み込み中…"))
        let hosting = NSHostingController(rootView: placeholder)
        self.hostingController = hosting
        let window = NSWindow(contentViewController: hosting)

        window.title = "ClipFeed — 設定"
        window.setContentSize(NSSize(width: 520, height: 380))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.level = Self.windowLevelAbovePopover

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 設定ウィンドウを前面に表示する。clipboardViewModel を渡すと「履歴を全削除」などが動作する。
    func show(clipboardViewModel: ClipboardViewModel? = nil) {
        if let vm = clipboardViewModel {
            hostingController.rootView = AnyView(
                SettingsView()
                    .environmentObject(vm)
            )
        }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
