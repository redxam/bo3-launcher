import SwiftUI

enum Theme {
    static let bgDark = Color(red: 0.08, green: 0.07, blue: 0.06)
    static let bgMedium = Color(red: 0.14, green: 0.12, blue: 0.10)
    static let bgLight = Color(red: 0.20, green: 0.17, blue: 0.14)
    static let headerBg = Color(red: 0.10, green: 0.09, blue: 0.08)
    static let orange = Color(red: 0.90, green: 0.55, blue: 0.10)
    static let orangeHover = Color(red: 1.0, green: 0.65, blue: 0.15)
    static let textPrimary = Color(red: 0.88, green: 0.85, blue: 0.80)
    static let textSecondary = Color(red: 0.55, green: 0.50, blue: 0.45)
    static let textMuted = Color(red: 0.40, green: 0.36, blue: 0.32)
    static let divider = Color(red: 0.22, green: 0.19, blue: 0.16)
}

struct ClickableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}
