import SwiftUI

/// アプリで選択したアクセント色。Environment で渡し、macOS の .tint() が効かない箇所でも確実に反映する。
private struct AppAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = AppSettings.accentColor(for: "green", colorScheme: .light)
}

extension EnvironmentValues {
    var appAccentColor: Color {
        get { self[AppAccentColorKey.self] }
        set { self[AppAccentColorKey.self] = newValue }
    }
}

/// UserDefaults のアクセントカラーを読み、子ビューに `.tint` と Environment で渡す。設定変更でポップオーバー・設定ウィンドウ両方が更新される。
struct AccentTintView<Content: View>: View {
    @AppStorage(AppSettings.accentColorKey) private var accentId: String = "green"
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let color = AppSettings.accentColor(for: accentId, colorScheme: colorScheme)
        content()
            .tint(color)
            .environment(\.appAccentColor, color)
    }
}
