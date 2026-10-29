import Foundation
import Models
import NetworkingKit
import Observation

/// A group's members and what their CLIs last said of the owner's quota (the desktop's members panel). The quota is
/// read when the sheet opens and once a minute while it stays open.
@MainActor @Observable
public final class MembersViewModel {
    public private(set) var members: [Employee] = []
    /// By CLI (`claude-code`, `codex`).
    public private(set) var quotas: [String: CliQuota] = [:]
    public private(set) var hasLoaded = false

    @ObservationIgnored private let api: PhilharmonicAPI
    /// Nil until the group's own list is read (`conversationId`): the sheet can open before the group has.
    @ObservationIgnored private let memberIds: [String]?
    @ObservationIgnored private let conversationId: String?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var polling: Task<Void, Never>?

    /// `memberIds` nil: the group's members are read from its row (`conversationId`) — Members tapped before the
    /// screen had them used to open an empty sheet (ISSUE-249 M3).
    public init(
        api: PhilharmonicAPI, memberIds: [String]?, conversationId: String? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.api = api
        self.memberIds = memberIds
        self.conversationId = conversationId
        self.sleep = sleep
    }

    public func start() {
        guard polling == nil else { return }
        let sleep = sleep
        polling = Task { [weak self] in
            await self?.loadMembers()
            while !Task.isCancelled {
                // The model is held only for the read, never across the sleep; once it is gone the loop ends
                // instead of spinning on a nil `self?.sleep` that never waited (ISSUE-249 M1).
                guard await self?.readQuota() != nil else { return }
                do { try await sleep(.seconds(60)) } catch { return }
            }
        }
    }

    public func stop() {
        polling?.cancel()
        polling = nil
    }

    /// "5h 100% · week 42% · limit reached · resets Thu 15:00" for a coding agent whose CLI has reported its quota;
    /// red once a window it stopped on has not reset yet.
    public func quotaLine(for employee: Employee, now: Date) -> (text: String, isLimited: Bool)? {
        guard employee.isCli, let quota = quotas[employee.runtime] else { return nil }
        let parts = QuotaWording.parts(quota, now: now)
        guard !parts.isEmpty else { return nil }
        let text = parts.map(Self.wording).joined(separator: " · ")
        guard let limit = parts.first(where: { $0.limited && !$0.reset }) else { return (text, false) }
        guard let resetsAt = limit.resetsAt else { return (text, true) }
        let time = resetsAt.formatted(.dateTime.weekday(.abbreviated).hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits))
        return (
            text + " · "
                + String(
                    localized: "philharmonic:chat.membersPanel.quota.limited",
                    defaultValue: "limit reached · resets \(time)"),
            true
        )
    }

    private static func wording(_ part: QuotaPart) -> String {
        let percent = String(part.percent)
        switch part.key {
        case .fiveHour:
            return String(localized: "philharmonic:chat.membersPanel.quota.fiveHour", defaultValue: "5h \(percent)%")
        case .sevenDay:
            return String(localized: "philharmonic:chat.membersPanel.quota.sevenDay", defaultValue: "week \(percent)%")
        case .other:
            let name = part.name
            return String(localized: "philharmonic:chat.membersPanel.quota.other", defaultValue: "\(name) \(percent)%")
        }
    }

    private func loadMembers() async {
        defer { hasLoaded = true }
        async let people = try? api.employees()
        let ids: [String]
        if let memberIds {
            ids = memberIds
        } else if let conversationId, let groups = try? await api.conversations() {
            ids = groups.first { $0.id == conversationId }?.memberAgentIds ?? []
        } else {
            ids = []
        }
        guard let everyone = await people else { return }
        let byId = Dictionary(everyone.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        members = ids.compactMap { byId[$0] }
    }

    /// A failed read keeps the last one: a stale line beats none, and the next minute tries again.
    private func readQuota() async {
        guard let read = try? await api.quota() else { return }
        quotas = Dictionary(read.map { ($0.cli, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// One sheet per opening: the sheet is keyed by the model it was opened with.
extension MembersViewModel: Identifiable {}
