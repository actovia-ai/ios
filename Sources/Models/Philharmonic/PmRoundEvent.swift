import Foundation

/// One entry of a PM round's decision trail (`GET …/conversations/:id/rounds/:roundId`): the trigger, the reports
/// read, thinking, text, a tool call or its result, usage or an error — `kind` says which, `payload` holds it.
public struct PmRoundEvent: Decodable, Sendable, Equatable {
    public let seq: Int
    public let kind: String
    public let payload: JSONValue
    public let createdAt: String

    public init(seq: Int, kind: String, payload: JSONValue, createdAt: String) {
        self.seq = seq
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
    }
}
