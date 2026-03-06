import Foundation
import AppKit
import SwiftUI

/// ClipFeed の設定キーとデフォルト値。UserDefaults で永続化する。
enum AppSettings {
    static let maxItemCountKey = "maxItems"
    static let launchAtLoginKey = "ClipFeed.launchAtLogin"
    static let appearanceModeKey = "ClipFeed.appearanceMode"
    static let appLanguageKey = "ClipFeed.appLanguage"
    static let accentColorKey = "ClipFeed.accentColor"

    static let maxItemCountOptions = [10, 30, 50, 100]
    static let defaultMaxItemCount = 50

    /// アクセントカラー識別子: "blue" / "purple" / "orange" / "green" / "teal"。デフォルト "blue"。
    static var accentColorId: String {
        get {
            let raw = UserDefaults.standard.string(forKey: accentColorKey) ?? "blue"
            return Self.accentColorIds.contains(raw) ? raw : "blue"
        }
        set {
            guard Self.accentColorIds.contains(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: accentColorKey)
            NotificationCenter.default.post(name: Self.accentColorDidChangeNotification, object: nil)
        }
    }

    static let accentColorIds = ["blue", "purple", "orange", "green", "teal"]
    static let accentColorDidChangeNotification = Notification.Name("AppSettings.accentColorDidChange")

    /// 指定した ID に対応する SwiftUI Color（macOS 風、赤は含めない）
    static func accentColor(for id: String) -> Color {
        switch id {
        case "purple": return Color(red: 0.61, green: 0.35, blue: 0.71)
        case "orange": return Color(red: 1.0, green: 0.58, blue: 0.0)
        case "green": return Color(red: 0.2, green: 0.78, blue: 0.35)
        case "teal": return Color(red: 0.35, green: 0.68, blue: 0.77)
        default: return Color(red: 0.25, green: 0.47, blue: 0.98) // blue (macOS standard)
        }
    }

    /// 指定した ID に対応する NSColor（メニューバーアイコンなど AppKit 用）
    static func accentNSColor(for id: String) -> NSColor {
        switch id {
        case "purple": return NSColor(red: 0.61, green: 0.35, blue: 0.71, alpha: 1)
        case "orange": return NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1)
        case "green": return NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
        case "teal": return NSColor(red: 0.35, green: 0.68, blue: 0.77, alpha: 1)
        default: return NSColor(red: 0.25, green: 0.47, blue: 0.98, alpha: 1)
        }
    }

    /// アプリの表示言語: "system"（端末の言語） / "ja" / "en"。日本語・英語以外の端末では system 時は英語にフォールバック。
    static var appLanguage: String {
        get {
            let raw = UserDefaults.standard.string(forKey: appLanguageKey) ?? "system"
            return ["system", "ja", "en"].contains(raw) ? raw : "system"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: appLanguageKey)
            NotificationCenter.default.post(name: Self.appLanguageDidChangeNotification, object: nil)
        }
    }

    static let appLanguageDidChangeNotification = Notification.Name("AppSettings.appLanguageDidChange")

    /// カラーモード: "system" / "light" / "dark"。デフォルトは "system"（端末の設定に従う）。
    static var appearanceMode: String {
        get {
            let raw = UserDefaults.standard.string(forKey: appearanceModeKey) ?? "system"
            return ["system", "light", "dark"].contains(raw) ? raw : "system"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: appearanceModeKey)
        }
    }

    /// 保存されている appearanceMode を NSApp に反映する。起動時と設定変更時に呼ぶ。
    static func applyAppearance() {
        switch appearanceMode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
        NotificationCenter.default.post(name: Self.appearanceDidChangeNotification, object: nil)
    }

    /// ポップオーバーなどに設定するための NSAppearance。system のときは nil（アプリに従う）。
    static func resolvedAppearance() -> NSAppearance? {
        switch appearanceMode {
        case "light":
            return NSAppearance(named: .aqua)
        case "dark":
            return NSAppearance(named: .darkAqua)
        default:
            return nil
        }
    }

    /// カラーモード変更時にポップオーバー側で受け取る通知
    static let appearanceDidChangeNotification = Notification.Name("AppSettings.appearanceDidChange")

    /// 最大保存件数（10/30/50/100）。未設定時は defaultMaxItemCount（50）。
    static var maxItemCount: Int {
        get {
            let n = UserDefaults.standard.integer(forKey: maxItemCountKey)
            return maxItemCountOptions.contains(n) ? n : defaultMaxItemCount
        }
        set {
            UserDefaults.standard.set(newValue, forKey: maxItemCountKey)
        }
    }

    /// 起動時に自動起動するか。デフォルト true。
    static var launchAtLogin: Bool {
        get {
            if UserDefaults.standard.object(forKey: launchAtLoginKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: launchAtLoginKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
        }
    }

    /// 初回起動時にデフォルト値を登録する。AppDelegate の applicationDidFinishLaunching で呼ぶ。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            maxItemCountKey: defaultMaxItemCount,
            launchAtLoginKey: true,
            appearanceModeKey: "system",
            appLanguageKey: "system",
            accentColorKey: "blue",
        ])
    }
}
