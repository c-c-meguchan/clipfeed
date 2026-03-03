import SwiftUI
import AppKit
import ServiceManagement

/// 設定画面。左サイドバーに大メニュー（設定 / アプリバージョン）、右に小メニューと内容。
struct SettingsView: View {
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel

    enum SidebarItem: String, CaseIterable {
        case settings
        case about
        case support

        var displayTitle: String {
            switch self {
            case .settings: return L("settings", fallback: "Settings")
            case .about: return L("about_app_version", fallback: "App Version")
            case .support: return L("support_developer", fallback: "Support Developer")
            }
        }

        var iconName: String {
            switch self {
            case .settings: return "gearshape.fill"
            case .about: return "info.circle.fill"
            case .support: return "heart.fill"
            }
        }
    }

    @State private var selectedSection: SidebarItem = .settings
    @State private var maxItemCount: Int = AppSettings.maxItemCount
    @State private var launchAtLogin: Bool = AppSettings.launchAtLogin
    @State private var appearanceMode: String = AppSettings.appearanceMode
    @State private var appLanguage: String = AppSettings.appLanguage
    @State private var showClearConfirm = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selectedSection) { item in
                Label {
                    Text(item.displayTitle)
                } icon: {
                    Image(systemName: item.iconName)
                        .foregroundStyle(.blue)
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
                case .about:
                    aboutDetail
                case .support:
                    supportDetail
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
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
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
                Button(L("check_update", fallback: "Check for Updates")) {
                    UpdateChecker.shared.checkForUpdates(showNoUpdateAlert: true, presentingWindow: SettingsWindowController.shared.window)
                }
            }
        }
        .formStyle(.grouped)
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
