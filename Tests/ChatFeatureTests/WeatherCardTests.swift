import Foundation
import MarkdownKit
import Models
import SwiftUI
import Testing
import UIKit

@testable import ChatFeature

private func value(_ json: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func model(_ json: String) throws -> WeatherCardModel {
    WeatherCardModel(try #require(WeatherResult(json: value(json))))
}

/// An Open-Meteo row for Edinburgh: WMO codes, a day of 24 ISO local times, and numbers that arrive as numbers.
private let edinburghRow = #"""
    {"location":"Edinburgh, United Kingdom","current":{"condition":"Slight rain showers","weatherCode":"80","tempC":11,"feelsLikeC":"8","humidity":"87","windKmph":"22","windDirDegree":"250","windDir":"WSW","precipMM":0.4,"uvIndex":"1","visibility":"10","pressure":"1006","observedAt":"2025-11-02T14:15","isDay":true},
     "forecast":[
      {"date":"2025-11-02","condition":"Slight rain showers","weatherCode":"80","maxTempC":"14","minTempC":"9","sunrise":"2025-11-02T06:52","sunset":"2025-11-02T16:58","hourly":[
        {"time":"2025-11-02T00:00","tempC":"9","weatherCode":"80","condition":"x","rainChance":"0"},{"time":"2025-11-02T01:00","tempC":"9","weatherCode":"80","condition":"x","rainChance":"1"},{"time":"2025-11-02T02:00","tempC":"9","weatherCode":"80","condition":"x","rainChance":"2"},
        {"time":"2025-11-02T03:00","tempC":"9","weatherCode":"80","condition":"x","rainChance":"3"},{"time":"2025-11-02T04:00","tempC":"9","weatherCode":"80","condition":"x","rainChance":"4"},{"time":"2025-11-02T05:00","tempC":"9","weatherCode":"80","condition":"x","rainChance":"5"},
        {"time":"2025-11-02T06:00","tempC":"9","weatherCode":"80","condition":"x","rainChance":"6"},{"time":"2025-11-02T07:00","tempC":"10","weatherCode":"80","condition":"x","rainChance":"7"},{"time":"2025-11-02T08:00","tempC":"10","weatherCode":"80","condition":"x","rainChance":"8"},
        {"time":"2025-11-02T09:00","tempC":"11","weatherCode":"80","condition":"x","rainChance":"9"},{"time":"2025-11-02T10:00","tempC":"12","weatherCode":"80","condition":"x","rainChance":"10"},{"time":"2025-11-02T11:00","tempC":"12","weatherCode":"80","condition":"x","rainChance":"11"},
        {"time":"2025-11-02T12:00","tempC":"13","weatherCode":"80","condition":"x","rainChance":"12"},{"time":"2025-11-02T13:00","tempC":"13","weatherCode":"80","condition":"x","rainChance":"13"},{"time":"2025-11-02T14:00","tempC":"14","weatherCode":"80","condition":"x","rainChance":"14"},
        {"time":"2025-11-02T15:00","tempC":"14","weatherCode":"80","condition":"x","rainChance":"15"},{"time":"2025-11-02T16:00","tempC":"13","weatherCode":"80","condition":"x","rainChance":"16"},{"time":"2025-11-02T17:00","tempC":"12","weatherCode":"80","condition":"x","rainChance":"17"},
        {"time":"2025-11-02T18:00","tempC":"12","weatherCode":"80","condition":"x","rainChance":"18"},{"time":"2025-11-02T19:00","tempC":"11","weatherCode":"80","condition":"x","rainChance":"19"},{"time":"2025-11-02T20:00","tempC":"11","weatherCode":"80","condition":"x","rainChance":"20"},
        {"time":"2025-11-02T21:00","tempC":"10","weatherCode":"80","condition":"x","rainChance":"21"},{"time":"2025-11-02T22:00","tempC":"10","weatherCode":"80","condition":"x","rainChance":"22"},{"time":"2025-11-02T23:00","tempC":"10","weatherCode":"80","condition":"x","rainChance":"23"}]},
      {"date":"2025-11-03","condition":"Overcast","weatherCode":"3","maxTempC":"12","minTempC":"8","sunrise":"2025-11-03T06:54","sunset":"2025-11-03T16:56","hourly":[]},
      {"date":"2025-11-04","condition":"Clear sky","weatherCode":"0","maxTempC":"15","minTempC":"7","sunrise":"2025-11-04T06:56","sunset":"2025-11-04T16:54","hourly":[]}]}
    """#

@Suite("Weather: codes to conditions and symbols")
struct WeatherConditionTests {
    @Test("WMO codes name the desktop's conditions")
    func wmo() {
        let expected: [String: WeatherConditionName] = [
            "0": .sunny, "1": .sunny, "2": .partlyCloudy, "3": .cloudy, "45": .fog, "51": .lightShowers, "56": .lightSleet,
            "63": .lightRain, "65": .heavyRain, "75": .heavySnow, "77": .lightSnow, "81": .heavyShowers,
            "86": .heavySnowShowers, "95": .thunderyShowers, "99": .thunderyHeavyRain,
        ]
        for (code, name) in expected { #expect(WeatherCondition.name(of: code) == name, "WMO \(code)") }
        #expect(WeatherCondition.wmo.count == 28)
    }

    @Test("an unknown, empty or padded code: cloudy, or read through its padding")
    func unknown() {
        #expect(WeatherCondition.name(of: "7") == .cloudy)
        #expect(WeatherCondition.name(of: "") == .cloudy)
        #expect(WeatherCondition.name(of: "sunny") == .cloudy)
        #expect(WeatherCondition.name(of: "113") == .cloudy)
        #expect(WeatherCondition.name(of: " 63 ") == .lightRain)
    }

    @Test("a clear or partly cloudy night is a moon; rain is rain by day and night")
    func dayAndNight() {
        #expect(WeatherCondition.symbol(code: "0") == "sun.max.fill")
        #expect(WeatherCondition.symbol(code: "0", isDay: false) == "moon.stars.fill")
        #expect(WeatherCondition.symbol(code: "2", isDay: false) == "cloud.moon.fill")
        #expect(WeatherCondition.symbol(code: "2") == "cloud.sun.fill")
        #expect(WeatherCondition.symbol(code: "63", isDay: false) == WeatherCondition.symbol(code: "63"))
        #expect(WeatherCondition.symbol(code: "95") == "cloud.bolt.rain.fill")
        #expect(WeatherCondition.symbol(code: "99") == "cloud.bolt.rain.fill")
        #expect(WeatherCondition.symbol(.thunderySnowShowers) == "cloud.bolt.fill")
    }

    @Test("a cloud is muted and what it carries keeps a colour; a bare sun or moon draws in its own")
    func accents() {
        #expect(WeatherCondition.accent(of: "cloud.sun.fill") == .yellow)
        #expect(WeatherCondition.accent(of: "cloud.bolt.rain.fill") == .yellow)
        #expect(WeatherCondition.accent(of: "cloud.drizzle.fill") == .cyan)
        #expect(WeatherCondition.accent(of: "cloud.snow.fill") == .cyan)
        #expect(WeatherCondition.accent(of: "cloud.fill") == nil)
        #expect(WeatherCondition.accent(of: "cloud.moon.fill") == nil)
        #expect(WeatherCondition.accent(of: "sun.max.fill") == nil)
    }

    @Test("every condition, by day and night, is a symbol the system has")
    func symbolsExist() {
        for name in WeatherConditionName.allCases {
            for isDay in [true, false] {
                let symbol = WeatherCondition.symbol(name, isDay: isDay)
                #expect(UIImage(systemName: symbol) != nil, "\(name) → \(symbol)")
            }
        }
    }
}

@Suite("Weather: clock times")
struct WeatherClockTests {
    @Test("ISO local times, anywhere in the string")
    func iso() {
        #expect(WeatherClock.hours("2026-09-23T06:02") == 6 + 2.0 / 60)
        #expect(WeatherClock.hours("2026-09-23T23:00") == 23)
        #expect(WeatherClock.hours("2026-09-23T13:30:00") == 13.5)
    }

    @Test("anything else does not read, and is shown as it came: a 12-hour clock or an hourly slot too")
    func unreadable() {
        #expect(WeatherClock.hours("") == nil)
        #expect(WeatherClock.hours("noon") == nil)
        #expect(WeatherClock.hours("12345") == nil)
        #expect(WeatherClock.hours("06:52") == nil)
        #expect(WeatherClock.hours("06:52 AM") == nil)
        #expect(WeatherClock.hours("300") == nil)
        #expect(WeatherClock.format("noon") == "noon")
    }
}

@Suite("Weather: the week's range bars and the day's curve")
struct WeatherScaleTests {
    @Test("a bar spans its day's low to high on the week's scale")
    func bars() throws {
        let scale = try #require(WeatherRangeScale(lows: [17, 15, 14], highs: [24, 20, 21]))
        #expect(scale.low == 14)
        #expect(scale.span == 10)
        let bar = scale.bar(low: 17, high: 24)
        #expect(abs(bar.start - 0.3) < 1e-9)
        #expect(abs(bar.width - 0.7) < 1e-9)
        let whole = scale.bar(low: 14, high: 24)
        #expect(whole.start == 0 && whole.width == 1)
    }

    @Test("a still day keeps a sliver, and no bar runs past the track")
    func edges() throws {
        let scale = try #require(WeatherRangeScale(lows: [10], highs: [20]))
        #expect(scale.bar(low: 12, high: 12).width == 0.04)
        let top = scale.bar(low: 20, high: 20)
        #expect(top.start + top.width <= 1)
        #expect(top.width == 0.04)
        let beyond = scale.bar(low: 5, high: 30)
        #expect(beyond.start == 0)
        #expect(beyond.width == 1)
    }

    @Test("a flat week still has a scale; a week with no numbers has none; non-finite values are ignored")
    func degenerate() throws {
        #expect(try #require(WeatherRangeScale(lows: [18, 18], highs: [18, 18])).span == 1)
        #expect(WeatherRangeScale(lows: [nil, nil], highs: [nil]) == nil)
        #expect(try #require(WeatherRangeScale(lows: [.infinity, 3], highs: [.nan, 9])).low == 3)
    }

    @Test("the curve is drawn on the day's own range, at least 6° wide and centred")
    func curveDomain() {
        #expect(WeatherCurve.domain([10, 20, 15]) == 10...20)
        #expect(WeatherCurve.domain([20, 21]) == 17.5...23.5)
        #expect(WeatherCurve.domain([5]) == 2...8)
        #expect(WeatherCurve.domain([]) == nil)
    }
}

@Suite("Weather: the card's model")
struct WeatherCardModelTests {
    @Test("a row reads: WMO symbols, 24 hours on the clock, ISO sunrise, number fields")
    func row() throws {
        let weather = try model(edinburghRow)
        #expect(weather.now.temp == "11")
        #expect(weather.now.symbol == "cloud.drizzle.fill")
        #expect(weather.days.map(\.symbol) == ["cloud.drizzle.fill", "cloud.fill", "sun.max.fill"])
        let today = try #require(weather.days.first)
        #expect(today.hours.map(\.x) == (0..<24).map(Double.init))
        #expect(today.lastHour == 23)
        #expect(today.hasCurve)
        #expect(today.curveDomain == 8.5...14.5)
        #expect(WeatherClock.hours(today.sunrise) == 6 + 52.0 / 60)
        #expect(!weather.days[1].hasCurve)
        #expect(weather.readings.map(\.reading) == WeatherCardModel.Reading.allCases)
        #expect(weather.days.allSatisfy { $0.bar != nil })
        #expect(weather.days[2].bar?.start == 0)
    }

    @Test("readings the result left empty are not shown; a stub with no forecast has no days")
    func sparse() throws {
        let weather = try model(#"{"location":"Shanghai","current":{"tempC":"22","weatherCode":"2","visibility":"","humidity":"64"},"forecast":[]}"#)
        #expect(weather.readings.map(\.reading) == [.humidity])
        #expect(weather.days.isEmpty)
        #expect(weather.now.symbol == "cloud.sun.fill")
    }

    @Test("a night reading is a moon; a slot whose time does not read puts the day on slot numbers")
    func nightAndSlots() throws {
        let weather = try model(
            #"{"location":"X","current":{"tempC":"12","weatherCode":"0","isDay":false},"forecast":[{"date":"2026-09-24","maxTempC":"n/a","minTempC":"3","hourly":[{"time":"2026-09-24T00:00","tempC":"3"},{"time":"later","tempC":"5"},{"time":"2026-09-24T02:00","tempC":"x"}]}]}"#)
        #expect(weather.now.symbol == "moon.stars.fill")
        let day = try #require(weather.days.first)
        #expect(day.hours.map(\.x) == [0, 1])
        #expect(day.bar == nil)
    }

    @Test("a weather card is built with the turn; a failed call keeps its place and message")
    func built() throws {
        let card = ToolCard(id: "t", toolName: "weather", kind: .weather, payload: value(edinburghRow))
        #expect(card.content.weather?.forecast?.location == "Edinburgh, United Kingdom")
        #expect(ToolCardRegistry.canDraw(card))
        let failed = ToolCard(
            id: "e", toolName: "weather", kind: .generic, arguments: value(#"{"location":"Atlantis"}"#), isError: true,
            errorText: #"No place found for "Atlantis""#)
        #expect(failed.content.weather == .failed(place: "Atlantis", message: #"No place found for "Atlantis""#))
    }

    @Test("a failed weather call is a card of its own as well as a failed step")
    func failedInTurn() throws {
        let messages = [
            decode(#"{"id":"u1","role":"user","runId":"u1","content":"weather?","timestamp":1}"#),
            decode(#"{"id":"a1","role":"assistant","runId":"u1","content":[{"type":"toolCall","id":"k1","name":"weather","arguments":{"location":"Atlantis"}}],"stopReason":"toolUse","timestamp":2}"#),
            decode(#"{"id":"t1","role":"toolResult","runId":"u1","toolCallId":"k1","toolName":"weather","content":[{"type":"text","text":"No place found"}],"isError":true,"timestamp":3}"#),
        ]
        var cache = RunGrouper.Cache()
        let turn = try #require(
            RunGrouper.group(messages, cache: &cache).compactMap { if case .assistantTurn(let turn) = $0 { turn } else { nil } }.first)
        #expect(turn.toolCards.map(\.toolName) == ["weather"])
        #expect(turn.toolCards.first?.content.weather == .failed(place: "Atlantis", message: "No place found"))
    }
}

@Suite("Weather: VoiceOver copy")
struct WeatherCardTextTests {
    @Test("now, a day's range and the curve read as sentences")
    func text() throws {
        let weather = try model(edinburghRow)
        #expect(WeatherCardText.summary(weather) == "Edinburgh, United Kingdom: 11°, Slight rain showers, feels like 8°")
        #expect(WeatherCardText.dayRange(weather.days[0]) == "Today, Slight rain showers: high 14°, low 9°")
        #expect(WeatherCardText.weekday(weather.days[1]) == "Tmr")
        #expect(WeatherCardText.chartValue(weather.days[0])?.hasPrefix("Lowest 9° at ") == true)
        #expect(WeatherCardText.chartValue(weather.days[1]) == nil)
        #expect(WeatherCardText.rainChance("60") == "60% rain")
    }
}

@MainActor
@Suite("Weather: the card draws every state without falling back")
struct WeatherCardRenderTests {
    @Test("a forecast, a stub and a failed card draw their own card and report nothing")
    func drawsWithoutReports() async {
        let reports = WeatherReportLog()
        let diagnostics = RenderDiagnostics { _, message, _ in reports.append(message) }
        let cards = [
            ToolCard(id: "t1", toolName: "weather", kind: .weather, payload: value(edinburghRow)),
            ToolCard(
                id: "t2", toolName: "weather", kind: .weather,
                payload: value(#"{"location":"S","current":{"tempC":"22","weatherCode":"2"},"forecast":[]}"#)),
            ToolCard(id: "t3", toolName: "weather", kind: .generic, isError: true, errorText: "boom"),
        ]
        for card in cards {
            guard case .card = ToolCardRegistry.resolve(card) else {
                Issue.record("\(card.id) fell back to the generic card")
                continue
            }
        }
        let root = VStack { ForEach(cards) { ToolCardView(card: $0) } }.environment(\.renderDiagnostics, diagnostics)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1400))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(reports.entries.isEmpty)
        window.isHidden = true
    }
}

private final class WeatherReportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var entries: [String] { lock.withLock { stored } }

    func append(_ entry: String) { lock.withLock { stored.append(entry) } }
}
