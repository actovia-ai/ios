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
