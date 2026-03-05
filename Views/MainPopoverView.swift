import SwiftUI
import AppKit

private struct SourceTab: Equatable {
    let name: String
    let iconData: Data?

    static func == (lhs: SourceTab, rhs: SourceTab) -> Bool {
        lhs.name == rhs.name
    }
}

struct MainPopoverView: View {
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel
    @Namespace private var cardAnimation

    /// items から sourceAppName を最新出現順で重複除去し、アイコンデータ付きで生成
    private var sourceTabs: [SourceTab] {
        var seen = Set<String>()
        var result: [SourceTab] = []
        for item in clipboardViewModel.items {
            if let name = item.sourceAppName, !seen.contains(name) {
                seen.insert(name)
                result.append(SourceTab(name: name, iconData: item.sourceAppIconData))
            }
        }
        return result
    }
    
    /// 現在のタブでショートカット対象となるアイテム（kind == .normal のみ、最大9件／最新順）
    private var shortcutTargets: [ClipboardItem] {
        Array(clipboardViewModel.filteredItems.filter { $0.kind == .normal }.prefix(9))
    }
    
    /// ショートカット用の index（0..<9）を item.id で O(1) 参照するためのマップ。body 内で 1 回だけ O(n) 計算し、ForEach 内では O(n²) にならないようにする。
    private var shortcutIndexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: shortcutTargets.enumerated().map { ($0.element.id, $0.offset) })
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceTabBar
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(clipboardViewModel.displayedItems) { item in
                                let shortcutIndex = shortcutIndexByID[item.id] ?? -1
                                VStack(spacing: 0) {
                                    ClipboardCardView(item: item, index: shortcutIndex)
                                    Divider()
                                }
                                .animation(nil, value: clipboardViewModel.items)
                                .matchedGeometryEffect(id: item.id, in: cardAnimation)
                            }
                        }
                    }
                    // ポップオーバーを開いたとき → 最新アイテムへスクロール
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollToLatest(proxy)
                        }
                    }
                    // 新規アイテム追加時
                    .onChange(of: clipboardViewModel.filteredItems.count) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollToLatest(proxy)
                            }
                        }
                    }
                    // タブ切替時
                    .onChange(of: clipboardViewModel.selectedSource) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToLatest(proxy)
                        }
                    }
                }

                if clipboardViewModel.showToast {
                    Text(clipboardViewModel.toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: clipboardViewModel.showToast)
        }
    }

    private var sourceTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // 「すべて」チップ
                sourceChip(name: L("filter_all", fallback: "All"), iconData: nil, source: nil)
                // コピー元別チップ
                ForEach(sourceTabs, id: \.name) { tab in
                    sourceChip(name: localizedSourceName(tab.name) ?? tab.name, iconData: tab.iconData, source: tab.name)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let id = clipboardViewModel.filteredItems.first?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
    }

    private func sourceChip(name: String, iconData: Data?, source: String?) -> some View {
        let isSelected = clipboardViewModel.selectedSource == source
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
                clipboardViewModel.selectedSource = source
            }
        } label: {
            HStack(spacing: 5) {
                if let data = iconData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                        .cornerRadius(3)
                }
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainPopoverView()
        .environmentObject(ClipboardViewModel())
}
