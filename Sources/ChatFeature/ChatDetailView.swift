import MarkdownKit
import Models
import NetworkingKit
import OdyKit
import SwiftUI

/// What a new chat opens on when a widget's round button started it: the camera, or recording (`ChatDetailView`'s
/// `initialOpening`). The widget's own link type lives in WidgetKitShared, which this module does not see.
public enum ComposerOpening: Sendable {
    case camera, voice
}

public struct ChatDetailView: View {
    /// This screen's view model, stores and loaders, built on first use and kept for the view's lifetime.
    /// `State(initialValue:)` is not lazy: building them in `init` built (and threw away) a full set on every re-render
    /// of the parent. Only the empty box is made per `init`.
    @State private var objectsBox = LazyBox<ChatScreenObjects>()
    private let makeObjects: @MainActor () -> ChatScreenObjects
    private var objects: ChatScreenObjects { objectsBox.value(makeObjects) }
    private var viewModel: ChatDetailViewModel { objects.viewModel }
    /// One line of the composer's text at the reader's size: past one and a half of it the field has wrapped and
    /// takes the row's top (`ComposerRowLayout`).
    @ScaledMetric(relativeTo: .body) private var composerLineHeight: CGFloat = 22
    /// Return inserts a newline in the multi-line composer, so the keyboard needs somewhere else to
    /// go: the composer's hide-keyboard button and a tap on the transcript both clear this.
    @FocusState private var isComposerFocused: Bool
    /// The Sources sheet, from an answer's Sources button or a tapped citation chip.
    @State private var sourcesSheet: SourcesSheetModel?
    /// The entity link tapped in an answer, whose Wikipedia summary a sheet shows.
    @State private var entity: EntityRequest?
    /// A folded answer opened from its "other version" link.
    @State private var otherVersion: OtherVersion?
    /// When a long press threw a recording away: the tap its release ends in must not start another.
    @State private var recordingDiscardedAt: Date?
    /// The end of the transcript is in view (`TranscriptEnd`): a streaming reply is followed only then.
    @State private var isAtEnd = true
    /// The older pages whose arrival the transcript has already answered: a page put in above is not a new message,
    /// and must not scroll the reader to the end.
    @State private var handledOlderPages = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.colorTone) private var colorTone
    @Environment(\.toneInk) private var toneInk
    @Environment(\.toneAccent) private var toneFillColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    /// The app session's `+` choices, from the app shell; nil (a preview) leaves the menu with pictures only.
    @Environment(ComposerTools.self) private var composerTools: ComposerTools?
    /// Kept alongside the view model, not just handed to its `init`: a rename from the sidebar
    /// while this chat is the one on screen changes this on a re-render, which `.onChange` below
    /// turns into a push into the already-running view model (its own `@State` only reads `init`'s
    /// value once, so a new `title:` argument alone would otherwise be silently ignored).
    private let title: String?
    /// A question handed over from Health, sent once the (new) chat's history is known.
    private let isNew: Bool
    private let initialMessage: String?
    private let onInitialMessageSent: (() -> Void)?
    /// A prompt handed over from a widget: put in the composer, never sent by itself.
    private let initialDraft: String?
    private let onInitialDraftUsed: (() -> Void)?
    /// What a widget's round button opens this new chat on: the camera, or recording.
    private let initialOpening: ComposerOpening?
    private let onInitialOpeningUsed: (() -> Void)?

    public init(
        chatId: String, title: String? = nil, isNew: Bool = false, apiClient: APIClient,
        streamManager: ChatStreamManager, serverConfig: ServerConfigStore, initialMessage: String? = nil,
        onInitialMessageSent: (() -> Void)? = nil,
        initialDraft: String? = nil, onInitialDraftUsed: (() -> Void)? = nil,
        initialOpening: ComposerOpening? = nil, onInitialOpeningUsed: (() -> Void)? = nil
    ) {
        self.title = title
        self.isNew = isNew
        self.initialDraft = initialDraft
        self.initialOpening = initialOpening
        self.onInitialOpeningUsed = onInitialOpeningUsed
        self.onInitialDraftUsed = onInitialDraftUsed
        self.initialMessage = initialMessage
        self.onInitialMessageSent = onInitialMessageSent
        makeObjects = {
            ChatScreenObjects(
                chatId: chatId, title: title, apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
        }
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if viewModel.hasOlder {
                        OlderHistoryRow(isLoading: viewModel.isLoadingOlder)
                            .onAppear { loadOlder(proxy) }
                    }
                    TranscriptRows(
                        segments: viewModel.segments, streamingTurnId: viewModel.streamingTurnId,
                        showsTypingIndicator: viewModel.showsPendingRow, liveError: viewModel.liveRunError,
                        actions: transcriptActions)
                }
                .padding(.horizontal)
                .readingColumn()
                .padding(.top, 8)
                // What is scrolled to: the end of the transcript and the room that keeps its last line off the
                // composer.
                .padding(.bottom, TranscriptRows.endRoom)
                .id(TranscriptRows.endID)
                .environment(\.generatedImageLoader, objects.imageLoader)
                .environment(\.computerUseFrames, viewModel.computerUseFrames)
                .environment(\.computerUseRemote, objects.computerUseRemote)
                .environment(\.deepResearchJobs, objects.researchJobs)
                .environment(\.runApprovals, viewModel.approvals)
                .environment(\.memoryFoot, viewModel.memoryFoot)
                .environment(\.placePhotoLoader, objects.placePhotos)
                .environment(\.workspaceFileLoader, objects.workspaceFiles)
                .environment(\.artifactSandbox, objects.artifactSandbox)
                .environment(\.readAloud, viewModel.readAloud)
                .environment(\.markdownAskAbout, MarkdownAskAction { [viewModel] text in viewModel.askAbout(text) })
                .environment(\.markdownEntityTap, MarkdownEntityAction { title in entity = EntityRequest(title: title) })
            }
            // Pull down to retry a history load that failed (the composer stays disabled until it succeeds).
            .scrollBounceBehavior(.always)
            .scrollDismissesKeyboard(.interactively)
            // What scrolls under the composer fades out, as under the title bar. Set, not left to the default: the
            // default left the bottom edge bare, and a reply showed sharp below the bar and doubled in its glass.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // Tapping the transcript puts the keyboard away. Rows are not inert — an answer's
            // Markdown holds tappable links, a timeline expands, a card opens — so this is
            // attached *simultaneously*: it recognises alongside whatever the content does instead
            // of competing with it, and a link inside a bubble still opens (measured with the
            // keyboard both up and down). A tap gesture also does not consume the drag that
            // scrolling, the interactive keyboard dismissal above and pull-to-refresh all need.
            .simultaneousGesture(TapGesture().onEnded { isComposerFocused = false })
            .refreshable {
                await viewModel.loadHistory()
                await viewModel.loadMemoryUsage()
            }
            .transcriptEnd(isAtEnd: $isAtEnd) { scrollToBottom(proxy, animated: true) }
            .onChange(of: viewModel.segments.count) { old, new in
                if viewModel.olderPageCount != handledOlderPages {
                    handledOlderPages = viewModel.olderPageCount
                    return
                }
                scrollToBottom(proxy, animated: TranscriptRules.animatesScroll(fromSegmentCount: old, to: new))
            }
            // Follow a reply as it streams in: the segment count is constant while the last turn grows. Not once
            // the reader has scrolled up — the button over the composer brings them back.
            .onChange(of: scrollKey) {
                if isAtEnd { scrollToBottom(proxy, animated: false) }
            }
            // Sending adds the pending row; reaching it is the point of `isTurnInFlight` flipping.
            .onChange(of: viewModel.isTurnInFlight) {
                scrollToBottom(proxy, animated: true)
            }
        }
        .overlay(alignment: .top) {
            if !viewModel.hasLoadedHistory && viewModel.errorMessage == nil {
                TranscriptSkeleton().allowsHitTesting(false)
            }
        }
        .overlay {
            if viewModel.showsEmptyState {
                // The literal first and last thing every new chat shows, so it earns a beat rather
                // than a hard cut (apple-design: preventing a jarring change). Pure opacity is
                // already Reduce-Motion-safe as written.
                emptyState.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.showsEmptyState)
        .safeAreaBar(edge: .bottom) {
            NoticeStack(notice: viewModel.notice, onDismiss: viewModel.dismissNotice) { composer }
        }
        .sheet(item: $sourcesSheet) { SourcesSheet(model: $0) }
        .sheet(item: $entity) { EntitySheet(title: $0.title, loader: objects.entities) }
        .sheet(item: $otherVersion) { version in
            OtherVersionSheet(version: version) { [viewModel] in
                Task { await viewModel.choose(runId: version.id) }
            }
            .environment(\.generatedImageLoader, objects.imageLoader)
            .environment(\.computerUseFrames, viewModel.computerUseFrames)
            .environment(\.computerUseRemote, objects.computerUseRemote)
            .environment(\.deepResearchJobs, objects.researchJobs)
            .environment(\.runApprovals, viewModel.approvals)
            .environment(\.memoryFoot, viewModel.memoryFoot)
            .environment(\.placePhotoLoader, objects.placePhotos)
            .environment(\.workspaceFileLoader, objects.workspaceFiles)
            .environment(\.artifactSandbox, objects.artifactSandbox)
        }
        .onChange(of: viewModel.choiceCount) {
            AccessibilityNotification.Announcement(CompareText.chosen).post()
        }
        // The banner goes after a few seconds; VoiceOver would never reach it, so it is spoken when it arrives.
        .onChange(of: viewModel.notice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(NoticeBanner.announcement(for: notice)).post() }
        }
        .navigationTitle(viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // First: a turn reads the session's choices when it starts, and one may start right below.
            viewModel.composerTools = composerTools
            await viewModel.onAppear(isNew: isNew)
            if let initialMessage {
                // Handed over now, not when the reply ends: the question is this chat's from here on.
                onInitialMessageSent?()
                await viewModel.sendInitial(initialMessage)
            }
            if let initialDraft {
                // Handed over now: the chat screen is made again on a later visit, and must not fill it again.
                viewModel.applyDraft(initialDraft)
                onInitialDraftUsed?()
            }
            if let initialOpening {
                onInitialOpeningUsed?()
                switch initialOpening {
                case .camera: viewModel.requestCamera()
                case .voice: await viewModel.startRecording()
                }
            }
        }
        // Apart from `onAppear`, which waits out a turn it re-attaches to.
        .task(id: viewModel.hasLoadedHistory) { await viewModel.loadMemoryUsage() }
        .onChange(of: viewModel.composerFocusRequest) { isComposerFocused = true }
        // The computer's memory may have changed meanwhile; only a list already read is read again.
        .onChange(of: scenePhase) {
            if scenePhase == .active, viewModel.memoryFoot.entries != nil {
                Task { await viewModel.memoryFoot.refreshEntries() }
            }
            // Nothing is read aloud from behind another app.
            if scenePhase == .background {
                viewModel.readAloud.stop()
                // The microphone stops in the background: what was recorded so far is thrown away, unsent.
                viewModel.cancelRecording()
            }
        }
        // Nor from a chat that was left.
        .onDisappear {
            viewModel.readAloud.stop()
            viewModel.cancelRecording()
        }
        // A rename from the sidebar while this chat is the one open: `title` changing is that
        // signal, since renaming never changes `chatId` and so never recreates this view.
        .onChange(of: title) { _, newTitle in
            viewModel.applyExternalRename(newTitle)
        }
        .alert(
            "ios:chat.alert.errorTitle",
            isPresented: Binding(
                get: { viewModel.showsErrorAlert },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("ios:app.alert.ok") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // Haptics: one per user action, firing on the causal event, never on a re-render or a
        // streamed token (apple-design §13 — causality, harmony, utility). Each trigger below is a
        // plain value the view model changes exactly once per real occurrence.
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.sendCount)
        .sensoryFeedback(.success, trigger: viewModel.completedTurnCount)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.stopCount)
        .sensoryFeedback(.selection, trigger: viewModel.choiceCount)
        // Once per failure, even when a second failure has the same text.
        .sensoryFeedback(.error, trigger: viewModel.failureCount)
        .sensoryFeedback(.start, trigger: viewModel.recordingStartCount)
        .sensoryFeedback(.success, trigger: viewModel.transcriptionCount)
        .alert("ios:chat.composer.micDeniedMessage", isPresented: Binding(
                get: { viewModel.explainsMicrophone },
                set: { viewModel.explainsMicrophone = $0 }
            )
        ) {
            Button("ios:settings.pairing.openSystemSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("common:action.cancel", role: .cancel) {}
        }
        // The colour tone is the chat's own: the transcript, the composer and the sheets opened from them.
        // What tints is the tone's ink, since a tint colours text; a surface in the tone asks for its fill
        // (`toneFill`). Neutral is black and white, as the desktop's default: nothing here is system blue, and
        // a link, which the tint alone would no longer set apart from the text around it, is underlined.
        .tint(toneInk)
        .environment(\.markdownUnderlinesLinks, colorTone == .neutral)
        // While recording the voice rises from the bottom of the screen, as voice-glow's phone demo, over the composer.
        .screenVoiceGlow(active: ComposerVoiceGlow.isShown(viewModel.recording), level: viewModel.voiceRecorder.level)
    }

    /// A new chat: Ody, still but for a blink (nothing at all under Reduce Motion), over the hour's greeting —
    /// the widgets' words — and the question. Ody keeps its own colours in every tone; it is not a button here.
    private var emptyState: some View {
        VStack(spacing: 14) {
            OdyView(expression: .happy, pokable: false)
                .frame(width: 67, height: 72)
                .padding(.bottom, 4)
            VStack(spacing: 6) {
                EmptyChatGreeting.title(at: .now)
                    .font(.title2.weight(.semibold))
                Text("ios:chat.detail.greeting")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var composer: some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 8) {
            if let quote = viewModel.quote {
                ComposerQuote(text: quote, onRemove: viewModel.removeQuote)
                    .transition(.opacity)
            }
            if !viewModel.attachments.isEmpty || viewModel.isPreparingPictures {
                ComposerPictureStrip(
                    pictures: viewModel.attachments.pictures, preparing: viewModel.preparingPictures,
                    onRemove: viewModel.removePicture)
                    .transition(.opacity)
            }
            if let composerTools, composerTools.isActive {
                ComposerToolPills(tools: composerTools)
                    .transition(.opacity)
            }
            composerRow
        }
        .padding(.leading, 16)
        .padding(.trailing, ComposerRowLayout.inset)
        .padding(.vertical, ComposerRowLayout.inset)
        .glassEffect(ComposerRowLayout.glass, in: .rect(cornerRadius: ComposerRowLayout.cornerRadius))
        .padding(.horizontal, 12)
        .readingColumn()
        .padding(.bottom, 4)
        // Extends `.snappy`, the curve this app already uses for every other toggle (search mode,
        // the drawer), rather than inventing a new one.
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isComposerFocused)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: viewModel.quote)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: viewModel.attachments)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: viewModel.preparingPictures)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: composerTools?.turnOptions)
        // The field growing a line, and the row's change of shape when it wraps (`ComposerRowLayout`).
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: viewModel.composerText)
    }

    /// As ChatGPT's: one line and the field sits between `+` and the round button, a pill; more and the field takes
    /// the top on its own with the buttons in a row under it. One layout with the same children either way, so the
    /// field keeps the keyboard across the change.
    private var composerRow: some View {
        @Bindable var viewModel = viewModel
        return ComposerRowLayout(oneLineHeight: composerLineHeight) {
            ComposerToolsButton(
                tools: composerTools, attachments: viewModel.attachments, cameraRequest: viewModel.cameraRequest
            ) { items in
                Task { await viewModel.addPictures(items) }
            }
            // Reaches into the composer's padding, so its circle sits as far from the edge as Send's on the other side.
            .padding(.leading, ComposerRowLayout.inset - 16)
            .composerRole(.leading)
            TextField("ios:chat.composer.placeholder", text: $viewModel.composerText, axis: .vertical)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .accessibilityIdentifier("composerField")
                // While recording, and until its text is in, nothing is typed; the meter takes the field's place.
                .disabled(viewModel.recording != .idle)
                .opacity(isRecording ? 0 : 1)
                .accessibilityHidden(isRecording)
                .overlay(alignment: .leading) {
                    if case .recording(let since) = viewModel.recording {
                        RecordingMeter(since: since)
                            .transition(.opacity)
                    }
                }
                .composerRole(.field)
            if isComposerFocused {
                // Return inserts a newline in this multi-line field, so without a button the only
                // ways out of the keyboard are gestures, which is what the owner could not find.
                // It lives here rather than in a `.keyboard` toolbar placement: measured on iOS 27,
                // such an item is drawn as a floating circle in the same band as this bar and lands
                // on top of the send button.
                Button {
                    isComposerFocused = false
                } label: {
                    Label("ios:chat.composer.hideKeyboard", systemImage: "keyboard.chevron.compact.down")
                        .labelStyle(.iconOnly)
                        // The keyboard symbol is wider and taller than the send arrow, and a circle
                        // sized to fit it would be the bigger of the two buttons.
                        .imageScale(.small)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                // Appearing next to Send would otherwise shove it sideways in one frame; entering
                // and leaving the way it would if it grew from nothing turns that into a slide
                // (apple-design: preventing a jarring change, not a showy one).
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .composerRole(.trailing)
            }
            turnButton
                .composerRole(.trailing)
        }
    }

    /// One button whose icon and action both switch on the same state, not two buttons swapped by
    /// an `if`: only a stable identity lets the icon morph (`.contentTransition`) instead of being
    /// destroyed and recreated with a hard cut. Stop is the way out of a turn that will not finish
    /// (a half-open connection can otherwise keep the composer locked for up to an hour).
    /// With nothing typed and nothing picked it records (`TurnButtonState`): tapped, a red stop while recording, then
    /// a spinner while the computer transcribes, and send once the text is in. A long press on the red stop throws
    /// the recording away.
    private var turnButton: some View {
        let state = turnState
        return Button {
            // Read at the tap, not when the button was drawn: the long press that discarded a recording ends in a tap.
            switch turnState {
            case .stop:
                Task { await viewModel.stop() }
            case .send:
                // The question is on its way: the keyboard goes, so the reply has the screen.
                isComposerFocused = false
                Task { await viewModel.sendMessage() }
            case .mic:
                if let discarded = recordingDiscardedAt, Date.now.timeIntervalSince(discarded) < 5 {
                    recordingDiscardedAt = nil
                    return
                }
                isComposerFocused = false
                Task { await viewModel.startRecording() }
            case .recording:
                Task { await viewModel.stopRecordingAndTranscribe() }
            case .transcribing:
                break
            }
        } label: {
            // Stop is neutral whatever the tone, as ChatGPT's: a dark square on a soft tone fill read as a stray
            // blot, and a stop that differs from send says a reply is running. A recording's stop is red.
            TurnButtonLabel(
                state: state, glyph: TurnButtonLabel.glyph(state, scheme: colorScheme, accentGlyph: accentGlyph))
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        // Set on the button itself (an outer `.tint` loses to an inner one): in light the tone's ink with a white
        // arrow (a white arrow on the soft fill is 1.6:1 in yellow, and a dark one read as a blot), in dark the fill
        // and its glyph.
        .tint(TurnButtonLabel.fill(state, scheme: colorScheme, toneFill: toneFillColor, toneInk: toneInk))
        .disabled(state == .transcribing || (state == .send && !viewModel.canSend))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                guard case .recording = viewModel.recording else { return }
                recordingDiscardedAt = .now
                viewModel.cancelRecording()
            })
        .accessibilityActions {
            if state == .recording {
                Button("common:action.cancel") { viewModel.cancelRecording() }
            }
        }
        .accessibilityIdentifier(state.identifier)
    }

    private var turnState: TurnButtonState {
        TurnButtonState.for(
            text: viewModel.composerText,
            hasPictures: !viewModel.attachments.isEmpty || viewModel.isPreparingPictures,
            inFlight: viewModel.isTurnInFlight, recording: viewModel.recording)
    }

    private var isRecording: Bool {
        if case .recording = viewModel.recording { return true }
        return false
    }

    private var transcriptActions: TranscriptActions {
        TranscriptActions(
            regenerableTurnId: viewModel.regenerableTurnId,
            canRetryOrphan: viewModel.canRetryOrphanError,
            regenerate: { [viewModel] in Task { await viewModel.regenerate() } },
            showSources: { [viewModel] turnId, marker in
                sourcesSheet = viewModel.sourcesSheet(forTurn: turnId, marker: marker)
            },
            canChoose: viewModel.canChoose,
            choose: { [viewModel] runId in Task { await viewModel.choose(runId: runId) } },
            showOtherVersion: { [viewModel] runId in otherVersion = viewModel.otherVersion(runId: runId) },
            canAnswer: viewModel.canAnswer,
            sendAnswer: { [viewModel] text in
                // Whether it is sent is known now (`canAnswer`); the turn it starts runs on.
                guard viewModel.canAnswer else { return false }
                Task { await viewModel.sendText(text) }
                return true
            })
    }

    private var scrollKey: TranscriptRules.ScrollKey {
        TranscriptRules.scrollKey(
            segments: viewModel.segments, showsTypingIndicator: viewModel.showsPendingRow,
            liveError: viewModel.liveRunError)
    }

    /// Loads the page before the first run shown and keeps the reader where they were: on the run that was first, or —
    /// when the transcript was short enough to show its end — at the end.
    private func loadOlder(_ proxy: ScrollViewProxy) {
        let first = viewModel.segments.first?.id
        Task {
            await viewModel.loadOlder()
            if isAtEnd {
                scrollToBottom(proxy, animated: false)
            } else if let first {
                proxy.scrollTo(first, anchor: .top)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !viewModel.segments.isEmpty || viewModel.showsPendingRow else { return }
        if animated {
            withAnimation { proxy.scrollTo(TranscriptRows.endID, anchor: .bottom) }
        } else {
            proxy.scrollTo(TranscriptRows.endID, anchor: .bottom)
        }
    }
}

/// An entity link's article title, as the sheet that shows its summary is presented.
struct EntityRequest: Identifiable {
    let title: String
    var id: String { title }
}

/// What one chat screen owns: its view model, and the stores and loaders its cards read, all over the paired session.
@MainActor
final class ChatScreenObjects {
    let viewModel: ChatDetailViewModel
    /// Generated images come through this chat's paired session.
    let imageLoader: GeneratedImageLoader
    /// Answers and stops a computer_use session on the computer through the same paired session.
    let computerUseRemote: ComputerUseRemote
    /// Reads deep_research jobs through the same paired session, keeping what it has read.
    let researchJobs: DeepResearchStore
    /// Places photos through the computer's proxy, over the same paired session.
    let placePhotos: PlacePhotoLoader
    /// The computer's artifact sandbox page, through the same paired session.
    let artifactSandbox: ArtifactSandboxSource
    /// This chat's workspace files (a file card's View), through the same paired session.
    let workspaceFiles: WorkspaceFileLoader
    /// Wikipedia's summaries for entity links, through the same paired session.
    let entities: EntityLoader

    init(
        chatId: String, title: String?, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore
    ) {
        viewModel = ChatDetailViewModel(
            chatId: chatId, title: title, apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
        imageLoader = GeneratedImageLoader(apiClient: apiClient)
        computerUseRemote = ComputerUseRemote(apiClient: apiClient)
        researchJobs = DeepResearchStore(apiClient: apiClient)
        placePhotos = PlacePhotoLoader(apiClient: apiClient)
        artifactSandbox = ArtifactSandboxSource(apiClient: apiClient)
        workspaceFiles = WorkspaceFileLoader(apiClient: apiClient, chatId: chatId)
        entities = EntityLoader(apiClient: apiClient)
    }
}

/// A value made on first use and then kept: held in `@State`, it is made once for the view's lifetime, not once per
/// `init`. Not observable; what it holds is.
@MainActor
final class LazyBox<Value> {
    private var stored: Value?

    var isEmpty: Bool { stored == nil }

    func value(_ make: () -> Value) -> Value {
        if let stored { return stored }
        let made = make()
        stored = made
        return made
    }
}

/// The text the next message is about, over the field: ↪, two lines of it, and ✕ to let it go.
struct ComposerQuote: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .lineLimit(2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The target reaches into the row's padding: the ✕ lines up with the send button under it.
            .padding(.vertical, -12)
            .padding(.trailing, -4)
            .accessibilityLabel(Text("ios:chat.ask.remove"))
        }
        .font(.subheadline)
        .padding(.trailing, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("ios:chat.ask.quoted"))
        .accessibilityValue(Text(verbatim: text))
    }
}

/// The empty chat's greeting by the hour, in the widgets' periods and words (`WidgetPresentation.period`): morning
/// from 5, afternoon from 12, evening from 18.
enum EmptyChatGreeting {
    enum Period: Equatable { case morning, afternoon, evening }

    static func period(at date: Date, calendar: Calendar = .current) -> Period {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }

    static func title(at date: Date) -> Text {
        switch period(at: date) {
        case .morning: Text("ios:widget.greeting.morning")
        case .afternoon: Text("ios:widget.greeting.afternoon")
        case .evening: Text("ios:widget.greeting.evening")
        }
    }
}
