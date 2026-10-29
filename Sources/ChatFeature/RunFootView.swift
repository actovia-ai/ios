import Models
import SwiftUI

/// The run's foot, drawn from `RunFoot` only: the line saying which memories the run read and the strip of what it
/// changed, over the action row (`TurnFoot`). A search's media are in the answer, where it was made.
struct RunFootView: View {
    enum Section {
        case usedMemories, memoryChanges
    }

    let foot: RunFoot
    let section: Section
    var runId = ""
    /// Whether the run still streams.
    var isStreaming = false
    @Environment(\.memoryFoot) private var memoryFoot

    var body: some View {
        switch section {
        case .usedMemories:
            if let memoryFoot {
                UsedMemoriesLine(run: memoryFoot.run(runId), store: memoryFoot)
            }
        case .memoryChanges:
            if let memoryFoot, let changes = RunMemoryChanges(foot.memoryUpdates) {
                MemoryChangeStrip(
                    runId: runId, changes: changes, active: isStreaming, run: memoryFoot.run(runId), store: memoryFoot
                )
                .padding(.top, TurnFootMetrics.blockGap)
                .padding(.bottom, TurnFootMetrics.cardBottom)
            }
        }
    }
}
