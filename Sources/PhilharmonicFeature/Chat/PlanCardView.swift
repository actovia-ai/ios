import Models
import SwiftUI

/// The PM's plan at the top of a group (the desktop's `PlanCard`): its summary, how far it has got, and each step
/// with who has it. Folded once it is over, or while it has more than four steps.
struct PlanCardView: View {
    let plan: GroupPlan
    let roster: GroupRoster

    @State private var isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(plan: GroupPlan, roster: GroupRoster) {
        self.plan = plan
        self.roster = roster
        _isOpen = State(initialValue: !(plan.status == .completed || plan.status == .aborted || plan.steps.count > 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(verbatim: plan.summary)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // A minute-old label is good enough: redrawn once a minute while the plan runs.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(verbatim: "\(done)/\(plan.steps.count) · \(Self.elapsed(plan, now: context.date))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    statusPill
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isOpen {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(plan.steps) { step in
                        stepRow(step)
                    }
                }
            }
        }
        .background(.fill.tertiary, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var done: Int { plan.steps.filter { $0.status == .done }.count }

    private var statusPill: some View {
        Group {
            switch plan.status {
            case .completed: Text("philharmonic:chat.planCard.status.done")
            case .aborted: Text("philharmonic:chat.planCard.status.aborted")
            case .drafting: Text("philharmonic:chat.planCard.status.draft")
            default: Text("philharmonic:chat.planCard.status.active")
            }
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.background, in: .capsule)
    }

    private func stepRow(_ step: PlanStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            stepGlyph(step.status)
                .font(.caption.weight(.semibold))
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(step.ordinal + 1). \(step.title)")
                    .font(.subheadline.weight(.medium))
                    .strikethrough(step.status == .done)
                    .foregroundStyle(step.status == .done || step.status == .skipped ? .secondary : .primary)
                if let intent = step.intent, !intent.isEmpty {
                    Text(verbatim: intent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let output = step.output, !output.isEmpty, step.status == .done {
                    Text(verbatim: "→ \(output)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let note = step.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let employee = roster.employee(step.assignedAgentId) {
                GroupAvatar(role: .employee, employee: employee)
                    .scaleEffect(0.75)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(step.status == .running ? AnyShapeStyle(.background.opacity(0.6)) : AnyShapeStyle(.clear))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func stepGlyph(_ status: PlanStep.Status) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark").foregroundStyle(.green)
                .accessibilityLabel(Text("philharmonic:chat.planCard.stepStatusAria.done"))
        case .failed:
            Image(systemName: "xmark").foregroundStyle(.red)
                .accessibilityLabel(Text("philharmonic:chat.planCard.stepStatusAria.failed"))
        case .running:
            Image(systemName: "hourglass").foregroundStyle(.orange)
                .accessibilityLabel(Text("philharmonic:chat.planCard.stepStatusAria.running"))
        case .skipped:
            Image(systemName: "slash.circle").foregroundStyle(.secondary)
                .accessibilityLabel(Text("philharmonic:chat.planCard.stepStatusAria.skipped"))
        case .pending, .unknown:
            Image(systemName: "circle").foregroundStyle(.secondary)
                .accessibilityLabel(Text("philharmonic:chat.planCard.stepStatusAria.pending"))
        }
    }

    /// From the plan's start to now, or to its last change once it is over.
    static func elapsed(_ plan: GroupPlan, now: Date) -> String {
        guard let start = GroupTime.date(plan.createdAt) else { return "" }
        let over = plan.status == .completed || plan.status == .aborted
        let end = over ? (GroupTime.date(plan.updatedAt) ?? now) : now
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes < 1 {
            return String(localized: "philharmonic:chat.planCard.elapsed.lessThanMin", defaultValue: "<1 min")
        }
        if minutes < 60 {
            return String(localized: "philharmonic:chat.planCard.elapsed.minutes", defaultValue: "\(String(minutes)) min")
        }
        let hours = String(minutes / 60)
        let rest = String(minutes % 60)
        return String(localized: "philharmonic:chat.planCard.elapsed.hoursMinutes", defaultValue: "\(hours)h \(rest)m")
    }
}
