import Models
import SwiftUI

/// A new group: a title (the desktop's "New group" when left empty) and an optional emoji.
public struct NewGroupSheet: View {
    let model: GroupListViewModel
    let onCreated: (GroupConversation) -> Void

    @State private var title = ""
    @State private var icon = ""
    @State private var isCreating = false
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(model: GroupListViewModel, onCreated: @escaping (GroupConversation) -> Void) {
        self.model = model
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("philharmonic:schedule.form.titleLabel", text: $title,
                    prompt: Text("philharmonic:container.newGroupDefaultTitle"))
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(create)
                TextField("philharmonic:teams.editor.fields.icon", text: $icon)
                    .onChange(of: icon) { _, value in
                        // One emoji: whatever was typed last.
                        if value.count > 1, let last = value.last { icon = String(last) }
                    }
            }
            .navigationTitle("philharmonic:chat.conversationList.newGroupMenuItem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common:action.create", action: create)
                        .disabled(isCreating)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name =
            trimmed.isEmpty
            ? String(localized: "philharmonic:container.newGroupDefaultTitle", defaultValue: "New group") : trimmed
        let emoji = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isCreating = false }
            guard let group = await model.create(title: name, icon: emoji.isEmpty ? nil : emoji) else { return }
            onCreated(group)
            dismiss()
        }
    }
}
