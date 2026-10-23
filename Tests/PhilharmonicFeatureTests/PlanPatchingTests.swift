import Models
import Testing

@testable import PhilharmonicFeature

@Suite("PlanPatching")
struct PlanPatchingTests {
    private let step = PlanStep(id: "st1", planId: "p1", ordinal: 0, title: "Draft", status: .pending, note: "old")
    private var plan: GroupPlan {
        GroupPlan(id: "p1", conversationId: "c1", summary: "S", status: .active, createdAt: "t", updatedAt: "t", steps: [step])
    }

    @Test("created replaces the plan")
    func createdReplaces() {
        let fresh = GroupPlan(id: "p2", conversationId: "c1", summary: "New", status: .drafting, createdAt: "t", updatedAt: "t", steps: [])
        #expect(PlanPatching.apply(.planCreated(conversationId: "c1", plan: fresh), to: plan) == fresh)
    }

    @Test("an update keeps an absent field, clears a null one and sets a value")
    func stepPatch() {
        let patched = PlanPatching.apply(
            .planStepUpdated(
                conversationId: "c1", stepId: "st1",
                patch: PlanStepPatch(status: .value(.running), output: .value("half"), note: .null)),
            to: plan)
        let s = patched?.steps.first
        #expect(s?.status == .running)
        #expect(s?.output == "half")
        #expect(s?.note == nil)
        #expect(s?.title == "Draft")
    }

    @Test("an update without a plan is ignored")
    func noPlan() {
        #expect(
            PlanPatching.apply(
                .planStepUpdated(conversationId: "c1", stepId: "st1", patch: PlanStepPatch(status: .value(.done))),
                to: nil) == nil)
    }

    @Test("appended adds a step; status changed sets the plan's status")
    func appendAndStatus() {
        let next = PlanStep(id: "st2", planId: "p1", ordinal: 1, title: "Ship", status: .pending)
        let appended = PlanPatching.apply(.planStepAppended(conversationId: "c1", step: next), to: plan)
        #expect(appended?.steps.map(\.id) == ["st1", "st2"])
        #expect(PlanPatching.apply(.planStatusChanged(conversationId: "c1", status: .completed), to: plan)?.status == .completed)
        #expect(PlanPatching.apply(.pmStarted(conversationId: "c1"), to: plan) == plan)
    }
}
