import Foundation
import AppKit

/// 軽量アップデート確認。GitHub Releases の latest を取得し、バージョン比較して .dmg を開く。
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// 設定ウィンドウ(200)より前面に出すためのレベル
    private static let alertWindowLevel = NSWindow.Level(rawValue: 201)

    /// GitHub の owner/repo（本体リポジトリ）。例: "c-c-meguchan/clipfeed"
    private let githubRepository = "c-c-meguchan/clipfeed"

    private var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepository)/releases/latest")!
    }

    private init() {}

    /// 新バージョンなら NSAlert で通知。showNoUpdateAlert == true のときは「最新です」も表示。
    /// presentingWindow を渡すとそのウィンドウにシートとして表示し、確実に前面に出る（設定から呼ぶときに渡す）。
    func checkForUpdates(showNoUpdateAlert: Bool = false, presentingWindow: NSWindow? = nil) {
        let current = Bundle.main.appVersion
        let window = presentingWindow
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClipFeed-Updater", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleResponse(current: current, data: data, response: response, error: error, showNoUpdateAlert: showNoUpdateAlert, presentingWindow: window)
            }
        }
        task.resume()
    }

    private func handleResponse(current: String, data: Data?, response: URLResponse?, error: Error?, showNoUpdateAlert: Bool, presentingWindow: NSWindow? = nil) {
        if let error = error {
            if showNoUpdateAlert {
                showAlert(title: L("update_check_title", fallback: "Update"), message: "\(L("update_check_fetch_error", fallback: "Failed to fetch version info."))\n\(error.localizedDescription)", presentingWindow: presentingWindow)
            }
            return
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if showNoUpdateAlert {
                let message: String
                if http.statusCode == 404 {
                    message = L("update_check_no_releases", fallback: "No releases found for this repository, or the repository does not exist.")
                } else {
                    message = "\(L("update_check_fetch_error", fallback: "Failed to fetch version info.")) (HTTP \(http.statusCode))"
                }
                showAlert(title: L("update_check_title", fallback: "Update"), message: message, presentingWindow: presentingWindow)
            }
            return
        }
        guard let data = data,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            if showNoUpdateAlert {
                showAlert(title: L("update_check_title", fallback: "Update"), message: L("update_check_fetch_error", fallback: "Failed to fetch version info."), presentingWindow: presentingWindow)
            }
            return
        }
        guard let info = release.toVersionInfo() else {
            if showNoUpdateAlert {
                showAlert(title: L("update_check_title", fallback: "Update"), message: L("update_check_no_dmg", fallback: "The latest release has no DMG file attached."), presentingWindow: presentingWindow)
            }
            return
        }
        let latest = info.latest_version
        if isVersion(current, lessThan: latest) {
            showUpdateAlert(info: info, presentingWindow: presentingWindow)
        } else if showNoUpdateAlert {
            showAlert(title: L("update_check_title", fallback: "Update"), message: L("update_latest", fallback: "You're on the latest version."), presentingWindow: presentingWindow)
        }
    }

    /// セマンティックバージョン風の数値比較（例: "1.2.3" vs "1.2.10"）
    private func isVersion(_ current: String, lessThan latest: String) -> Bool {
        let c = numericVersionComponents(current)
        let l = numericVersionComponents(latest)
        for i in 0..<max(c.count, l.count) {
            let cv = i < c.count ? c[i] : 0
            let lv = i < l.count ? l[i] : 0
            if cv < lv { return true }
            if cv > lv { return false }
        }
        return false
    }

    private func numericVersionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }

    private func showUpdateAlert(info: VersionInfo, presentingWindow: NSWindow? = nil) {
        let notes = info.release_notes.map { "\n\n\($0)" } ?? ""
        let message = String(format: L("update_available_message", fallback: "Version %@ is now available."), info.latest_version) + notes
        let alert = NSAlert()
        alert.messageText = L("update_available", fallback: "Update available")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("update_download", fallback: "Download"))
        alert.addButton(withTitle: L("update_later", fallback: "Later"))
        if let win = presentingWindow {
            alert.beginSheetModal(for: win) { response in
                if response == .alertFirstButtonReturn,
                   let url = URL(string: info.download_url) {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            applyAlertWindowLevel(alert)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: info.download_url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showAlert(title: String, message: String, presentingWindow: NSWindow? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("alert_ok", fallback: "OK"))
        if let win = presentingWindow {
            alert.beginSheetModal(for: win) { _ in }
        } else {
            applyAlertWindowLevel(alert)
            alert.runModal()
        }
    }

    private func applyAlertWindowLevel(_ alert: NSAlert) {
        alert.window.level = Self.alertWindowLevel
    }
}

// MARK: - GitHub Releases API

private struct GitHubRelease: Decodable {
    let tag_name: String
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }

    /// tag_name（先頭の "v" を除く）と .dmg の URL を VersionInfo に変換。.dmg がなければ nil。
    func toVersionInfo() -> VersionInfo? {
        let version = tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
        guard let dmg = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else { return nil }
        return VersionInfo(
            latest_version: version,
            download_url: dmg.browser_download_url,
            release_notes: body
        )
    }
}

// MARK: - Bundle extension

extension Bundle {
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
