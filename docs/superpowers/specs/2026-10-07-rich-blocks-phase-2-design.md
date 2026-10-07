# Rich blocks — phase 2: illustrated steps, entity panels, stock charts

Date: 2026-10-07 · Status: decided — the owner answered the four questions in §6 on 2026-10-07; nothing implemented yet
Repos: `exodus` (desktop: prompt, routes, renderer) and `exodus-ios` (renderer)
Builds on: `2026-10-06-interactive-blocks-design.md` (phase 1 — the fenced-block mechanism, the answer fence, the renderers' hooks)

## 1. Goal

ChatGPT and Gemini answer some questions with more than prose: a how-to as numbered steps with a picture each, a name that opens a small panel about the person or place, a ticker that shows its chart. Phase 1 gave Exodus one mechanism for blocks the model emits (a fenced code block with a reserved language and JSON inside, drawn natively by both clients, as code anywhere else). Phase 2 adds three such blocks:

| Block | Fence | What the reader sees |
|---|---|---|
| Illustrated steps | `exodus-steps` | Numbered steps, each with a line or two and, where the model found one, a picture — the thumbnail Brave's image search handed the run, never the original |
| Entity panel | inline link `[Marie Curie](entity:Marie_Curie)` | The name in the text, underlined like a link; tapped, a panel with Wikipedia's summary, picture and a link out |
| Stock chart | `exodus-stock` | A TradingView mini chart for the symbol, with the model's one-line reading under it |

Decided by the owner (2026-10-06): TradingView for the charts ("用 TradingView"); plain-text answers stay the rule for anything interactive (nothing here sends anything back). Decided 2026-10-07: the entity panel is a plain lookup — Wikipedia's summary and nothing of the model's ("先做成一个纯搜索的效果"); a model-written gloss may be added later if wanted.

### Non-goals
- No new tool calls: a block never fetches on the model's behalf. Pictures come from search results the run already holds; the entity summary is fetched by the client through a desktop route when the panel opens; the chart is TradingView's own widget.
- No persistence beyond the message text, as in phase 1.
- No trading, no portfolio, no alerts: a chart is a picture of a price.

## 2. The wire

### 2.1 `exodus-steps`
```json
{
  "title": "Replacing the strings",
  "steps": [
    { "text": "Loosen the old string from the tuning peg.", "image": "https://…/peg.jpg" },
    { "text": "Thread the new one through the bridge." },
    { "text": "Tune up slowly, stretching the string as you go.", "image": "https://…/tune.jpg" }
  ]
}
```
- `title` ≤ 200 (optional); `steps` 2–12; `text` ≤ 300, one line; `image` optional, an `https:` URL **that is a thumbnail among the run's web-search results** — Brave's `thumbnail.src` (served from Brave's own image proxy), never a result's original `url`/`image`: an original is hot-linked from a site that may refuse or swap it, which this app has already been bitten by (owner, 2026-10-07: "原图可能触发原站盗链"). Any other URL is dropped by the client, not drawn — the allow-list the chat's Markdown images already use (`remote-image.tsx` on the desktop; `MarkdownImagePolicy` on the phone) is narrowed the same way for this block. The block is still valid without its pictures.
- UTF-16 counting, the same scanner rules as phase 1 (first top-level closed fence is the block; one block per message; the one-line and length refines).

### 2.2 `entity:` links
Inline, inside ordinary Markdown: `[Marie Curie](entity:Marie_Curie)`, `[Kyoto](entity:Kyoto)` — the target is a Wikipedia article title (underscores for spaces, as Wikipedia writes them), ≤ 200 chars, `[\p{L}\p{N}_().,'\-:]+`. The model may use at most ~5 per reply (prompt guidance, not validated). An `entity:` target that fails the pattern renders as plain text with the name (never as a dead link).
- Desktop route `GET /api/v1/entity/:title?lang=xx` → `{ title, extract, thumbnail?: { source, width, height }, url }` from Wikipedia's REST summary (`https://{lang}.wikipedia.org/api/rest_v1/page/summary/{title}`), fetched by **main** through `fetchPublicHttps()` (public hosts only, pinned TLS rules as `maps.ts` uses), cached 24 h in memory, 404 → `{ title, extract: null }`. `lang` from the app locale (`zh-Hans`→`zh`, etc.), fallback `en`. The phone calls the same route (its desktop is its network).
- The panel: desktop a `Popover` (shadcn) at the link; phone a `.sheet` with `.medium` detent — picture, title, extract (≤ 600 chars shown, "Read more" to `url` in the browser). Loading and "nothing found" states.

### 2.3 `exodus-stock`
```json
{ "symbol": "NASDAQ:AAPL", "range": "1D", "note": "Up 12% since the earnings call; the gap at Oct 2 is the split." }
```
- `symbol`: TradingView's `EXCHANGE:TICKER` (≤ 40, `^[A-Z0-9_.]+:[A-Z0-9_.\-]+$`); `range` one of `1D 5D 1M 3M 6M 1Y 5Y ALL`, **default `1D`** — the finest the widget offers (owner: "默认展示最小的粒度"); the model names a wider one only when the question does ("this year" → `1Y`); `note` ≤ 300 optional, shown under the chart in the chat's text. One `exodus-stock` per reply, as every `exodus-*` fence.
- **Desktop:** TradingView's Mini Symbol Overview widget inside a sandboxed `<iframe>` (`sandbox="allow-scripts allow-same-origin"`, `referrerpolicy="no-referrer"`, fixed height 220, `loading="lazy"`), whose `srcdoc` is built by us and loads only `https://s3.tradingview.com/external-embedding/embed-widget-mini-symbol-overview.js`; the CSP gets a `frame-src https://www.tradingview-widget.com https://s3.tradingview.com` entry and the widget's `script-src` stays confined to the iframe document. Theme from the app's scheme; the tone's accent as `trendLineColor`. A chart that fails to load (offline, blocked) shows the symbol and the note as a card with a "Open on TradingView" link.
- **Phone:** `WKWebView` with the same `srcdoc`, `WKContentRuleList` allowing only TradingView's hosts, non-persistent data store, JavaScript on, no navigation off the widget (a tap on the chart opens `https://www.tradingview.com/symbols/{symbol}` in the system browser via `decidePolicyFor`). Height 220, Reduce Motion unaffected (TradingView animates its own line; nothing of ours).
- Privacy note for the owner: the widget is a third-party embed — TradingView sees the symbol and the viewer's IP, as any embedded chart would. No cookies are kept (iframe sandbox without `allow-storage`; non-persistent store on the phone). The Settings › Privacy text gets one sentence.

## 3. The prompt (desktop)

The `interactive blocks` section grows a second half, ~25 lines: steps for "how do I…" answers with 3+ ordered actions (pictures only from the search you ran — paste the result's image URL, never invent one); an `entity:` link the first time a notable person, place, organisation or work is named when a reader may want to know more (not for the user's own names, not for common words); `exodus-stock` when the user asks about a listed company's or index's price or performance, with your reading in `note`. Never inside a list or table (phase 1's rule). Both examples included. The prompt budget test moves from 11,500 to ~13,000.

## 4. Renderers

- **Desktop:** `interactive-fence.tsx` gains `steps` and `stock` kinds (same `opensBlock` position rule); `steps-block.tsx` (an `<ol>` with `RemoteImage` per step, images gated by the run's allow-list through the existing `AllowedImageUrlsContext`); `stock-block.tsx` (the iframe + fallback card); `entity-link.tsx` wired through `markdown.tsx`'s `a` renderer when `href` starts with `entity:` (otherwise links are unchanged); route `src/main/lib/server/routes/entity.ts`.
- **Phone:** `MarkdownFencedBlocks` already lets a host draw a fence; `StepsBlockView`, `StockBlockView` (WKWebView wrapper in `Sources/ChatFeature/Interactive/`), and an `entity:` scheme handled by MarkdownKit's link policy → `EntitySheet`. Images in steps go through `MarkdownImageView` (tap-to-load unless in the run's search allow-list, as Markdown images do today).
- Both: a block's text is also what Copy / read-aloud get (steps as a numbered list; a stock block as `symbol — note`), through the phase-1 plain-text paths.

## 5. Testing
- Shared vectors (vitest + Swift Testing, byte-identical): steps limits (1 step, 13 steps, 301-char text, an `http:` image, an image not in the run's results → dropped, a result's *original* image URL → dropped, its thumbnail → kept); stock symbol pattern, range enum and the `1D` default; entity target pattern.
- Desktop: the entity route (mocked fetch; 404; cache; lang fallback); `entity:` link renders a popover trigger and never an `<a href="entity:…">`; stock iframe `srcdoc` loads only the allowed script and sets `sandbox`; steps images outside the allow-list render the placeholder.
- Phone: `WKContentRuleList` compiles and blocks a non-TradingView URL; `EntitySheet` states; gallery runs `steps`, `entity`, `stock` with light/dark/AX screenshots.
- Prompt budget test.

## 6. Open questions for the owner
1. ~~Entity panels: Wikipedia only, or also the model's own one-line gloss when Wikipedia has nothing?~~ **Decided 2026-10-07: Wikipedia only, a pure lookup; "nothing found" otherwise. An AI gloss is a possible later addition, not part of phase 2.**
2. ~~Stock range default `1M` — or follow what the user asked?~~ **Decided: default `1D`, the finest granularity; the model widens it only when the question names a span.**
3. ~~Steps pictures: thumbnails or the result's full image?~~ **Decided: Brave's thumbnail only, never the original — originals are hot-links the source site may block (a lesson already learned in this app).**
4. ~~Should `exodus-stock` be limited to one per reply?~~ **Decided: yes.**
