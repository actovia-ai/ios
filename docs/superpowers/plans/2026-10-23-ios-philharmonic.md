# Philharmonic on iPhone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Philharmonic placeholder with the desktop's group workspace — group list, live group chat
(plan, reports, agent cards with Allow/Deny/questions, decision process), composer with photos/Stop/ask_user,
members with quota, a read-only Dashboard (costs, schedule) and Workforce — over the paired LAN connection.

**Architecture:** Wire types and the SSE event enum live in `Models`; `PhilharmonicAPI` (NetworkingKit) wraps the
routes on `APIClient`; `SSEClient` becomes generic over its event type. Every rule the desktop has as a pure
function (message merge, plan patch, busy reducer, quota wording, round description) is a pure Swift function with
the desktop's test vectors. One `@MainActor @Observable GroupChatViewModel` per open group owns state and the
stream (`GroupStream`: reconnect with backoff, a 45 s idle watchdog). Views reuse ChatFeature's pieces, made
`public` in place.

**Tech Stack:** SwiftUI (iOS 26), Swift 6, Tuist static frameworks, Swift Testing, URLSession `bytes(for:)`.

**Spec:** `docs/superpowers/specs/2026-10-23-ios-philharmonic-design.md` (desktop part merged: desktop master
`50381a19`). Desktop wire shapes are quoted below from `actovia/packages/shared/src/types/{philharmonic,agents,pm-round}.ts`,
`src/renderer/stores/philharmonic.ts` and the routes; read those files when a field is in doubt — they win.

## Global Constraints

- Swift 6, iOS 26, iPhone only; Swift Testing; test targets are hostless (`String(localized:defaultValue:comment:)`
  outside views, `Text(verbatim:)` for user data, no ternary of two string literals).
- Every user-facing string through the catalog: desktop `philharmonic:` keys via `python3 scripts/l10n.py add
  "philharmonic:<path>"` + `sync-from-desktop` where the text is the desktop's; `ios:philharmonic.*` with
  `--en-value` otherwise. All shipped locales (including zh-Hans and ru after Task 1).
- No copied view: a ChatFeature view needed here is made `public` in place (ChatFeature stays the owner).
- Tone: Philharmonic's layout is neutral; a group's transcript and composer take the colour tone.
- Layout: reading column (`.readingColumn()`), docked sidebar on an unfolded Duo, drawer on iPhone; no title header
  in a group; toolbar buttons where the chat puts them.
- API: `/api/v1/philharmonic/*`, `/api/v1/agents/*`. Responses are bare JSON (no envelope); errors
  `{type:"error", error:{code,message,params?}}` → `HTTPError`. Timestamps are ISO-8601 strings with fractional
  seconds (kept as `String`, parsed with `ISO8601FormatStyle(includingFractionalSeconds:)` on demand, the app's
  convention); quota times are epoch **ms** (`Double / 1000`).
- Decode leniently: an unknown event `type` or part `kind` is `.unknown`/skipped, never a thrown decode.
- `message_delta.delta` is the whole text so far: **replace**, never append.
- Tests: after adding/removing files `tuist generate --no-open`; run a module with
  `xcodebuild test -workspace ActoviaIos.xcworkspace -scheme <Module> -destination "platform=iOS Simulator,id=D8A2BE45-88F3-46AE-8693-B147F2815724" -only-testing:<Module>Tests/<SwiftTypeName>`
  (the iPhone 17e; never the Actovia Shots / Duo / Hikki simulators). A wrong `-only-testing` name still prints
  SUCCEEDED — confirm the "Test run with N tests" line.
- Commits on branch `feat/philharmonic` only.

## Review Focus

1. A group deleted on the desktop while it is open on the phone (`/messages` or `/sse` answers 404): the phone says
   so and returns to the list, no reconnect loop. → Task 7 test `deletedGroupStopsAndReports`.
2. The app locked while the stream reconnects (`APP_LOCKED`): unlock once through `ServerConnection.unlockComputer`,
   then connect; if unlock fails, stop retrying and show the locked state. → Task 6 test `lockedConnectUnlocksOnce`.
3. A permission prompt answered on the desktop first: the phone's Allow gets `409 AGENT_PROMPT_GONE` → the card shows
   settled, no error. → Task 7 test `promptGoneSettlesQuietly`.
