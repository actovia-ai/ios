import Foundation
import Testing

@testable import ChatFeature

@Suite("OfflineBanner: what the banner says")
struct OfflineBannerTests {
    private let en = Locale(identifier: "en_US")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("with a last sync it says Offline and how long ago")
    func textWithSync() {
        let text = OfflineBanner.text(lastSyncedAt: now.addingTimeInterval(-300), now: now, locale: en)
        #expect(text.contains("Offline"))
        #expect(text.contains("5 min"))
        #expect(text.contains("ago"))
    }

    @Test("without a last sync it is just Offline")
    func textWithoutSync() {
        #expect(OfflineBanner.text(lastSyncedAt: nil, now: now, locale: en) == "Offline")
    }
}
