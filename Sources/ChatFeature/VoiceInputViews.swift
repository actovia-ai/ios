import SwiftUI
import UIKit

/// The composer's round button's face, shared by the chat screen and the composer gallery: the icon morphs between
/// states (`.contentTransition`) because the button around it keeps one identity.
struct TurnButtonLabel: View {
    let state: TurnButtonState
    let glyph: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            // One literal per branch, never a ternary (scripts/l10n.py audit bans it).
            switch state {
            case .send: Text("chat:composer.send")
            case .stop: Text("chat:composer.stop")
            case .mic: Text("ios:chat.composer.record")
            case .recording: Text("ios:chat.composer.stopRecording")
            case .transcribing: Text("ios:chat.composer.transcribing")
            }
        } icon: {
            Image(systemName: state.symbol)
                // Kept, unseen, under the spinner: the button stays the size it was.
                .opacity(state == .transcribing ? 0 : 1)
                .overlay {
                    if state == .transcribing {
                        ProgressView().controlSize(.small).tint(glyph)
                    }
                }
        }
        .labelStyle(.iconOnly)
        // The glyph's box, which the glass circle pads out to the pill's button size (`ComposerRowLayout.buttonSide`).
        .frame(width: Self.glyphSide, height: Self.glyphSide)
        .foregroundStyle(glyph)
        // The single most-tapped control in the app (apple-design §13: state indication, tens of times a day, so the
        // motion stays fast and subtle, never a showy morph).
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }

    static let glyphSide: CGFloat = 22

    /// Send and record in the tone (in light its ink, in dark its fill); stop neutral; a recording's stop red.
    static func fill(_ state: TurnButtonState, scheme: ColorScheme, toneFill: Color, toneInk: Color) -> Color {
        switch state {
        case .stop: Color(.label)
        case .recording: .red
        case .send, .mic, .transcribing: scheme == .dark ? toneFill : toneInk
        }
    }

    static func glyph(_ state: TurnButtonState, scheme: ColorScheme, accentGlyph: Color) -> Color {
        switch state {
        case .stop: Color(.systemBackground)
        case .recording: .white
        case .send, .mic, .transcribing: scheme == .dark ? accentGlyph : .white
        }
    }
}

/// In the message field's place while recording: a red dot and the length so far, `m:ss`. The voice's level is the
/// screen's glow (`screenVoiceGlow`); the bar that also drew it read as a timeline and is gone (owner, 2026-10-08).
struct RecordingMeter: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(VoiceRecorder.elapsed(from: since, to: context.date))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
