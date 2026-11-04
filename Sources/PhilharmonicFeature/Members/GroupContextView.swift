import Models
import SwiftUI

struct GroupContextView: View {
    let snapshot: GroupContextSnapshot
    private let colors: [Color] = [.purple, .pink, .cyan, .orange, .green, .teal, .indigo]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: snapshot.model).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: "\(snapshot.total.formatted()) / \(snapshot.contextWindow.formatted())").font(.subheadline.monospacedDigit())
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(Array(snapshot.parts.enumerated()), id: \.offset) { index, part in
                        colors[index % colors.count].frame(width: max(0, geometry.size.width * CGFloat(part.tokens) / CGFloat(max(1, max(snapshot.contextWindow, snapshot.total)))))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            .background(.fill.tertiary, in: .rect(cornerRadius: 4))
            .clipShape(.rect(cornerRadius: 4))
            ForEach(Array(snapshot.parts.enumerated()), id: \.offset) { index, part in
                HStack(spacing: 8) {
                    Circle().fill(colors[index % colors.count]).frame(width: 8, height: 8)
                    Text(LocalizedStringKey("chat:panel.context.part.\(part.key)"))
                    Spacer()
                    Text(verbatim: part.tokens.formatted()).monospacedDigit().foregroundStyle(.secondary)
                }.font(.caption)
            }
            if snapshot.estimated { Text("chat:panel.context.estimated").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
    }
}
