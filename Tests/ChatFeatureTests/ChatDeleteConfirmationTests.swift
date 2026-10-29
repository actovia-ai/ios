import Models
import Testing

@testable import ChatFeature

@Suite("ChatDeleteConfirmation (ISSUE-112: a chat is deleted only after a confirmation)")
struct ChatDeleteConfirmationTests {
    @Test("names the chat, its title's white space collapsed")
    func namesTheChat() {
        let chat = ChatSummary(id: "c1", title: "Trip  to\nKyoto", createdAt: "2026-10-29T00:00:00.000Z")
        let message = ChatDeleteConfirmation.message(for: chat)
        #expect(message.contains("Trip to Kyoto"))
    }
}
