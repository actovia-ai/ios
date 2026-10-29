import Foundation
import Models
import Testing

@testable import ChatFeature

private func output(_ command: String, exitCode: String?) -> ToolPresentation.TerminalOutput {
    .init(command: command, cwd: "/tmp", exitCode: exitCode, stdout: "", stderr: "")
}

@Suite("Tool trace: a terminal or generic call as one line (ISSUE-301)")
struct ToolTraceTests {
    @Test("a command that exited 0 is one closed line, \"Ran …\", in the quiet colour")
    func terminalSuccess() {
        let trace = ToolTrace.terminal(output("ls -la", exitCode: "0"))
        #expect(trace.title == "Ran ls -la")
        #expect(trace.status == .done)
        #expect(!trace.isError)
        #expect(!trace.startsOpen)
        #expect(trace.systemImage == "terminal")
    }

    @Test("a command that did not exit 0 says its code, is destructive and opens by itself")
    func terminalFailure() {
        let trace = ToolTrace.terminal(output("swift test", exitCode: "1"))
        #expect(trace.title == "swift test exited with code 1")
        #expect(trace.status == .failed)
        #expect(trace.isError)
        #expect(trace.startsOpen)
        #expect(ToolTrace.terminal(output("sleep 9", exitCode: "ETIMEDOUT")).title == "sleep 9 exited with code ETIMEDOUT")
    }

    @Test("a command with no exit code reads as run; one over several lines is one line in the title")
    func terminalEdges() {
        #expect(ToolTrace.terminal(output("pwd", exitCode: nil)) == ToolTrace.terminal(output("pwd", exitCode: "0")))
        #expect(ToolTrace.terminal(output("cd app\n  swift build\n", exitCode: "0")).title == "Ran cd app swift build")
    }

    @Test("a generic call: \"Called …\" when done, its name while it runs, \"… failed\" open in red when it failed")
    func generic() {
        let done = ToolTrace.generic(ToolCard(id: "1", toolName: "drawio_create", kind: .generic))
        #expect(done.title == "Called drawio_create")
        #expect(done.status == .done)
        #expect(!done.startsOpen)
        #expect(done.systemImage == "wrench.and.screwdriver")

        let running = ToolTrace.generic(ToolCard(id: "2", toolName: "computer_use", kind: .generic, isPending: true))
        #expect(running.title == "Computer Use")
        #expect(running.status == .running)
        #expect(!running.startsOpen)

        let failed = ToolTrace.generic(ToolCard(id: "3", toolName: "weather", kind: .generic, isError: true))
        #expect(failed.title == "Weather failed")
        #expect(failed.isError)
        #expect(failed.startsOpen)
    }

    @Test("a generic line opens on its arguments and its result; with neither it does not open")
    func genericDetail() {
        let full = GenericTraceDetail(
            card: ToolCard(
                id: "1", toolName: "drawio_create", kind: .generic, payload: .object(["pages": .number(1)]),
                arguments: .object(["title": .string("Plan")])))
        #expect(full.arguments?.contains("\"title\" : \"Plan\"") == true)
        #expect(full.result?.contains("\"pages\" : 1") == true)

        let bare = GenericTraceDetail(card: ToolCard(id: "2", toolName: "ping", kind: .generic, arguments: .object([:])))
        #expect(bare.isEmpty)

        let failed = GenericTraceDetail(
            card: ToolCard(id: "3", toolName: "weather", kind: .generic, isError: true, errorText: "No such place"))
        #expect(failed.arguments == nil)
        #expect(failed.result == "No such place")

        let running = GenericTraceDetail(
            card: ToolCard(id: "4", toolName: "x", kind: .generic, arguments: .object(["q": .string("a")]), isPending: true))
        #expect(running.arguments != nil)
        #expect(running.result == nil)
    }
}
