# Philharmonic on iPhone — design

Date: 2026-10-23. Owner's ask: "先在 iOS 实现 Philharmonic … 就暂时用你在 mac 端的例子就好" — bring Philharmonic
(multi-agent Groups) to the iPhone app, with the desktop app as the reference. It replaces
`Sources/PhilharmonicFeature/PhilharmonicPlaceholderView.swift`.

## Intent

The desktop is the hub; the phone is the same conversation from the sofa or the street (product principle: iOS is
consistent with the desktop's chat interaction and operates the computer remotely). A group's work runs for minutes
to hours on the computer. What the phone must do well is the part that needs the owner while they are away from the
desk: **follow a group's run live, answer it, and unblock it** — reply to the PM, answer the PM's question, Allow or
Deny a coding agent's step, Stop a round, start a new task in a group.

Success: the owner can leave the desk mid-round and, from the phone, watch the plan tick, read the reports, approve a
"waiting for you" step and send the next instruction, with nothing that the desktop shows for that conversation
missing or contradicted.

## Goals (v1)

1. **Philharmonic workspace in the sidebar** (`AppWorkspace.philharmonic` becomes available). Choosing it lists the
   groups (conversations) under the workspace rows, where Chat lists Recents: title, icon, latest-message preview and
   time, newest first. New group (title + optional emoji icon), rename, delete (confirm) — the desktop's
   conversation-list actions.
2. **Group chat** — the transcript of one group, as the desktop draws it (`group-chat.tsx`,
   `group-message-bubble.tsx`):
   - user bubbles (with attachments), PM messages and employee reports (markdown via MarkdownKit, the speaker's
     avatar + name + role), system rows (errors, `[Scheduled]` triggers).
   - live streaming over the group's SSE stream: a bubble grows while `message_delta` arrives (the delta is the full
     text so far — replace, never append), saved rows replace live bubbles after `message_end` (the desktop's merge
     rule: saved rows win).
   - Actovia-runtime employees' tool cards (`tool_card`) drawn as the desktop draws them: one plain row per call — a
     wrench, the tool's name, a spinner or a check — on the live bubble only (the event carries no call id or
     arguments, and saved rows keep no tool cards, so the desktop's rows go at `message_end` too). *My call, from the
     anti-goals: richer cards would contradict the desktop and need desktop changes first.*
   - CLI employees' **agent cards** (`agent_card` part / event): the steps, the state, and when `blocked`, the prompts
     — permission (Allow / Deny with an optional reason) and questions (the options) — answered with
     `POST /api/v1/agents/sessions/:id/respond`. A `409 AGENT_PROMPT_GONE` means it was answered elsewhere: show the
     settled state, no error toast.
   - the PM's artifact part opens like a chat artifact card.
   - **Decision process** under a PM message: the collapsed line with its counts from the `decision` part; opening it
     fetches `GET …/rounds/:roundId` once and draws the trail (trigger, reports read, thinking, text, tool calls and
     results, usage, error), as `decision-process.tsx` does.
3. **Plan card** pinned at the head of the live round (desktop `plan-card.tsx`): summary, steps with status and
   assignee, updated from `plan_*` events after an initial `GET …/plan`.
