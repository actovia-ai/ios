// One line per conversation event of the desktop's `PhilharmonicSseEvent` (packages/shared/src/types/philharmonic.ts),
// then a task-scoped event and one no build knows: both must decode to `.unknown`.
enum PhilharmonicFixtures {
    static let card = #"""
        {"kind":"agent_card","sessionId":"s1","agentId":"a1","runtime":"claude-code","model":"opus","projectName":"site","cwd":"/w/site","branch":"main","state":"blocked","steps":[{"id":"t1","tool":"Bash","summary":"npm test","status":"ok"}],"blocks":["Ran the tests."],"pending":"","prompts":[{"kind":"permission","requestId":"r1","tool":"Write","summary":"src/a.ts","detail":"export const a = 1"},{"kind":"question","requestId":"r2","questions":[{"question":"Which?","multiSelect":false,"options":[{"label":"A"},{"label":"B","description":"the other"}]}]}],"notices":[],"costUsd":0.12,"denials":0,"error":null,"continuedInTerminal":false,"queued":false}
        """#

    static let step = #"""
        {"id":"st1","planId":"p1","ordinal":0,"title":"Draft","intent":null,"assignedAgentId":"a1","status":"pending","output":null,"note":null,"taskId":null,"startedAt":null,"completedAt":null}
        """#

    static let plan = #"""
        {"id":"p1","conversationId":"c1","summary":"Ship it","status":"active","createdAt":"2026-10-23T01:00:00.000Z","updatedAt":"2026-10-23T01:00:00.000Z","steps":[\#(step)]}
        """#

    static let events: [String] = [
        #"{"type":"message_start","conversationId":"c1","messageId":"m1","role":"pm"}"#,
        #"{"type":"message_delta","conversationId":"c1","messageId":"m1","delta":"Hello so far"}"#,
        #"{"type":"message_end","conversationId":"c1","messageId":"m1"}"#,
        #"{"type":"tool_card","conversationId":"c1","messageId":"m2","toolName":"web_search","phase":"end","result":{"ok":true}}"#,
        #"{"type":"agent_card","conversationId":"c1","messageId":"m3","card":\#(card)}"#,
        #"{"type":"member_joined","conversationId":"c1","agentId":"a2"}"#,
        #"{"type":"round_start","conversationId":"c1","label":"[Scheduled] nightly"}"#,
        #"{"type":"ask_user","conversationId":"c1","question":"Which colour?","options":["Red","Blue"]}"#,
        #"{"type":"conversation_error","conversationId":"c1","error":"No key"}"#,
        #"{"type":"pm_started","conversationId":"c1"}"#,
        #"{"type":"pm_ended","conversationId":"c1","reason":"done"}"#,
        #"{"type":"delegation_retry","conversationId":"c1","taskId":"t1","agentId":"a1","attempt":2,"delayMs":4000,"error":"busy"}"#,
        #"{"type":"plan_created","conversationId":"c1","plan":\#(plan)}"#,
        #"{"type":"plan_step_updated","conversationId":"c1","stepId":"st1","patch":{"status":"running","note":null}}"#,
        #"{"type":"plan_step_appended","conversationId":"c1","step":\#(step)}"#,
        #"{"type":"plan_status_changed","conversationId":"c1","status":"completed"}"#,
        #"{"type":"task_status","taskId":"t1","status":"running"}"#,
        #"{"type":"future_event","conversationId":"c1"}"#,
    ]
}
