import SwiftUI

/// Kord design system — derived from the Rising Tides brand kit.
/// Near-black layered surfaces, magenta -> purple gradient accent,
/// white-opacity borders, continuous corners.
enum KordTheme {
    // MARK: Surfaces (darkest -> most elevated)
    static let void = Color(hex: 0x060606)
    static let graphite = Color(hex: 0x0A0A0A)
    static let raised = Color(hex: 0x141414)
    static let elevated = Color(hex: 0x1D1D21)
    static let card = Color(hex: 0x2E323C)

    // MARK: Borders
    static let borderSubtle = Color.white.opacity(0.06)
    static let borderMuted = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.20)
    /// Legacy name used across views for 1px strokes.
    static let rail = borderMuted

    // MARK: Text
    static let text = Color(hex: 0xFAFCFF)
    static let secondary = Color(hex: 0xB8B9BB)
    static let muted = Color(hex: 0x909098)
    static let faint = Color(hex: 0x5A5C63)

    // MARK: Accent
    static let magenta = Color(hex: 0xE100C3)
    static let purple = Color(hex: 0x8500D7)
    /// Legacy accent name; now points at brand magenta.
    static let ember = magenta
    static let live = Color(hex: 0x1ED760)
    static let danger = Color(hex: 0xFF3B3B)

    static let accentGradient = LinearGradient(
        colors: [magenta, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradientHorizontal = LinearGradient(
        colors: [magenta, purple],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Soft accent wash for backgrounds behind active elements.
    static let accentWash = LinearGradient(
        colors: [magenta.opacity(0.16), purple.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Shape
    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 10
    static let radiusLarge: CGFloat = 20

    // MARK: Type
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Panels

struct KordPanel: ViewModifier {
    var radius: CGFloat = KordTheme.radius

    func body(content: Content) -> some View {
        content
            .background(KordTheme.raised)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(KordTheme.borderSubtle, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A panel highlighted with the brand gradient wash — for active/featured states.
struct KordAccentPanel: ViewModifier {
    var radius: CGFloat = KordTheme.radius

    func body(content: Content) -> some View {
        content
            .background(KordTheme.raised)
            .background(KordTheme.accentWash)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(KordTheme.magenta.opacity(0.35), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func kordPanel(radius: CGFloat = KordTheme.radius) -> some View {
        modifier(KordPanel(radius: radius))
    }

    func kordAccentPanel(radius: CGFloat = KordTheme.radius) -> some View {
        modifier(KordAccentPanel(radius: radius))
    }
}

// MARK: - Buttons

/// Filled gradient pill — the primary call to action.
struct KordPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KordTheme.label(16))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(KordTheme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet raised button for secondary actions.
struct KordSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KordTheme.label(16))
            .foregroundStyle(KordTheme.text)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(KordTheme.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous)
                    .strokeBorder(KordTheme.borderMuted, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: KordTheme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
