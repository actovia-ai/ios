import ChatFeature
import NetworkingKit
import OdyKit
import SwiftUI

/// One group, live: the plan, the transcript and the composer (the desktop's `GroupChat`). The transcript and the
/// composer take the colour tone; the rest stays neutral.
struct GroupChatView: View {
    let api: PhilharmonicAPI
    let onGone: () -> Void

    @State private var model: GroupChatViewModel
    @State private var roster = GroupRoster()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.toneInk) private var toneInk

    init(conversationId: String, api: PhilharmonicAPI, stream: GroupStream, onGone: @escaping () -> Void) {
        self.api = api
        self.onGone = onGone
        _model = State(initialValue: GroupChatViewModel(conversationId: conversationId, api: api, stream: stream))
    }

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
        .task {
            // Who is who: names, teams, CLIs. A failed read leaves the fallbacks ("Employee").
            async let employees = try? api.employees()
            async let teams = try? api.teams()
            let (people, groups) = await (employees, teams)
            roster = GroupRoster(
                employees: Dictionary((people ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                teams: Dictionary((groups ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resume() } }
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
