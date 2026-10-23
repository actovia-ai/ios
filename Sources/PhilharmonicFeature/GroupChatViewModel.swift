import ChatFeature
import Foundation
import Models
import NetworkingKit
import Observation

/// Something the group's screen says above its transcript.
public enum GroupNotice: Sendable, Equatable {
    /// The group was deleted (on the computer or another device).
    case gone
    /// The computer is locked and was not unlocked.
    case locked
    case error(String)
}

/// The PM's question (`ask_user`), waiting for the owner.
public struct GroupQuestion: Sendable, Equatable {
    public let question: String
    public let options: [String]

    public init(question: String, options: [String]) {
        self.question = question
        self.options = options
    }
}

/// One open group: its saved rows, what the stream is writing now, the plan, and the PM's state.
@MainActor @Observable
public final class GroupChatViewModel {
    public let conversationId: String

    public private(set) var bubbles: [GroupBubble] = []
    public private(set) var plan: GroupPlan?
    public private(set) var askUser: GroupQuestion?
    public private(set) var pmRunning = false
    public private(set) var busy = BusyAgents()
    public private(set) var notice: GroupNotice?
    public private(set) var isLoading = true
    /// Prompts answered from here, or found answered elsewhere: drawn settled, never asked again.
    public private(set) var settledPrompts: Set<String> = []

    @ObservationIgnored private let api: PhilharmonicAPI
    @ObservationIgnored private let stream: GroupStream
    @ObservationIgnored private var history: [GroupMessage] = []
    @ObservationIgnored private var live: [LiveBubble] = []
    @ObservationIgnored private var liveCards: [String: AgentCard] = [:]
    @ObservationIgnored private var rounds: [String: [PmRoundEvent]] = [:]
    @ObservationIgnored private var listening: Task<Void, Never>?

    public init(conversationId: String, api: PhilharmonicAPI, stream: GroupStream) {
        self.conversationId = conversationId
        self.api = api
        self.stream = stream
    }

    /// Starts listening. The group is read whole each time the stream connects (missed events are not replayed).
    public func start() async {
        guard listening == nil else { return }
        let updates = await stream.updates()
        listening = Task { [weak self] in
            for await update in updates {
                guard let self, !Task.isCancelled else { return }
                await self.handle(update)
            }
        }
    }

    public func stop() {
        listening?.cancel()
        listening = nil
    }

    /// Back in the foreground: the connection may have died while the app slept.
    public func resume() async {
        await stream.reconnectNow()
    }

    // MARK: Acting

    /// Sends a message; false when it did not go (the composer keeps its text).
    @discardableResult
    public func send(text: String, pictures: [ComposerPicture]) async -> Bool {
        let attachments = pictures.enumerated().map { index, picture in
            OutgoingAttachment(
                name: "photo-\(index + 1).\(picture.mimeType == "image/png" ? "png" : "jpg")", url: picture.dataURL,
                contentType: picture.mimeType)
        }
        do {
            let row = try await api.send(conversationId: conversationId, content: text, attachments: attachments)
            history = GroupHistory.append(history, [row])
            rebuild()
            return true
        } catch {
            report(error)
            return false
        }
    }

    public func interrupt() async {
        do { _ = try await api.interrupt(conversationId: conversationId) } catch { report(error) }
    }

    /// Answers the PM's question.
    public func answer(_ text: String) async {
        do {
            try await api.answerAskUser(conversationId: conversationId, response: text)
            askUser = nil
        } catch {
            report(error)
        }
    }

    /// Answers a coding agent's prompt. Answered elsewhere already is not an error: the prompt just settles.
    public func respond(card: AgentCard, prompt: AgentPrompt, answer: AgentAnswer) async {
        guard let requestId = prompt.requestId else { return }
        do {
            _ = try await api.respond(sessionId: card.sessionId, requestId: requestId, answer: answer)
            settledPrompts.insert(requestId)
        } catch {
            report(error)
        }
    }

    /// A PM round's decision trail, read once.
    public func round(_ roundId: String) async -> [PmRoundEvent] {
        if let cached = rounds[roundId] { return cached }
        guard let events = try? await api.round(conversationId: conversationId, roundId: roundId) else { return [] }
        rounds[roundId] = events
        return events
    }

    // MARK: The stream

