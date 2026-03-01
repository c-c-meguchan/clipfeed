import Foundation

/// アップデート確認用のリモート JSON レスポンス。
struct VersionInfo: Decodable {
    let latest_version: String
    let download_url: String
    let release_notes: String?
}
