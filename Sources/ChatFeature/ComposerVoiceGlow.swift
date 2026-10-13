import SwiftUI
import VoiceGlowKit

/// The glow while the composer records: voice-glow (libraries.dev, Jakub Antalik) rising from the bottom of the screen
/// with the voice. It reads the level from our own `AVAudioRecorder` (`VoiceRecorder.level()`), never the library's
/// `VoiceMeter`: that one runs its own `AVAudioEngine` and turns the audio session off under the recording.
enum ComposerVoiceGlow {
    /// The recorder's level (−50 dB…0 dB, linear) at or below which the glow rests: about −40 dB, a quiet room's hum,
    /// so silence leaves the faint resting beam that says the microphone is open and only a voice raises it.
    static let floor = 0.2

    /// With Reduce Motion the glow holds at this level and does not follow the voice: still lit, nothing moving.
    static let steadyLevel = 0.3

    /// It shows only while recording; typing, transcribing and idle have none.
    static func isShown(_ recording: VoiceRecordingState) -> Bool {
        if case .recording = recording { return true }
        return false
    }

    /// The level the glow is fed, 0…1, from the recorder's.
    static func level(_ recorded: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return steadyLevel }
        return min(1, max(0, (recorded - floor) / (1 - floor)))
    }
}

extension View {
    /// The glow over the whole screen while recording, rising from its bottom edge as voice-glow's phone demo (the
    /// `mobile` type). An overlay that takes no taps: the composer and the transcript under it work as before. It fades in
    /// and out with `active` and draws nothing, nor ticks, while off.
    func screenVoiceGlow(active: Bool, level: @escaping () -> Double) -> some View {
        modifier(ScreenVoiceGlowModifier(active: active, level: level))
    }
}

private struct ScreenVoiceGlowModifier: ViewModifier {
    let active: Bool
    let level: () -> Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The screen's own corners, which the glow's bottom follows. iOS does not say what they are; this is the
    /// library's own phone figure, close to every current iPhone's.
    static let displayCornerRadius = 55.0

    func body(content: Content) -> some View {
        var options = VoiceGlowOptions()
        // Without a spectrum the library wobbles the lobes on a clock; with Reduce Motion they stay put.
        options.bands = !reduceMotion
        return content.overlay {
            Color.clear
                .voiceGlow(
                    type: .mobile,
                    levelProvider: { [reduceMotion, level] in ComposerVoiceGlow.level(level(), reduceMotion: reduceMotion) },
                    active: active,
                    cornerRadius: Self.displayCornerRadius,
                    options: options
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