4. Coming back from the background after minutes away: reconnect at once and read messages + plan whole (missed
   events are not replayed). → Task 6 test `foregroundReconnectsImmediately`, Task 7 `reconnectReadsWhole`.
5. Two `message_end`s close together, and a `message_end` whose row is saved after it (an employee's turn): the
   `?after=` re-read dedups and a missed row comes with the next bump. → Task 5 merge vectors + Task 7
   `afterReadDedupsAndFallsBack`.

---

### Task 1: Locales and module wiring

**Files:**
- Modify: `Vendor/actovia-locales/` (git subtree pull from desktop master `50381a19`, README "Refreshing" recipe)
- Modify: `Resources/App/Localizable.xcstrings` (`sync-from-desktop`)
- Modify: `Project.swift` (`PhilharmonicFeature` deps; new `PhilharmonicFeatureTests` target)
- Create: `Tests/PhilharmonicFeatureTests/SmokeTests.swift`

**Interfaces:**
- Produces: module `PhilharmonicFeature` depending on `[Models, NetworkingKit, ChatFeature, MarkdownKit, OdyKit]`;
  test target `PhilharmonicFeatureTests` depending on `[PhilharmonicFeature, NetworkingKit, Models]`.

- [ ] **Step 1:** Refresh the vendored catalogs (subtree split of `packages/shared/src/i18n/locales` at desktop
      `50381a19`, pull `--squash` in a throwaway worktree, `--ff-only` merge). Expected: `Vendor/actovia-locales/zh-Hans`
      and `/ru` exist.
- [ ] **Step 2:** `python3 scripts/l10n.py sync-from-desktop` then `python3 scripts/l10n.py audit`. Expected: audit
      reports no missing translation for the shipped locales; `python3 -m unittest Tests.L10nScriptTests.test_l10n` passes.
- [ ] **Step 3:** Project wiring + a smoke test `@Test("the module links") func links()` that imports
      `PhilharmonicFeature`; `tuist generate --no-open`; run scheme `PhilharmonicFeature`. Expected: 1 test passes.
- [ ] **Step 4: Commit** `chore(i18n): vendored catalogs from desktop 50381a19 (zh-Hans, ru)` and
      `build(philharmonic): the feature module and its tests`.

### Task 2: A generic SSE client

**Files:**
- Modify: `Sources/NetworkingKit/SSEClient.swift`, `Sources/NetworkingKit/SSEFrameParsing.swift`
- Test: `Tests/NetworkingKitTests/SSEFrameParsingTests.swift` (add), `Tests/NetworkingKitTests/SSEClientGenericTests.swift`

**Interfaces:**
- Produces:
  - `SSEFrameParsing.frame<E: Decodable & Sendable>(_ type: E.Type, fromLine: String, decoder: JSONDecoder = JSONDecoder()) -> Frame<E>`
    with `enum Frame<E> { case event(E), undecodable(type: String?, reason: String, bytes: Int), ignored, comment }`
    — a line starting with `:` is `.comment` (Task 6 counts it as "the connection is alive").
  - `SSEClient.events<E: Decodable & Sendable>(_ type: E.Type, for: URLRequest, session: URLSession? = nil) -> AsyncThrowingStream<SSEItem<E>, Error>`
    with `enum SSEItem<E> { case event(E), heartbeat }`.
  - The existing `frame(fromLine:)` / `events(for:session:)` keep their signatures and `ChatSseEvent` behaviour
    (thin wrappers), so ChatFeature is untouched.

- [ ] **Step 1: Failing tests:** `": ping"` → `.comment`; a `data: {"type":"x"}` line decodes into a test enum; the
      existing ChatSseEvent tests unchanged; the stream yields `.heartbeat` for `: ping` and `.event` for data
      (MockURLProtocol body `": ping\n\ndata: {…}\n\n"`).
- [ ] **Step 2:** Run scheme `NetworkingKit`. Expected: FAIL (no generic overload).
- [ ] **Step 3:** Implement; the ChatSseEvent entry points call the generic ones and drop `.heartbeat`.
- [ ] **Step 4:** Run `NetworkingKit` and `ChatFeature` schemes. Expected: all pass.
- [ ] **Step 5: Commit** `refactor(sse): the client reads any event type, and says when the server pings`.

### Task 3: Philharmonic wire models

**Files:**
- Create: `Sources/Models/Philharmonic/` — `GroupConversation.swift`, `GroupMessage.swift` (+ `GroupMessagePart`),
  `AgentCard.swift` (`AgentCard`, `AgentPrompt`, `AgentQuestion`, `AgentAnswer`), `GroupPlan.swift` (`GroupPlan`,
  `PlanStep`, `PlanStepPatch`), `CliQuota.swift`, `PmRoundEvent.swift`, `PhilharmonicCosts.swift`,
  `ScheduledTask.swift`, `Employee.swift` (`Employee`, `Team`), `PhilharmonicSseEvent.swift`
- Test: `Tests/ModelsTests/PhilharmonicModelsTests.swift`, fixtures in `Tests/ModelsTests/Fixtures/philharmonic-events.jsonl`

Field lists (all `Codable, Sendable, Equatable`; `?` = optional; ISO dates as `String`):
- `GroupConversation`: id, title, icon?, memberAgentIds [String]?, archived Bool?, createdAt, updatedAt, lastMessageAt,
  latestMessage `{role, content, agentId?, createdAt}`?
- `GroupMessage`: id, conversationId, role (`user|pm|employee|system` → `enum GroupRole` with `.unknown(String)`),
  agentId?, content, parts `[GroupMessagePart]` (absent/null → `[]`), taskId?, roundId?, createdAt.
- `GroupMessagePart` by `kind`: `.attachment(name,url,contentType)`, `.artifact(artifactId,title,code)`,
  `.decision(delegations,waits)`, `.agentCard(AgentCard)`, `.unknown(kind)`.
- `AgentCard`: sessionId, agentId, runtime, model?, projectName, cwd, branch?, state (`working|blocked|done|stopped|error`),
  steps `[{id, tool, summary, status: running|ok|error}]`, blocks [String], pending String, prompts [AgentPrompt],
  notices [String], costUsd?, denials Int, error?, continuedInTerminal Bool, queued Bool.
- `AgentPrompt`: `.permission(requestId, tool, summary, detail)` | `.question(requestId, questions [AgentQuestion])`;
  `AgentQuestion`: id?, isOther?, isSecret?, question, header?, multiSelect, options `[{label, description?}]`.
- `AgentAnswer` (Encodable): `.allow` → `{kind:"allow"}`, `.deny(reason?)`, `.answers([String: AnswerValue])` where
  `AnswerValue` is a string or `[String]`; keys are `question.id ?? question.question`.
- `GroupPlan`: id, conversationId, summary, status (`drafting|active|completed|aborted`), createdAt, updatedAt,
  steps [PlanStep]; `PlanStep`: id, planId, ordinal, title, intent?, assignedAgentId?, status
  (`pending|running|done|skipped|failed`), output?, note?, taskId?, startedAt?, completedAt?.
- `PlanStepPatch`: every field `Patch<T>` = `.absent | .null | .value(T)` (absent vs explicit null matters).
- `CliQuota`: cli, windows `[QuotaWindow{name, usedPercent, resetsAt ms?, model?, rejected?, seenAt ms?, durationMins?}]`,
  state (`ok|warning|rejected`), rejectedWindow?, overage, asOf ms.
- `PmRoundEvent`: seq, kind, payload (`JSONValue`), createdAt.
- `PhilharmonicCosts`: totalCost, totalTokens, byConversation `[{conversationId,cost,tokens}]`, byAgent
  `[{agentId,cost,tokens}]`, daily `[{date "YYYY-MM-DD", cost, tokens}]`.
- `ScheduledTask`: id, conversationId?, title, description?, status, priority, assignedAgentId?, cronExpression?,
  runAt?, lastRunAt?, lastRunStatus?, createdAt.
- `Employee`: id, name, description?, teamId?, avatarSeed?, avatarStyle?, model?, provider?, runtime
  (`actovia|claude-code|codex`), isActive?; `Team`: id, name, description?, icon?.
- `PhilharmonicSseEvent` (conversation events only; task-scoped ones and anything else → `.unknown(type)`):
  `messageStart(conversationId, messageId, role, agentId?)`, `messageDelta(conversationId, messageId, delta)`,
  `messageEnd(conversationId, messageId)`, `toolCard(conversationId, messageId, toolName, phase: start|end, result: JSONValue?)`,
  `agentCard(conversationId, messageId, card)`, `memberJoined(conversationId, agentId)`, `roundStart(conversationId, label)`,
  `askUser(conversationId, question, options)`, `conversationError(conversationId, error)`, `pmStarted(conversationId)`,
  `pmEnded(conversationId, reason)`, `delegationRetry(conversationId, taskId, agentId, attempt, delayMs, error)`,
  `planCreated(conversationId, plan)`, `planStepUpdated(conversationId, stepId, patch)`,
  `planStepAppended(conversationId, step)`, `planStatusChanged(conversationId, status)`, `unknown(type)`.

- [ ] **Step 1: Failing tests:** `decodesEveryEventFromFixture` — the fixture has one line per conversation event
      type plus `task_status` and an invented `"future_event"`; each decodes to its case, the last two to `.unknown`.
      `messageWithUnknownPartKeepsTheRest` — parts `[attachment, {kind:"hologram"}, decision]` → 3 parts, middle
      `.unknown("hologram")`. `stepPatchTellsAbsentFromNull` — `{"note":null}` → note `.null`, output `.absent`.
      `agentAnswerEncodesAsDesktopExpects` — `.allow` → `{"kind":"allow"}`; `.answers(["Which?": .one("A")])` →
      `{"kind":"answers","answers":{"Which?":"A"}}`. `quotaTimesAreMilliseconds` — `resetsAt: 1761200000000`.
- [ ] **Step 2:** Run `Models`. Expected: FAIL (types missing).
- [ ] **Step 3:** Implement. Reuse Models' internal `AnyCodingKey` / `lenient(_:forKey:)`; add `JSONValue` if Models
      has none (`.string|.number|.bool|.object|.array|.null`).
- [ ] **Step 4:** Run `Models`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(models): Philharmonic's wire types and events`.

### Task 4: `PhilharmonicAPI`

**Files:**
- Create: `Sources/NetworkingKit/PhilharmonicAPI.swift`
- Modify: `Sources/NetworkingKit/APIClient.swift` (only if a decoding `patch`/`put` is missing: add
  `put<Body,T>(_:body:) -> T` and `patch<Body,T>(_:body:) -> T` beside the existing ones)
- Test: `Tests/NetworkingKitTests/PhilharmonicAPITests.swift`

**Interfaces:**
- Produces `public struct PhilharmonicAPI: Sendable { public init(client: APIClient, serverConfig: ServerConfigStore) }` with:
  `conversations() -> [GroupConversation]`; `createConversation(title: String, icon: String?) -> GroupConversation`
  (POST `/conversations`); `renameConversation(id:title:icon:) -> GroupConversation` (PUT `/conversations/:id`);
  `deleteConversation(id:)`; `messages(conversationId:after: String? = nil) -> [GroupMessage]`;
  `send(conversationId:content:attachments: [OutgoingAttachment]) -> GroupMessage` (`OutgoingAttachment{name,url,contentType}`,
  url a `data:image/…` URL); `interrupt(conversationId:) -> Bool` (`wasRunning`); `answerAskUser(conversationId:response:)`;
  `plan(conversationId:) -> GroupPlan?`; `round(conversationId:roundId:) -> [PmRoundEvent]`;
  `costs(days: Int?) -> PhilharmonicCosts` (`?days=30` for the dashboard); `upcomingTasks()`, `recurringTasks() -> [ScheduledTask]`;
  `cancelTask(id:) -> ScheduledTask` (PATCH `{status:"cancelled"}`); `employees() -> [Employee]` (GET `/agents`);
  `teams() -> [Team]`; `quota() -> [CliQuota]` (GET `/api/v1/agents/quota`);
  `respond(sessionId:requestId:answer: AgentAnswer) -> RespondOutcome` (`.done | .gone` — `409 AGENT_PROMPT_GONE` is
  `.gone`, every other error throws); `streamRequest(conversationId:) -> URLRequest?` (GET
  `/api/v1/philharmonic/conversations/:id/sse` on `route.bases.first`, `route.authorization`, `timeoutInterval = 3600`,
  built as `ChatStreamManager.makeRequest` builds the chat's).
  All paths under `/api/v1/philharmonic` unless noted.

- [ ] **Step 1: Failing tests** (MockURLProtocol): `messagesAfterSendsQuery` (path + `after=m9`);
      `sendPostsDataURLAttachments` (body JSON); `respondMapsGoneTo409` (409 `AGENT_PROMPT_GONE` → `.gone`; 500 →
      throws `HTTPError`); `costsAskForThirtyDays` (`?days=30`); `streamRequestCarriesAuthorization`.
- [ ] **Step 2:** Run `NetworkingKit`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `NetworkingKit`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(networking): the Philharmonic API`.

### Task 5: The desktop's rules, as pure functions

**Files:**
- Create in `Sources/PhilharmonicFeature/Logic/`: `GroupMessageMerge.swift`, `PlanPatching.swift`,
  `BusyAgents.swift`, `QuotaWording.swift`, `RoundDescription.swift`, `GroupHistory.swift`
- Test: `Tests/PhilharmonicFeatureTests/` one file per source file

**Interfaces** (all `public`, used by Tasks 7, 9, 10):
- `struct LiveBubble { messageId, role: GroupRole, agentId: String?, text: String, toolRows: [ToolRow], agentCard: AgentCard? }`,
  `struct ToolRow { toolName, phase, result: JSONValue? }`;
  `struct GroupBubble: Identifiable { id, role, agentId?, text, attachments, artifacts: [ArtifactPart], decision?, agentCard?, agentCardSuperseded: Bool, toolRows, roundId?, createdAt?, isLive: Bool }`;
  `GroupMessageMerge.merge(history: [GroupMessage], live: [LiveBubble], liveCards: [String: AgentCard]) -> [GroupBubble]`
  — desktop `merge-group-messages.ts`: history rows first (attachments/artifacts/first decision from parts; card =
  `liveCards[id] ?? first agent_card part`), then live bubbles whose id is not saved (artifacts from end-phase
  tool rows whose `result.type == "artifact"`), then every card but its session's latest is superseded.
- `PlanPatching.apply(_ event: PhilharmonicSseEvent, to plan: GroupPlan?) -> GroupPlan?` — created replaces; step
  updated merges the patch (`.absent` keeps, `.null` clears, `.value` sets; ignored without a plan); appended adds;
  status changed sets.
- `BusyAgents` (value type) with `mutating func apply(_ event: PhilharmonicSseEvent)` and `label(for actor: String) -> BusyLabel?`
  (`.orchestrating | .thinking | .running(tool)`; actor `"__pm__"` or agentId) — desktop `busy-reducer.ts`.
- `QuotaWording.parts(_ q: CliQuota, now: Date) -> [QuotaPart]` (`QuotaPart{key: .fiveHour|.sevenDay|.other, name, percent, reset, stale, limited, resetsAt: Date?}`)
  and `QuotaWording.windowLabel(_ w: QuotaWindow) -> String` — desktop `lib/agent-quota.ts` / `agents/quota.ts`.
- `RoundDescription.lines(_ events: [PmRoundEvent], bubbleText: String) -> [RoundLine]` — desktop `lib/pm-round.ts`
  (`trigger, reports, thinking, text, call(tool,args,result?,isError,refused), usage, error`; last text dropped when
  equal to the bubble's, trimmed).
- `GroupHistory.append(_ held: [GroupMessage], _ rows: [GroupMessage]) -> [GroupMessage]` (dedup by id).

- [ ] **Step 1: Failing tests** — port each desktop test file's cases by name, same inputs and expectations:
      `merge-group-messages.test.ts` (3 cases, incl. superseded `[m1 true, m2 true, m3 false, m4 false]`);
      `busy-reducer.test.ts` (8); `agent-quota.test.ts` (3) and `quota.test.ts` `quotaWindowLabel` vectors
      (`five_hour`→"5-hour", `seven_day`→"week", `seven_day_opus`+opus→"opus only: week", `primary`→"primary",
      `primary`+300→"5-hour", `"GPT-5.6 Pro secondary"`+10080+`gpt-5.6-pro`→"gpt-5.6-pro only: week",
      `secondary`+60→"secondary"); `pm-round.test.ts`; plan patch: absent/null/value + ignored without a plan;
      `GroupHistory.append` dedups in either order.
- [ ] **Step 2:** Run `PhilharmonicFeature`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS (every ported case).
- [ ] **Step 5: Commit** `feat(philharmonic): the desktop's merge, plan, busy, quota and round rules`.

### Task 6: `GroupStream` — reconnecting event stream

**Files:**
- Create: `Sources/PhilharmonicFeature/GroupStream.swift`
- Test: `Tests/PhilharmonicFeatureTests/GroupStreamTests.swift`

**Interfaces:**
- Produces `public actor GroupStream` with
  `init(connect: @Sendable () async throws -> AsyncThrowingStream<SSEItem<PhilharmonicSseEvent>, Error>, unlock: @Sendable () async -> Bool, sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, idleLimit: Duration = .seconds(45))`
  and `func updates() -> AsyncStream<GroupStreamUpdate>` where
  `enum GroupStreamUpdate { case connected, event(PhilharmonicSseEvent), disconnected(retryIn: Duration), gone, locked }`;
  `func reconnectNow()` (foreground). `connected` is yielded on every (re)connect — the view model reads whole on it.
- Rules: backoff 1, 2, 4, 8, 16, 30, 30 … s, reset after the first event/heartbeat of a connection; no byte for
  `idleLimit` → drop and reconnect; `HTTPError` 404 → `.gone`, stop; `APP_LOCKED` → `unlock()` once, success →
  connect at once, failure → `.locked`, stop; cancellation of the consumer ends it.

- [ ] **Step 1: Failing tests** (fake `connect` and recorded `sleep`): `backoffDoublesToThirty`
      (six failures → sleeps `[1,2,4,8,16,30]` s); `firstByteResetsBackoff`; `idleLimitDropsAndReconnects`
      (a stream that never yields, `idleLimit: .milliseconds(50)` → a second `connect`); `notFoundIsGone`;
      `lockedConnectUnlocksOnce` (unlock true → connected; unlock false → `.locked`, `connect` called once);
      `foregroundReconnectsImmediately` (`reconnectNow()` during a backoff sleep → connect without waiting).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5: Commit** `feat(philharmonic): a group stream that comes back on its own`.

### Task 7: `GroupChatViewModel`

**Files:**
- Create: `Sources/PhilharmonicFeature/GroupChatViewModel.swift`
- Test: `Tests/PhilharmonicFeatureTests/GroupChatViewModelTests.swift`

**Interfaces:**
- Consumes: `PhilharmonicAPI` (Task 4), `GroupStream` (Task 6), Task 5's functions.
- Produces `@MainActor @Observable public final class GroupChatViewModel` with
  `init(conversationId: String, api: PhilharmonicAPI, stream: GroupStream)` and public read-only state
  `bubbles: [GroupBubble]`, `plan: GroupPlan?`, `askUser: (question: String, options: [String])?`, `pmRunning: Bool`,
  `busy: BusyAgents`, `notice: GroupNotice?` (`.gone | .locked | .error(String)`), `isLoading: Bool`; methods
  `start() async` (read messages + plan, then consume the stream; on every `.connected` read both whole again),
  `stop()`, `send(text: String, pictures: [ComposerPicture]) async` (pictures → `data:` URLs through
  `ComposerPicture`'s prepared JPEG/PNG data), `interrupt() async`, `answer(_ text: String) async` (ask_user),
  `respond(card: AgentCard, prompt: AgentPrompt, answer: AgentAnswer) async`, `round(_ roundId: String) async -> [PmRoundEvent]` (cached per id).
- Event handling: `messageStart` adds a live bubble; `messageDelta` replaces its text; `toolCard` adds/updates a tool
  row; `agentCard` sets `liveCards[messageId]`; `messageEnd` → `messages(after: last held id)` appended with
  `GroupHistory.append`, any error → read whole; `plan*` → `PlanPatching.apply`; `askUser` sets it, `pmStarted`/`pmEnded`
  set `pmRunning` (pmEnded clears askUser); `conversationError` → `notice = .error`; events whose `conversationId`
  differs are ignored; `busy.apply` sees every event. Live bubbles whose id is saved are dropped by the merge.

- [ ] **Step 1: Failing tests** (Harness: MockURLProtocol `APIClient` + a `GroupStream` over a scripted
      `AsyncThrowingStream`): `startReadsMessagesAndPlan`; `deltaReplacesText` (deltas "He", "Hello" → "Hello");
      `afterReadDedupsAndFallsBack` (two `messageEnd`s → one appended row; a 500 on `after` → a whole read);
      `reconnectReadsWhole` (second `.connected` → second GET of `/messages` without `after` and of `/plan`);
      `deletedGroupStopsAndReports` (404 → `notice == .gone`, stream not restarted); `promptGoneSettlesQuietly`
      (409 → no `notice`, the prompt hidden for that requestId); `sendPostsDataURLs`; `askUserClearsOnPmEnded`;
      `otherConversationEventsIgnored`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5: Commit** `feat(philharmonic): one view model per open group`.

### Task 8: ChatFeature's shared pieces made public

**Files:**
- Modify (access level + `public init` only, no behaviour): `Sources/ChatFeature/AssistantTurnView.swift`
  (`UserBubble`, `TypingIndicator`, `RunErrorLine`), `ArtifactCard.swift`, `ComposerToolsViews.swift`
  (`ComposerToolsButton`, `ComposerPictureStrip`), `ComposerRowLayout.swift` (`ComposerRowLayout`, `.composerRole`),
  `VoiceInputViews.swift` (`TurnButtonLabel`, `TurnButtonState`), `ChatSidebarView.swift` (the `SidebarRow` modifier
  as `public extension View { func sidebarRow(isSelected: Bool, menu: (() -> UIMenu)? = nil, select: @escaping () -> Void) -> some View }`,
  `SidebarRowTouchSurface` stays internal behind it), `TranscriptLoading.swift` (`TranscriptSkeleton`).
- Modify: `ChatSidebarView` gains `@ViewBuilder lists: () -> Lists` (default `EmptyView`) and
  `showsRecents: Bool = true`: when `showsRecents` is false the Recents section, search and New Chat row are not drawn
  and `lists()` is drawn in their place.

- [ ] **Step 1:** Make the changes; `tuist generate --no-open`.
- [ ] **Step 2:** Run `ChatFeature` (all tests) and build `App`. Expected: unchanged pass count, build succeeds.
- [ ] **Step 3: Commit** `refactor(chat): the pieces a group transcript reuses are public`.

### Task 9: The workspace and its group list

**Files:**
- Modify: `Sources/App/AppWorkspace.swift` (`isAvailable` → `true` for all), `Sources/App/AppShell.swift`
  (`detail`: `.philharmonic` → `PhilharmonicRootView`; the sidebar passes `showsRecents: workspace != .philharmonic`
  and `lists: { GroupListSection(…) }`; toolbar New Chat hidden in Philharmonic, a New Group button in its place)
- Create: `Sources/PhilharmonicFeature/GroupListViewModel.swift`, `GroupListSection.swift`, `PhilharmonicRootView.swift`,
  `NewGroupSheet.swift`
- Delete: `Sources/PhilharmonicFeature/PhilharmonicPlaceholderView.swift` (and its two `ios:` keys if unused)
- Test: `Tests/PhilharmonicFeatureTests/GroupListViewModelTests.swift`

**Interfaces:**
- `@MainActor @Observable public final class GroupListViewModel` — `init(api:)`, `groups: [GroupConversation]` (newest
  `lastMessageAt` first), `load()`, `create(title:icon:) -> GroupConversation?`, `rename(_:title:)`, `delete(_:)`
  (optimistic, rolls back on failure, like `ChatListViewModel`).
- `GroupListSection(model:, activeId: String?, onSelect: (GroupConversation) -> Void)` — rows via `.sidebarRow`:
  icon (emoji) + title + `RecentTimestamp` of `lastMessageAt`, a one-line latest-message preview; long-press menu
  Rename / Delete (confirm); Dashboard and Workforce rows under the groups (my call for "Left to the builder").
- `PhilharmonicRootView(api:, selection: PhilharmonicSelection)` — `enum PhilharmonicSelection { case group(id, title), dashboard, workforce, none }`;
  `.none` shows an empty state with New Group.

- [ ] **Step 1: Failing tests:** `loadSortsByLastMessage`; `deleteRollsBackOnFailure`; `createInsertsAtTop`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement; strings: desktop's `philharmonic:` list/new-group keys where they exist
      (`l10n.py add` + `sync-from-desktop`), `ios:philharmonic.*` otherwise.
- [ ] **Step 4:** Run `PhilharmonicFeature` + build `App`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(philharmonic): the workspace lists its groups`.

### Task 10: The group chat screen

**Files:**
- Create in `Sources/PhilharmonicFeature/Chat/`: `GroupChatView.swift`, `GroupBubbleView.swift` (user → `UserBubble`
  with attachment images; pm/employee → avatar + name + role header and `MarkdownView`; system → a muted row),
  `ToolRowsView.swift` (one plain row per call: wrench, tool name, spinner or check — live bubbles only),
  `AgentCardView.swift` (steps, state, and when `blocked` its prompts: Allow / Deny with an optional reason field;
  a question's options, multi-select when `multiSelect`, "Other" free text when `isOther`; superseded cards show no
  prompts), `DecisionProcessView.swift` (collapsed line from the `decision` part's counts; opening fetches
  `round(_:)` once and lists `RoundDescription.lines`), `PlanCardView.swift` (summary, steps with status glyph and
  assignee name; pinned at the head of the transcript, collapses to one line on scroll), `GroupComposer.swift` (text,
  `ComposerToolsButton` + `ComposerPictureStrip`, Send / Stop via `TurnButtonLabel`; while `askUser` is set, the
  question and its options above the field, free text allowed)
- Test: `Tests/PhilharmonicFeatureTests/AgentPromptAnswerTests.swift` (the answer built from a question form)

**Interfaces:**
- Consumes Task 7's view model, Task 8's public views.
- `AgentPromptForm.answer(for questions: [AgentQuestion], selections: [String: Set<String>], other: [String: String]) -> AgentAnswer`
  (keys `id ?? question`; single-select → string, multi-select → array; "Other" text replaces an empty selection).

- [ ] **Step 1: Failing tests:** `singleSelectAnswersAString`, `multiSelectAnswersAnArray`, `keysByIdWhenPresent`,
      `otherTextFillsAnEmptySelection`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the form logic and the views. The transcript and composer sit in the tone scope; the
      rest neutral. Artifact parts open with `ArtifactCard`. Strings from the desktop's `philharmonic:chat.*`,
      `agents.*` keys.
- [ ] **Step 4:** Run tests; build `App`; on the iPhone 17e simulator against a running desktop (the owner's demo
      data, `ACTOVIA_HOME=/tmp/actovia-demo/home`), open a group, send a message, watch a round, answer a prompt;
      light and dark. Expected: matches the desktop's group in content and order.
- [ ] **Step 5: Commit** `feat(philharmonic): the group chat, live`.

### Task 11: Members, Dashboard, Workforce

**Files:**
- Create: `Sources/PhilharmonicFeature/Members/MembersSheet.swift` (+ `MembersViewModel.swift`),
  `Dashboard/DashboardView.swift` (+ `DashboardViewModel.swift`), `Workforce/WorkforceView.swift`
- Test: `Tests/PhilharmonicFeatureTests/MembersViewModelTests.swift`, `DashboardViewModelTests.swift`

**Interfaces:**
- `MembersViewModel(api:, memberIds: [String])` — employees filtered to the group, quota read on open and every 60 s
  while open (`start()`/`stop()`, injected `sleep`), `quotaLine(for: Employee, now:) -> (text: String, isLimited: Bool)?`
  from `QuotaWording.parts` with the desktop's wording ("5h {percent}%", "week {percent}%", "{name} {percent}%",
  " · " joined, " · limit reached · resets {weekday hh:mm}" from the first limited part).
- Members sheet: avatar, name, role, model, busy label (from the group's `BusyAgents`), quota line for CLI runtimes;
  `.presentationDetents([.medium, .large])`; opened from a toolbar button in the group.
- `DashboardViewModel(api:)` — costs (`days: 30`: four KPI tiles — total cost, total tokens, employees, groups — and
  cost by employee), upcoming + recurring tasks, `cancel(_ task:)` (optimistic, rolls back).
- Workforce: teams with their employees (avatar, name, runtime, model); a tap shows details read-only.

- [ ] **Step 1: Failing tests:** `quotaReReadsEveryMinuteWhileOpen` (two reads after one 60 s sleep, none after
      `stop()`); `quotaLineSaysLimitReached`; `cancelRollsBackOnFailure`; `costsAreThirtyDays`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run; build `App`; simulator check light/dark.
- [ ] **Step 5: Commit** `feat(philharmonic): members with quota, the dashboard and the workforce`.

### Task 12: Gate and hand-off

- [ ] **Step 1:** `tuist generate --no-open`; run every scheme's tests (`Models`, `NetworkingKit`, `ChatFeature`,
      `PhilharmonicFeature`, `SettingsFeature`, `HealthFeature`, `App`) and `python3 scripts/l10n.py audit`. Expected: all pass.
- [ ] **Step 2:** Report to the owner (branch, what was checked on the simulator) and ask before merging to `main`.
