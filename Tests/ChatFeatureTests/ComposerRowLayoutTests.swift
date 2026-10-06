import CoreGraphics
import Testing

@testable import ChatFeature

@Suite("The composer's row: a pill while the text fits one line, the field over the buttons once it wraps")
struct ComposerRowLayoutTests {
    let button = CGSize(width: 32, height: 32)

    func plan(
        width: CGFloat = 360, trailing: [CGSize]? = nil, text: @escaping (CGFloat) -> CGFloat
    ) -> ComposerRowPlan {
        ComposerRowPlan.make(
            width: width, leading: [button], trailing: trailing ?? [button], fieldHeight: text, spacing: 8,
            rowSpacing: 6, oneLineHeight: 22)
    }

    @Test("one line: `+`, the field and the button share a 32pt row, the field centred between them")
    func compact() {
        let plan = plan { _ in 22 }
        #expect(!plan.expanded)
        #expect(plan.size == CGSize(width: 360, height: 32))
        #expect(plan.leading == [CGRect(x: 0, y: 0, width: 32, height: 32)])
        // 360 less two 32pt buttons and the 8pt either side of the field.
        #expect(plan.field == CGRect(x: 40, y: 5, width: 280, height: 22))
        #expect(plan.trailing == [CGRect(x: 328, y: 0, width: 32, height: 32)])
    }

    @Test("wrapped: the field takes the top at full width, the buttons a row under it")
    func expanded() {
        let plan = plan { _ in 44 }
        #expect(plan.expanded)
        #expect(plan.field == CGRect(x: 0, y: 0, width: 360, height: 44))
        // 44 of field, 6 between, 32 of buttons.
        #expect(plan.size.height == 82)
        #expect(plan.leading.first?.origin == CGPoint(x: 0, y: 50))
        #expect(plan.trailing.first?.origin == CGPoint(x: 328, y: 50))
    }

    @Test("decided at the width beside the buttons: text that fits the wide line alone still expands, and stays")
    func measuredBesideTheButtons() {
        // Two lines at 280pt, one at 360pt.
        let plan = plan { width in width < 300 ? 44 : 22 }
        #expect(plan.expanded)
        #expect(plan.field == CGRect(x: 0, y: 0, width: 360, height: 22))
    }

    @Test("a line and a half is the mark")
    func threshold() {
        #expect(!ComposerRowPlan.expands(fieldHeight: 22, oneLineHeight: 22))
        #expect(!ComposerRowPlan.expands(fieldHeight: 33, oneLineHeight: 22))
        #expect(ComposerRowPlan.expands(fieldHeight: 34, oneLineHeight: 22))
        #expect(ComposerRowPlan.expands(fieldHeight: 44, oneLineHeight: 22))
    }

    @Test("a second trailing button (hide keyboard) sits left of the first, centred, the field giving way")
    func twoTrailingButtons() {
        let plan = plan(trailing: [CGSize(width: 28, height: 28), button]) { _ in 22 }
        #expect(plan.trailing.map(\.minX) == [292, 328])
        #expect(plan.trailing[0].midY == 16)
        // 360 less the three buttons (32, 28, 32) and the 8 beside each of them.
        #expect(plan.field.width == 244)
    }

    @Test("a row narrower than its buttons leaves the field no width rather than a negative one")
    func narrow() {
        let plan = plan(width: 60) { _ in 22 }
        #expect(plan.field.width == 0)
    }
}
