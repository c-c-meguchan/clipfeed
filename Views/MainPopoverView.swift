import SwiftUI
import AppKit

private struct SourceTab: Equatable {
    let name: String
    let iconData: Data?

    static func == (lhs: SourceTab, rhs: SourceTab) -> Bool {
        lhs.name == rhs.name
    }
}

/// タブ横スクロールで選択タブを表示に収めるための ID（ScrollViewReader 用）
private enum SourceTabId: Hashable {
    case all
    case source(String)
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 各カードの frame（clipboardScroll 座標）を集約
private struct ItemFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// スクロール領域の表示高さ
private struct ScrollVisibleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

struct MainPopoverView: View {
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel
    @Environment(\.appAccentColor) private var appAccentColor
    @Namespace private var cardAnimation
    @State private var lastFocusedIndex: Int?
    @State private var scrollOffset: CGFloat = 0
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var scrollVisibleHeight: CGFloat = 400

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
    
    /// ショートカット用の index（0..<9）を item.id で O(1) 参照。shortcutOrderedIDs を View が更新するのでここでは参照するだけ。
    private var shortcutIndexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: clipboardViewModel.shortcutOrderedIDs.enumerated().map { ($0.element, $0.offset) })
    }

    /// 表示順（displayedItems）におけるインデックスを item.id から逆引きするマップ
    private var indexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: clipboardViewModel.displayedItems.enumerated().map { ($0.element.id, $0.offset) })
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceTabBar
            ZStack {
                GeometryReader { zstackGeo in
                    Color.clear.preference(key: ScrollVisibleHeightPreferenceKey.self, value: zstackGeo.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
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
                                    Button("戻る esc") {
                                        clipboardViewModel.clearSearchAndReturnToNavigation()
                                        clipboardViewModel.setSearchResign()
                                    }
                                    .buttonStyle(BackButtonStyle())
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
                                    .id(item.id)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: ItemFramesPreferenceKey.self,
                                                value: [item.id: geo.frame(in: .named("clipboardScroll"))]
                                            )
                                        }
                                    )
                                    .animation(nil, value: clipboardViewModel.items)
                                    .matchedGeometryEffect(id: item.id, in: cardAnimation)
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "clipboardScroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                        DispatchQueue.main.async { updateShortcutOrder(scrollOffset: value) }
                    }
                    .onPreferenceChange(ItemFramesPreferenceKey.self) { value in
                        itemFrames = value
                        DispatchQueue.main.async { updateShortcutOrder(itemFrames: value) }
                    }
                    .onDisappear {
                        DispatchQueue.main.async { clipboardViewModel.savePopoverCloseState() }
                    }
                    // ポップオーバーを開いたとき → 前回のフォーカスを復元 or 最新にリセットし、検索にはフォーカスしない
                    .onAppear {
                        DispatchQueue.main.async { updateShortcutOrder() }
                        DispatchQueue.main.async {
                            let focusLatest = clipboardViewModel.restoreOrResetFocusOnPopoverOpen()
                            if let fid = clipboardViewModel.focusedItemID, let idx = indexByID[fid] {
                                lastFocusedIndex = idx
                            } else {
                                lastFocusedIndex = nil
                            }
                            clipboardViewModel.setSearchResign()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                clipboardViewModel.setSearchResign()
                                if focusLatest {
                                    clipboardViewModel.ensureFeedFocus()
                                    scrollToLatest(proxy)
                                } else {
                                    clipboardViewModel.ensureFeedFocus()
                                    if let id = clipboardViewModel.focusedItemID {
                                        proxy.scrollTo(id, anchor: .center)
                                    }
                                }
                                clipboardViewModel.endRestoringFocusOnPopoverOpen()
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                        }
                    }
                    // 新規アイテム追加時
                    .onChange(of: clipboardViewModel.filteredItems.count) { _ in
                        DispatchQueue.main.async { updateShortcutOrder() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollToLatest(proxy)
                            }
                        }
                    }
                    // タブ切替時
                    .onChange(of: clipboardViewModel.selectedSource) { _ in
                        DispatchQueue.main.async { updateShortcutOrder() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToLatest(proxy)
                        }
                    }
                    // 検索テキスト変更時もショートカット割り当てを再計算
                    .onChange(of: clipboardViewModel.searchText) { _ in
                        DispatchQueue.main.async { updateShortcutOrder() }
                    }
                    // フォーカス移動時: フォーカス中アイテムが表示外に出る場合のみスクロール（中腹では端に固定されず現在地を維持）
                    .onChange(of: clipboardViewModel.focusedItemID) { id in
                        guard let id else { return }
                        guard let newIndex = indexByID[id] else { return }
                        let previous = lastFocusedIndex
                        lastFocusedIndex = newIndex
                        guard let prev = previous, prev != newIndex else { return }

                        let visibleTop: CGFloat = -scrollOffset
                        let visibleBottom: CGFloat = -scrollOffset + scrollVisibleHeight
                        if let frame = itemFrames[id] {
                            let inView = frame.minY >= visibleTop - 1 && frame.maxY <= visibleBottom + 1
                            if inView { return }
                        }
                        let anchor: UnitPoint = newIndex > prev ? .bottom : .top
                        proxy.scrollTo(id, anchor: anchor)
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
                if area == .feed {
                    DispatchQueue.main.async { clipboardViewModel.ensureFeedFocus() }
                }
            }
            .onPreferenceChange(ScrollVisibleHeightPreferenceKey.self) { value in
                if value > 0 {
                    scrollVisibleHeight = value
                    DispatchQueue.main.async { updateShortcutOrder(scrollVisibleHeight: value) }
                } else {
                    DispatchQueue.main.async { updateShortcutOrder() }
                }
            }
        }
    }

    private var sourceTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    sourceChip(name: L("filter_all", fallback: "All"), iconData: nil, source: nil)
                        .id(SourceTabId.all)
                    ForEach(sourceTabs, id: \.name) { tab in
                        sourceChip(name: localizedSourceName(tab.name) ?? tab.name, iconData: tab.iconData, source: tab.name)
                            .id(SourceTabId.source(tab.name))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .onChange(of: clipboardViewModel.selectedSource) { newSource in
                let id = newSource.map { SourceTabId.source($0) } ?? .all
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    /// 表示順の最新（一番上）にスクロール
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let id = clipboardViewModel.displayedItems.first?.id else { return }
        proxy.scrollTo(id, anchor: .top)
    }

    /// 表示内のアイテムのうち kind == .normal を上から順に最大9件の ID を shortcutOrderedIDs にセットする。index 0 = ⌘1 = 一番上。
    private func updateShortcutOrder(
        scrollOffset overrideOffset: CGFloat? = nil,
        itemFrames overrideFrames: [UUID: CGRect]? = nil,
        scrollVisibleHeight overrideHeight: CGFloat? = nil
    ) {
        let displayed = clipboardViewModel.displayedItems
        let offset = overrideOffset ?? scrollOffset
        let frames = overrideFrames ?? itemFrames
        let height = overrideHeight ?? scrollVisibleHeight

        let visibleTop: CGFloat = -offset
        let visibleBottom: CGFloat = -offset + height

        let ids: [UUID]
        if frames.isEmpty || height <= 0 {
            ids = displayed.filter { $0.kind == .normal }.prefix(9).map(\.id)
        } else {
            let visible = displayed.filter { item in
                guard item.kind == .normal, let f = frames[item.id] else { return false }
                return f.maxY > visibleTop && f.minY < visibleBottom
            }
            ids = visible
                .sorted { (frames[$0.id]?.minY ?? 0) < (frames[$1.id]?.minY ?? 0) }
                .prefix(9)
                .map(\.id)
        }
        clipboardViewModel.shortcutOrderedIDs = ids
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
            .background(isSelected ? appAccentColor : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// 検索0件時の「戻る」用。コピーボタン（ShortcutButtonStyle）と同じ目立ち度・アクセントなし
private struct BackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.2 : 0.08))
            .cornerRadius(4)
    }
}

#Preview {
    MainPopoverView()
        .environmentObject(ClipboardViewModel())
}
