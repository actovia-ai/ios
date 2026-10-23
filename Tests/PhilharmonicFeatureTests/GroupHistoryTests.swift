import Models
import Testing

@testable import PhilharmonicFeature

@Suite("GroupHistory")
struct GroupHistoryTests {
    @Test("appending keeps one row per id, in either order")
    func dedups() {
        let a = Fx.row("m1"), b = Fx.row("m2"), c = Fx.row("m3")
        #expect(GroupHistory.append([a, b], [b, c]).map(\.id) == ["m1", "m2", "m3"])
        #expect(GroupHistory.append([a], [c, a]).map(\.id) == ["m1", "m3"])
        #expect(GroupHistory.append([], [a, a]).map(\.id) == ["m1"])
    }
}
