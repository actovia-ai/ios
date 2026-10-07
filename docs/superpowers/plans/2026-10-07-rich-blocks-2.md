# Rich Blocks 2 — Illustrated Steps, Entity Panels, Stock Charts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reply can carry three more things both apps draw natively — numbered steps with a thumbnail each (`exodus-steps`), a name that opens a Wikipedia summary panel (`[Marie Curie](entity:Marie_Curie)`), and a TradingView mini chart of a symbol (`exodus-stock`) — through the phase-1 fence mechanism, with nothing sent back and nothing fetched on the model's behalf.

**Architecture:** Phase 1's scanner grows two kinds: `steps` and `stock` join the reserved languages on both sides (desktop `packages/shared/src/types/interactive.ts`, iOS `InteractiveBlock`), so a reply's first `exodus-*` fence is its block whatever its kind, and the existing dispatch (`InteractiveFence` / `InteractiveBlockView`) draws the new ones. Pictures in steps are only thumbnails the run's own search returned (the desktop's `allowedImageUrls` narrowed to thumbnails; the phone's `SearchGallery.trustedURLs` likewise). An `entity:` link is a new link action in both Markdown renderers (react-markdown's `urlTransform` + the `a` renderer; MarkdownKit's `MarkdownLinkPolicy` + router), opening a popover / sheet fed by one new desktop route, `GET /api/v1/entity/:title`, which reads Wikipedia's REST summary through `fetchPublicHttps()` and caches it a day. The chart is TradingView's own embed URL (verified 2026-10-07 to render alone) in a sandboxed iframe on the desktop and a rule-listed `WKWebView` on the phone — no TradingView script ever runs in our documents. Copy and read-aloud get the block's words instead of its JSON.

**Tech Stack:** Desktop: TypeScript, React 19, react-markdown 10 (`defaultUrlTransform`), zod 4, Hono, `@tanstack/react-query`, shadcn `Popover`, i18next, vitest (+ happy-dom), bun. iOS: Swift 6, SwiftUI (iOS 27), WebKit (`WKWebView`, `WKContentRuleList`), swift-markdown (via MarkdownKit), Foundation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-07-rich-blocks-phase-2-design.md` (exodus-ios) — §2 the wire (steps, `entity:` links and the route, stock), §3 the prompt, §4 renderers, §5 testing, §6 the owner's four decisions (all made 2026-10-07). It builds on `docs/superpowers/specs/2026-10-06-interactive-blocks-design.md` and the phase-1 plan `docs/superpowers/plans/2026-10-06-interactive-blocks-1.md`, whose tooling notes (tuist, xcodebuild, the catalog script) still hold.

## Decisions (spec gaps, resolved here)

1. **One block per reply, of any kind.** `steps` and `stock` are kinds of the phase-1 block: the first `exodus-*` fence of a turn that validates is its block (`findInteractiveBlock` / `InteractiveFence.first`, unchanged), a second fence of any kind is code. So a reply cannot hold both a questionnaire and a chart — the spec's "one block per message stays the rule for every `exodus-*` fence" (§6 Q4).
2. **Steps pictures are thumbnails, exactly.** A step's `image` is drawn only when it is, byte for byte after URL normalisation, one of the run's search *thumbnails*: a web result's `thumbnail` (Brave's `thumbnail.src`) or a media result's `thumbnailUrl`. A media result's original `url` — which phase 1's `allowedImageUrls` / `trustedURLs` admit for Markdown images — is **not** admitted here (owner: "原图可能触发原站盗链"). A step whose picture is anything else is drawn without one. Admitted pictures load on sight (they are the run's own thumbnails, as the search gallery loads them), through `RemoteImage` on the desktop and `SearchMediaLoader` on the phone.
3. **The stock range set is TradingView's:** `1D 1M 3M 12M 60M ALL`, default `1D` (§6 Q2); the model widens it only when the question names a span. Spelled in the schema, the prompt and the Swift enum alike.
4. **Chart colours are TradingView's own.** Only `colorTheme` (light/dark) and `isTransparent: true` are set. The spec's "the tone's accent as `trendLineColor`" is dropped: the renderer's tone tokens are `oklch()` CSS variables the widget cannot read, and a wrong colour is worse than theirs.
5. **The chart's URL is the embed URL, built by us** (spec §2.3 as amended): `https://www.tradingview-widget.com/embed-widget/mini-symbol-overview/?locale=<tv locale>&symbol=<EXCHANGE:TICKER>#<encodeURIComponent(JSON settings)>`. The desktop's `index.html` CSP already admits `frame-src https://*.tradingview-widget.com` (and `https://*.tradingview.com`): **no CSP change**. "Open on TradingView" goes to `https://www.tradingview.com/symbols/<EXCHANGE>-<TICKER>/`.
6. **The entity title rule** (both scanners, the same vectors): `href` starts with `entity:`; the rest is percent-decoded; the title is 1–200 UTF-16 units of `[\p{L}\p{N}_().,'\-:]` and holds at least one letter or digit (so `..` and `.` are not titles). Anything else is plain text — never a link, never a request.
7. **The route** `GET /api/v1/entity/:title?lang=xx`: `lang` is `[a-z]{2,3}` (400 otherwise, as an invalid title is); the article is looked up in `lang` and, when that is a 404 and `lang` is not `en`, in `en`; a title neither has is a **200** `{ title, extract: null, description: null, thumbnail: null, url: null, lang }` — "nothing found" is an answer. The summary is cached in memory for 24 h, at most 500 entries, oldest out. Any other upstream failure is `503 SERVICE_UNAVAILABLE`, logged without the URL. `fetchPublicHttps` gains an optional `headers` so the request carries the `User-Agent` Wikimedia's API policy asks for.
8. **Which Wikipedia:** the client maps its locale to the language subdomain — the first subtag lowercased when it is 2–3 letters (`zh-Hant-TW` → `zh`, `pt-BR` → `pt`, `en` → `en`), else `en` (`wikipediaLang` / `EntityLoader.wikipediaLang`). The route does not guess the language; it is told.
9. **Where the panel fetches:** desktop `useQuery({ queryKey: ['entity', lang, title], staleTime: 24 h })` over `fetcher<EntitySummary>` in a new `services/entity-service.ts`; iOS an `EntityLoader` (`apiClient.get`) with an in-memory dictionary, injected through the environment like `placePhotoLoader`. Both fetch when the panel opens, not when the link is drawn.
10. **`entity:` on the phone goes through the link policy, not around it.** `MarkdownLinkAction` gains `.entity(String)`; `MarkdownLinkPolicy.action` returns it for a valid title; `MarkdownAttributedText` keeps the `.link` attribute for `.entity` (today only `.open` keeps it, so the tap could never reach a handler); `MarkdownTextTap.offersMenu` stays `.open`-only (no system menu for an entity); the router gains `onEntityTap`, fed from a new environment entry `markdownEntityTap: MarkdownEntityAction?` the chat screen sets. A host that sets none (the gallery, a sheet) gets a handled tap that does nothing.
11. **`entity:` on the desktop** needs react-markdown's `urlTransform`: `defaultUrlTransform` empties any scheme but http(s)/mailto/irc/xmpp, so `markdownUrlTransform` lets a valid `entity:` href through and hands everything else to the default. The `a` renderer draws an `EntityLink` (a Popover trigger button, never `<a href="entity:…">`). A confirmation's `details` keep the default transform: an entity link there is plain text.
12. **Plain text for Copy / read-aloud** exists only for the two new kinds (phase 1 has none for ask/confirm and this plan does not add one): `withBlockText(markdown)` / `InteractivePlainText.replacingBlock(in:)` swap a reply's steps fence for a numbered list and a stock fence for `symbol — note` (or the symbol alone). Wired into the desktop's `message-action.tsx` (copy) and `audio-player.tsx` (speech), the phone's `CopiedAnswer.text(of:)` and `SpeechText.prose`.
13. **`AssistantTurnView.asks`** (iOS) counts only the answerable kinds: a turn with a chart must not redraw when a turn starts or ends. `InteractiveBlock.Kind.isAnswerable` is `ask` / `confirm`.
14. **Gallery:** `-MessageGallerySection steps|entity|stock` name three new runs appended to `interactiveRuns`; `namedSection` reads the index from one list of names (`["ask", "confirm", "answered", "steps", "entity", "stock"]`) and `MessageGalleryInteractiveTests` is rewritten to that list. The entity run's reply holds two `entity:` links and a web-search tool result with `thumbnail` fields, so the steps run (the same search) has pictures to show.
15. **Prompt budget:** the section may reach 70 lines (was 40) and `getSystemPrompt({})` 13,500 characters (was 11,500; measured 11,185 before this plan).
16. **Privacy text:** the desktop's Lock & Privacy section (`lock-privacy.tsx`) gets one always-visible sentence, `lock:privacy.thirdParty`. The phone has no privacy page; its disclosure is the chart card's footer, "Chart by TradingView", which every chart shows.
17. **Test IDs** (desktop): `TEST_IDS.chat.richBlocks.{steps, step, stepImage, stock, stockFrame, stockFallback, entityLink, entityPanel}` — each applied in `src/renderer` and referenced by a test (`test-ids.linkage.test.ts` enforces it).
18. **Strings:** desktop `chat:richBlocks.*` (8 keys, all ten locales, inserted textually by a script as phase 1 did); iOS `ios:chat.block.*` (8 keys, ten languages, `add_keys.py`). Translations are written in the plan.
19. **Trees:** both repos were clean at HEAD on 2026-10-07 23:30 (iOS `374285f`, desktop `d363353b`) but for the untracked `.playwright-mcp/`. If `git status` shows the owner's edits in a file a task touches, stop and apply the phase-1 dual-edit procedure (`/tmp/blocks/dual_edit.py`, plan 2026-10-06 "Shared tooling") rather than committing their hunks.
20. **Streaming:** nothing new — a fence still open is code until it closes (phase 1); the chart's iframe mounts only once its block is closed and valid.

## Global Constraints

- Two repos, both on branch `maintenance`, **never push**: iOS `/Users/yanceyleo/Code/exodus/exodus-ios`, desktop `/Users/yanceyleo/Code/exodus/exodus`.
- **Commits by explicit path only:** `git add <the files your task names> && git commit -F msg.txt` from that repo's root; never `git add -A`, `git add .`, `git commit -a`, `git stash`, `git reset`, `git restore`, `git checkout -- <file>`, never `--no-verify`. The desktop's pre-commit hook runs `lint-staged` (oxlint + oxfmt on staged `*.{ts,tsx}`, oxfmt on `*.json`) → `bun run typecheck` → `bun run i18n:check`; let it. After each commit, `git show --stat HEAD` must list only your files. Commit messages: one sentence in the repo's voice saying what and why, a blank line, then `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Run `git status --porcelain` at the start of every task. Only `?? .playwright-mcp/` is expected. Anything else in a file you must edit → Decision 19.
- **The vectors are the contract:** the schema, finder, entity-title and plain-text vectors in Tasks 1 and 6 are the same text in both repos. A change to the wire changes both files and both implementations.
- Desktop: `bunx oxfmt <dir>` and `bunx oxlint <files>` before committing; typecheck with `bun run typecheck:shared`, `bun run typecheck:node`, `bun run typecheck:web` (each that covers your files); tests with `bunx vitest run <path>`. New `chat`/`lock` keys go into all ten locales (`en, de, es, fr, it, ja, ko, pt-BR, zh-Hant-HK, zh-Hant-TW`) or `i18n:check` fails; insert them textually with the task's script, never by rewriting a JSON file. Test IDs: never a raw `data-testid` string; add to `TEST_IDS` and reference in a test.
- iOS: Swift 6 language mode, iOS 27.0, Tuist with buildable folders. **After creating any new file under `Sources/` or `Tests/`, run** `PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH tuist generate --no-open` (the toolchain prefix keeps `~/.swiftly` out of the manifest build). Simulator `992425B7-F06B-4CE5-9288-95C71C2F1D44`, `-derivedDataPath /tmp/rich2-dd`. Tests: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme <ChatFeature|MarkdownKit> -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd [-only-testing:<ChatFeatureTests|MarkdownKitTests>/<TypeName>] 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"` — a wrong `-only-testing` name still prints SUCCEEDED, so confirm `Test run with N tests` with N > 0. App build: `xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`.
- iOS strings: keys `ios:chat.block.<element>`, ten languages (`en, de, es, fr, it, ja, ko, pt-BR, zh-HK, zh-Hant`), inserted textually with the task's `add_keys.py`; never `scripts/l10n.py add|fill|save`. `python3 scripts/l10n.py audit 2>&1 | tail -1` prints `0 error(s)` at the end of every iOS task. Views use the key literal (`Text("ios:chat.block.chartBy")`); code uses `String(localized:defaultValue:comment:)` with `defaultValue` equal to the catalog's English. Never a ternary of two string literals in a text initializer; model-written text through `Text(verbatim:)`. No CJK in `Sources/` (tests may hold CJK).
- No new packages in either repo. iOS: native frameworks only (WebKit is one). Dynamic Type through text styles; Reduce Motion: no animation of ours in the new views.
- Match the surrounding code: doc comments short and plain, saying *why*; Swift Testing (`@Test`, `#expect`, `#require`); vitest `describe`/`it`.
- Do not dispatch subagents from inside a task.

## Review Focus

- A step whose `image` is a search result's *original* URL, or any URL the run's search did not return as a thumbnail: the step is drawn without a picture and nothing is fetched. Tests: `rich-blocks.test.ts › steps › a picture that is not one of the run's thumbnails is not drawn` (Task 4); `StepsPicturesTests.originalsAreNotPictures` (Task 8).
- An `entity:` link with a hostile or odd target — `entity:../x`, a 201-unit title, `entity:%2F`, `entity:..`, a space, an empty one: plain text, no popover or sheet, no request (a title that merely looks like a scheme, `javascript:alert(1)`, is a harmless path segment and stays a title). Tests: `entity-link.test.ts` vectors (Task 1), `MarkdownLinkPolicyTests.entity` (Task 7).
- A stock symbol the widget would not take — lowercase, a space, a slash, no exchange, 41 units, a range of `5D`: the fence stays a code block, never an iframe. Tests: `STOCK_CASES` (Task 1), `stockCases` (Task 6).
- The chart loads only its embed URL; a tap inside opens nothing inside the app; offline the card falls back to the symbol, the note and the link. Tests: `rich-blocks.test.ts › stock › the iframe's src is the embed URL and it is sandboxed` and `› falls back when the frame fails` (Task 4); `StockChartTests.allowsNavigation` and `.contentRulesCompile` (Task 8).
- Copy or read aloud of a reply that holds a steps or stock block gives words, not JSON; a reply with no such block is untouched. Tests: `interactive-plain-text.test.ts` (Task 1), `InteractivePlainTextTests` (Task 6), `rich-blocks.test.ts › copy and read aloud take the block's words` (Task 5).

---

## File Structure

**Desktop (`/Users/yanceyleo/Code/exodus/exodus`)**
- Modify `packages/shared/src/types/interactive.ts` — kinds `steps`/`stock`, `stepSchema`, `stepsBlockSchema`, `STOCK_RANGES`, `DEFAULT_STOCK_RANGE`, `stockBlockSchema`, the union, `interactiveKind`, `parseInteractiveBlock`.
- Create `packages/shared/src/utils/entity-link.ts` — `ENTITY_SCHEME`, `ENTITY_TITLE_MAX`, `isWikipediaTitle`, `entityTitle`, `isWikipediaLang`, `wikipediaLang`.
- Create `packages/shared/src/types/entity.ts` — `EntitySummary`.
- Create `packages/shared/src/utils/stock-chart.ts` — `STOCK_CHART_HEIGHT`, `tradingViewLocale`, `tradingViewEmbedUrl`, `tradingViewSymbolPageUrl`.
- Create `packages/shared/src/utils/interactive-plain-text.ts` — `blockText`, `withBlockText`.
- Tests: extend `tests/unit/shared/types/interactive.test.ts`; create `tests/unit/shared/utils/entity-link.test.ts`, `stock-chart.test.ts`, `interactive-plain-text.test.ts`.
- Modify `src/main/lib/net/safe-fetch.ts` (+ its test) — `headers`.
- Create `src/main/lib/server/routes/entity.ts` (+ `tests/unit/main/lib/server/routes/entity.test.ts`); modify `src/main/lib/server/app.ts`; one paragraph in `docs/chat-api.md`.
- Modify `src/main/lib/ai/interactive-blocks-prompt.ts` (+ its test, `tests/unit/main/lib/ai/prompts.test.ts`).
- Modify `packages/shared/src/constants/test-ids.ts` — `chat.richBlocks`.
- Modify `packages/shared/src/i18n/locales/<10>/chat.json` — `richBlocks.*`; `<10>/lock.json` — `privacy.thirdParty`.
- Create `src/renderer/components/chat/interactive/steps-block.tsx`, `stock-block.tsx`, `entity-link.tsx`; `src/renderer/services/entity-service.ts`.
- Modify `src/renderer/components/markdown/remote-image.tsx` — `SearchThumbnailUrlsContext`, `searchThumbnailUrls`; `markdown.tsx` — the context, `urlTransform`, the `a` renderer; `src/renderer/components/chat/interactive/interactive-fence.tsx` — the dispatch.
- Modify `src/renderer/components/chat/message-action.tsx`, `audio-player.tsx` — `withBlockText`; `settings/settings-form/lock-privacy.tsx` — the sentence; `docs/security-hardening.md` — the TradingView note.
- Create `tests/unit/renderer/components/chat/rich-blocks.test.ts`.

**iOS (`/Users/yanceyleo/Code/exodus/exodus-ios`)**
- Modify `Sources/ChatFeature/Interactive/InteractiveBlock.swift` — `Kind.steps/.stock`, `Steps`, `Stock`, `isValid`, `Kind.isAnswerable`.
- Create `Sources/ChatFeature/Interactive/InteractivePlainText.swift`, `StockChart.swift`, `StockBlockView.swift`, `StepsBlockView.swift`, `EntitySummary.swift`, `EntitySheet.swift`.
- Modify `Sources/ChatFeature/Interactive/InteractiveBlockView.swift` — the switch, `fencedBlocks(… pictures:)`; `Sources/ChatFeature/AssistantTurnView.swift` — `asks`, the pictures; `Sources/ChatFeature/CopiedAnswer.swift`, `ReadAloud.swift` — the plain text; `Sources/ChatFeature/ChatDetailView.swift` — the entity action and sheet.
- Modify `Sources/MarkdownKit/MarkdownLinks.swift` — `.entity`, `MarkdownEntityLink`, `onEntityTap`; `MarkdownStyledText.swift` — `markdownEntityTap`, `MarkdownEntityAction`; `MarkdownView.swift`, `MarkdownDocumentView.swift` — the wiring; `MarkdownAttributedText.swift` — the kept link.
- Modify `Sources/ChatFeature/MessageGalleryInteractive.swift` — three runs, `namedSection`; `Resources/App/Localizable.xcstrings` — 8 keys.
- Tests: extend `Tests/ChatFeatureTests/InteractiveBlockTests.swift`, `MessageGalleryInteractiveTests.swift`, `Tests/MarkdownKitTests/MarkdownSafetyTests.swift`; create `Tests/ChatFeatureTests/InteractivePlainTextTests.swift`, `StockChartTests.swift`, `StepsPicturesTests.swift`, `EntitySummaryTests.swift`.
- Create `docs/chat-rich-blocks-device-checklist.md`.

---

### Task 1: Desktop shared — the two kinds, the entity title, the chart's URLs and the block's words

**Files:**
- Modify: `packages/shared/src/types/interactive.ts`
- Create: `packages/shared/src/utils/entity-link.ts`, `packages/shared/src/types/entity.ts`, `packages/shared/src/utils/stock-chart.ts`, `packages/shared/src/utils/interactive-plain-text.ts`
- Test: `tests/unit/shared/types/interactive.test.ts` (extend), `tests/unit/shared/utils/entity-link.test.ts`, `tests/unit/shared/utils/stock-chart.test.ts`, `tests/unit/shared/utils/interactive-plain-text.test.ts`

**Interfaces:**
- Consumes: phase 1's `text`, `label`, `oneLine`, `findInteractiveBlock`, `fenceRun`, `blank`, `trimTrailingBlanks` in `interactive.ts`.
- Produces: `INTERACTIVE_LANGUAGES.steps = 'exodus-steps'`, `.stock = 'exodus-stock'`; `StepsBlock { title?: string | null; steps: Array<{ text: string; image?: string | null }> }`; `StockBlock { symbol: string; range?: StockRange | null; note?: string | null }`; `STOCK_RANGES`, `StockRange`, `DEFAULT_STOCK_RANGE`; `InteractiveFence` with `kind: 'steps' | 'stock'` members; `entityTitle(href: string | null | undefined): string | null`; `isWikipediaTitle(title: string): boolean`; `isWikipediaLang(lang: string): boolean`; `wikipediaLang(locale: string): string`; `EntitySummary`; `tradingViewEmbedUrl({ symbol, range, theme, locale }): string`; `tradingViewSymbolPageUrl(symbol): string`; `tradingViewLocale(locale): string`; `STOCK_CHART_HEIGHT = 220`; `blockText(fence: InteractiveFence): string | null`; `withBlockText(markdown: string): string`.

- [ ] **Step 1: Add the schema and finder vectors (failing)**

In `tests/unit/shared/types/interactive.test.ts`, after `CONFIRM_CASES` (line ~130) add:

```ts
const STEPS_SOURCE =
  '{"title":"Replacing the strings","steps":[{"text":"Loosen the old string from the tuning peg.","image":"https://imgs.search.brave.com/peg.jpg"},{"text":"Thread the new one through the bridge."},{"text":"Tune up slowly, stretching the string as you go.","image":"https://imgs.search.brave.com/tune.jpg"}]}'
const STOCK_SOURCE =
  '{"symbol":"NASDAQ:AAPL","range":"1D","note":"Up 12% since the earnings call; the gap at Oct 2 is the split."}'

const step = (i: number, extra: Record<string, unknown> = {}) => ({
  text: `Step ${i}`,
  ...extra
})
const steps = (extra: Record<string, unknown> = {}) =>
  JSON.stringify({ steps: [step(1), step(2)], ...extra })
const stock = (extra: Record<string, unknown> = {}) =>
  JSON.stringify({ symbol: 'NASDAQ:AAPL', ...extra })

const STEPS_CASES: Array<[string, string, boolean]> = [
  ["the spec's example", STEPS_SOURCE, true],
  ['two steps, no title', steps(), true],
  ['one step', steps({ steps: [step(1)] }), false],
  ['twelve steps', steps({ steps: range(12).map((i) => step(i)) }), true],
  ['thirteen steps', steps({ steps: range(13).map((i) => step(i)) }), false],
  ['a 300-character step', steps({ steps: [step(1, { text: 'x'.repeat(300) }), step(2)] }), true],
  ['a 301-character step', steps({ steps: [step(1, { text: 'x'.repeat(301) }), step(2)] }), false],
  ['150 emoji (300 UTF-16 units)', steps({ steps: [step(1, { text: '😀'.repeat(150) }), step(2)] }), true],
  ['151 emoji (302 UTF-16 units)', steps({ steps: [step(1, { text: '😀'.repeat(151) }), step(2)] }), false],
  ['a step on two lines', steps({ steps: [step(1, { text: 'a\nb' }), step(2)] }), false],
  ['an empty step', steps({ steps: [step(1, { text: '' }), step(2)] }), false],
  ['an https picture', steps({ steps: [step(1, { image: 'https://imgs.search.brave.com/x.jpg' }), step(2)] }), true],
  ['an http picture', steps({ steps: [step(1, { image: 'http://example.com/x.jpg' }), step(2)] }), false],
  ['a data: picture', steps({ steps: [step(1, { image: 'data:image/png;base64,AAAA' }), step(2)] }), false],
  ['a picture URL with a space', steps({ steps: [step(1, { image: 'https://example.com/a b.jpg' }), step(2)] }), false],
  ['a 2048-character picture URL', steps({ steps: [step(1, { image: 'https://e.co/' + 'a'.repeat(2035) }), step(2)] }), true],
  ['a 2049-character picture URL', steps({ steps: [step(1, { image: 'https://e.co/' + 'a'.repeat(2036) }), step(2)] }), false],
  ['a 200-character title', steps({ title: 't'.repeat(200) }), true],
  ['a 201-character title', steps({ title: 't'.repeat(201) }), false],
  ['a title on two lines', steps({ title: 'a\nb' }), false],
  ['an empty title (none)', steps({ title: '' }), true],
  ['nulls for what is optional', steps({ title: null, steps: [step(1, { image: null }), step(2)] }), true],
  ['keys it does not know', steps({ colour: 'red' }), true],
  ['not JSON', '{"steps":', false],
  ['an array', '[]', false]
]

const STOCK_CASES: Array<[string, string, boolean]> = [
  ["the spec's example", STOCK_SOURCE, true],
  ['a symbol alone', stock(), true],
  ...['1D', '1M', '3M', '12M', '60M', 'ALL'].map(
    (r): [string, string, boolean] => [`the range ${r}`, stock({ range: r }), true]
  ),
  ['a range it does not know (5D)', stock({ range: '5D' }), false],
  ['a lowercase range', stock({ range: '1d' }), false],
  ['a lowercase symbol', stock({ symbol: 'nasdaq:aapl' }), false],
  ['a symbol without an exchange', stock({ symbol: 'AAPL' }), false],
  ['a symbol with a space', stock({ symbol: 'NASDAQ: AAPL' }), false],
  ['a symbol with a slash', stock({ symbol: 'NASDAQ:AAPL/../X' }), false],
  ['a symbol with a dot and a dash', stock({ symbol: 'TSE:7203.T-A' }), true],
  ['a 40-character symbol', stock({ symbol: 'X:' + 'A'.repeat(38) }), true],
  ['a 41-character symbol', stock({ symbol: 'X:' + 'A'.repeat(39) }), false],
  ['a 300-character note', stock({ note: 'n'.repeat(300) }), true],
  ['a 301-character note', stock({ note: 'n'.repeat(301) }), false],
  ['a note on two lines', stock({ note: 'a\nb' }), true],
  ['nulls for what is optional', stock({ range: null, note: null }), true],
  ['no symbol', JSON.stringify({ note: 'x' }), false],
  ['an array', '[]', false]
]
```

In the `describe('parseInteractiveBlock', …)` block add, after the confirm `it.each`:

