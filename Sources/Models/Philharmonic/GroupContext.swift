import Foundation

public struct GroupContextSnapshot: Decodable, Sendable, Equatable {
    public struct Part: Decodable, Sendable, Equatable {
        public let key: String
        public let tokens: Int
    }
    public let model: String
    public let contextWindow: Int
    public let total: Int
    public let estimated: Bool
    public let parts: [Part]
}
