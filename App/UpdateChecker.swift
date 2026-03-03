import Foundation
import AppKit

/// 軽量アップデート確認。Sparkle は使わず、versionURL の JSON を取得して比較する。
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// 設定ウィンドウ(200)より前面に出すためのレベル
    private static let alertWindowLevel = NSWindow.Level(rawValue: 201)

    /// バージョン情報を取得する URL（要差し替え）
    private let versionURL = URL(string: "https://c-c-meguchan.github.io/clipfeed-site/version.json")!

    private init() {}

    /// 新バージョンなら NSAlert で通知。showNoUpdateAlert == true のときは「最新です」も表示。
    /// presentingWindow を渡すとそのウィンドウにシートとして表示し、確実に前面に出る（設定から呼ぶときに渡す）。
    func checkForUpdates(showNoUpdateAlert: Bool = false, presentingWindow: NSWindow? = nil) {
        let current = Bundle.main.appVersion
        let window = presentingWindow
        let task = URLSession.shared.dataTask(with: versionURL) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.handleResponse(current: current, data: data, error: error, showNoUpdateAlert: showNoUpdateAlert, presentingWindow: window)
            }
        }
        task.resume()
    }

    private func handleResponse(current: String, data: Data?, error: Error?, showNoUpdateAlert: Bool, presentingWindow: NSWindow? = nil) {
        if let error = error {
            if showNoUpdateAlert {
                showAlert(title: L("update_check_title", fallback: "Update"), message: "\(L("update_check_fetch_error", fallback: "Failed to fetch version info."))\n\(error.localizedDescription)", presentingWindow: presentingWindow)
            }
            return
        }
        guard let data = data,
              let info = try? JSONDecoder().decode(VersionInfo.self, from: data) else {
            if showNoUpdateAlert {
                showAlert(title: L("update_check_title", fallback: "Update"), message: L("update_check_fetch_error", fallback: "Failed to fetch version info."), presentingWindow: presentingWindow)
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

// MARK: - Bundle extension

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