```ts
  it.each(STEPS_CASES)('exodus-steps: %s → valid: %s', (_name, source, valid) => {
    expect(parseInteractiveBlock('steps', source) !== null).toBe(valid)
  })
  it.each(STOCK_CASES)('exodus-stock: %s → valid: %s', (_name, source, valid) => {
    expect(parseInteractiveBlock('stock', source) !== null).toBe(valid)
  })
  it('keeps the parsed blocks', () => {
    const steps = parseInteractiveBlock('steps', STEPS_SOURCE)
    expect(steps?.kind).toBe('steps')
    if (steps?.kind === 'steps') {
      expect(steps.block.steps).toHaveLength(3)
      expect(steps.block.steps[1].image).toBeUndefined()
    }
    const stock = parseInteractiveBlock('stock', STOCK_SOURCE)
    expect(stock?.kind).toBe('stock')
    if (stock?.kind === 'stock') expect(stock.block.range).toBe('1D')
  })
```

Change `FIND_CASES`'s type to `Array<[string, string, 'ask' | 'confirm' | 'steps' | 'stock' | null]>` and append:

```ts
  ['a steps block', `Here:\n\n\`\`\`exodus-steps\n${STEPS_SOURCE}\n\`\`\``, 'steps'],
  ['a stock block', `\`\`\`exodus-stock\n${STOCK_SOURCE}\n\`\`\``, 'stock'],
  [
    'a stock block after a questionnaire: the questionnaire',
    `\`\`\`exodus-ask\n${ASK_SOURCE}\n\`\`\`\n\n\`\`\`exodus-stock\n${STOCK_SOURCE}\n\`\`\``,
    'ask'
  ],
  [
    'a stock block that does not validate, then steps: none',
    `\`\`\`exodus-stock\n{"symbol":"aapl"}\n\`\`\`\n\n\`\`\`exodus-steps\n${STEPS_SOURCE}\n\`\`\``,
    null
  ]
```

- [ ] **Step 2: Run the vectors to see them fail**

Run: `cd /Users/yanceyleo/Code/exodus/exodus && bunx vitest run tests/unit/shared/types/interactive.test.ts`
Expected: FAIL — `parseInteractiveBlock('steps', …)` is a type error / returns null (`steps` is not an `InteractiveKind`).

- [ ] **Step 3: Grow `interactive.ts`**

Replace `INTERACTIVE_LANGUAGES`:

```ts
export const INTERACTIVE_LANGUAGES = {
  ask: 'exodus-ask',
  confirm: 'exodus-confirm',
  steps: 'exodus-steps',
  stock: 'exodus-stock'
} as const
```

After `confirmBlockSchema` add:

```ts
/**
 * An `https:` URL of at most 2048 units, with no whitespace: a step's
 * picture, as the run's search returned it. Whether the run did return it is
 * the renderer's check, not the schema's.
 */
const httpsUrl = text(1, 2048).refine((s) => /^https:\/\/\S+$/u.test(s), {
  message: 'Expected an https: URL'
})

export const stepSchema = z.object({
  text: oneLine(1, 300),
  /** A thumbnail among the run's web-search results; the client drops any other URL. */
  image: httpsUrl.nullish()
})

export const stepsBlockSchema = z.object({
  /** Optional; an empty one is none. */
  title: oneLine(0, 200).nullish(),
  steps: z.array(stepSchema).min(2).max(12)
})

/** TradingView's Mini Chart `dateRange` set, as it spells it — nothing in between. */
export const STOCK_RANGES = ['1D', '1M', '3M', '12M', '60M', 'ALL'] as const
export type StockRange = (typeof STOCK_RANGES)[number]
/** The finest the widget offers (owner, 2026-10-07). */
export const DEFAULT_STOCK_RANGE: StockRange = '1D'

export const stockBlockSchema = z.object({
  /** TradingView's `EXCHANGE:TICKER`. */
  symbol: text(1, 40).refine((s) => /^[A-Z0-9_.]+:[A-Z0-9_.-]+$/u.test(s), {
    message: 'Expected EXCHANGE:TICKER'
  }),
  range: z.enum(STOCK_RANGES).nullish(),
  /** The model's reading, under the chart. */
  note: label(300)
})

export type Step = z.infer<typeof stepSchema>
export type StepsBlock = z.infer<typeof stepsBlockSchema>
export type StockBlock = z.infer<typeof stockBlockSchema>
```

Replace the union and the two functions:

```ts
/** A reply's block, and the text of its fence — how its code block is known. */
export type InteractiveFence =
  | { kind: 'ask'; block: AskBlock; source: string }
  | { kind: 'confirm'; block: ConfirmBlock; source: string }
  | { kind: 'steps'; block: StepsBlock; source: string }
  | { kind: 'stock'; block: StockBlock; source: string }

/** The block a fence's info string names, or null. */
export function interactiveKind(language: string): InteractiveKind | null {
  for (const [kind, name] of Object.entries(INTERACTIVE_LANGUAGES)) {
    if (language === name) return kind as InteractiveKind
  }
  return null
}

/** A fence's body as its block, or null when it is not one JSON object within the limits. */
export function parseInteractiveBlock(
  kind: InteractiveKind,
  source: string
): InteractiveFence | null {
  let value: unknown
  try {
    value = JSON.parse(source)
  } catch {
    return null
  }
  switch (kind) {
    case 'ask': {
      const parsed = askBlockSchema.safeParse(value)
      return parsed.success ? { kind, block: parsed.data, source } : null
    }
    case 'confirm': {
      const parsed = confirmBlockSchema.safeParse(value)
      return parsed.success ? { kind, block: parsed.data, source } : null
    }
    case 'steps': {
      const parsed = stepsBlockSchema.safeParse(value)
      return parsed.success ? { kind, block: parsed.data, source } : null
    }
    case 'stock': {
      const parsed = stockBlockSchema.safeParse(value)
      return parsed.success ? { kind, block: parsed.data, source } : null
    }
  }
}
```

Update the file's header comment's first line to: `// The blocks a reply can carry (exodus-ios specs 2026-10-06 and 2026-10-07): a fenced block whose info string names it and whose body is one JSON object — a questionnaire, a confirmation, illustrated steps or a stock chart.` (keep the rest).

- [ ] **Step 4: Run the vectors**

Run: `bunx vitest run tests/unit/shared/types/interactive.test.ts`
Expected: PASS (all `ASK_CASES`, `CONFIRM_CASES`, `STEPS_CASES`, `STOCK_CASES`, `FIND_CASES`).

- [ ] **Step 5: Write the entity-link tests (failing)**

Create `tests/unit/shared/utils/entity-link.test.ts`:

```ts
// An `entity:` link names a Wikipedia article; anything a reply could write
// that is not one is plain text. exodus-ios's MarkdownLinkPolicyTests.entity
// holds the same vectors — keep them in step.
import {
  entityTitle,
  isWikipediaLang,
  isWikipediaTitle,
  wikipediaLang
} from '@exodus/shared/utils/entity-link'
import { describe, expect, it } from 'vitest'

const ENTITY_CASES: Array<[string, string, string | null]> = [
  ['a plain title', 'entity:Marie_Curie', 'Marie_Curie'],
  ['a title with punctuation Wikipedia uses', "entity:Dvořák's_Symphony_No._9_(From_the_New_World)", "Dvořák's_Symphony_No._9_(From_the_New_World)"],
  ['a CJK title', 'entity:東京', '東京'],
  ['a percent-encoded title', 'entity:%E6%9D%B1%E4%BA%AC', '東京'],
  ['a colon inside (a namespace)', 'entity:Category:Physicists', 'Category:Physicists'],
  ['a 200-unit title', 'entity:' + 'a'.repeat(200), 'a'.repeat(200)],
  ['a 201-unit title', 'entity:' + 'a'.repeat(201), null],
  ['100 emoji (200 units) are letters? no — not in the set', 'entity:' + '😀'.repeat(100), null],
  ['an empty title', 'entity:', null],
  ['a slash', 'entity:Marie/Curie', null],
  ['a dot-dot', 'entity:..', null],
  ['a single dot', 'entity:.', null],
  ['only punctuation', "entity:_()'", null],
  ['an encoded slash', 'entity:Marie%2FCurie', null],
  ['a bad percent escape', 'entity:%E6%9D', null],
  ['a query', 'entity:Marie_Curie?x=1', null],
  ['a hash', 'entity:Marie_Curie#History', null],
  ['a space', 'entity:Marie Curie', null],
  // `entity:javascript:alert(1)` IS a title by the alphabet (as `Category:Physicists` is) and harmless: a title
  // is only ever a percent-encoded path segment of the Wikipedia URL, never navigated — so it is not a vector.
  ['not an entity link', 'https://en.wikipedia.org/wiki/Marie_Curie', null],
  ['the scheme in capitals', 'ENTITY:Marie_Curie', null],
  ['nothing', '', null]
]

describe('entityTitle', () => {
  it.each(ENTITY_CASES)('%s → %s', (_name, href, title) => {
    expect(entityTitle(href)).toBe(title)
  })
  it('is null for no href', () => {
    expect(entityTitle(null)).toBeNull()
    expect(entityTitle(undefined)).toBeNull()
  })
  it('isWikipediaTitle is the same rule on a bare title', () => {
    expect(isWikipediaTitle('Marie_Curie')).toBe(true)
    expect(isWikipediaTitle('..')).toBe(false)
    expect(isWikipediaTitle('a/b')).toBe(false)
  })
})

describe('wikipediaLang', () => {
  it.each([
    ['en', 'en'],
    ['zh-Hant-TW', 'zh'],
    ['zh-Hant-HK', 'zh'],
    ['pt-BR', 'pt'],
    ['ja', 'ja'],
    ['ko', 'ko'],
    ['DE', 'de'],
    ['', 'en'],
    ['x', 'en'],
    ['toolong-x', 'en']
  ])('%s → %s', (locale, lang) => {
    expect(wikipediaLang(locale)).toBe(lang)
  })
  it('isWikipediaLang accepts two or three lowercase letters', () => {
    expect(isWikipediaLang('en')).toBe(true)
    expect(isWikipediaLang('yue')).toBe(true)
    expect(isWikipediaLang('EN')).toBe(false)
    expect(isWikipediaLang('e')).toBe(false)
    expect(isWikipediaLang('en.wikipedia.org')).toBe(false)
  })
})
```

