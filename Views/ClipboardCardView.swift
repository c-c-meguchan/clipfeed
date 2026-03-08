import SwiftUI
import AppKit

/// サムネイル画像表示サブビュー。
/// 80×80 の小さなサムネイルは NSImage(data:) の生成コストが無視できるため、
/// @State キャッシュは使わず body 内で直接生成する（onAppear 待ちによる
/// 表示欠落を防ぐためのシンプルな設計）。
private struct CachedThumbnailView: View {
    let data: Data?
    let isHighlit: Bool
    @Environment(\.appAccentColor) private var appAccentColor
    static let size: CGFloat = 80

    var body: some View {
        Group {
            if let data, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size, height: Self.size)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .fill(appAccentColor.opacity(isHighlit ? 0.35 : 0))
                            // withAnimation を使わず、このビューだけに animation を閉じ込める
                            .animation(
                                isHighlit ? .easeIn(duration: 0.2) : .easeOut(duration: 0.8),
                                value: isHighlit
                            )
                    )
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}

struct ClipboardCardView: View {
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel
    @Environment(\.appAccentColor) private var appAccentColor
    let item: ClipboardItem
    let index: Int

    private static let displayLength = 120
    private static let thumbnailSize: CGFloat = 80
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var isFocused: Bool {
        clipboardViewModel.focusedItemID == item.id && !clipboardViewModel.isSearchFieldActuallyFirstResponder
    }

    /// 親カード（通常コピー）のハイライト判定 — .parent(item.id) の完全一致のみ
    private var isCardHighlighted: Bool {
        clipboardViewModel.highlightedTarget == .parent(item.id)
    }
    /// OCR プレビュー専用のハイライト判定 — .ocr(item.id) の完全一致のみ
    private var isOCRHighlighted: Bool {
        clipboardViewModel.highlightedTarget == .ocr(item.id)
    }

    // withAnimation を使うと全カードにアニメーションが波及するため、
    // @State Bool を onChange で直接変化させ、animation は各ビューに局所付与する。
    @State private var cardIsHighlit: Bool = false
    @State private var ocrIsHighlit: Bool = false

    var body: some View {
        Group {
            if item.kind == .oversizedPlaceholder {
                placeholderCard
            } else {
                normalCard
            }
        }
        .contentShape(Rectangle())
        .onChange(of: isCardHighlighted) { newValue in
            cardIsHighlit = newValue
        }
        .onChange(of: isOCRHighlighted) { newValue in
            ocrIsHighlit = newValue
        }
        .onTapGesture {
            guard item.kind == .normal else { return }
            clipboardViewModel.reCopyItem(item)
        }
    }

    /// サイズ超過プレースホルダー用：メッセージのみ・薄く表示・再コピー不可
    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("oversized_placeholder_message", fallback: "⚠ Cannot re-copy: over 2MB"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    createdLabel
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .opacity(0.6)
    }

