import Models

/// A plan event applied to the plan on show.
public enum PlanPatching {
    public static func apply(_ event: PhilharmonicSseEvent, to plan: GroupPlan?) -> GroupPlan? {
        switch event {
        case .planCreated(_, let fresh):
            return fresh
        case .planStepUpdated(_, let stepId, let patch):
            guard var plan, let index = plan.steps.firstIndex(where: { $0.id == stepId }) else { return plan }
            var step = plan.steps[index]
            if case .value(let status) = patch.status { step.status = status }
            if case .value(let title) = patch.title { step.title = title }
            step.output = patch.output.applied(to: step.output)
            step.note = patch.note.applied(to: step.note)
            step.startedAt = patch.startedAt.applied(to: step.startedAt)
            step.completedAt = patch.completedAt.applied(to: step.completedAt)
            step.assignedAgentId = patch.assignedAgentId.applied(to: step.assignedAgentId)
            step.intent = patch.intent.applied(to: step.intent)
            plan.steps[index] = step
            return plan
        case .planStepAppended(_, let step):
            guard var plan else { return nil }
            if !plan.steps.contains(where: { $0.id == step.id }) { plan.steps.append(step) }
            return plan
        case .planStatusChanged(_, let status):
            guard var plan else { return nil }
            plan.status = status
            return plan
        default:
            return plan
        }
    }
}