(The emoji case's name is deliberate: an emoji is neither `\p{L}` nor `\p{N}`, so it is not a title.)

- [ ] **Step 6: Run it to see it fail**

Run: `bunx vitest run tests/unit/shared/utils/entity-link.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 7: Write `entity-link.ts` and `entity.ts`**

Create `packages/shared/src/utils/entity-link.ts`:

```ts
// `[Marie Curie](entity:Marie_Curie)` — a link in a reply that opens a small
// panel about the person, place or thing (exodus-ios spec 2026-10-07 §2.2).
// The target is a Wikipedia article title, and only something that could be
// one is a link; anything else is plain text. exodus-ios's
// `MarkdownEntityLink` has the same rule, held to the same vectors.

export const ENTITY_SCHEME = 'entity:'
export const ENTITY_TITLE_MAX = 200

/** Letters, digits and the punctuation Wikipedia titles carry; never `/`, `?`, `#`, a space or a control. */
const TITLE = /^[\p{L}\p{N}_().,'\-:]+$/u
const HAS_WORD = /[\p{L}\p{N}]/u

/**
 * Whether `title` could be a Wikipedia article's: 1–200 UTF-16 units of the
 * title alphabet, with at least one letter or digit (so `.` and `..` are
 * not titles and the route's URL cannot climb).
 */
export function isWikipediaTitle(title: string): boolean {
  return (
    title.length > 0 &&
    title.length <= ENTITY_TITLE_MAX &&
    TITLE.test(title) &&
    HAS_WORD.test(title)
  )
}

/**
 * The article title an `entity:` href names, percent-escapes decoded (a
 * Markdown tool may encode `東京`), or null when the href is not such a link
 * or its title is not one.
 */
export function entityTitle(href: string | null | undefined): string | null {
  if (!href || !href.startsWith(ENTITY_SCHEME)) return null
  let title: string
  try {
    title = decodeURIComponent(href.slice(ENTITY_SCHEME.length))
  } catch {
    return null
  }
  return isWikipediaTitle(title) ? title : null
}

/** A Wikipedia language subdomain: two or three lowercase letters. */
export function isWikipediaLang(lang: string): boolean {
  return /^[a-z]{2,3}$/u.test(lang)
}

/**
 * Wikipedia's language for an app locale: the first subtag, lowercased, when
 * it is a language code (`zh-Hant-TW` → `zh`, `pt-BR` → `pt`); else `en`.
 */
export function wikipediaLang(locale: string): string {
  const base = (locale.split('-')[0] ?? '').toLowerCase()
  return isWikipediaLang(base) ? base : 'en'
}
```

Create `packages/shared/src/types/entity.ts`:

```ts
/**
 * What `GET /api/v1/entity/:title` answers: Wikipedia's summary of the
 * article, or `extract: null` when neither the asked language nor English
 * has it. `lang` is the language the summary came from.
 */
export interface EntitySummary {
  title: string
  extract: string | null
  description: string | null
  thumbnail: { source: string; width: number; height: number } | null
  /** The article's page, to read more; null when nothing was found. */
  url: string | null
  lang: string
}
```

- [ ] **Step 8: Run the entity tests**

Run: `bunx vitest run tests/unit/shared/utils/entity-link.test.ts`
Expected: PASS.

- [ ] **Step 9: Write the chart URL tests (failing)**

Create `tests/unit/shared/utils/stock-chart.test.ts`:

```ts
// The chart is TradingView's own embed URL in a frame: its settings travel in
// the hash, exactly as the widget's loader script would put them (verified
// 2026-10-07 to render alone). exodus-ios's StockChartTests holds the same
// vectors — keep them in step.
import {
  STOCK_CHART_HEIGHT,
  tradingViewEmbedUrl,
  tradingViewLocale,
  tradingViewSymbolPageUrl
} from '@exodus/shared/utils/stock-chart'
import { describe, expect, it } from 'vitest'

describe('tradingViewEmbedUrl', () => {
  it('is the mini-symbol-overview embed with the symbol and locale in the query and the settings in the hash', () => {
    const url = new URL(
      tradingViewEmbedUrl({
        symbol: 'NASDAQ:AAPL',
        range: '1D',
        theme: 'dark',
        locale: 'en'
      })
    )
    expect(url.origin).toBe('https://www.tradingview-widget.com')
    expect(url.pathname).toBe('/embed-widget/mini-symbol-overview/')
    expect(url.searchParams.get('locale')).toBe('en')
    expect(url.searchParams.get('symbol')).toBe('NASDAQ:AAPL')
    expect(JSON.parse(decodeURIComponent(url.hash.slice(1)))).toEqual({
      symbol: 'NASDAQ:AAPL',
      dateRange: '1D',
      colorTheme: 'dark',
      isTransparent: true,
      width: '100%',
      height: STOCK_CHART_HEIGHT,
      autosize: false,
      largeChartUrl: ''
    })
  })

  it('is byte-identical to the phone for the same input', () => {
    expect(
      tradingViewEmbedUrl({ symbol: 'TSE:7203', range: '12M', theme: 'light', locale: 'ja' })
    ).toBe(
      'https://www.tradingview-widget.com/embed-widget/mini-symbol-overview/?locale=ja&symbol=TSE%3A7203#%7B%22symbol%22%3A%22TSE%3A7203%22%2C%22dateRange%22%3A%2212M%22%2C%22colorTheme%22%3A%22light%22%2C%22isTransparent%22%3Atrue%2C%22width%22%3A%22100%25%22%2C%22height%22%3A220%2C%22autosize%22%3Afalse%2C%22largeChartUrl%22%3A%22%22%7D'
    )
  })
})

describe('tradingViewLocale', () => {
  it.each([
    ['en', 'en'],
    ['de', 'de'],
    ['es', 'es'],
    ['fr', 'fr'],
    ['it', 'it'],
    ['ja', 'ja'],
    ['ko', 'kr'],
    ['pt-BR', 'br'],
    ['zh-Hant-TW', 'zh_TW'],
    ['zh-Hant-HK', 'zh_TW'],
    ['zh', 'zh_CN'],
    ['nl', 'en'],
    ['', 'en']
  ])('%s → %s', (locale, tv) => {
    expect(tradingViewLocale(locale)).toBe(tv)
  })
})

describe('tradingViewSymbolPageUrl', () => {
  it('is the symbol page, the colon a dash', () => {
    expect(tradingViewSymbolPageUrl('NASDAQ:AAPL')).toBe(
      'https://www.tradingview.com/symbols/NASDAQ-AAPL/'
    )
    expect(tradingViewSymbolPageUrl('TSE:7203.T-A')).toBe(
      'https://www.tradingview.com/symbols/TSE-7203.T-A/'
    )
  })
})
```

- [ ] **Step 10: Run it to see it fail**

Run: `bunx vitest run tests/unit/shared/utils/stock-chart.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 11: Write `stock-chart.ts`**

```ts
// TradingView's Mini Chart (`mini-symbol-overview`) as the URL its loader
// script would put in an iframe, built here so no script of theirs runs in
// our documents (exodus-ios spec 2026-10-07 §2.3). exodus-ios's `StockChart`
// builds the same bytes, held to the same vectors.
import type { StockRange } from '../types/interactive'

export const STOCK_CHART_HEIGHT = 220
export const TRADINGVIEW_EMBED_ORIGIN = 'https://www.tradingview-widget.com'
const EMBED_PATH = '/embed-widget/mini-symbol-overview/'

/** The widget's locale codes for the app's: TradingView spells Korean `kr`, Brazilian Portuguese `br`, Chinese by script. */
const TV_LOCALES: Record<string, string> = {
  en: 'en',
  de: 'de',
  es: 'es',
  fr: 'fr',
  it: 'it',
  ja: 'ja',
  ko: 'kr',
  'pt-BR': 'br',
  'zh-Hant-TW': 'zh_TW',
  'zh-Hant-HK': 'zh_TW',
  zh: 'zh_CN'
}

export function tradingViewLocale(locale: string): string {
  return TV_LOCALES[locale] ?? TV_LOCALES[locale.split('-')[0] ?? ''] ?? 'en'
}

/**
 * The embed URL: `locale` and `symbol` in the query, the settings JSON
 * percent-encoded in the hash — the loader's own wire. Key order is the
 * settings' order here, so the phone writes the same string.
 */
export function tradingViewEmbedUrl({
  symbol,
  range,
  theme,
  locale
}: {
  symbol: string
  range: StockRange
  theme: 'light' | 'dark'
  locale: string
}): string {
  const settings = {
    symbol,
    dateRange: range,
    colorTheme: theme,
    isTransparent: true,
    width: '100%',
    height: STOCK_CHART_HEIGHT,
    autosize: false,
    largeChartUrl: ''
  }
  const query = new URLSearchParams({
    locale: tradingViewLocale(locale),
    symbol
  })
  return `${TRADINGVIEW_EMBED_ORIGIN}${EMBED_PATH}?${query.toString()}#${encodeURIComponent(JSON.stringify(settings))}`
}

/** The symbol's own page on TradingView: "Open on TradingView", and where a tap on the chart goes. */
export function tradingViewSymbolPageUrl(symbol: string): string {
  return `https://www.tradingview.com/symbols/${symbol.replace(':', '-')}/`
}
```

- [ ] **Step 12: Run the chart tests**

Run: `bunx vitest run tests/unit/shared/utils/stock-chart.test.ts`
Expected: PASS. (`URLSearchParams` writes `TSE%3A7203`, as the vector expects; if the byte-identical case fails, fix the implementation, not the vector — the phone is held to the same string in Task 8.)

- [ ] **Step 13: Write the plain-text tests (failing)**

Create `tests/unit/shared/utils/interactive-plain-text.test.ts`:

```ts
// Copy and read-aloud take a reply's words: a steps block as its numbered
// list, a stock block as its symbol and note. exodus-ios's
// InteractivePlainTextTests holds the same vectors — keep them in step.
import { withBlockText } from '@exodus/shared/utils/interactive-plain-text'
import { describe, expect, it } from 'vitest'

const STEPS =
  '{"title":"Replacing the strings","steps":[{"text":"Loosen the old string.","image":"https://imgs.search.brave.com/peg.jpg"},{"text":"Thread the new one."}]}'
const STOCK = '{"symbol":"NASDAQ:AAPL","range":"1D","note":"Up 12% since the call."}'
const ASK = '{"title":"T","questions":[{"id":"a","text":"Q?","type":"single","options":["x","y"]}]}'

const CASES: Array<[string, string, string]> = [
  [
    'steps become a titled numbered list',
    `Here is how:\n\n\`\`\`exodus-steps\n${STEPS}\n\`\`\`\n\nGood luck.`,
    'Here is how:\n\nReplacing the strings\n\n1. Loosen the old string.\n2. Thread the new one.\n\nGood luck.'
  ],
  [
    'steps without a title',
    `\`\`\`exodus-steps\n{"steps":[{"text":"A"},{"text":"B"}]}\n\`\`\``,
    '1. A\n2. B'
  ],
  [
    'a stock block is its symbol and note',
    `\`\`\`exodus-stock\n${STOCK}\n\`\`\``,
    'NASDAQ:AAPL — Up 12% since the call.'
  ],
  [
    'a stock block without a note is its symbol',
    '```exodus-stock\n{"symbol":"NASDAQ:AAPL"}\n```',
    'NASDAQ:AAPL'
  ],
  [
    'CRLF line ends are made LF',
    `Intro\r\n\r\n\`\`\`exodus-stock\r\n${STOCK}\r\n\`\`\`\r\n`,
    'Intro\n\nNASDAQ:AAPL — Up 12% since the call.\n'
  ],
  [
    'a questionnaire is left as it is',
    `\`\`\`exodus-ask\n${ASK}\n\`\`\``,
    `\`\`\`exodus-ask\n${ASK}\n\`\`\``
  ],
  [
    'a second block is code and stays',
    `\`\`\`exodus-stock\n${STOCK}\n\`\`\`\n\n\`\`\`exodus-steps\n${STEPS}\n\`\`\``,
    `NASDAQ:AAPL — Up 12% since the call.\n\n\`\`\`exodus-steps\n${STEPS}\n\`\`\``
  ],
  ['a reply without a block is untouched', 'Just words.\n\n```js\nlet a = 1\n```', 'Just words.\n\n```js\nlet a = 1\n```'],
  ['a block that does not validate stays code', '```exodus-stock\n{"symbol":"aapl"}\n```', '```exodus-stock\n{"symbol":"aapl"}\n```']
]

describe('withBlockText', () => {
  it.each(CASES)('%s', (_name, markdown, text) => {
    expect(withBlockText(markdown)).toBe(text)
  })
})
```

- [ ] **Step 14: Run it to see it fail**

Run: `bunx vitest run tests/unit/shared/utils/interactive-plain-text.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 15: Write `interactive-plain-text.ts`**

```ts
// What leaves the app as words — Copy, read-aloud — of a reply that holds a
// steps or stock block: the list a reader would say, the symbol and its
// reading, in place of the fence's JSON (exodus-ios spec 2026-10-07 §4). The
// questionnaire and the confirmation are left as they are, as in phase 1.
import {
  findInteractiveBlock,
  interactiveKind,
  trimTrailingBlanks,
  type InteractiveFence
} from '../types/interactive'

/** The block's words, or null for a kind that has none here. */
export function blockText(fence: InteractiveFence): string | null {
  switch (fence.kind) {
    case 'steps': {
      const list = fence.block.steps
        .map((step, i) => `${i + 1}. ${step.text}`)
        .join('\n')
      const title = fence.block.title?.trim()
      return title ? `${title}\n\n${list}` : list
    }
    case 'stock': {
      const note = fence.block.note?.trim()
      return note ? `${fence.block.symbol} — ${note}` : fence.block.symbol
    }
    default:
      return null
  }
}

/**
 * The reply with its block's fence — the lines from ```` ```exodus-… ```` to
 * the closing ```` ``` ```` — replaced by the block's words; the reply as it
 * was (line ends made `\n`) when it holds no such block.
 */
export function withBlockText(markdown: string): string {
  const text = markdown.replaceAll(/\r\n?/gu, '\n')
  const fence = findInteractiveBlock(text)
  if (!fence) return text
  const words = blockText(fence)
  if (words === null) return text
  const lines = text.split('\n')
  // The first opening line of the block's kind whose body is the block's
  // source: the same fence the finder took (an earlier copy inside another
  // fence has a different body or no closer of its own).
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (!line.startsWith('```')) continue
    if (interactiveKind(trimTrailingBlanks(line.slice(3))) !== fence.kind) continue
    for (let j = i + 1; j < lines.length; j++) {
      if (!/^ {0,3}```+[ \t]*$/u.test(lines[j])) continue
      if (lines.slice(i + 1, j).join('\n') === fence.source) {
        return [...lines.slice(0, i), words, ...lines.slice(j + 1)].join('\n')
      }
      break
    }
  }
  return text
}
```

- [ ] **Step 16: Run the plain-text tests**

Run: `bunx vitest run tests/unit/shared/utils/interactive-plain-text.test.ts`
Expected: PASS.

- [ ] **Step 17: Typecheck, format, lint, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
bun run typecheck:shared && bun run typecheck:web
bunx oxfmt packages/shared/src/types packages/shared/src/utils tests/unit/shared && bunx oxlint packages/shared/src/types/interactive.ts packages/shared/src/utils/entity-link.ts packages/shared/src/utils/stock-chart.ts packages/shared/src/utils/interactive-plain-text.ts packages/shared/src/types/entity.ts
bunx vitest run tests/unit/shared
git add packages/shared/package.json packages/shared/src/types/interactive.ts packages/shared/src/types/entity.ts packages/shared/src/utils/entity-link.ts packages/shared/src/utils/stock-chart.ts packages/shared/src/utils/interactive-plain-text.ts tests/unit/shared/types/interactive.test.ts tests/unit/shared/utils/entity-link.test.ts tests/unit/shared/utils/stock-chart.test.ts tests/unit/shared/utils/interactive-plain-text.test.ts
git commit -F - <<'EOF'
feat(blocks): two more kinds a reply can carry — illustrated steps (exodus-steps: 2–12 one-line steps, a thumbnail each) and a stock chart (exodus-stock: TradingView's EXCHANGE:TICKER, its own range set, default 1D) — with the entity-link title rule, the chart's embed and symbol-page URLs, and the words Copy and read-aloud get in place of a block's JSON; vectors the phone is held to

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```
Expected: the commit lists exactly the ten files (`packages/shared/package.json` gains the four `exports` entries the new modules need).

### Task 2: Desktop main — `GET /api/v1/entity/:title`, Wikipedia's summary through the safe fetch

**Files:**
- Modify: `src/main/lib/net/safe-fetch.ts` (the `headers` option), `tests/unit/main/lib/net/safe-fetch.test.ts`
- Create: `src/main/lib/server/routes/entity.ts`
- Modify: `src/main/lib/server/app.ts` (two lines), `docs/chat-api.md` (one section)
- Test: `tests/unit/main/lib/server/routes/entity.test.ts`

**Interfaces:**
- Consumes: `fetchPublicHttps(url, { maxBytes, signal, timeoutMs, headers })`, `ValidationError`, `ServiceError`, `ErrorCode`, `logger`, `Variables` (`../types`), `isWikipediaTitle`, `isWikipediaLang` (Task 1), `EntitySummary` (Task 1).
- Produces: the route's answer, an `EntitySummary` JSON (Decision 7); `clearEntityCache()` for tests. Both clients call `GET /api/v1/entity/<encodeURIComponent(title)>?lang=<wikipediaLang(locale)>` (Tasks 5 and 9).

- [ ] **Step 1: Test that `headers` reach the request (failing)**

In `tests/unit/main/lib/net/safe-fetch.test.ts`, record the request headers in the `https` mock: change the `requests` array's type to `Array<{ url: string; lookup: PinnedLookup; headers?: Record<string, string> }>`, the mock's `options` type to `{ lookup: PinnedLookup; headers?: Record<string, string> }`, and the push to `requests.push({ url: href, lookup: options.lookup, headers: options.headers })`. Then, inside `describe('fetchPublicHttps', …)`, add (after 'downloads a public https URL…'):

```ts
  it('sends the headers it is given with the request', async () => {
    dnsLookup.mockResolvedValue([{ address: '93.184.216.34', family: 4 }])
    responses.set('https://en.wikipedia.org/api/rest_v1/page/summary/X', {
      status: 200,
      headers: { 'content-type': 'application/json' },
      body: '{}'
    })
    await fetchPublicHttps(
      'https://en.wikipedia.org/api/rest_v1/page/summary/X',
      {
        maxBytes: 1024,
        headers: { 'User-Agent': 'Exodus/1 test', Accept: 'application/json' }
      }
    )
    expect(requests.at(-1)?.headers).toEqual({
      'User-Agent': 'Exodus/1 test',
      Accept: 'application/json'
    })
  })
```

(The file's `afterEach` resets `responses`, `requests` and the DNS mock; if the one you find does not, clear them at the start of this test.)

- [ ] **Step 2: Run it to see it fail**

Run: `cd /Users/yanceyleo/Code/exodus/exodus && bunx vitest run tests/unit/main/lib/net/safe-fetch.test.ts`
Expected: FAIL — `headers` is `undefined` on the recorded request (and a type error on the option).

- [ ] **Step 3: Pass `headers` through `safe-fetch.ts`**

In `FetchPublicHttpsOptions` add:

```ts
  /** Sent with every hop: the `User-Agent` an API's policy asks for, an `Accept`. */
  headers?: Record<string, string>
```

Change `get`'s signature and the request options:

```ts
function get(
  url: URL,
  addrs: Resolved,
  signal: AbortSignal,
  headers: Record<string, string> | undefined
): Promise<{ res: IncomingMessage; abort: (e: Error) => void }> {
  return new Promise((resolvePromise, reject) => {
    const req = request(
      url,
      {
        method: 'GET',
        signal,
        headers,
        // Pinned: the socket connects to an address vetHost checked, never
        // to a fresh DNS answer.
        lookup: (_host, options, cb) => {
```

In `fetchPublicHttps`, destructure `headers` with the others and call `get(current, addrs, combined, headers)`.

- [ ] **Step 4: Run the safe-fetch tests**

Run: `bunx vitest run tests/unit/main/lib/net/safe-fetch.test.ts`
Expected: PASS (every earlier case too: `headers` is `undefined` for them, which `https.request` ignores).

- [ ] **Step 5: Write the route tests (failing)**

Create `tests/unit/main/lib/server/routes/entity.test.ts`:

```ts
// src/main/lib/server/routes/entity.ts — GET /api/v1/entity/:title: Wikipedia's
// summary of an article for the entity panel, fetched in main through the safe
// fetch so a phone needs only its computer, cached a day. The asked language
// first, then English; nothing found is an answer (200, no extract).
import { Hono } from 'hono'
import { beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('electron', () => ({ app: { getPath: () => '/tmp' } }))
const warn = vi.fn()
vi.mock('@main/lib/logger', () => ({
  logger: { info: vi.fn(), warn, error: vi.fn(), debug: vi.fn() }
}))
const fetchPublicHttps = vi.fn()
vi.mock('@main/lib/net/safe-fetch', () => ({ fetchPublicHttps }))

const { default: entityRouter, clearEntityCache } =
  await import('@main/lib/server/routes/entity')
const { errorHandler } =
  await import('@main/lib/server/middlewares/error-handler')

const app = new Hono()
app.route('/api/v1/entity', entityRouter as never)
app.onError(errorHandler)
const get = (path: string) => app.request(`/api/v1/entity${path}`)

const CURIE = {
  title: 'Marie Curie',
  extract:
    'Maria Salomea Skłodowska-Curie was a Polish and naturalised-French physicist and chemist.',
  description: 'Polish-French physicist and chemist (1867–1934)',
  thumbnail: {
    source: 'https://upload.wikimedia.org/x/330px-Marie_Curie.jpg',
    width: 330,
    height: 448
  },
  content_urls: { desktop: { page: 'https://en.wikipedia.org/wiki/Marie_Curie' } },
  lang: 'en',
  type: 'standard'
}
const json = (value: unknown) => ({
  bytes: Buffer.from(JSON.stringify(value)),
  contentType: 'application/json'
})
const urls = () => fetchPublicHttps.mock.calls.map((call) => call[0])

beforeEach(() => {
  fetchPublicHttps.mockReset()
  warn.mockReset()
  clearEntityCache()
})

describe('GET /api/v1/entity/:title', () => {
  it('answers the summary from the asked language, with the fields the panel draws', async () => {
    fetchPublicHttps.mockResolvedValue(json(CURIE))
    const res = await get('/Marie_Curie?lang=en')
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      title: 'Marie Curie',
      extract: CURIE.extract,
      description: CURIE.description,
      thumbnail: CURIE.thumbnail,
      url: 'https://en.wikipedia.org/wiki/Marie_Curie',
      lang: 'en'
    })
    const [url, options] = fetchPublicHttps.mock.calls[0]!
    expect(url).toBe(
      'https://en.wikipedia.org/api/rest_v1/page/summary/Marie_Curie'
    )
    expect(options.headers['User-Agent']).toMatch(/^Exodus\//u)
    expect(options.headers.Accept).toBe('application/json')
    expect(options.maxBytes).toBe(512 * 1024)
  })

  it('percent-encodes the title and uses the language subdomain', async () => {
    fetchPublicHttps.mockResolvedValue(json({ ...CURIE, title: '東京', lang: 'ja' }))
    await get('/%E6%9D%B1%E4%BA%AC?lang=ja')
    expect(urls()).toEqual([
      'https://ja.wikipedia.org/api/rest_v1/page/summary/%E6%9D%B1%E4%BA%AC'
    ])
  })

  it('falls back to English when the asked language has no article', async () => {
    fetchPublicHttps
      .mockRejectedValueOnce(new Error('HTTP 404'))
      .mockResolvedValueOnce(json(CURIE))
    const res = await get('/Marie_Curie?lang=zh')
    expect(res.status).toBe(200)
    expect((await res.json()).lang).toBe('en')
    expect(urls()).toEqual([
      'https://zh.wikipedia.org/api/rest_v1/page/summary/Marie_Curie',
      'https://en.wikipedia.org/api/rest_v1/page/summary/Marie_Curie'
    ])
  })

  it('nothing found anywhere is a 200 with no extract', async () => {
    fetchPublicHttps.mockRejectedValue(new Error('HTTP 404'))
    const res = await get('/Nobody_Here?lang=en')
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      title: 'Nobody Here',
      extract: null,
      description: null,
      thumbnail: null,
      url: null,
      lang: 'en'
    })
    expect(fetchPublicHttps).toHaveBeenCalledTimes(1)
  })

  it('remembers an answer for a day, per language', async () => {
    fetchPublicHttps.mockResolvedValue(json(CURIE))
    await get('/Marie_Curie?lang=en')
    await get('/Marie_Curie?lang=en')
    expect(fetchPublicHttps).toHaveBeenCalledTimes(1)
    await get('/Marie_Curie?lang=fr')
    expect(fetchPublicHttps).toHaveBeenCalledTimes(2)
  })

  it('defaults the language to English', async () => {
    fetchPublicHttps.mockResolvedValue(json(CURIE))
    await get('/Marie_Curie')
    expect(urls()[0]).toContain('https://en.wikipedia.org/')
  })

  // (`..` and `.` as a path segment are swallowed by URL parsing before the
  // route sees them; the title rule's own vectors cover them in Task 1.)
  it.each([
    '/a%2Fb?lang=en',
    '/Marie%20Curie?lang=en',
    `/${'a'.repeat(201)}?lang=en`,
    '/Marie_Curie?lang=EN',
    '/Marie_Curie?lang=e',
    '/Marie_Curie?lang=en.evil',
    '/Marie_Curie?lang=en%2Fx'
  ])('refuses %s with a 400 before any fetch', async (path) => {
    const res = await get(path)
    expect(res.status).toBe(400)
    expect(fetchPublicHttps).not.toHaveBeenCalled()
  })

  it('an upstream failure is a 503 that names no URL', async () => {
    fetchPublicHttps.mockRejectedValue(new Error('HTTP 503'))
    const res = await get('/Marie_Curie?lang=en')
    expect(res.status).toBe(503)
    expect(await res.text()).not.toContain('wikipedia.org')
    expect(warn).toHaveBeenCalledWith(
      'entity',
      'Wikipedia summary fetch failed',
      { error: expect.any(Error) }
    )
  })

  it('a summary without a thumbnail or a page is answered without them', async () => {
    fetchPublicHttps.mockResolvedValue(json({ title: 'X', extract: 'Y' }))
    expect(await (await get('/X?lang=en')).json()).toEqual({
      title: 'X',
      extract: 'Y',
      description: null,
      thumbnail: null,
      url: null,
      lang: 'en'
    })
  })

  it('a thumbnail that is not https is dropped', async () => {
    fetchPublicHttps.mockResolvedValue(
      json({ ...CURIE, thumbnail: { source: 'http://x/y.jpg', width: 1, height: 1 } })
    )
    expect((await (await get('/Marie_Curie?lang=en')).json()).thumbnail).toBeNull()
  })
})
```

- [ ] **Step 6: Run it to see it fail**

Run: `bunx vitest run tests/unit/main/lib/server/routes/entity.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 7: Write `routes/entity.ts`**

```ts
import { ErrorCode } from '@exodus/shared/constants/error-codes'
import {
  ServiceError,
  ValidationError
} from '@exodus/shared/errors/app-error'
import type { EntitySummary } from '@exodus/shared/types/entity'
import {
  isWikipediaLang,
  isWikipediaTitle
} from '@exodus/shared/utils/entity-link'
import { Hono } from 'hono'

import { logger } from '../../logger'
import { fetchPublicHttps } from '../../net/safe-fetch'
import { Variables } from '../types'

/**
 * `GET /api/v1/entity/:title?lang=xx` — Wikipedia's summary of an article,
 * for the panel a reply's `[name](entity:Title)` link opens (exodus-ios spec
 * 2026-10-07 §2.2). Fetched here through `fetchPublicHttps()` (https only,
 * public addresses only, pinned) so a paired phone needs no network but its
 * computer's, and the answer is kept a day. Tried in the app's language
 * first, then English; an article neither has is `{ extract: null }` with a
 * 200 — "nothing found" is an answer, not a failure. The upstream URL never
 * appears in an error or a log line.
 */
const entity = new Hono<{ Variables: Variables }>()

const TTL_MS = 24 * 60 * 60 * 1000
const CACHE_MAX = 500
const MAX_BYTES = 512 * 1024
// Wikimedia's API policy asks every client for a User-Agent that names it
// and says where to find its maker.
const USER_AGENT = 'Exodus/1 (https://github.com/YanceyOfficial/exodus) entity-panel'

interface WikipediaSummary {
  title?: string
  extract?: string
  description?: string
  thumbnail?: { source?: string; width?: number; height?: number }
  content_urls?: { desktop?: { page?: string } }
  lang?: string
}

const cache = new Map<string, { at: number; summary: EntitySummary }>()

/** For tests: the day's memory emptied. */
export function clearEntityCache(): void {
  cache.clear()
}

/** Wikipedia's answer as the panel's: the fields it draws, the rest dropped. */
export function summaryOf(
  json: WikipediaSummary,
  lang: string,
  askedTitle: string
): EntitySummary {
  const thumb = json.thumbnail
  const hasThumb =
    typeof thumb?.source === 'string' &&
    thumb.source.startsWith('https://') &&
    typeof thumb.width === 'number' &&
    typeof thumb.height === 'number'
  return {
    title: json.title ?? askedTitle.replaceAll('_', ' '),
    extract: json.extract?.trim() || null,
    description: json.description ?? null,
    thumbnail: hasThumb
      ? { source: thumb.source!, width: thumb.width!, height: thumb.height! }
      : null,
    url: json.content_urls?.desktop?.page ?? null,
    lang: json.lang ?? lang
  }
}

/** The article's summary in `lang`, or null when Wikipedia has no such page (its 404). */
async function lookup(
  lang: string,
  title: string,
  signal: AbortSignal
): Promise<EntitySummary | null> {
  const url = `https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`
  let fetched: { bytes: Buffer; contentType: string | null }
  try {
    fetched = await fetchPublicHttps(url, {
      maxBytes: MAX_BYTES,
      timeoutMs: 15_000,
      signal,
      headers: { Accept: 'application/json', 'User-Agent': USER_AGENT }
    })
  } catch (error) {
    if (error instanceof Error && error.message === 'HTTP 404') return null
    throw error
  }
  const json = JSON.parse(fetched.bytes.toString('utf8')) as WikipediaSummary
  return summaryOf(json, lang, title)
}

function remember(key: string, summary: EntitySummary): void {
  if (cache.size >= CACHE_MAX) {
    const oldest = cache.keys().next().value
    if (oldest !== undefined) cache.delete(oldest)
  }
  cache.set(key, { at: Date.now(), summary })
}

entity.get('/:title', async (c) => {
  const title = c.req.param('title')
  if (!isWikipediaTitle(title)) {
    throw new ValidationError(ErrorCode.VALIDATION_FAILED, 'Invalid entity title')
  }
  const lang = c.req.query('lang') ?? 'en'
  if (!isWikipediaLang(lang)) {
    throw new ValidationError(ErrorCode.VALIDATION_FAILED, 'Invalid lang')
  }
  const key = `${lang}/${title}`
  const hit = cache.get(key)
  if (hit && Date.now() - hit.at < TTL_MS) return c.json(hit.summary)
  const signal = c.req.raw.signal
  let summary: EntitySummary
  try {
    const found =
      (await lookup(lang, title, signal)) ??
      (lang === 'en' ? null : await lookup('en', title, signal))
    summary = found ?? {
      title: title.replaceAll('_', ' '),
      extract: null,
      description: null,
      thumbnail: null,
      url: null,
      lang
    }
  } catch (error) {
    // A safe-fetch error's message never carries the URL.
    logger.warn('entity', 'Wikipedia summary fetch failed', {
      error: error instanceof Error ? error : 'unknown'
    })
    throw new ServiceError(
      ErrorCode.SERVICE_UNAVAILABLE,
      'Entity summary unavailable'
    )
  }
  remember(key, summary)
  return c.json(summary)
})

export default entity
```

- [ ] **Step 8: Mount it**

In `src/main/lib/server/app.ts`, among the route imports (alphabetical: after `discoverRouter`) add `import entityRouter from './routes/entity'`, and after `v1.route('/discover', discoverRouter)` add `v1.route('/entity', entityRouter)`.

- [ ] **Step 9: Run the route tests**

Run: `bunx vitest run tests/unit/main/lib/server/routes/entity.test.ts tests/unit/main/lib/server`
Expected: PASS (the new file and every other route test).

- [ ] **Step 10: Document the route**

In `docs/chat-api.md`, after §8.2's paragraph (before whatever section follows it, or at the end if none), add:

```markdown
## 9. Entity summaries: `GET /api/v1/entity/:title`

For the panel a reply's `[name](entity:Title)` link opens (rich blocks phase 2). `title` is a Wikipedia article
title (1–200 units of letters, digits, `_ ( ) . , ' - :`, percent-encoded in the path); `lang` a two- or
three-letter Wikipedia language, default `en`. The computer reads `https://<lang>.wikipedia.org/api/rest_v1/page/summary/<title>`
through the safe fetch (https, public addresses only), then English when that is a 404, and keeps the answer a day:

```jsonc
{ "title": "Marie Curie", "extract": "…", "description": "…",
  "thumbnail": { "source": "https://upload.wikimedia.org/…", "width": 330, "height": 448 } | null,
  "url": "https://en.wikipedia.org/wiki/Marie_Curie" | null, "lang": "en" }
```

An article neither language has is a `200` with `extract: null` and `url: null`. `400 VALIDATION_FAILED` for a title or
`lang` outside the rule; `503 SERVICE_UNAVAILABLE` when Wikipedia could not be reached.
```

- [ ] **Step 11: Typecheck, format, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
bun run typecheck:node
bunx oxfmt src/main/lib/server/routes/entity.ts src/main/lib/net/safe-fetch.ts tests/unit/main/lib/server/routes/entity.test.ts tests/unit/main/lib/net/safe-fetch.test.ts && bunx oxlint src/main/lib/server/routes/entity.ts src/main/lib/net/safe-fetch.ts
git add src/main/lib/net/safe-fetch.ts src/main/lib/server/routes/entity.ts src/main/lib/server/app.ts tests/unit/main/lib/net/safe-fetch.test.ts tests/unit/main/lib/server/routes/entity.test.ts docs/chat-api.md
git commit -F - <<'EOF'
feat(server): GET /api/v1/entity/:title answers Wikipedia's summary of an article for the entity panel — read through the safe fetch in the app's language, then English, kept a day; nothing found is a 200 without an extract, and the safe fetch learns to carry request headers (the User-Agent Wikimedia asks for)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```
Expected: the six files.

### Task 3: Desktop — the chat prompt's second half

**Files:**
- Modify: `src/main/lib/ai/interactive-blocks-prompt.ts`
- Test: `tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts`, `tests/unit/main/lib/ai/prompts.test.ts` (one number)

**Interfaces:**
- Consumes: `stepsBlockSchema`, `stockBlockSchema` (Task 1).
- Produces: `STEPS_EXAMPLE`, `STOCK_EXAMPLE`; `INTERACTIVE_BLOCKS_PROMPT` now teaches four blocks and the entity link.

- [ ] **Step 1: Extend the prompt test (failing)**

In `tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts`:
- Import `stepsBlockSchema, stockBlockSchema` alongside the two schemas, and `STEPS_EXAMPLE, STOCK_EXAMPLE` from the prompt module.
- In 'is in the chat prompt…' add:

```ts
    expect(prompt).toContain(
      `\`\`\`exodus-steps\n${JSON.stringify(STEPS_EXAMPLE)}\n\`\`\``
    )
    expect(prompt).toContain(
      `\`\`\`exodus-stock\n${JSON.stringify(STOCK_EXAMPLE)}\n\`\`\``
    )
    expect(prompt).toContain('[Marie Curie](entity:Marie_Curie)')
```
- In 'shows examples the clients draw' add:

```ts
    expect(stepsBlockSchema.safeParse(STEPS_EXAMPLE).success).toBe(true)
    expect(stockBlockSchema.safeParse(STOCK_EXAMPLE).success).toBe(true)
```
- Add:

```ts
  it('tells the model where a picture may come from, and which ranges exist', () => {
    expect(INTERACTIVE_BLOCKS_PROMPT).toContain('never an original image')
    expect(INTERACTIVE_BLOCKS_PROMPT).toContain('1D, 1M, 3M, 12M, 60M, ALL')
    expect(INTERACTIVE_BLOCKS_PROMPT).toContain('at most five a reply')
  })
```
- Change 'stays short' to `toBeLessThanOrEqual(70)`.
- In 'is in no other prompt' add `expect(other).not.toContain('exodus-steps')`, `expect(other).not.toContain('exodus-stock')`, `expect(other).not.toContain('(entity:')`.

In `tests/unit/main/lib/ai/prompts.test.ts` change the budget line to `expect(getSystemPrompt({}).length).toBeLessThan(13_500)` and its comment's last sentence to: `// …which brought the chat prompt to ~11.2k characters; phase 2 (steps, the entity link, the stock chart) adds ~1.8k.`

- [ ] **Step 2: Run them to see them fail**

Run: `bunx vitest run tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts`
Expected: FAIL — `STEPS_EXAMPLE` is not exported.

- [ ] **Step 3: Grow the prompt**

In `src/main/lib/ai/interactive-blocks-prompt.ts`, after `CONFIRM_EXAMPLE` add:

```ts
/** The illustrated steps the section shows; a test holds that it validates. */
export const STEPS_EXAMPLE = {
  title: 'Replacing the strings',
  steps: [
    {
      text: 'Loosen the old string from the tuning peg and pull it out at the bridge.',
      image: 'https://imgs.search.brave.com/eXAmPLe/rs:fit:500:0:0:0/g:ce/aHR0cHM6Ly9leGFtcGxlLmNvbS9wZWcuanBn'
    },
    { text: 'Thread the new one through the bridge pin hole and up to the peg.' },
    { text: 'Tune up slowly, stretching the string gently as you go.' }
  ]
}

/** The stock chart the section shows; a test holds that it validates. */
export const STOCK_EXAMPLE = {
  symbol: 'NASDAQ:AAPL',
  range: '1D',
  note: "Flat on the day after yesterday's 3% rise; the earnings call is tomorrow."
}
```

Replace the section's first line and insert the new half before `Rules`, then amend the rules. The whole constant becomes:

```ts
export const INTERACTIVE_BLOCKS_PROMPT = `<interactive_blocks>
Both apps draw four fenced blocks natively inside your reply, and one kind of link; two of the blocks ask, and the user's answer comes back as a message.

\`exodus-ask\` is a questionnaire. Use it when your answer depends on facts only the user has — their situation, preferences, constraints — and a few short choices get them faster than prose. Ask only what changes your answer; what you can reasonably assume, assume and say so. 1–8 questions, 2–8 short options each; "type" is "single" or "multi"; "other": true adds a choice the user types into.
${FENCE}exodus-ask
${JSON.stringify(ASK_EXAMPLE)}
${FENCE}

\`exodus-confirm\` is a confirmation. Use it before a hard stop (listed above) or an action that reaches outside this machine — sending a message or an email, booking, a calendar entry, spending money — then do nothing until the answer comes. Inside your workspace act freely: no confirmation. Say what will happen in "details" (Markdown), briefly.
${FENCE}exodus-confirm
${JSON.stringify(CONFIRM_EXAMPLE)}
${FENCE}

\`exodus-steps\` is a how-to as numbered steps, each a line or two and, where a picture from your web search in this reply fits, that picture. Use it for "how do I…" answers of 3–12 ordered actions. "image" is optional and must be, character for character, a thumbnail URL a search result of this reply carried (a page's thumbnail, or an image result's thumbnail) — never an original image, never a URL you made up; the app drops anything else and draws the step without a picture.
${FENCE}exodus-steps
${JSON.stringify(STEPS_EXAMPLE)}
${FENCE}

\`exodus-stock\` is a price chart. Use it when the user asks about a listed company's or an index's price or performance: the app draws TradingView's chart of "symbol" (EXCHANGE:TICKER — NASDAQ:AAPL, NYSE:BRK.B, TSE:7203, NASDAQ:NDX) with your one-line reading as "note". "range" is one of 1D, 1M, 3M, 12M, 60M, ALL; leave it out (1D) unless the question names a span.
${FENCE}exodus-stock
${JSON.stringify(STOCK_EXAMPLE)}
${FENCE}

An entity link, \`[Marie Curie](entity:Marie_Curie)\`, opens a short Wikipedia summary when tapped. Use it at the first mention of a notable person, place, organisation or work the user may want to know more about — at most five a reply; never for the user's own names, everyday words or anything you are unsure has an article. The target is the article's title as Wikipedia writes it, spaces as "_".

Rules
- At most one block per reply, of any kind, after what you write, on lines of its own; never inside another code block, a list, a quote or a table.
- The JSON is one object with only these keys. Limits: title 200 characters, question 200, option 80, note 120 (questionnaire and confirmation) or 300 (stock), submit/approve/reject 40, details 1000, step 300, 2–12 steps, symbol 40; question ids are lowercase letters, digits, "_" or "-", each used once.
- Write the block's words in the user's language (an entity title stays the article's own).
- A user message whose text opens with ${FENCE}exodus-answer answers the questionnaire or confirmation you asked: act on it, do not ask again. "—" is a question left blank; carry on with what you have. A rejected confirmation means do not do it.
- Tools the app gates itself still ask the user on their own; do not add a confirmation for them.
</interactive_blocks>`
```

Update the file's header comment: `// The chat's section on the blocks both apps draw (exodus-ios specs 2026-10-06 §3 and 2026-10-07 §3): …`.

- [ ] **Step 4: Run the prompt tests and the budget**

Run: `bunx vitest run tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts tests/unit/main/lib/ai/prompts.test.ts`
Expected: PASS. If the budget fails, shorten the new prose (not the examples) until it passes; do not raise the number again.

- [ ] **Step 5: Format, typecheck, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
bunx oxfmt src/main/lib/ai/interactive-blocks-prompt.ts tests/unit/main/lib/ai && bun run typecheck:node
git add src/main/lib/ai/interactive-blocks-prompt.ts tests/unit/main/lib/ai/interactive-blocks-prompt.test.ts tests/unit/main/lib/ai/prompts.test.ts
git commit -F - <<'EOF'
feat(prompt): the chat prompt teaches the two new blocks and the entity link — steps only with the search's own thumbnails (never an original), the stock chart with TradingView's range set and 1D by default, entity links sparingly on first mentions; the section may run to 70 lines and the prompt to 13.5k characters

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```

### Task 4: Desktop renderer — the strings, the steps and the chart drawn in a reply

**Files:**
- Create: `/tmp/rich2/desktop_strings.py` (tooling, not committed)
- Modify: `packages/shared/src/i18n/locales/<10>/chat.json` (`richBlocks`), `packages/shared/src/i18n/locales/<10>/lock.json` (`privacy.thirdParty`, used in Task 5), `packages/shared/src/constants/test-ids.ts`
- Modify: `src/renderer/components/markdown/remote-image.tsx`, `src/renderer/components/markdown/markdown.tsx`, `src/renderer/components/chat/interactive/interactive-fence.tsx`
- Create: `src/renderer/components/chat/interactive/steps-block.tsx`, `src/renderer/components/chat/interactive/stock-block.tsx`
- Test: `tests/unit/renderer/components/chat/rich-blocks.test.ts`

**Interfaces:**
- Consumes: `StepsBlock`, `StockBlock`, `DEFAULT_STOCK_RANGE`, `InteractiveFence` (Task 1); `tradingViewEmbedUrl`, `tradingViewSymbolPageUrl`, `STOCK_CHART_HEIGHT` (Task 1); `RemoteImage`, `httpsHref` (remote-image.tsx); `InteractiveTurnContext`, `useInteractiveChat` (phase 1).
- Produces: `searchThumbnailUrls(results): ReadonlySet<string> | null`, `SearchThumbnailUrlsContext`, `thumbnailHref(src, thumbnails): string | null` (remote-image.tsx); `StepsBlock({ block })`, `StockBlock({ block })`, `STOCK_FRAME_TIMEOUT_MS`; `TEST_IDS.chat.richBlocks.*`; `chat:richBlocks.*` strings; `lock:privacy.thirdParty` (Task 5 reads it).

- [ ] **Step 1: The strings, inserted textually**

Write `/tmp/rich2/desktop_strings.py`:

```python
#!/usr/bin/env python3
"""Inserts the chat namespace's `richBlocks` object and the lock namespace's `privacy.thirdParty` line into the ten
desktop locales, textually — before "workspaceFile" in chat.json, before "enroll" inside "privacy" in lock.json — so
no other line is rewritten. Run from the desktop repo root: python3 /tmp/rich2/desktop_strings.py"""
import json

DIR = "packages/shared/src/i18n/locales"
LOCALES = ["en", "de", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-Hant-HK", "zh-Hant-TW"]
KEYS = ["stepLabel", "openOnTradingView", "chartBy", "chartUnavailable", "entityLoading", "entityNothing",
        "entityFailed", "readMore"]
CHAT = {
    "en": ["Step {{number}}", "Open on TradingView", "Chart by TradingView", "The chart could not be loaded.",
           "Loading…", "Nothing found on Wikipedia.", "Could not reach Wikipedia.", "Read more on Wikipedia"],
    "de": ["Schritt {{number}}", "Auf TradingView öffnen", "Chart von TradingView",
           "Der Chart konnte nicht geladen werden.", "Wird geladen …", "Nichts auf Wikipedia gefunden.",
           "Wikipedia ist nicht erreichbar.", "Mehr auf Wikipedia lesen"],
    "es": ["Paso {{number}}", "Abrir en TradingView", "Gráfico de TradingView", "No se pudo cargar el gráfico.",
           "Cargando…", "No se encontró nada en Wikipedia.", "No se pudo conectar con Wikipedia.",
           "Leer más en Wikipedia"],
    "fr": ["Étape {{number}}", "Ouvrir sur TradingView", "Graphique TradingView",
           "Le graphique n'a pas pu être chargé.", "Chargement…", "Rien trouvé sur Wikipédia.",
           "Wikipédia est injoignable.", "Lire la suite sur Wikipédia"],
    "it": ["Passo {{number}}", "Apri su TradingView", "Grafico di TradingView", "Impossibile caricare il grafico.",
           "Caricamento…", "Nessun risultato su Wikipedia.", "Impossibile raggiungere Wikipedia.",
           "Leggi di più su Wikipedia"],
    "ja": ["ステップ {{number}}", "TradingView で開く", "チャート: TradingView", "チャートを読み込めませんでした。",
           "読み込み中…", "Wikipedia に該当する記事はありません。", "Wikipedia に接続できませんでした。",
           "Wikipedia で続きを読む"],
    "ko": ["{{number}}단계", "TradingView에서 열기", "차트: TradingView", "차트를 불러올 수 없습니다.", "불러오는 중…",
           "Wikipedia에서 찾을 수 없습니다.", "Wikipedia에 연결할 수 없습니다.", "Wikipedia에서 더 읽기"],
    "pt-BR": ["Passo {{number}}", "Abrir no TradingView", "Gráfico do TradingView",
              "Não foi possível carregar o gráfico.", "Carregando…", "Nada encontrado na Wikipédia.",
              "Não foi possível acessar a Wikipédia.", "Ler mais na Wikipédia"],
    "zh-Hant-HK": ["第 {{number}} 步", "喺 TradingView 開啟", "圖表：TradingView", "載入唔到圖表。", "載入緊…",
                   "維基百科冇相關條目。", "連接唔到維基百科。", "喺維基百科閱讀更多"],
    "zh-Hant-TW": ["第 {{number}} 步", "在 TradingView 開啟", "圖表：TradingView", "無法載入圖表。", "載入中…",
                   "維基百科沒有相關條目。", "無法連線到維基百科。", "在維基百科閱讀更多"],
}
THIRD_PARTY = {
    "en": "A stock chart in a chat is TradingView's own embed: TradingView sees the symbol and your IP address, as any embedded chart would. No cookies are kept.",
    "de": "Ein Aktienchart im Chat ist eine Einbettung von TradingView: TradingView sieht das Symbol und Ihre IP-Adresse, wie bei jedem eingebetteten Chart. Es werden keine Cookies gespeichert.",
    "es": "Un gráfico bursátil en un chat es una inserción de TradingView: TradingView ve el símbolo y tu dirección IP, como con cualquier gráfico insertado. No se guardan cookies.",
    "fr": "Un graphique boursier dans une conversation est une intégration TradingView : TradingView voit le symbole et votre adresse IP, comme pour tout graphique intégré. Aucun cookie n'est conservé.",
    "it": "Un grafico azionario in una chat è un embed di TradingView: TradingView vede il simbolo e il tuo indirizzo IP, come per qualsiasi grafico incorporato. Nessun cookie viene conservato.",
    "ja": "チャット内の株価チャートは TradingView の埋め込みです。埋め込みチャートの常として、TradingView にはシンボルとあなたの IP アドレスが伝わります。Cookie は保存されません。",
    "ko": "채팅의 주가 차트는 TradingView 임베드입니다. 다른 임베드 차트와 마찬가지로 TradingView는 종목 기호와 IP 주소를 알게 됩니다. 쿠키는 저장되지 않습니다.",
    "pt-BR": "Um gráfico de ações em um chat é um embed do TradingView: o TradingView vê o símbolo e seu endereço IP, como em qualquer gráfico incorporado. Nenhum cookie é mantido.",
    "zh-Hant-HK": "對話入面嘅股票圖表係 TradingView 嘅嵌入內容：同所有嵌入圖表一樣，TradingView 會見到股票代號同你嘅 IP 地址。唔會保留 Cookie。",
    "zh-Hant-TW": "對話中的股票圖表是 TradingView 的嵌入內容：如同任何嵌入圖表，TradingView 會看到股票代號與你的 IP 位址。不會保留 Cookie。",
}
CHAT_ANCHOR = '\n  "workspaceFile": {\n'
LOCK_ANCHOR = '\n    "enroll": {\n'

def rich_blocks(locale):
    lines = [f'    "{k}": {json.dumps(v, ensure_ascii=False)}' for k, v in zip(KEYS, CHAT[locale])]
    return '\n  "richBlocks": {\n' + ",\n".join(lines) + "\n  },"

for locale in LOCALES:
    path = f"{DIR}/{locale}/chat.json"
    text = open(path, encoding="utf-8").read()
    assert '"richBlocks"' not in text, path + " has it already"
    assert text.count(CHAT_ANCHOR) == 1, path
    text = text.replace(CHAT_ANCHOR, rich_blocks(locale) + CHAT_ANCHOR, 1)
    json.loads(text)
    open(path, "w", encoding="utf-8").write(text)
    path = f"{DIR}/{locale}/lock.json"
    text = open(path, encoding="utf-8").read()
    assert '"thirdParty"' not in text, path + " has it already"
    assert text.count(LOCK_ANCHOR) == 1, path
    line = f'\n    "thirdParty": {json.dumps(THIRD_PARTY[locale], ensure_ascii=False)},'
    text = text.replace(LOCK_ANCHOR, line + LOCK_ANCHOR, 1)
    json.loads(text)
    open(path, "w", encoding="utf-8").write(text)
print("done")
```

Run: `mkdir -p /tmp/rich2 && cd /Users/yanceyleo/Code/exodus/exodus && python3 /tmp/rich2/desktop_strings.py && bunx oxfmt packages/shared/src/i18n/locales && bun run i18n:check`
Expected: `done`, then `i18n:check OK`. (`git diff --stat` shows the twenty locale files and nothing else.)

- [ ] **Step 2: Test IDs**

In `packages/shared/src/constants/test-ids.ts`, inside `chat`, after `remoteImage: { … }` add:

```ts
    /** The phase-2 blocks drawn in a reply: steps, the stock chart, the entity link and its panel (chat/interactive/). */
    richBlocks: {
      steps: 'chat.rich-blocks.steps',
      step: 'chat.rich-blocks.step',
      stepImage: 'chat.rich-blocks.step-image',
      stock: 'chat.rich-blocks.stock',
      stockFrame: 'chat.rich-blocks.stock-frame',
      stockFallback: 'chat.rich-blocks.stock-fallback',
      entityLink: 'chat.rich-blocks.entity-link',
      entityPanel: 'chat.rich-blocks.entity-panel'
    }
```

(The linkage test will fail until Tasks 4 and 5 apply and reference every one of them; that is expected between the two tasks' commits only if Task 5 is not yet done — run `bunx vitest run tests/unit/shared/constants` at the end of Task 5, not here.)

- [ ] **Step 3: Write the render tests (failing)**

Create `tests/unit/renderer/components/chat/rich-blocks.test.ts`:

```ts
// @vitest-environment happy-dom
// @vitest-environment-options { "happyDOM": { "settings": { "disableIframePageLoading": true, "disableJavaScriptFileLoading": true, "disableCSSFileLoading": true } } }
// A reply's illustrated steps and stock chart are drawn in place of their
// fences: steps with only the run's own search thumbnails as pictures, the
// chart as TradingView's embed in a sandboxed frame that falls back to a card
// when it cannot load. Copy takes the block's words.
import { TEST_IDS } from '@exodus/shared/constants/test-ids'
import type { ChatMessage, SendMessageOptions, TurnBlock } from '@exodus/shared/types/chat'
import type { WebSearchResult } from '@exodus/shared/types/web-search'
import { tradingViewEmbedUrl, tradingViewSymbolPageUrl } from '@exodus/shared/utils/stock-chart'
import { Provider as JotaiProvider } from 'jotai'
import { act, createElement, type ReactElement } from 'react'
import { createRoot } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

;(
  globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
).IS_REACT_ACT_ENVIRONMENT = true

const t = (key: string, params?: Record<string, unknown>) =>
  params ? `${key} ${JSON.stringify(params)}` : key
const i18n = { resolvedLanguage: 'en', language: 'en' }
vi.mock('react-i18next', () => ({ useTranslation: () => ({ t, i18n }) }))
// The real one observes the viewport; here a picture is an <img>.
vi.mock('@/components/markdown/lazy-load-image', () => ({
  LazyLoadImage: ({ src, alt }: { src: string; alt: string }) =>
    createElement('img', { src, alt, 'data-lazy': '' })
}))
const handleCopy = vi.fn()
vi.mock('@/hooks/use-clipboard', () => ({
  useClipboard: () => ({ copied: null, handleCopy })
}))
vi.mock('@/components/chat/audio-player', () => ({ AudioPlayer: () => null }))

const { default: Markdown } = await import('@/components/markdown/markdown')
const { InteractiveProvider, InteractiveTurnContext, TurnTextAboveContext, turnTextsAbove, useInteractiveTurn } =
  await import('@/components/chat/interactive/interactive-context')
const { MessageAction } = await import('@/components/chat/message-action')

const STEPS = {
  title: 'Replacing the strings',
  steps: [
    { text: 'Loosen the old string.', image: 'https://imgs.search.brave.com/peg.jpg' },
    { text: 'Thread the new one.', image: 'https://cdn.example.com/original/bridge.jpg' },
    { text: 'Tune up slowly.', image: 'https://imgs.search.brave.com/not-from-this-run.jpg' },
    { text: 'Stretch it.' }
  ]
}
const STOCK = { symbol: 'NASDAQ:AAPL', range: '12M', note: 'Up 12% since the call.' }
// A search this run made: a page with a thumbnail, and an image result whose
// original is the second step's picture.
const RESULTS: WebSearchResult[] = [
  {
    rank: 1,
    link: 'https://guitars.example/strings',
    title: 'Restringing',
    content: '',
    snippet: '',
    thumbnail: 'https://imgs.search.brave.com/peg.jpg',
    media: [
      {
        kind: 'image',
        title: 'bridge',
        url: 'https://cdn.example.com/original/bridge.jpg',
        sourceUrl: 'https://guitars.example/strings',
        thumbnailUrl: 'https://imgs.search.brave.com/bridge-thumb.jpg'
      }
    ]
  }
]

const fence = (language: string, value: unknown) =>
  `\`\`\`${language}\n${JSON.stringify(value)}\n\`\`\``

function Turn({ body, results }: { body: string; results?: WebSearchResult[] }) {
  const turn = useInteractiveTurn('run-1', body)
  const above = turnTextsAbove([{ kind: 'text', key: 't0', text: body } as TurnBlock])
  return createElement(
    InteractiveTurnContext.Provider,
    { value: turn },
    createElement(
      TurnTextAboveContext.Provider,
      { value: above[0] },
      createElement(Markdown, { src: body, webSearchResults: results })
    )
  )
}

let host: HTMLDivElement
let root: ReturnType<typeof createRoot>
const send = vi.fn(async (_opts: SendMessageOptions) => {})
const messages: ChatMessage[] = []

beforeEach(() => {
  handleCopy.mockClear()
  host = document.createElement('div')
  document.body.append(host)
  root = createRoot(host)
})

afterEach(async () => {
  await act(async () => root.unmount())
  host.remove()
})

const show = (node: ReactElement) =>
  act(async () =>
    root.render(
      createElement(
        JotaiProvider,
        null,
        createElement(InteractiveProvider, { messages, status: 'idle', send }, node)
      )
    )
  )
const byId = (id: string) => host.querySelector<HTMLElement>(`[data-testid="${id}"]`)
const allById = (id: string) => Array.from(host.querySelectorAll<HTMLElement>(`[data-testid="${id}"]`))

describe('illustrated steps in a reply', () => {
  it('are drawn as a numbered list in place of the code, with the title', async () => {
    await show(createElement(Turn, { body: `How to:\n\n${fence('exodus-steps', STEPS)}`, results: RESULTS }))
    expect(byId(TEST_IDS.chat.richBlocks.steps)).not.toBeNull()
    expect(host.querySelector('pre')).toBeNull()
    expect(allById(TEST_IDS.chat.richBlocks.step)).toHaveLength(4)
    expect(host.textContent).toContain('Replacing the strings')
    expect(host.textContent).toContain('Tune up slowly.')
  })

  it("draws a picture only when it is one of the run's search thumbnails", async () => {
    await show(createElement(Turn, { body: fence('exodus-steps', STEPS), results: RESULTS }))
    const pictures = allById(TEST_IDS.chat.richBlocks.stepImage)
    expect(pictures).toHaveLength(1)
    expect(pictures[0].querySelector('img')?.getAttribute('src')).toBe('https://imgs.search.brave.com/peg.jpg')
    // The second step's picture is an image result's *original*: not a thumbnail, not drawn.
    expect(host.innerHTML).not.toContain('original/bridge.jpg')
    // The third is a Brave URL this run never returned.
    expect(host.innerHTML).not.toContain('not-from-this-run')
    // No placeholder either: a dropped picture is nothing, not a "Load image" button.
    expect(byId(TEST_IDS.chat.remoteImage.placeholder)).toBeNull()
  })

  it('draws no pictures when the run searched nothing', async () => {
    await show(createElement(Turn, { body: fence('exodus-steps', STEPS) }))
    expect(allById(TEST_IDS.chat.richBlocks.step)).toHaveLength(4)
    expect(allById(TEST_IDS.chat.richBlocks.stepImage)).toHaveLength(0)
  })

  it('a second block in the reply stays code', async () => {
    await show(createElement(Turn, { body: `${fence('exodus-steps', STEPS)}\n\n${fence('exodus-stock', STOCK)}` }))
    expect(byId(TEST_IDS.chat.richBlocks.steps)).not.toBeNull()
    expect(byId(TEST_IDS.chat.richBlocks.stock)).toBeNull()
    expect(host.querySelector('pre')).not.toBeNull()
  })
})

describe('a stock chart in a reply', () => {
  it("is TradingView's embed in a sandboxed frame, with the note and the symbol's page under it", async () => {
    await show(createElement(Turn, { body: fence('exodus-stock', STOCK) }))
    const frame = byId(TEST_IDS.chat.richBlocks.stockFrame)
    expect(frame?.getAttribute('src')).toBe(
      tradingViewEmbedUrl({ symbol: 'NASDAQ:AAPL', range: '12M', theme: 'light', locale: 'en' })
    )
    expect(frame?.getAttribute('sandbox')).toBe('allow-scripts allow-same-origin')
    expect(frame?.getAttribute('referrerpolicy')).toBe('no-referrer')
    expect(frame?.getAttribute('height')).toBe('220')
    expect(host.textContent).toContain('Up 12% since the call.')
    expect(host.textContent).toContain('richBlocks.chartBy')
    const link = host.querySelector<HTMLAnchorElement>('a[target="_blank"]')
    expect(link?.getAttribute('href')).toBe(tradingViewSymbolPageUrl('NASDAQ:AAPL'))
    expect(host.querySelector('pre')).toBeNull()
  })

  it('takes 1D when the block names no range', async () => {
    await show(createElement(Turn, { body: fence('exodus-stock', { symbol: 'NYSE:BRK.B' }) }))
    expect(byId(TEST_IDS.chat.richBlocks.stockFrame)?.getAttribute('src')).toContain('%22dateRange%22%3A%221D%22')
  })

  it('falls back to a card when the frame fails', async () => {
    await show(createElement(Turn, { body: fence('exodus-stock', STOCK) }))
    await act(async () => {
      byId(TEST_IDS.chat.richBlocks.stockFrame)?.dispatchEvent(new Event('error'))
    })
    expect(byId(TEST_IDS.chat.richBlocks.stockFrame)).toBeNull()
    const fallback = byId(TEST_IDS.chat.richBlocks.stockFallback)
    expect(fallback?.textContent).toContain('NASDAQ:AAPL')
    expect(fallback?.textContent).toContain('richBlocks.chartUnavailable')
    expect(byId(TEST_IDS.chat.richBlocks.stock)?.getAttribute('data-state')).toBe('failed')
    // The note and the page link stay.
    expect(host.textContent).toContain('Up 12% since the call.')
  })

  it('falls back when the frame says nothing for ten seconds', async () => {
    vi.useFakeTimers()
    try {
      await show(createElement(Turn, { body: fence('exodus-stock', STOCK) }))
      await act(async () => {
        vi.advanceTimersByTime(10_001)
      })
      expect(byId(TEST_IDS.chat.richBlocks.stockFallback)).not.toBeNull()
    } finally {
      vi.useRealTimers()
    }
  })

  it('a symbol the widget would not take stays code', async () => {
    await show(createElement(Turn, { body: fence('exodus-stock', { symbol: 'nasdaq:aapl' }) }))
    expect(byId(TEST_IDS.chat.richBlocks.stock)).toBeNull()
    expect(host.querySelector('pre')).not.toBeNull()
  })
})

describe('copy and read aloud take the block’s words', () => {
  it("Copy writes the stock block's symbol and note, not its JSON", async () => {
    const content = `Here:\n\n${fence('exodus-stock', STOCK)}`
    await show(createElement(MessageAction, { content }))
    const row = byId(TEST_IDS.chat.messageAction)
    await act(async () => row?.querySelector('button')?.click())
    expect(handleCopy).toHaveBeenCalledTimes(1)
    const copied = handleCopy.mock.calls[0]![0] as string
    expect(copied).toContain('NASDAQ:AAPL — Up 12% since the call.')
    expect(copied).not.toContain('exodus-stock')
  })
})
```

- [ ] **Step 4: Run it to see it fail**

Run: `bunx vitest run tests/unit/renderer/components/chat/rich-blocks.test.ts`
Expected: FAIL — `TEST_IDS.chat.richBlocks` is undefined until Step 2 is in (then: the steps fence renders as `<pre>`).

- [ ] **Step 5: The thumbnail set and its context (`remote-image.tsx`)**

After `allowedImageUrls` add:

```ts
/**
 * The thumbnails a run's search returned — a page's thumbnail, a media
 * result's thumbnail — and nothing else: what a step's picture may be. A
 * media result's original `url`, which `allowedImageUrls` admits for a
 * Markdown image, is left out on purpose: an original is a hot-link the
 * source site may refuse or swap (owner, 2026-10-07).
 */
export function searchThumbnailUrls(
  webSearchResults: WebSearchResult[] | undefined
): ReadonlySet<string> | null {
  if (!webSearchResults || webSearchResults.length === 0) return null
  const urls = new Set<string>()
  const add = (src: string | undefined) => {
    const href = httpsHref(src)
    if (href) urls.add(href)
  }
  for (const result of webSearchResults) {
    add(result.thumbnail)
    for (const media of result.media ?? []) add(media.thumbnailUrl)
  }
  return urls.size > 0 ? urls : null
}

/** Provided by `Markdown` beside `AllowedImageUrlsContext`, for the same reason. */
export const SearchThumbnailUrlsContext =
  createContext<ReadonlySet<string> | null>(null)

/** `src` in `URL.href` form when it is one of the thumbnails; null otherwise. */
export function thumbnailHref(
  src: string,
  thumbnails: ReadonlySet<string> | null
): string | null {
  const href = httpsHref(src)
  return href !== null && thumbnails?.has(href) ? href : null
}
```

In `markdown.tsx`: import `SearchThumbnailUrlsContext, searchThumbnailUrls` from `./remote-image`; after `allowedUrls` add

```ts
  const thumbnailUrls = useMemo(
    () => searchThumbnailUrls(webSearchResults),
    [webSearchResults]
  )
```

and wrap the section one level deeper: `<AllowedImageUrlsContext.Provider value={allowedUrls}><SearchThumbnailUrlsContext.Provider value={thumbnailUrls}><section …>…</section></SearchThumbnailUrlsContext.Provider></AllowedImageUrlsContext.Provider>`.

- [ ] **Step 6: `steps-block.tsx`**

```tsx
import { TEST_IDS } from '@exodus/shared/constants/test-ids'
import type { StepsBlock as StepsBlockData } from '@exodus/shared/types/interactive'
import { useContext } from 'react'
import { useTranslation } from 'react-i18next'

import {
  RemoteImage,
  SearchThumbnailUrlsContext,
  thumbnailHref
} from '@/components/markdown/remote-image'

/**
 * A reply's illustrated steps (`exodus-steps`): a numbered list, each step
 * its text and, when its picture is one of the run's search thumbnails, that
 * picture — loaded on sight by `RemoteImage`, which admits the same URLs. A
 * picture that is anything else (an original, a URL the run never saw) is
 * dropped, never fetched, never a placeholder (spec 2026-10-07 §2.1).
 */
export function StepsBlock({ block }: { block: StepsBlockData }) {
  const { t } = useTranslation('chat')
  const thumbnails = useContext(SearchThumbnailUrlsContext)
  const title = block.title?.trim()
  return (
    <section
      data-interactive="steps"
      data-testid={TEST_IDS.chat.richBlocks.steps}
      className="bg-card text-card-foreground rounded-2xl border p-4"
    >
      {title && <p className="mb-3 text-sm font-semibold text-pretty">{title}</p>}
      <ol className="flex flex-col gap-3">
        {block.steps.map((step, i) => {
          const picture = step.image ? thumbnailHref(step.image, thumbnails) : null
          return (
            <li
              // Steps never reorder; the place is the identity.
              // eslint-disable-next-line react/no-array-index-key
              key={i}
              data-testid={TEST_IDS.chat.richBlocks.step}
              className="flex items-start gap-3"
            >
              <span
                aria-label={t('richBlocks.stepLabel', { number: i + 1 })}
                className="bg-muted text-muted-foreground mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold tabular-nums"
              >
                {i + 1}
              </span>
              <div className="flex min-w-0 flex-1 flex-col gap-2">
                <p className="text-sm leading-6">{step.text}</p>
                {picture && (
                  <span
                    data-testid={TEST_IDS.chat.richBlocks.stepImage}
                    className="block max-w-72 overflow-hidden rounded-lg"
                  >
                    <RemoteImage src={picture} alt="" className="mb-0" />
                  </span>
                )}
              </div>
            </li>
          )
        })}
      </ol>
    </section>
  )
}
```

- [ ] **Step 7: `stock-block.tsx`**

```tsx
import { TEST_IDS } from '@exodus/shared/constants/test-ids'
import {
  DEFAULT_STOCK_RANGE,
  type StockBlock as StockBlockData
} from '@exodus/shared/types/interactive'
import {
  STOCK_CHART_HEIGHT,
  tradingViewEmbedUrl,
  tradingViewSymbolPageUrl
} from '@exodus/shared/utils/stock-chart'
import { useTheme } from 'next-themes'
import { useEffect, useMemo, useState } from 'react'
import { useTranslation } from 'react-i18next'

/** How long the frame may say nothing before the card gives up on it (offline, blocked). */
export const STOCK_FRAME_TIMEOUT_MS = 10_000

/**
 * A reply's stock chart (`exodus-stock`): TradingView's Mini Chart as its
 * own embed URL in a sandboxed frame — no script of theirs in our document;
 * the frame cannot navigate us or open windows — the model's note under it,
 * and "Chart by TradingView" with the symbol's page. The frame is not lazy:
 * a frame that never starts could not be told from one that failed, and the
 * card falls back to the symbol and the note when it fails or stays silent.
 */
export function StockBlock({ block }: { block: StockBlockData }) {
  const { t, i18n } = useTranslation('chat')
  const { resolvedTheme } = useTheme()
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'failed'>('loading')
  const locale = i18n.resolvedLanguage ?? i18n.language ?? 'en'
  const src = useMemo(
    () =>
      tradingViewEmbedUrl({
        symbol: block.symbol,
        range: block.range ?? DEFAULT_STOCK_RANGE,
        theme: resolvedTheme === 'dark' ? 'dark' : 'light',
        locale
      }),
    [block.symbol, block.range, resolvedTheme, locale]
  )

  useEffect(() => {
    if (phase !== 'loading') return
    const timer = setTimeout(() => setPhase('failed'), STOCK_FRAME_TIMEOUT_MS)
    return () => clearTimeout(timer)
  }, [phase, src])

  const note = block.note?.trim()
  return (
    <section
      data-interactive="stock"
      data-state={phase}
      data-testid={TEST_IDS.chat.richBlocks.stock}
      className="bg-card text-card-foreground overflow-hidden rounded-2xl border"
    >
      {phase === 'failed' ? (
        <div
          data-testid={TEST_IDS.chat.richBlocks.stockFallback}
          className="flex flex-col gap-1 px-4 pt-4"
        >
          <p className="text-sm font-semibold">{block.symbol}</p>
          <p className="text-muted-foreground text-sm">{t('richBlocks.chartUnavailable')}</p>
        </div>
      ) : (
        <iframe
          data-testid={TEST_IDS.chat.richBlocks.stockFrame}
          key={src}
          src={src}
          title={block.symbol}
          sandbox="allow-scripts allow-same-origin"
          referrerPolicy="no-referrer"
          height={STOCK_CHART_HEIGHT}
          className="block w-full border-0"
          onLoad={() => setPhase('loaded')}
          onError={() => setPhase('failed')}
        />
      )}
      {note && <p className="px-4 pt-3 text-sm leading-6">{note}</p>}
      <footer className="text-muted-foreground flex items-center justify-between gap-3 px-4 py-2.5 text-xs">
        <span>{t('richBlocks.chartBy')}</span>
        <a
          href={tradingViewSymbolPageUrl(block.symbol)}
          target="_blank"
          rel="noopener noreferrer"
          className="text-primary-ink hover:underline"
        >
          {t('richBlocks.openOnTradingView')}
        </a>
      </footer>
    </section>
  )
}
```

- [ ] **Step 8: The dispatch (`interactive-fence.tsx`)**

Change the shared import to also bring the fence type under another name:

```ts
import {
  findInteractiveBlock,
  interactiveKind,
  trimTrailingBlanks,
  type InteractiveFence as FenceData,
  type InteractiveKind
} from '@exodus/shared/types/interactive'
```

Import the two new components (`./steps-block`, `./stock-block`) and `type { Answered }` from `./interactive-context`. Replace the component's tail (from `const answerable = turn.answerable` to the end) with:

```tsx
  const answerable = turn.answerable
  const answer: AnswerProps = {
    runId: turn.runId,
    answered: chat.answers.get(turn.runId) ?? null,
    canSubmit: answerable && chat.canSubmit,
    submit: answerable ? chat.submit : () => {}
  }
  return (
    <ErrorBoundary scope="interactive-block" fallback={children}>
      {drawn(fence, answer)}
    </ErrorBoundary>
  )
}

/** What the two asking blocks need besides their data; the steps and the chart need nothing. */
interface AnswerProps {
  runId: string
  answered: Answered | null
  canSubmit: boolean
  submit: (text: string) => void
}

function drawn(fence: FenceData, answer: AnswerProps): ReactNode {
  switch (fence.kind) {
    case 'ask':
      return <QuestionnaireBlock block={fence.block} {...answer} />
    case 'confirm':
      return <ConfirmationBlock block={fence.block} {...answer} />
    case 'steps':
      return <StepsBlock block={fence.block} />
    case 'stock':
      return <StockBlock block={fence.block} />
  }
}
```

Update the component's doc line in `Pre` (markdown.tsx): `// A reply's block — a questionnaire, a confirmation, steps or a chart: the control, or this code when it is not the turn's block (see interactive-fence.tsx).`

- [ ] **Step 9: Run the render tests**

Run: `bunx vitest run tests/unit/renderer/components/chat/rich-blocks.test.ts tests/unit/renderer/components/chat/interactive-blocks.test.ts`
Expected: PASS but for `copy and read aloud…` (Task 5 wires `withBlockText`); everything in `interactive-blocks.test.ts` still passes. If the copy test is the only failure, continue — Task 5's commit turns it green; do not commit a red test file: mark that one `it.skip` in this task's commit and un-skip it in Task 5.

- [ ] **Step 10: Typecheck, format, lint, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
bun run typecheck:web && bun run typecheck:shared
bunx oxfmt src/renderer/components/chat/interactive src/renderer/components/markdown packages/shared/src/constants tests/unit/renderer/components/chat && bunx oxlint src/renderer/components/chat/interactive src/renderer/components/markdown
bunx vitest run tests/unit/renderer/components/chat tests/unit/shared/constants
git add packages/shared/src/i18n/locales/*/chat.json packages/shared/src/i18n/locales/*/lock.json packages/shared/src/constants/test-ids.ts src/renderer/components/markdown/remote-image.tsx src/renderer/components/markdown/markdown.tsx src/renderer/components/chat/interactive/interactive-fence.tsx src/renderer/components/chat/interactive/steps-block.tsx src/renderer/components/chat/interactive/stock-block.tsx tests/unit/renderer/components/chat/rich-blocks.test.ts
git commit -F - <<'EOF'
feat(chat): illustrated steps and a stock chart drawn in a reply — exodus-steps as a numbered card whose pictures are only the run's own search thumbnails (an original is dropped, never fetched), exodus-stock as TradingView's embed in a sandboxed frame with the note and the symbol's page, a card in its place when the frame fails; the strings in ten languages

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```
Expected: 20 locale files + 7 source/test files. (`tests/unit/shared/constants` — the test-id linkage — may still fail on `entityLink`/`entityPanel` until Task 5; if so, run it at the end of Task 5 instead and note it in your report.)

### Task 5: Desktop renderer — the entity link and its panel, the block's words for Copy and read-aloud, the privacy line

**Files:**
- Create: `src/renderer/services/entity-service.ts`, `src/renderer/components/chat/interactive/entity-link.tsx`
- Modify: `src/renderer/components/markdown/markdown.tsx` (`urlTransform`, the `a` renderer), `src/renderer/components/chat/message-action.tsx`, `src/renderer/components/chat/audio-player.tsx`, `src/renderer/components/settings/settings-form/lock-privacy.tsx`, `docs/security-hardening.md`
- Test: `tests/unit/renderer/components/chat/rich-blocks.test.ts` (extend), `tests/unit/shared/constants` (the linkage test, now green)

**Interfaces:**
- Consumes: `entityTitle`, `wikipediaLang` (Task 1), `EntitySummary` (Task 1), the route (Task 2), `withBlockText` (Task 1), `TEST_IDS.chat.richBlocks.entityLink|entityPanel`, `chat:richBlocks.*`, `lock:privacy.thirdParty` (Task 4), `fetcher` (`@exodus/shared/utils/http`), `useQuery`, `Popover*` (`@/components/ui/popover`), `defaultUrlTransform` (react-markdown).
- Produces: `markdownUrlTransform(url): string`; `EntityLink({ title, children })`; `EntityPanel({ title })` (exported for its test); `getEntitySummary(title, lang): Promise<EntitySummary>`.

- [ ] **Step 1: Extend the tests (failing)**

In `rich-blocks.test.ts`, add after the imports:

```ts
import type { EntitySummary } from '@exodus/shared/types/entity'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const getEntitySummary = vi.fn<(title: string, lang: string) => Promise<EntitySummary>>()
vi.mock('@/services/entity-service', () => ({
  getEntitySummary: (title: string, lang: string) => getEntitySummary(title, lang)
}))
```

and `const { EntityPanel } = await import('@/components/chat/interactive/entity-link')` beside the other awaited imports. Then a new describe:

```ts
describe('an entity link in a reply', () => {
  it('is a button that opens the panel, never an anchor to entity:', async () => {
    await show(createElement(Turn, { body: 'Ask [Marie Curie](entity:Marie_Curie) or [Kyoto](entity:Kyoto).' }))
    const links = allById(TEST_IDS.chat.richBlocks.entityLink)
    expect(links.map((l) => l.getAttribute('data-entity'))).toEqual(['Marie_Curie', 'Kyoto'])
    expect(links[0].tagName).toBe('BUTTON')
    expect(links[0].textContent).toBe('Marie Curie')
    expect(host.querySelector('a[href^="entity:"]')).toBeNull()
  })

  it.each(['entity:../x', 'entity:Marie%20Curie', `entity:${'a'.repeat(201)}`, 'entity:Marie%2FCurie', 'entity:'])(
    'a target that is not a title (%s) is plain text',
    async (href) => {
      await show(createElement(Turn, { body: `See [this](${href}) now.` }))
      expect(allById(TEST_IDS.chat.richBlocks.entityLink)).toHaveLength(0)
      expect(host.querySelector('a')).toBeNull()
      expect(host.textContent).toContain('See this now.')
    }
  )

  it('an ordinary link is still a link', async () => {
    await show(createElement(Turn, { body: '[Wikipedia](https://en.wikipedia.org/wiki/Marie_Curie)' }))
    expect(host.querySelector('a')?.getAttribute('href')).toBe('https://en.wikipedia.org/wiki/Marie_Curie')
  })
})

describe('the entity panel', () => {
  const client = () => new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const panel = (title: string) =>
    createElement(QueryClientProvider, { client: client() }, createElement(EntityPanel, { title }))

  it("asks the computer for the title in the app's Wikipedia language and draws the summary", async () => {
    getEntitySummary.mockResolvedValue({
      title: 'Marie Curie',
      extract: 'Polish and naturalised-French physicist.',
      description: 'Physicist (1867–1934)',
      thumbnail: { source: 'https://upload.wikimedia.org/x.jpg', width: 330, height: 448 },
      url: 'https://en.wikipedia.org/wiki/Marie_Curie',
      lang: 'en'
    })
    await show(panel('Marie_Curie'))
    await act(async () => {
      await Promise.resolve()
    })
    expect(getEntitySummary).toHaveBeenCalledWith('Marie_Curie', 'en')
    const node = byId(TEST_IDS.chat.richBlocks.entityPanel)
    expect(node?.textContent).toContain('Marie Curie')
    expect(node?.textContent).toContain('Polish and naturalised-French physicist.')
    expect(node?.querySelector('img')?.getAttribute('src')).toBe('https://upload.wikimedia.org/x.jpg')
    expect(node?.querySelector('a')?.getAttribute('href')).toBe('https://en.wikipedia.org/wiki/Marie_Curie')
    expect(node?.textContent).toContain('richBlocks.readMore')
  })

  it('says when Wikipedia has nothing, and when it could not be reached', async () => {
    getEntitySummary.mockResolvedValue({ title: 'Nobody Here', extract: null, description: null, thumbnail: null, url: null, lang: 'en' })
    await show(panel('Nobody_Here'))
    await act(async () => {
      await Promise.resolve()
    })
    expect(byId(TEST_IDS.chat.richBlocks.entityPanel)?.textContent).toContain('richBlocks.entityNothing')

    getEntitySummary.mockRejectedValue(new Error('HTTP 503'))
    await show(panel('Marie_Curie'))
    await act(async () => {
      await Promise.resolve()
    })
    expect(byId(TEST_IDS.chat.richBlocks.entityPanel)?.textContent).toContain('richBlocks.entityFailed')
  })

  it('cuts a long extract at 600 characters', async () => {
    getEntitySummary.mockResolvedValue({ title: 'X', extract: 'y'.repeat(700), description: null, thumbnail: null, url: null, lang: 'en' })
    await show(panel('X'))
    await act(async () => {
      await Promise.resolve()
    })
    expect(byId(TEST_IDS.chat.richBlocks.entityPanel)?.textContent).toContain('y'.repeat(600) + '…')
    expect(byId(TEST_IDS.chat.richBlocks.entityPanel)?.textContent).not.toContain('y'.repeat(601))
  })
})
```

Un-skip the Copy test if Task 4 skipped it. If `await Promise.resolve()` is not enough for react-query to settle in your run, use `await vi.waitFor(() => expect(getEntitySummary).toHaveBeenCalled())` and then `await vi.waitFor(() => expect(byId(…)?.textContent).toContain(…))` instead.

- [ ] **Step 2: Run it to see it fail**

Run: `bunx vitest run tests/unit/renderer/components/chat/rich-blocks.test.ts`
Expected: FAIL — `entity-link` module not found; the Copy test still red.

- [ ] **Step 3: `entity-service.ts`**

```ts
import type { EntitySummary } from '@exodus/shared/types/entity'
import { fetcher } from '@exodus/shared/utils/http'

/** Wikipedia's summary of `title` in `lang` (then English), through the computer's `GET /api/v1/entity/:title`. */
export const getEntitySummary = (title: string, lang: string) =>
  fetcher<EntitySummary>(
    `/api/v1/entity/${encodeURIComponent(title)}?lang=${encodeURIComponent(lang)}`
  )
```

- [ ] **Step 4: `entity-link.tsx`**

```tsx
import { TEST_IDS } from '@exodus/shared/constants/test-ids'
import { entityTitle, wikipediaLang } from '@exodus/shared/utils/entity-link'
import { useQuery } from '@tanstack/react-query'
import { type ReactNode, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { defaultUrlTransform } from 'react-markdown'

import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { getEntitySummary } from '@/services/entity-service'

/** The most of an extract the panel shows; "Read more" has the rest. */
const EXTRACT_MAX = 600
const DAY_MS = 24 * 60 * 60 * 1000

/**
 * react-markdown's URL rule, plus ours: a valid `entity:` href passes
 * through to the `a` renderer (which draws it as `EntityLink`, never as an
 * anchor); everything else is the default's call — `http(s)`, `mailto` and
 * a few more pass, any other scheme is emptied.
 */
export function markdownUrlTransform(url: string): string {
  return entityTitle(url) !== null ? url : defaultUrlTransform(url)
}

/**
 * `[Marie Curie](entity:Marie_Curie)` in a reply: the name, dotted under,
 * opening a popover with Wikipedia's summary (spec 2026-10-07 §2.2). The
 * summary is fetched when the popover opens, never when the link is drawn.
 */
export function EntityLink({ title, children }: { title: string; children: ReactNode }) {
  const [open, setOpen] = useState(false)
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger
        data-testid={TEST_IDS.chat.richBlocks.entityLink}
        data-entity={title}
        className="text-primary-ink cursor-pointer underline decoration-dotted underline-offset-4 hover:decoration-solid"
      >
        {children}
      </PopoverTrigger>
      <PopoverContent align="start" className="w-80 p-0">
        {open && <EntityPanel title={title} />}
      </PopoverContent>
    </Popover>
  )
}

/** What the popover holds: loading, the summary, "nothing found", or "could not reach". */
export function EntityPanel({ title }: { title: string }) {
  const { t, i18n } = useTranslation('chat')
  const lang = wikipediaLang(i18n.resolvedLanguage ?? i18n.language ?? 'en')
  const { data, isPending, isError } = useQuery({
    queryKey: ['entity', lang, title],
    queryFn: () => getEntitySummary(title, lang),
    staleTime: DAY_MS
  })
  return (
    <div data-testid={TEST_IDS.chat.richBlocks.entityPanel} className="flex flex-col gap-2 p-4">
      {isPending ? (
        <p className="text-muted-foreground text-sm">{t('richBlocks.entityLoading')}</p>
      ) : isError || !data ? (
        <p className="text-muted-foreground text-sm">{t('richBlocks.entityFailed')}</p>
      ) : data.extract === null ? (
        <>
          <p className="text-sm font-semibold">{data.title}</p>
          <p className="text-muted-foreground text-sm">{t('richBlocks.entityNothing')}</p>
        </>
      ) : (
        <>
          <div className="flex items-start gap-3">
            {data.thumbnail && (
              <img
                src={data.thumbnail.source}
                alt=""
                width={64}
                height={Math.round((64 * data.thumbnail.height) / data.thumbnail.width)}
                className="size-16 shrink-0 rounded-lg object-cover"
              />
            )}
            <div className="min-w-0">
              <p className="text-sm font-semibold">{data.title}</p>
              {data.description && (
                <p className="text-muted-foreground text-xs">{data.description}</p>
              )}
            </div>
          </div>
          <p className="text-sm leading-6">
            {data.extract.length > EXTRACT_MAX
              ? `${data.extract.slice(0, EXTRACT_MAX)}…`
              : data.extract}
          </p>
          {data.url && (
            <a
              href={data.url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary-ink text-sm hover:underline"
            >
              {t('richBlocks.readMore')}
            </a>
          )}
        </>
      )}
    </div>
  )
}
```

(The panel's picture is Wikipedia's own thumbnail, chosen by the route from the article, not written by the model — so it loads on sight, unlike a Markdown image.)

- [ ] **Step 5: `markdown.tsx` — the transform and the `a` renderer**

Import `entityTitle` from `@exodus/shared/utils/entity-link` and `EntityLink, markdownUrlTransform` from `../chat/interactive/entity-link`. In `MarkdownBlock`, give `ReactMarkdown` `urlTransform={markdownUrlTransform}`. Replace the `a` renderer's body:

```tsx
      a({ className, children, node, href, ...rest }: any) {
        // A link still streaming in (see healStreamingTail) is text until
        // its URL is complete.
        if (href === INCOMPLETE_LINK_HREF) return <span>{children}</span>
        // A name that opens a Wikipedia summary (entity-link.tsx): never an
        // `<a href="entity:…">`.
        const entity = entityTitle(href)
        if (entity !== null) return <EntityLink title={entity}>{children}</EntityLink>
        // A scheme the URL rule emptied (`tel:`, `javascript:`, a bad
        // `entity:`): the words alone.
        if (!href) return <span>{children}</span>
        // Styling lives in globals.css `.markdown a` — primary color, no
        // underline by default, underline on hover. The previous always-bold
        // + always-underlined treatment made body text feel cluttered.
        return (
          <a
            {...rest}
            href={href}
            rel="noopener noreferrer"
            target="_blank"
            className={className}
          >
            {children}
          </a>
        )
      },
```

- [ ] **Step 6: Copy and read-aloud take the block's words**

`message-action.tsx`: import `withBlockText` from `@exodus/shared/utils/interactive-plain-text`; in `copyText`'s memo call `withReferences(withBlockText(content), citationSources ?? [], …)`. `audio-player.tsx`: import it too; `textToSpeech(withBlockText(content))`.

- [ ] **Step 7: The privacy line and the security note**

In `lock-privacy.tsx`, as the first child of `<SettingsSection title={t('lock:privacy.title')} plain>` (before the PIN card / rows, whatever `status` says), add:

```tsx
      <p className="text-muted-foreground text-sm">{t('lock:privacy.thirdParty')}</p>
```

In `docs/security-hardening.md`, at the TradingView note (~line 286), add a sentence: `A reply's stock chart (\`exodus-stock\`) is the widget's own embed URL in a sandboxed iframe (\`allow-scripts allow-same-origin\`, \`referrerpolicy=no-referrer\`), built in the renderer from a validated symbol — no TradingView script runs in our document; \`frame-src\` already admits \`https://*.tradingview-widget.com\`.`

- [ ] **Step 8: Run everything that could have moved**

Run: `bunx vitest run tests/unit/renderer/components/chat tests/unit/shared/constants tests/unit/i18n`
Expected: PASS — `rich-blocks.test.ts` whole (the Copy test included), `interactive-blocks.test.ts`, the test-id linkage, the i18n tests.

- [ ] **Step 9: Typecheck, format, lint, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus
bun run typecheck:web
bunx oxfmt src/renderer/components/chat src/renderer/components/markdown src/renderer/components/settings/settings-form src/renderer/services tests/unit/renderer/components/chat && bunx oxlint src/renderer/components/chat/interactive/entity-link.tsx src/renderer/services/entity-service.ts src/renderer/components/markdown/markdown.tsx
git add src/renderer/services/entity-service.ts src/renderer/components/chat/interactive/entity-link.tsx src/renderer/components/markdown/markdown.tsx src/renderer/components/chat/message-action.tsx src/renderer/components/chat/audio-player.tsx src/renderer/components/settings/settings-form/lock-privacy.tsx docs/security-hardening.md tests/unit/renderer/components/chat/rich-blocks.test.ts
git commit -F - <<'EOF'
feat(chat): an entity link in a reply — [Marie Curie](entity:Marie_Curie) is a dotted name that opens a popover with Wikipedia's summary from the computer's entity route (loading, nothing found, could not reach), never an anchor; a target that is not a title is plain text; Copy and read-aloud take a steps or stock block's words instead of its JSON; Lock & Privacy says what TradingView sees

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```

### Task 6: iOS — `InteractiveBlock` learns `steps` and `stock`; the block's words; the chart's URLs

**Files:**
- Modify: `Sources/ChatFeature/Interactive/InteractiveBlock.swift`
- Create: `Sources/ChatFeature/Interactive/InteractivePlainText.swift`, `Sources/ChatFeature/Interactive/StockChart.swift`
- Test: `Tests/ChatFeatureTests/InteractiveBlockTests.swift` (extend), `Tests/ChatFeatureTests/InteractivePlainTextTests.swift`, `Tests/ChatFeatureTests/StockChartTests.swift`

**Interfaces:**
- Consumes: phase 1's `InteractiveBlock`, `InteractiveFence.first(in:)` (with `line`/`closingLine`), `JSText`.
- Produces: `InteractiveBlock.steps(Steps)` / `.stock(Stock)`; `InteractiveBlock.Kind.steps/.stock`, `Kind.isAnswerable: Bool`; `Steps { title: String?; steps: [Step { text: String; image: String? }] }`; `Stock { symbol: String; range: Range?; note: String? }` with `Stock.Range: String, CaseIterable` (`oneDay = "1D"`, `oneMonth = "1M"`, `threeMonths = "3M"`, `twelveMonths = "12M"`, `sixtyMonths = "60M"`, `all = "ALL"`, `static let default = Range.oneDay`); `InteractivePlainText.text(of: InteractiveBlock) -> String?`, `InteractivePlainText.replacingBlock(in: String) -> String`; `StockChart.height: CGFloat = 220`, `StockChart.embedURL(symbol:range:dark:locale:) -> URL?`, `StockChart.symbolPageURL(_:) -> URL?`, `StockChart.tradingViewLocale(_ identifier: String) -> String`, `StockChart.tradingViewLocale(_ locale: Locale) -> String`, `StockChart.allowsNavigation(to: URL?) -> Bool`, `StockChart.isTradingViewSite(_ url: URL?) -> Bool`.

- [ ] **Step 1: Add the vectors (failing)**

In `Tests/ChatFeatureTests/InteractiveBlockTests.swift`, after `confirmCases` add (the same names and sources as the desktop's `STEPS_CASES` / `STOCK_CASES`):

```swift
private let stepsSource =
    #"{"title":"Replacing the strings","steps":[{"text":"Loosen the old string from the tuning peg.","image":"https://imgs.search.brave.com/peg.jpg"},{"text":"Thread the new one through the bridge."},{"text":"Tune up slowly, stretching the string as you go.","image":"https://imgs.search.brave.com/tune.jpg"}]}"#
private let stockSource =
    #"{"symbol":"NASDAQ:AAPL","range":"1D","note":"Up 12% since the earnings call; the gap at Oct 2 is the split."}"#

private func step(_ i: Int, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["text": "Step \(i)"].merging(extra) { $1 }
}
private func steps(_ extra: [String: Any] = [:]) -> String { json(["steps": [step(1), step(2)]].merging(extra) { $1 }) }
private func stock(_ extra: [String: Any] = [:]) -> String { json(["symbol": "NASDAQ:AAPL"].merging(extra) { $1 }) }

private let stepsCases: [(String, String, Bool)] = [
    ("the spec's example", stepsSource, true),
    ("two steps, no title", steps(), true),
    ("one step", steps(["steps": [step(1)]]), false),
    ("twelve steps", steps(["steps": (0..<12).map { step($0) }]), true),
    ("thirteen steps", steps(["steps": (0..<13).map { step($0) }]), false),
    ("a 300-character step", steps(["steps": [step(1, ["text": repeated("x", 300)]), step(2)]]), true),
    ("a 301-character step", steps(["steps": [step(1, ["text": repeated("x", 301)]), step(2)]]), false),
    ("150 emoji (300 UTF-16 units)", steps(["steps": [step(1, ["text": repeated("😀", 150)]), step(2)]]), true),
    ("151 emoji (302 UTF-16 units)", steps(["steps": [step(1, ["text": repeated("😀", 151)]), step(2)]]), false),
    ("a step on two lines", steps(["steps": [step(1, ["text": "a\nb"]), step(2)]]), false),
    ("an empty step", steps(["steps": [step(1, ["text": ""]), step(2)]]), false),
    ("an https picture", steps(["steps": [step(1, ["image": "https://imgs.search.brave.com/x.jpg"]), step(2)]]), true),
    ("an http picture", steps(["steps": [step(1, ["image": "http://example.com/x.jpg"]), step(2)]]), false),
    ("a data: picture", steps(["steps": [step(1, ["image": "data:image/png;base64,AAAA"]), step(2)]]), false),
    ("a picture URL with a space", steps(["steps": [step(1, ["image": "https://example.com/a b.jpg"]), step(2)]]), false),
    ("a 2048-character picture URL", steps(["steps": [step(1, ["image": "https://e.co/" + repeated("a", 2035)]), step(2)]]), true),
    ("a 2049-character picture URL", steps(["steps": [step(1, ["image": "https://e.co/" + repeated("a", 2036)]), step(2)]]), false),
    ("a 200-character title", steps(["title": repeated("t", 200)]), true),
    ("a 201-character title", steps(["title": repeated("t", 201)]), false),
    ("a title on two lines", steps(["title": "a\nb"]), false),
    ("an empty title (none)", steps(["title": ""]), true),
    ("nulls for what is optional", steps(["title": NSNull(), "steps": [step(1, ["image": NSNull()]), step(2)]]), true),
    ("keys it does not know", steps(["colour": "red"]), true),
    ("not JSON", #"{"steps":"#, false),
    ("an array", "[]", false),
]

private let stockCases: [(String, String, Bool)] =
    [
        ("the spec's example", stockSource, true),
        ("a symbol alone", stock(), true),
    ] + ["1D", "1M", "3M", "12M", "60M", "ALL"].map { ("the range \($0)", stock(["range": $0]), true) } + [
        ("a range it does not know (5D)", stock(["range": "5D"]), false),
        ("a lowercase range", stock(["range": "1d"]), false),
        ("a lowercase symbol", stock(["symbol": "nasdaq:aapl"]), false),
        ("a symbol without an exchange", stock(["symbol": "AAPL"]), false),
        ("a symbol with a space", stock(["symbol": "NASDAQ: AAPL"]), false),
        ("a symbol with a slash", stock(["symbol": "NASDAQ:AAPL/../X"]), false),
        ("a symbol with a dot and a dash", stock(["symbol": "TSE:7203.T-A"]), true),
        ("a 40-character symbol", stock(["symbol": "X:" + repeated("A", 38)]), true),
        ("a 41-character symbol", stock(["symbol": "X:" + repeated("A", 39)]), false),
        ("a 300-character note", stock(["note": repeated("n", 300)]), true),
        ("a 301-character note", stock(["note": repeated("n", 301)]), false),
        ("a note on two lines", stock(["note": "a\nb"]), true),
        ("nulls for what is optional", stock(["range": NSNull(), "note": NSNull()]), true),
        ("no symbol", json(["note": "x"]), false),
        ("an array", "[]", false),
    ]
```

Append to `findCases`:

```swift
    ("a steps block", "Here:\n\n```exodus-steps\n\(stepsSource)\n```", .steps),
    ("a stock block", "```exodus-stock\n\(stockSource)\n```", .stock),
    ("a stock block after a questionnaire: the questionnaire", "```exodus-ask\n\(askSource)\n```\n\n```exodus-stock\n\(stockSource)\n```", .ask),
    ("a stock block that does not validate, then steps: none", "```exodus-stock\n{\"symbol\":\"aapl\"}\n```\n\n```exodus-steps\n\(stepsSource)\n```", nil),
```

In `InteractiveBlockTests` add, after `askLimits`:

```swift
    @Test("exodus-steps", arguments: stepsCases)
    func stepsLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.steps, source: source) != nil) == valid, "\(name)")
    }

    @Test("exodus-stock", arguments: stockCases)
    func stockLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.stock, source: source) != nil) == valid, "\(name)")
    }

    @Test("the parsed blocks keep their fields; a missing range is the default, 1D")
    func parsed() throws {
        guard case .steps(let steps)? = InteractiveBlock.parse(.steps, source: stepsSource) else { return #expect(Bool(false)) }
        #expect(steps.steps.count == 3)
        #expect(steps.steps[1].image == nil)
        guard case .stock(let stock)? = InteractiveBlock.parse(.stock, source: stockSource) else { return #expect(Bool(false)) }
        #expect(stock.range == .oneDay)
        guard case .stock(let bare)? = InteractiveBlock.parse(.stock, source: stock()) else { return #expect(Bool(false)) }
        #expect(bare.range == nil)
        #expect((bare.range ?? .default) == .oneDay)
        #expect(InteractiveBlock.Kind.steps.isAnswerable == false)
        #expect(InteractiveBlock.Kind.ask.isAnswerable)
    }
```

(`json()` here uses `JSONSerialization`, which writes `NSNull()` as `null`, as the ask cases already rely on.)

- [ ] **Step 2: Run them to see them fail**

Run: `cd /Users/yanceyleo/Code/exodus/exodus-ios && xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd -only-testing:ChatFeatureTests/InteractiveBlockTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: a build error — `.steps` is not a member of `Kind`.

- [ ] **Step 3: Grow `InteractiveBlock.swift`**

Replace the enum's head through `Confirm` with:

```swift
/// The blocks a reply can carry (specs 2026-10-06 and 2026-10-07): a fenced block whose info string names it
/// (`exodus-ask`, `exodus-confirm`, `exodus-steps`, `exodus-stock`) and whose body is one JSON object. One that
/// validates is drawn natively; anything else stays the code block it is. The desktop has the same rules
/// (`packages/shared/src/types/interactive.ts`), held to the same vectors; lengths are UTF-16 units, as zod counts.
enum InteractiveBlock: Equatable, Sendable {
    case ask(Ask)
    case confirm(Confirm)
    case steps(Steps)
    case stock(Stock)

    enum Kind: String, Codable, Sendable {
        case ask, confirm, steps, stock

        /// The fence's info string.
        var language: String { "exodus-" + rawValue }

        init?(language: String) {
            guard language.hasPrefix("exodus-") else { return nil }
            self.init(rawValue: String(language.dropFirst("exodus-".count)))
        }

        /// The two blocks that ask: only they wait for an answer and freeze; the others only show.
        var isAnswerable: Bool { self == .ask || self == .confirm }
    }
```

Keep `Ask` and `Confirm` as they are; after `Confirm` add:

```swift
    /// Illustrated steps: a numbered list, each step a line and, where the run's search returned one, a thumbnail.
    struct Steps: Decodable, Equatable, Sendable {
        struct Step: Decodable, Equatable, Sendable {
            let text: String
            /// A thumbnail among the run's web-search results; the phone drops any other URL (`StepsPictures`).
            let image: String?
        }

        /// Optional; empty is none.
        let title: String?
        let steps: [Step]
    }

    /// A TradingView chart of a symbol, with the model's one-line reading.
    struct Stock: Decodable, Equatable, Sendable {
        /// The Mini Chart widget's own `dateRange` set, as it spells it.
        enum Range: String, Decodable, Sendable, CaseIterable {
            case oneDay = "1D"
            case oneMonth = "1M"
            case threeMonths = "3M"
            case twelveMonths = "12M"
            case sixtyMonths = "60M"
            case all = "ALL"

            /// The finest the widget offers (owner, 2026-10-07).
            static let `default` = Range.oneDay
        }

        /// TradingView's `EXCHANGE:TICKER`.
        let symbol: String
        let range: Range?
        let note: String?
    }
```

`kind`:

```swift
    var kind: Kind {
        switch self {
        case .ask: .ask
        case .confirm: .confirm
        case .steps: .steps
        case .stock: .stock
        }
    }
```

In `parse`, the switch gains:

```swift
            case .steps: (try? decoder.decode(Steps.self, from: data)).map(InteractiveBlock.steps)
            case .stock: (try? decoder.decode(Stock.self, from: data)).map(InteractiveBlock.stock)
```

In `isValid`, after the `.confirm` case:

```swift
        case .steps(let steps):
            Self.optionalOneLine(steps.title, 200) && (2...12).contains(steps.steps.count)
                && steps.steps.allSatisfy { Self.oneLine($0.text, 300) && Self.isHTTPSURL($0.image) }
        case .stock(let stock):
            Self.isSymbol(stock.symbol) && Self.within(stock.note, 300)
```

After `isID` add the helpers:

```swift
    /// An optional one-line text: absent or empty is none; otherwise within `max`.
    private static func optionalOneLine(_ text: String?, _ max: Int) -> Bool {
        guard let text, !text.isEmpty else { return true }
        return oneLine(text, max)
    }
    /// The desktop's `/^https:\/\/\S+$/` within 2048 units, or absent.
    private static func isHTTPSURL(_ text: String?) -> Bool {
        guard let text else { return true }
        let units = Array(text.utf16)
        let prefix = Array("https://".utf16)
        return units.count <= 2048 && units.count > prefix.count && units.starts(with: prefix)
            && !units[prefix.count...].contains(where: JSText.isWhitespace)
    }
    private static let exchangeUnits = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.".utf16)
    private static let tickerUnits = exchangeUnits.union(Set("-".utf16))
    /// The desktop's `/^[A-Z0-9_.]+:[A-Z0-9_.-]+$/` within 40 units.
    private static func isSymbol(_ symbol: String) -> Bool {
        let units = Array(symbol.utf16)
        guard (1...40).contains(units.count), let colon = units.firstIndex(of: UInt16(UInt8(ascii: ":"))) else {
            return false
        }
        let exchange = units[..<colon]
        let ticker = units[(colon + 1)...]
        return !exchange.isEmpty && !ticker.isEmpty && exchange.allSatisfy(exchangeUnits.contains)
            && ticker.allSatisfy(tickerUnits.contains)
    }
```

(A second colon lands in `ticker`, which `tickerUnits` refuses — the regex's `[A-Z0-9_.-]+` says the same.)

- [ ] **Step 4: Run the block tests**

Run the Step 2 command.
Expected: `Test run with N tests … passed`, N ≥ 90.

- [ ] **Step 5: The block's words — tests (failing)**

Create `Tests/ChatFeatureTests/InteractivePlainTextTests.swift`:

```swift
import Testing

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/utils/interactive-plain-text.test.ts — keep them in step.
private let steps =
    #"{"title":"Replacing the strings","steps":[{"text":"Loosen the old string.","image":"https://imgs.search.brave.com/peg.jpg"},{"text":"Thread the new one."}]}"#
private let stock = #"{"symbol":"NASDAQ:AAPL","range":"1D","note":"Up 12% since the call."}"#
private let ask = #"{"title":"T","questions":[{"id":"a","text":"Q?","type":"single","options":["x","y"]}]}"#

private let cases: [(String, String, String)] = [
    ("steps become a titled numbered list", "Here is how:\n\n```exodus-steps\n\(steps)\n```\n\nGood luck.",
     "Here is how:\n\nReplacing the strings\n\n1. Loosen the old string.\n2. Thread the new one.\n\nGood luck."),
    ("steps without a title", "```exodus-steps\n{\"steps\":[{\"text\":\"A\"},{\"text\":\"B\"}]}\n```", "1. A\n2. B"),
    ("a stock block is its symbol and note", "```exodus-stock\n\(stock)\n```", "NASDAQ:AAPL — Up 12% since the call."),
    ("a stock block without a note is its symbol", "```exodus-stock\n{\"symbol\":\"NASDAQ:AAPL\"}\n```", "NASDAQ:AAPL"),
    ("CRLF line ends are made LF", "Intro\r\n\r\n```exodus-stock\r\n\(stock)\r\n```\r\n", "Intro\n\nNASDAQ:AAPL — Up 12% since the call.\n"),
    ("a questionnaire is left as it is", "```exodus-ask\n\(ask)\n```", "```exodus-ask\n\(ask)\n```"),
    ("a second block is code and stays", "```exodus-stock\n\(stock)\n```\n\n```exodus-steps\n\(steps)\n```",
     "NASDAQ:AAPL — Up 12% since the call.\n\n```exodus-steps\n\(steps)\n```"),
    ("a reply without a block is untouched", "Just words.\n\n```js\nlet a = 1\n```", "Just words.\n\n```js\nlet a = 1\n```"),
    ("a block that does not validate stays code", "```exodus-stock\n{\"symbol\":\"aapl\"}\n```", "```exodus-stock\n{\"symbol\":\"aapl\"}\n```"),
]

@Suite("InteractivePlainText: Copy and read-aloud get a block's words")
struct InteractivePlainTextTests {
    @Test("replacingBlock", arguments: cases)
    func replacing(_ name: String, _ markdown: String, _ text: String) {
        #expect(InteractivePlainText.replacingBlock(in: markdown) == text, "\(name)")
    }

    @Test("read-aloud speaks the words, not the JSON")
    func speech() {
        let prose = SpeechText.prose("Here:\n\n```exodus-stock\n\(stock)\n```")
        #expect(prose.contains("NASDAQ:AAPL — Up 12% since the call."))
        #expect(!prose.contains("exodus-stock"))
    }
}
```

- [ ] **Step 6: Run it to see it fail**

Run (after `tuist generate --no-open` with the toolchain prefix, since the test file is new): the ChatFeature test command with `-only-testing:ChatFeatureTests/InteractivePlainTextTests`.
Expected: a build error — `InteractivePlainText` is not in scope.

- [ ] **Step 7: Write `InteractivePlainText.swift`**

```swift
import Foundation

/// What leaves the app as words — Copy, read-aloud — of a reply that holds a steps or stock block (spec 2026-10-07
/// §4): the list a reader would say, the symbol and its reading, in place of the fence's JSON. The questionnaire and
/// the confirmation are left as they are, as in phase 1. The desktop's `interactive-plain-text.ts` writes the same
/// strings, held to the same vectors.
enum InteractivePlainText {
    /// The block's words, or nil for a kind that has none here.
    static func text(of block: InteractiveBlock) -> String? {
        switch block {
        case .steps(let steps):
            let list = steps.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            let title = steps.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? list : title + "\n\n" + list
        case .stock(let stock):
            let note = stock.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? stock.symbol : stock.symbol + " \u{2014} " + note
        case .ask, .confirm:
            return nil
        }
    }

    /// The reply with its block's fence — the lines from ```` ```exodus-… ```` to the closing ```` ``` ```` — replaced by
    /// the block's words; the reply as it was (line ends made `\n`) when it holds no such block.
    static func replacingBlock(in markdown: String) -> String {
        let normalized = JSText.string(JSText.unixLines(markdown))
        guard let fence = InteractiveFence.first(in: normalized), let words = text(of: fence.block) else {
            return normalized
        }
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard fence.line < lines.count, fence.closingLine < lines.count else { return normalized }
        lines.replaceSubrange(fence.line...fence.closingLine, with: [words])
        return lines.joined(separator: "\n")
    }
}
```

Then in `Sources/ChatFeature/ReadAloud.swift` change `SpeechText.prose`:

```swift
    static func prose(_ markdown: String) -> String {
        MarkdownPlainText.strip(withoutCitations(InteractivePlainText.replacingBlock(in: markdown)))
    }
```

and in `Sources/ChatFeature/CopiedAnswer.swift` change `text(of:)`:

```swift
    static func text(of turn: AssistantTurn, heading: String = CopiedAnswer.heading) -> String {
        text(markdown: InteractivePlainText.replacingBlock(in: turn.body), heading: heading) { turn.citation(forMarker: $0) }
    }
```

(`SpeechText`'s doc comment gains: "a steps or stock block is read as its words (`InteractivePlainText`)".)

- [ ] **Step 8: Run the plain-text tests**

Run: the ChatFeature test command with `-only-testing:ChatFeatureTests/InteractivePlainTextTests`.
Expected: `Test run with 10 tests … passed`.

- [ ] **Step 9: The chart's URLs — tests (failing)**

Create `Tests/ChatFeatureTests/StockChartTests.swift`:

```swift
import Foundation
import Testing
import WebKit

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/utils/stock-chart.test.ts — keep them in step.
@Suite("StockChart: TradingView's embed URL and what the chart's web view may do")
struct StockChartTests {
    @Test("the embed URL is byte-identical to the desktop's for the same input")
    func embedURL() throws {
        let url = try #require(StockChart.embedURL(symbol: "TSE:7203", range: .twelveMonths, dark: false, locale: "ja"))
        #expect(
            url.absoluteString
                == "https://www.tradingview-widget.com/embed-widget/mini-symbol-overview/?locale=ja&symbol=TSE%3A7203#%7B%22symbol%22%3A%22TSE%3A7203%22%2C%22dateRange%22%3A%2212M%22%2C%22colorTheme%22%3A%22light%22%2C%22isTransparent%22%3Atrue%2C%22width%22%3A%22100%25%22%2C%22height%22%3A220%2C%22autosize%22%3Afalse%2C%22largeChartUrl%22%3A%22%22%7D"
        )
        let dark = try #require(StockChart.embedURL(symbol: "NASDAQ:AAPL", range: .oneDay, dark: true, locale: "en"))
        #expect(dark.absoluteString.contains("%22colorTheme%22%3A%22dark%22"))
        #expect(dark.absoluteString.contains("%22dateRange%22%3A%221D%22"))
        #expect(dark.host() == "www.tradingview-widget.com")
    }

    @Test("the widget's locale for the app's", arguments: [
        ("en", "en"), ("de", "de"), ("es", "es"), ("fr", "fr"), ("it", "it"), ("ja", "ja"), ("ko", "kr"),
        ("pt-BR", "br"), ("zh-Hant-TW", "zh_TW"), ("zh-Hant-HK", "zh_TW"), ("zh", "zh_CN"), ("nl", "en"), ("", "en"),
        // The phone's own spellings.
        ("zh-Hant", "zh_TW"), ("zh-HK", "zh_TW"), ("zh_TW", "zh_TW"), ("pt_BR", "br"), ("en_US", "en"),
    ])
    func locale(_ identifier: String, _ expected: String) {
        #expect(StockChart.tradingViewLocale(identifier) == expected, "\(identifier)")
    }

    @Test("the symbol's page: the colon a dash")
    func symbolPage() {
        #expect(StockChart.symbolPageURL("NASDAQ:AAPL")?.absoluteString == "https://www.tradingview.com/symbols/NASDAQ-AAPL/")
        #expect(StockChart.symbolPageURL("TSE:7203.T-A")?.absoluteString == "https://www.tradingview.com/symbols/TSE-7203.T-A/")
    }

    @Test("the web view may go to its embed origin and blank, nowhere else")
    func navigation() {
        #expect(StockChart.allowsNavigation(to: URL(string: "https://www.tradingview-widget.com/embed-widget/mini-symbol-overview/?locale=en")))
        #expect(StockChart.allowsNavigation(to: URL(string: "about:blank")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "https://www.tradingview.com/symbols/NASDAQ-AAPL/")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "https://example.com")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "http://www.tradingview-widget.com/")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "exodus://pair?c=1")))
        #expect(!StockChart.allowsNavigation(to: nil))
    }

    @Test("TradingView's own site is what a tap may open in the browser")
    func site() {
        #expect(StockChart.isTradingViewSite(URL(string: "https://www.tradingview.com/symbols/NASDAQ-AAPL/")))
        #expect(StockChart.isTradingViewSite(URL(string: "https://tradingview.com/")))
        #expect(!StockChart.isTradingViewSite(URL(string: "https://eviltradingview.com/")))
        #expect(!StockChart.isTradingViewSite(URL(string: "http://www.tradingview.com/")))
        #expect(!StockChart.isTradingViewSite(URL(string: "https://example.com/?u=tradingview.com")))
        #expect(!StockChart.isTradingViewSite(nil))
    }

    @Test("the content rules compile")
    func rules() async throws {
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "exodus-stock-chart-test", encodedContentRuleList: StockChart.contentRules)
        #expect(rules != nil)
    }
}
```

- [ ] **Step 10: Run it to see it fail**

Run (after `tuist generate --no-open`): the ChatFeature test command with `-only-testing:ChatFeatureTests/StockChartTests`.
Expected: a build error — `StockChart` is not in scope.

- [ ] **Step 11: Write `StockChart.swift`**

```swift
import Foundation

/// TradingView's Mini Chart (`mini-symbol-overview`) as the URL its loader script would put in a frame — the
/// desktop's `stock-chart.ts` byte for byte, held to the same vectors — and what the chart's web view may load and
/// where it may go (spec 2026-10-07 §2.3).
enum StockChart {
    static let height: CGFloat = 220
    static let embedOrigin = "https://www.tradingview-widget.com"
    private static let embedPath = "/embed-widget/mini-symbol-overview/"

    /// The widget's locale codes for the app's languages: Korean is `kr`, Brazilian Portuguese `br`, Chinese by
    /// script or region (`zh_TW` for Traditional), and English for a language it does not have.
    static func tradingViewLocale(_ locale: Locale) -> String {
        guard let language = locale.language.languageCode?.identifier.lowercased() else { return "en" }
        switch language {
        case "en", "de", "es", "fr", "it", "ja": return language
        case "ko": return "kr"
        case "pt": return "br"
        case "zh":
            let script = locale.language.script?.identifier.lowercased()
            let region = locale.region?.identifier.uppercased() ?? ""
            return script == "hant" || ["TW", "HK", "MO"].contains(region) ? "zh_TW" : "zh_CN"
        default: return "en"
        }
    }

    /// The same, from an identifier (`zh-Hant-TW`, `pt_BR`, `en`); empty is English.
    static func tradingViewLocale(_ identifier: String) -> String {
        identifier.isEmpty ? "en" : tradingViewLocale(Locale(identifier: identifier))
    }

    /// The embed URL: `locale` and `symbol` in the query, the settings JSON percent-encoded in the hash, in the
    /// desktop's key order and with its `encodeURIComponent` alphabet, so both apps write the same string.
    static func embedURL(symbol: String, range: InteractiveBlock.Stock.Range, dark: Bool, locale: String) -> URL? {
        let settings =
            "{\"symbol\":\"\(symbol)\",\"dateRange\":\"\(range.rawValue)\",\"colorTheme\":\"\(dark ? "dark" : "light")\","
            + "\"isTransparent\":true,\"width\":\"100%\",\"height\":220,\"autosize\":false,\"largeChartUrl\":\"\"}"
        guard let query = formEncoded(tradingViewLocale(locale)), let encodedSymbol = formEncoded(symbol),
            let hash = settings.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed)
        else { return nil }
        return URL(string: "\(embedOrigin)\(embedPath)?locale=\(query)&symbol=\(encodedSymbol)#\(hash)")
    }

    /// The symbol's own page on TradingView: "Open on TradingView", and where a tap on the chart goes.
    static func symbolPageURL(_ symbol: String) -> URL? {
        guard let colon = symbol.firstIndex(of: ":") else { return nil }
        var page = symbol
        page.replaceSubrange(colon...colon, with: "-")
        return URL(string: "https://www.tradingview.com/symbols/\(page)/")
    }

    /// Where the chart's web view may go: its own embed origin, or blank. Anything else is cancelled — and, when it
    /// is TradingView's own site (a tap on the chart), opened outside the app instead.
    static func allowsNavigation(to url: URL?) -> Bool {
        guard let url else { return false }
        if url.absoluteString == "about:blank" { return true }
        return url.scheme?.lowercased() == "https" && url.host()?.lowercased() == "www.tradingview-widget.com"
    }

    /// TradingView's own pages, which a tap may open in the browser.
    static func isTradingViewSite(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        return host == "tradingview.com" || host.hasSuffix(".tradingview.com")
    }

    /// Every load but TradingView's own hosts is blocked. One rule per host: the rule-list compiler refuses `|`.
    static let contentRules = #"""
        [
          {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "^https://([a-z0-9-]+\\.)*tradingview-widget\\.com/"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^https://([a-z0-9-]+\\.)*tradingview\\.com/"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}
        ]
        """#

    /// JavaScript's `encodeURIComponent` alphabet: unreserved marks stay, everything else is escaped.
    private static let uriComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    /// `URLSearchParams`' alphabet for a value without spaces (a symbol, a locale).
    private static let formAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._")
    private static func formEncoded(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: formAllowed)
    }
}
```

(The symbol's alphabet is `[A-Z0-9_.:-]`, so the only character the JSON would escape is none — `"\(symbol)"` is `JSON.stringify(symbol)`.)

- [ ] **Step 12: Run the chart tests**

Run: the ChatFeature test command with `-only-testing:ChatFeatureTests/StockChartTests`.
Expected: `Test run with 24 tests … passed`. If `rules()` fails to compile the list, fix the regex (WebKit's `url-filter` accepts `.`, `*`, `+`, `?`, `[a-z]` ranges, `( )` groups, `^` and `$`), never drop the test.

- [ ] **Step 13: Run the suites touched, audit, commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
git add Sources/ChatFeature/Interactive/InteractiveBlock.swift Sources/ChatFeature/Interactive/InteractivePlainText.swift Sources/ChatFeature/Interactive/StockChart.swift Sources/ChatFeature/ReadAloud.swift Sources/ChatFeature/CopiedAnswer.swift Tests/ChatFeatureTests/InteractiveBlockTests.swift Tests/ChatFeatureTests/InteractivePlainTextTests.swift Tests/ChatFeatureTests/StockChartTests.swift
git commit -F - <<'EOF'
feat(chat): the block scanner learns illustrated steps (exodus-steps) and a stock chart (exodus-stock), held to the desktop's vectors; Copy and read-aloud get a block's words instead of its JSON; TradingView's embed URL built byte for byte as the desktop builds it, with what the chart's web view may load and where it may go

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```
Expected: the whole ChatFeature suite passes (the full run, not only the new suites); `0 error(s)`; eight files in the commit.

### Task 7: iOS MarkdownKit — `entity:` is a link action of its own

**Files:**
- Modify: `Sources/MarkdownKit/MarkdownLinks.swift`, `Sources/MarkdownKit/MarkdownStyledText.swift`, `Sources/MarkdownKit/MarkdownView.swift`, `Sources/MarkdownKit/MarkdownDocumentView.swift`, `Sources/MarkdownKit/MarkdownAttributedText.swift`
- Test: `Tests/MarkdownKitTests/MarkdownSafetyTests.swift` (extend)

**Interfaces:**
- Consumes: `MarkdownLinkAction`, `MarkdownLinkPolicy`, `MarkdownLinkRouter`, the `markdownAskAbout` entry's shape.
- Produces: `MarkdownLinkAction.entity(String)`; `public enum MarkdownEntityLink { static let scheme = "entity"; static let maxUnits = 200; static func title(from: URL) -> String?; static func isTitle(_: String) -> Bool }`; `MarkdownLinkRouter.onEntityTap: ((String) -> Void)?`; `public struct MarkdownEntityAction: Sendable { let perform: @MainActor @Sendable (String) -> Void }`; `EnvironmentValues.markdownEntityTap: MarkdownEntityAction?`.

- [ ] **Step 1: The vectors (failing)**

In `Tests/MarkdownKitTests/MarkdownSafetyTests.swift`, inside `MarkdownLinkPolicyTests`, add:

```swift
    // The same vectors as the desktop's tests/unit/shared/utils/entity-link.test.ts — keep them in step. (Its
    // "nothing" case is no URL at all here.)
    @Test("an entity link names its article; anything that is not a title is discarded", arguments: [
        ("entity:Marie_Curie", "Marie_Curie"),
        ("entity:Dvořák's_Symphony_No._9_(From_the_New_World)", "Dvořák's_Symphony_No._9_(From_the_New_World)"),
        ("entity:東京", "東京"),
        ("entity:%E6%9D%B1%E4%BA%AC", "東京"),
        ("entity:Category:Physicists", "Category:Physicists"),
        ("entity:" + String(repeating: "a", count: 200), String(repeating: "a", count: 200)),
        ("entity:" + String(repeating: "a", count: 201), nil),
        ("entity:" + String(repeating: "😀", count: 100), nil),
        ("entity:", nil),
        ("entity:Marie/Curie", nil),
        ("entity:..", nil),
        ("entity:.", nil),
        ("entity:_()'", nil),
        ("entity:Marie%2FCurie", nil),
        ("entity:%E6%9D", nil),
        ("entity:Marie_Curie?x=1", nil),
        ("entity:Marie_Curie#History", nil),
        ("entity:Marie Curie", nil),
        ("https://en.wikipedia.org/wiki/Marie_Curie", nil),
        ("ENTITY:Marie_Curie", nil),
    ] as [(String, String?)])
    func entity(_ string: String, _ title: String?) throws {
        let url = try #require(URL(string: string))
        let expected: MarkdownLinkAction = title.map { .entity($0) } ?? (string.hasPrefix("https:") ? .open(url) : .discard)
        #expect(MarkdownLinkPolicy.action(for: url) == expected, "\(string)")
    }

    @Test("the router hands an entity tap its title and calls it handled")
    @MainActor
    func entityRouting() throws {
        let router = MarkdownLinkRouter()
        var tapped: [String] = []
        var opened: [URL] = []
        router.onEntityTap = { tapped.append($0) }
        router.openURL = { opened.append($0) }
        #expect(router.handle(try #require(URL(string: "entity:Marie_Curie"))) == .handled)
        #expect(tapped == ["Marie_Curie"])
        #expect(opened.isEmpty)
        // Without a host handler the tap is still handled — never opened, never discarded into the system.
        router.onEntityTap = nil
        #expect(router.handle(try #require(URL(string: "entity:Kyoto"))) == .handled)
        #expect(opened.isEmpty)
    }
```

(`OpenURLAction.Result` is not `Equatable`; if `== .handled` does not compile, compare through a small `switch` that sets a Bool.)

- [ ] **Step 2: Run them to see them fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme MarkdownKit -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd -only-testing:MarkdownKitTests/MarkdownLinkPolicyTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: a build error — `.entity` is not a member.

- [ ] **Step 3: `MarkdownLinks.swift`**

```swift
import SwiftUI

/// What a tap on a link in model-written text does. Only web and mail links leave the app, like the
/// desktop's `openExternalSafely`: `tel:`, `sms:`, `shortcuts:`, `file:` and other apps' schemes are
/// reachable by injected text, so they are dropped. An `entity:` link opens the host's panel for the article.
enum MarkdownLinkAction: Equatable {
    case citation(Int)
    case open(URL)
    /// `[Marie Curie](entity:Marie_Curie)`: the article's title, decoded.
    case entity(String)
    case discard
}

enum MarkdownLinkPolicy {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    static func action(for url: URL) -> MarkdownLinkAction {
        if let number = MarkdownPreprocessor.citationNumber(from: url) { return .citation(number) }
        if let title = MarkdownEntityLink.title(from: url) { return .entity(title) }
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return .discard }
        return .open(url)
    }
}

/// `[Marie Curie](entity:Marie_Curie)` — a link that opens a short Wikipedia summary (spec 2026-10-07 §2.2). The
/// desktop's `entity-link.ts` rule, held to the same vectors: the scheme is `entity`, written in lowercase; the rest,
/// percent-escapes decoded, is 1–200 UTF-16 units of letters, digits and `_ ( ) . , ' - :` with at least one letter
/// or digit (so `.` and `..` are not titles). Anything else is text, never a link.
public enum MarkdownEntityLink {
    public static let scheme = "entity"
    public static let maxUnits = 200

    public static func title(from url: URL) -> String? {
        let string = url.absoluteString
        guard string.hasPrefix(scheme + ":") else { return nil }
        guard let title = String(string.dropFirst(scheme.count + 1)).removingPercentEncoding else { return nil }
        return isTitle(title) ? title : nil
    }

    public static func isTitle(_ title: String) -> Bool {
        guard (1...maxUnits).contains(title.utf16.count) else { return false }
        var hasWord = false
        for scalar in title.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                .decimalNumber, .letterNumber, .otherNumber:
                hasWord = true
            default:
                guard Self.punctuation.contains(scalar) else { return false }
            }
        }
        return hasWord
    }

    private static let punctuation = Set("_().,'-:".unicodeScalars)
}

/// Owns the one `OpenURLAction` a `MarkdownView` puts in its environment. The action is created once, so
/// its identity never changes while a message streams; the handlers it routes to are refreshed instead.
@MainActor
final class MarkdownLinkRouter {
    var onCitationTap: ((Int) -> Void)?
    var openURL: ((URL) -> Void)?
    /// An entity link's title, for the host's panel; nil handles the tap and does nothing.
    var onEntityTap: ((String) -> Void)?

    private(set) lazy var action = OpenURLAction { [weak self] url in
        MainActor.assumeIsolated { self?.handle(url) ?? .discarded }
    }

    func handle(_ url: URL) -> OpenURLAction.Result {
        switch MarkdownLinkPolicy.action(for: url) {
        case .citation(let number):
            onCitationTap?(number)
            return .handled
        case .open(let url):
            openURL?(url)
            return .handled
        case .entity(let title):
            onEntityTap?(title)
            return .handled
        case .discard:
            return .discarded
        }
    }
}
```

- [ ] **Step 4: The environment entry, the wiring, the kept link**

`MarkdownStyledText.swift`: after `markdownAskAbout` add

```swift
    /// A tap on an `entity:` link, handed the article's title, for the host to open its panel. Nil: the tap does
    /// nothing (a gallery, a sheet).
    @Entry public var markdownEntityTap: MarkdownEntityAction?
```

and after `MarkdownAskAction`:

```swift
public struct MarkdownEntityAction: Sendable {
    public let perform: @MainActor @Sendable (String) -> Void
    public init(_ perform: @escaping @MainActor @Sendable (String) -> Void) { self.perform = perform }
}
```

`MarkdownView.swift` and `MarkdownDocumentView.swift`: add `@Environment(\.markdownEntityTap) private var entityTap` and, beside `router.openURL = …`, `router.onEntityTap = entityTap.map { action in { action.perform($0) } }`. Update `MarkdownView`'s doc comment: "…any other scheme in model-written text is dropped (`MarkdownLinkPolicy`); an `entity:` link goes to `markdownEntityTap`."

`MarkdownAttributedText.swift` (the line "Only what a tap may open is a link"): replace with

```swift
        // Only what a tap may open is a link: anything else in model-written text is text. An entity link keeps
        // its own URL — the tap path reads the title back from it (MarkdownLinkRouter).
        if let link = run.link {
            switch MarkdownLinkPolicy.action(for: link) {
            case .open(let url): attributes[.link] = url
            case .entity: attributes[.link] = link
            case .citation, .discard: break
            }
        }
```

`MarkdownTextTap.offersMenu` stays as it is: an entity has no system menu.

- [ ] **Step 5: Run the MarkdownKit suite**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme MarkdownKit -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: the whole suite passes (the policy vectors, the router, and every earlier safety test — `exodus://`, `javascript:` and the rest still `.discard`).

- [ ] **Step 6: Commit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git add Sources/MarkdownKit/MarkdownLinks.swift Sources/MarkdownKit/MarkdownStyledText.swift Sources/MarkdownKit/MarkdownView.swift Sources/MarkdownKit/MarkdownDocumentView.swift Sources/MarkdownKit/MarkdownAttributedText.swift Tests/MarkdownKitTests/MarkdownSafetyTests.swift
git commit -F - <<'EOF'
feat(markdown): an entity: link is a link action of its own — the article title it names (the desktop's rule, the same vectors) reaches the host through markdownEntityTap instead of being dropped as an unknown scheme; nothing else about which links leave the app changes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```

### Task 8: iOS ChatFeature — the strings, the steps and the chart drawn in an answer

**Files:**
- Create: `/tmp/rich2/add_keys.py` (tooling, not committed)
- Modify: `Resources/App/Localizable.xcstrings` (7 keys)
- Create: `Sources/ChatFeature/Interactive/StepsBlockView.swift`, `Sources/ChatFeature/Interactive/StockBlockView.swift`
- Modify: `Sources/ChatFeature/Interactive/InteractiveBlockView.swift`, `Sources/ChatFeature/AssistantTurnView.swift`
- Test: `Tests/ChatFeatureTests/StepsPicturesTests.swift`, `Tests/ChatFeatureTests/InteractiveRenderingTests.swift` (extend)

**Interfaces:**
- Consumes: `InteractiveBlock.Steps/.Stock`, `StockChart` (Task 6); `SearchMediaPolicy.fetchableURL`, `SearchMediaLoader` (`\.searchMediaLoader`), `CardStyle`, `CardSurface`; `CitationSource.thumbnail`, `WebSearchMedia.thumbnailUrl`; `AssistantTurn.sources`, `AssistantTurn.foot.searchMedia`.
- Produces: `StepsPictures(sources:media:)`, `StepsPictures(urls:)`, `StepsPictures.url(for: InteractiveBlock.Steps.Step) -> URL?`; `StepsBlockView(block:pictures:)`; `StockBlockView(block:)`, `StockChartWebView`, `StockChartPhase`; `InteractiveRendering.fencedBlocks(… pictures: StepsPictures = StepsPictures(), …)`; strings `ios:chat.block.{openOnTradingView, chartBy, chartUnavailable, entityLoading, entityNothing, entityFailed, readMore}`.

- [ ] **Step 1: The strings**

Copy `/tmp/favs/add_keys.py` to `/tmp/rich2/add_keys.py` and replace its `KEYS` list with:

```python
KEYS = [
    ("ios:chat.block.openOnTradingView", "Stock chart card: the footer link to the symbol's page on TradingView.",
     {"en": "Open on TradingView", "de": "Auf TradingView öffnen", "es": "Abrir en TradingView", "fr": "Ouvrir sur TradingView", "it": "Apri su TradingView", "ja": "TradingView で開く", "ko": "TradingView에서 열기", "pt-BR": "Abrir no TradingView", "zh-HK": "喺 TradingView 開啟", "zh-Hant": "在 TradingView 開啟"}),
    ("ios:chat.block.chartBy", "Stock chart card: the footer's credit, which is also the third-party disclosure.",
     {"en": "Chart by TradingView", "de": "Chart von TradingView", "es": "Gráfico de TradingView", "fr": "Graphique TradingView", "it": "Grafico di TradingView", "ja": "チャート: TradingView", "ko": "차트: TradingView", "pt-BR": "Gráfico do TradingView", "zh-HK": "圖表：TradingView", "zh-Hant": "圖表：TradingView"}),
    ("ios:chat.block.chartUnavailable", "Stock chart card: shown in the chart's place when it failed to load (offline, blocked).",
     {"en": "The chart could not be loaded.", "de": "Der Chart konnte nicht geladen werden.", "es": "No se pudo cargar el gráfico.", "fr": "Le graphique n'a pas pu être chargé.", "it": "Impossibile caricare il grafico.", "ja": "チャートを読み込めませんでした。", "ko": "차트를 불러올 수 없습니다.", "pt-BR": "Não foi possível carregar o gráfico.", "zh-HK": "載入唔到圖表。", "zh-Hant": "無法載入圖表。"}),
    ("ios:chat.block.entityLoading", "Entity sheet: while Wikipedia's summary is on its way.",
     {"en": "Loading…", "de": "Wird geladen …", "es": "Cargando…", "fr": "Chargement…", "it": "Caricamento…", "ja": "読み込み中…", "ko": "불러오는 중…", "pt-BR": "Carregando…", "zh-HK": "載入緊…", "zh-Hant": "載入中…"}),
    ("ios:chat.block.entityNothing", "Entity sheet: Wikipedia has no article of that title in the app's language or English.",
     {"en": "Nothing found on Wikipedia.", "de": "Nichts auf Wikipedia gefunden.", "es": "No se encontró nada en Wikipedia.", "fr": "Rien trouvé sur Wikipédia.", "it": "Nessun risultato su Wikipedia.", "ja": "Wikipedia に該当する記事はありません。", "ko": "Wikipedia에서 찾을 수 없습니다.", "pt-BR": "Nada encontrado na Wikipédia.", "zh-HK": "維基百科冇相關條目。", "zh-Hant": "維基百科沒有相關條目。"}),
    ("ios:chat.block.entityFailed", "Entity sheet: the computer could not reach Wikipedia (or the phone its computer).",
     {"en": "Could not reach Wikipedia.", "de": "Wikipedia ist nicht erreichbar.", "es": "No se pudo conectar con Wikipedia.", "fr": "Wikipédia est injoignable.", "it": "Impossibile raggiungere Wikipedia.", "ja": "Wikipedia に接続できませんでした。", "ko": "Wikipedia에 연결할 수 없습니다.", "pt-BR": "Não foi possível acessar a Wikipédia.", "zh-HK": "連接唔到維基百科。", "zh-Hant": "無法連線到維基百科。"}),
    ("ios:chat.block.readMore", "Entity sheet: the link to the article in the browser.",
     {"en": "Read more on Wikipedia", "de": "Mehr auf Wikipedia lesen", "es": "Leer más en Wikipedia", "fr": "Lire la suite sur Wikipédia", "it": "Leggi di più su Wikipedia", "ja": "Wikipedia で続きを読む", "ko": "Wikipedia에서 더 읽기", "pt-BR": "Ler mais na Wikipédia", "zh-HK": "喺維基百科閱讀更多", "zh-Hant": "在維基百科閱讀更多"}),
]
```

Run: `cd /Users/yanceyleo/Code/exodus/exodus-ios && python3 /tmp/rich2/add_keys.py Resources/App/Localizable.xcstrings && python3 scripts/l10n.py audit 2>&1 | tail -1`
Expected: `added 7 keys …`, then `0 error(s)` (warnings about keys not referenced yet are fine until Steps 5–6).

- [ ] **Step 2: The pictures' tests (failing)**

Create `Tests/ChatFeatureTests/StepsPicturesTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import ChatFeature

/// A run's search, as its tool result carries it: a page with a thumbnail, and an image result with an original and
/// a thumbnail.
private func sources() throws -> [CitationSource] {
    let json = #"""
        [{"rank":1,"link":"https://guitars.example/strings","title":"Restringing","snippet":"","hostname":"guitars.example",
          "thumbnail":"https://imgs.search.brave.com/peg.jpg",
          "media":[{"type":"image","title":"bridge","url":"https://cdn.example.com/original/bridge.jpg","sourceUrl":"https://guitars.example/strings","thumbnailUrl":"https://imgs.search.brave.com/bridge-thumb.jpg"}]},
         {"rank":2,"link":"https://other.example/a","title":"Other","snippet":"","hostname":"other.example"}]
        """#
    let values = try JSONDecoder().decode([JSONValue].self, from: Data(json.utf8))
    return values.compactMap(CitationSource.init)
}

private func step(_ image: String?) -> InteractiveBlock.Steps.Step {
    let source = image.map { #"{"text":"S","image":"\#($0)"}"# } ?? #"{"text":"S"}"#
    return try! JSONDecoder().decode(InteractiveBlock.Steps.Step.self, from: Data(source.utf8))
}

@Suite("StepsPictures: a step's picture is one of the run's search thumbnails, or nothing")
struct StepsPicturesTests {
    @Test("thumbnails are pictures; an original, an unknown URL, http and no image are not")
    func pictures() throws {
        let sources = try sources()
        let media = sources.flatMap { $0.media.compactMap(WebSearchMedia.init(json:)) }
        let pictures = StepsPictures(sources: sources, media: media)
        #expect(pictures.url(for: step("https://imgs.search.brave.com/peg.jpg"))?.absoluteString == "https://imgs.search.brave.com/peg.jpg")
        #expect(pictures.url(for: step("https://imgs.search.brave.com/bridge-thumb.jpg")) != nil)
        // The image result's original: not a thumbnail, not drawn.
        #expect(pictures.url(for: step("https://cdn.example.com/original/bridge.jpg")) == nil)
        #expect(pictures.url(for: step("https://imgs.search.brave.com/not-from-this-run.jpg")) == nil)
        #expect(pictures.url(for: step("http://imgs.search.brave.com/peg.jpg")) == nil)
        #expect(pictures.url(for: step(nil)) == nil)
    }

    @Test("a run that searched nothing has no pictures")
    func none() {
        #expect(StepsPictures(sources: [], media: []).url(for: step("https://imgs.search.brave.com/peg.jpg")) == nil)
        #expect(StepsPictures().urls.isEmpty)
    }
}
```

(If `CitationSource.init?(_:)` is not reachable with `compactMap(CitationSource.init)`, write `values.compactMap { CitationSource($0) }`. The `media` items' JSON shape — `type`, `url`, `sourceUrl`, `thumbnailUrl` — is `WebSearchMedia.init?(json:)`'s; check `Sources/Models/ToolResults.swift:409` and use its key names if they differ.)

- [ ] **Step 3: Run it to see it fail**

Run (after `tuist generate --no-open`): the ChatFeature test command with `-only-testing:ChatFeatureTests/StepsPicturesTests`.
Expected: a build error — `StepsPictures` is not in scope.

- [ ] **Step 4: `StepsBlockView.swift`**

```swift
import Models
import SwiftUI
import UIKit

/// The thumbnails a run's search returned — a page's thumbnail, a media result's thumbnail — and nothing else: what
/// a step's picture may be. A media result's original `url`, which `SearchGallery.trustedURLs` admits for the
/// gallery, is left out on purpose: an original is a hot-link the source site may refuse or swap (owner, 2026-10-07).
struct StepsPictures: Equatable, Sendable {
    let urls: Set<URL>

    init(urls: Set<URL> = []) { self.urls = urls }

    init(sources: [CitationSource], media: [WebSearchMedia]) {
        var urls: Set<URL> = []
        for source in sources {
            if let thumbnail = source.thumbnail, let url = SearchMediaPolicy.fetchableURL(thumbnail) { urls.insert(url) }
        }
        for item in media {
            if let thumbnail = item.thumbnailUrl, let url = SearchMediaPolicy.fetchableURL(thumbnail) { urls.insert(url) }
        }
        self.urls = urls
    }

    /// The step's picture when the run's search returned it as a thumbnail; nil otherwise.
    func url(for step: InteractiveBlock.Steps.Step) -> URL? {
        guard let image = step.image, let url = SearchMediaPolicy.fetchableURL(image), urls.contains(url) else {
            return nil
        }
        return url
    }
}

/// A reply's illustrated steps (`exodus-steps`): a numbered card, each step its text and, when its picture is one of
/// the run's search thumbnails, that picture, loaded on sight as the gallery loads its thumbnails. A picture that is
/// anything else is dropped — never fetched, never a tap-to-load (spec 2026-10-07 §2.1).
struct StepsBlockView: View {
    let block: InteractiveBlock.Steps
    let pictures: StepsPictures

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                Text(verbatim: title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(block.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .frame(width: 24, height: 24)
                        .background(.fill.tertiary, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: step.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = pictures.url(for: step) {
                            StepPicture(url: url)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: "\(index + 1). \(step.text)"))
            }
        }
        .padding(CardStyle.inset)
        .modifier(CardSurface())
    }
}

/// One step's thumbnail: a quiet block while it loads, the picture once in, nothing when it failed.
private struct StepPicture: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.searchMediaLoader) private var loader

    var body: some View {
        if !failed {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.fill.quaternary)
                }
            }
            .frame(maxWidth: 280)
            .frame(height: 140)
            .clipShape(CardStyle.innerShape)
            .accessibilityHidden(true)
            .task(id: url) {
                if let cached = loader.cached(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap) {
                    image = cached
                    return
                }
                do {
                    image = try await loader.load(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap)
                } catch {
                    failed = true
                }
            }
        }
    }
}
```

- [ ] **Step 5: `StockBlockView.swift`**

```swift
import SwiftUI
import WebKit

/// How the chart's web view is doing.
enum StockChartPhase: Equatable {
    case loading, loaded, failed
}

/// A reply's stock chart (`exodus-stock`): TradingView's Mini Chart as its own embed URL in a web view that may load
/// nothing but TradingView's hosts and go nowhere else — a tap on the chart opens the symbol's page in the browser —
/// the model's note under it, and "Chart by TradingView" with the page's link (the disclosure the phone has, having
/// no privacy page). When the chart cannot load, the symbol and the note stand in its place.
struct StockBlockView: View {
    let block: InteractiveBlock.Stock

    @State private var phase = StockChartPhase.loading
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if phase == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: block.symbol).font(.headline)
                    Text("ios:chat.block.chartUnavailable").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(CardStyle.inset)
            } else if let url = StockChart.embedURL(
                symbol: block.symbol, range: block.range ?? .default, dark: colorScheme == .dark,
                locale: locale.identifier)
            {
                StockChartWebView(url: url, onPhase: { phase = $0 }, openExternally: { openURL($0) })
                    .frame(height: StockChart.height)
                    .accessibilityLabel(Text(verbatim: block.symbol))
            }
            if let note = block.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(verbatim: note)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, CardStyle.inset)
                    .padding(.top, 12)
            }
            HStack {
                Text("ios:chat.block.chartBy")
                Spacer()
                if let page = StockChart.symbolPageURL(block.symbol) {
                    Link("ios:chat.block.openOnTradingView", destination: page)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, CardStyle.inset)
            .padding(.vertical, 10)
        }
        .modifier(CardSurface())
        // The web view is made once for what the URL is made of; a change of scheme makes it again.
        .id("\(block.symbol)|\(block.range?.rawValue ?? "")|\(colorScheme == .dark)")
    }
}

/// The web view: non-persistent storage, a content rule list that blocks every load but TradingView's hosts
/// (compiled once a launch; without it the chart is not shown — it fails closed), no navigation off the embed origin
/// (TradingView's own pages open in the browser instead), no new windows, and the chat's scrolling, not its own.
struct StockChartWebView: UIViewRepresentable {
    let url: URL
    let onPhase: (StockChartPhase) -> Void
    let openExternally: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPhase: onPhase, openExternally: openExternally) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        context.coordinator.load(url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPhase = onPhase
        context.coordinator.openExternally = openExternally
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        coordinator.loading?.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onPhase: (StockChartPhase) -> Void
        var openExternally: (URL) -> Void
        weak var webView: WKWebView?
        var loading: Task<Void, Never>?
        private var phase = StockChartPhase.loading

        /// Compiled once per launch: a chat with several charts makes a web view for each.
        private static var compiledRules: WKContentRuleList?

        init(onPhase: @escaping (StockChartPhase) -> Void, openExternally: @escaping (URL) -> Void) {
            self.onPhase = onPhase
            self.openExternally = openExternally
        }

        func load(_ url: URL) {
            loading = Task { [weak self] in
                var rules = Self.compiledRules
                if rules == nil {
                    rules = try? await WKContentRuleListStore.default().compileContentRuleList(
                        forIdentifier: "exodus-stock-chart", encodedContentRuleList: StockChart.contentRules)
                    Self.compiledRules = rules
                }
                guard let self, !Task.isCancelled, let webView = self.webView else { return }
                guard let rules else {
                    self.set(.failed)
                    return
                }
                webView.configuration.userContentController.add(rules)
                webView.load(URLRequest(url: url))
                // Ten seconds of silence is a failure (offline, blocked).
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled, self.phase == .loading { self.set(.failed) }
            }
        }

        private func set(_ phase: StockChartPhase) {
            guard self.phase != phase else { return }
            self.phase = phase
            onPhase(phase)
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url
            if StockChart.allowsNavigation(to: url) { return .allow }
            if let url, StockChart.isTradingViewSite(url) { openExternally(url) }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { set(.loaded) }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            set(.failed)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { set(.failed) }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { set(.failed) }

        // MARK: WKUIDelegate

        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, StockChart.isTradingViewSite(url) { openExternally(url) }
            return nil
        }
    }
}
```

- [ ] **Step 6: The dispatch and the turn**

`InteractiveBlockView.swift`:
- `fencedBlocks` gains a parameter after `drafts`: `pictures: StepsPictures = StepsPictures(),` and passes it: `InteractiveBlockView(fence: fence, runId: runId, answered: answered, mode: mode, drafts: drafts, pictures: pictures, sendAnswer: send)`.
- `InteractiveBlockView` gains `let pictures: StepsPictures` (after `drafts`), and its `switch fence.block` two cases:

```swift
            case .steps(let block):
                StepsBlockView(block: block, pictures: pictures)
            case .stock(let block):
                StockBlockView(block: block)
```

- Its doc line: "A reply's block, drawn by its kind: the two that ask send through `sendAnswer`; the steps and the chart only show."

`AssistantTurnView.swift`:
- `asks` becomes:

```swift
    /// The turn holds a block still waiting for its answer, so whether one may be sent changes how it looks. Read only
    /// when `canAnswer` changed (a turn starting or ending), never per streamed frame. Steps and a chart never wait.
    nonisolated var asks: Bool {
        answered == nil && (turn.body.contains("```exodus-ask") || turn.body.contains("```exodus-confirm"))  // l10n:ignore: markdown syntax
    }
```

- In `answer`, after `let placed = …`:

```swift
        // The steps' pictures: only the run's own search thumbnails (StepsPictures); built only for a steps block.
        let pictures = placed?.fence.kind == .steps
            ? StepsPictures(sources: turn.sources, media: turn.foot.searchMedia) : StepsPictures()
```

and `fencedBlocks(…, drafts: drafts, pictures: pictures, sendAnswer: sendAnswer)`.

- [ ] **Step 7: Rendering tests**

In `Tests/ChatFeatureTests/InteractiveRenderingTests.swift` add to its suite (using its `drawnCount` helper):

```swift
    @Test("steps and a chart are drawn as their blocks, once, and a second fence stays code")
    func stepsAndStock() {
        let steps = #"{"steps":[{"text":"A"},{"text":"B"}]}"#
        let stock = #"{"symbol":"NASDAQ:AAPL"}"#
        #expect(drawnCount(["How to:\n\n```exodus-steps\n\(steps)\n```"]) == 1)
        #expect(drawnCount(["```exodus-stock\n\(stock)\n```"]) == 1)
        #expect(drawnCount(["```exodus-stock\n\(stock)\n```\n\n```exodus-steps\n\(steps)\n```"]) == 1)
        #expect(drawnCount(["```exodus-stock\n{\"symbol\":\"aapl\"}\n```"]) == 0)
    }
```

- [ ] **Step 8: Build, test, audit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: the whole suite passes (`StepsPicturesTests`, the new rendering test, everything before); `0 error(s)`; the audit no longer warns about `openOnTradingView`, `chartBy`, `chartUnavailable` (the entity keys stay unreferenced until Task 9).

- [ ] **Step 9: Commit**

```bash
git add Resources/App/Localizable.xcstrings Sources/ChatFeature/Interactive/StepsBlockView.swift Sources/ChatFeature/Interactive/StockBlockView.swift Sources/ChatFeature/Interactive/InteractiveBlockView.swift Sources/ChatFeature/AssistantTurnView.swift Tests/ChatFeatureTests/StepsPicturesTests.swift Tests/ChatFeatureTests/InteractiveRenderingTests.swift
git commit -F - <<'EOF'
feat(chat): illustrated steps and a stock chart drawn in an answer — exodus-steps as a numbered card whose pictures are only the run's own search thumbnails (an original is dropped, never fetched), exodus-stock as TradingView's embed in a web view that loads nothing but TradingView's hosts and goes nowhere else, the note and the symbol's page under it, the symbol and note in its place when it fails; seven strings in ten languages

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```

### Task 9: iOS ChatFeature — the entity sheet

**Files:**
- Create: `Sources/ChatFeature/Interactive/EntitySummary.swift`, `Sources/ChatFeature/Interactive/EntitySheet.swift`
- Modify: `Sources/ChatFeature/ChatDetailView.swift`
- Test: `Tests/ChatFeatureTests/EntitySummaryTests.swift`

**Interfaces:**
- Consumes: `APIClient.get<T: Decodable>(_ path: String, query: [URLQueryItem])`, `MarkdownEntityAction`, `\.markdownEntityTap` (Task 7), `\.searchMediaLoader`, `CardStyle`, strings `ios:chat.block.entity*`, `readMore` (Task 8), `common:action.close`.
- Produces: `EntitySummary: Decodable, Equatable, Sendable { title, extract: String?, description: String?, thumbnail: Thumbnail?, url: String?, lang }`; `@MainActor @Observable final class EntityLoader { init(fetch:); convenience init(apiClient:); func summary(for title: String, lang: String) async throws -> EntitySummary; static func wikipediaLang(for: Locale) -> String }`; `EntitySheet(title: String, loader: EntityLoader?)`; `ChatScreenObjects.entities: EntityLoader`.

- [ ] **Step 1: Tests (failing)**

Create `Tests/ChatFeatureTests/EntitySummaryTests.swift`:

```swift
import Foundation
import Testing

@testable import ChatFeature

@Suite("EntitySummary and EntityLoader: Wikipedia's summary through the computer")
struct EntitySummaryTests {
    @Test("decodes what the route answers, nulls included")
    func decodes() throws {
        let found = #"{"title":"Marie Curie","extract":"Physicist.","description":"Polish-French physicist","thumbnail":{"source":"https://upload.wikimedia.org/x.jpg","width":330,"height":448},"url":"https://en.wikipedia.org/wiki/Marie_Curie","lang":"en"}"#
        let summary = try JSONDecoder().decode(EntitySummary.self, from: Data(found.utf8))
        #expect(summary.title == "Marie Curie")
        #expect(summary.thumbnail?.width == 330)
        #expect(summary.url == "https://en.wikipedia.org/wiki/Marie_Curie")
        let nothing = #"{"title":"Nobody Here","extract":null,"description":null,"thumbnail":null,"url":null,"lang":"en"}"#
        let none = try JSONDecoder().decode(EntitySummary.self, from: Data(nothing.utf8))
        #expect(none.extract == nil)
        #expect(none.thumbnail == nil)
    }

    @Test("Wikipedia's language for the phone's locale", arguments: [
        ("en_US", "en"), ("zh-Hant_TW", "zh"), ("zh-Hant_HK", "zh"), ("pt_BR", "pt"), ("ja_JP", "ja"), ("ko_KR", "ko"),
        ("de", "de"), ("yue", "yue"), ("", "en"),
    ])
    func lang(_ identifier: String, _ expected: String) {
        #expect(EntityLoader.wikipediaLang(for: Locale(identifier: identifier)) == expected, "\(identifier)")
    }

    /// What the fake computer was asked; a class on the main actor, since the loader's fetch is a `@Sendable` closure.
    @MainActor
    private final class Recorder {
        var asked: [(String, String)] = []
        var calls = 0
    }

    @Test("asks the computer once per title and language, and remembers the answer")
    @MainActor
    func caches() async throws {
        let recorder = Recorder()
        let summary = EntitySummary(title: "Kyoto", extract: "A city.", description: nil, thumbnail: nil, url: nil, lang: "en")
        let loader = EntityLoader { title, lang in
            recorder.asked.append((title, lang))
            return summary
        }
        #expect(try await loader.summary(for: "Kyoto", lang: "en") == summary)
        #expect(try await loader.summary(for: "Kyoto", lang: "en") == summary)
        _ = try await loader.summary(for: "Kyoto", lang: "ja")
        #expect(recorder.asked.map(\.0) == ["Kyoto", "Kyoto"])
        #expect(recorder.asked.map(\.1) == ["en", "ja"])
    }

    @Test("a failure is thrown, not remembered")
    @MainActor
    func failure() async {
        let recorder = Recorder()
        let loader = EntityLoader { _, _ in
            recorder.calls += 1
            throw URLError(.notConnectedToInternet)
        }
        await #expect(throws: URLError.self) { try await loader.summary(for: "Kyoto", lang: "en") }
        await #expect(throws: URLError.self) { try await loader.summary(for: "Kyoto", lang: "en") }
        #expect(recorder.calls == 2)
    }
}
```

(`EntitySummary` needs the struct's synthesized memberwise `init`, so declare it without a custom one.)

- [ ] **Step 2: Run it to see it fail**

Run (after `tuist generate --no-open`): the ChatFeature test command with `-only-testing:ChatFeatureTests/EntitySummaryTests`.
Expected: a build error — `EntitySummary` is not in scope.

- [ ] **Step 3: `EntitySummary.swift`**

```swift
import Foundation
import NetworkingKit
import Observation
import SwiftUI

/// What the computer's `GET /api/v1/entity/:title` answers (the desktop's `EntitySummary`): Wikipedia's summary of
/// the article, or `extract == nil` when neither the asked language nor English has it.
struct EntitySummary: Decodable, Equatable, Sendable {
    struct Thumbnail: Decodable, Equatable, Sendable {
        let source: String
        let width: Int
        let height: Int
    }

    let title: String
    let extract: String?
    let description: String?
    let thumbnail: Thumbnail?
    /// The article's page, to read more; nil when nothing was found.
    let url: String?
    let lang: String
}

/// Reads summaries through the computer (the phone has no network of its own but its computer's), once each per
/// title and language for the chat screen's life. A failure is thrown and asked again next time.
@MainActor @Observable
final class EntityLoader {
    typealias Fetch = @MainActor @Sendable (_ title: String, _ lang: String) async throws -> EntitySummary

    private let fetch: Fetch
    private var cache: [String: EntitySummary] = [:]

    init(fetch: @escaping Fetch) { self.fetch = fetch }

    convenience init(apiClient: APIClient) {
        self.init { title, lang in
            // The title is one path component: `appendingPathComponent` percent-encodes it.
            try await apiClient.get("/api/v1/entity/\(title)", query: [URLQueryItem(name: "lang", value: lang)])
        }
    }

    func summary(for title: String, lang: String) async throws -> EntitySummary {
        let key = lang + "/" + title
        if let hit = cache[key] { return hit }
        let summary = try await fetch(title, lang)
        cache[key] = summary
        return summary
    }

    /// Wikipedia's language for the phone's locale: the language code when it is two or three ASCII letters
    /// (`zh-Hant_TW` → `zh`, `pt_BR` → `pt`), else English — the desktop's `wikipediaLang`.
    static func wikipediaLang(for locale: Locale) -> String {
        guard let code = locale.language.languageCode?.identifier.lowercased(), (2...3).contains(code.count),
            code.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return "en" }
        return code
    }
}

extension EnvironmentValues {
    /// The chat screen's reader of entity summaries; nil (a gallery) shows the sheet's "could not reach" state.
    @Entry var entityLoader: EntityLoader?
}
```

- [ ] **Step 4: `EntitySheet.swift`**

```swift
import SwiftUI
import UIKit

/// What a tapped `entity:` link opens: Wikipedia's summary of the article — its picture, title, one-line description
/// and the first paragraph (at most 600 characters), with a link to read on — or "nothing found" / "could not reach".
/// A sheet at medium height, as the spec asks; the summary is fetched when the sheet opens, never when the link is
/// drawn.
struct EntitySheet: View {
    let title: String
    let loader: EntityLoader?

    private enum Phase: Equatable {
        case loading
        case found(EntitySummary)
        case nothing(String)
        case failed
    }

    /// The most of an extract the sheet shows; "Read more" has the rest.
    private static let extractMax = 600

    @State private var phase = Phase.loading
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CardStyle.inset)
            }
            .navigationTitle(Text(verbatim: shownTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: title) { await load() }
    }

    private var shownTitle: String {
        if case .found(let summary) = phase { return summary.title }
        return title.replacingOccurrences(of: "_", with: " ")
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            Text("ios:chat.block.entityLoading").foregroundStyle(.secondary)
        case .failed:
            Text("ios:chat.block.entityFailed").foregroundStyle(.secondary)
        case .nothing:
            Text("ios:chat.block.entityNothing").foregroundStyle(.secondary)
        case .found(let summary):
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if let thumbnail = summary.thumbnail, let url = URL(string: thumbnail.source) {
                        EntityPicture(url: url)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: summary.title).font(.headline)
                        if let description = summary.description, !description.isEmpty {
                            Text(verbatim: description).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if let extract = summary.extract {
                    Text(verbatim: Self.shortened(extract))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let page = summary.url.flatMap(URL.init(string:)) {
                    Button {
                        openURL(page)
                    } label: {
                        Label("ios:chat.block.readMore", systemImage: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    /// The first 600 characters, an ellipsis after a cut.
    static func shortened(_ extract: String) -> String {
        extract.count > extractMax ? String(extract.prefix(extractMax)) + "\u{2026}" : extract
    }

    private func load() async {
        phase = .loading
        guard let loader else {
            phase = .failed
            return
        }
        do {
            let summary = try await loader.summary(for: title, lang: EntityLoader.wikipediaLang(for: locale))
            phase = summary.extract == nil ? .nothing(summary.title) : .found(summary)
        } catch {
            phase = .failed
        }
    }
}

/// Wikipedia's thumbnail of the article — chosen by the route from the article, not written by the model, so it
/// loads on sight, through the search media loader as the gallery's thumbnails do.
private struct EntityPicture: View {
    let url: URL
    @State private var image: UIImage?
    @Environment(\.searchMediaLoader) private var loader

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.fill.quaternary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(CardStyle.innerShape)
        .accessibilityHidden(true)
        .task(id: url) {
            image = loader.cached(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap)
                ?? (try? await loader.load(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap))
        }
    }
}
```

(A `Button` that calls `openURL`, not a `Link`: inside the sheet the environment's `openURL` is the system's, and a Button keeps the row's look.)

- [ ] **Step 5: Wire the chat screen**

`ChatDetailView.swift`:
- `ChatScreenObjects` gains `/// Wikipedia's summaries for entity links, through the same paired session.` `let entities: EntityLoader` and, in its `init`, `entities = EntityLoader(apiClient: apiClient)`.
- A state and a request type, next to `sourcesSheet`:

```swift
    /// The entity link tapped in an answer, whose Wikipedia summary a sheet shows.
    @State private var entity: EntityRequest?
```

and at file scope: `struct EntityRequest: Identifiable { let title: String; var id: String { title } }`.
- Where `.environment(\.markdownAskAbout, …)` is set on the transcript, add

```swift
                .environment(\.markdownEntityTap, MarkdownEntityAction { title in entity = EntityRequest(title: title) })
```

- Beside `.sheet(item: $sourcesSheet)`, add

```swift
        .sheet(item: $entity) { EntitySheet(title: $0.title, loader: objects.entities) }
```

- [ ] **Step 6: Run the tests, build the app, audit**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH tuist generate --no-open
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd -only-testing:ChatFeatureTests/EntitySummaryTests 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `Test run with 13 tests … passed`; `BUILD SUCCEEDED`; `0 error(s)` with no warning left about `ios:chat.block.*`.

- [ ] **Step 7: Commit**

```bash
git add Sources/ChatFeature/Interactive/EntitySummary.swift Sources/ChatFeature/Interactive/EntitySheet.swift Sources/ChatFeature/ChatDetailView.swift Tests/ChatFeatureTests/EntitySummaryTests.swift
git commit -F - <<'EOF'
feat(chat): an entity link in an answer opens a sheet with Wikipedia's summary — picture, title, description, the first paragraph and a link to read on — read through the computer's entity route in the phone's language, remembered for the screen's life; nothing found and could not reach have their own words

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```

### Task 10: iOS — gallery runs, screenshots, the device checklist

**Files:**
- Modify: `Sources/ChatFeature/MessageGalleryInteractive.swift`, `Tests/ChatFeatureTests/MessageGalleryInteractiveTests.swift`
- Create: `/tmp/rich2/shots.sh` (tooling), `docs/chat-rich-blocks-device-checklist.md`

**Interfaces:**
- Consumes: `MessageGalleryFixtures.runs`, `interactiveRuns`, `codeRuns`, `interactiveRun(id:question:reply:then:)`, `segments(_:)`, `CopiedAnswer.text(of:)`.
- Produces: runs `steps`, `entity`, `stock`; `MessageGalleryFixtures.interactiveNames`; `-MessageGallerySection steps|entity|stock`.

- [ ] **Step 1: Rewrite the gallery test (failing)**

Replace `namedSections` in `Tests/ChatFeatureTests/MessageGalleryInteractiveTests.swift` with:

```swift
    @Test("the interactive runs are named, in order, at the end; the code run sits just before them; another name is none")
    func namedSections() {
        let count = MessageGalleryFixtures.runs.count
        let names = MessageGalleryFixtures.interactiveNames
        #expect(names == ["ask", "confirm", "answered", "steps", "entity", "stock"])
        #expect(MessageGalleryFixtures.interactiveRuns.count == names.count)
        for (offset, name) in names.enumerated() {
            #expect(MessageGalleryFixtures.namedSection(name) == count - names.count + offset, "\(name)")
        }
        #expect(MessageGalleryFixtures.namedSection("code") == count - names.count - MessageGalleryFixtures.codeRuns.count)
        #expect(MessageGalleryFixtures.namedSection("questionnaire") == nil)
    }

    @Test("the steps run's pictures are thumbnails its own search returned, so the gallery shows them")
    func stepsPictures() throws {
        let index = try #require(MessageGalleryFixtures.namedSection("steps"))
        let segments = MessageGalleryFixtures.segments(MessageGalleryFixtures.runs[index].json)
        let turn = try #require(
            segments.compactMap { if case .assistantTurn(let turn) = $0, turn.body.contains("```exodus-steps") { turn } else { nil } }.first)
        let placed = try #require(InteractiveRendering.placed(in: [turn.body]))
        guard case .steps(let block) = placed.fence.block else { return #expect(Bool(false)) }
        let pictures = StepsPictures(sources: turn.sources, media: turn.foot.searchMedia)
        #expect(block.steps.compactMap(pictures.url(for:)).count == 2)
    }

    @Test("Copy of the stock run's answer is its words, not its JSON")
    func stockCopy() throws {
        let index = try #require(MessageGalleryFixtures.namedSection("stock"))
        let segments = MessageGalleryFixtures.segments(MessageGalleryFixtures.runs[index].json)
        let turn = try #require(
            segments.compactMap { if case .assistantTurn(let turn) = $0, turn.body.contains("```exodus-stock") { turn } else { nil } }.first)
        let copied = CopiedAnswer.text(of: turn)
        #expect(copied.contains("NASDAQ:AAPL \u{2014} "))
        #expect(!copied.contains("exodus-stock"))
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: the ChatFeature test command with `-only-testing:ChatFeatureTests/MessageGalleryInteractiveTests`.
Expected: a build error — `interactiveNames` is not a member.

- [ ] **Step 3: The runs**

In `Sources/ChatFeature/MessageGalleryInteractive.swift`, extend the doc comment ("…`-MessageGallerySection ask|confirm|answered|steps|entity|stock` scrolls to one; `steps` has a search behind it whose thumbnails the steps use, `entity` two entity links, `stock` a chart.") and add after `confirmSource`:

```swift
    static let stepsSource =
        #"{"title":"Restringing an acoustic guitar","steps":[{"text":"Loosen the old string at the tuning peg and pull the bridge pin.","image":"https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Acoustic_guitar_bridge_pins.jpg/320px-Acoustic_guitar_bridge_pins.jpg"},{"text":"Seat the new string's ball end under the pin, then thread the other end through the peg."},{"text":"Wind two or three turns, tuning up slowly and stretching the string as you go.","image":"https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Guitar_headstock_tuning.jpg/320px-Guitar_headstock_tuning.jpg"},{"text":"Trim the excess and tune once more.","image":"https://cdn.example.com/original/trim.jpg"}]}"#
    static let stockSource =
        #"{"symbol":"NASDAQ:AAPL","note":"Flat on the day after yesterday's 3% rise; the earnings call is tomorrow."}"#
```

Append three runs to `interactiveRuns`:

```swift
        Run(title: "Illustrated steps, pictured from the run's own search", json: stepsRun()),
        Run(
            title: "Entity links: a name opens its Wikipedia summary",
            json: interactiveRun(
                id: "ib5", question: "Who was Marie Curie, and where did she work?",
                reply:
                    "[Marie Curie](entity:Marie_Curie) was a Polish-born physicist and chemist who did most of her work in Paris, at the [Sorbonne](entity:University_of_Paris), where she became the first woman to hold a professorship. She won two Nobel Prizes — physics in 1903 and chemistry in 1911.")),
        Run(
            title: "A stock chart with the model's reading",
            json: interactiveRun(
                id: "ib6", question: "How's Apple doing today?",
                reply: "Quiet so far:\n\n```exodus-stock\n\(stockSource)\n```")),
```

Replace `namedSection` with:

```swift
    /// The interactive runs' names, in their order at the end of `runs`.
    static let interactiveNames = ["ask", "confirm", "answered", "steps", "entity", "stock"]

    /// The run index a `-MessageGallerySection` name stands for.
    static func namedSection(_ name: String) -> Int? {
        // The code run sits just before the interactive ones (MessageGallery.swift keeps that order).
        if name == "code" { return runs.count - interactiveRuns.count - codeRuns.count }
        guard let offset = interactiveNames.firstIndex(of: name) else { return nil }
        return runs.count - interactiveRuns.count + offset
    }
```

Add the steps run's builder after `answeredRun()`:

```swift
    /// A search whose results carry the thumbnails the steps use — a page's thumbnail and an image result's — and an
    /// original the last step names, which is dropped: the step is drawn without a picture.
    private static func stepsRun() -> String {
        let details = #"""
            [{"rank":1,"link":"https://guitars.example/restringing","title":"How to restring an acoustic guitar","snippet":"","hostname":"guitars.example","siteName":"Guitar Notes",
              "thumbnail":"https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Acoustic_guitar_bridge_pins.jpg/320px-Acoustic_guitar_bridge_pins.jpg",
              "media":[{"type":"image","title":"Tuning up","url":"https://cdn.example.com/original/tuning.jpg","sourceUrl":"https://guitars.example/restringing","thumbnailUrl":"https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Guitar_headstock_tuning.jpg/320px-Guitar_headstock_tuning.jpg"},
                       {"type":"image","title":"Trimming","url":"https://cdn.example.com/original/trim.jpg","sourceUrl":"https://guitars.example/restringing","thumbnailUrl":"https://imgs.search.brave.com/trim-thumb.jpg"}]},
             {"rank":2,"link":"https://strings.example/guide","title":"String gauges explained","snippet":"","hostname":"strings.example"}]
            """#
        let messages: [[String: Any]] = [
            ["id": "ib4s", "runId": "ib4s", "role": "user", "content": "How do I restring my acoustic guitar?", "timestamp": 1000],
            [
                "id": "ib4sa", "runId": "ib4s", "role": "assistant",
                "content": [["type": "toolCall", "id": "k40", "name": "web_search", "arguments": ["query": "how to restring an acoustic guitar"]]],
                "stopReason": "toolUse", "timestamp": 1100,
            ],
            [
                "id": "ib4st", "runId": "ib4s", "role": "toolResult", "toolCallId": "k40", "toolName": "web_search",
                "content": [["type": "text", "text": "ok"]], "details": (try? JSONSerialization.jsonObject(with: Data(details.utf8))) ?? [],
                "isError": false, "timestamp": 1200,
            ],
            [
                "id": "ib4sb", "runId": "ib4s", "role": "assistant",
                "content": [["type": "text", "text": "Four steps, one string at a time so the neck's tension never drops【1-source】:\n\n```exodus-steps\n\(stepsSource)\n```"]],
                "stopReason": "stop", "timestamp": 1500,
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
```

(The media items' keys — `type`, `title`, `url`, `sourceUrl`, `thumbnailUrl` — are `WebSearchMedia.init?(json:)`'s; if Step 2 of Task 8 found them spelled otherwise, spell them the same here. The Wikimedia URLs are examples: any `https:` URL works for the gallery, and one that 404s shows how a lost picture degrades — the step without it.)

- [ ] **Step 4: Run the gallery tests and the suite**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme ChatFeature -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
```
Expected: the whole suite passes.

- [ ] **Step 5: Screenshots**

Write `/tmp/rich2/shots.sh`:

```bash
#!/bin/bash
# Light, dark and AX screenshots of the phase-2 gallery runs. Run from the repo root after an App build into /tmp/rich2-dd.
set -euo pipefail
SIM=992425B7-F06B-4CE5-9288-95C71C2F1D44
APP=app.yancey.exodus.exodus-ios
OUT=.superpowers/rich2
mkdir -p "$OUT"
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl install "$SIM" /tmp/rich2-dd/Build/Products/Debug-iphonesimulator/Exodus.app
shoot() {
  local name=$1; shift
  xcrun simctl terminate "$SIM" "$APP" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$APP" "$@" >/dev/null
  sleep 6
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null
}
for mode in light dark; do
  xcrun simctl ui "$SIM" appearance "$mode"
  for s in steps entity stock; do shoot "$mode-$s" -MessageGallery -MessageGallerySection "$s"; done
done
xcrun simctl ui "$SIM" appearance light
xcrun simctl ui "$SIM" content_size accessibility-extra-extra-extra-large
for s in steps stock; do shoot "ax-$s" -MessageGallery -MessageGallerySection "$s"; done
xcrun simctl ui "$SIM" content_size large
echo done
```

Run: `xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=992425B7-F06B-4CE5-9288-95C71C2F1D44" -derivedDataPath /tmp/rich2-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" && bash /tmp/rich2/shots.sh`, then look at each PNG in `.superpowers/rich2/` (it is git-ignored). Check: the steps card numbers 1–4 with two pictures and the fourth step without one; the entity run's two names dotted/tinted as links; the stock card with the chart (the simulator has the network) or, offline, the symbol and note in its place, and the footer "Chart by TradingView · Open on TradingView"; nothing clipped at the AX size. Fix what is wrong before committing.

- [ ] **Step 6: The device checklist**

Create `docs/chat-rich-blocks-device-checklist.md`:

```markdown
# Rich blocks phase 2 — device checklist

What only a phone (paired with the desktop) and a desktop with the network can show. Tick on a real iPhone; the
simulator covers the rest (`docs/superpowers/plans/2026-10-07-rich-blocks-2.md`, Task 10).

## Desktop
- [ ] Ask "How do I restring an acoustic guitar?" with web search on: the reply's steps card shows pictures only where a step's URL is a thumbnail the search returned; Copy of the reply gives the numbered list, not JSON.
- [ ] Ask "How's Apple doing today?": the chart draws (TradingView's), a click on it opens the symbol's page in the browser, nothing navigates inside the app; disconnect the network and ask again: the card shows the symbol and the note, with "Open on TradingView".
- [ ] A reply with `[Marie Curie](entity:Marie_Curie)`: the dotted name opens the popover with Wikipedia's summary and picture; "Read more" opens the article in the browser; in a non-English UI the summary comes in that language when Wikipedia has it, else in English.
- [ ] Settings › General › Lock & Privacy shows the TradingView sentence.

## iPhone
- [ ] The same three replies, over the pairing: the steps' pictures load (and a step whose picture was dropped shows no gap); the chart draws in the card and a tap on it opens Safari on TradingView, never navigates the card; offline, the card shows the symbol and the note.
- [ ] An entity link: tap opens the half-height sheet with the summary; "Read more" opens Safari; a second tap on the same name is instant (remembered).
- [ ] Long-press on an entity name offers no "Open Link" (there is nothing to open); long-press on an ordinary link still does.
- [ ] Read aloud of the stock reply speaks "NASDAQ:AAPL — …", not JSON.
- [ ] Dynamic Type at the largest accessibility size: the steps card's numbers and text wrap, the chart card's footer wraps rather than clips.
- [ ] VoiceOver: each step is read as "1. …"; the chart is announced by its symbol; the sheet's Close button is reachable.
```

- [ ] **Step 7: Commit**

```bash
git add Sources/ChatFeature/MessageGalleryInteractive.swift Tests/ChatFeatureTests/MessageGalleryInteractiveTests.swift docs/chat-rich-blocks-device-checklist.md
git commit -F - <<'EOF'
feat(chat): the gallery shows the phase-2 blocks — steps pictured from the run's own search (one picture dropped as an original would be), two entity links, a stock chart — named for the screenshot script; the device checklist for what only a phone can show

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git show --stat HEAD
```

---

## Self-Review

**Spec coverage.** §2.1 steps (limits, thumbnails-only pictures, UTF-16, one block): Tasks 1, 6 (schemas/vectors), 4, 8 (drawn, pictures filtered), 3 (prompt). §2.2 `entity:` links (title rule, dead-link-as-text, the route with `lang`, 24 h cache, 404 → extract null, popover / sheet with picture, title, extract ≤ 600, "Read more", loading and nothing-found states): Tasks 1 (rule + lang), 2 (route), 5 (popover), 7 (link action), 9 (sheet). §2.3 stock (symbol pattern, TradingView's range set, default 1D, one per reply, embed URL in a sandboxed iframe / rule-listed `WKWebView`, no navigation off the widget, tap opens the symbol page outside, fallback card, no cookies, privacy sentence): Tasks 1, 4, 6, 8; Decision 16 and Task 5 for the privacy text; Decision 4 for the colours. §3 prompt: Task 3. §4 renderers and the plain-text paths: Tasks 4, 5, 8, 9; plain text Tasks 1, 5, 6. §5 testing: the vectors are mirrored (Tasks 1 ↔ 6, entity rule 1 ↔ 7, embed URL 1 ↔ 6, plain text 1 ↔ 6), the route is tested with a mocked fetch (Task 2), the desktop renders are tested in happy-dom (Tasks 4, 5), the phone's rules compile and its navigation policy is tested (Task 6), gallery runs with light/dark/AX screenshots (Task 10), the prompt budget (Task 3). §6: Q1 (Wikipedia only) — the route and both panels have no model gloss; Q2 (1D) — `DEFAULT_STOCK_RANGE` / `Range.default`; Q3 (thumbnails only) — Decision 2, Tasks 4 and 8; Q4 (one per reply) — Decision 1.

**Gaps noted, by design:** the spec's `trendLineColor` from the tone (Decision 4) and `loading="lazy"` on the iframe (incompatible with the silence timeout, Task 4) are dropped; a Settings › Privacy sentence exists only on the desktop (Decision 16).

**Placeholder scan.** No TBD/TODO; every code step carries its code; the two "if the API differs, spell it as the file does" notes (Task 8 Step 2, Task 10 Step 3) point at one concrete file each and give the fallback spelling.

**Type consistency.** `StepsBlock`/`StockBlock` (TS) ↔ `InteractiveBlock.Steps`/`.Stock` (Swift) carry the same fields; `StockRange` values and `Stock.Range` raw values are the six strings; `tradingViewEmbedUrl({symbol, range, theme, locale})` ↔ `StockChart.embedURL(symbol:range:dark:locale:)` write the vector string in Tasks 1 and 6; `EntitySummary` has the same six fields on both sides (Tasks 1, 2, 5, 9); `fencedBlocks(… pictures:)` is declared in Task 8 and called with it in Task 8's turn edit; `MarkdownEntityAction` is declared in Task 7 and used in Task 9; `TEST_IDS.chat.richBlocks.*` names are the same in Tasks 4 and 5; `clearEntityCache` is exported in Task 2 and imported by its test.

**Review Focus.** Each of the five lines names its tests, and those tests appear in the tasks named (Task 4: steps pictures, stock frame and fallback; Task 1: entity vectors, stock cases, plain text; Task 7: entity policy; Task 6: `allowsNavigation`, `rules`; Task 5: Copy).
