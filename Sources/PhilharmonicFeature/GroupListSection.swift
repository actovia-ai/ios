import ChatFeature
import Models
import SwiftUI
import UIKit

/// What the Philharmonic workspace shows.
public enum PhilharmonicSelection: Hashable, Sendable {
    case group(id: String, title: String)
    case dashboard
    case workforce
    case none

    var groupId: String? { if case .group(let id, _) = self { id } else { nil } }
}

/// The groups in the drawer, where Chat lists Recents, then Dashboard and Workforce.
public struct GroupListSection: View {
    let model: GroupListViewModel
    let selection: PhilharmonicSelection
    let onSelect: (PhilharmonicSelection) -> Void

    @State private var renaming: GroupConversation?
    @State private var renameText = ""
    @State private var deleting: GroupConversation?
    @State private var deletedTrigger = 0

    public init(
        model: GroupListViewModel, selection: PhilharmonicSelection,
        onSelect: @escaping (PhilharmonicSelection) -> Void
    ) {
        self.model = model
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        Section {
            if model.groups.isEmpty {
                if model.hasLoaded {
                    Text("philharmonic:chat.conversationList.emptyState.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(model.groups) { group in
                row(for: group)
            }
        } header: {
            Text("ios:philharmonic.list.groups")
        }
        Section {
            Label("philharmonic:chat.conversationList.configNav.dashboard", systemImage: "chart.bar")
                .sidebarRow(isSelected: selection == .dashboard) { onSelect(.dashboard) }
            Label("philharmonic:chat.conversationList.configNav.workforce", systemImage: "person.3")
                .sidebarRow(isSelected: selection == .workforce) { onSelect(.workforce) }
        }
        .task { await model.load() }
        .alert(
            "philharmonic:chat.conversationList.renameDialog.title",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { group in
            TextField("philharmonic:chat.conversationList.renameDialog.title", text: $renameText)
            Button("common:action.save") {
                let title = renameText
                Task {
                    if await model.rename(group, title: title), selection.groupId == group.id {
                        onSelect(.group(id: group.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("common:action.cancel", role: .cancel) {}
        }
        .alert(
            "philharmonic:chat.conversationList.deleteDialog.title",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { group in
            Button("common:action.delete", role: .destructive) {
                Task {
                    guard await model.delete(group) else { return }
                    deletedTrigger += 1
                    if selection.groupId == group.id { onSelect(.none) }
                }
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: { group in
            Text(
                String(
                    localized: "ios:philharmonic.list.deleteMessage",
                    defaultValue: "“\(group.title)” and all its messages, tasks and executions will be permanently removed."))
        }
        .alert(
            "ios:chat.alert.errorTitle",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("ios:app.alert.ok") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: deletedTrigger)
    }

    private func row(for group: GroupConversation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            GroupIcon(icon: group.icon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(group.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let timestamp = RecentTimestamp.format(group.lastMessageAt) {
                        Text(timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                preview(of: group)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .sidebarRow(isSelected: selection.groupId == group.id, menu: { menu(for: group) }) {
            onSelect(.group(id: group.id, title: group.title))
        }
    }

    private func preview(of group: GroupConversation) -> Text {
        let latest = group.latestMessage?.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return latest.isEmpty ? Text("philharmonic:chat.conversationList.noMessagesYetPreview") : Text(latest)
    }

    private func menu(for group: GroupConversation) -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: String(localized: "philharmonic:chat.conversationList.rename", defaultValue: "Rename"),
                image: UIImage(systemName: "pencil")
            ) { _ in
                renameText = group.title
                renaming = group
            },
            UIAction(
                title: String(localized: "common:action.delete", defaultValue: "Delete"),
                image: UIImage(systemName: "trash"), attributes: .destructive
            ) { _ in deleting = group },
        ])
    }
}

/// A group's emoji, or the workspace's symbol when it has none.
struct GroupIcon: View {
    let icon: String?

    var body: some View {
        if let icon, !icon.isEmpty {
            Text(icon)
        } else {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
        }
    }
}
