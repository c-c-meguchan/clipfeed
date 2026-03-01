import SwiftUI
import AppKit
import ServiceManagement

/// 設定画面。左サイドバーに大メニュー（設定 / アプリバージョン）、右に小メニューと内容。
struct SettingsView: View {
    @EnvironmentObject var clipboardViewModel: ClipboardViewModel

    enum SidebarItem: String, CaseIterable {
        case settings = "設定"
        case about = "アプリバージョン"
        case support = "開発者を支援"

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
    @State private var showClearConfirm = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selectedSection) { item in
                Label {
                    Text(item.rawValue)
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
        }
        .confirmationDialog("履歴を全削除", isPresented: $showClearConfirm) {
            Button("削除", role: .destructive) {
                clipboardViewModel.clearAllHistory()
                showClearConfirm = false
            }
            Button("キャンセル", role: .cancel) {
                showClearConfirm = false
            }
        } message: {
            Text("クリップボード履歴をすべて削除します。この操作は取り消せません。")
        }
    }

    private var settingsDetail: some View {
        Form {
            Section {
                Text("設定")
                    .font(.headline)
            }
            Section {
                Picker("カラーモード", selection: $appearanceMode) {
                    Text("端末の設定").tag("system")
                    Text("ライト").tag("light")
                    Text("ダーク").tag("dark")
                }
                .onChange(of: appearanceMode) { newValue in
                    AppSettings.appearanceMode = newValue
                    AppSettings.applyAppearance()
                }

                Picker("最大保存件数", selection: $maxItemCount) {
                    ForEach(AppSettings.maxItemCountOptions, id: \.self) { n in
                        Text("\(n)件").tag(n)
                    }
                }
                .onChange(of: maxItemCount) { newValue in
                    AppSettings.maxItemCount = newValue
                    clipboardViewModel.applyMaxItemCountFromSettings()
                }

                Toggle("起動時に自動起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        AppSettings.launchAtLogin = newValue
                        LaunchAtLoginHelper.setEnabled(newValue)
                    }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Text("履歴を全削除")
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/c.c.meguchan")!

    private var supportDetail: some View {
        Form {
            Section {
                Text("開発者を支援")
                    .font(.headline)
            }
            Section {
                Text("このアプリは、個人がバイブスで開発したものを、皆さんにもこの便利さをシェアしたい！という思いで運営しています。継続のために応援してくれると嬉しいです！")
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NSWorkspace.shared.open(Self.buyMeACoffeeURL)
                } label: {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("コーヒーを送る")
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
                Text("アプリバージョン")
                    .font(.headline)
            }
            Section {
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .foregroundStyle(.secondary)
                }
                Button("アップデートを確認") {
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
