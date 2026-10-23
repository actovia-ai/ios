import ChatFeature
import MarkdownKit
import Models
import SwiftUI

/// Who is who in a group: the employees and teams a bubble's header names.
struct GroupRoster: Equatable {
    var employees: [String: Employee] = [:]
    var teams: [String: Team] = [:]

    func employee(_ id: String?) -> Employee? { id.flatMap { employees[$0] } }
}

/// One bubble of a group's transcript, as the desktop's `GroupMessageBubble` draws it.
struct GroupBubbleView: View {
    let bubble: GroupBubble
    let roster: GroupRoster
    let model: GroupChatViewModel

    var body: some View {
        switch bubble.role {
        case .user:
            UserBubble(
                text: bubble.text, messageId: bubble.id,
                images: bubble.attachments.filter { $0.contentType.hasPrefix("image/") }.map(\.url))
        case .system:
            VStack(spacing: 4) {
                Text(bubble.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(.fill.tertiary, in: .capsule)
                decision
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        default:
            voice
        }
    }

    /// The PM or an employee: avatar, a header line, then the words (or the coding agent's card).
    private var voice: some View {
        HStack(alignment: .top, spacing: 10) {
            GroupAvatar(role: bubble.role, employee: roster.employee(bubble.agentId))
            VStack(alignment: .leading, spacing: 6) {
                header
                if bubble.role == .employee, let card = bubble.agentCard {
                    AgentCardView(card: card, model: model)
                } else if !bubble.text.isEmpty {
                    MarkdownView(text: bubble.text, isStreaming: bubble.isLive)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.fill.quaternary, in: UnevenRoundedRectangle(
                            topLeadingRadius: 4, bottomLeadingRadius: 18, bottomTrailingRadius: 18,
                            topTrailingRadius: 18, style: .continuous))
                }
                ForEach(bubble.artifacts, id: \.artifactId) { part in
                    ArtifactCard(
                        artifact: ArtifactResult(
                            artifactId: part.artifactId, chatId: nil, title: part.title, code: part.code))
                }
                if bubble.role == .pm { decision }
                if !bubble.toolRows.isEmpty { ToolRowsView(rows: bubble.toolRows) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        let employee = roster.employee(bubble.agentId)
        let team = employee?.teamId.flatMap { roster.teams[$0] }
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Group {
                if bubble.role == .pm {
                    Text("philharmonic:chat.roles.pm")
                } else if let employee {
                    Text(employee.name)
                } else {
                    Text("philharmonic:chat.roles.employeeFallback")
                }
            }
            .foregroundStyle(.primary)
            .fontWeight(.medium)
            if let team {
                Text(verbatim: "· \(team.icon.map { "\($0) " } ?? "")\(team.name)")
            }
            if let time = GroupTime.clock(bubble.createdAt) {
                Text(verbatim: "· \(time)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder private var decision: some View {
        if let roundId = bubble.roundId {
            DecisionProcessView(
                roundId: roundId, bubbleText: bubble.text, counts: bubble.decision, roster: roster, model: model)
        }
    }
}

/// The PM's badge, or an employee's initials.
struct GroupAvatar: View {
    let role: GroupRole
    let employee: Employee?
    @Environment(\.toneAccent) private var toneAccent
    @Environment(\.accentGlyph) private var accentGlyph
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 32

    var body: some View {
        Group {
            if role == .pm {
                Text("philharmonic:chat.roles.pm")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentGlyph)
                    .frame(width: side, height: side)
                    .background(toneAccent, in: .circle)
            } else {
                Text(verbatim: GroupTime.initials(employee?.name))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: side, height: side)
                    .background(.fill.secondary, in: .circle)
            }
        }
        .accessibilityHidden(true)
    }
}

enum GroupTime {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func date(_ iso8601: String?) -> Date? {
        guard let iso8601 else { return nil }
        return (try? fractional.parse(iso8601)) ?? (try? Date.ISO8601FormatStyle().parse(iso8601))
    }

    /// "3:42 PM" in the reader's locale.
    static func clock(_ iso8601: String?) -> String? {
        date(iso8601)?.formatted(date: .omitted, time: .shortened)
    }

    static func initials(_ name: String?) -> String {
        let words = (name ?? "").split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "·" : letters
    }
}
