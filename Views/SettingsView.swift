import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// 設定画面。左サイドバーに大メニュー（設定 / アプリバージョン）、右に小メニューと内容。
struct SettingsView: View {
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel
    @Environment(\.appAccentColor) private var appAccentColor

    enum SidebarItem: String, CaseIterable {
        case settings
        case shortcuts
        case about
        case support
        case contact

        var displayTitle: String {
            switch self {
            case .settings: return L("settings", fallback: "Settings")
            case .shortcuts: return L("shortcuts", fallback: "Shortcuts")
            case .about: return L("about_app_version", fallback: "App Version")
            case .support: return L("support_developer", fallback: "Support Developer")
            case .contact: return L("contact_tab", fallback: "Contact")
            }
        }

        var iconName: String {
            switch self {
            case .settings: return "gearshape.fill"
            case .shortcuts: return "keyboard"
            case .about: return "info.circle.fill"
            case .support: return "heart.fill"
            case .contact: return "envelope.fill"
            }
        }
    }

    @State private var selectedSection: SidebarItem = .settings
    @State private var maxItemCount: Int = AppSettings.maxItemCount
    @State private var launchAtLogin: Bool = AppSettings.launchAtLogin
    @State private var appearanceMode: String = AppSettings.appearanceMode
    @State private var appLanguage: String = AppSettings.appLanguage
    @State private var accentColorId: String = AppSettings.accentColorId
    @State private var showClearConfirm = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selectedSection) { item in
                Label {
                    Text(item.displayTitle)
                } icon: {
                    Image(systemName: item.iconName)
                        .foregroundColor(appAccentColor)
                }
                .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedSection {
                case .settings:
                    settingsDetail
                case .shortcuts:
                    shortcutsDetail
                case .about:
                    aboutDetail
                case .support:
                    supportDetail
                case .contact:
                    contactDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .onAppear {
            maxItemCount = AppSettings.maxItemCount
            launchAtLogin = AppSettings.launchAtLogin
            appearanceMode = AppSettings.appearanceMode
            appLanguage = AppSettings.appLanguage
            accentColorId = AppSettings.accentColorId
        }
        .confirmationDialog(L("clear_history_title", fallback: "Clear all history"), isPresented: $showClearConfirm) {
            Button(L("delete", fallback: "Delete"), role: .destructive) {
                clipboardViewModel.clearAllHistory()
                showClearConfirm = false
            }
            Button(L("cancel", fallback: "Cancel"), role: .cancel) {
                showClearConfirm = false
            }
        } message: {
            Text(L("clear_history_message", fallback: "All clipboard history will be deleted. This action cannot be undone."))
        }
    }

    private var settingsDetail: some View {
        Form {
            Section {
                Text(L("settings", fallback: "Settings"))
                    .font(.headline)
            }
            Section {
                Picker(L("app_language", fallback: "App language"), selection: $appLanguage) {
                    Text(L("app_language_system", fallback: "System language (default)")).tag("system")
                    Text(L("app_language_ja", fallback: "Japanese")).tag("ja")
                    Text(L("app_language_en", fallback: "English")).tag("en")
                }
                .onChange(of: appLanguage) { newValue in
                    AppSettings.appLanguage = newValue
                }

                Picker(L("color_mode", fallback: "Color mode"), selection: $appearanceMode) {
                    Text(L("color_mode_system", fallback: "System settings")).tag("system")
                    Text(L("color_mode_light", fallback: "Light")).tag("light")
                    Text(L("color_mode_dark", fallback: "Dark")).tag("dark")
                }
                .onChange(of: appearanceMode) { newValue in
                    AppSettings.appearanceMode = newValue
                    AppSettings.applyAppearance()
                }

                Picker(L("accent_color", fallback: "Accent color"), selection: $accentColorId) {
                    ForEach(AppSettings.accentColorIds, id: \.self) { id in
                        Text(L("accent_\(id)", fallback: Self.accentColorDisplayName(id))).tag(id)
                    }
                }
                .onChange(of: accentColorId) { newValue in
                    AppSettings.accentColorId = newValue
                }

                Picker(L("max_items_label", fallback: "Max items to save"), selection: $maxItemCount) {
                    ForEach(AppSettings.maxItemCountOptions, id: \.self) { n in
                        Text(String(format: L("items_count_format", fallback: "%d items"), n)).tag(n)
                    }
                }
                .onChange(of: maxItemCount) { newValue in
                    AppSettings.maxItemCount = newValue
                    clipboardViewModel.applyMaxItemCountFromSettings()
                }

                Toggle(L("launch_at_login", fallback: "Launch at startup"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        AppSettings.launchAtLogin = newValue
                        LaunchAtLoginHelper.setEnabled(newValue)
                    }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Text(L("clear_history_button", fallback: "Clear all history"))
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func accentColorDisplayName(_ id: String) -> String {
        switch id {
        case "blue": return "Blue"
        case "purple": return "Purple"
        case "orange": return "Orange"
        case "green": return "Green"
        case "teal": return "Teal"
        case "pink": return "Pink"
        default: return "Green"
        }
    }

    private var shortcutsDetail: some View {
        Form {
            Section {
                Text(L("shortcuts", fallback: "Shortcuts"))
                    .font(.headline)
            }
            Section {
                shortcutRow(keys: "⌘⌥⇧H", descriptionKey: "shortcut_toggle_popover", fallback: "Open / close popover")
                shortcutRow(keys: "⌘⌥ ← / →", descriptionKey: "shortcut_switch_tab", fallback: "Switch copy source tab")
                shortcutRow(keys: "⌘ 1–9", descriptionKey: "shortcut_recopy", fallback: "Re-copy item (when popover is open)")
                shortcutRow(keys: "⌘⌥ 1–9", descriptionKey: "shortcut_ocr_copy", fallback: "OCR copy from image (when popover is open)")
                shortcutRow(keys: "⌘ ,", descriptionKey: "shortcut_open_settings", fallback: "Open Settings")
                shortcutRow(keys: "Tab", descriptionKey: "shortcut_focus_search_feed", fallback: "Switch focus between search and feed")
                shortcutRow(keys: "↩", descriptionKey: "shortcut_copy_focused", fallback: "Copy focused item")
                shortcutRow(keys: "⌥↩", descriptionKey: "shortcut_ocr_focused", fallback: "OCR focused item (image)")
                shortcutRow(keys: "Esc", descriptionKey: "shortcut_clear_search", fallback: "Clear search and return")
                shortcutRow(keys: "↑ / ↓", descriptionKey: "shortcut_move_focus", fallback: "Move focus up / down")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(keys: String, descriptionKey: String, fallback: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 100, alignment: .leading)
            Text(L(descriptionKey, fallback: fallback))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/c.c.meguchan")!

    private var supportDetail: some View {
        Form {
            Section {
                Text(L("support_developer", fallback: "Support Developer"))
                    .font(.headline)
            }
            Section {
                Text(L("support_developer_message", fallback: "This app is made with the hope that a favorite tool for myself might be useful to someone else. Your support helps keep it going!"))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NSWorkspace.shared.open(Self.buyMeACoffeeURL)
                } label: {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                        Text(L("buy_me_coffee", fallback: "Buy me a coffee"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatPrimaryButtonStyle(accentColor: appAccentColor))
            }
        }
        .formStyle(.grouped)
    }

    private static let contactFormURL = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLScGqNNWjsaCtIzmYRRW6nHeYXp-4PP6NX_Jllg-GXrbvbyDbw/viewform?usp=header")!

    private var contactDetail: some View {
        Form {
            Section {
                Text(L("contact_tab", fallback: "Contact"))
                    .font(.headline)
            }
            Section {
                Button {
                    NSWorkspace.shared.open(Self.contactFormURL)
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text(L("contact_button", fallback: "Contact us here"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatPrimaryButtonStyle(accentColor: appAccentColor))

                Button {
                    Self.exportLogToFile(presentingWindow: NSApp.keyWindow)
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text(L("export_log", fallback: "Export log"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatSecondaryButtonStyle())
            }
        }
        .formStyle(.grouped)
    }

    /// 診断ログをテキストで生成し、NSSavePanel で保存する。
    private static func exportLogToFile(presentingWindow: NSWindow?) {
        let logContent = buildLogContent()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let dateStr = formatter.string(from: Date())
        let defaultName = "ClipFeed-log-\(dateStr).txt"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        panel.title = L("export_log", fallback: "Export log")

        if let window = presentingWindow {
            panel.beginSheetModal(for: window) { response in
                // シートが完全に閉じてから処理するため、次のランループで実行する
                DispatchQueue.main.async {
                    switch response {
                    case .OK:
                        if let url = panel.url {
                            writeLogAndNotify(content: logContent, to: url, presentingWindow: window)
                        }
                    default:
                        break
                    }
                }
            }
            return
        }
        let result = panel.runModal()
        if result == .OK, let url = panel.url {
            writeLogAndNotify(content: logContent, to: url, presentingWindow: nil)
        }
    }

    private static func buildLogContent() -> String {
        let version = Bundle.main.appVersion
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osStr = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        let lang = effectiveAppLanguage()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let dateStr = dateFormatter.string(from: Date())

        let lines: [String] = [
            "ClipFeed Diagnostic Log",
            "=====================",
            "",
            "Generated: \(dateStr)",
            "App Version: \(version)",
            "macOS: \(osStr)",
            "App language (effective): \(lang)",
            "",
            "Launch source",
            "-------------",
            "\(Bundle.main.launchSourceInfo.description)",
            "Bundle path: \(Bundle.main.launchSourceInfo.path)",
            "",
            "Settings",
            "--------",
            "App language (setting): \(AppSettings.appLanguage)",
            "Appearance: \(AppSettings.appearanceMode)",
            "Accent color: \(AppSettings.accentColorId)",
            "Max items: \(AppSettings.maxItemCount)",
            "Launch at login: \(AppSettings.launchAtLogin)",
            "",
            "Runtime log (last \(LogCapture.maxLinesDisplay) lines)",
            "----------------------------------------",
            LogCapture.getContent().isEmpty ? "(No log entries yet)" : LogCapture.getContent(),
        ]
        return lines.joined(separator: "\n")
    }

    private static func writeLogAndNotify(content: String, to url: URL, presentingWindow: NSWindow?) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            let alert = NSAlert()
            alert.messageText = L("log_export_success", fallback: "Log exported successfully.")
            alert.informativeText = url.path
            alert.alertStyle = .informational
            alert.addButton(withTitle: L("alert_ok", fallback: "OK"))
            if let window = presentingWindow {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("log_export_failed", fallback: "Failed to save log.")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("alert_ok", fallback: "OK"))
            if let window = presentingWindow {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                alert.runModal()
            }
        }
    }

    private var aboutDetail: some View {
        Form {
            Section {
                Text(L("about_app_version", fallback: "App Version"))
                    .font(.headline)
            }
            Section {
                HStack {
                    Text(L("app_version", fallback: "Version"))
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .foregroundStyle(.secondary)
                }
                let source = Bundle.main.launchSourceInfo
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("launch_source_label", fallback: "Launch source"))
                        Spacer()
                        Text(source.description)
                            .foregroundStyle(.secondary)
                    }
                    Text(source.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button(L("check_update", fallback: "Check for Updates")) {
                    UpdateChecker.shared.checkForUpdates(showNoUpdateAlert: true, presentingWindow: SettingsWindowController.shared.window)
                }
                .buttonStyle(FlatSecondaryButtonStyle())
            }
        }
        .formStyle(.grouped)
    }

}

/// 設定画面用：アクセント色のフラットなボタン（影・ベベルなし）
private struct FlatPrimaryButtonStyle: ButtonStyle {
    var accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(accentColor.opacity(configuration.isPressed ? 0.85 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 設定画面用：薄い背景のフラットなボタン（影・ベベルなし）
private struct FlatSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 起動時ログイン（Login Item）の有効/無効。macOS 13+ の SMAppService を使用。
enum LaunchAtLoginHelper {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            if enabled {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ClipboardViewModel())
        .frame(width: 520, height: 360)
}
