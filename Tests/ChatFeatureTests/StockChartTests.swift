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
        #expect(StockChart.opensExternally(site, isMainFrameOrWindow: true))
        #expect(!StockChart.opensExternally(site, isMainFrameOrWindow: false))
        #expect(!StockChart.opensExternally(URL(string: "https://example.com/"), isMainFrameOrWindow: true))
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
