import SwiftUI
import WebKit

/// How the chart's web view is doing.
enum StockChartPhase: Equatable {
    case loading, loaded, failed
}

/// A reply's stock chart (`actovia-stock`): TradingView's Symbol Overview as its own embed URL in a web view that may load
/// nothing but TradingView's hosts and go nowhere else — a tap on the chart opens the symbol's page in the browser —
/// the model's note under it, and "Chart by TradingView" with the page's link (the disclosure the phone has, having
/// no privacy page). When the chart cannot load — TradingView not reachable from the phone's network, often — the
/// symbol and the note stand in its place, with Retry.
struct StockBlockView: View {
    let block: InteractiveBlock.Stock

    @State private var phase = Self.pinnedPhase ?? .loading
    /// Bumped by Retry: a new web view, a new load.
    @State private var attempt = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    /// The scheme the chart is drawn in; see `StockChart.drawsDark`.
    @State private var dark: Bool?
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if phase == .failed {
                unavailable
            } else if let url = StockChart.embedURL(
                symbol: block.symbol, range: block.range ?? .default, dark: isDark,
                locale: locale.identifier)
            {
                StockChartWebView(
                    url: url, onPhase: { if Self.pinnedPhase == nil { phase = $0 } },
                    openExternally: { openURL($0) })
                    .frame(height: StockChart.height)
                    .accessibilityLabel(Text(verbatim: block.symbol))
                    // Until the chart draws, the web view is transparent: the symbol and a spinner hold its place,
                    // so the card is not an empty frame for the seconds TradingView takes.
                    .overlay {
                        if phase == .loading { loadingPlaceholder.transition(.opacity) }
                    }
                    .animation(.easeOut(duration: 0.2), value: phase)
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
                // Failed, the link is the card's own button above.
                if phase != .failed, let page = StockChart.symbolPageURL(block.symbol) {
                    Link(destination: page) { Text("ios:chat.block.openOnTradingView") }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, CardStyle.inset)
            .padding(.vertical, 10)
        }
        .modifier(CardSurface())
        // The web view is made once for what the URL is made of; a change of scheme makes it again.
        .id("\(block.symbol)|\(block.range?.rawValue ?? "")|\(isDark)|\(attempt)")
        .onAppear { if dark == nil { dark = colorScheme == .dark } }
        .onChange(of: colorScheme) { follow() }
        .onChange(of: scenePhase) { follow() }
    }

    /// `-MessageGalleryStock loading|failed` (DEBUG): the card held in that state, for screenshots.
    private static var pinnedPhase: StockChartPhase? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-MessageGalleryStock"), index + 1 < arguments.count else {
            return nil
        }
        switch arguments[index + 1] {
        case "loading": return .loading
        case "failed": return .failed
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading) {
            Text(verbatim: block.symbol).font(.headline)
            Spacer()
            ProgressView().frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(CardStyle.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// The chart could not load (TradingView unreachable from the phone's network, often): the symbol, what went
    /// wrong, and the two ways on — try again, or read the symbol on TradingView's own page in the browser.
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: block.symbol).font(.headline)
                Text("ios:chat.block.chartUnavailable").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("common:action.retry") {
                    phase = .loading
                    attempt += 1
                }
                .buttonStyle(.bordered)
                if let page = StockChart.symbolPageURL(block.symbol) {
                    Link(destination: page) { Text("ios:chat.block.openOnTradingView") }
                        .buttonStyle(.borderless)
                }
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(CardStyle.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isDark: Bool {
        StockChart.drawsDark(shown: dark, onScreen: colorScheme == .dark, isActive: scenePhase == .active)
    }

    private func follow() {
        dark = isDark
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
        webView.addGestureRecognizer(
            TouchRecorder { [weak coordinator = context.coordinator] in coordinator?.lastTouch = Date() })
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
        /// When a finger last touched the chart (`TouchRecorder`).
        var lastTouch: Date?
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
                        forIdentifier: "actovia-stock-chart", encodedContentRuleList: StockChart.contentRules)
                    Self.compiledRules = rules
                }
                guard let self, !Task.isCancelled, let webView = self.webView else { return }
                guard let rules else {
                    self.set(.failed)
                    return
                }
                webView.configuration.userContentController.add(rules)
                webView.load(URLRequest(url: url))
                // Twenty seconds of silence is a failure (offline, blocked, a slow route to TradingView); Retry tries again.
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled, self.phase == .loading { self.set(.failed) }
            }
        }

        private func set(_ phase: StockChartPhase) {
            guard self.phase != phase else { return }
            self.phase = phase
            onPhase(phase)
        }

        private func isTap(_ action: WKNavigationAction) -> Bool {
            StockChart.isTap(
                linkActivated: action.navigationType == .linkActivated,
                sinceTouch: lastTouch.map { Date().timeIntervalSince($0) })
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url
            if StockChart.allowsNavigation(to: url) { return .allow }
            // A nil target frame is a new window; a subframe's navigation elsewhere is only cancelled.
            let isMainFrameOrWindow = navigationAction.targetFrame?.isMainFrame != false
            if let url,
                StockChart.opensExternally(url, isMainFrameOrWindow: isMainFrameOrWindow, isTap: isTap(navigationAction))
            {
                openExternally(url)
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { set(.loaded) }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }

        /// A drawn chart stays drawn: a later navigation's failure (a tap the policy cancelled and sent to Safari)
        /// is not the chart's, and a cancelled navigation is never a failure.
        private func fail(_ error: Error) {
            guard phase != .loaded, !StockChart.isCancelledNavigation(error) else { return }
            set(.failed)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { set(.failed) }

        // MARK: WKUIDelegate

        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // A new window: from the chart's own top frame, and from a tap, as above.
            let fromTopFrame = navigationAction.sourceFrame.isMainFrame
            if let url = navigationAction.request.url,
                StockChart.opensExternally(url, isMainFrameOrWindow: fromTopFrame, isTap: isTap(navigationAction))
            {
                openExternally(url)
            }
            return nil
        }
    }
}

/// Notes when a finger comes down on the chart, and nothing else: it never recognizes, so every touch goes on to the
/// web view (and the chat's scrolling) as before.
private final class TouchRecorder: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }
}
