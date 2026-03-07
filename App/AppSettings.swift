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

    /// アクセントカラー識別子: "green" / "blue" / "purple" / "pink" / "orange" / "teal"。デフォルト "green"（アプリアイコンに合わせる）。
    static var accentColorId: String {
        get {
            let raw = UserDefaults.standard.string(forKey: accentColorKey) ?? "green"
            return Self.accentColorIds.contains(raw) ? raw : "green"
        }
        set {
            guard Self.accentColorIds.contains(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: accentColorKey)
            NotificationCenter.default.post(name: Self.accentColorDidChangeNotification, object: nil)
        }
    }

    static let accentColorIds = ["green", "blue", "purple", "pink", "orange", "teal"]
    static let accentColorDidChangeNotification = Notification.Name("AppSettings.accentColorDidChange")

    /// 指定した ID に対応する SwiftUI Color。ライトモード用は明度高めの macOS 風トーン、ダークモード用は暗い背景で映える色。
    static func accentColor(for id: String, colorScheme: ColorScheme) -> Color {
        let isDark = colorScheme == .dark
        switch id {
        case "purple":
            return isDark ? Color(red: 0.65, green: 0.45, blue: 0.9) : Color(red: 0.62, green: 0.44, blue: 0.82)
        case "orange":
            return isDark ? Color(red: 1.0, green: 0.65, blue: 0.2) : Color(red: 0.96, green: 0.58, blue: 0.32)
        case "green":
            return isDark ? Color(red: 0.35, green: 0.85, blue: 0.5) : Color(red: 0.32, green: 0.78, blue: 0.56)
        case "teal":
            return isDark ? Color(red: 0.4, green: 0.75, blue: 0.9) : Color(red: 0.34, green: 0.7, blue: 0.8)
        case "pink":
            return isDark ? Color(red: 0.95, green: 0.35, blue: 0.6) : Color(red: 0.88, green: 0.28, blue: 0.62)
        default: // blue（macOS 標準に近い明るい青）
            return isDark ? Color(red: 0.4, green: 0.6, blue: 1.0) : Color(red: 0.28, green: 0.48, blue: 0.96)
        }
    }

    /// 後方互換: colorScheme 未指定時はライトとして扱う（主に Environment のないテスト用）
    static func accentColor(for id: String) -> Color {
        accentColor(for: id, colorScheme: .light)
    }

    /// 指定した ID に対応する NSColor（メニューバーアイコンなど AppKit 用）。appearance に応じてライト/ダーク用の色を返す。
    static func accentNSColor(for id: String, appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSApp.effectiveAppearance
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        switch id {
        case "purple":
            return isDark ? NSColor(red: 0.65, green: 0.45, blue: 0.9, alpha: 1) : NSColor(red: 0.62, green: 0.44, blue: 0.82, alpha: 1)
        case "orange":
            return isDark ? NSColor(red: 1.0, green: 0.65, blue: 0.2, alpha: 1) : NSColor(red: 0.96, green: 0.58, blue: 0.32, alpha: 1)
        case "green":
            return isDark ? NSColor(red: 0.35, green: 0.85, blue: 0.5, alpha: 1) : NSColor(red: 0.32, green: 0.78, blue: 0.56, alpha: 1)
        case "teal":
            return isDark ? NSColor(red: 0.4, green: 0.75, blue: 0.9, alpha: 1) : NSColor(red: 0.34, green: 0.7, blue: 0.8, alpha: 1)
        case "pink":
            return isDark ? NSColor(red: 0.95, green: 0.35, blue: 0.6, alpha: 1) : NSColor(red: 0.88, green: 0.28, blue: 0.62, alpha: 1)
        default:
            return isDark ? NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1) : NSColor(red: 0.28, green: 0.48, blue: 0.96, alpha: 1)
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
            accentColorKey: "green",
        ])
    }
}
