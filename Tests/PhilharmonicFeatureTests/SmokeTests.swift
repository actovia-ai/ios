import PhilharmonicFeature
import Testing

@Suite("PhilharmonicFeature")
struct SmokeTests {
    @Test("the module links") func links() {
        #expect(String(describing: PhilharmonicPlaceholderView.self).isEmpty == false)
    }
}
