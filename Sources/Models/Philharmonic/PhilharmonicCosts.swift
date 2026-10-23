import Foundation

/// `GET /api/v1/philharmonic/costs?days=7|30`: every figure for the period.
public struct PhilharmonicCosts: Decodable, Sendable, Equatable {
    public struct ByConversation: Decodable, Sendable, Equatable {
        public let conversationId: String
        public let cost: Double
        public let tokens: Int
    }

    public struct ByAgent: Decodable, Sendable, Equatable {
        public let agentId: String
        public let cost: Double
        public let tokens: Int
    }

    public struct Day: Decodable, Sendable, Equatable {
        /// `YYYY-MM-DD`, the computer's local day.
        public let date: String
        public let cost: Double
        public let tokens: Int
    }

    public let totalCost: Double
    public let totalTokens: Int
    public let byConversation: [ByConversation]
    public let byAgent: [ByAgent]
    public let daily: [Day]
}
