import Foundation

/// The top-level areas of the app. Philharmonic is not available yet, and the drawer leaves it out until it is
/// (`listed`).
enum AppWorkspace: CaseIterable, Identifiable {
    case chat
    case health
    case philharmonic

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .chat:
            LocalizedStringResource(
                "ios:app.workspace.chat", comment: "Name of the chat workspace in the sidebar.")
        case .health:
            LocalizedStringResource(
                "ios:app.workspace.health", comment: "Name of the Health workspace in the sidebar.")
        case .philharmonic:
            LocalizedStringResource("ios:app.workspace.philharmonic")
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .health: "heart.text.square"
        case .philharmonic: "music.note.list"
        }
    }

    var isAvailable: Bool { self != .philharmonic }

    /// What the drawer lists: the workspaces that work. A "Coming soon" row was a promise with nothing behind it.
    static var listed: [AppWorkspace] { allCases.filter(\.isAvailable) }
}
