import ChatFeature
import NetworkingKit
import SwiftUI

/// The Philharmonic workspace's card: the group, Dashboard or Workforce picked in the drawer.
public struct PhilharmonicRootView: View {
    let api: PhilharmonicAPI
    let selection: PhilharmonicSelection
    let onNewGroup: () -> Void
    /// The group on show was deleted elsewhere.
    let onGroupGone: () -> Void

    public init(
        api: PhilharmonicAPI, selection: PhilharmonicSelection, onNewGroup: @escaping () -> Void,
        onGroupGone: @escaping () -> Void = {}
    ) {
        self.api = api
        self.selection = selection
        self.onNewGroup = onNewGroup
        self.onGroupGone = onGroupGone
    }

    static func stream(_ conversationId: String, api: PhilharmonicAPI) -> GroupStream {
        GroupStream(
            connect: { try api.streamEvents(conversationId: conversationId) },
            unlock: { await api.unlockComputer() })
    }

    public var body: some View {
        content
            // Employees' faces, wherever this workspace draws them: the transcript, the plan, members, Workforce.
            .environment(\.employeeAvatars, EmployeeAvatars(api: api))
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .none:
            ContentUnavailableView {
                Label("philharmonic:container.noGroupSelected.title", systemImage: "person.2")
            } description: {
                Text("philharmonic:container.noGroupSelected.description")
            } actions: {
                Button("philharmonic:container.noGroupSelected.createButton", action: onNewGroup)
                    .buttonStyle(.glassProminent)
            }
        case .group(let id, _):
            GroupChatView(conversationId: id, api: api, stream: Self.stream(id, api: api), onGone: onGroupGone)
                .id(id)
        case .dashboard:
            DashboardView(api: api)
        case .workforce:
            WorkforceView(api: api)
        }
    }
}
