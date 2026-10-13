import Foundation
import Testing

@testable import ChatFeature

@Suite("ComposerVoiceGlow: when the composer glows, and how much")
struct ComposerVoiceGlowTests {
    @Test("only while recording: not idle, not transcribing")
    func shown() {
        #expect(ComposerVoiceGlow.isShown(.recording(since: .now)))
        #expect(!ComposerVoiceGlow.isShown(.idle))
        #expect(!ComposerVoiceGlow.isShown(.transcribing))
    }

    @Test("a quiet room and below rest the glow; 0 dB is full; linear in between")
    func level() {
        #expect(ComposerVoiceGlow.level(0, reduceMotion: false) == 0)
        #expect(ComposerVoiceGlow.level(VoiceRecorder.normalizedLevel(decibels: -40), reduceMotion: false) == 0)
        #expect(ComposerVoiceGlow.level(1, reduceMotion: false) == 1)
        #expect(abs(ComposerVoiceGlow.level(0.6, reduceMotion: false) - 0.5) < 1e-9)
    }

    @Test("out-of-range readings are clamped")
    func clamped() {
        #expect(ComposerVoiceGlow.level(-0.5, reduceMotion: false) == 0)
        #expect(ComposerVoiceGlow.level(1.5, reduceMotion: false) == 1)
    }

    @Test("with Reduce Motion the level holds, whatever the voice", arguments: [0.0, 0.4, 1.0])
    func steady(recorded: Double) {
        #expect(ComposerVoiceGlow.level(recorded, reduceMotion: true) == ComposerVoiceGlow.steadyLevel)
    }
}
