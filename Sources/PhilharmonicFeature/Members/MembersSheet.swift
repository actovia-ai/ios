import Models
import SwiftUI

/// Who is in the group and what each is doing (the desktop's members panel): the PM, then each team's members, then
/// those with no team; a coding agent also shows its CLI's quota.
struct MembersSheet: View {
    let model: MembersViewModel
    let teams: [String: Team]
    let busy: BusyAgents

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(
                        avatar: GroupAvatar(role: .pm, employee: nil),
                        name: Text("philharmonic:chat.roles.pm"), detail: nil, quota: nil,
                        activity: busy.label(for: BusyAgents.pm),
                        idle: Text("philharmonic:chat.membersPanel.pmIdleActivity"))
                } header: {
                    Text(verbatim: "🧭 " + String(localized: "philharmonic:chat.membersPanel.coordinatorsLabel", defaultValue: "Coordinators"))
                }
                ForEach(sections, id: \.key) { section in
                    Section {
                        ForEach(section.members) { member in
                            memberRow(member, team: section.team)
                        }
                    } header: {
                        Text(verbatim: section.title)
                    }
                }
            }
            .overlay {
                if model.hasLoaded, model.members.isEmpty {
                    ContentUnavailableView {
                        Label("philharmonic:chat.membersPanel.emptyState.title", systemImage: "person.3")
                    } description: {
                        Text("philharmonic:chat.membersPanel.emptyState.description")
                    }
                }
            }
            .navigationTitle(Text("philharmonic:chat.membersPanel.heading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common:action.close") { dismiss() }
                }
            }
        }
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    private struct TeamSection {
        let key: String
        let title: String
        let team: Team?
        let members: [Employee]
    }

    /// Teams by name, then those with no team (or a team since deleted).
    private var sections: [TeamSection] {
        var byTeam: [String: [Employee]] = [:]
        var unassigned: [Employee] = []
        for member in model.members {
            if let id = member.teamId, teams[id] != nil {
                byTeam[id, default: []].append(member)
            } else {
                unassigned.append(member)
            }
        }
        var result = byTeam.compactMap { id, members -> TeamSection? in
            guard let team = teams[id] else { return nil }
            return TeamSection(
                key: id, title: (team.icon.map { "\($0) " } ?? "") + "\(team.name) · \(members.count)", team: team,
                members: members)
        }
        .sorted { ($0.team?.name ?? "").localizedStandardCompare($1.team?.name ?? "") == .orderedAscending }
        if !unassigned.isEmpty {
            let label = String(localized: "philharmonic:chat.membersPanel.unassignedLabel", defaultValue: "Unassigned")
            result.append(TeamSection(key: "", title: "👤 \(label) · \(unassigned.count)", team: nil, members: unassigned))
        }
        return result
    }

    private func memberRow(_ member: Employee, team: Team?) -> some View {
        let idle = Text(
            verbatim: (team?.name ?? String(localized: "philharmonic:chat.membersPanel.noTeam", defaultValue: "No team"))
                + " · " + String(localized: "philharmonic:chat.membersPanel.idle", defaultValue: "idle"))
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            row(
                avatar: GroupAvatar(role: .employee, employee: member), name: Text(verbatim: member.name),
                detail: Self.modelLabel(member), quota: model.quotaLine(for: member, now: context.date),
                activity: busy.label(for: member.id), idle: idle)
        }
    }

    private func row(
        avatar: GroupAvatar, name: Text, detail: String?, quota: (text: String, isLimited: Bool)?,
        activity: BusyLabel?, idle: Text
    ) -> some View {
        HStack(spacing: 12) {
            avatar
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(activity == nil ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                }
            VStack(alignment: .leading, spacing: 2) {
                name.font(.body.weight(.medium))
                Group {
                    if let detail { Text(verbatim: detail) }
                    if let quota {
                        Text(verbatim: quota.text)
                            .foregroundStyle(quota.isLimited ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                    if let activity {
                        Self.activityText(activity).foregroundStyle(.orange)
                    } else {
                        idle
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func activityText(_ label: BusyLabel) -> Text {
        switch label {
        case .orchestrating: Text("ios:philharmonic.members.orchestrating")
        case .thinking: Text("ios:philharmonic.members.thinking")
        case .running(let tool):
            Text(
                String(
                    localized: "ios:philharmonic.members.running", defaultValue: "Running \(AgentCardWording.toolLabel(tool))…",
                    comment: "What a group member is doing now, under its name. %@ is the tool's name."))
        }
    }

    /// The model it runs on, after its CLI for a coding agent.
    static func modelLabel(_ member: Employee) -> String {
        member.isCli ? AgentCardWording.cliName(member.runtime) + " · " + modelName(member) : modelName(member)
    }

    /// The model alone: its own, the CLI's default, or the app's.
    static func modelName(_ member: Employee) -> String {
        if let model = member.model, !model.isEmpty { return model }
        if member.isCli {
            return String(localized: "philharmonic:employees.model.cliDefault", defaultValue: "The CLI's default")
        }
        return String(localized: "philharmonic:employees.model.default", defaultValue: "Default (the app's model)")
    }
}
