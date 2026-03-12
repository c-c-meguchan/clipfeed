import Foundation

extension Bundle {
    /// アプリのバージョン文字列（CFBundleShortVersionString）
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 実行元の種類とフルパス。設定画面・診断ログ用。
    /// 「お化けビルド」の原因特定のため、アプリフォルダ / Xcode(DerivedData) / その他 を判別する。
    var launchSourceInfo: (description: String, path: String) {
        let path = bundlePath
        if path.contains("DerivedData") {
            return (L("launch_source_xcode", fallback: "Xcode build (development)"), path)
        }
        if path.hasPrefix("/Applications") {
            return (L("launch_source_apps", fallback: "Applications folder"), path)
        }
        return (L("launch_source_other", fallback: "Other"), path)
    }

    /// 起動元を UI に表示してよいか。製品版（アプリフォルダ）では false、開発ビルドなどでは true。
    var launchSourceVisibleInUI: Bool {
        !bundlePath.hasPrefix("/Applications")
    }
}
