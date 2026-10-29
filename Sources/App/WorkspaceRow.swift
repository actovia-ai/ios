import ChatFeature
import SwiftUI

/// One workspace in the sidebar: a `sidebarRow` like every other row — the icon in the shared column, the quiet
/// selected fill, and a tap that leaves a swipe to the drawer (ISSUE-297). An unavailable workspace says why and
/// does nothing.
struct WorkspaceRow: View {
    let option: AppWorkspace
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            SidebarLabel(option.title, systemImage: option.systemImage)
            if !option.isAvailable {
                Spacer()
                Text("ios:app.workspace.comingSoon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(option.isAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .sidebarRow(isSelected: isSelected) {
            if option.isAvailable { action() }
        }
    }
}