    private var normalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // コンテンツ部分のみ hasBeenReCopied の opacity を適用（サムネイル・テキストのみ。ダウンロードボタンは薄くしない）
                    Group {
                        if item.type == .image {
                            ZStack(alignment: .bottomLeading) {
                                imageThumbnail
                                    .opacity(item.hasBeenReCopied ? 0.5 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: item.hasBeenReCopied)
                                Button {
                                    clipboardViewModel.saveImageItemToFile(item)
                                } label: {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                                        .frame(width: 22, height: 22)
                                        .background(Color.black.opacity(0.4))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                            }
                        } else {
                            textLabel
                                .foregroundColor(cardIsHighlit ? appAccentColor : .primary)
                                .animation(
                                    cardIsHighlit ? .easeIn(duration: 0.2) : .easeOut(duration: 0.8),
                                    value: cardIsHighlit
                                )
                                .opacity(item.hasBeenReCopied ? 0.5 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: item.hasBeenReCopied)
                        }
                    }

                    createdLabel
                }
                Spacer()
                actionButtons
            }

            if let ocrResult = item.ocrResult {
                ocrResultView(ocrResult)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(appAccentColor.opacity(isFocused ? 0.9 : 0), lineWidth: 2)
        )
    }

    private func ocrResultView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                Rectangle()
                    .fill(appAccentColor.opacity(0.6))
                    .frame(width: 2)
                Text(text)
                    .font(.caption)
                    .foregroundColor(ocrIsHighlit ? appAccentColor : .secondary)
                    .animation(
                        ocrIsHighlit ? .easeIn(duration: 0.2) : .easeOut(duration: 0.8),
                        value: ocrIsHighlit
                    )
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(0.5)
            if index >= 0 && index < 9 {
                ocrCopyButton(label: "\(L("copy", fallback: "Copy")) ⌘⌥\(index + 1)")
            } else {
                ocrCopyButton(label: L("copy", fallback: "Copy"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            appAccentColor.opacity(ocrIsHighlit ? 0.26 : 0.06)
                .animation(
                    ocrIsHighlit ? .easeIn(duration: 0.2) : .easeOut(duration: 0.8),
                    value: ocrIsHighlit
                )
        )
        .cornerRadius(4)
    }

    /// 再コピー用。フォーカス中は [Copy Enter]/[Image Enter]、それ以外は [Copy ⌘N]/[Image ⌘N]。画像用 [Text ⌘⌥N] は変化なし。
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            if isFocused {
                Button(item.type == .image && item.ocrResult == nil ? "\(L("image", fallback: "Image")) ↩" : "\(L("copy", fallback: "Copy")) ↩") {
                    clipboardViewModel.reCopyItem(item)
                }
                .buttonStyle(ShortcutButtonStyle(accentColor: appAccentColor))
            } else if index >= 0 && index < 9 {
                Button(item.type == .image && item.ocrResult == nil ? "\(L("image", fallback: "Image")) ⌘\(index + 1)" : "\(L("copy", fallback: "Copy")) ⌘\(index + 1)") {
                    clipboardViewModel.reCopyItem(item)
                }
                .buttonStyle(ShortcutButtonStyle())
            } else {
                Button(item.type == .image && item.ocrResult == nil ? L("image", fallback: "Image") : L("copy", fallback: "Copy")) {
                    clipboardViewModel.reCopyItem(item)
                }
                .buttonStyle(ShortcutButtonStyle())
            }
            if item.type == .image && item.ocrResult == nil && !item.ocrNoText {
                if isFocused {
                    Button("\(L("text", fallback: "Text")) ⌥↩") {
                        clipboardViewModel.ocrCopy(item)
                    }
                    .buttonStyle(ShortcutButtonStyle(accentColor: appAccentColor))
                } else if index >= 0 && index < 9 {
                    Button("\(L("text", fallback: "Text")) ⌘⌥\(index + 1)") {
                        clipboardViewModel.ocrCopy(item)
                    }
                    .buttonStyle(ShortcutButtonStyle(accentColor: nil))
                } else {
                    Button(L("text", fallback: "Text")) {
                        clipboardViewModel.ocrCopy(item)
                    }
                    .buttonStyle(ShortcutButtonStyle(accentColor: nil))
                }
            }
        }
    }

    private func ocrCopyButton(label: String) -> some View {
        Button(label) {
            clipboardViewModel.ocrCopy(item)
        }
        .buttonStyle(ShortcutButtonStyle())
    }

    private var imageThumbnail: some View {
        CachedThumbnailView(data: item.thumbnailData, isHighlit: cardIsHighlit)
    }

    private var textLabel: some View {
        let raw = item.text ?? ""
        let display = raw.count > Self.displayLength
            ? String(raw.prefix(Self.displayLength)) + "…"
            : raw
        return Text(display)
            .lineLimit(3)
            .font(.body)
    }

    private var createdLabel: some View {
        CreatedLabelContent(
            iconData: item.sourceAppIconData,
            appName: localizedSourceName(item.sourceAppName) ?? item.sourceAppName,
            createdAt: item.createdAt
        )
        .equatable()
    }
}

/// アイコン・アプリ名・日付。Equatable により入力が同じなら再描画をスキップし、他カードの hasBeenReCopied 更新時のちらつきを防ぐ
private struct CreatedLabelContent: View, Equatable {
    let iconData: Data?
    let appName: String?
    let createdAt: Date

    /// 検証用: true にすると body 実行ごとに [CreatedLabel] body 実行 をコンソールへ出力（本番は false）
    static var logCreatedLabelRenders = false

    static func == (lhs: CreatedLabelContent, rhs: CreatedLabelContent) -> Bool {
        lhs.iconData == rhs.iconData && lhs.appName == rhs.appName && lhs.createdAt == rhs.createdAt
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 3) {
            if let iconData = iconData,
               let nsIcon = NSImage(data: iconData) {
                Image(nsImage: nsIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
            }
            if let appName = appName {
                Text(appName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(Self.dateFormatter.string(from: createdAt))
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .animation(nil, value: createdAt)
        .drawingGroup()
        .background(CreatedLabelRenderLog())
    }
}

/// [Copy ⌘1] / [Text ⌘⌥1] 用の小さなボタンスタイル。accentColor を渡すと背景をアクセント・文字を白にする（フォーカス中のカード用）。
private struct ShortcutButtonStyle: ButtonStyle {
    var accentColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(accentColor != nil ? .white : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Group {
                    if let accent = accentColor {
                        accent.opacity(configuration.isPressed ? 0.85 : 1.0)
                    } else {
                        Color.secondary.opacity(configuration.isPressed ? 0.2 : 0.08)
                    }
                }
            )
            .cornerRadius(4)
    }
}

/// 検証用: body 実行のたびに 1 行ログ。CreatedLabelContent.logCreatedLabelRenders を true にすると有効
private struct CreatedLabelRenderLog: View {
    var body: some View {
        if CreatedLabelContent.logCreatedLabelRenders {
            let _ = LogCapture.record("[CreatedLabel] body 実行")
        }
        return EmptyView()
    }
}

#Preview {
    ClipboardCardView(
        item: ClipboardItem(
            createdAt: Date(),
            type: .text,
            text: "サンプルテキスト"
        ),
        index: 0
    )
    .environmentObject(ClipboardViewModel())
    .frame(width: 360)
}
