import ChatFeature
import NetworkingKit
import OdyKit
import SwiftUI

/// One group, live: the plan, the transcript and the composer (the desktop's `GroupChat`). The transcript and the
/// composer take the colour tone; the rest stays neutral.
///
/// The model and its stream are made once, when the screen first appears — not in `init`, which runs on every
/// redraw of the parent and made a model and a stream each time only to drop them (ISSUE-249 M7).
struct GroupChatView: View {
    let conversationId: String
    let api: PhilharmonicAPI
    let makeStream: () -> GroupStream
    let onGone: () -> Void

    @State private var model: GroupChatViewModel?

    var body: some View {
        if let model {
            GroupChatScreen(model: model, api: api, onGone: onGone)
        } else {
            Color.clear.onAppear {
                model = GroupChatViewModel(conversationId: conversationId, api: api, stream: makeStream())
            }
        }
    }
}

/// Coming back to the foreground, as the group's stream needs to know it: only from `.background`, where a
/// connection may have died with the app. Pulling down Control Center goes `.inactive → .active` and leaves a
/// healthy stream alone (ISSUE-249 M6).
struct ForegroundReturn {
    private var wasInBackground = false

    /// Whether this phase is a return from the background.
    mutating func observe(_ phase: ScenePhase) -> Bool {
        switch phase {
        case .background:
            wasInBackground = true
            return false
        case .active:
            defer { wasInBackground = false }
            return wasInBackground
        default:
            return false
        }
    }
}

private struct GroupChatScreen: View {
    let model: GroupChatViewModel
    let api: PhilharmonicAPI
    let onGone: () -> Void

    @State private var roster = GroupRoster()
    /// Nil until the group's row is read: Members tapped before then reads it itself (ISSUE-249 M3).
    @State private var memberIds: [String]?
    @State private var members: MembersViewModel?
    @State private var foreground = ForegroundReturn()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.toneInk) private var toneInk

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let plan = model.plan, !plan.steps.isEmpty {
                    PlanCardView(plan: plan, roster: roster)
                }
                ForEach(model.bubbles) { bubble in
                    GroupBubbleView(bubble: bubble, roster: roster, model: model)
                        .tint(toneInk)
                }
                if model.pmRunning, !model.bubbles.contains(where: \.isLive) {
                    TypingIndicator()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .readingColumn()
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if model.isLoading, model.bubbles.isEmpty {
                TranscriptSkeleton()
            } else if model.bubbles.isEmpty, model.plan == nil {
                ContentUnavailableView {
                    Label("philharmonic:chat.groupChat.emptyState.title", systemImage: "person.3")
                } description: {
                    Text("philharmonic:chat.groupChat.emptyState.description")
                }
                .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top) {
            if let notice = model.notice { banner(notice) }
        }
        .safeAreaInset(edge: .bottom) {
            GroupComposer(model: model)
                .readingColumn()
                .tint(toneInk)
        }
        .task {
            await model.start()
        }
        .task(id: model.memberJoins) {
            // Who is who: names, teams, CLIs. A failed read leaves the fallbacks ("Employee"). Read again when a
            // member joins.
            async let employees = try? api.employees()
            async let teams = try? api.teams()
            async let conversations = try? api.conversations()
            let (people, groups, all) = await (employees, teams, conversations)
            if let all { memberIds = all.first { $0.id == model.conversationId }?.memberAgentIds ?? [] }
            roster = GroupRoster(
                employees: Dictionary((people ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                teams: Dictionary((groups ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        .onDisappear { model.stop() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    members = MembersViewModel(api: api, memberIds: memberIds, conversationId: model.conversationId)
                } label: {
                    Label("philharmonic:chat.membersPanel.heading", systemImage: "person.2")
                }
                .accessibilityIdentifier("groupMembers")
            }
        }
        .sheet(item: $members) { members in
            MembersSheet(model: members, teams: roster.teams, busy: model.busy)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: scenePhase) { _, phase in
            if foreground.observe(phase) { Task { await model.resume() } }
        }
        .onChange(of: model.notice) { _, notice in
            if notice == .gone { onGone() }
        }
    }

    @ViewBuilder private func banner(_ notice: GroupNotice) -> some View {
        Group {
            switch notice {
            case .locked:
                Label("ios:philharmonic.chat.locked", systemImage: "lock")
            case .error(let message):
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            case .gone:
                EmptyView()
            }
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 4)
    }
}
