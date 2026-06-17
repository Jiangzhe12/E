import AppKit
import SwiftUI

// MARK: - Adaptive color

extension Color {
    /// An app color that resolves to `light` in light appearance and `dark` in dark appearance.
    /// Lets brand colors live in one place yet still adapt to the system theme.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    /// Translucent "glass" overlay for frosted panels / pills / hover fills. Stays subtle in
    /// dark mode instead of becoming a glaring near-white block.
    static func glass(_ opacity: Double) -> Color {
        Color(light: .white.opacity(opacity), dark: .white.opacity(opacity * 0.16))
    }
}

// MARK: - Semantic color tokens

/// App-wide semantic colors. Replaces the dozens of scattered `Color(red:…)` literals so a
/// palette or dark-mode change happens in one place. Light values match the previous
/// hardcoded brand colors; dark values are lighter variants ready for dark-mode support.
enum AppColor {
    /// Card / section title blue (was `Color(red: 0.13, green: 0.30, blue: 0.50)`, repeated ~16×).
    static let title = Color(light: Color(red: 0.13, green: 0.30, blue: 0.50),
                             dark: Color(red: 0.64, green: 0.80, blue: 0.99))
    /// Interactive accent / in-progress blue.
    static let accent = Color(light: Color(red: 0.231, green: 0.510, blue: 0.965),
                              dark: Color(red: 0.46, green: 0.66, blue: 1.0))
    /// Success / completed green.
    static let success = Color(light: Color(red: 0.133, green: 0.773, blue: 0.369),
                               dark: Color(red: 0.30, green: 0.85, blue: 0.52))
    /// Warning / due-soon orange.
    static let warning = Color(light: Color(red: 0.84, green: 0.45, blue: 0.18),
                               dark: Color(red: 0.98, green: 0.64, blue: 0.32))
    /// Destructive / overdue red.
    static let danger = Color(light: Color(red: 0.84, green: 0.27, blue: 0.27),
                              dark: Color(red: 1.0, green: 0.46, blue: 0.46))
    /// Caution / due-soon yellow (the third tier between warning-orange and neutral).
    static let caution = Color(light: Color(red: 0.66, green: 0.50, blue: 0.06),
                               dark: Color(red: 0.95, green: 0.82, blue: 0.35))
    /// Muted secondary-label blue (was `Color(red: 0.22, green: 0.44, blue: 0.64)`, repeated ~13×).
    static let subtitle = Color(light: Color(red: 0.22, green: 0.44, blue: 0.64),
                                dark: Color(red: 0.60, green: 0.74, blue: 0.92))
    /// Deep heading ink blue (was `Color(red: 0.10, green: 0.21, blue: 0.36)`).
    static let ink = Color(light: Color(red: 0.10, green: 0.21, blue: 0.36),
                           dark: Color(red: 0.78, green: 0.87, blue: 1.0))
    /// Deep green for green *text / headings* (distinct from the bright `success` fill);
    /// converges the ~8 hand-tuned green text colors that were scattered around.
    static let successDeep = Color(light: Color(red: 0.16, green: 0.42, blue: 0.30),
                                   dark: Color(red: 0.46, green: 0.82, blue: 0.58))
    /// One-off accent purple.
    static let purple = Color(light: Color(red: 0.45, green: 0.34, blue: 0.72),
                              dark: Color(red: 0.72, green: 0.64, blue: 0.96))
    /// Foreground for text/icons sitting ON a filled accent chip (selected pill, "today"
    /// circle, count badge). The semantic fills are dark in light mode and light in dark mode,
    /// so the text must invert: white on the dark fill, black on the light fill.
    static let onAccent = Color(light: .white, dark: .black)

    // Pale surface tints — used as chip / section / answer backgrounds.
    static let tintBlue = Color(light: Color(red: 0.90, green: 0.95, blue: 1.0),
                                dark: Color(red: 0.15, green: 0.20, blue: 0.29))
    static let tintGreen = Color(light: Color(red: 0.89, green: 0.97, blue: 0.91),
                                 dark: Color(red: 0.13, green: 0.24, blue: 0.18))
    static let tintOrange = Color(light: Color(red: 1.0, green: 0.93, blue: 0.84),
                                  dark: Color(red: 0.28, green: 0.20, blue: 0.12))
}

/// The desktop-pet bubble's *always-dark* neon skin. These are deliberately NOT adaptive —
/// the bubble keeps its dark identity in both system appearances. Collected here so the skin
/// can be tuned in one place instead of being copy-pasted across the bubble view.
enum PetPalette {
    static let ink = Color(red: 0.90, green: 0.99, blue: 1.0)        // primary text
    static let inkBright = Color(red: 0.92, green: 0.99, blue: 1.0)  // button title text
    static let cyan = Color(red: 0.42, green: 0.94, blue: 1.0)       // accent / icon
    static let cyanSoft = Color(red: 0.58, green: 0.96, blue: 1.0)   // metadata
    static let subtitle = Color(red: 0.62, green: 0.75, blue: 0.95)  // secondary text
    static let bullet = Color(red: 0.72, green: 0.82, blue: 0.98)    // explanation text
    static let violet = Color(red: 0.65, green: 0.55, blue: 1.0)     // phonetic
    static let violetDeep = Color(red: 0.62, green: 0.46, blue: 1.0)
    static let close = Color(red: 0.64, green: 0.78, blue: 0.95)     // close button
    static let bgTop = Color(red: 0.04, green: 0.08, blue: 0.24)
    static let bgMid = Color(red: 0.04, green: 0.09, blue: 0.26)
    static let bgDeep = Color(red: 0.03, green: 0.07, blue: 0.21)
}

extension LinearGradient {
    /// The main window background. Soft light-blue in light mode, deep slate in dark mode.
    static let appWindow = LinearGradient(
        colors: [
            Color(light: Color(red: 0.92, green: 0.96, blue: 0.99), dark: Color(red: 0.10, green: 0.12, blue: 0.16)),
            Color(light: Color(red: 0.89, green: 0.95, blue: 0.99), dark: Color(red: 0.08, green: 0.10, blue: 0.14)),
            Color(light: Color(red: 0.93, green: 0.97, blue: 1.0), dark: Color(red: 0.11, green: 0.13, blue: 0.18)),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Geometry tokens

/// 8pt-based spacing scale. Use instead of bare magic numbers for consistent rhythm.
enum AppSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Corner-radius scale. Outer containers should be >= inner ones.
enum AppRadius {
    static let chip: CGFloat = 8
    static let control: CGFloat = 10
    static let card: CGFloat = 16
}

// MARK: - Card surface

/// The standard translucent card surface: a system material fill plus a hairline border.
/// Replaces the hand-rolled `RoundedRectangle(...).fill(.white.opacity(...)).overlay(stroke)`
/// that was copy-pasted across the app, and adapts to light/dark automatically.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = AppRadius.card

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Applies the standard ``CardSurface`` (material fill + hairline border).
    func cardSurface(cornerRadius: CGFloat = AppRadius.card) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }

    /// A lightweight inset surface for sub-cards nested inside a ``cardSurface``:
    /// a subtle translucent fill, no border. Adapts to light/dark.
    func insetSurface(cornerRadius: CGFloat = AppRadius.control) -> some View {
        background(
            Color(light: .white.opacity(0.7), dark: .white.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