4. **Composer**: text + photos (the chat composer's picture flow), Send → `POST …/messages`; Stop while the PM runs →
   `POST …/interrupt`. While the PM has asked a question (`ask_user`), the composer area shows the question and its
   options, answered with `POST …/respond` (free text allowed).
5. **Members** (header button → sheet): each member's avatar, name, role, model, busy activity (from the stream), and
   for CLI members the quota line (`GET /api/v1/agents/quota`, re-read on open and every 60 s while open), using the
   desktop's wording rules (`quotaParts`, window labels).
6. **Dashboard, read-only** (a section in the group list's toolbar menu or a row under the groups — builder's call):
   Costs (the four KPI tiles and the cost-by-employee list for 30 days, `GET /costs`) and Schedule (upcoming and
   recurring tasks, `GET /tasks/upcoming|recurring`, with Cancel → `PATCH /tasks/:id {status:'cancelled'}`).
7. **Workforce, read-only**: teams and their employees (avatar, name, runtime, model). Tapping one shows its details.
   No editing.

## Non-goals

- Editing employees or teams, creating scheduled tasks, choosing a group's project folder — all desktop. The folder
  routes are `desktopOnly` (403 on the LAN) anyway; the phone shows the folder name read-only if the API exposes it,
  and a group with no folder whose coding agent cannot start shows the desktop's own error text.
- Continue in Terminal, Open folder, CLI checks (`desktopOnly`).
- Widgets, Live Activities, push notifications for "waiting for you" (a later step; the phone learns only while the
  app is open).
- Offline cache of groups.

## Anti-goals (a failure even if it works)

- A phone transcript that disagrees with the desktop's (missing reports, duplicated rounds, a different order).
- Approving a step the phone shows as pending after it was answered on the desktop.
- A second visual language: bubbles, cards, markdown, avatars, colours and motion are ChatFeature's and the
  desktop's, not new ones. Tone: Philharmonic's layout is neutral and a group's transcript and composer take the
  colour tone (desktop rule, CLAUDE.md "Colour tone").

## Constraints

- API: `/api/v1/philharmonic/*` and `/api/v1/agents/*` over the paired LAN connection (Bearer device token, pinned
  TLS — `APIClient` / `ServerConnection`). The presence gate does not apply on the LAN listener, so every route above
  is callable from a paired phone; `desktopOnly` routes are not. 423 while the app is locked: the existing unlock
  flow.
- SSE: `GET /api/v1/philharmonic/conversations/:id/sse` — `data: <json>` lines, no event names, no heartbeat; replays
  `pm_started` and a pending `ask_user` on connect. The event union is `PhilharmonicSseEvent`
  (`packages/shared/src/types/philharmonic.ts`). One stream per open group; on a drop it reconnects (see "Also
  decided") and re-reads all of `/messages` and `/plan` (events missed while away are not replayed, and saved rows
  can change after they are saved — an agent card answered or gone stale — so only the re-read after a
  `message_end` uses `?after=`).
- Transcript rows are `ConversationMessageData` (renderer `stores/philharmonic.ts`, not the shared package) with
  `parts` (`attachment`, `artifact`, `decision`, `agent_card`) and `roundId`. Decode leniently; an unknown part or
  event is ignored, never fatal (the chat's `unknown` event pattern).
- Swift 6, iOS 26, iPhone only, Swift Testing; strings through the catalog — reuse the desktop's `philharmonic:`
  keys via `l10n.py add` + `sync-from-desktop` wherever the text is the same, `ios:philharmonic.*` otherwise. The
  vendored catalogs lack `zh-Hans` and `ru`: refresh `Vendor/actovia-locales` from the desktop (now that master has
  them) before syncing.
- Layout follows the app's rules: reading column on wide screens, the docked sidebar on an unfolded Duo, the sidebar
  page on a folded Duo, the drawer on an iPhone; no title header in a group (the chat's immersive rule), toolbar
  buttons where the chat puts them.

## How (decided)

- **Shared UI moves out of ChatFeature where Philharmonic needs it.** Almost all of ChatFeature's views are
  `internal`. The pieces a group transcript needs — the markdown answer body, the user bubble, the
  typing indicator, the photo composer pieces, the error line — become `public` in place (ChatFeature stays the
  owner; PhilharmonicFeature depends on ChatFeature). Moving them to a new kit is not worth it now.
- **SSE is made generic.** `SSEClient.events` and `SSEFrameParsing` take the event type as a generic `Decodable`
  parameter; `ChatSseEvent` keeps working unchanged. A `PhilharmonicSseEvent` enum mirrors the desktop union with an
  `unknown` fallback.
- **One view model per open group** (`GroupChatViewModel`), owning: saved messages, live bubbles, plan, ask-user,
  PM running, busy agents, agent cards; the merge rule as a pure, tested function (`GroupMessageMerge`, the
  desktop's `merge-group-messages.ts` as test vectors).
- Models (`ConversationSummary`, `GroupMessage`, `Plan`, `PlanStep`, `AgentCard`, `AgentPrompt`, `CliQuota`,
  `PmRoundEvent`, `CostSummary`, `ScheduledTask`, `Employee`, `Team`) live in `Models`; a `PhilharmonicAPI` in
  NetworkingKit wraps the routes.

## Left to the builder

- Exact placement of Dashboard and Workforce in the navigation (toolbar menu vs rows), the members sheet's detents,
  how the plan card collapses while scrolling.
- Which ChatFeature views are made public, as long as no view is copied.
- Test split, as long as the merge rule, event decoding (every event type from a fixture), agent-card prompt
  answering and the plan patching are covered.

## Desktop changes first (owner: "按照你建议的来", 2026-10-23)

The phone needs four changes in the desktop repo (`actovia-ai/actovia`), each with tests and its `docs/` /
CLAUDE.md lines, done and merged before the iOS work starts:

1. **Heartbeat on the group stream.** Every Philharmonic SSE stream (`/conversations/:id/sse`, `/sse`,
   `/tasks/:id/sse`) sends an SSE comment line (`: ping`) every 15 s, so a client can tell a quiet round from a
   dead connection. Comments are ignored by `EventSource` and by the iOS frame parser. The phone treats 45 s without
   a byte as a dropped connection: reconnect, then read the group again.
2. **Only new messages.** `GET /conversations/:id/messages?after=<messageId>` returns the rows after that one, in
   order (the whole list without it, as today; an unknown id is a 404 the client answers with a full read). Rows are
   ordered by `createdAt` then `id`, so two rows with one timestamp keep one order. Rows can be edited after they
   are saved (an agent card's parts), so `after` is only for the re-read that follows a `message_end` — the live
   `agent_card` events carry those edits — and every client reads the whole list when it (re)connects. The
   desktop's `GroupChat` follows the same rule.
3. **Photos in a group are saved like Chat's.** The Philharmonic composer's S3 path is broken twice over: it posts to
   `/api/v1/s3-uploader/direct-upload` while the router is mounted at `/api/v1/s3` (a 404 and a warning toast on every
   photo when S3 is set up), and an S3 link would reach the model as if it were image data (`bareImageData` in
   `buildUserContent`). The S3 path is removed: a photo is a data URL, as in Chat, and the messages route fits each
   image with the chat's `withFittedImages()` rules before the row is saved. The phone sends data URLs.
4. **Costs by period.** `GET /costs?days=7|30` (no parameter: all time) filters every figure — totals, by employee,
   by group, daily — to the period; the desktop's 7d / 30d / All switch, which today changes nothing, passes it.

## Also decided

- Employees' tool cards are the desktop's plain rows (see Goals 2), not the chat's rich cards.
- No existing SSE reconnect backoff exists on iOS to reuse: the group stream gets its own (1 s, 2 s, 4 s … capped at
  30 s, reset on the first event), and reconnects at once when the app returns to the foreground.
