import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var viewModel: ClipboardHistoryViewModel
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel
    @EnvironmentObject var languageObserver: AppLanguageObserver
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("maxItems") private var maxItems: Int = 50
    @FocusState private var searchFieldFocused: Bool

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
        .onChange(of: clipboardViewModel.focusArea) { area in
            if area == .search {
                searchFieldFocused = true
            } else {
                searchFieldFocused = false
            }
        }
        .onChange(of: clipboardViewModel.forceSearchResignTrigger) { _ in
            searchFieldFocused = false
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 10) {
            Text("ClipFeed")
                .font(.headline)
            TextField(
                L("search_placeholder", fallback: "Search clipboard"),
                text: Binding(
                    get: { clipboardViewModel.searchText },
                    set: { clipboardViewModel.updateSearchText($0) }
                )
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(searchBoxBackgroundColor)
            )
            .focused($searchFieldFocused)
            .onChange(of: searchFieldFocused) { focused in
                if clipboardViewModel.isRestoringFocusOnPopoverOpen && focused {
                    return
                }
                clipboardViewModel.isSearchFocused = focused
                if focused {
                    clipboardViewModel.focusArea = .search
                    clipboardViewModel.focusedItemID = nil
                }
            }
            Button {
                NotificationCenter.default.post(name: AppDelegate.openSettingsNotification, object: nil)
            } label: {
                Image(systemName: "gearshape")
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
