# Offline, read-only chats — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the paired computer can't be reached, the iPhone still shows the chat list and every chat opened recently, read-only, with a clear offline state; when it comes back, everything refreshes quietly.

**Architecture:** A small on-disk store in ChatFeature (`OfflineChatStore`) keeps the last good chat list and each opened chat's newest page, one folder per paired computer, under complete file protection. A process-wide `ConnectionStatus` in NetworkingKit is set by `APIClient` from what requests actually do: offline on a transport failure, online on any response. The views read both. The list and detail view models fall back to the store on a transport failure, and the write actions are gated on `ConnectionStatus.isOffline`.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, Tuist (iOS 26).

**Spec:** the owner-agreed direction in Linear ISSUE-242, comment of 2026-10-27, reproduced here because it is the whole spec:
- **Cache:** the chat list and the newest page of each opened chat, saved after a successful fetch, kept apart per paired computer, under iOS file protection (unreadable while locked). The 50 most recent chats; older ones are evicted. Images use only the existing image caches; older pages that were never loaded are not cached. Cleared on unpair or revoke.
- **Offline UI:** a thin banner under the title: "Offline · Last synced <time>". Tap or pull to retry; it disappears once connected. The list stays tappable; chats with no cached page are greyed out, and tapping one says it can't be opened offline. A chat can be read and copied; send, Regenerate, choose-a-version, model/tools, rename/delete are disabled. The composer still takes typing and says it will send once connected; it never sends by itself. On reconnect the open chat refreshes silently, without jumping.
- **Not this round:** Philharmonic, Deep Research progress, workspace file preview. Health already has its own cache.
- **Open:** the number 50 (owner did not object) — use 50.

## Global Constraints

- iOS repo rules: no commits on `main`. Work on `linear/2026-10-28-offline` in `~/Code/actovia/ios-offline`. Commit messages reference ISSUE-242 and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Every user-facing string is a key in `Resources/App/Localizable.xcstrings`, with all 12 languages filled via `scripts/l10n.py add` / `fill`. `python3 scripts/l10n.py audit` passes.
- Builds: first run `export PATH=$(echo $PATH | tr ':' '\n' | grep -v swiftly | paste -sd: -)`. After adding files, run `tuist generate --no-open`.
- Test command shape: `xcodebuild test -workspace ActoviaIos.xcworkspace -scheme <Module> -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:<Module>Tests/<Suite>`.
- Tests are Swift Testing (`@MainActor @Suite(…, .serialized)`, `#expect`). Mock HTTP with a file-private `URLProtocol`, as in `Tests/ChatFeatureTests/ChatListViewModelTests.swift`.
- Disk writes:
  - Use `.atomic, .completeFileProtection` and set `isExcludedFromBackup`, as in `ReportCache` (`Sources/HealthFeature/Report/ReportStore.swift`).
  - A read that fails (locked, corrupt, wrong version) returns nil and never throws to the UI.
- `URLCache` stays disabled. Nothing new caches images.
- Constants: `OfflineChatStore.maxChats = 50`, file format `version = 1`.

## Review Focus

