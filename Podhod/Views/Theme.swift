import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.067)
    static let card = Color(red: 0.092, green: 0.106, blue: 0.137)
    static let accent = Color(red: 0.30, green: 0.62, blue: 1.0)
    static let secondary = Color(red: 0.57, green: 0.62, blue: 0.70)
    static let green = Color(red: 0.68, green: 0.89, blue: 0.47)
}

private struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(18).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
extension View {
    func appCard() -> some View { modifier(AppCardModifier()) }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?
    init(_ title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 33, weight: .light))
                .foregroundStyle(AppTheme.accent).frame(width: 76, height: 76)
                .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
            VStack(spacing: 8) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text(message).font(.subheadline).foregroundStyle(AppTheme.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 30).padding(.horizontal, 20).frame(maxWidth: .infinity)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = AppTheme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(tint)
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(AppTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).appCard()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Color.white)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(AppTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.3), in: RoundedRectangle(cornerRadius: 17))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
