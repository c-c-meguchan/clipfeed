import AppKit
import Combine
import Foundation

/// バックグラウンドキューで changeCount を監視し、解析もバックグラウンドで行う。
/// UI 更新（@Published の更新）のみ main で実行する。
class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    @Published var copiedText: String?
    @Published var imageData: Data?

    /// 2MB超でスキップしたときに ViewModel がプレースホルダを挿入するためにセットする。ViewModel が処理したら clearSkippedOversizedContent() でクリア。
    @Published var skippedOversizedContent: (sourceAppName: String?, sourceBundleID: String?, sourceAppIconData: Data?)?

    /// copiedText / imageData が発火した時点で ViewModel が同期的に読み取れるよう保持
    private(set) var latestRTFData: Data?
    private(set) var latestHTMLData: Data?
    private(set) var latestSourceAppName: String?
    private(set) var latestSourceBundleID: String?
    private(set) var latestSourceAppIconData: Data?

    /// ViewModel が再コピー・OCRコピー直前に true にセットする。スレッドセーフ。
    var isInternalCopy: Bool {
        get { lock.withLock { _isInternalCopy } }
        set { lock.withLock { _isInternalCopy = newValue } }
    }
    private var _isInternalCopy = false
    private let lock = NSLock()

    private let pasteboard = NSPasteboard.general
    private let queue = DispatchQueue(label: "clipboard.monitor", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    /// ViewModel が保持する lastChangeCount の get/set。タイマー内で比較・更新に使用
    private var changeCountGet: (() -> Int)?
    private var changeCountSet: ((Int) -> Void)?

    /// ViewModel の lastChangeCount プロパティを参照・更新するための provider を登録する
    func setChangeCountProvider(get: @escaping () -> Int, set: @escaping (Int) -> Void) {
        changeCountGet = get
        changeCountSet = set
    }

    /// skippedOversizedContent をクリア（ViewModel がプレースホルダ挿入後に呼ぶ）
    func clearSkippedOversizedContent() {
        skippedOversizedContent = nil
    }

    private init() {}

    func startMonitoring() {
        stopMonitoring()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 0.5)
        t.setEventHandler { [weak self] in
            self?.checkClipboard()
        }
        t.resume()
        timer = t
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }

    /// キュー上で実行。changeCount が変わったら 0.15 秒後に readClipboard を呼ぶ。
    /// lastChangeCount の更新は readClipboard 内で types が有効な場合のみ行う（空の change を消費しない）
    private func checkClipboard() {
        let current = pasteboard.changeCount
        let last = changeCountGet?() ?? -1
        guard current != last else { return }

        LogCapture.record("[ClipboardVM] change detected: \(current)")
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.readClipboard(expectedChangeCount: current)
        }
    }

    /// キュー上で実行。types が空なら lastChangeCount を更新せず return（次のポールで再試行）。
    /// types が有効な場合のみ lastChangeCount を更新してから解析する。
    private func readClipboard(expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return }

        LogCapture.record("Types: \(pasteboard.types ?? [])")
        guard let types = pasteboard.types, !types.isEmpty else { return }

        // types が存在する場合のみ lastChangeCount を更新（空の change を消費しない）
        changeCountSet?(expectedChangeCount)

        let rtf = pasteboard.data(forType: .rtf)
        let html = pasteboard.data(forType: .html)
        let text = pasteboard.string(forType: .string)

        var resolvedImageData: Data?
        if let d = pasteboard.data(forType: .png), !d.isEmpty {
            resolvedImageData = d.count <= ClipboardSizeLimit.maxContentBytes ? d : nil
            if d.count > ClipboardSizeLimit.maxContentBytes {
                LogCapture.record("[Clipboard] PNG skipped (size \(d.count) > \(ClipboardSizeLimit.maxContentBytes))")
            }
        } else if let d = pasteboard.data(forType: .tiff), !d.isEmpty {
            resolvedImageData = d.count <= ClipboardSizeLimit.maxContentBytes ? d : nil
            if d.count > ClipboardSizeLimit.maxContentBytes {
                LogCapture.record("[Clipboard] TIFF skipped (size \(d.count) > \(ClipboardSizeLimit.maxContentBytes))")
            }
        } else {
            resolvedImageData = nil
        }

        let hasImageData = resolvedImageData != nil
        let hasRTF = rtf != nil
        let hasHTML = html != nil
        let hasString = text != nil && !text!.isEmpty

        LogCapture.record("[Clipboard] hasRTF: \(hasRTF), hasHTML: \(hasHTML), hasString: \(hasString), hasImage: \(hasImageData)")
        LogCapture.record("Types: \(types)")

        let internalCopy = isInternalCopy
        if internalCopy {
            isInternalCopy = false
        }

        let source = internalCopy ? nil : resolveSourceOnQueue(hasImage: hasImageData, hasString: hasString, hasRTF: hasRTF, hasHTML: hasHTML)

        // ① 画像
        if let imgData = resolvedImageData {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.latestRTFData = nil
                self.latestHTMLData = nil
                self.latestSourceAppName = source?.name
                self.latestSourceBundleID = source?.bundleID
                self.latestSourceAppIconData = source?.iconData
                self.imageData = imgData
                self.copiedText = nil
            }
            LogCapture.record("Clipboard changed: [image]")
            return
        }

        // ② テキスト系（長文・巨大HTMLはメモリ負荷で落ちるため上限でスキップ）
        if hasRTF || hasString {
            let textSize = (text ?? "").utf8.count
            let rtfSize = rtf?.count ?? 0
            let htmlSize = html?.count ?? 0
            let totalSize = textSize + rtfSize + htmlSize
            if totalSize > ClipboardSizeLimit.maxContentBytes {
                LogCapture.record("[Clipboard] Text/RTF/HTML skipped (total \(totalSize) > \(ClipboardSizeLimit.maxContentBytes))")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.latestRTFData = nil
                    self.latestHTMLData = nil
                    self.copiedText = nil
                    self.imageData = nil
                    self.skippedOversizedContent = (source?.name, source?.bundleID, source?.iconData)
                }
                return
            }
            let rtfCopy = rtf
            let htmlCopy = html
            let textCopy = text ?? ""
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.latestRTFData = rtfCopy
                self.latestHTMLData = htmlCopy
                self.latestSourceAppName = source?.name
                self.latestSourceBundleID = source?.bundleID
                self.latestSourceAppIconData = source?.iconData
                self.copiedText = textCopy
                self.imageData = nil
            }
            let desc = text.map { $0.isEmpty ? "(empty)" : $0 } ?? (rtf != nil ? "[RTF]" : "[HTML]")
            LogCapture.record("Clipboard changed: \(desc)")
            return
        }

        // ③ HTML fallback（画像 URL 取得を試行）。巨大HTMLはスキップ。
        if hasHTML, let htmlData = html, let htmlString = String(data: htmlData, encoding: .utf8) {
            if htmlData.count > ClipboardSizeLimit.maxContentBytes {
                LogCapture.record("[Clipboard] HTML skipped (size \(htmlData.count) > \(ClipboardSizeLimit.maxContentBytes))")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.latestRTFData = nil
                    self.latestHTMLData = nil
                    self.copiedText = nil
                    self.imageData = nil
                    self.skippedOversizedContent = (source?.name, source?.bundleID, source?.iconData)
                }
                return
            }
            fetchImageFromHTML(htmlString, changeCount: expectedChangeCount, source: source)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestRTFData = nil
            self.latestHTMLData = nil
            self.copiedText = nil
            self.imageData = nil
        }
    }

    /// キュー上で実行。コピー元情報を返すだけ（self の latest* は更新しない）
    private func resolveSourceOnQueue(hasImage: Bool, hasString: Bool, hasRTF: Bool, hasHTML: Bool) -> (name: String?, bundleID: String?, iconData: Data?)? {
        let item = pasteboard.pasteboardItems?.first
        if item?.types.contains(where: { $0.rawValue == "com.apple.is-remote-clipboard" }) == true {
            LogCapture.record("Source: Universal Clipboard")
            return ("他のデバイス", "universal.clipboard", nil)
        }
        if hasImage && !hasString && !hasHTML && !hasRTF {
            LogCapture.record("Source: Screenshot")
            return ("スクリーンショット", "com.apple.screencapture", nil)
        }
        let app = NSWorkspace.shared.frontmostApplication
        LogCapture.record("Source: \(app?.localizedName ?? "Unknown")")
        return (app?.localizedName, app?.bundleIdentifier, app?.icon?.tiffRepresentation)
    }

    /// キュー上から呼ばれる。ダウンロード完了後は main で @Published を更新
    private func fetchImageFromHTML(_ htmlString: String, changeCount: Int, source: (name: String?, bundleID: String?, iconData: Data?)?) {
        let pattern = #"<img[^>]+src\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString)),
              let urlRange = Range(match.range(at: 1), in: htmlString) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.latestHTMLData = htmlString.data(using: .utf8)
                self.latestSourceAppName = source?.name
                self.latestSourceBundleID = source?.bundleID
                self.latestSourceAppIconData = source?.iconData
                self.copiedText = ""
                self.imageData = nil
            }
            LogCapture.record("Clipboard changed: [HTML text]")
            return
        }

        let urlString = String(htmlString[urlRange])
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.latestHTMLData = htmlString.data(using: .utf8)
                self.latestSourceAppName = source?.name
                self.latestSourceBundleID = source?.bundleID
                self.latestSourceAppIconData = source?.iconData
                self.copiedText = ""
                self.imageData = nil
            }
            LogCapture.record("Clipboard changed: [HTML text - invalid URL]")
            return
        }

        LogCapture.record("[Clipboard] Downloading image from HTML: \(urlString)")

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self, let data, error == nil, !data.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.latestHTMLData = htmlString.data(using: .utf8)
                    self.latestSourceAppName = source?.name
                    self.latestSourceBundleID = source?.bundleID
                    self.latestSourceAppIconData = source?.iconData
                    self.copiedText = ""
                    self.imageData = nil
                    LogCapture.record("[Clipboard] Image download failed, treating as HTML text")
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.pasteboard.changeCount == changeCount else {
                    LogCapture.record("[Clipboard] Image download completed but clipboard changed, discarding")
                    return
                }
                self.latestRTFData = nil
                self.latestHTMLData = nil
                self.latestSourceAppName = source?.name
                self.latestSourceBundleID = source?.bundleID
                self.latestSourceAppIconData = source?.iconData
                self.imageData = data
                self.copiedText = nil
                LogCapture.record("Clipboard changed: [image from HTML]")
            }
        }.resume()
    }

    deinit {
        stopMonitoring()
    }
}
