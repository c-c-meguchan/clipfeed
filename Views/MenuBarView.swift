import SwiftUI
import AppKit

// MARK: - 検索フィールド（AppKit）— マウスでフォーカスした際も becomeFirstResponder で検知し、カードのフォーカスを確実に外す

private final class SearchNSTextField: NSTextField {
    var onBecomeFirstResponder: (() -> Void)?
    var onResignFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        onBecomeFirstResponder?()
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        onResignFirstResponder?()
        return super.resignFirstResponder()
    }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}

private struct SearchFieldRepresentable: NSViewRepresentable {
    var text: String
    var placeholder: String
    var shouldHaveFocus: Bool
    var forceResignTrigger: Int
    /// タブ切替時に updateNSView を確実に呼ばせ、first responder の再同期を行う
    var selectedSourceForSync: String?
    var accentNSColor: NSColor
    var onTextChange: (String) -> Void
    var onBecomeFirstResponder: () -> Void
    var onResignFirstResponder: () -> Void
    var onFirstResponderChange: (Bool) -> Void
    var onSyncSearchFocusStateIfNeeded: () -> Void

    func makeNSView(context: Context) -> SearchNSTextField {
        let field = SearchNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.onBecomeFirstResponder = onBecomeFirstResponder
        field.onResignFirstResponder = onResignFirstResponder
        return field
    }

    func updateNSView(_ nsView: SearchNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.onBecomeFirstResponder = onBecomeFirstResponder
        nsView.onResignFirstResponder = onResignFirstResponder

        if shouldHaveFocus, let window = nsView.window, window.firstResponder != nsView.currentEditor() && window.firstResponder != nsView {
            window.makeFirstResponder(nsView)
        }
        if !shouldHaveFocus, let window = nsView.window, window.firstResponder == nsView || window.firstResponder == nsView.currentEditor() {
            window.makeFirstResponder(nil)
        }
        if forceResignTrigger != context.coordinator.lastResignTrigger {
            context.coordinator.lastResignTrigger = forceResignTrigger
            nsView.window?.makeFirstResponder(nil)
        }
        // 検索フィールドが実際に first responder かどうかを毎回報告し、カードのフォーカス表示のずれを防ぐ
        let isSearchFirstResponder: Bool = {
            guard let window = nsView.window, let resp = window.firstResponder else { return false }
            if resp === nsView { return true }
            if let editor = nsView.currentEditor(), resp === editor { return true }
            return false
        }()
        onFirstResponderChange(isSearchFirstResponder)
        if isSearchFirstResponder {
            onSyncSearchFocusStateIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, accentNSColor: accentNSColor)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onTextChange: (String) -> Void
        var accentNSColor: NSColor
        var lastResignTrigger: Int = 0

        init(onTextChange: @escaping (String) -> Void, accentNSColor: NSColor) {
            self.onTextChange = onTextChange
            self.accentNSColor = accentNSColor
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onTextChange(field.stringValue)
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            editor.insertionPointColor = accentNSColor
        }
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var viewModel: ClipboardHistoryViewModel
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel
    @EnvironmentObject var languageObserver: AppLanguageObserver
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("maxItems") private var maxItems: Int = 50
    @AppStorage(AppSettings.accentColorKey) private var accentColorId: String = "blue"

    var body: some View {
        VStack(spacing: 0) {
            headerView
            contentView
        }
        .id(languageObserver.currentLanguage + "-\(languageObserver.languageChangeSeed)")
        .frame(width: 400, height: 600)
        .onChange(of: maxItems) { _ in
            viewModel.enforceMaxItems()
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 10) {
            Text("ClipFeed")
                .font(.headline)
            HStack(spacing: 6) {
                SearchFieldRepresentable(
                    text: clipboardViewModel.searchText,
                    placeholder: "⇥ " + L("search_placeholder", fallback: "Search clipboard"),
                    shouldHaveFocus: clipboardViewModel.focusArea == .search,
                    forceResignTrigger: clipboardViewModel.forceSearchResignTrigger,
                    selectedSourceForSync: clipboardViewModel.selectedSource,
                    accentNSColor: AppSettings.accentNSColor(for: accentColorId),
                    onTextChange: { clipboardViewModel.updateSearchText($0) },
                    onBecomeFirstResponder: {
                        if clipboardViewModel.isRestoringFocusOnPopoverOpen { return }
                        clipboardViewModel.setSearchFieldActuallyFirstResponder(true)
                    },
                    onResignFirstResponder: { clipboardViewModel.setSearchFieldActuallyFirstResponder(false) },
                    onFirstResponderChange: { clipboardViewModel.setSearchFieldActuallyFirstResponder($0) },
                    onSyncSearchFocusStateIfNeeded: { clipboardViewModel.syncSearchFocusStateIfNeeded() }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(searchBoxBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(searchBoxFocusBorderColor, lineWidth: clipboardViewModel.isSearchFieldActuallyFirstResponder ? 1 : 0)
            )
            Button {
                NotificationCenter.default.post(name: AppDelegate.openSettingsNotification, object: nil)
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.plain)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    /// ヘッダーとかろうじて差がつく検索ボックス用の塗り（ライト/ダーク対応）
    private var searchBoxBackgroundColor: Color {
        switch colorScheme {
        case .dark:
            return Color(white: 0.20)
        default:
            return Color(white: 0.95)
        }
    }

    /// 検索ボックスフォーカス時の枠線（カラーテーマに応じたグレー）
    private var searchBoxFocusBorderColor: Color {
        switch colorScheme {
        case .dark:
            return Color(white: 0.45)
        default:
            return Color(white: 0.55)
        }
    }
    
    private var contentView: some View {
        MainPopoverView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ClipboardHistoryViewModel())
        .environmentObject(ClipboardViewModel())
        .environmentObject(AppLanguageObserver.shared)
}
