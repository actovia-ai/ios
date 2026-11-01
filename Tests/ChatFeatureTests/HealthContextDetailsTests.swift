import Testing

@testable import ChatFeature

@Suite("Health context display")
struct HealthContextDetailsTests {
    @Test("categorised days become labelled rows, not serialized JSON")
    func days() {
        let sections = HealthContextDetails.sections(
            json:
                #"{"category":"sleep","days":[{"date":"2026-10-31","values":{"asleepMin":440,"deepMin":75,"baselineMin":420},"wake":"07:10"}]}"#
        )
        #expect(sections.count == 1)
        #expect(sections[0].rows.count == 3)
        #expect(
            sections[0].rows.allSatisfy { !$0.value.contains("{") && !$0.value.contains("asleepMin") })
        #expect(sections[0].rows.last?.value == "07:10")
    }

    @Test("bad payloads and unsupported values safely render no details")
    func invalid() {
        #expect(HealthContextDetails.sections(json: "invalid").isEmpty)
        #expect(
            HealthContextDetails.sections(json: #"{"sleep":{"asleepMin":-1,"deepMin":true,"unknown":1}}"#)
                .isEmpty)
        #expect(HealthContextDetails.sections(json: #"{"sleep":{"asleepMin":1e90}}"#).isEmpty)
    }

    @Test("all supported summary categories retain their labels and units")
    func summary() {
        let sections = HealthContextDetails.sections(
            json:
                #"{"sleep":{"asleepHours":7.5},"activity":{"steps":4200,"standHours":4},"recovery":{"hrvMs":52,"respRate":14},"body":{"waterCups":3,"weightKg":68.5}}"#
        )
        #expect(sections.count == 4)
        #expect(sections.map(\.rows.count) == [1, 2, 2, 2])
        #expect(sections[2].rows[0].value.contains("52"))
    }
}
