import Foundation

/// A conversation once a run has ended, under protocol 2 (desktop spec 2026-10-01 §C2): the server's `done` carries the
/// run as stored — its question, then its answer — and every regenerate group's state, not the whole conversation
/// again. The run's local copies (the optimistic question, the streamed answer) are replaced by the stored run where they
/// stood; a run not shown yet goes at the end; then every run takes its stored state. The desktop's `mergeRun`
/// (`packages/shared/src/utils/run-merge.ts`), to the same vectors.
public enum RunMerge {
    public static func merge(
        _ messages: [ChatMessage], run: [ChatMessage], attempts: [String: RunAttempt]
    ) -> [ChatMessage] {
        guard let runId = run.first?.runId else { return applying(attempts, to: messages) }
        let at = messages.firstIndex { $0.runId == runId }
        let others = messages.filter { $0.runId != runId }
        let merged: [ChatMessage]
        if let at {
            merged = Array(others[..<at]) + run + Array(others[at...])
        } else {
            merged = others + run
        }
        return applying(attempts, to: merged)
    }

    /// Each user message's `attempt` set to the stored one (none when the map has none) — the desktop's `applyAttempts`.
    public static func applying(_ attempts: [String: RunAttempt], to messages: [ChatMessage]) -> [ChatMessage] {
        messages.map { message in
            guard message.role == "user" else { return message }
            let next = attempts[message.id]
            guard message.attempt != next else { return message }
            var copy = message
            copy.raw["attempt"] = next.map { .string($0.rawValue) } ?? .null
            return copy
        }
    }
}
