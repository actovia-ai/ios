import Models
import NetworkingKit
import SwiftUI

/// The workforce (the desktop's Workforce page, read-only here): each team and its employees; a tap shows one.
struct WorkforceView: View {
    let api: PhilharmonicAPI

    @State private var employees: [Employee] = []
    @State private var teams: [Team] = []
    @State private var hasLoaded = false
    @State private var shown: Employee?

    var body: some View {
        List {
            Section {
            } header: {
                PageHeader(title: Text("philharmonic:chat.conversationList.configNav.workforce")) {
                    if hasLoaded, !employees.isEmpty || !teams.isEmpty {
                        Text(verbatim: Self.count(employees.count, one: "employee") + " · " + Self.count(teams.count, one: "team"))
                    }
                }
            }
            ForEach(teams.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { team in
                let members = employees.filter { $0.teamId == team.id }
                Section {
                    if let description = team.description, !description.isEmpty {
                        Text(verbatim: description).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(members) { employeeRow($0) }
                } header: {
                    Text(verbatim: (team.icon.map { "\($0) " } ?? "") + team.name)
                }
            }
            let teamIds = Set(teams.map(\.id))
            let unassigned = employees.filter { $0.teamId.map { !teamIds.contains($0) } ?? true }
            if !unassigned.isEmpty {
                Section {
                    ForEach(unassigned) { employeeRow($0) }
                } header: {
                    Text("philharmonic:workforce.teamSection.unassignedFallback")
                }
            }
        }
        .overlay {
            if !hasLoaded {
                ProgressView()
            } else if employees.isEmpty, teams.isEmpty {
                ContentUnavailableView {
                    Label("philharmonic:workforce.emptyState.title", systemImage: "person.3")
                } description: {
                    Text("philharmonic:workforce.emptyState.description")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $shown) { employee in
            EmployeeDetail(employee: employee, team: teams.first { $0.id == employee.teamId })
                .presentationDetents([.medium, .large])
        }
    }

    private func employeeRow(_ employee: Employee) -> some View {
        Button {
            shown = employee
        } label: {
            HStack(spacing: 12) {
                GroupAvatar(role: .employee, employee: employee)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: employee.name).foregroundStyle(.primary)
                    Text(verbatim: MembersSheet.modelLabel(employee))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        async let people = try? api.employees()
        async let groups = try? api.teams()
        let (loadedPeople, loadedTeams) = await (people, groups)
        if let loadedPeople { employees = loadedPeople.filter { $0.isActive != false } }
        if let loadedTeams { teams = loadedTeams }
        hasLoaded = true
    }

    /// The catalog picks the plural form; the branches only give the English its singular.
    private static func count(_ count: Int, one kind: String) -> String {
        switch (kind, count) {
        case ("team", 1):
            String(localized: "philharmonic:workforce.header.teamCount", defaultValue: "\(count) team")
        case ("team", _):
            String(localized: "philharmonic:workforce.header.teamCount", defaultValue: "\(count) teams")
        case (_, 1):
            String(localized: "philharmonic:workforce.header.employeeCount", defaultValue: "\(count) employee")
        default:
            String(localized: "philharmonic:workforce.header.employeeCount", defaultValue: "\(count) employees")
        }
    }
}

/// One employee, read-only: what it does, its team, what it runs on and its model.
private struct EmployeeDetail: View {
    let employee: Employee
    let team: Team?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        GroupAvatar(role: .employee, employee: employee)
                            .scaleEffect(1.4)
                            .frame(width: 48, height: 48)
                        Text(verbatim: employee.name).font(.title3.weight(.semibold))
                    }
                    if let description = employee.description, !description.isEmpty {
                        Text(verbatim: description).foregroundStyle(.secondary)
                    }
                }
                Section {
                    LabeledContent {
                        Text(verbatim: team.map { ($0.icon.map { "\($0) " } ?? "") + $0.name }
                            ?? String(localized: "philharmonic:workforce.teamSection.unassignedFallback", defaultValue: "No team"))
                    } label: {
                        Text("philharmonic:teams.editor.header.label")
                    }
                    LabeledContent {
                        Text(verbatim: employee.isCli ? AgentCardWording.cliName(employee.runtime)
                            : String(localized: "philharmonic:employees.runtime.actovia", defaultValue: "Actovia"))
                    } label: {
                        Text("philharmonic:employees.runtime.label")
                    }
                    LabeledContent {
                        Text(verbatim: MembersSheet.modelName(employee))
                    } label: {
                        Text("philharmonic:employees.model.label")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common:action.close") { dismiss() }
                }
            }
        }
    }
}
