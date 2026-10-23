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
                == "https://www.tradingview-widget.com/embed-widget/symbol-overview/?locale=ja#%7B%22symbols%22%3A%5B%5B%227203%22%2C%22TSE%3A7203%7C12M%22%5D%5D%2C%22chartOnly%22%3Afalse%2C%22width%22%3A%22100%25%22%2C%22height%22%3A380%2C%22colorTheme%22%3A%22light%22%2C%22isTransparent%22%3Atrue%2C%22autosize%22%3Afalse%2C%22showVolume%22%3Afalse%2C%22showMA%22%3Afalse%2C%22hideDateRanges%22%3Afalse%2C%22hideMarketStatus%22%3Afalse%2C%22hideSymbolLogo%22%3Afalse%2C%22scalePosition%22%3A%22right%22%2C%22scaleMode%22%3A%22Normal%22%2C%22fontSize%22%3A%2210%22%2C%22noTimeScale%22%3Afalse%2C%22valuesTracking%22%3A%221%22%2C%22changeMode%22%3A%22price-and-percent%22%2C%22chartType%22%3A%22area%22%2C%22lineWidth%22%3A2%2C%22lineType%22%3A0%2C%22dateRanges%22%3A%5B%221d%7C1%22%2C%221m%7C30%22%2C%223m%7C60%22%2C%2212m%7C1D%22%2C%2260m%7C1W%22%2C%22all%7C1M%22%5D%7D"
        )
        let dark = try #require(StockChart.embedURL(symbol: "NASDAQ:AAPL", range: .oneDay, dark: true, locale: "en"))
        #expect(dark.absoluteString.contains("%22colorTheme%22%3A%22dark%22"))
        #expect(dark.absoluteString.contains("NASDAQ%3AAAPL%7C1D"))
        #expect(dark.host() == "www.tradingview-widget.com")
    }

    @Test("the widget's locale for the app's", arguments: [
        ("en", "en"), ("de", "de"), ("es", "es"), ("fr", "fr"), ("it", "it"), ("ja", "ja"), ("ko", "kr"),
        ("pt-BR", "br"), ("ru", "ru"), ("zh-Hans", "zh_CN"), ("zh-Hant-TW", "zh_TW"), ("zh-Hant-HK", "zh_TW"),
        ("zh", "zh_CN"), ("nl", "en"), ("", "en"),
        // The phone's own spellings.
        ("zh-Hant", "zh_TW"), ("zh-HK", "zh_TW"), ("zh_TW", "zh_TW"), ("zh-Hans_CN", "zh_CN"), ("ru_RU", "ru"),
        ("pt_BR", "br"), ("en_US", "en"),
    ])
    func locale(_ identifier: String, _ expected: String) {
        #expect(StockChart.tradingViewLocale(identifier) == expected, "\(identifier)")
    }

    @Test("the scheme follows the screen while active, and holds through the background's snapshots")
    func schemeThroughBackground() {
        #expect(StockChart.drawsDark(shown: false, onScreen: true, isActive: true))
        #expect(!StockChart.drawsDark(shown: false, onScreen: true, isActive: false))
        #expect(StockChart.drawsDark(shown: true, onScreen: false, isActive: false))
        #expect(StockChart.drawsDark(shown: nil, onScreen: true, isActive: false))
    }

    @Test("the symbol's page: the colon a dash")
    func symbolPage() {
        #expect(StockChart.symbolPageURL("NASDAQ:AAPL")?.absoluteString == "https://www.tradingview.com/symbols/NASDAQ-AAPL/")
        #expect(StockChart.symbolPageURL("TSE:7203.T-A")?.absoluteString == "https://www.tradingview.com/symbols/TSE-7203.T-A/")
    }

    @Test("the web view may go to its embed origin and blank, nowhere else")
    func navigation() {
        #expect(StockChart.allowsNavigation(to: URL(string: "https://www.tradingview-widget.com/embed-widget/symbol-overview/?locale=en")))
        #expect(StockChart.allowsNavigation(to: URL(string: "about:blank")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "https://www.tradingview.com/symbols/NASDAQ-AAPL/")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "https://example.com")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "http://www.tradingview-widget.com/")))
        #expect(!StockChart.allowsNavigation(to: URL(string: "actovia://pair?c=1")))
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

    @Test("only the top frame or a new window may send TradingView's site to the browser")
    func opensExternally() {
        let site = URL(string: "https://www.tradingview.com/symbols/NASDAQ-AAPL/")
        #expect(StockChart.opensExternally(site, isMainFrameOrWindow: true, isTap: true))
        #expect(!StockChart.opensExternally(site, isMainFrameOrWindow: false, isTap: true))
        #expect(!StockChart.opensExternally(URL(string: "https://example.com/"), isMainFrameOrWindow: true, isTap: true))
        // A script that navigates on its own never sends the reader to Safari.
        #expect(!StockChart.opensExternally(site, isMainFrameOrWindow: true, isTap: false))
    }

    @Test("a tap: a link activated, or a navigation within a second of a touch")
    func tapWindow() {
        #expect(StockChart.isTap(linkActivated: true, sinceTouch: nil))
        #expect(StockChart.isTap(linkActivated: false, sinceTouch: 0.3))
        #expect(!StockChart.isTap(linkActivated: false, sinceTouch: 5))
        #expect(!StockChart.isTap(linkActivated: false, sinceTouch: nil))
    }

    @Test("a cancelled navigation is not a failure")
    func cancelled() {
        #expect(StockChart.isCancelledNavigation(URLError(.cancelled)))
        #expect(StockChart.isCancelledNavigation(NSError(domain: "WebKitErrorDomain", code: 102)))
        #expect(!StockChart.isCancelledNavigation(URLError(.notConnectedToInternet)))
    }

    @Test("the content rules compile") @MainActor
    func rules() async throws {
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "actovia-stock-chart-test", encodedContentRuleList: StockChart.contentRules)
        #expect(rules != nil)
    }
}
