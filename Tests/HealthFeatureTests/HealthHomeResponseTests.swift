// Tests/HealthFeatureTests/HealthHomeResponseTests.swift
import Foundation
import Models
import Testing

@testable import HealthFeature

/// Holds every note until released, the way the computer takes its time to write one.
actor GatedSummaries: HealthSummaryService {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var open = false
    var holding: Bool { !held.isEmpty }

    func release() {
        open = true
        for waiter in held { waiter.resume() }
        held = []
    }

    func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary {
        if !open { await withCheckedContinuation { held.append($0) } }
        return HealthSummary(
            headline: "h", summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
            memorySuggestion: nil)
    }
}

/// A tap answers at once: nothing on screen waits for the computer to write a note.
@MainActor
struct HealthHomeResponseTests {
    let source = FakeHealthSource()
    let summaries = GatedSummaries()
    let prefs = HealthPreferences(defaults: UserDefaults(suiteName: "response-\(UUID())")!)
    let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: "response-\(UUID())"))

    func model() -> HealthHomeModel {
        HealthHomeModel(
            source: source, summaries: summaries, memory: StubMemory(), cache: cache, preferences: prefs,
            calendar: TestClock.calendar, now: { TestClock.now }, locale: "en")
    }

    func withData() async {
        await source.set { $0.sums[.steps] = [DayValue(day: TestClock.today, value: 9000)] }
    }

    @Test("pull to refresh returns once Apple Health has answered; the note keeps writing in its card")
    func refreshDoesNotWaitForTheNote() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        let note = await m.refresh()
        #expect(m.day?.snapshot.activity?.steps == 9000)
        #expect(m.report == .writing)
        await summaries.release()
        await note.value
        #expect(m.readyHeadline == "h")
    }

    @Test("consent shows the note writing at once, before Apple Health is read again")
    func consentAnswersAtOnce() async {
        await withData()
        let m = model()
        await m.load()
        #expect(m.report == .needsConsent)
        await source.set { $0.gated = true }
        let consent = Task { await m.grantConsent() }
        while await !source.holding { await Task.yield() }
        #expect(m.report == .writing)
        await source.release()
        while await !summaries.holding { await Task.yield() }
        await summaries.release()
        await consent.value
        #expect(m.readyHeadline == "h")
    }
}

private extension HealthHomeModel {
    var readyHeadline: String? {
        if case .ready(let summary) = report { summary.headline } else { nil }
    }
}
