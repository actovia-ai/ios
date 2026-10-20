import Foundation

/// TradingView's Symbol Overview (`symbol-overview`: price, change, market status, an area chart and range tabs) as
/// the URL its loader script would put in a frame — the desktop's `stock-chart.ts` byte for byte, held to the same
/// vectors — and what the chart's web view may load and where it may go (spec 2026-10-07 §2.3).
enum StockChart {
    static let height: CGFloat = 380
    static let embedOrigin = "https://www.tradingview-widget.com"
    private static let embedPath = "/embed-widget/symbol-overview/"

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
            if script == "hant" || ["TW", "HK", "MO"].contains(region) { return "zh_TW" }
            return "zh_CN"
        default: return "en"
        }
    }

    /// The same, from an identifier (`zh-Hant-TW`, `pt_BR`, `en`); empty is English.
    static func tradingViewLocale(_ identifier: String) -> String {
        identifier.isEmpty ? "en" : tradingViewLocale(Locale(identifier: identifier))
    }

    /// The range tabs under the chart, each `label|interval`, as TradingView's own Symbol Overview offers them.
    static let dateRanges = ["1d|1", "1m|30", "3m|60", "12m|1D", "60m|1W", "all|1M"]

    /// The embed URL: `locale` in the query, the settings JSON percent-encoded in the hash, in the desktop's key order
    /// and with its `encodeURIComponent` alphabet, so both apps write the same string. The range the model picked is
    /// the tab the chart opens on (`symbol|range`).
    static func embedURL(symbol: String, range: InteractiveBlock.Stock.Range, dark: Bool, locale: String) -> URL? {
        let theme = if dark { "dark" } else { "light" }
        let name = symbol.split(separator: ":").last.map(String.init) ?? symbol
        let ranges = dateRanges.map { "\"\($0)\"" }.joined(separator: ",")
        let settings =
            "{\"symbols\":[[\"\(name)\",\"\(symbol)|\(range.rawValue)\"]],\"chartOnly\":false,\"width\":\"100%\","
            + "\"height\":380,\"colorTheme\":\"\(theme)\",\"isTransparent\":true,\"autosize\":false,"
            + "\"showVolume\":false,\"showMA\":false,\"hideDateRanges\":false,\"hideMarketStatus\":false,"
            + "\"hideSymbolLogo\":false,\"scalePosition\":\"right\",\"scaleMode\":\"Normal\",\"fontSize\":\"10\","
            + "\"noTimeScale\":false,\"valuesTracking\":\"1\",\"changeMode\":\"price-and-percent\","
            + "\"chartType\":\"area\",\"lineWidth\":2,\"lineType\":0,\"dateRanges\":[\(ranges)]}"
        guard let query = formEncoded(tradingViewLocale(locale)),
            let hash = settings.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed)
        else { return nil }
        return URL(string: "\(embedOrigin)\(embedPath)?locale=\(query)#\(hash)")
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

    /// Whether a navigation the web view cancels opens outside the app: only TradingView's own site, and only when
    /// the chart's top frame or a new window asked for it (a tap) — a subframe or a script elsewhere on the page
    /// that navigates is just cancelled.
    static func opensExternally(_ url: URL?, isMainFrameOrWindow: Bool) -> Bool {
        isMainFrameOrWindow && isTradingViewSite(url)
    }

    /// A navigation that was called off rather than failed: `URLError.cancelled`, or WebKit's "frame load
    /// interrupted by policy change" (`WebKitErrorDomain` 102) — what a tap the policy cancels and opens in Safari
    /// reports. Neither means the chart is gone.
    static func isCancelledNavigation(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102)
    }

    /// Every load but TradingView's own hosts is blocked. The widget's quotes arrive over a WebSocket to the same hosts,
    /// so `wss:` is admitted to them as `https:` is. One rule per host: the rule-list compiler refuses `|`.
    static let contentRules = #"""
        [
          {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "^https://([a-z0-9-]+\\.)*tradingview-widget\\.com/"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^https://([a-z0-9-]+\\.)*tradingview\\.com/"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^wss://([a-z0-9-]+\\.)*tradingview-widget\\.com/"}, "action": {"type": "ignore-previous-rules"}},
          {"trigger": {"url-filter": "^wss://([a-z0-9-]+\\.)*tradingview\\.com/"}, "action": {"type": "ignore-previous-rules"}},
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
