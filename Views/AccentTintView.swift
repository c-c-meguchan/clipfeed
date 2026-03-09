import SwiftUI

/// アプリのアクセント色。Environment で渡し、macOS の .tint() が効かない箇所でも確実に反映する。
private struct AppAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = AppSettings.accentColor(colorScheme: .light)
}

extension EnvironmentValues {
    var appAccentColor: Color {
        get { self[AppAccentColorKey.self] }
        set { self[AppAccentColorKey.self] = newValue }
    }
}

/// colorScheme に応じたアクセント色を子ビューに `.tint` と Environment で渡す。
struct AccentTintView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let color = AppSettings.accentColor(colorScheme: colorScheme)
        content()
            .tint(color)
            .environment(\.appAccentColor, color)
    }
}
