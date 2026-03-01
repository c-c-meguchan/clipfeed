import Foundation
import Combine
import SwiftUI
import AppKit

class ClipboardHistoryViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var statistics: [DayStatistics] = []
    
    @AppStorage("maxItems") private var maxItems: Int = 50
    
    private let clipboardManager = ClipboardManager.shared
    private let ocrManager = OCRManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var hasPerformedInitialOCR = false
    
    init() {
        setupClipboardObserver()
    }
    
    private func setupClipboardObserver() {
        clipboardManager.$changeCount
            .dropFirst()
            .sink { [weak self] _ in
                self?.handleClipboardChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleClipboardChange() {
        guard let content = clipboardManager.getCurrentContent(),
              !content.isEmpty else {
            return
        }
        
        // 重複チェック（直近のアイテムと同じテキストの場合は追加しない）
        if let lastItem = items.first, lastItem.text == content {
            return
        }
        
        let newItem = ClipboardItem(
            type: .text,
            text: content,
            isPinned: false
        )
        items.insert(newItem, at: 0)
        
        // 最大件数制限（Pinnedは削除対象外）
        enforceMaxItems()
        
        updateStatistics()
    }
    
    func enforceMaxItems() {
        // 「非Pinnedのみ」maxItems 件を超えた分だけ、古い順に削除する（Pinnedは削除しない）
        var unpinnedCount = items.reduce(0) { $0 + ($1.isPinned ? 0 : 1) }
        guard unpinnedCount > maxItems else { return }

        for index in items.indices.reversed() {
            if unpinnedCount <= maxItems { break }
            if items[index].isPinned { continue }
            items.remove(at: index)
            unpinnedCount -= 1
        }
    }
    
    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        
        items[index].isPinned.toggle()
        updateStatistics()
    }
    
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        updateStatistics()
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let text = item.text {
            pasteboard.setString(text, forType: .string)
        }
    }
    
    func performOCR(for item: ClipboardItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        // クリップボードに画像がある場合のみOCRを実行（コピー直後には呼ばれない設計）
        if let ocrText = await ocrManager.performOCR(on: .general) {
            await MainActor.run {
                items[index].ocrText = ocrText
            }
        }
    }
    
    func performInitialOCR() async {
        guard !hasPerformedInitialOCR else {
            return
        }
        
        hasPerformedInitialOCR = true
        
        // 現在のクリップボード内容に対してOCRを実行
        if let ocrText = await ocrManager.performOCR(on: .general) {
            // 最新のアイテムにOCR結果を追加
            if let index = items.firstIndex(where: { $0.id == items.first?.id }) {
                await MainActor.run {
                    items[index].ocrText = ocrText
                }
            }
        }
    }
    
    private func updateStatistics() {
        let grouped = Dictionary(grouping: items) { $0.dayKey }
        statistics = grouped.map { dayKey, items in
            DayStatistics(dayKey: dayKey, count: items.count)
        }
        .sorted { $0.dayKey > $1.dayKey }
    }
}
