import SwiftUI
import UIKit

/// The app's type (D65): Barlow for reading text, Barlow Condensed for numbers and section
/// titles. Both are bundled under `Resources/Fonts` (SIL Open Font License) and listed in
/// `UIAppFonts`. Every size follows the iPhone's text-size setting.
enum BrandFont {
    static func barlow(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: "Barlow-Medium"
        case .semibold: "Barlow-SemiBold"
        case .bold, .heavy, .black: "Barlow-Bold"
        default: "Barlow-Regular"
        }
    }

    static func condensed(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "BarlowCondensed-Bold"
        case .semibold: "BarlowCondensed-SemiBold"
        default: "BarlowCondensed-Medium"
        }
    }

    /// Navigation bar titles, which UIKit draws.
    static func styleNavigationBars() {
        let title = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: UIFont(name: barlow(.semibold), size: 17) ?? .preferredFont(forTextStyle: .headline))
        let large = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: UIFont(name: condensed(.semibold), size: 36) ?? .preferredFont(forTextStyle: .largeTitle))
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: title]
        bar.largeTitleTextAttributes = [.font: large]
    }
}

extension Font {
    /// Barlow at a system text style's size, growing with the text-size setting like that style.
    /// Headlines default to semibold, as the system's do.
    static func barlow(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let weight = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(BrandFont.barlow(weight), size: style.baseSize, relativeTo: style)
    }

    /// Numbers in the dashboard: Barlow Condensed with digits that line up.
    ///
    /// Sizes follow the iPhone's text-size setting, scaled like `style` (a big hero number scales
    /// like a large title, so it grows less than body text). A view using these must declare
    /// `@Environment(\.dynamicTypeSize)` so it redraws when the setting changes.
    /// `relativeTo: nil` keeps the size fixed, for labels inside charts (whose text size is capped).
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: UIFont.TextStyle? = .body) -> Font {
        .custom(BrandFont.condensed(weight), fixedSize: style.map { scaled(size, $0) } ?? size).monospacedDigit()
    }

    /// Condensed headings, like the dashboard section titles.
    static func condensed(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: UIFont.TextStyle = .title2) -> Font {
        .custom(BrandFont.condensed(weight), fixedSize: scaled(size, style))
    }

    private static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: size)
    }
}

private extension Font.TextStyle {
    /// The default (Large) size of each system text style, in points.
    var baseSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

/// Screens built on a `Form` or `List` show the app background instead of system grey (D65).
extension View {
    func themedBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.background)
    }
}
