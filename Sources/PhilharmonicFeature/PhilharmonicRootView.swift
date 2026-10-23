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

    public var body: some View {
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
        case .group:
            TranscriptSkeleton()
        case .dashboard, .workforce:
            ProgressView()
        }
    }
}
