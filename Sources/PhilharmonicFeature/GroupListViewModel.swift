import Foundation
import Models
import NetworkingKit
import Observation

/// The groups the drawer lists in the Philharmonic workspace, newest message first. Changes show at once and come
/// back if the computer refused them, as the chat list's do.
@MainActor @Observable
public final class GroupListViewModel {
    public private(set) var groups: [GroupConversation] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var errorMessage: String?

    @ObservationIgnored private let api: PhilharmonicAPI

    public init(api: PhilharmonicAPI) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = Self.sorted(try await api.conversations())
            hasLoaded = true
        } catch {
            guard !Self.isCancellation(error) else { return }
            hasLoaded = true
            errorMessage = error.localizedDescription
        }
    }

    /// The new group, at the top; nil when it could not be made.
    public func create(title: String, icon: String?) async -> GroupConversation? {
        do {
            let group = try await api.createConversation(title: title, icon: icon)
            groups.removeAll { $0.id == group.id }
            groups.insert(group, at: 0)
            return group
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func rename(_ group: GroupConversation, title: String) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == group.id }) else { return false }
        let before = groups[index]
        groups[index].title = trimmed
        do {
            let saved = try await api.renameConversation(id: group.id, title: trimmed, icon: before.icon)
            if let now = groups.firstIndex(where: { $0.id == group.id }) { groups[now] = saved }
            return true
        } catch {
            if let now = groups.firstIndex(where: { $0.id == group.id }) { groups[now] = before }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func delete(_ group: GroupConversation) async -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return false }
        let removed = groups.remove(at: index)
        do {
            try await api.deleteConversation(id: group.id)
            return true
        } catch {
            if !groups.contains(where: { $0.id == group.id }) { groups.insert(removed, at: min(index, groups.endIndex)) }
            guard !Self.isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// ISO 8601 strings of one shape compare as their instants.
    private static func sorted(_ groups: [GroupConversation]) -> [GroupConversation] {
        groups.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
