import Models
import NetworkingKit
import SwiftUI

/// Tighter than the system's 16 pt: a row is about 44 pt at the default text size instead of 52,
/// which is still the 44 pt touch target and fits more chats on screen. With the separators hidden
/// the list reads as one column of titles, like the ChatGPT app's sidebar.
private let sidebarRowInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

extension EnvironmentValues {
    /// The sidebar stands docked beside the content (a wide screen) rather than sliding over it: it then takes a
    /// surface a step off the page's, as Claude's does on the Duo (owner, 2026-10-23), so the two read as two panes.
    @Entry public var sidebarIsDocked = false
}

/// The docked sidebar's surface: a little darker than the page in light, a little lighter in dark.
private let dockedSidebarSurface = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(white: 0.085, alpha: 1) : UIColor(white: 0.955, alpha: 1)
})

/// One selectable sidebar row — a Recents chat or a search result.
///
/// The padding is part of the row's own hit area and the list row itself gets no insets, so the
/// whole cell selects the chat; `listRowInsets` would pad *around* the content shape and leave the
/// edges of the row to the list. `minHeight` keeps the shape at the 44 pt touch target even at a
/// small text size, where the content alone would be shorter than the list's minimum row height.
///
/// Not a `Button`: one inside a `List` fires on touch-up wherever the finger ended up, so a left
/// swipe over a row closed the drawer and opened that chat at the same time. The touches are read by
/// `SidebarRowTouchSurface`, whose tap fails as soon as the finger moves, which leaves the swipe to the
/// drawer and the scroll to the list — and what the `Button` gave VoiceOver is spelled out instead,
/// the trait plus an activation action.
private struct SidebarRow: ViewModifier {
    let isSelected: Bool
    var menu: (() -> UIMenu)? = nil
    let select: () -> Void
    /// A finger down on the row, for the background tint below; `SidebarRowTouchSurface` reports it.
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sidebarRowInsets)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay {
                SidebarRowTouchSurface(select: select, pressChanged: { isPressed = $0 }, menu: menu)
                    .accessibilityHidden(true)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            // A shape, not a plain colour: `listRowBackground` otherwise fills the row's full,
            // square-cornered bounds edge to edge. Padding the shape itself insets it into a pill
            // within that space instead.
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isPressed ? Color.primary.opacity(0.06)
                            : isSelected ? Color.primary.opacity(0.08) : Color.clear
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            )
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select() }
    }
}

