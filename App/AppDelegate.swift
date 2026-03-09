import AppKit
import SwiftUI
import Carbon
import Combine

// ANSI キーコードと数字（1〜9）のマッピング
// 数字キーのキーコードは連番ではないため明示的に定義する
private let kNumberKeyCodes: [Int64: Int] = [
    18: 1, // kVK_ANSI_1
    19: 2, // kVK_ANSI_2
    20: 3, // kVK_ANSI_3
    21: 4, // kVK_ANSI_4
    23: 5, // kVK_ANSI_5
    22: 6, // kVK_ANSI_6
    26: 7, // kVK_ANSI_7
    28: 8, // kVK_ANSI_8
    25: 9  // kVK_ANSI_9
]

// Carbon ホットキーコールバック（キャプチャなしのファイルスコープ関数として定義）
private func carbonHotKeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    if hotKeyID.id == 1 {
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
            LogCapture.record("Global shortcut detected")
            delegate.togglePopover()
        }
    }
    return noErr
}

// ---

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var clipboardViewModel: ClipboardViewModel?
    private var localMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var iconFlashCancellable: AnyCancellable?

    private let keyCodeH: UInt16 = 4 // kVK_ANSI_H

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppSettings.registerDefaults()
        AppSettings.applyAppearance()
        LaunchAtLoginHelper.setEnabled(AppSettings.launchAtLogin)

        clipboardViewModel = ClipboardViewModel()

        guard let clipboardViewModel else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipFeed")
            button.action = #selector(togglePopoverFromButton)
            button.target = self
        }
        statusItem?.menu = nil

        popover = NSPopover()
        popover?.delegate = self
        popover?.contentSize = NSSize(width: 400, height: 600)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: AccentTintView {
                MenuBarView()
                    .environmentObject(clipboardViewModel)
                    .environmentObject(AppLanguageObserver.shared)
            }
        )

        addLocalMonitor()
        registerCarbonHotKey()
        observeAppearanceChanges()
        observeOpenSettings()
        observeClosePopoverAfterReCopy()

        UpdateChecker.shared.checkForUpdates()

        // items.count が増加したとき（新規クリップボード検出時）にアイコンをフラッシュ
        iconFlashCancellable = clipboardViewModel.$items
            .map(\.count)
            .removeDuplicates()
            .dropFirst()            // 起動時の初期値はスキップ
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.flashMenuBarIcon()
            }
    }

    // MARK: - Local Monitor

    /// ポップオーバーが開いてアプリがアクティブなときのキー処理
    /// ⌘⌥⇧H のクローズと ⌘+数字 の再コピーを担当する
    private func addLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let f = event.modifierFlags

            // [診断] ⌘⌥ の組み合わせが来たときのみアプリ状態をログ
            if f.contains(.command) && f.contains(.option) {
                LogCapture.record("[LocalMonitor] ⌘⌥ keyDown — keyCode:\(event.keyCode) isActive:\(NSApp.isActive) popoverShown:\(self.popover?.isShown ?? false)")
            }

            // ⌘⌥⇧H：ポップオーバーを閉じる
            if f.contains(.command) && f.contains(.option) && f.contains(.shift)
                && !f.contains(.control) && event.keyCode == self.keyCodeH {
                DispatchQueue.main.async { self.togglePopover() }
                return nil
            }

            // ⌘⌥ + ← / →：タブ切替
            // NSEvent ローカルモニターは ScrollView 等がイベントを消費する前に発火するため
            // SwiftUI .keyboardShortcut より確実に動作する
            if f.contains(.command) && f.contains(.option) && !f.contains(.shift) {
                if event.keyCode == 123 { // ←
                    self.clipboardViewModel?.switchSourceTab(delta: -1)
                    return nil
                }
                if event.keyCode == 124 { // →
                    self.clipboardViewModel?.switchSourceTab(delta: 1)
                    return nil
                }
            }

            // ⌘⌥ + 数字（1〜9）：OCRコピー（画像アイテムのみ）
            // reCopy より先に判定
            if f.contains(.command) && f.contains(.option) && !f.contains(.shift),
               let number = kNumberKeyCodes[Int64(event.keyCode)] {
                self.ocrCopyByIndex(number - 1)
                return nil
            }

            // ⌘ + 数字（1〜9）：履歴の再コピー（ポップオーバーが開いているときのみ）
            if f.contains(.command) && !f.contains(.option) && !f.contains(.shift),
               let number = kNumberKeyCodes[Int64(event.keyCode)] {
                self.reCopyByIndex(number - 1)
                return nil
            }

            // ⌘,：設定ウィンドウを開く
            if f.contains(.command) && !f.contains(.option) && !f.contains(.shift) && event.keyCode == 43 { // kVK_ANSI_Comma
                self.openSettings()
                return nil
            }

            // Tab: 検索窓とフィードのフォーカスを切り替え
            if !f.contains(.command) && !f.contains(.option) && !f.contains(.shift) && event.keyCode == 48 { // kVK_Tab
                if let vm = self.clipboardViewModel {
                    if vm.focusArea == .search || vm.isSearchFocused {
                        // 検索 → フィード
                        vm.focusArea = .feed
                        vm.ensureFeedFocus()
                    } else {
                        // フィード → 検索
                        vm.focusArea = .search
                    }
                }
                return nil
            }

            // Enter: フィード側にフォーカスがあるときだけフォーカス中アイテムをコピー（検索0件時のクリアはEscに委譲）
            if !f.contains(.command) && !f.contains(.option) && !f.contains(.shift) && event.keyCode == 36 { // kVK_Return
                if let vm = self.clipboardViewModel {
                    if vm.focusArea == .feed, !vm.isSearchFocused {
                        vm.copyFocusedItem()
                        return nil
                    }
                }
            }

            // ⌥ + Enter: フォーカス中アイテムのOCR（画像の場合のみ）
            if f.contains(.option) && !f.contains(.command) && !f.contains(.shift) && event.keyCode == 36 { // kVK_Return
                if let vm = self.clipboardViewModel {
                    if vm.focusArea == .feed, !vm.isSearchFocused {
                        self.ocrCopyFocusedItem()
                        return nil
                    }
                }
            }

            // Esc: 検索中なら検索状態をクリアしてナビに戻る（日本語変換確定とEnterの競合を避ける）
            if !f.contains(.command) && !f.contains(.option) && !f.contains(.shift) && event.keyCode == 53 { // kVK_Escape
                if let vm = self.clipboardViewModel, !vm.searchText.isEmpty {
                    vm.clearSearchAndReturnToNavigation()
                    return nil
                }
            }

            // ↑ / ↓ : フィードにフォーカスがあるときはフォーカス移動（検索テキストありでも Tab でフィードに移れば可）
            if !f.contains(.command) && !f.contains(.option) && !f.contains(.shift),
               let vm = self.clipboardViewModel,
               vm.focusArea == .feed,
               !vm.isSearchFieldActuallyFirstResponder {
                if event.keyCode == 126 { // 上矢印
                    vm.moveFocus(.up)
                    return nil
                }
                if event.keyCode == 125 { // 下矢印
                    vm.moveFocus(.down)
                    return nil
                }
            }

            return event
        }
    }

    // MARK: - Carbon Global Hotkey

    /// Carbon の RegisterEventHotKey で ⌘⌥⇧H をグローバル登録する
    /// パーミッション不要・リビルド後も権限が失効しない
    private func registerCarbonHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = fourCharCode("clph")
        hotKeyID.id = 1

        var eventSpec = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1, &eventSpec,
            selfPtr,
            &hotKeyHandlerRef
        )
        guard installStatus == noErr else {
            LogCapture.record("[AppDelegate] ⚠️ Carbon event handler install failed: \(installStatus)")
            return
        }

        // ⌘⌥⇧H = kVK_ANSI_H(4), cmdKey | optionKey | shiftKey
        let modifiers = UInt32(cmdKey | optionKey | shiftKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            LogCapture.record("[AppDelegate] Carbon hotkey registered ✓")
        } else {
            LogCapture.record("[AppDelegate] ⚠️ Carbon hotkey registration failed: \(registerStatus)")
        }
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.unicodeScalars.prefix(4).reduce(0) { ($0 << 8) + OSType($1.value) }
    }

    // MARK: - Re-copy by Shortcut

    func reCopyByIndex(_ index: Int) {
        guard let popover, popover.isShown else { return }
        guard let vm = clipboardViewModel else { return }
        guard index >= 0, index < vm.shortcutOrderedIDs.count else { return }
        let id = vm.shortcutOrderedIDs[index]
        guard let item = vm.filteredItems.first(where: { $0.id == id }) else { return }
        LogCapture.record("Shortcut re-copy index: \(index)")
        vm.reCopyItem(item)
    }

    func ocrCopyByIndex(_ index: Int) {
        guard let popover, popover.isShown else { return }
        guard let vm = clipboardViewModel else { return }
        guard index >= 0, index < vm.shortcutOrderedIDs.count else { return }
        let id = vm.shortcutOrderedIDs[index]
        guard let item = vm.filteredItems.first(where: { $0.id == id }) else { return }
        guard item.type == .image else { return }
        LogCapture.record("Performing OCR for index \(index)")
        vm.ocrCopy(item)
    }

    /// フォーカス中の画像アイテムに対して ⌥+Enter で呼ばれる。
    /// OCR済みテキストがあればそのままコピー、なければOCRを実行する。
    func ocrCopyFocusedItem() {
        guard let popover, popover.isShown else { return }
        guard let vm = clipboardViewModel else { return }
        guard let id = vm.focusedItemID else { return }
        guard let item = vm.displayedItems.first(where: { $0.id == id }) else { return }
        guard item.type == .image else { return }
        if item.ocrResult != nil {
            vm.copyFocusedItemOCRResult()
        } else {
            LogCapture.record("Performing OCR for focused item")
            vm.ocrCopy(item)
        }
    }

    // MARK: - Popover

    private func applyPopoverAppearance() {
        guard let popover else { return }
        if #available(macOS 12.0, *) {
            popover.appearance = AppSettings.resolvedAppearance()
        }
    }

    private func observeAppearanceChanges() {
        NotificationCenter.default.addObserver(
            forName: AppSettings.appearanceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyPopoverAppearance()
        }
    }

    static let openSettingsNotification = Notification.Name("AppDelegate.openSettings")
    static let closePopoverAfterReCopyNotification = Notification.Name("AppDelegate.closePopoverAfterReCopy")

    private func observeOpenSettings() {
        NotificationCenter.default.addObserver(
            forName: Self.openSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }
    }

    /// 再コピー／OCRコピー後にフラッシュが収まるタイミング（0.5秒後）でポップオーバーを閉じる
    private func observeClosePopoverAfterReCopy() {
        NotificationCenter.default.addObserver(
            forName: Self.closePopoverAfterReCopyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let popover = self.popover, popover.isShown else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(clipboardViewModel: clipboardViewModel)
    }

    @objc private func togglePopoverFromButton() {
        togglePopover()
    }

    func togglePopover() {
        LogCapture.record("Toggle popover")
        guard let popover,
              let statusItem,
              let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            applyPopoverAppearance()
            // 表示前の初回フレームで検索がフォーカスを奪わないよう、先にフィード側に正規化する
            clipboardViewModel?.resetFocusToFeedForPopoverOpen()
            clipboardViewModel?.beginRestoringFocusOnPopoverOpen()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            LogCapture.record("[Popover] shown — isActive:\(NSApp.isActive)")
            // 初回だけ必ずカード側にフォーカスを移す（開いた直後に AppKit が検索にフォーカスしても上書きする）
            resignSearchFieldFromPopoverWindow(after: 0.08, forceResignEvenIfSearchFocused: true)
            // 2回目以降はユーザーが検索をクリックしていたら奪わない
            resignSearchFieldFromPopoverWindow(after: 0.18, forceResignEvenIfSearchFocused: false)
            resignSearchFieldFromPopoverWindow(after: 0.35, forceResignEvenIfSearchFocused: false)
        }
    }

    /// ポップオーバー内容ウィンドウの first responder を外す（検索にフォーカスが残ると矢印キーが効かない）
    /// - Parameters:
    ///   - forceResignEvenIfSearchFocused: true のときはユーザーが検索にフォーカスしていても必ず contentView に移す（開直後のデフォルトをカードにするため）。false のときは検索フォーカス中は奪わない。
    private func resignSearchFieldFromPopoverWindow(after delay: TimeInterval, forceResignEvenIfSearchFocused: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let popover = self.popover, popover.isShown,
                  let contentView = popover.contentViewController?.view else { return }
            if !forceResignEvenIfSearchFocused, self.clipboardViewModel?.isSearchFieldActuallyFirstResponder == true { return }
            let window = contentView.window
            window?.makeFirstResponder(nil)
            window?.makeFirstResponder(contentView)
            self.clipboardViewModel?.ensureFeedFocus()
        }
    }

    // MARK: - NSPopoverDelegate

    /// ポップオーバーが閉じた直後に呼ばれる。onDisappear は NSPopover では呼ばれないことがあるため、ここで必ず状態保存・フォーカス正規化を行う
    func popoverDidClose(_ notification: Notification) {
        clipboardViewModel?.savePopoverCloseState()
    }

    // MARK: - Icon Flash

    /// クリップボード変更検出時にメニューバーアイコンを青くフラッシュし、
    /// 800ms かけてテンプレートアイコンにフェードバックする。
    ///
    /// ポイント:
    ///  - button.image を直接差し替えることで NSStatusBarButton 自身がサイズ・スケーリングを管理し、
    ///    テンプレートアイコンと完全に同じレンダリングになる（CALayer による外部オーバーレイでは
    ///    スケールが合わないため採用しない）
    ///  - フェードバックは CATransition(.fade) で button.image 変更時に付与する
    private func flashMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true

        // アクセント色のアイコン（paletteColors でカラーレンダリング、isTemplate = false）
        let accentNS = AppSettings.accentNSColor()
        guard let accentImage = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(paletteColors: [accentNS])) else { return }

        // テンプレートアイコン（通常状態）
        let templateImage = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipFeed"
        )
        templateImage?.isTemplate = true

        // 即座にアクセント色アイコンへ切り替え
        button.image = accentImage

        // 800ms かけてテンプレートへフェードバック
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let button = self?.statusItem?.button else { return }
            let transition = CATransition()
            transition.type        = .fade
            transition.duration    = 0.8
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            button.layer?.add(transition, forKey: kCATransition)
            button.image = templateImage
        }
    }

    // MARK: - Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
        clipboardViewModel?.saveToDiskAndWait()
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = hotKeyHandlerRef { RemoveEventHandler(ref) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        iconFlashCancellable?.cancel()
    }
}
