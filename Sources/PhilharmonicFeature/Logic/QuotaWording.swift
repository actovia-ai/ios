import Foundation
import Models

/// One window of a CLI's quota as the members sheet words it.
public struct QuotaPart: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case fiveHour, sevenDay, other
    }

    public let key: Key
    /// The window's name, or the model a window of its own counts.
    public let name: String
    public let percent: Int
    /// Its reset time has passed: the percentage is from before it.
    public let reset: Bool
    /// No reset time, and read over an hour ago: no longer believed.
    public let stale: Bool
    /// The CLI stopped on this window and it has not reset yet.
    public let limited: Bool
    public let resetsAt: Date?
}

/// The desktop's `lib/agent-quota.ts` (`quotaParts`) and `agents/quota.ts` (`quotaWindowLabel`).
public enum QuotaWording {
    private static let keys: [String: QuotaPart.Key] = ["five_hour": .fiveHour, "seven_day": .sevenDay]
    /// Codex names its windows `primary` / `secondary`; the length says which.
    private static let durationKeys: [Double: QuotaPart.Key] = [300: .fiveHour, 10080: .sevenDay]
    private static let labels = ["five_hour": "5-hour", "seven_day": "week"]
    private static let durationLabels: [Double: String] = [300: "5-hour", 10080: "week"]
    private static let noResetBelievedFor: Double = 60 * 60_000

    public static func parts(_ q: CliQuota, now: Date) -> [QuotaPart] {
        let nowMs = now.timeIntervalSince1970 * 1000
        return q.windows.map { w in
            let reset = w.resetsAt.map { $0 <= nowMs } ?? false
            let stale = w.resetsAt == nil && nowMs - (w.seenAt ?? q.asOf) >= noResetBelievedFor
            let rejected =
                w.rejected == true
                || (q.state == .rejected && (w.name == q.rejectedWindow || w.usedPercent >= 100))
            return QuotaPart(
                key: key(of: w), name: w.model ?? w.name, percent: Int(w.usedPercent.rounded()), reset: reset,
                stale: stale, limited: !reset && !stale && rejected,
                resetsAt: w.resetsAt.map { Date(timeIntervalSince1970: $0 / 1000) })
        }
    }

    /// A window as the owner says it: `5-hour`, `week`, `opus only: week`.
    public static func windowLabel(_ w: CliQuota.Window) -> String {
        let suffix = w.model.map { "_\($0.lowercased())" } ?? ""
        let base =
            !suffix.isEmpty && w.name.lowercased().hasSuffix(suffix) ? String(w.name.dropLast(suffix.count)) : w.name
        let label = w.durationMins.flatMap { durationLabels[$0] } ?? labels[base] ?? w.name
        return (w.model.map { "\($0) only: " } ?? "") + label
    }

    private static func key(of w: CliQuota.Window) -> QuotaPart.Key {
        guard w.model == nil else { return .other }
        return w.durationMins.flatMap { durationKeys[$0] } ?? keys[w.name] ?? .other
    }
}