    private func handle(_ update: GroupStreamUpdate) async {
        switch update {
        case .connected:
            // What was being written while away is not replayed; the saved rows say how it ended.
            live = []
            liveCards = [:]
            await readWhole()
        case .event(let event):
            await apply(event)
        case .disconnected:
            break
        case .gone:
            gone()
        case .locked:
            notice = .locked
            stop()
        }
    }

    private func apply(_ event: PhilharmonicSseEvent) async {
        guard event.conversationId == conversationId else { return }
        busy.apply(event)
        switch event {
        case .messageStart(_, let messageId, let role, let agentId):
            if !live.contains(where: { $0.messageId == messageId }) {
                live.append(LiveBubble(messageId: messageId, role: role, agentId: agentId))
            }
        case .messageDelta(_, let messageId, let delta):
            updateLive(messageId) { $0.text = delta }
        case .toolCard(_, let messageId, let toolName, let phase, let result):
            updateLive(messageId) { bubble in
                let row = ToolRow(toolName: toolName, phase: phase, result: result)
                if phase == .end,
                    let index = bubble.toolRows.lastIndex(where: { $0.toolName == toolName && $0.phase == .start })
                {
                    bubble.toolRows[index] = row
                } else {
                    bubble.toolRows.append(row)
                }
            }
        case .agentCard(_, let messageId, let card):
            liveCards[messageId] = card
        case .messageEnd:
            await readAfter()
            return
        case .planCreated, .planStepUpdated, .planStepAppended, .planStatusChanged:
            plan = PlanPatching.apply(event, to: plan)
            return
        case .askUser(_, let question, let options):
            askUser = GroupQuestion(question: question, options: options)
        case .pmStarted:
            pmRunning = true
        case .pmEnded:
            pmRunning = false
            askUser = nil
        case .conversationError(_, let error):
            notice = .error(error)
        default:
            return
        }
        rebuild()
    }

    private func updateLive(_ messageId: String, _ change: (inout LiveBubble) -> Void) {
        guard let index = live.firstIndex(where: { $0.messageId == messageId }) else { return }
        change(&live[index])
    }

    // MARK: Reading

    private func readWhole() async {
        do {
            async let rows = api.messages(conversationId: conversationId)
            async let current = api.plan(conversationId: conversationId)
            let fresh = try await rows
            plan = try await current
            // A deleted group reads as an empty one: only the list of groups tells them apart.
            if fresh.isEmpty, !(try await api.conversations().contains(where: { $0.id == conversationId })) {
                gone()
                return
            }
            // Rows an earlier read held that this one missed (saved while it was on its way) stay.
            let freshIds = Set(fresh.map(\.id))
            history = fresh + history.filter { !freshIds.contains($0.id) }
            if notice == .locked { notice = nil }
        } catch let error as HTTPError where error.statusCode == 404 {
            gone()
            return
        } catch {
            report(error)
        }
        isLoading = false
        rebuild()
    }

    /// After a `message_end`: only what was saved after the last row held; anything wrong reads the group whole.
    private func readAfter() async {
        guard let last = history.last?.id else { return await readWhole() }
        do {
            let rows = try await api.messages(conversationId: conversationId, after: last)
            history = GroupHistory.append(history, rows)
            rebuild()
        } catch {
            await readWhole()
        }
    }

    private func rebuild() {
        let saved = Set(history.map(\.id))
        live.removeAll { saved.contains($0.messageId) }
        bubbles = GroupMessageMerge.merge(history: history, live: live, liveCards: liveCards)
    }

    private func gone() {
        notice = .gone
        isLoading = false
        stop()
    }

    private func report(_ error: Error) {
        if let error = error as? HTTPError, error.statusCode == 404 { return gone() }
        notice = .error(error.localizedDescription)
    }
}

extension PhilharmonicSseEvent {
    /// The group an event is about; nil for one this build does not know.
    var conversationId: String? {
        switch self {
        case .messageStart(let id, _, _, _), .messageDelta(let id, _, _), .messageEnd(let id, _),
            .toolCard(let id, _, _, _, _), .agentCard(let id, _, _), .memberJoined(let id, _), .roundStart(let id, _),
            .askUser(let id, _, _), .conversationError(let id, _), .pmStarted(let id), .pmEnded(let id, _),
            .delegationRetry(let id, _, _, _, _, _), .planCreated(let id, _), .planStepUpdated(let id, _, _),
            .planStepAppended(let id, _), .planStatusChanged(let id, _):
            id
        case .unknown:
            nil
        }
    }
}
