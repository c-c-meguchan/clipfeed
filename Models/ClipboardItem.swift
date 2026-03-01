import Foundation

enum ClipboardItemKind: String, Codable, Equatable {
    case normal
    case oversizedPlaceholder
}

enum ClipboardType: String, Codable, Equatable {
    case text
    case image
    case html
    case file
}

/// 永続化用。version は必須（将来の互換性のため）。
struct ClipboardStore: Codable {
    let version: Int
    let items: [ClipboardItem]
}

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let createdAt: Date
    let kind: ClipboardItemKind
    let type: ClipboardType
    var text: String?
    var rtfData: Data?
    var htmlData: Data?
    var imageData: Data?
    var thumbnailData: Data?
    var fileURL: URL?
    var ocrText: String?
    var ocrResult: String?
    var isPinned: Bool
    var sourceAppName: String?
    var sourceBundleID: String?
    var sourceAppIconData: Data?
    var hasBeenReCopied: Bool = false
    /// OCR を試したが画像に文字が含まれていなかった場合 true（以後そのカードに Text ボタンを出さない）
    var ocrNoText: Bool = false

    /// プレーンテキスト。表示用に text も同期する（サイズは validateItemSize で 2MB 制限）
    var plainText: String?
    /// HTML文字列（Figma再ペースト用）。保存可否は validateItemSize で 2MB 制限
    var html: String?
    /// HTMLを保存した場合 true、サイズ超過で破棄した場合 false
    var figmaCompatible: Bool = false
    /// ペースト時にHTMLが存在したかどうか
    var hadHTML: Bool = false
    /// text + html + imageData の SHA256（直前同一判定・必ず保存）
    var contentHash: String?

    var dayKey: String {
        ClipboardItem.dayFormatter.string(from: createdAt)
    }
    
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ClipboardItemKind = .normal,
        type: ClipboardType,
        text: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        fileURL: URL? = nil,
        ocrText: String? = nil,
        ocrResult: String? = nil,
        isPinned: Bool = false,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        sourceAppIconData: Data? = nil,
        hasBeenReCopied: Bool = false,
        ocrNoText: Bool = false,
        plainText: String? = nil,
        html: String? = nil,
        figmaCompatible: Bool = false,
        hadHTML: Bool = false,
        contentHash: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.type = type
        self.text = text
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.fileURL = fileURL
        self.ocrText = ocrText
        self.ocrResult = ocrResult
        self.isPinned = isPinned
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.sourceAppIconData = sourceAppIconData
        self.hasBeenReCopied = hasBeenReCopied
        self.ocrNoText = ocrNoText
        self.plainText = plainText
        self.html = html
        self.figmaCompatible = figmaCompatible
        self.hadHTML = hadHTML
        self.contentHash = contentHash
    }

    // MARK: - Codable（永続化用。sourceAppIconData は含めず、load 後に NSWorkspace で再取得）

    enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, type, text, rtfData, htmlData, imageData, thumbnailData
        case fileURL, ocrText, ocrResult, isPinned
        case sourceAppName
        case sourceAppBundleIdentifier
        case sourceBundleID
        case hasBeenReCopied, ocrNoText, isOversized, errorReason
        case plainText, html, figmaCompatible, hadHTML, htmlDiscardedDueToSize, contentHash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        kind = try c.decodeIfPresent(ClipboardItemKind.self, forKey: .kind) ?? .normal
        type = try c.decode(ClipboardType.self, forKey: .type)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        rtfData = try c.decodeIfPresent(Data.self, forKey: .rtfData)
        htmlData = try c.decodeIfPresent(Data.self, forKey: .htmlData)
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        thumbnailData = try c.decodeIfPresent(Data.self, forKey: .thumbnailData)
        fileURL = try c.decodeIfPresent(URL.self, forKey: .fileURL)
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        ocrResult = try c.decodeIfPresent(String.self, forKey: .ocrResult)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceAppBundleIdentifier)
        if sourceBundleID == nil {
            sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        }
        sourceAppIconData = nil
        hasBeenReCopied = try c.decodeIfPresent(Bool.self, forKey: .hasBeenReCopied) ?? false
        ocrNoText = try c.decodeIfPresent(Bool.self, forKey: .ocrNoText) ?? false
        _ = try c.decodeIfPresent(Bool.self, forKey: .isOversized)
        _ = try c.decodeIfPresent(String.self, forKey: .errorReason)
        plainText = try c.decodeIfPresent(String.self, forKey: .plainText) ?? text
        html = try c.decodeIfPresent(String.self, forKey: .html)
        if html == nil, let data = try c.decodeIfPresent(Data.self, forKey: .htmlData) {
            html = String(data: data, encoding: .utf8)
        }
        figmaCompatible = try c.decodeIfPresent(Bool.self, forKey: .figmaCompatible) ?? (html != nil)
        hadHTML = try c.decodeIfPresent(Bool.self, forKey: .hadHTML) ?? (html != nil)
        _ = try c.decodeIfPresent(Bool.self, forKey: .htmlDiscardedDueToSize)
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(kind, forKey: .kind)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(rtfData, forKey: .rtfData)
        try c.encodeIfPresent(htmlData, forKey: .htmlData)
        try c.encodeIfPresent(imageData, forKey: .imageData)
        try c.encodeIfPresent(thumbnailData, forKey: .thumbnailData)
        try c.encodeIfPresent(fileURL, forKey: .fileURL)
        try c.encodeIfPresent(ocrText, forKey: .ocrText)
        try c.encodeIfPresent(ocrResult, forKey: .ocrResult)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        try c.encodeIfPresent(sourceBundleID, forKey: .sourceAppBundleIdentifier)
        try c.encode(hasBeenReCopied, forKey: .hasBeenReCopied)
        try c.encode(ocrNoText, forKey: .ocrNoText)
        try c.encodeIfPresent(plainText, forKey: .plainText)
        try c.encodeIfPresent(html, forKey: .html)
        try c.encode(figmaCompatible, forKey: .figmaCompatible)
        try c.encode(hadHTML, forKey: .hadHTML)
        try c.encodeIfPresent(contentHash, forKey: .contentHash)
    }
}
