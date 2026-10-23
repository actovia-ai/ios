import Models
import Testing

@testable import NetworkingKit

@Suite("SSEFrameParsing")
struct SSEFrameParsingTests {
    @Test("decodes a well-formed data line")
    func decodesDataLine() {
        let event = SSEFrameParsing.decodeEvent(
            fromLine: #"data: {"type":"title","title":"héllo 世界"}"#)
        guard case .title(let title) = event else {
            Issue.record("expected .title, got \(String(describing: event))")
            return
        }
        #expect(title == "héllo 世界")
    }

    @Test("ignores lines that aren't a data: frame")
    func ignoresNonDataLines() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "") == nil)
        #expect(SSEFrameParsing.decodeEvent(fromLine: "event: ping") == nil)

        // The two lines above would fail JSON decoding even with no prefix
        // check, so on their own they can't fail for the reason this test is
        // named for. These carry a *valid* event payload behind a non-`data: `
        // field, so only the prefix check can reject them. The control line
        // proves the payload really is decodable.
        let validPayload = #"{"type":"title","title":"x"}"#
        #expect(SSEFrameParsing.decodeEvent(fromLine: "data: \(validPayload)") != nil)
        #expect(SSEFrameParsing.decodeEvent(fromLine: "event: \(validPayload)") == nil)
        #expect(SSEFrameParsing.decodeEvent(fromLine: "retry: \(validPayload)") == nil)
    }

    @Test("ignores a data: line with an empty payload")
    func ignoresEmptyPayload() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "data: ") == nil)
    }

    @Test("ignores genuinely malformed JSON instead of throwing")
    func ignoresMalformedJSON() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: "data: {not json") == nil)
    }
}

private enum ProbeEvent: Decodable, Sendable, Equatable {
    case x(String)
    init(from decoder: Decoder) throws {
        struct Wire: Decodable { let type: String; let value: String? }
        let wire = try Wire(from: decoder)
        guard wire.type == "x" else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not x"))
        }
        self = .x(wire.value ?? "")
    }
}

@Suite("SSEFrameParsing: any event type")
struct SSEFrameParsingGenericTests {
    @Test("a comment line is a comment, not an ignored line")
    func commentLine() {
        guard case .comment = SSEFrameParsing.frame(ProbeEvent.self, fromLine: ": ping") else {
            Issue.record("expected .comment")
            return
        }
    }

    @Test("a data line decodes into the type asked for")
    func decodesIntoGivenType() {
        guard case .event(let event) = SSEFrameParsing.frame(ProbeEvent.self, fromLine: #"data: {"type":"x","value":"v"}"#)
        else {
            Issue.record("expected .event")
            return
        }
        #expect(event == .x("v"))
    }

    @Test("an event of another type is undecodable, with its type named")
    func otherTypeUndecodable() {
        guard case .undecodable(let type, _, _) = SSEFrameParsing.frame(ProbeEvent.self, fromLine: #"data: {"type":"y"}"#)
        else {
            Issue.record("expected .undecodable")
            return
        }
        #expect(type == "y")
    }

    @Test("the chat entry point still ignores a comment")
    func chatIgnoresComment() {
        #expect(SSEFrameParsing.decodeEvent(fromLine: ": ping") == nil)
    }
}