1. **Switching between two paired computers.** The cache of the one not on show must survive (the owner's "kept apart per computer"), and must never be shown for the other. Today `onComputerChange` also fires on `switchTo`, so a blanket clear there would be wrong. Test in Task 1 (`prune keeps paired computers`) and Task 6.
2. **A corrupt, truncated or old-version cache file.** The UI shows the "can't load" state as today, not a crash or an empty list that looks real. Test in Task 1.
3. **A chat id that is not a UUID** (from a hostile or buggy server). It is never used as a file name. Test in Task 1.
4. **The connection drops while an answer is streaming.**
   - The stream's own error line still shows.
   - The banner appears.
   - Coming back online must not re-fetch over a run in flight; the silent refresh waits until no turn is streaming.
   - Test in Task 5.
5. **A 401 revoke while offline cached data is on screen.** The cache for that computer is deleted, and the existing pairing flow takes over. Test in Task 6.

---

### Task 1: OfflineChatStore

**Files:**
- Create: `Sources/ChatFeature/Offline/OfflineChatStore.swift`
- Modify: `Sources/ChatFeature/ChatHistoryRows.swift:68-82`. Make `ChatHistoryPage` `Codable`, and keep the decode of fields the server sends.
- Test: `Tests/ChatFeatureTests/OfflineChatStoreTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct CachedChatList: Codable, Equatable, Sendable { let version: Int; let savedAt: Date; let chats: [ChatSummary]; let favorites: [ChatSummary] }
  struct CachedChatPage: Codable, Sendable { let version: Int; let savedAt: Date; let page: ChatHistoryPage }
  public struct OfflineChatStore: Sendable {
      public static let maxChats = 50
      public init(root: URL, fingerprint: String)            // folder = root/<sha256(fingerprint) hex>
      public static func standard(fingerprint: String) -> OfflineChatStore   // root = Application Support/OfflineChats
      public func saveList(chats: [ChatSummary], favorites: [ChatSummary], at: Date)
      public func loadList() -> CachedChatList?
      func savePage(_ page: ChatHistoryPage, chatId: String, at: Date)   // evicts beyond maxChats, oldest savedAt first
      func loadPage(chatId: String) -> CachedChatPage?
      public func cachedChatIds() -> Set<String>
      public func clear()
      public static func prune(root: URL, keeping fingerprints: Set<String>)  // delete folders of computers no longer paired
  }
  ```
- Layout:
  - `<folder>/list.json`
  - `<folder>/chats/<chatId>.json`
  - A `chatId` that does not parse as `UUID` is ignored on save and returns nil on load.

- [ ] **Step 1: Write the failing tests** (temp dir per test, as in `Tests/HealthFeatureTests/ReportStoreTests.swift:20`):
  - `roundTripsList`: save, then load; `#expect(loaded.chats == chats && loaded.favorites == favs && loaded.savedAt == t)`.
  - `roundTripsPage`: a page from `ChatPageFixture`; `#expect(loaded.page.messages.count == fixture.messages.count && loaded.page.olderCursor == fixture.olderCursor)`.
  - `evictsOldestBeyondFifty`: save 51 pages, the i-th at `t + i`; `#expect(store.cachedChatIds().count == 50 && !ids.contains(firstId))`.
  - `corruptFileReadsAsNil`: write `"{"` to `list.json` and to a page file; both loads are nil. Repeat with `version: 2` JSON.
  - `rejectsNonUUIDChatId`: `savePage(page, chatId: "../x")`; nothing is written outside `chats/` and `loadPage(chatId: "../x") == nil`.
  - `separatesComputers`: two stores with fingerprints "A" and "B" on one root; a save in A is invisible to B.
  - `pruneKeepsPairedComputers`: stores A and B, `prune(root:keeping: ["A"])`; A's list still loads and B's folder is gone.
  - `clearRemovesEverything`.
- [ ] **Step 2: Run them; they fail to compile** (`OfflineChatStore` is undefined).
  Run: `xcodebuild test … -scheme ChatFeature -only-testing:ChatFeatureTests/OfflineChatStoreTests`
- [ ] **Step 3: Implement it.**
  - JSON with `.iso8601` dates.
  - Each write is `.atomic, .completeFileProtection` plus `isExcludedFromBackup` on the folder.
  - Eviction reads each page's `savedAt`. Use the file modification date only if decode fails, and delete that file.
- [ ] **Step 4: Run them; all pass.**
- [ ] **Step 5: Commit** `feat(offline): a per-computer store for the chat list and opened chats (ISSUE-242)`.

### Task 2: ConnectionStatus, fed by APIClient

**Files:**
- Create: `Sources/NetworkingKit/ConnectionStatus.swift`
- Modify:
  - `Sources/NetworkingKit/APIClient.swift:191-198` (where a response arrives).
  - The transport-error path (`:303-318` helpers). That is where a request fails with `URLError` or `HTTPError(statusCode: 0)` after trying every route.
- Test: `Tests/NetworkingKitTests/ConnectionStatusTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor @Observable public final class ConnectionStatus {
      public static let shared: ConnectionStatus
      public private(set) var isOffline: Bool          // starts false
      public func markOffline()
      public func markOnline()
  }
  // APIClient gains `status: ConnectionStatus?` (init parameter, default `.shared`; tests pass a fresh instance).
  ```
- Rules:
  - Any HTTP response (any status, 401 included) → `markOnline()`.
  - A failure where no response arrived on any route → `markOffline()`.
  - A cancelled request (`URLError.cancelled`, `CancellationError`) changes nothing.

- [ ] **Step 1: Failing tests:**
  - `transportFailureMarksOffline`: the mock throws `URLError(.cannotConnectToHost)`; after the call fails, `#expect(status.isOffline)`.
  - `anyResponseMarksOnline`: offline first, then a 500 → `#expect(!status.isOffline)`.
  - `cancellationLeavesStateAlone`.
- [ ] **Step 2: Run; they fail.** `-scheme NetworkingKit -only-testing:NetworkingKitTests/ConnectionStatusTests`
- [ ] **Step 3: Implement.** Hop to the main actor with `await MainActor.run`; `APIClient` is a Sendable struct.
- [ ] **Step 4: Run them, plus the whole NetworkingKit suite; green.**
- [ ] **Step 5: Commit** `feat(offline): know from requests whether the computer answers (ISSUE-242)`.

### Task 3: The chat list reads and writes the store

**Files:**
- Modify: `Sources/ChatFeature/ChatListViewModel.swift` (`load()` :44, `refresh()` :65, `fetchPage` :108, `rename` :167, `delete` :138, `toggleFavorite` :94)
- Test: `Tests/ChatFeatureTests/ChatListViewModelOfflineTests.swift`

**Interfaces:**
- Consumes: Task 1 `OfflineChatStore`; Task 2 `ConnectionStatus`.
- Produces on `ChatListViewModel`:
  - `init(…, offlineStore: OfflineChatStore?, status: ConnectionStatus)`
  - `private(set) var lastSyncedAt: Date?`
  - `private(set) var showsCached: Bool`
  - `func isAvailableOffline(_ chatId: String) -> Bool`, which is true when online or the page is cached.
  - `var canEdit: Bool`, which is `!status.isOffline`.

- [ ] **Step 1: Failing tests:**
  - `savesFirstPageOnSuccess`: after `load()`, `store.loadList()?.chats.map(\.id) == ids` and `lastSyncedAt != nil`. Only the first page is saved, not `loadMore` pages.
  - `fallsBackToCacheWhenUnreachable`: seed the store, the mock fails with `URLError(.notConnectedToInternet)`; after `load()`, `chats` equals the cached list, `showsCached`, `!loadFailed`, `lastSyncedAt == seeded savedAt`.
  - `noCacheStillShowsCantLoad`: same failure with an empty store → `loadFailed` as today.
  - `editsRefusedOffline`: with the status offline, `rename`, `delete` and `toggleFavorite` send no request (the recorder is empty).
  - `isAvailableOfflineFollowsCache`.
- [ ] **Step 2: Run; fail.**
- [ ] **Step 3: Implement.**
  - `refresh()` keeps its silent behaviour.
  - On success it writes the store and clears `showsCached`.
- [ ] **Step 4: Run with the existing `ChatListViewModelTests`; green.**
- [ ] **Step 5: Commit** `feat(offline): the chat list survives a computer that doesn't answer (ISSUE-242)`.

### Task 4: A chat's newest page reads and writes the store

**Files:**
- Modify: `Sources/ChatFeature/ChatDetailViewModel.swift`:
  - `loadHistory()` :275-301
  - gates `canSend` :201, `canRegenerate` :220, `canChoose` :505-535
  - `sendMessage` :344, `regenerate` :493, `choose` :505
- Test: `Tests/ChatFeatureTests/ChatDetailViewModelOfflineTests.swift`

**Interfaces:**
- Consumes: Task 1 and Task 2.
- Produces on `ChatDetailViewModel`:
  - `init(…, offlineStore: OfflineChatStore?, status: ConnectionStatus)`
  - `private(set) var showsCached: Bool`
  - `var isReadOnly: Bool`, which is `status.isOffline`.
  - `func refreshAfterReconnect() async`, which re-fetches the newest page and merges it with `ChatHistoryRows` as `loadHistory` does. It does not reset `hasLoadedHistory` or clear `messages`, and returns at once while a turn is streaming.

- [ ] **Step 1: Failing tests:**
  - `savesNewestPage`: after `loadHistory()`, `store.loadPage(chatId:)` matches the served page. A `loadOlder` page is not written.
  - `fallsBackToCachedPage`: seed, then the mock fails with a transport error; `messages` are the cached ones, `hasLoadedHistory`, `showsCached`, no error alert.
  - `noCachedPageShowsError`: as today.
  - `offlineRefusesWrites`: with the status offline, `canSend == false`, `canRegenerate == false`, `canChoose(runId) == false`, and `sendMessage()` sends nothing while the draft text is kept.
  - `refreshAfterReconnectWaitsForStream`: while streaming, the call makes no request.
- [ ] **Step 2: Run; fail.**
- [ ] **Step 3: Implement.** Save in the same place `loadHistory` decodes. `refreshAfterReconnect` also writes the store.
- [ ] **Step 4: Run with all `ChatDetailViewModel*Tests`; green.**
- [ ] **Step 5: Commit** `feat(offline): an opened chat can be read without the computer (ISSUE-242)`.

### Task 5: The offline UI

**Files:**
- Create: `Sources/ChatFeature/Offline/OfflineBanner.swift`
- Modify:
  - `Sources/ChatFeature/ChatSidebarView.swift`: banner at the top of the list; rows (greyed with `.foregroundStyle(.secondary)`) via `isAvailableOffline`; menu :333-361, swipe :326-329 and accessibility actions :319-324 disabled by `canEdit`; tapping an unavailable row shows the alert below.
  - `Sources/ChatFeature/ChatDetailView.swift`: banner under the title; `turnButton` disabled (:454); the composer placeholder becomes the offline hint while offline; `ComposerToolsButton` disabled; `transcriptActions` (:481-499) pass nil regenerate/choose while read-only; `.onChange(of: status.isOffline)` going false → `refreshAfterReconnect()`.
- Test: `Tests/ChatFeatureTests/OfflineBannerTests.swift`. The text is built by a pure function.

**Interfaces:**
- Produces:
  ```swift
  struct OfflineBanner: View { let lastSyncedAt: Date?; let retry: () -> Void }
  static func OfflineBanner.text(lastSyncedAt: Date?, now: Date, locale: Locale) -> String
  ```
- Copy (English source; add each key with `scripts/l10n.py add`, then fill all languages):
  - `ios:offline.banner` = "Offline · Last synced %@". `%@` is a relative time ("5 min ago"), from `Date.RelativeFormatStyle`.
  - `ios:offline.bannerNoSync` = "Offline".
  - `ios:offline.unavailableTitle` = "Not available offline".
  - `ios:offline.unavailableMessage` = "This chat hasn't been opened on this iPhone yet. It will open once your computer is reachable."
  - `ios:offline.composerHint` = "Offline — you can send once you're connected".
- Behaviour:
  - Tapping the banner calls `retry`: the list's `refresh()`, or the detail's `refreshAfterReconnect()`.
  - The banner has no animation beyond the default insertion fade.
  - It is announced to VoiceOver as one element with the accessibility hint "Double-tap to retry". Add the key `ios:offline.retryHint`.

- [ ] **Step 1: Failing tests:** `textWithSync` (contains "Offline" and the relative time), `textWithoutSync == "Offline"` (en locale).
- [ ] **Step 2: Run; fail.**
- [ ] **Step 3: Implement the banner and the view wiring.** Add the strings, then run `python3 scripts/l10n.py audit`; it is clean.
- [ ] **Step 4: Run the ChatFeature suite; green.** Build the App scheme for the simulator.
- [ ] **Step 5: Manual check on the "Actovia Shots" simulator against the demo desktop app (never the owner's).**
  1. Open two chats.
  2. Stop the demo app. The banner shows; the two chats open read-only; others are grey and show the alert; send, regenerate and the menu are disabled.
  3. Restart the demo app and tap the banner. It disappears and the open chat refreshes without jumping.
  4. Take screenshots for the In Review comment.
- [ ] **Step 6: Commit** `feat(offline): say when the computer is away and keep chats readable (ISSUE-242)`.

### Task 6: Clearing on unpair, revoke and switch

**Files:**
- Modify:
  - `Sources/App/ActoviaApp.swift:28-31` (the `onComputerChange` subscribers).
  - `Sources/App/AppShell.swift`: build the per-computer `OfflineChatStore.standard(fingerprint:)` from the active route's fingerprint, and pass it with `ConnectionStatus.shared` into the list and detail view models.
- Test: `Tests/AppTests/OfflineCacheLifecycleTests.swift` (or `ChatFeatureTests`, if AppTests cannot reach `PairedComputers` without the Keychain; use `InMemoryCredentialStore`).

**Interfaces:**
- Consumes: Task 1 `prune(root:keeping:)`.
- On every `onComputerChange`, call `OfflineChatStore.prune(root: standardRoot, keeping: Set(pairedComputers.servers.map(\.fingerprint)))`. This covers unpair, forget and revoke, which all remove the server first; a switch removes nothing.
- On the same event, `ConnectionStatus.shared.markOnline()`, so the next computer starts clean.

- [ ] **Step 1: Failing tests:**
  - `revokeDeletesThatComputersCache`: two paired fingerprints with caches; `revoked(fingerprint: B)`; B's folder is gone and A's list still loads.
  - `switchKeepsBoth`: `switchTo(A)` leaves both folders.
- [ ] **Step 2: Run; fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run AppTests and the ChatFeature suite; green.** Build App.
- [ ] **Step 5: Commit** `feat(offline): a computer's cache leaves with the computer (ISSUE-242)`.

---

Done when all six tasks are committed, the audit is clean, the manual check in Task 5 has screenshots, and ISSUE-242 is In Review with them.
