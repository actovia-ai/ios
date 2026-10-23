import Foundation
import Models
import Testing

@testable import PhilharmonicFeature

@Suite("QuotaWording (desktop agent-quota.test.ts, quota.test.ts quotaWindowLabel)")
struct QuotaWordingTests {
    private func at(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    @Test("names the account windows, keeps the others, marks a limit")
    func namesWindows() {
        let q = CliQuota(
            cli: "claude-code",
            windows: [
                .init(name: "five_hour", usedPercent: 5.2, resetsAt: 10),
                .init(name: "seven_day", usedPercent: 85, resetsAt: 20),
                .init(name: "seven_day_opus", usedPercent: 100, resetsAt: 30, model: "opus"),
            ], state: .rejected, rejectedWindow: "seven_day_opus", asOf: 1)
        let parts = QuotaWording.parts(q, now: at(0))
        #expect(parts.map(\.key) == [.fiveHour, .sevenDay, .other])
        #expect(parts.map(\.name) == ["five_hour", "seven_day", "opus"])
        #expect(parts.map(\.percent) == [5, 85, 100])
        #expect(parts.map(\.limited) == [false, false, true])
        #expect(parts.map(\.reset) == [false, false, false])
        #expect(parts.map(\.resetsAt) == [at(10), at(20), at(30)])
    }

    @Test("a window past its reset is not limited, and says it reset")
    func pastReset() {
        let q = CliQuota(
            cli: "claude-code", windows: [.init(name: "five_hour", usedPercent: 100, resetsAt: 10, rejected: true)],
            state: .rejected, rejectedWindow: "five_hour", asOf: 1)
        let part = QuotaWording.parts(q, now: at(11))[0]
        #expect(part.limited == false)
        #expect(part.reset == true)
        #expect(part.percent == 100)
    }

    @Test("a carried-over rejected window is limited in an ok record; Codex windows by length")
    func codexByLength() {
        let q = CliQuota(
            cli: "codex",
            windows: [
                .init(name: "primary", usedPercent: 3, resetsAt: 50, durationMins: 300),
                .init(name: "secondary", usedPercent: 9, resetsAt: 60, durationMins: 10080),
                .init(
                    name: "GPT-5.6 Pro secondary", usedPercent: 100, resetsAt: 70, model: "gpt-5.6-pro",
                    rejected: true, durationMins: 10080),
            ], state: .ok, asOf: 1)
        let parts = QuotaWording.parts(q, now: at(5))
        #expect(parts.map(\.key) == [.fiveHour, .sevenDay, .other])
        #expect(parts.map(\.name) == ["primary", "secondary", "gpt-5.6-pro"])
        #expect(parts.map(\.limited) == [false, false, true])
    }

    @Test("a window with no reset time is believed for an hour")
    func noResetGoesStale() {
        let q = CliQuota(
            cli: "claude-code", windows: [.init(name: "five_hour", usedPercent: 100, rejected: true)],
            state: .rejected, rejectedWindow: "five_hour", asOf: 0)
        #expect(QuotaWording.parts(q, now: at(59 * 60_000))[0].limited == true)
        let late = QuotaWording.parts(q, now: at(60 * 60_000))[0]
        #expect(late.stale == true)
        #expect(late.limited == false)
    }

    @Test("names a window as the owner says it")
    func windowLabels() {
        #expect(QuotaWording.windowLabel(.init(name: "five_hour", usedPercent: 0)) == "5-hour")
        #expect(QuotaWording.windowLabel(.init(name: "seven_day", usedPercent: 0)) == "week")
        #expect(
            QuotaWording.windowLabel(.init(name: "seven_day_opus", usedPercent: 0, model: "opus")) == "opus only: week")
        #expect(QuotaWording.windowLabel(.init(name: "primary", usedPercent: 0)) == "primary")
        #expect(QuotaWording.windowLabel(.init(name: "primary", usedPercent: 0, durationMins: 300)) == "5-hour")
        #expect(
            QuotaWording.windowLabel(
                .init(name: "GPT-5.6 Pro secondary", usedPercent: 0, model: "gpt-5.6-pro", durationMins: 10080))
                == "gpt-5.6-pro only: week")
        #expect(QuotaWording.windowLabel(.init(name: "secondary", usedPercent: 0, durationMins: 60)) == "secondary")
    }
}
