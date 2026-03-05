import Foundation

// MARK: - Effective language

func effectiveAppLanguage() -> String {
    let setting = AppSettings.appLanguage
    if setting == "ja" { return "ja" }
    if setting == "en" { return "en" }
    let preferred = Bundle.preferredLocalizations(from: ["en", "ja"]).first ?? "en"
    return preferred == "ja" ? "ja" : "en"
}

// MARK: - Strings cache (load .strings files ourselves; no dependency on NSLocalizedString)

/// ファイル読み込みが全て失敗した場合に使う埋め込み辞書（設定で日本語を選んだときに確実に表示するため）
private let embeddedJA: [String: String] = [
    "settings": "設定", "close": "閉じる", "copy": "コピー", "app_version": "バージョン", "check_update": "アップデートを確認",
    "app_language": "アプリの言語", "app_language_system": "端末の言語（デフォルト）", "app_language_ja": "日本語", "app_language_en": "英語",
    "about_app_version": "アプリバージョン", "support_developer": "開発者を支援", "clear_history_title": "履歴を全削除", "delete": "削除", "cancel": "キャンセル",
    "clear_history_message": "クリップボード履歴をすべて削除します。この操作は取り消せません。", "color_mode": "カラーモード", "color_mode_system": "端末の設定",
    "color_mode_light": "ライト", "color_mode_dark": "ダーク", "max_items_label": "最大保存件数", "items_count_format": "%d件",
    "launch_at_login": "起動時に自動起動", "clear_history_button": "履歴を全削除", "buy_me_coffee": "コーヒーを送る", "loading": "読み込み中…",
    "filter_all": "すべて", "source_other_devices": "他のデバイス", "source_screenshot": "スクリーンショット", "image": "画像", "text": "テキスト",
    "support_developer_message": "このアプリは、自分用に作ったお気に入りツールがどこかの誰かの役にも立ったらハッピー！という思いで運営しています。継続のために応援してくれると嬉しいです！",
    "oversized_placeholder_message": "⚠ 2MBを超えているため再コピーできません", "toast_no_text": "テキストがありません", "toast_saved": "保存しました",
    "toast_save_failed": "保存に失敗しました", "toast_copied": "クリップボードにコピーしました", "update_check_title": "アップデート確認",
    "update_check_fetch_error": "バージョン情報の取得に失敗しました。", "update_available": "アップデートがあります", "update_download": "ダウンロード",
    "update_later": "あとで", "update_latest": "現在が最新バージョンです。", "alert_ok": "OK",
    "update_available_message": "新しいバージョン %@ が利用可能です。", "copied_from": "コピー元",
    "search_placeholder": "コピー履歴を検索",
]

private enum StringsCache {
    private static let lock = NSLock()
    private static var en: [String: String]?
    private static var ja: [String: String]?

    static func dictionary(for lang: String) -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        switch lang {
        case "en":
            if let en = en { return en }
            let loaded = loadStrings(lang: "en")
            en = loaded
            return loaded
        case "ja":
            if let ja = ja { return ja }
            let loaded = loadStrings(lang: "ja")
            ja = loaded ?? embeddedJA
            return ja!
        default:
            return dictionary(for: "en")
        }
    }

    /// バンドル内の lang.lproj/Localizable.strings を読み、[key: value] で返す。
    private static func loadStrings(lang: String) -> [String: String]? {
        // 1) path(forResource:ofType:inDirectory:)
        if let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "\(lang).lproj"),
           let dict = loadStringsFile(path: path) {
            return dict
        }
        // 2) url(forResource:withExtension:subdirectory:)
        if let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(lang).lproj"),
           let dict = loadStringsFile(url: url) {
            return dict
        }
        // 3) lproj バンドル経由
        if let lprojURL = Bundle.main.url(forResource: lang, withExtension: "lproj"),
           let lproj = Bundle(url: lprojURL),
           let path = lproj.path(forResource: "Localizable", ofType: "strings"),
           let dict = loadStringsFile(path: path) {
            return dict
        }
        // 4) バンドルパスを直接組み立て（Xcode の検索が失敗する場合）
        let base = Bundle.main.bundlePath as NSString
        let directPath = base.appendingPathComponent("Contents/Resources/\(lang).lproj/Localizable.strings")
        if FileManager.default.fileExists(atPath: directPath), let dict = loadStringsFile(path: directPath) {
            return dict
        }
        // 5) resourcePath から直接（Bundle 検索が全て失敗する場合）
        if let resPath = Bundle.main.resourcePath {
            let path = (resPath as NSString).appendingPathComponent("\(lang).lproj/Localizable.strings")
            if FileManager.default.fileExists(atPath: path), let dict = loadStringsFile(path: path) {
                return dict
            }
        }
        return nil
    }

    private static func loadStringsFile(path: String) -> [String: String]? {
        (NSDictionary(contentsOfFile: path) as? [String: String])
            ?? parseStringsFile(path: path)
    }

    private static func loadStringsFile(url: URL) -> [String: String]? {
        (NSDictionary(contentsOf: url) as? [String: String])
            ?? parseStringsFile(url: url)
    }

    /// .strings を手動パース（UTF-8 や NSDictionary が失敗する場合のフォールバック）
    private static func parseStringsFile(path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return parseStringsData(data)
    }

    private static func parseStringsFile(url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseStringsData(data)
    }

    private static func parseStringsData(_ data: Data) -> [String: String]? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .unicode]
        for encoding in encodings {
            if let content = String(data: data, encoding: encoding) {
                let result = parseStringsContent(content)
                if !result.isEmpty { return result }
            }
        }
        return nil
    }

    private static func parseStringsContent(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("/*"), !trimmed.hasPrefix("//") else { continue }
            // "key" = "value"; または "key"="value";
            guard trimmed.contains("=") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let keyPart = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var valuePart = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if valuePart.hasSuffix(";") { valuePart.removeLast() }
            valuePart = valuePart.trimmingCharacters(in: .whitespaces)
            guard keyPart.hasPrefix("\""), keyPart.hasSuffix("\""),
                  valuePart.hasPrefix("\""), valuePart.hasSuffix("\"") else { continue }
            let key = String(keyPart.dropFirst().dropLast())
            let value = String(valuePart.dropFirst().dropLast())
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
            result[key] = value
        }
        return result
    }
}

// MARK: - Public API

func L(_ key: String, fallback value: String) -> String {
    let lang = effectiveAppLanguage()
    if let dict = StringsCache.dictionary(for: lang), let s = dict[key] {
        return s
    }
    return value
}

func localizedSourceName(_ name: String?) -> String? {
    guard let name = name, !name.isEmpty else { return name }
    if name == "他のデバイス" || name == "Other devices" { return L("source_other_devices", fallback: "Other devices") }
    if name == "スクリーンショット" || name == "Screenshot" { return L("source_screenshot", fallback: "Screenshot") }
    return name
}

// MARK: - Observer (UI refresh on language change)

final class AppLanguageObserver: ObservableObject {
    static let shared = AppLanguageObserver()

    @Published private(set) var currentLanguage: String
    /// 言語変更のたびに増やす。別ウィンドウのビューが .id() で確実に再描画されるようにする
    @Published private(set) var languageChangeSeed: Int = 0

    private init() {
        self.currentLanguage = effectiveAppLanguage()
        NotificationCenter.default.addObserver(
            forName: AppSettings.appLanguageDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let newLang = effectiveAppLanguage()
            self.currentLanguage = newLang
            self.languageChangeSeed += 1
            // 別ウィンドウ（ポップオーバー）の SwiftUI が更新を拾うよう、次のランループで再通知する
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
}
