import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var viewModel: ClipboardHistoryViewModel
    @EnvironmentObject var languageObserver: AppLanguageObserver
    @AppStorage("maxItems") private var maxItems: Int = 50

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerView

            // コンテンツエリア（今後実装）
            contentView

            // フッター（今後実装）
            footerView
        }
        .id(languageObserver.currentLanguage + "-\(languageObserver.languageChangeSeed)")
        .frame(width: 400, height: 600)
        .onChange(of: maxItems) { _ in
            viewModel.enforceMaxItems()
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("ClipFeed")
                .font(.headline)
            Spacer()
            Button {
                NotificationCenter.default.post(name: AppDelegate.openSettingsNotification, object: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var contentView: some View {
        MainPopoverView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var footerView: some View {
        HStack {
            Spacer()
            Button(L("close", fallback: "Close")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ClipboardHistoryViewModel())
        .environmentObject(AppLanguageObserver.shared)
}
