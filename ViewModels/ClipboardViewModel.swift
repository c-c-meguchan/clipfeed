import Foundation
import Combine
import AppKit
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

enum CopyTarget: Equatable {
    case parent(UUID)
    case ocr(UUID)
}

enum FocusArea {
    case feed
    case search
}

final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var showToast: Bool = false
    @Published var toastMessage: String = ""
    @Published var selectedSource: String?
    @Published var highlightedTarget: CopyTarget?
    @Published var searchText: String = ""
    @Published var focusedItemID: UUID?
    @Published var focusArea: FocusArea = .feed
    @Published var isSearchFocused: Bool = false

    /// 検索フィールドが実際に first responder か（AppKit から報告）。true の間はカードにフォーカスを付けず表示もしない
    @Published var isSearchFieldActuallyFirstResponder: Bool = false

    /// ショートカット ⌘1〜⌘9 の割り当て順（画面内で上から順）。index 0 = ⌘1 = 一番上の表示アイテム。
    @Published var shortcutOrderedIDs: [UUID] = []

    /// キーボードナビゲーション（moveFocus）の最終実行時刻。
    /// スクロールアニメーション中の refocus 誤発火を抑制するために View 側で参照する。
    var lastKeyboardNavigationTime = Date.distantPast

    /// ポップオーバーを閉じたときの状態（再開時にフォーカス復元 or 最新にリセットの判定に使用）
    private var lastFocusedItemIDWhenClosed: UUID?
    private var lastFilteredCountWhenClosed: Int?
    private var lastLatestItemIDWhenClosed: UUID?

    /// ポップオーバーを開いた直後のフォーカス復元中。true の間は検索にフォーカスが移っても focusedItemID を消さない（AppDelegate で表示前に true にする）
    var isRestoringFocusOnPopoverOpen: Bool = false

    @AppStorage("maxItems") private var maxItems: Int = 50

    /// コピー元別フィルタ後のアイテム（検索は含めない）
    var filteredItems: [ClipboardItem] {
        guard let source = selectedSource else { return items }
        return items.filter { $0.sourceAppName == source }
    }

    /// View に渡す表示順（最新が先頭 = 上が最新）。⌘1 = 一番上。
    var displayedItems: [ClipboardItem] {
        let base = filteredItems
        guard !searchText.isEmpty else {
            return base
        }
        let query = searchText
        let searched = base.filter { item in
            let text = item.plainText ?? item.text ?? ""
            let ocr = item.ocrText ?? item.ocrResult ?? ""
            return text.localizedCaseInsensitiveContains(query) || ocr.localizedCaseInsensitiveContains(query)
        }
        return searched
    }

    /// タブ生成用：items から sourceAppName を最新出現順で重複除去したリスト
    var availableSources: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            if let name = item.sourceAppName, !seen.contains(name) {
                seen.insert(name)
                result.append(name)
            }
        }
        return result
    }

    // MARK: - Search & Focus

    func updateSearchText(_ text: String) {
        searchText = text
        repairFocusIfNeeded()
    }

    private func repairFocusIfNeeded() {
        // 検索フィールドが実際に first responder の間は絶対にカードにフォーカスを付けない
        // ただしポップオーバー表示直後の復元中は、AppKit の一時フォーカスで保存済み focusedItemID を消さない
        if isSearchFieldActuallyFirstResponder {
            if !isRestoringFocusOnPopoverOpen { focusedItemID = nil }
            return
        }
        if isSearchFocused || focusArea == .search {
            if !isRestoringFocusOnPopoverOpen { focusedItemID = nil }
            return
        }

        // フォーカス対象は kind == .normal のみ（2MB 超プレースホルダはフォーカスしない）
        let focusableItems = displayedItems.filter { $0.kind == .normal }
        guard !focusableItems.isEmpty else {
            focusedItemID = nil
            return
        }

        if let focused = focusedItemID,
           focusableItems.contains(where: { $0.id == focused }) {
            return
        }

        // 最新の通常アイテム（一番上）にフォーカスを合わせる
        focusedItemID = focusableItems.first?.id
    }

    /// タブを delta 分だけ循環切替（nil = "すべて" を先頭に含む）
    /// NSEvent ローカルモニターから main thread 上で呼ばれることを前提とする
    func switchSourceTab(delta: Int) {
        let sources: [String?] = [nil] + availableSources.map { Optional($0) }
        guard sources.count > 1 else {
            LogCapture.record("[switchSourceTab] skipped — sources.count:\(sources.count) (タブが1つしかない)")
            return
        }
        let currentIndex = sources.firstIndex(where: { $0 == selectedSource }) ?? 0
        let newIndex = (currentIndex + delta + sources.count) % sources.count
        LogCapture.record("[switchSourceTab] delta:\(delta) \(String(describing: selectedSource)) → \(String(describing: sources[newIndex]))")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.1)) {
            selectedSource = sources[newIndex]
        }
        repairFocusIfNeeded()
    }
    
    func moveFocus(_ direction: MoveCommandDirection) {
        // フィードにフォーカスがあり、検索フィールドが first responder でないときだけ移動可能（検索テキストありでも Tab でフィードに移れば上下移動可）
        guard focusArea == .feed, !isSearchFieldActuallyFirstResponder else { return }

        // フォーカスが無い場合は、まず検索結果の先頭などにフォーカスを合わせる
        if focusedItemID == nil {
            repairFocusIfNeeded()
        }

        // フォーカス対象は kind == .normal のみ
        let focusableItems = displayedItems.filter { $0.kind == .normal }
        guard !focusableItems.isEmpty else { return }

        guard let current = focusedItemID,
              let index = focusableItems.firstIndex(where: { $0.id == current }) else { return }

        let newIndex: Int

        switch direction {
        case .down:
            newIndex = min(index + 1, focusableItems.count - 1)
        case .up:
            newIndex = max(index - 1, 0)
        default:
            return
        }

        focusedItemID = focusableItems[newIndex].id
        lastKeyboardNavigationTime = Date()
    }
    
    /// 1アイテムあたりの保存サイズ上限は ClipboardSizeLimit.maxContentBytes（2MB）。HTML/テキスト/画像はこの関数で一元チェック。
    /// Application Support / ClipFeed / clipboard.json
    private static var persistenceFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ClipFeed", isDirectory: true)
        return dir.appendingPathComponent("clipboard.json", isDirectory: false)
    }

    /// 保存前バックアップ用。clipboard.json と同じディレクトリの backup.json
    private static var backupFileURL: URL {
        persistenceFileURL.deletingLastPathComponent().appendingPathComponent("backup.json", isDirectory: false)
    }

    /// JSON 全体のサイズ上限（100MB）。performWrite 内でのみ参照。UI件数とは別の安全制限。
    private static let maxTotalJSON = 100_000_000  // 100MB

    /// 保存直前に必ず通す。1アイテムの実データ合計が ClipboardSizeLimit.maxContentBytes 以下なら true。
    /// 超過時はログを出して false（追加・保存しない）。
    /// ※ sourceAppIconData はメタデータのため合計に含めない（TIFF が巨大になり全件 2MB 超過するのを防ぐ）
    private static func validateItemSize(_ item: ClipboardItem) -> Bool {
        var total = 0
        if let text = item.text {
            total += text.utf8.count
        } else if let plain = item.plainText {
            total += plain.utf8.count
        }
        total += item.html?.utf8.count ?? 0
        total += item.imageData?.count ?? 0
        total += item.rtfData?.count ?? 0
        total += item.htmlData?.count ?? 0
        total += item.thumbnailData?.count ?? 0
        // sourceAppIconData は除外（アプリアイコン TIFF が 2MB 超になることがあるため）
        total += item.ocrText?.utf8.count ?? 0
        total += item.ocrResult?.utf8.count ?? 0
        if total > ClipboardSizeLimit.maxContentBytes {
            LogCapture.record("[ClipboardVM] validateItemSize: OVER limit — \(total) bytes")
            return false
        }
        return true
    }

    /// text + html + imageData を連結して SHA256 の hex 文字列を返す（直前同一判定用）
    /// Figma などは同じフレームでもコピーごとに空白・属性順が変わるため、文字列は正規化してからハッシュする。
    private static func contentHash(text: String?, html: String?, imageData: Data?) -> String {
        var data = Data()
        data.append(Data(normalizeForHash(text ?? "").utf8))
        data.append(Data(normalizeHtmlForHash(html ?? "").utf8))
        data.append(imageData ?? Data())
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// 同一内容判定用：連続する空白を1つにし、前後トリム。Figma の連続コピーで差分が出ないようにする。
    private static func normalizeForHash(_ s: String) -> String {
        s.replacingOccurrences(of: "[\\s]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML を同一判定用に正規化。空白の正規化に加え、Figma/React が毎回変える data-* 属性を除去する。
    private static func normalizeHtmlForHash(_ html: String) -> String {
        var s = normalizeForHash(html)
        // data-reactid, data-key, data-dataurl などコピーごとに変わりうる属性を除去
        let patterns = [
            "data-reactid=\"[^\"]*\"",
            "data-key=\"[^\"]*\"",
            "data-dataurl=\"[^\"]*\"",
            "data-id=\"[^\"]*\"",
            "data-node-id=\"[^\"]*\"",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: "\\s+" + pattern) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            }
        }
        return normalizeForHash(s)
    }

    private let monitor: ClipboardMonitor
    private var cancellables = Set<AnyCancellable>()
    private var lastReCopiedText: String?
    private var lastReCopiedImageData: Data?
    /// OCR 実行中に true にセット → 次のクリップボード変化を履歴追加から除外する
    private var isPerformingOCR = false
    /// 初回 loadFromDisk 完了まで true。完了前のクリップボード発火で 1 件だけ save がキューに入り後から上書きする不具合を防ぐ
    private var loadCompleted = false

    /// changeCount 監視用。Monitor のタイマー内で比較・更新される（スレッドセーフ）
    private var _lastChangeCount: Int = NSPasteboard.general.changeCount
    private let lastChangeCountLock = NSLock()
    private var lastChangeCount: Int {
        get { lastChangeCountLock.withLock { _lastChangeCount } }
        set { lastChangeCountLock.withLock { _lastChangeCount = newValue } }
    }

    init(monitor: ClipboardMonitor = .shared) {
        LogCapture.record("ClipboardViewModel initialized")
        self.monitor = monitor

        monitor.setChangeCountProvider(
            get: { [weak self] in self?.lastChangeCount ?? -1 },
            set: { [weak self] value in self?.lastChangeCount = value }
        )

        loadFromDisk()

        monitor.$copiedText
            .compactMap { $0 }
            .sink { [weak self] text in
                guard let self else { return }
                // copiedText 発火時点で latestRTFData / latestHTMLData は確定済み
                self.handleClipboardText(
                    text,
                    rtf: self.monitor.latestRTFData,
                    html: self.monitor.latestHTMLData
                )
            }
            .store(in: &cancellables)
        
        monitor.$imageData
            .compactMap { $0 }
            .sink { [weak self] data in
                self?.handleClipboardImage(data)
            }
            .store(in: &cancellables)
        
        monitor.$skippedOversizedContent
            .compactMap { $0 }
            .sink { [weak self] source in
                self?.handleSkippedOversizedContent(sourceAppName: source.0, sourceBundleID: source.1, sourceAppIconData: source.2)
            }
            .store(in: &cancellables)
        
        // 監視は load 完了後に開始（load 前に発火した「1件」で save が上書きされる不具合を防ぐ）
    }
    
    /// Monitor が 2MB 超でスキップしたときに呼ばれる。プレースホルダを挿入してフラグをクリアする。
    private func handleSkippedOversizedContent(sourceAppName: String?, sourceBundleID: String?, sourceAppIconData: Data?) {
        if !loadCompleted { return }
        let placeholder = ClipboardItem(
            id: UUID(),
            createdAt: Date(),
            kind: .oversizedPlaceholder,
            type: .text,
            text: "⚠ 2MBを超えているため再コピーできません",
            isPinned: false,
            sourceAppName: sourceAppName,
            sourceBundleID: sourceBundleID,
            sourceAppIconData: sourceAppIconData
        )
        items.insert(placeholder, at: 0)
        enforceMaxItems()
        saveToDisk()
        monitor.clearSkippedOversizedContent()
        LogCapture.record("[ClipboardVM] Oversized content placeholder inserted (skipped by Monitor)")
    }
    
    private func handleClipboardText(_ text: String, rtf: Data? = nil, html: Data? = nil) {
        if !loadCompleted { return }
        if isPerformingOCR {
            isPerformingOCR = false
            LogCapture.record("Skip history append (OCR operation)")
            return
        }
        if let last = lastReCopiedText, last == text {
            lastReCopiedText = nil
            LogCapture.record("Skipped self-triggered copy")
            return
        }

        let plainText: String? = text.isEmpty ? nil : text
        let htmlString: String? = html.flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
        if plainText == nil && htmlString == nil {
            return
        }

        let hadHTML = htmlString != nil
        if let h = htmlString {
            let htmlBytes = h.utf8.count
            LogCapture.record("[ClipboardVM] HTML size (1件): \(htmlBytes) bytes (\(String(format: "%.2f", Double(htmlBytes) / 1_000_000)) MB) source: \(monitor.latestSourceAppName ?? "?")")
        }

        // 一旦フル内容でアイテムを組み立て、validateItemSize で 2MB 制限のみチェック
        let contentHashValue = Self.contentHash(text: plainText, html: htmlString, imageData: nil)
        let newItem = ClipboardItem(
            kind: .normal,
            type: .text,
            text: plainText,
            htmlData: nil,
            isPinned: false,
            sourceAppName: monitor.latestSourceAppName,
            sourceBundleID: monitor.latestSourceBundleID,
            sourceAppIconData: monitor.latestSourceAppIconData,
            plainText: plainText,
            html: htmlString,
            figmaCompatible: htmlString != nil,
            hadHTML: hadHTML,
            contentHash: contentHashValue
        )

        if !Self.validateItemSize(newItem) {
            let placeholder = ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                kind: .oversizedPlaceholder,
                type: .text,
                text: "⚠ 2MBを超えているため再コピーできません",
                isPinned: false,
                sourceAppName: monitor.latestSourceAppName,
                sourceBundleID: monitor.latestSourceBundleID,
                sourceAppIconData: monitor.latestSourceAppIconData
            )
            items.insert(placeholder, at: 0)
            enforceMaxItems()
            saveToDisk()
            LogCapture.record("[ClipboardVM] Oversized item placeholder inserted")
            return
        }

        if items.first?.contentHash == contentHashValue {
            LogCapture.record("[ClipboardVM] Skipped duplicate (same content as previous item)")
            return
        }

        items.insert(newItem, at: 0)
        enforceMaxItems()
        saveToDisk()
        focusedItemID = newItem.id
        let totalHTMLBytes = items.compactMap { $0.html }.reduce(0) { $0 + $1.utf8.count }
        LogCapture.record("[ClipboardVM] Current clipboard items: \(items.count), total HTML in memory: \(totalHTMLBytes) bytes (\(String(format: "%.2f", Double(totalHTMLBytes) / 1_000_000)) MB)")
    }
    
    private func handleClipboardImage(_ data: Data) {
        if !loadCompleted { return }
        if isPerformingOCR {
            isPerformingOCR = false
            LogCapture.record("Skip history append (OCR operation)")
            return
        }
        if let last = lastReCopiedImageData, last == data {
            lastReCopiedImageData = nil
            LogCapture.record("Skipped self-triggered copy")
            return
        }

        // 巨大画像は reencode 前に弾く（TIFF のデコードでメモリが爆発するのを防ぐ）
        if data.count > ClipboardSizeLimit.maxContentBytes {
            let placeholder = ClipboardItem(
                id: UUID(),
                createdAt: Date(),
                kind: .oversizedPlaceholder,
                type: .image,
                text: "⚠ 2MBを超えているため再コピーできません",
                isPinned: false,
                sourceAppName: monitor.latestSourceAppName,
                sourceBundleID: monitor.latestSourceBundleID,
                sourceAppIconData: monitor.latestSourceAppIconData
            )
            items.insert(placeholder, at: 0)
            enforceMaxItems()
            saveToDisk()
            LogCapture.record("[ClipboardVM] Image rejected before reencode (size \(data.count) > \(ClipboardSizeLimit.maxContentBytes))")
            return
        }

        let sourceName = monitor.latestSourceAppName
        let sourceBundleID = monitor.latestSourceBundleID
        let sourceIconData = monitor.latestSourceAppIconData

        // reencode / ハッシュ / アイテム組み立てはバックグラウンドで実行（TIFF→PNG など重い処理でメインが落ちないように）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let imageDataToStore = Self.reencodeImageData(data) ?? data
            let contentHashValue = Self.contentHash(text: nil, html: nil, imageData: imageDataToStore)
            let newItem = ClipboardItem(
                kind: .normal,
                type: .image,
                imageData: imageDataToStore,
                thumbnailData: nil,
                isPinned: false,
                sourceAppName: sourceName,
                sourceBundleID: sourceBundleID,
                sourceAppIconData: sourceIconData,
                contentHash: contentHashValue
            )

            if !Self.validateItemSize(newItem) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let placeholder = ClipboardItem(
                        id: UUID(),
                        createdAt: Date(),
                        kind: .oversizedPlaceholder,
                        type: .image,
                        text: "⚠ 2MBを超えているため再コピーできません",
                        isPinned: false,
                        sourceAppName: sourceName,
                        sourceBundleID: sourceBundleID,
                        sourceAppIconData: sourceIconData
                    )
                    self.items.insert(placeholder, at: 0)
                    self.enforceMaxItems()
                    self.saveToDisk()
                    LogCapture.record("[ClipboardVM] Oversized item placeholder inserted (after reencode)")
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.items.first?.contentHash == contentHashValue {
                    LogCapture.record("[ClipboardVM] Skipped duplicate (same content as previous item)")
                    return
                }
                self.items.insert(newItem, at: 0)
                self.enforceMaxItems()
                self.saveToDisk()
                self.focusedItemID = newItem.id
                LogCapture.record("[Image] size: \(data.count) bytes (\(String(format: "%.2f", Double(data.count) / 1_000_000)) MB)")
                LogCapture.record("Current clipboard items count: \(self.items.count)")

                let itemId = newItem.id
                let imageDataForThumb = data
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let thumbData = Self.makeThumbnailData(from: imageDataForThumb, maxSize: 80) else { return }
                    DispatchQueue.main.async {
                        guard let self = self,
                              let idx = self.items.firstIndex(where: { $0.id == itemId }) else { return }
                        self.items[idx].thumbnailData = thumbData
                    }
                }
            }
        }
    }
    
    /// ペーストボード由来の画像 Data を保存用に正規化する。
    /// - PNG/JPEG はそのまま返す（画質・色空間・Retina解像度を維持）。
    /// - TIFF 等は NSBitmapImageRep から直接 PNG 出力に変換するのみ（再描画・ポイントサイズ変換は行わない）。
    private static func reencodeImageData(_ data: Data) -> Data? {
        if isPNG(data) || isJPEG(data) {
            return data
        }
        // TIFF 等: デコード済みの NSBitmapImageRep から PNG を出力するだけ。draw は使わない。
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func isPNG(_ data: Data) -> Bool {
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= sig.count else { return false }
        return data.prefix(sig.count).elementsEqual(sig)
    }

    private static func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }

    private static func makeThumbnailData(from imageData: Data, maxSize: CGFloat) -> Data? {
        let size = maxSize
        guard let source = NSImage(data: imageData) else { return nil }
        let srcSize = source.size
        guard srcSize.width > 0, srcSize.height > 0 else { return nil }
        let scale = max(size / srcSize.width, size / srcSize.height)
        let cropSize = size / scale
        let srcRect = NSRect(
            x: max(0, srcSize.width / 2 - cropSize / 2),
            y: max(0, srcSize.height / 2 - cropSize / 2),
            width: min(cropSize, srcSize.width),
            height: min(cropSize, srcSize.height)
        )
        let newImage = NSImage(size: NSSize(width: size, height: size))
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: NSSize(width: size, height: size)),
                    from: srcRect,
                    operation: .copy,
                    fraction: 1.0)
        newImage.unlockFocus()
        return newImage.tiffRepresentation
    }
    
    func ocrCopy(_ item: ClipboardItem) {
        guard item.type == .image,
              let imageData = item.imageData,
              let nsImage = NSImage(data: imageData) else { return }
        Task {
            guard let text = await OCRManager.shared.performOCR(on: nsImage) else {
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].ocrNoText = true
                    }
                    showToastMessage(L("toast_no_text", fallback: "No text found"))
                }
                return
            }
            await MainActor.run {
                // 対象 item の ocrResult を更新（新規履歴は追加しない）
                // hasBeenReCopied は親カード（通常再コピー）専用のため OCR では更新しない
                if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[idx].ocrResult = text
                }
                // OCR 由来のクリップボード変化を履歴追加・コピー元判定から除外するフラグを立てる
                isPerformingOCR = true
                monitor.isInternalCopy = true
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                showReCopyToast()
                showHighlight(.ocr(item.id))
                LogCapture.record("OCR copy completed: \(text.prefix(80))")
            }
        }
    }

    func reCopyItem(_ item: ClipboardItem) {
        guard item.kind == .normal else { return }
        // 次の run loop で実行し、呼び出し元（ショートカット／タップ）をすぐ返してからフィードバックを出す（重い body の前に描画機会を確保）
        DispatchQueue.main.async { [weak self] in
            self?.reCopyItemNow(item)
        }
    }

    private func reCopyItemNow(_ item: ClipboardItem) {
        guard item.kind == .normal else { return }
        monitor.isInternalCopy = true
        let pasteboard = NSPasteboard.general

        switch item.type {
        case .text:
            let stringToCopy = item.plainText ?? item.text ?? ""
            lastReCopiedText = stringToCopy
            lastReCopiedImageData = nil
            if item.figmaCompatible, let html = item.html, let htmlData = html.data(using: .utf8) {
                let payload = (stringToCopy, htmlData)
                showHighlight(.parent(item.id)) { [weak self] in self?.markReCopied(item) }
                showReCopyToast()
                DispatchQueue.global(qos: .userInitiated).async {
                    pasteboard.clearContents()
                    pasteboard.setData(payload.1, forType: .html)
                    pasteboard.setString(payload.0, forType: .string)
                }
            } else if !stringToCopy.isEmpty {
                showHighlight(.parent(item.id)) { [weak self] in self?.markReCopied(item) }
                showReCopyToast()
                DispatchQueue.global(qos: .userInitiated).async {
                    pasteboard.clearContents()
                    pasteboard.setString(stringToCopy, forType: .string)
                }
            }
        case .image:
            if let data = item.imageData {
                lastReCopiedImageData = data
                lastReCopiedText = nil
                showHighlight(.parent(item.id)) { [weak self] in self?.markReCopied(item) }
                showReCopyToast()
                DispatchQueue.global(qos: .userInitiated).async {
                    pasteboard.clearContents()
                    pasteboard.setData(data, forType: .png)
                }
            }
        case .html, .file:
            break
        }
    }

    func copyFocusedItem() {
        guard let id = focusedItemID,
              let item = items.first(where: { $0.id == id }) else { return }
        reCopyItem(item)
    }

    /// フォーカス中アイテムの OCR 済みテキストをクリップボードにコピーする（⌘+Enter）
    func copyFocusedItemOCRResult() {
        guard let id = focusedItemID,
              let item = items.first(where: { $0.id == id }),
              let text = item.ocrResult else { return }
        monitor.isInternalCopy = true
        isPerformingOCR = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showReCopyToast()
        showHighlight(.ocr(item.id))
        LogCapture.record("OCR result re-copy: \(text.prefix(80))")
    }

    /// 検索状態をクリアしてナビゲーションモードに戻す（Esc や「Esc 戻る」から使用）
    func clearSearchAndReturnToNavigation() {
        searchText = ""
        isSearchFocused = false
        focusArea = .feed
        repairFocusIfNeeded()
    }

    /// 外部から「フィード側にフォーカスを戻したい」ときに呼ぶラッパー
    func ensureFeedFocus() {
        // 検索フィールドから確実にフォーカスを外し、フィード用のフォーカスを復活させる
        isSearchFocused = false
        focusArea = .feed
        repairFocusIfNeeded()
    }

    /// ポップオーバーを閉じる直前に呼ぶ。次回開いたときの復元判定用に現在の状態を保存する。
    /// 閉じた時点で「必ずフィード側フォーカス」に正規化するため、focusArea / isSearchFocused / isSearchFieldActuallyFirstResponder もリセットする。
    /// （検索フォーカスを保持したまま閉じると、再表示時に first responder と見た目がずれ、入力も効かずカードにもフォーカスが当たらない状態になるため）
    func savePopoverCloseState() {
        lastFilteredCountWhenClosed = filteredItems.count
        lastLatestItemIDWhenClosed = displayedItems.first?.id
        if focusArea == .feed, !isSearchFocused {
            lastFocusedItemIDWhenClosed = focusedItemID
        } else {
            lastFocusedItemIDWhenClosed = nil
        }
        // 次回開いたときに必ずカード側にフォーカスするよう、閉じる時点で検索フォーカス状態を捨てる
        focusArea = .feed
        isSearchFocused = false
        isSearchFieldActuallyFirstResponder = false
    }

    /// ポップオーバーを表示する直前に AppDelegate から呼ぶ。表示前に true にすることで検索フィールドがフォーカスを奪っても focusedItemID を消さない
    func beginRestoringFocusOnPopoverOpen() {
        isRestoringFocusOnPopoverOpen = true
    }

    /// ポップオーバーを開く直前に AppDelegate から呼ぶ。初回フレームで検索がフォーカスを奪わないよう、先にフィード側に正規化する
    func resetFocusToFeedForPopoverOpen() {
        focusArea = .feed
        isSearchFocused = false
        isSearchFieldActuallyFirstResponder = false
    }

    /// フォーカス復元処理が終わったら View の遅延ブロックから呼ぶ
    func endRestoringFocusOnPopoverOpen() {
        isRestoringFocusOnPopoverOpen = false
    }

    /// ヘッダー検索フィールドに「フォーカスを外せ」と伝える（MainPopoverView の復元時や「戻る」押下時）
    @Published var forceSearchResignTrigger: Int = 0
    func setSearchResign() {
        forceSearchResignTrigger += 1
    }

    /// 検索フィールドが実際に first responder のときに呼ぶ。状態がずれていれば検索フォーカスに揃え、カードのフォーカスを外す（見た目のずれ防止）
    func syncSearchFocusStateIfNeeded() {
        guard !isRestoringFocusOnPopoverOpen else { return }
        if isSearchFocused && focusArea == .search && focusedItemID == nil { return }
        isSearchFocused = true
        focusArea = .search
        focusedItemID = nil
    }

    /// 検索フィールドの first responder 状態を AppKit から報告する。true の間は repairFocusIfNeeded でカードにフォーカスを付けない
    /// true にしたときは常に focusArea / focusedItemID を検索側に揃え、ローカルモニターが Enter を握りつぶさないようにする（変換確定のため）
    func setSearchFieldActuallyFirstResponder(_ value: Bool) {
        guard isSearchFieldActuallyFirstResponder != value else { return }
        isSearchFieldActuallyFirstResponder = value
        if value {
            // ポップオーバー表示直後の復元中は AppKit が検索に一時フォーカスを当てるだけなので、
            // focusArea / focusedItemID を上書きしない（直後の resignSearchFieldFromPopoverWindow で修正される）
            guard !isRestoringFocusOnPopoverOpen else { return }
            focusArea = .search
            isSearchFocused = true
            focusedItemID = nil
        }
    }

    /// ポップオーバーを開いたときに呼ぶ。フォーカスを「前回の位置に復元」または「最新にリセット」する。
    /// - Returns: 最新アイテムにフォーカスした場合は true（スクロールを最新へ）。復元した場合は false（スクロールをフォーカス中へ）。
    func restoreOrResetFocusOnPopoverOpen() -> Bool {
        focusArea = .feed
        isSearchFocused = false

        let focusableItems = displayedItems.filter { $0.kind == .normal }
        guard !focusableItems.isEmpty else {
            focusedItemID = nil
            return true
        }

        let currentCount = filteredItems.count
        let currentLatestID = focusableItems.first?.id

        // 初回起動 or 閉じている間に新規コピーが追加された → 最新にフォーカス
        if lastFilteredCountWhenClosed == nil {
            focusedItemID = currentLatestID
            lastFilteredCountWhenClosed = currentCount
            lastLatestItemIDWhenClosed = currentLatestID
            return true
        }
        if currentCount != lastFilteredCountWhenClosed! || currentLatestID != lastLatestItemIDWhenClosed! {
            focusedItemID = currentLatestID
            lastFilteredCountWhenClosed = currentCount
            lastLatestItemIDWhenClosed = currentLatestID
            return true
        }

        // 前回のフォーカス位置を復元（表示中に残っていれば）
        if let saved = lastFocusedItemIDWhenClosed,
           focusableItems.contains(where: { $0.id == saved }) {
            focusedItemID = saved
            return false
        }
        focusedItemID = currentLatestID
        return true
    }

    /// 画像アイテムを「名前をつけて保存」— 本体の imageData（サムネイルではない）を NSSavePanel で保存
    func saveImageItemToFile(_ item: ClipboardItem) {
        guard item.type == .image,
              let idx = items.firstIndex(where: { $0.id == item.id }),
              let data = items[idx].imageData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "Image.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            showToastMessage(L("toast_saved", fallback: "Saved"))
        } catch {
            showToastMessage(L("toast_save_failed", fallback: "Save failed"))
        }
    }
    
    private func markReCopied(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].hasBeenReCopied = true
    }

    /// ハイライトを付け、delay 後にハイライト解除と onClear を同時に実行（青→通常を挟まずグレーへつなぐ）
    private func showHighlight(_ target: CopyTarget, onClearAfterDelay: (() -> Void)? = nil) {
        highlightedTarget = target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.highlightedTarget = nil
            onClearAfterDelay?()
        }
    }

    private func showReCopyToast() {
        showToastMessage(L("toast_copied", fallback: "Copied to clipboard"))
        NotificationCenter.default.post(name: AppDelegate.closePopoverAfterReCopyNotification, object: nil)
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showToast = false
        }
    }
    
    private func enforceMaxItems() {
        // 件数のみ参照。maxItems（@AppStorage）を超えた非Pinnedを古い順に削除。JSONサイズは見ない。
        var countable = items.reduce(0) { $0 + ($1.isPinned ? 0 : 1) }
        guard countable > maxItems else { return }

        var removed = 0
        for index in items.indices.reversed() {
            if countable <= maxItems { break }
            if items[index].isPinned { continue }
            items.remove(at: index)
            countable -= 1
            removed += 1
        }
        if removed > 0 {
            saveToDisk()
        }
    }

    /// 設定で最大件数を変更したあと、現在の件数に適用するために呼ぶ。
    func applyMaxItemCountFromSettings() {
        enforceMaxItems()
    }

    /// 履歴を全削除し、永続化も空で上書きする。
    func clearAllHistory() {
        items = []
        saveToDisk(immediate: true)
    }

    // MARK: - Persistence

    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.4
    private var saveGeneration: Int = 0

    /// 永続化。通常は 0.4 秒デバウンス。immediate == true は load 完了・終了時用。
    private func saveToDisk(immediate: Bool = false) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.saveToDisk(immediate: immediate) }
            return
        }
        let normalCount = items.filter { $0.kind == .normal }.count
        let placeholderCount = items.filter { $0.kind == .oversizedPlaceholder }.count
        LogCapture.record("[saveToDisk] 直前 — items.count: \(items.count), normal: \(normalCount), placeholder: \(placeholderCount), immediate: \(immediate)")
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        if immediate {
            let snapshot = items.filter { $0.kind == .normal }
            performWrite(snapshot: snapshot, completion: nil)
            return
        }
        saveGeneration += 1
        let generation = saveGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.saveGeneration != generation { return }
            self.pendingSaveWorkItem = nil
            let snapshot = self.items.filter { $0.kind == .normal }
            self.performWrite(snapshot: snapshot, completion: nil)
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    /// 渡された snapshot をバックグラウンドでエンコード・書き込む。保存前に current → backup へコピーする。
    /// 安全制限: data.count > maxTotalJSON の場合のみ古いアイテムを削除して再エンコード（UI件数とは別の二段階防御）。
    /// sourceAppIconData は永続化しない（TIFF が大きく合計で 100MB を超え、サイズ制限削除で他アイテムが消える不具合を防ぐ）。
    /// completion: 書き込み完了後に呼ぶ（saveToDiskAndWait で待機するために使用）
    private func performWrite(snapshot: [ClipboardItem], completion: (() -> Void)?) {
        let url = Self.persistenceFileURL
        let backupURL = Self.backupFileURL
        let maxTotalJSON = Self.maxTotalJSON

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            LogCapture.record("[saveToDisk] performWrite — 書き込む件数: \(snapshot.count)")
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            // 保存前に current → backup へコピー
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let currentData = try Data(contentsOf: url)
                    try currentData.write(to: backupURL, options: .atomic)
                    LogCapture.record("[ClipboardVM] backup: clipboard.json → backup.json (\(currentData.count) bytes)")
                } catch {
                    LogCapture.record("[ClipboardVM] backup failed (current → backup): \(error)")
                }
            }
            let encoder = JSONEncoder()
            var persistableItems = snapshot.map { item in
                var c = item
                c.sourceAppIconData = nil
                return c
            }
            var data: Data
            do {
                data = try encoder.encode(ClipboardStore(version: 1, items: persistableItems))
            } catch {
                LogCapture.record("[ClipboardVM] saveToDisk failed (encode): \(error)")
                completion?()
                return
            }
            if data.count > maxTotalJSON {
                LogCapture.record("[ClipboardVM] saveToDisk: JSON size \(data.count) > \(maxTotalJSON), trimming oldest items")
            }
            while data.count > maxTotalJSON && !persistableItems.isEmpty {
                let sorted = persistableItems.sorted { $0.createdAt < $1.createdAt }
                guard let toRemove = sorted.first(where: { !$0.isPinned }),
                      let idx = persistableItems.firstIndex(where: { $0.id == toRemove.id }) else { break }
                persistableItems.remove(at: idx)
                do {
                    data = try encoder.encode(ClipboardStore(version: 1, items: persistableItems))
                } catch {
                    LogCapture.record("[ClipboardVM] saveToDisk failed (re-encode): \(error)")
                    completion?()
                    return
                }
            }
            do {
                try data.write(to: url, options: .atomic)
                LogCapture.record("[ClipboardVM] saveToDisk success: \(persistableItems.count) items → \(url.path)")
            } catch {
                LogCapture.record("[ClipboardVM] saveToDisk failed (write): \(error)")
            }
            completion?()
        }
    }

    /// アプリ終了時に呼ぶ。保留中のデバウンスをキャンセルし、現在の items を書き込み完了まで待つ。
    func saveToDiskAndWait() {
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { saveToDiskAndWait() }
            return
        }
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        let snapshot = items.filter { $0.kind == .normal }
        let group = DispatchGroup()
        group.enter()
        performWrite(snapshot: snapshot) { group.leave() }
        group.wait()
    }

    /// 永続化ファイルから読み込み。失敗時は backup.json から復元を試みる。両方失敗時のみ空配列。
    /// ファイルI/O・decode はバックグラウンド、items 代入のみ main で実行。
    private func loadFromDisk() {
        let url = Self.persistenceFileURL
        let backupURL = Self.backupFileURL

        func decodeItems(from data: Data) -> [ClipboardItem]? {
            if let store = try? JSONDecoder().decode(ClipboardStore.self, from: data) {
                return store.items
            }
            if let legacy = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                return legacy
            }
            return nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let loaded: [ClipboardItem]
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    if let items = decodeItems(from: data) {
                        loaded = items
                        LogCapture.record("[ClipboardVM] loadFromDisk: decoded clipboard.json — \(items.count) items")
                    } else {
                        // decode 失敗 → backup から復元を試みる
                        if FileManager.default.fileExists(atPath: backupURL.path),
                           let backupData = try? Data(contentsOf: backupURL),
                           let items = decodeItems(from: backupData) {
                            loaded = items
                            LogCapture.record("[ClipboardVM] loadFromDisk: decode failed for clipboard.json, restored from backup.json — \(items.count) items")
                        } else {
                            loaded = []
                            LogCapture.record("[ClipboardVM] loadFromDisk: both clipboard.json and backup.json decode failed — using empty array")
                        }
                    }
                } catch {
                    LogCapture.record("[ClipboardVM] loadFromDisk: read error for clipboard.json: \(error)")
                    if FileManager.default.fileExists(atPath: backupURL.path),
                       let backupData = try? Data(contentsOf: backupURL),
                       let items = decodeItems(from: backupData) {
                        loaded = items
                        LogCapture.record("[ClipboardVM] loadFromDisk: restored from backup.json — \(items.count) items")
                    } else {
                        loaded = []
                        LogCapture.record("[ClipboardVM] loadFromDisk: both clipboard.json and backup.json failed — using empty array")
                    }
                }
            } else {
                if FileManager.default.fileExists(atPath: backupURL.path),
                   let backupData = try? Data(contentsOf: backupURL),
                   let items = decodeItems(from: backupData) {
                    loaded = items
                    LogCapture.record("[ClipboardVM] loadFromDisk: clipboard.json missing, loaded from backup.json — \(items.count) items")
                } else {
                    loaded = []
                    LogCapture.record("[ClipboardVM] loadFromDisk: no clipboard.json, backup unavailable or decode failed — using empty array")
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.items = loaded
                for index in self.items.indices {
                    if let bundleID = self.items[index].sourceBundleID,
                       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                        self.items[index].sourceAppIconData = icon.tiffRepresentation
                    }
                }
                self.enforceMaxItems()
                self.loadCompleted = true
                self.saveToDisk(immediate: true)
                self.monitor.startMonitoring()
            }
        }
    }
}

