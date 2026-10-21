// Sources/HealthFeature/Trends/TrendStatsHeader.swift
import SwiftUI

/// The three numbers over the calendar: average sleep, daily steps and HRV, each against the period before. Side by
/// side; one under another at accessibility sizes.
struct TrendStatsHeader: View {
    let scope: TrendScope
    let current: Aggregates?
    let previous: Aggregates?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            ForEach(TrendMetric.allCases, id: \.self) { metric in tile(metric) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ metric: TrendMetric) -> some View {
        let value = current.flatMap(metric.value)
        let change = TrendMath.change(value, from: previous.flatMap(metric.value))
        // Which way it moved sits on the value's own line; how much, and against what, under it. Unchanged — or
        // nothing to compare with — the tile is its name and its number, without a bare arrow line.
        let moved = change.flatMap { $0.direction == .flat ? nil : $0 }
        return VStack(alignment: .leading, spacing: 3) {
            Text(metric.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value.map(metric.format) ?? "—")
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let moved {
                    Image(systemName: moved.direction == .up ? "arrow.up" : "arrow.down")  // l10n:ignore: SF Symbol names
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrendText.color(moved))
                }
            }
            if let moved {
                Text(verbatim: TrendText.amount(moved, metric: metric))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrendText.color(moved))
                Text(scope.versusLabel).font(.caption2).foregroundStyle(.secondary)
            }
        }
        // Tiles side by side keep one height whatever each one says.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(HealthSurface.card, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrendText.spoken(metric: metric, value: value, change: change, scope: scope)))
    }
}
