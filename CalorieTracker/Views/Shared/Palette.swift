import SwiftUI
import UIKit

/// The dashboard's colours, from the reference design. Each has a light and a dark value
/// and follows the system appearance.
enum Palette {
    static let background = dynamic(0xEDF1EB, 0x131915)
    static let panel = dynamic(0xF7F9F5, 0x1B221D)
    static let ink = dynamic(0x1E2A23, 0xE4EBE5)
    static let muted = dynamic(0x66746B, 0x93A198)
    static let rule = dynamic(0xD5DDD3, 0x2B352E)
    static let green = dynamic(0x2E6A4E, 0x6FBE93)
    static let greenSoft = dynamic(0x9DBBA9, 0x3F6B53)
    static let ochre = dynamic(0xB7832A, 0xDDB05A)
    /// Used for "over".
    static let plum = dynamic(0x9A3C58, 0xDB7A9B)
    static let track = dynamic(0xDDE4DA, 0x26302A)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// How a source is drawn everywhere: Label solid green, Estimate green hatched,
/// Photo Estimate ochre hatched.
struct SourceFill: ShapeStyle {
    var source: Source

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        switch source {
        case .label: return AnyShapeStyle(Palette.green)
        case .estimate: return AnyShapeStyle(Hatch.paint(Palette.green, on: Palette.greenSoft, in: environment))
        case .photoEstimate: return AnyShapeStyle(Hatch.paint(Palette.ochre, on: Palette.greenSoft, in: environment))
        }
    }
}

/// Diagonal stripes, as a tiling image paint.
enum Hatch {
    /// One tile: stripes at 45°, so tiles join seamlessly.
    static func paint(_ stripe: Color, on base: Color, in environment: EnvironmentValues) -> ImagePaint {
        let size: CGFloat = 8
        let stripeColor = UIColor(Color(stripe.resolve(in: environment)))
        let baseColor = UIColor(Color(base.resolve(in: environment)))
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            baseColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let path = UIBezierPath()
            for offset in [-size, 0, size] {
                path.move(to: CGPoint(x: offset, y: size))
                path.addLine(to: CGPoint(x: offset + size, y: 0))
            }
            path.lineWidth = size * 0.4
            stripeColor.setStroke()
            path.stroke()
        }
        return ImagePaint(image: Image(uiImage: image))
    }
}

extension Source {
    /// The short name used on tags and in legends.
    var shortName: String {
        switch self {
        case .label: "Label"
        case .estimate: "Estimate"
        case .photoEstimate: "Photo"
        }
    }

    var tagColor: Color {
        switch self {
        case .label: Palette.green
        case .estimate: Palette.muted
        case .photoEstimate: Palette.ochre
        }
    }
}

/// Numbers in the dashboard: condensed, with digits that line up.
extension Font {
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }
}