/// The drawer's content: workspaces, Recents, and an inline search. It owns its `NavigationStack`, so
/// the title and the search button are native; the bottom bar is a `safeAreaBar` of its own, because a
/// bottom-bar toolbar item cannot show a labelled button. Rows have no swipe actions (a left swipe
/// closes the drawer); a chat is deleted from its long-press menu.
/// What "Copy Chat ID" puts on the pasteboard: the id the computer knows the conversation by, and nothing
/// else. It is pasted into another chat, for the model to look that conversation up.
enum ConversationID {
    static func copyText(for chat: ChatSummary) -> String {
        chat.id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ChatSidebarView<Workspaces: View>: View {
    @State private var list: ChatListViewModel
    @State private var search: ChatSearchViewModel
    @State private var isSearching = false
    /// Bumped exactly once when a chat's delete succeeds and its row leaves the list — a plain
    /// counter so `sensoryFeedback` fires with the row's removal, not when the context menu opens
    /// and not for a failed delete (which raises `list.showsErrorAlert` instead).
    @State private var deletedTrigger = 0
    /// The chat a rename alert is open for, and the text it is editing. `nil` closes the alert; a
    /// non-nil `renamingChat` and the alert's own `isPresented` are two views of the same state, so
    /// they cannot disagree about whether it is on screen.
    @State private var renamingChat: ChatSummary?
    @State private var renameText = ""
    /// Bumped when a conversation's id has been put on the pasteboard: the only sign that it was.
    @State private var copiedTrigger = 0

    private let activeChatId: String
    private let isOpen: Bool
    private let reloadToken: Int
    private let onSelectChat: (String, String?) -> Void
    private let onNewChat: () -> Void
    private let onOpenSettings: () -> Void
    private let onDeleteChat: (String) -> Void
    private let onRenameChat: (String, String) -> Void
    private let onRecentsChange: ([ChatSummary]) -> Void
    private let workspaces: Workspaces

    /// A brand name: a plain `String`, shown as is and never looked up in the catalog.
    private static var appName: String { "Actovia" }

    public init(
        apiClient: APIClient,
        activeChatId: String,
        isOpen: Bool,
        reloadToken: Int,
        onSelectChat: @escaping (String, String?) -> Void,
        onNewChat: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onDeleteChat: @escaping (String) -> Void,
        onRenameChat: @escaping (String, String) -> Void,
        onRecentsChange: @escaping ([ChatSummary]) -> Void = { _ in },
        @ViewBuilder workspaces: () -> Workspaces
    ) {
        _list = State(initialValue: ChatListViewModel(apiClient: apiClient))
        _search = State(initialValue: ChatSearchViewModel(apiClient: apiClient))
        self.activeChatId = activeChatId
        self.isOpen = isOpen
        self.reloadToken = reloadToken
        self.onSelectChat = onSelectChat
        self.onNewChat = onNewChat
        self.onOpenSettings = onOpenSettings
        self.onDeleteChat = onDeleteChat
        self.onRenameChat = onRenameChat
        self.onRecentsChange = onRecentsChange
        self.workspaces = workspaces()
    }

    @Environment(\.sidebarIsDocked) private var isDocked
    private var dockedSurface: Color { dockedSidebarSurface }

    public var body: some View {
        NavigationStack {
            List {
                if isSearching && search.hasQuery {
                    searchResultRows
                } else {
                    if !isSearching {
                        // On the rows, not on the `Section`: a section passes the hidden separator down
                        // but keeps the insets to itself.
                        Section {
                            workspaces
                                .listRowSeparator(.hidden)
                                .listRowInsets(sidebarRowInsets)
                        }
                    }
                    if !isSearching, !list.favorites.isEmpty {
                        Section("ios:chat.sidebar.favorites") {
                            ForEach(list.favorites) { chat in
                                row(for: chat)
                            }
                        }
                    }
                    Section("ios:chat.sidebar.recents") {
                        ForEach(list.recents) { chat in
                            row(for: chat)
                        }
                        if list.hasMore, !list.chats.isEmpty {
                            loadMoreRow
                        }
                        recentsStateRow
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(isDocked ? .hidden : .automatic)
            .background { if isDocked { dockedSurface.ignoresSafeArea() } }
            // The insets alone do not shrink a row below the list's own minimum, which is what held
            // the rows at 52 pt. 44 pt is the touch-target floor, never less.
            .environment(\.defaultMinListRowHeight, 44)
            // The bottom bar is not a system `.bottomBar`, so it does not get the scroll edge
            // effect for free: without it the rows print through the pill and the gear, and at
            // an accessibility text size a title is chopped mid-word by them.
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .overlay { searchStateOverlay }
            // Spinner, empty state, failure and results all cross-fade instead of cutting — the
            // Recents block only when a load finishes, search on every phase it can be in while a
            // query is live (apple-design: preventing a jarring change).
            .animation(.easeOut(duration: 0.15), value: list.chats.isEmpty)
            .animation(.easeOut(duration: 0.15), value: search.phase)
            .animation(.easeOut(duration: 0.15), value: search.isSearching)
            // Blank always: the system's own inline title centres itself and stays small, neither
            // of which is what "Actovia" should do here. `sidebarToolbar`'s leading item draws it
            // instead, left-aligned and a size up from that.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .top) {
                if isSearching {
                    SidebarSearchBar(
                        text: Binding(get: { search.query }, set: { search.updateQuery($0) }),
                        onCancel: leaveSearch)
                }
            }
            .toolbar { sidebarToolbar }
            // Hidden while searching so it cannot ghost through the keyboard.
            .safeAreaBar(edge: .bottom) {
                if !isSearching {
                    bottomBar
                }
            }
            // A full `load()`, not `refresh()`: this runs at launch and again after Settings closes, and
            // Settings can change the server address, so a silent refresh could leave the old server's
            // chats on screen.
            .task(id: reloadToken) { await list.load() }
            .onChange(of: loadedChats, initial: true) { _, chats in
                if let chats { onRecentsChange(chats) }
            }
            .refreshable { await list.load() }
            .onChange(of: isOpen) { _, nowOpen in
                if nowOpen {
                    Task { await list.refresh() }
                } else {
                    leaveSearch()
                }
            }
            .alert(
                "ios:chat.alert.errorTitle",
                isPresented: Binding(
                    get: { list.showsErrorAlert },
                    set: { if !$0 { list.errorMessage = nil } }
                )
            ) {
                Button("ios:app.alert.ok") {}
            } message: {
                Text(list.errorMessage ?? "")
            }
            .alert(
                "ios:chat.sidebar.renameTitle",
                isPresented: Binding(
                    get: { renamingChat != nil },
                    set: { if !$0 { renamingChat = nil } }
                ),
                presenting: renamingChat
            ) { chat in
                TextField("ios:chat.sidebar.renameTitle", text: $renameText)
                // Never a blank title: the row would have nothing left to show, and
                // `list.rename` would reject it anyway. Disabling here keeps the person in the
                // dialog to fix it instead of a tap that silently does nothing.
                Button("common:action.save") {
                    let title = renameText
                    Task {
                        if await list.rename(chat, to: title) {
                            onRenameChat(chat.id, title.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("common:action.cancel", role: .cancel) {}
            }
            // Haptics: the causal event only — the alert's own appearance, and a delete once the
            // row is actually gone (apple-design §13). Neither fires for the tap that opens the
            // context menu, and a failed delete gets only the error haptic above.
            .sensoryFeedback(trigger: list.showsErrorAlert) { old, new in
                !old && new ? .error : nil
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: deletedTrigger)
            .sensoryFeedback(.success, trigger: copiedTrigger)
        }
    }

    // MARK: - Rows

    private func row(for chat: ChatSummary) -> some View {
        HStack(spacing: 8) {
            Text(chat.title.collapsedWhitespace)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let timestamp = RecentTimestamp.format(chat.createdAt) {
                Text(timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Keeps its own width; the title above truncates first.
                    .layoutPriority(1)
            }
        }
        // The selected tint lives inside `SidebarRow` now, alongside the press tint: applying
        // `.listRowBackground` again out here would simply replace whichever one it set.
        // The long-press menu is the row's own, shown without lifting anything (see `SidebarRowTouchSurface`);
        // VoiceOver gets the same four as named actions. Both close over this row's chat, so nothing indexes
        // `list.chats` after a concurrent load.
        .modifier(
            SidebarRow(isSelected: chat.id == activeChatId, menu: { menu(for: chat) }) {
                onSelectChat(chat.id, chat.title)
            })
        .accessibilityAction(named: favoriteActionName(for: chat)) {
            Task { await list.toggleFavorite(chat) }
        }
        .accessibilityAction(named: Text("chat:sidebar.history.rename")) { beginRename(chat) }
        .accessibilityAction(named: Text("ios:chat.sidebar.copyConversationId")) { copyID(of: chat) }
        .accessibilityAction(named: Text("common:action.delete")) { delete(chat) }
        // A leading swipe stars the chat (the desktop's star on hover); the row moves to Favorites at once.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            favoriteButton(for: chat)
                .tint(.yellow)
        }
    }

    /// Favorite (or Unfavorite), Rename, Copy Chat ID, Delete.
    private func menu(for chat: ChatSummary) -> UIMenu {
        let favorite =
            chat.favorite == true
            ? UIAction(
                title: String(localized: "ios:chat.sidebar.unfavorite", defaultValue: "Unfavorite"),
                image: UIImage(systemName: "star.slash")
            ) { _ in Task { await list.toggleFavorite(chat) } }
            : UIAction(
                title: String(localized: "ios:chat.sidebar.favorite", defaultValue: "Favorite"),
                image: UIImage(systemName: "star")
            ) { _ in Task { await list.toggleFavorite(chat) } }
        return UIMenu(children: [
            favorite,
            UIAction(
                title: String(localized: "chat:sidebar.history.rename", defaultValue: "Rename"),
                image: UIImage(systemName: "pencil")
            ) { _ in beginRename(chat) },
            UIAction(
                title: String(localized: "ios:chat.sidebar.copyConversationId", defaultValue: "Copy Chat ID"),
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in copyID(of: chat) },
            UIAction(
                title: String(localized: "common:action.delete", defaultValue: "Delete"),
                image: UIImage(systemName: "trash"), attributes: .destructive
            ) { _ in delete(chat) },
        ])
    }

    private func favoriteActionName(for chat: ChatSummary) -> Text {
        chat.favorite == true ? Text("ios:chat.sidebar.unfavorite") : Text("ios:chat.sidebar.favorite")
    }

    private func beginRename(_ chat: ChatSummary) {
        renameText = chat.title.collapsedWhitespace
        renamingChat = chat
    }

    private func copyID(of chat: ChatSummary) {
        UIPasteboard.general.string = ConversationID.copyText(for: chat)
        copiedTrigger += 1
    }

    private func delete(_ chat: ChatSummary) {
        Task {
            if await list.delete(chat) {
                deletedTrigger += 1
                onDeleteChat(chat.id)
            }
        }
    }

    /// The chat list once a load has answered: before it the empty list means "not known yet", and passing that on
    /// would blank the widgets' recents at every launch; a failed load leaves what they last showed.
    /// Star or unstar — two buttons, not one with a ternary label: each state has its own words.
    @ViewBuilder
    private func favoriteButton(for chat: ChatSummary) -> some View {
        if chat.favorite == true {
            Button {
                Task { await list.toggleFavorite(chat) }
            } label: {
                Label("ios:chat.sidebar.unfavorite", systemImage: "star.slash")
            }
        } else {
            Button {
                Task { await list.toggleFavorite(chat) }
            } label: {
                Label("ios:chat.sidebar.favorite", systemImage: "star")
            }
        }
    }

    /// The list's end while older pages remain: a spinner that asks for the next page as it scrolls into view.
    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .task { await list.loadMore() }
    }

    private var loadedChats: [ChatSummary]? {
        list.hasLoaded && !list.loadFailed ? list.chats : nil
    }

    @ViewBuilder
    private var searchResultRows: some View {
        if case .results(let results) = search.phase {
            ForEach(results) { result in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(SearchHighlight.attributed(result.title.collapsedWhitespace, query: search.query))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let timestamp = RecentTimestamp.format(result.matchedAt) {
                            Text(timestamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                    }
                    if let snippet = result.snippets.first {
                        Text(SearchHighlight.attributed(snippet.text, query: search.query))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                // Title and snippet are one element to VoiceOver, as the button's label used to be.
                .accessibilityElement(children: .combine)
                .modifier(SidebarRow(isSelected: false) { onSelectChat(result.id, result.title.collapsedWhitespace) })
            }
        }
    }

    // MARK: - States

    /// A row of the Recents section, not an overlay of the whole list: the list carries the workspace
    /// rows now, and a centred overlay covered them — at an accessibility text size it printed "Can't
    /// load chats" straight across Chat and Philharmonic.
    @ViewBuilder
    private var recentsStateRow: some View {
        if list.chats.isEmpty {
            Group {
                // Not loaded yet reads as "loading", never as "No chats yet".
                if list.isLoading || !list.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if list.loadFailed {
                    ContentUnavailableView {
                        Label("ios:chat.sidebar.loadFailedTitle", systemImage: "wifi.exclamationmark")
                    } description: {
                        // The error text lives here, not in an alert (see `showsErrorAlert`).
                        VStack(spacing: 4) {
                            if let message = list.errorMessage {
                                Text(message)
                            }
                            Text("ios:chat.sidebar.loadFailedHint")
                        }
                    } actions: {
                        // A list row makes its buttons plain, which would leave Retry looking like
                        // static text; `.borderless` gives it the tint back.
                        Button("common:action.retry") { Task { await list.load() } }
                            .buttonStyle(.borderless)
                    }
                } else {
                    ContentUnavailableView("ios:chat.sidebar.empty", systemImage: "message")
                }
            }
            .transition(.opacity)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// Search mode keeps its overlay: the results it would cover are the ones it replaces, and the
    /// spinner over stale results while a new query runs is the point.
    @ViewBuilder
    private var searchStateOverlay: some View {
        if isSearching && search.hasQuery {
            switch search.phase {
            // A retry shows the spinner too, so Retry gives feedback and the failure view is not
            // on screen while it runs. Earlier results stay visible while a new query is in flight.
            case .idle where search.isSearching, .failed where search.isSearching:
                ProgressView()
                    .accessibilityLabel("ios:chat.search.progressLabel")
                    .transition(.opacity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("ios:chat.search.failedTitle", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("common:action.retry") { search.retry() }
                }
                .transition(.opacity)
            case .empty:
                ContentUnavailableView("ios:chat.search.noResults", systemImage: "magnifyingglass")
                    .transition(.opacity)
            case .idle, .results:
                EmptyView()
            }
        }
    }

    // MARK: - Toolbar and search mode

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        if !isSearching {
            ToolbarItem(placement: .topBarLeading) {
                // A brand name: shown as is, never looked up in the catalog (see `appName` above).
                // One size up from the system's own inline title (`.headline`), left-aligned
                // instead of centred, on the same line as Search either way.
                Text(Self.appName)
                    .font(.title2.weight(.semibold))
                    // The toolbar proposes this item a width tighter than "Actovia" needs (it
                    // truncated to "Ex…" with room to spare) — this is six fixed characters,
                    // never user content, so laying out at its own ideal size is safe.
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
            }
            // Without this, Liquid Glass gives a plain `Text` toolbar item the same circular
            // glass background a button gets — it read as a tappable "E…" bubble, not a title.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { isSearching = true }
                } label: {
                    Label("ios:chat.search.label", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("sidebarSearch")
            }
        }
    }

    /// A bar of its own, not `ToolbarItem(placement: .bottomBar)`: a bottom-bar item ignores
    /// `.labelStyle(.titleAndIcon)` and rendered New chat as a bare compose glyph, while the design
    /// asks for a labelled pill next to the round gear.
    private var bottomBar: some View {
        HStack {
            Button(action: onNewChat) {
                Label("chat:sidebar.newChat", systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
                    // The longest translation ("Nouvelle conversation") must fit on one line next to
                    // the gear, in a sidebar that is a fraction of the screen wide.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("sidebarNewChat")
            Spacer(minLength: 12)
            Button(action: onOpenSettings) {
                Label("common:nav.settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("sidebarSettings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // A bar, like a toolbar: it stops growing where a toolbar would. The sidebar is a fixed
        // fraction of the screen, and "Nouvelle conversation" next to the gear only fits on one line
        // up to about this size; past it the title would truncate. The list itself still scales.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func leaveSearch() {
        withAnimation(.snappy) { isSearching = false }
        search.reset()
    }
}
