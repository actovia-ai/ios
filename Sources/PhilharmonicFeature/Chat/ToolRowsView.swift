import SwiftUI

/// An Actovia-runtime employee's tool calls while it writes: one plain row per call, as the desktop draws them.
struct ToolRowsView: View {
    let rows: [ToolRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Image(systemName: "wrench.adjustable")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 6))
                    Text(verbatim: AgentCardWording.toolLabel(row.toolName))
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if row.phase == .end {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 6, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 14,
                        style: .continuous
                    )
                    .strokeBorder(.separator))
            }
        }
    }
}
