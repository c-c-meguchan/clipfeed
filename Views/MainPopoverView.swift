import SwiftUI
import AppKit

private struct SourceTab: Equatable {
    let name: String
    let iconData: Data?

    static func == (lhs: SourceTab, rhs: SourceTab) -> Bool {
        lhs.name == rhs.name
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MainPopoverView: View {
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel
    @Namespace private var cardAnimation
    @State private var lastFocusedIndex: Int?
    @FocusState private var searchFieldFocused: Bool
    @State private var scrollOffset: CGFloat = 0

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

    /// 表示順（displayedItems）におけるインデックスを item.id から逆引きするマップ
    private var indexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: clipboardViewModel.displayedItems.enumerated().map { ($0.element.id, $0.offset) })
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceTabBar
            // スクロール位置に応じて少しだけ隠れる検索フィールド（フィードの上部に「浮かぶ」イメージ）
            let hideProgress = min(max(-scrollOffset / 40.0, 0), 1)   // 下方向に 40pt スクロールでほぼ消える
            let yOffset = -hideProgress * 8

            TextField(
                L("search_placeholder", fallback: "Search clipboard"),
                text: Binding(
                    get: { clipboardViewModel.searchText },
                    set: { clipboardViewModel.updateSearchText($0) }
                )
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8) // ほんの少し高さを大きく
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(1.0))
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .focused($searchFieldFocused)
            .opacity(1 - hideProgress)
            .offset(y: yOffset)
            .onChange(of: searchFieldFocused) { focused in
                clipboardViewModel.isSearchFocused = focused
                if focused {
                    clipboardViewModel.focusArea = .search
                    // 検索窓にフォーカスがある間はフィード側のフォーカスを外す
                    clipboardViewModel.focusedItemID = nil
                }
            }
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // スクロール位置計測用（先頭付近のオフセットを取得）
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geo.frame(in: .named("clipboardScroll")).minY
                                    )
                            }
                            .frame(height: 0)

                            if clipboardViewModel.displayedItems.isEmpty {
                                VStack(spacing: 12) {
                                    Text("履歴が見つかりません")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Button("⏎ 戻る") {
                                        // 検索状態をリセットしてナビゲーションモードに戻す
                                        clipboardViewModel.updateSearchText("")
                                        clipboardViewModel.focusArea = .feed
                                        clipboardViewModel.ensureFeedFocus()
                                        searchFieldFocused = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .frame(maxWidth: .infinity, minHeight: 160)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                            } else {
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
                    }
                    .coordinateSpace(name: "clipboardScroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }
                    // ポップオーバーを開いたとき → 最新アイテムへスクロール
                    .onAppear {
                        DispatchQueue.main.async {
                            // 初期状態では必ずフィード側にフォーカスを置き、検索フィールドのフォーカスを外す
                            searchFieldFocused = false
                            clipboardViewModel.isSearchFocused = false
                            clipboardViewModel.focusArea = .feed
                            // 最新アイテム（一番下）にフォーカス
                            let lastID = clipboardViewModel.displayedItems.last?.id
                            clipboardViewModel.focusedItemID = lastID
                            if let lastID, let idx = indexByID[lastID] {
                                lastFocusedIndex = idx
                            } else {
                                lastFocusedIndex = nil
                            }
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
                    // フォーカス移動時: フォーカス中アイテムが常に表示領域内に収まるようにする
                    .onChange(of: clipboardViewModel.focusedItemID) { id in
                        guard let id else { return }
                        guard let newIndex = indexByID[id] else { return }
                        let previous = lastFocusedIndex
                        lastFocusedIndex = newIndex
                        // 初回はスクロールしない（onAppear 側で処理）
                        guard let prev = previous, prev != newIndex else { return }
                        let anchor: UnitPoint = newIndex > prev ? .bottom : .top
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(id, anchor: anchor)
                            }
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
            .onMoveCommand { direction in
                clipboardViewModel.moveFocus(direction)
            }
            .onChange(of: clipboardViewModel.focusArea) { area in
                switch area {
                case .search:
                    searchFieldFocused = true
                case .feed:
                    searchFieldFocused = false
                    clipboardViewModel.ensureFeedFocus()
                }
            }
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
