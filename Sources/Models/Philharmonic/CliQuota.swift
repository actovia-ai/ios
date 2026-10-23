import Foundation

/// What a coding agent's CLI last reported of the owner's quota (`GET /api/v1/agents/quota`). Times in epoch ms.
public struct CliQuota: Decodable, Sendable, Equatable {
    public enum State: String, Sendable, Equatable, WireEnum {
        case ok, warning, rejected, unknown
        static let unknownCase = State.unknown
        public init(from decoder: Decoder) throws { try self.init(wire: decoder) }
    }

    public struct Window: Decodable, Sendable, Equatable {
        /// `five_hour`, `seven_day`, a model's own window, Codex `primary` / `secondary` / `<limit> primary`.
        public let name: String
        /// 0–100.
        public let usedPercent: Double
        public let resetsAt: Double?
        /// Set when the window counts one model only (e.g. `opus`).
        public let model: String?
        /// The CLI said this window stopped it, until `resetsAt`.
        public let rejected: Bool?
        /// When a window with no `resetsAt` was first read.
        public let seenAt: Double?
        /// The window's length when the CLI says it: 300 is the 5-hour, 10080 the week.
        public let durationMins: Double?

        public init(
            name: String, usedPercent: Double, resetsAt: Double? = nil, model: String? = nil, rejected: Bool? = nil,
            seenAt: Double? = nil, durationMins: Double? = nil
        ) {
            self.name = name
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
            self.model = model
            self.rejected = rejected
            self.seenAt = seenAt
            self.durationMins = durationMins
        }
    }

    public let cli: String
    public let windows: [Window]
    /// The CLI's own verdict, never inferred from the percentages.
    public let state: State
    public let rejectedWindow: String?
    /// May the CLI run past the limit at a cost.
    public let overage: Bool
    /// When this was reported.
    public let asOf: Double

    public init(
        cli: String, windows: [Window], state: State, rejectedWindow: String? = nil, overage: Bool = false,
        asOf: Double
    ) {
        self.cli = cli
        self.windows = windows
        self.state = state
        self.rejectedWindow = rejectedWindow
        self.overage = overage
        self.asOf = asOf
    }
}
