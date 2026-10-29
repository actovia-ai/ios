import MarkdownKit
import SwiftUI

struct ToolCardView: View {
    let card: ToolCard
    @Environment(\.renderDiagnostics) private var diagnostics

    var body: some View {
        switch ToolCardRegistry.resolve(card) {
        case .card(let view):
            view
        case .generic(let issue):
            GenericToolCard(card: card)
                .onAppear {
                    if let issue { diagnostics.report("chat.toolCard", issue.message, issue.attributes) }
                }
        }
    }
}

/// A command the model ran, as one line that opens on its output (`ToolTrace.terminal`): closed after a success,
/// open after a failure.
struct TerminalCard: View {
    let output: ToolPresentation.TerminalOutput

    var body: some View {
        ToolTraceLine(trace: .terminal(output)) {
            TerminalOutputBlock(output: output)
        }
    }
}

/// What a command printed: its output, its errors (red after a failure), the folder it ran in. Cut at twelve lines,
/// with a button to show the rest.
private struct TerminalOutputBlock: View {
    let output: ToolPresentation.TerminalOutput
    @State private var showsAll = false
    private static let collapsedLines = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            outputBody
            if isLong {
                Divider()
                expandButton
            }
            if let cwd = output.cwd {
                Divider()
                Text(verbatim: cwd)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, CardStyle.inset)
                    .padding(.vertical, 6)
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .modifier(CardSurface())
    }

    private var isLong: Bool { ToolPresentation.terminalOutputIsLong(output, collapsedLines: Self.collapsedLines) }

    // A button of its own: a tap on the output must stay free for selecting text.
    private var expandButton: some View {
        Button {
            showsAll.toggle()
        } label: {
            Group {
                if showsAll {
                    Label("ios:chat.message.terminal.showLess", systemImage: "chevron.up")
                } else {
                    Label("ios:chat.message.terminal.showAll", systemImage: "chevron.down")
                }
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var outputBody: some View {
        if output.stdout.isEmpty && output.stderr.isEmpty {
            Text("ios:chat.message.terminal.noOutput")
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, CardStyle.inset)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !output.stdout.isEmpty {
                    Text(verbatim: output.stdout)
                        .lineLimit(showsAll ? nil : Self.collapsedLines)
                }
                if !output.stderr.isEmpty {
                    Text(verbatim: output.stderr)
                        .lineLimit(showsAll ? nil : Self.collapsedLines)
                        .foregroundStyle(output.succeeded ? Color.orange : Color.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CardStyle.inset)
            .padding(.vertical, 8)
        }
    }
}

/// A tool with no card of its own, as one line (`ToolTrace.generic`) that opens on what it was called with and what
/// it gave back; a failure opens on its error. A line with neither does not open.
private struct GenericToolCard: View {
    let card: ToolCard

    var body: some View {
        let parts = GenericTraceDetail(card: card)
        ToolTraceLine(trace: .generic(card), opens: !parts.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                if let arguments = parts.arguments {
                    section(Text("ios:chat.message.trace.arguments"), arguments)
                }
                if let result = parts.result {
                    section(Text("ios:chat.message.trace.result"), result, isError: card.isError)
                }
            }
        }
    }

    private func section(_ title: Text, _ body: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(verbatim: body)
                .font(.caption2.monospaced())
                .foregroundStyle(isError ? Color.red : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CardStyle.inset)
                .padding(.vertical, 8)
                .modifier(CardSurface())
        }
    }
}

/// What a generic tool line opens on, as text: the call's arguments (an empty object is none) and its result — the
/// error for a failure, nothing while it runs.
struct GenericTraceDetail: Equatable {
    let arguments: String?
    let result: String?

    var isEmpty: Bool { arguments == nil && result == nil }

    init(card: ToolCard, maxLines: Int = 200) {
        let isEmptyObject: Bool = if case .object(let fields)? = card.arguments { fields.isEmpty } else { false }
        arguments =
            ToolPresentation.hasPayload(card.arguments) && !isEmptyObject
            ? ToolPresentation.prettyPayload(card.arguments, maxLines: maxLines) : nil
        if card.isError {
            result = card.errorText.flatMap { $0.isEmpty ? nil : $0 }
        } else if ToolPresentation.hasPayload(card.payload) {
            result = ToolPresentation.prettyPayload(card.payload, maxLines: maxLines)
        } else {
            result = nil
        }
    }
}
