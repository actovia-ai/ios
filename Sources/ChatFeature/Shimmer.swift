import SwiftUI

/// The timing and the running rule of the shimmer: the desktop's `ShimmeringText` (2 s sweep, 0.5 s rest, linear, the
/// band `2 × length` points to each side of its centre), kept pure so a test can hold it.
enum Shimmer {
    static let duration: Double = 2
    static let restDuration: Double = 0.5
    static let spreadPerCharacter: Double = 2

    /// How far the band has got, 0 at the right edge's start to 1 at the left edge's end (the desktop sweeps right to
    /// left); `nil` while it rests between two sweeps.
    static func progress(elapsed: Double) -> Double? {
        let cycle = duration + restDuration
        guard elapsed >= 0 else { return nil }
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        return t < duration ? t / duration : nil
    }

    /// Half the band's width in points for a label of `length` characters, never wider than the text itself.
    static func halfBand(length: Int, width: Double) -> Double {
        min(Double(length) * spreadPerCharacter, max(width / 2, 0))
    }

    /// Only the step that is working shimmers: a tool call still waiting for its result, while its turn is live.
    /// A finished step, and anything in settled history, never does.
    static func isRunning(_ step: AssistantTurn.Step, isActive: Bool) -> Bool {
        guard isActive, case .toolCall(let call) = step else { return false }
        return call.isPending
    }
}

extension View {
    /// A light band sweeps across the view's own glyphs, on top of its colour. Layout is untouched (an overlay);
    /// with `isActive` false, or reduce motion on, nothing moves and nothing is drawn.
    func shimmering(_ isActive: Bool, length: Int) -> some View {
        modifier(ShimmerModifier(isActive: isActive, length: length))
    }
}

private struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    let length: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive, !reduceMotion {
            content.overlay { ShimmerBand(length: length).mask(content) }
        } else {
            content
        }
    }
}

struct ShimmerBand: View {
    let length: Int
    /// A fixed point of the sweep, for the snapshots; `nil` runs the clock.
    var frozenProgress: Double?
    @State private var start = Date.now

    var body: some View {
        if let frozenProgress { band(progress: frozenProgress) } else {
            TimelineView(.animation) { context in
                band(progress: Shimmer.progress(elapsed: context.date.timeIntervalSince(start)))
            }
        }
    }

    private func band(progress: Double?) -> some View {
        GeometryReader { proxy in
            let width = Double(proxy.size.width)
            let half = Shimmer.halfBand(length: length, width: width)
            ZStack {
                // The centre travels from half a band past the right edge to half a band past the left one.
                let centre = progress.map { width + half - $0 * (width + 2 * half) }
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .primary, .clear], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(half * 2, 1))
                    .position(x: centre ?? -10_000, y: proxy.size.height / 2)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Shimmer") {
    VStack(alignment: .leading, spacing: 16) {
        Text(verbatim: "Web Fetch: https://www.federalreserve.gov/news…")
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            .shimmering(true, length: 46)
        Text(verbatim: "Web Fetch: settled step")
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            .shimmering(false, length: 23)
    }
    .padding()
}
#endif
