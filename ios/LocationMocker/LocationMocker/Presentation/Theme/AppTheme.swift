import SwiftUI

enum AppTheme {

    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let surface = Color(.systemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)

    struct Card: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    struct ChipNeutral: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(AppTheme.Card())
    }

    func chipNeutral() -> some View {
        modifier(AppTheme.ChipNeutral())
    }
}
