import SwiftUI

/// The search screen's field: a magnifier, a plain `TextField` and a Cancel button on one line, a hairline under
/// it — Hikki's search is the reference (owner, 2026-10-23). Built by hand because `.searchable` did not respond
/// inside the drawer (see the spec, section 3).
struct SidebarSearchBar: View {
    @Binding var text: String
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("ios:chat.search.label", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("searchField")
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("ios:chat.search.clearButton")
                }
                Button("common:action.cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("searchCancel")
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            Divider()
        }
        .onAppear { focused = true }
    }
}
