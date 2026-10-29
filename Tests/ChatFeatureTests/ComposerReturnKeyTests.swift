import Testing
import UIKit

@testable import ChatFeature

/// A hardware keyboard's Return in the composer (ISSUE-291, the iPad): Return sends, a modified Return is a newline,
/// and a Return that commits an input method's composition is the input method's.
struct ComposerReturnKeyTests {
    @Test func plainReturnSends() {
        #expect(ComposerReturnKey.sends(keyCode: .keyboardReturnOrEnter, modifiers: [], composing: false))
        #expect(ComposerReturnKey.sends(keyCode: .keypadEnter, modifiers: .numericPad, composing: false))
    }

    @Test func capsLockDoesNotTurnReturnIntoANewline() {
        #expect(ComposerReturnKey.sends(keyCode: .keyboardReturnOrEnter, modifiers: .alphaShift, composing: false))
    }

    @Test(arguments: [UIKeyModifierFlags.shift, .alternate, .control, .command])
    func aModifiedReturnIsTheTextViewsOwn(modifier: UIKeyModifierFlags) {
        #expect(!ComposerReturnKey.sends(keyCode: .keyboardReturnOrEnter, modifiers: modifier, composing: false))
    }

    @Test func returnCommittingAPinyinCompositionDoesNotSend() {
        #expect(!ComposerReturnKey.sends(keyCode: .keyboardReturnOrEnter, modifiers: [], composing: true))
    }

    @Test func otherKeysNeverSend() {
        #expect(!ComposerReturnKey.sends(keyCode: .keyboardTab, modifiers: [], composing: false))
        #expect(!ComposerReturnKey.sends(keyCode: .keyboardSpacebar, modifiers: [], composing: false))
    }

    /// Without a handler the field is the plain multi-line text view it always was.
    @MainActor @Test func aFieldWithoutAHandlerKeepsReturnANewline() {
        let field = PastingTextView.composerField()
        #expect(field.onReturnKey == nil)
    }
}
