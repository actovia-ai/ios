import Models
import SwiftUI

/// A tool call drawn as one line, as the desktop's AI Elements Trace draws it (ISSUE-301): an icon and what happened —
/// "Ran ls", "swift test exited with code 1", "Called drawio_create" — that opens on its detail. A failure is drawn in
/// the destructive colour and opens by itself; a success stays one closed line, since the answer is what is read.
/// Decided here, out of the views, so it can be tested.
struct ToolTrace: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case done, running, failed
    }

    let systemImage: String
    let title: String
    let status: Status
    /// Open before anyone taps it: a failure, whose detail is the reason.
    let startsOpen: Bool

    var isError: Bool { status == .failed }

    /// A command: "Ran …", or "… exited with code N" when it did not exit 0. One with no exit code (a row stored
    /// before the shape was fixed) reads as run.
    static func terminal(_ output: ToolPresentation.TerminalOutput) -> ToolTrace {
        let command = oneLine(output.command)
        if let code = output.exitCode, code != "0" {
            return ToolTrace(systemImage: "terminal", title: exitedText(command, code: code), status: .failed, startsOpen: true)
        }
        return ToolTrace(systemImage: "terminal", title: ranText(command), status: .done, startsOpen: false)
    }

    /// Any other tool without a card of its own (an MCP tool, a result that did not decode): "Called …"; while it
    /// runs, its name; failed, "… failed".
    static func generic(_ card: ToolCard) -> ToolTrace {
        let image = ToolPresentation.systemImage(for: card.toolName)
        if card.isPending {
            return ToolTrace(
                systemImage: image, title: ToolPresentation.displayName(card.toolName), status: .running, startsOpen: false)
        }
        if card.isError {
            return ToolTrace(
                systemImage: image, title: ToolPresentation.failedText(card.toolName), status: .failed, startsOpen: true)
        }
        return ToolTrace(
            systemImage: image, title: calledText(ToolPresentation.displayName(card.toolName)), status: .done,
            startsOpen: false)
    }

    /// A command written over several lines reads as one in the title; the detail keeps it as written.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func ranText(_ command: String) -> String {
        String(
            localized: "ios:chat.message.trace.ran", defaultValue: "Ran \(command)",
            comment: "A terminal command the model ran, as one line of a reply. %@ is the command.")
    }

    static func exitedText(_ command: String, code: String) -> String {
        String(
            localized: "ios:chat.message.trace.exited", defaultValue: "\(command) exited with code \(code)",
            comment: "A terminal command that failed, as one line of a reply. The first %@ is the command, the second its exit code, such as 1 or 127.")
    }

    static func calledText(_ tool: String) -> String {
        String(
            localized: "ios:chat.message.trace.called", defaultValue: "Called \(tool)",
            comment: "A tool the model called, as one line of a reply. %@ is the tool's name.")
    }
}

/// The line of a `ToolTrace`, and the detail it opens on, set in from the line beside a rule. Not openable when it
/// has no detail; the open and close are a plain crossfade, none under Reduce Motion.
struct ToolTraceLine<Detail: View>: View {
    let trace: ToolTrace
    var opens = true
    @ViewBuilder let detail: () -> Detail
    @State private var openState: Bool?
    /// The DEBUG galleries open every line to show what is in it.
    @Environment(\.timelineStartsExpanded) private var startsExpanded
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { opens && (openState ?? (trace.startsOpen || startsExpanded)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if opens {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { openState = !isOpen }
                } label: {
                    line
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: trace.title))
                .accessibilityValue(
                    isOpen ? Text("ios:chat.message.timeline.expanded") : Text("ios:chat.message.timeline.collapsed"))
            } else {
                line
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: trace.title))
            }
            if isOpen {
                detail()
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 1)
                            .padding(.leading, 7)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var line: some View {
        HStack(spacing: 6) {
            Image(systemName: trace.systemImage)
                .imageScale(.small)
                .frame(width: 16)
                .accessibilityHidden(true)
            // Cut in the middle: a failure's code is at the end of a long command.
            Text(verbatim: trace.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .shimmering(trace.status == .running, length: trace.title.count)
            if opens {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .font(.footnote)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline)
        .foregroundStyle(trace.isError ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
        .contentShape(.rect)
        .footRowTarget()
    }
}
