import Testing

@testable import Actovia

@Suite("UnlockPresentation (ISSUE-298: a lock covers the app, never rebuilds it)")
struct UnlockPresentationTests {
    @Test("a cold start behind Face ID builds nothing until the first unlock")
    func coldStart() {
        var gate = UnlockPresentation(isLocked: true)
        #expect(!gate.mountsContent)
        #expect(gate.coversContent)
        gate.settle(stillLocked: true)  // Face ID cancelled
        #expect(!gate.mountsContent)
        gate.settle(stillLocked: false)
        #expect(gate.mountsContent)
        #expect(!gate.coversContent)
    }

    @Test("locking again after the background keeps the app mounted, only covered, and unlocking uncovers it")
    func relockKeepsContent() {
        var gate = UnlockPresentation(isLocked: true)
        gate.settle(stillLocked: false)
        gate.lock()
        #expect(gate.mountsContent)
        #expect(gate.coversContent)
        gate.settle(stillLocked: true)
        #expect(gate.mountsContent)
        #expect(gate.coversContent)
        gate.settle(stillLocked: false)
        #expect(gate.mountsContent)
        #expect(!gate.coversContent)
    }

    @Test("an unpaired app (the Simulator) is open from the start")
    func unpaired() {
        let gate = UnlockPresentation(isLocked: false)
        #expect(gate.mountsContent)
        #expect(!gate.coversContent)
    }

    @Test("the cover window goes up only over a mounted app — over its sheets and keyboard — and down on unlock")
    func coverWindow() {
        var gate = UnlockPresentation(isLocked: true)
        #expect(!gate.needsCoverWindow)  // cold start: nothing under the in-tree lock screen
        gate.settle(stillLocked: false)
        #expect(!gate.needsCoverWindow)
        gate.lock()
        #expect(gate.needsCoverWindow)
        gate.settle(stillLocked: true)  // Face ID cancelled: stays up
        #expect(gate.needsCoverWindow)
        gate.settle(stillLocked: false)
        #expect(!gate.needsCoverWindow)
        #expect(!UnlockPresentation(isLocked: false).needsCoverWindow)
    }
}
