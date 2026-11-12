import SwiftUI
import UIKit

/// The few brand colours and fonts the widget uses. The values match the app's `Palette`
/// and `BrandFont` (D65); they're repeated here so the widget doesn't carry the app's views.
enum WidgetStyle {
    static let background = dynamic(0xEDF1EB, 0x131915)
    static let ink = dynamic(0x1E2A23, 0xE4EBE5)
    static let muted = dynamic(0x5B695F, 0x9AA89F)
    /// Used for "over".
    static let plum = dynamic(0x9A3C58, 0xDB7A9B)

    static let number = "BarlowCondensed-SemiBold"
    static let label = "Barlow-Medium"

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
