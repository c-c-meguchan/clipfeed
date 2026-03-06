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
        let placeholder = AnyView(Text(L("loading", fallback: "Loading…")))
        let hosting = NSHostingController(rootView: placeholder)
        self.hostingController = hosting
        let window = NSWindow(contentViewController: hosting)

        window.title = "ClipFeed — \(L("settings", fallback: "Settings"))"
        window.setContentSize(NSSize(width: 520, height: 380))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.level = Self.windowLevelAbovePopover

        super.init(window: window)
        NotificationCenter.default.addObserver(
            forName: AppSettings.appLanguageDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.window?.title = "ClipFeed — \(L("settings", fallback: "Settings"))"
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 設定ウィンドウを前面に表示する。clipboardViewModel を渡すと「履歴を全削除」などが動作する。
    func show(clipboardViewModel: ClipboardViewModel? = nil) {
        let observer = AppLanguageObserver.shared
        if let vm = clipboardViewModel {
            hostingController.rootView = AnyView(
                AccentTintView {
                    SettingsView()
                        .environmentObject(vm)
                        .environmentObject(observer)
                        .id(observer.currentLanguage + "-\(observer.languageChangeSeed)")
                }
            )
        }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
