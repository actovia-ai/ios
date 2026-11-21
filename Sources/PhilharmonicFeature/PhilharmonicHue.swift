import SwiftUI
import UIKit

/// The desktop's Philharmonic hues (`components/philharmonic/lib/hue.ts` and the `--ph-hue-*` tokens in
/// `globals.css`): a soft disc and a ring of the same colour, picked from a seed, behind an employee's face and a
/// group's emoji. The same seed picks the same hue on both, so a group or an employee wears one colour everywhere.
public enum PhilharmonicHue: Int, CaseIterable, Sendable {
    case lilac, mint, peach, sky, rose, honey, periwinkle, sage

    /// The desktop's `pickHue`: FNV-1a over the seed's UTF-16 code units (JavaScript's `charCodeAt`), an empty or
    /// missing seed read as `"default"`.
    public static func pick(_ seed: String?) -> PhilharmonicHue {
        let key = seed.flatMap { $0.isEmpty ? nil : $0 } ?? "default"
        var hash: UInt32 = 2_166_136_261
        for unit in key.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16_777_619
        }
        return allCases[Int(hash % UInt32(allCases.count))]
    }

    /// The disc.
    public var fill: Color { Color(uiColor: Self.dynamic(light: palette.lightFill, dark: palette.darkFill)) }
    /// The 1.5 pt ring just inside the disc's edge.
    public var ring: Color { Color(uiColor: Self.dynamic(light: palette.lightRing, dark: palette.darkRing)) }

    private var palette: (lightFill: UInt32, lightRing: UInt32, darkFill: UInt32, darkRing: UInt32) {
        switch self {
        case .lilac: (0xE8D5FF, 0xC8A8FF, 0x3A2F5C, 0x6B53B5)
        case .mint: (0xC2F0E2, 0x6DCCAB, 0x1F4538, 0x3E8869)
        case .peach: (0xFFD7C2, 0xFF9B6C, 0x4A2E22, 0x94583F)
        case .sky: (0xCFE8F3, 0x6FC3DD, 0x1D3848, 0x3A6B89)
        case .rose: (0xFFD2DC, 0xFF8AA5, 0x4A2832, 0xA24A63)
        case .honey: (0xFFE9B5, 0xE8B948, 0x4A3D1A, 0xA88A2E)
        case .periwinkle: (0xD7E4FF, 0x8AA8FF, 0x252E48, 0x5A75B5)
        case .sage: (0xD5F3D1, 0x6FC76F, 0x1F3D1F, 0x3E783E)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// A hue disc with its ring, and something on it: the desktop's `hueStyle()` wrapper (`rounded-full`, the hue's fill,
/// `inset 0 0 0 1.5px` of its ring — drawn under the content, as an inset shadow is).
struct HueDisc<Content: View>: View {
    let hue: PhilharmonicHue
    let side: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().fill(hue.fill)
            Circle().strokeBorder(hue.ring, lineWidth: 1.5)
            content()
        }
        .frame(width: side, height: side)
        .clipShape(.circle)
    }
}

/// A group's avatar, as the desktop's group list draws it: its emoji (💬 when it has none) on the hue its id picks.
public struct GroupEmojiAvatar: View {
    let id: String
    let icon: String?
    let side: CGFloat

    public init(id: String, icon: String?, side: CGFloat) {
        self.id = id
        self.icon = icon
        self.side = side
    }

    public var body: some View {
        Group {
            if let icon, !icon.isEmpty, !icon.hasPrefix("ody:") {
                Text(verbatim: icon).font(.system(size: side * 0.7))
            } else {
                let names = ["lilac", "mint", "peach", "sky", "rose", "honey", "periwinkle", "sage"]
                let colors: [UInt32] = [0xA78BFA, 0x54BBA4, 0xEF925F, 0x609AEE, 0xE883AD, 0xE5B34C, 0x8F9DEB, 0x7BB673]
                let index = icon.flatMap { names.firstIndex(of: String($0.dropFirst(4))) } ?? PhilharmonicHue.pick(id).rawValue
                let color = colors[index]
                Canvas { context, size in
                    let scale = size.width / 64
                    context.scaleBy(x: scale, y: scale)
                    var body = Path()
                    body.move(to: CGPoint(x: 6, y: 52))
                    body.addCurve(to: CGPoint(x: 32, y: 5), control1: CGPoint(x: 6, y: 24), control2: CGPoint(x: 15, y: 5))
                    body.addCurve(to: CGPoint(x: 58, y: 52), control1: CGPoint(x: 49, y: 5), control2: CGPoint(x: 58, y: 24))
                    body.addQuadCurve(to: CGPoint(x: 52, y: 58), control: CGPoint(x: 58, y: 58))
                    body.addLine(to: CGPoint(x: 12, y: 58))
                    body.addQuadCurve(to: CGPoint(x: 6, y: 52), control: CGPoint(x: 6, y: 58))
                    context.fill(body, with: .color(Color(red: Double((color >> 16) & 255) / 255, green: Double((color >> 8) & 255) / 255, blue: Double(color & 255) / 255)))
                    for x in [33.0, 45.0] {
                        context.fill(Path(roundedRect: CGRect(x: x, y: 25, width: 6, height: 13), cornerRadius: 3), with: .color(Color(red: 0.106, green: 0.106, blue: 0.122)))
                    }
                    var smile = Path()
                    smile.move(to: CGPoint(x: 38, y: 45))
                    smile.addQuadCurve(to: CGPoint(x: 46, y: 45), control: CGPoint(x: 42, y: 49))
                    context.stroke(smile, with: .color(Color(red: 0.106, green: 0.106, blue: 0.122)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
