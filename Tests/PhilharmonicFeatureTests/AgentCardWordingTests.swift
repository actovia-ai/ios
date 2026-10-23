import Models
import Testing

@testable import PhilharmonicFeature

/// The desktop's `lib/agent-card.ts` and `lib/tool-label.ts`.
@Suite("AgentCardWording")
struct AgentCardWordingTests {
    private func step(_ id: Int) -> AgentCard.Step {
        AgentCard.Step(id: "\(id)", tool: "Bash", summary: "", status: .ok)
    }

    @Test("the last six steps show; the rest are counted")
    func visibleStepsKeepsTheLastSix() {
        let card = AgentCard(
            sessionId: "s", agentId: "a", runtime: "claude-code", projectName: "P", cwd: "/p", state: .working,
            steps: (1...8).map(step))
        let visible = AgentCardWording.visibleSteps(card)
        #expect(visible.hidden == 2)
        #expect(visible.shown.map(\.id) == ["3", "4", "5", "6", "7", "8"])
    }

    @Test("queued wins over the state; blocked reads as waiting, error as failed")
    func stateWord() {
        #expect(AgentCardWording.stateKey(Fx.card(state: .working, queued: true)) == "queued")
        #expect(AgentCardWording.stateKey(Fx.card(state: .blocked)) == "waiting")
        #expect(AgentCardWording.stateKey(Fx.card(state: .error)) == "failed")
        #expect(AgentCardWording.stateKey(Fx.card(state: .done)) == "done")
    }

    @Test("a tool's name as a person reads it; an MCP tool names its server")
    func toolLabels() {
        #expect(AgentCardWording.toolLabel("Bash") == "Bash")
        #expect(AgentCardWording.toolLabel("WebFetch") == "Web Fetch")
        #expect(AgentCardWording.toolLabel("read_file") == "Read File")
        #expect(AgentCardWording.cliToolLabel("mcp__plugin_playwright_playwright__browser_run_code_unsafe")
            == "Playwright · Browser Run Code Unsafe")
        #expect(AgentCardWording.cliToolLabel("mcp__github__create_issue") == "Github · Create Issue")
        #expect(AgentCardWording.toolLabel("mcp_tools") == "MCP Tools")
    }

    @Test("paths under the run's folder lose the folder")
    func relativeSummary() {
        #expect(AgentCardWording.relativeSummary("Read /tmp/atlas/src/app.ts", cwd: "/tmp/atlas/") == "Read src/app.ts")
        #expect(AgentCardWording.relativeSummary("ls /tmp/atlas", cwd: "/tmp/atlas") == "ls .")
        #expect(AgentCardWording.relativeSummary("cat /tmp/atlas2/x", cwd: "/tmp/atlas") == "cat /tmp/atlas2/x")
        #expect(AgentCardWording.relativeSummary("pwd", cwd: "/") == "pwd")
    }
}
