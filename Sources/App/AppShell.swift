import ChatFeature
import HealthFeature
import Models
import NetworkingKit
import OdyKit
import PhilharmonicFeature
import SettingsFeature
import SwiftUI
import WidgetKitShared

/// The chat on screen. A new chat is a fresh lowercased UUID with no title; the server creates the
/// chat when the first message is sent.
struct ActiveChat: Equatable {
    var id: String
    var title: String?
    /// Made here and never shown before: there is no history to read, so the screen does not ask the server for one.
    var isNew = false

    static func new() -> ActiveChat { ActiveChat(id: UUID().uuidString.lowercased(), title: nil, isNew: true) }
}

/// The app's root: a drawer whose sidebar lists chats and whose card shows the active chat.
struct AppShell: View {
    let apiClient: APIClient
    let streamManager: ChatStreamManager
    let serverConfig: ServerConfigStore
    let widgetWriter: WidgetSnapshotWriter
    /// A widget's link, waiting for the shell: it is taken as soon as the shell is on screen.
    let pendingLink: PendingLink

    @State private var activeChat = ActiveChat.new()
    @State private var isSidebarOpen = false
    /// The screen is wide enough for the sidebar to stay beside the content (an unfolded iPhone Duo, landscape), as
    /// Claude's app does there; the toolbar button then hides and shows it instead of sliding a drawer.
    @State private var isDocked = false
    /// The narrow layout's sidebar is a page of its own rather than a drawer (a folded Duo).
    @State private var usesSidebarPage = false
    /// Whether the docked sidebar is showing. Its own value, so a drawer closed on a phone does not hide it later.
    @State private var isDockedSidebarShown = true
    @State private var workspace: AppWorkspace = .chat
    /// Settings, and the page it opens on. One value, so the page arrives with the presentation itself: two flags let
    /// the first presentation read a stale page and open on the root.
    @State private var settings: SettingsRoute?
    /// Bumped when Settings closes so the sidebar reloads Recents from the (possibly new) server.
    @State private var recentsReloadToken = 0
    /// A question from Health waiting for its new chat to open and send it.
    @State private var pendingAsk: (chatId: String, text: String)?
    /// A widget's prompt for its new chat's composer, never sent by itself.
    @State private var draft: (chatId: String, text: String)?
    /// What a widget's new chat opens on: the camera, or already recording.
    @State private var opening: (chatId: String, opening: ComposerOpening)?
    /// A widget's question for Health's ask box.
    @State private var healthAsk: String?
    /// The composer's `+` choices (reasoning effort, Deep Research) for the whole app session, as the desktop keeps them,
    /// with the current model's levels and the MCP tools the menu offers.
    @State private var composerTools = ComposerTools()
    /// The Philharmonic workspace's groups, made the first time the shell appears.
    @State private var groupList: GroupListViewModel?
    @State private var philharmonicSelection: PhilharmonicSelection = .none
    @State private var showsNewGroup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ColorToneModel.self) private var toneModel: ColorToneModel?

    var body: some View {
        Group {
            if isDocked {
                HStack(spacing: 0) {
                    if isDockedSidebarShown {
                        sidebar
                            .environment(\.sidebarIsDocked, true)
                            .frame(width: ReadingColumn.sidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider().ignoresSafeArea()
                    }
                    content
                }
            } else if usesSidebarPage {
                // A folded Duo: the sidebar is a page of its own that takes the screen, not a drawer that pushes the
                // content aside (owner, 2026-10-23, after Claude's app there). The chat stays alive behind it — a
                // reply keeps streaming, the scroll position holds — and only one of the two is seen, touched or read
                // by VoiceOver at a time. Other phones keep the drawer (same day).
                ZStack {
                    content
                        .opacity(isSidebarOpen ? 0 : 1)
                        .allowsHitTesting(!isSidebarOpen)
                        .accessibilityHidden(isSidebarOpen)
                    sidebar
                        .environment(\.closeSidebar, CloseSidebarAction { setSidebar(open: false) })
                        .opacity(isSidebarOpen ? 1 : 0)
                        .allowsHitTesting(isSidebarOpen)
                        .accessibilityHidden(!isSidebarOpen)
                }
            } else {
                SideDrawer(isOpen: $isSidebarOpen) { sidebar } content: { content }
            }
        }
        // Measured behind the layout, from its first width on: `onGeometryChange` on the switching `Group` was never
        // called for the width it started with, and a landscape launch stayed a drawer.
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.width >= ReadingColumn.dockedSidebarFrom, initial: true) { _, wide in
                    isDocked = wide
                    // The drawer's state means nothing beside a docked sidebar, and must not open over the content later.
                    if wide { isSidebarOpen = false }
                }
                // Upright with a side inset: the camera beside the screen, a folded Duo. An ordinary phone upright
                // has none (a landscape phone does, but is docked by then).
                .onChange(of: proxy.size.width < proxy.size.height
                    && proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing > 0, initial: true) { _, page in
                    usesSidebarPage = page
                }
            }
        }
        .sheet(
            item: $settings,
            onDismiss: {
                recentsReloadToken += 1
                // The model may have changed there, and with it the reasoning levels.
                refreshComposerTools()
            }
        ) { route in
            SettingsView(apiClient: apiClient, serverConfig: serverConfig, opensMemory: route == .memory)
                .horizontalBars()
        }
        // The workspace actually changing, once (apple-design §13): `workspace` only changes when
        // a row not already selected is tapped, so re-tapping the active row fires nothing. And
        // today .chat and .health are selectable (AppWorkspace.isAvailable).
        .sensoryFeedback(.selection, trigger: workspace)
        // What is on screen: a screenshot is titled after it (the share sheet's header, and the file's name when it
        // reaches a computer). Settings, and a chat's sheets, are inside it and win while they are up.
        .screenTitle(sceneTitle)
        // The desktop may have picked another tone meanwhile.
        .task { await toneModel?.refresh(apiClient: apiClient) }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await toneModel?.refresh(apiClient: apiClient) }
                refreshComposerTools()
            }
        }
        // A chat opening reads the current model's levels and the MCP tools (the desktop may have changed either).
        .onChange(of: activeChat.id, initial: true) { refreshComposerTools() }
        // Back from another workspace the chat screen is made again, and what was sent meanwhile is history now.
        .onChange(of: workspace) { if workspace != .chat { activeChat.isNew = false } }
        // Initial too: a link that arrived behind the unlock or pairing gate is opened once the shell appears.
        .onChange(of: pendingLink.link, initial: true) {
            guard let link = pendingLink.take() else { return }
            open(link)
        }
    }

    /// The paired computer's offline copy of its chats; nil while no computer is paired (the Simulator's manual
    /// address). The shell starts again on a switch (`PairingGate`), so it is read afresh for the new computer.
    private var offlineStore: OfflineChatStore? {
        serverConfig.connection?.route?.fingerprint.map { OfflineChatStore.standard(fingerprint: $0) }
    }

    private var sidebar: some View {
        ChatSidebarView(
            apiClient: apiClient,
            activeChatId: activeChat.id,
            isOpen: isDocked ? isDockedSidebarShown : isSidebarOpen,
            reloadToken: recentsReloadToken,
            onSelectChat: { id, title in select(id: id, title: title) },
            onNewChat: { startNewChat() },
            onOpenSettings: { settings = .root },
            onDeleteChat: { id in
                // The deleted chat was the one on screen: leave it for a fresh one, drawer stays open.
                if id == activeChat.id { activeChat = .new() }
            },
            onRenameChat: { id, title in
                // The renamed chat is the one on screen: `ChatDetailView` picks this up from
                // its own `title` argument changing, via `.onChange` (its `chatId` does not
                // change, so it is never recreated by this).
                if id == activeChat.id { activeChat.title = title }
            },
            onRecentsChange: { widgetWriter.recentsChanged($0) },
            showsRecents: workspace != .philharmonic,
            offlineStore: offlineStore
        ) {
            ForEach(AppWorkspace.listed) { option in
                WorkspaceRow(option: option, isSelected: option == workspace) {
                    workspace = option
                    setSidebar(open: false)
                }
            }
        } lists: {
            if let groupList {
                GroupListSection(model: groupList, selection: philharmonicSelection) { picked in
                    philharmonicSelection = picked
                    setSidebar(open: false)
                }
            }
        }
        .task {
            if groupList == nil { groupList = GroupListViewModel(api: philharmonicAPI) }
        }
    }

    private var philharmonicAPI: PhilharmonicAPI { PhilharmonicAPI(client: apiClient, serverConfig: serverConfig) }

    private var content: some View {
        NavigationStack {
            detail
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            toggleSidebar()
                        } label: {
                            if isSidebarVisible {
                                Label("ios:app.sidebar.close", systemImage: "sidebar.leading")
                            } else {
                                Label("ios:app.sidebar.open", systemImage: "sidebar.leading")
                            }
                        }
                        .accessibilityIdentifier("sidebarToggle")
                    }
                    // Health has its own menu there; a new chat is in the drawer.
                    if workspace == .philharmonic {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showsNewGroup = true
                            } label: {
                                Label("philharmonic:chat.conversationList.newGroupMenuItem", systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("topNewGroup")
                        }
                    } else if workspace != .health {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                startNewChat()
                            } label: {
                                Label("chat:sidebar.newChat", systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("topNewChat")
                        }
                    }
                }
        }
        // No `horizontalBars()` here: on a Duo, folded or open, the bar stands beside the camera as Claude's does
        // (owner, 2026-10-23); a phone without a side camera keeps it on top by itself.
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace {
        case .chat:
            ChatDetailView(
                chatId: activeChat.id, title: activeChat.title, isNew: activeChat.isNew, apiClient: apiClient,
                streamManager: streamManager, serverConfig: serverConfig,
                initialMessage: pendingAsk?.chatId == activeChat.id ? pendingAsk?.text : nil,
                onInitialMessageSent: { pendingAsk = nil },
                initialDraft: draft?.chatId == activeChat.id ? draft?.text : nil,
                onInitialDraftUsed: { draft = nil },
                initialOpening: opening?.chatId == activeChat.id ? opening?.opening : nil,
                onInitialOpeningUsed: { opening = nil },
                offlineStore: offlineStore
            )
            // A different chat is a different view model.
            .id(activeChat.id)
            .environment(composerTools)
            .environment(
                \.openMemorySettings,
                OpenMemorySettingsAction {
                    settings = .memory
                })
        case .health:
            HealthRootView(
                apiClient: apiClient, onGlanceChange: { widgetWriter.healthChanged($0) }, initialAsk: healthAsk,
                onInitialAskUsed: { healthAsk = nil }
            ) { text in
                let chat = ActiveChat.new()
                pendingAsk = (chat.id, text)
                activeChat = chat
                workspace = .chat
            }
        case .philharmonic:
            PhilharmonicRootView(
                api: philharmonicAPI, selection: philharmonicSelection, onNewGroup: { showsNewGroup = true },
                onGroupGone: {
                    philharmonicSelection = .none
                    Task { await groupList?.load() }
                }
            )
            .sheet(isPresented: $showsNewGroup) {
                if let groupList {
                    NewGroupSheet(model: groupList) { group in
                        philharmonicSelection = .group(id: group.id, title: group.title)
                    }
                }
            }
        }
    }

    /// The title of what is on screen: the chat's, else the workspace's.
    private var sceneTitle: String {
        switch workspace {
        case .chat:
            let title = activeChat.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty
                ? String(localized: "chat:sidebar.newChat", defaultValue: "New chat") : title
        case .philharmonic:
            if case .group(_, let title) = philharmonicSelection { return title }
            return String(localized: workspace.title)
        case .health:
            return String(localized: workspace.title)
        }
    }

    private func select(id: String, title: String?) {
        pendingAsk = nil
        healthAsk = nil
        activeChat = ActiveChat(id: id, title: title)
        // A chat picked from the drawer is shown, whichever workspace was open.
        workspace = .chat
        setSidebar(open: false)
    }

    private func startNewChat() {
        pendingAsk = nil
        healthAsk = nil
        activeChat = .new()
        workspace = .chat
        setSidebar(open: false)
    }

    /// Where a widget's link leads. Settings closes first: whatever the link opens is under it.
    private func open(_ link: DeepLink) {
        settings = nil
        switch link {
        case .newChat(let prompt, let opens):
            startNewChat()
            // An empty draft still focuses the composer: the link is "ask something" — unless the camera or the
            // microphone is what opens, when the keyboard would only be in the way.
            if let prompt {
                draft = (activeChat.id, prompt)
            } else if opens == nil {
                draft = (activeChat.id, "")
            }
            opening = opens.map { (activeChat.id, ComposerOpening($0)) }
        case .chat(let id):
            // The title comes with the history (the chat already on screen keeps its own); an unknown id shows the
            // server's error in the chat, and the drawer still lists the rest.
            select(id: id, title: id == activeChat.id ? activeChat.title : nil)
        case .health(let ask):
            pendingAsk = nil
            healthAsk = ask
            workspace = .health
            setSidebar(open: false)
        }
    }

    private func refreshComposerTools() {
        Task { await composerTools.refresh(from: ComposerToolsSource(apiClient: apiClient)) }
    }

    /// Shows the sidebar page or the content. A docked sidebar is left as it is: picking a chat there keeps the list beside it.
    private func setSidebar(open: Bool) {
        guard !isDocked else { return }
        withAnimation(usesSidebarPage ? .easeOut(duration: 0.2) : drawerAnimation(reduceMotion: reduceMotion)) {
            isSidebarOpen = open
        }
    }

    /// The toolbar's sidebar button: the sidebar page on a narrow screen, the docked column on a wide screen.
    private func toggleSidebar() {
        if isDocked {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) { isDockedSidebarShown.toggle() }
        } else {
            setSidebar(open: !isSidebarOpen)
        }
    }

    private var isSidebarVisible: Bool { isDocked ? isDockedSidebarShown : isSidebarOpen }
}

extension ComposerOpening {
    /// The widget link's word for it.
    init(_ opening: DeepLink.Opening) {
        switch opening {
        case .camera: self = .camera
        case .voice: self = .voice
        }
    }
}

/// Where Settings opens: its root, or the Memory page (from a chat's used-memories sheet).
enum SettingsRoute: String, Identifiable {
    case root, memory

    var id: String { rawValue }
}

extension View {
    /// Keeps the bars horizontal — the navigation bar on top, beside the status bar — where iOS 27.1 would move
    /// them into a vertical bar beside the camera (an iPhone Duo). A chat's two bar buttons don't fill that bar, and
    /// the transcript and the composer gave up its whole width for them; with horizontal bars they run edge to edge.
    /// Applied once per presentation: the shell, and sheets that bring their own bars.
    /// `enabled` false leaves the system's choice — the vertical bar — as the docked layout wants.
    @ViewBuilder
    func horizontalBars(_ enabled: Bool = true) -> some View {
        if #available(iOS 27.1, *), enabled {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}
