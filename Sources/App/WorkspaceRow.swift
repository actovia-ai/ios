import SwiftUI

/// One workspace in the sidebar. An unavailable workspace is disabled and says why.
struct WorkspaceRow: View {
    let option: AppWorkspace
    let isSelected: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(option.title)
                } icon: {
                    Image(systemName: option.systemImage)
                }
                if !option.isAvailable {
                    Spacer()
                    Text("ios:app.workspace.comingSoon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // `.plain` hit-tests the label, not the row, so stretch it and give it a shape: without this
            // a tap to the right of the title would miss. Same pattern as the Recents and search rows.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // `.plain`-like: the row's own foreground, not the button tint, so the unavailable workspace reads as
        // unavailable. The press is reported out so the row's background can show it.
        .buttonStyle(RowPressStyle(isPressed: $isPressed))
        .foregroundStyle(option.isAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .disabled(!option.isAvailable)
        // The same inset pill as the Recents and search rows (`SidebarRow` in ChatFeature): 6% while pressed,
        // 8% for the workspace on screen.
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isPressed ? Color.primary.opacity(0.06)
                        : isSelected ? Color.primary.opacity(0.08) : Color.clear
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        )
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Draws the label as it is and reports whether it is pressed, for the row's background.
private struct RowPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed, initial: true) { _, pressed in isPressed = pressed }
    }
}
