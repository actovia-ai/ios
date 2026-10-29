import SwiftUI
import Testing

@testable import PhilharmonicFeature

@Suite("ForegroundReturn (ISSUE-249 M6)")
struct ForegroundReturnTests {
    @Test("Control Center (inactive → active) is not a return; the background is, once")
    func onlyFromTheBackground() {
        var tracker = ForegroundReturn()
        let phases: [ScenePhase] = [.active, .inactive, .active, .inactive, .background, .inactive, .active, .inactive, .active]
        let returns = phases.map { tracker.observe($0) }
        #expect(returns == [false, false, false, false, false, false, true, false, false])
    }
}

@Suite("GroupComposerRule (ISSUE-249 M5)")
struct GroupComposerRuleTests {
    @Test("answering the PM takes words only; pictures neither count nor block")
    func answering() {
        #expect(!GroupComposerRule.canSend(hasWords: false, hasPictures: true, preparing: 0, sending: false, answering: true))
        #expect(GroupComposerRule.canSend(hasWords: true, hasPictures: true, preparing: 1, sending: false, answering: true))
        #expect(!GroupComposerRule.canSend(hasWords: true, hasPictures: false, preparing: 0, sending: true, answering: true))
    }

    @Test("an ordinary message takes words or pictures, once they are ready")
    func ordinary() {
        #expect(GroupComposerRule.canSend(hasWords: false, hasPictures: true, preparing: 0, sending: false, answering: false))
        #expect(!GroupComposerRule.canSend(hasWords: true, hasPictures: true, preparing: 1, sending: false, answering: false))
        #expect(!GroupComposerRule.canSend(hasWords: false, hasPictures: false, preparing: 0, sending: false, answering: false))
    }
}
