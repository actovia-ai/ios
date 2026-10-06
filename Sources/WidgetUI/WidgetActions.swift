import SwiftUI
import WidgetKitShared

/// The medium widget's round buttons, as Claude's widget has them: a photo, a word, Health and the latest chat. Each
/// is a link into the app; the glyphs are the composer's own (`mic.fill` is its record button).
struct WidgetAction: Identifiable {
    let id: String
    let symbol: String
    let label: LocalizedStringResource
    let url: URL

    /// In the order a right-handed thumb reaches them least to most: the latest chat, under the thumb, is the one
    /// most often wanted back.
    static func all(latest: RecentChat?) -> [WidgetAction] {
        [
            WidgetAction(
                id: "camera", symbol: "camera.fill",
                label: LocalizedStringResource("ios:widget.action.camera", bundle: .main),
                url: DeepLink.newChat(prompt: nil, opening: .camera).url),
            WidgetAction(
                id: "voice", symbol: "mic.fill",
                label: LocalizedStringResource("ios:widget.action.voice", bundle: .main),
                url: DeepLink.newChat(prompt: nil, opening: .voice).url),
            WidgetAction(
                id: "health", symbol: "heart.fill",
                label: LocalizedStringResource("ios:widget.action.health", bundle: .main),
                url: DeepLink.health(ask: nil).url),
            // Without a chat yet, the button starts one.
            WidgetAction(
                id: "latest", symbol: "clock.arrow.circlepath",
                label: LocalizedStringResource("ios:widget.action.latest", bundle: .main),
                url: latest.map { DeepLink.chat(id: $0.id).url } ?? DeepLink.newChat(prompt: nil).url),
        ]
    }
}

/// A round button on the sky: the frost the capsule is made of, the glyph in the ink.
struct WidgetActionCircle: View {
    let action: WidgetAction
    let ink: Color
    let diameter: CGFloat

    var body: some View {
        Link(destination: action.url) {
            Image(systemName: action.symbol)
                .font(.system(size: diameter * 0.38, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: diameter, height: diameter)
                .background(ink.opacity(0.16), in: .circle)
        }
        .accessibilityLabel(Text(action.label))
    }
}
