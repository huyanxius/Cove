import Foundation
import Testing
@testable import CoveCore

@Suite struct TranscriptEventTests {
    @Test func parsesCustomAndAITitles() {
        #expect(TranscriptEvent.parse(#"{"type":"custom-title","customTitle":"Fix login","sessionId":"s"}"#) == [.customTitle("Fix login")])
        #expect(TranscriptEvent.parse(#"{"type":"ai-title","aiTitle":"尼康Z30连接问题","sessionId":"s"}"#) == [.aiTitle("尼康Z30连接问题")])
    }

    @Test func parsesHumanPromptWithContext() {
        let line = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"帮我看看"},"timestamp":"2026-09-24T13:46:14.285Z","cwd":"/Users/me/app","gitBranch":"main","sessionId":"s"}"#
        guard case let .humanPrompt(text, timestamp, cwd, branch) = TranscriptEvent.parse(line).first else {
            Issue.record("expected humanPrompt"); return
        }
        #expect(text == "帮我看看")
        #expect(cwd == "/Users/me/app")
        #expect(branch == "main")
        #expect(timestamp != nil)
    }

    @Test func parsesHumanPromptFromTextBlocks() {
        let line = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#
        #expect(TranscriptEvent.parse(line) == [.humanPrompt(text: "hello", timestamp: nil, cwd: nil, gitBranch: nil)])
    }

    @Test func ignoresMetaSidechainAndCommandEchoes() {
        let meta = #"{"type":"user","isMeta":true,"message":{"role":"user","content":"Caveat: …"}}"#
        let side = #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent prompt"}}"#
        let echo = #"{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#
        #expect(TranscriptEvent.parse(meta) == [.other])
        #expect(TranscriptEvent.parse(side) == [.other])
        #expect(TranscriptEvent.parse(echo) == [.other])
    }

    @Test func parsesToolUse() {
        let line = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Edit","input":{"replace_all":false,"file_path":"/a/b.swift","old_string":"x","new_string":"y"}}],"stop_reason":"tool_use"}}"#
        #expect(TranscriptEvent.parse(line) == [
            .assistant(.toolUse(id: "toolu_1", name: "Edit",
                                input: ToolInput(["file_path": "/a/b.swift", "old_string": "x", "new_string": "y"])),
                       stopReason: "tool_use", timestamp: nil),
        ])
    }

    @Test func parsesTextAndThinkingBlocks() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":"Done."}],"stop_reason":"end_turn"}}"#
        #expect(TranscriptEvent.parse(line) == [
            .assistant(.thinking, stopReason: "end_turn", timestamp: nil),
            .assistant(.text("Done."), stopReason: "end_turn", timestamp: nil),
        ])
    }

    @Test func parsesToolResultsWithTaskID() {
        let line = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_9","content":"Task #3 created"}]},"toolUseResult":{"task":{"id":"3","subject":"x"}}}"#
        #expect(TranscriptEvent.parse(line) == [.toolResult(toolUseID: "toolu_9", isError: false, taskID: "3", timestamp: nil)])
        let failed = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","is_error":true},{"type":"tool_result","tool_use_id":"b"}]}}"#
        #expect(TranscriptEvent.parse(failed) == [
            .toolResult(toolUseID: "a", isError: true, taskID: nil, timestamp: nil),
            .toolResult(toolUseID: "b", isError: false, taskID: nil, timestamp: nil),
        ])
    }

    @Test func parsesCostState() {
        let line = #"{"type":"cost-state","totalLinesAdded":120,"totalLinesRemoved":8,"totalCostUSD":1.25}"#
        #expect(TranscriptEvent.parse(line) == [.cost(linesAdded: 120, linesRemoved: 8, costUSD: 1.25)])
    }

    @Test func malformedLinesAreOther() {
        #expect(TranscriptEvent.parse("{not json") == [.other])
        #expect(TranscriptEvent.parse("") == [.other])
    }

    @Test func interruptionMarkersAreNotHumanPrompts() {
        let line = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"timestamp":"2026-09-28T04:03:38.339Z"}"#
        guard case .interrupted = TranscriptEvent.parse(line).first else {
            Issue.record("expected .interrupted"); return
        }
        let forTool = #"{"type":"user","message":{"content":"[Request interrupted by user for tool use]"}}"#
        #expect(TranscriptEvent.parse(forTool) == [.interrupted(timestamp: nil)])
    }
}
