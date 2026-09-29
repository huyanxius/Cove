import Foundation
import Testing
@testable import CoveCore

/// 行样本取自 claude 2.1.284 `-p --input-format stream-json --output-format stream-json
/// --verbose --include-partial-messages --permission-prompt-tool stdio` 的真实输出，删掉了无关字段。
@Suite struct StreamEventTests {
    @Test func parsesTextDeltaAndBlockStart() {
        let start = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}}"#
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"你好"}}}"#
        #expect(StreamEvent.parse(start) == [.blockStart(.text)])
        #expect(StreamEvent.parse(delta) == [.textDelta("你好")])
    }

    @Test func parsesPermissionRequestKeepingRawInput() throws {
        let line = #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Write","display_name":"Write","input":{"file_path":"/p/hello.txt","content":"hi"},"description":"hello.txt","tool_use_id":"toolu_1"}}"#
        guard case let .permission(request) = StreamEvent.parse(line).first else {
            Issue.record("expected permission"); return
        }
        #expect(request.requestID == "r1")
        #expect(request.toolName == "Write")
        #expect(request.toolUseID == "toolu_1")
        #expect(request.input["file_path"] == "/p/hello.txt")
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(request.rawInput.utf8)) as? [String: Any])
        #expect(raw["content"] as? String == "hi")
    }

    @Test func parsesInitializeResponseCommands() {
        let line = #"{"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[{"name":"compact","description":"Clear history but keep a summary","argumentHint":"<instructions>"},{"name":"review","description":"Review a PR"}]}}}"#
        #expect(StreamEvent.parse(line) == [.commands([
            SlashCommand(name: "compact", description: "Clear history but keep a summary", argumentHint: "<instructions>"),
            SlashCommand(name: "review", description: "Review a PR", argumentHint: ""),
        ])])
    }

    @Test func parsesSessionInfoAndModeChanges() {
        let line = #"{"type":"control_response","response":{"subtype":"success","request_id":"i","response":{"commands":[],"models":[{"value":"default","displayName":"Default (recommended)","description":"Opus 5.5"},{"value":"sonnet","displayName":"Sonnet 5.5"}],"current_permission_mode":"auto"}}}"#
        #expect(StreamEvent.parse(line) == [.commands([]), .sessionInfo(models: [
            ModelOption(value: "default", displayName: "Default (recommended)", description: "Opus 5.5"),
            ModelOption(value: "sonnet", displayName: "Sonnet 5.5", description: ""),
        ], permissionMode: "auto")])
        let mode = #"{"type":"control_response","response":{"subtype":"success","request_id":"m","response":{"mode":"plan"}}}"#
        #expect(StreamEvent.parse(mode) == [.permissionMode("plan")])
    }

    @Test func parsesRateLimitsAndResult() {
        let limits = #"{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.15,"resetsAt":1790686800},"seven_day":{"utilization":0.02,"resetsAt":1791223200}}}}"#
        guard case let .usage(usage) = StreamEvent.parse(limits).first else { Issue.record("expected usage"); return }
        #expect(usage.fiveHourPercent == 15)
        #expect(usage.sevenDayPercent == 2)
        #expect(usage.fiveHourResetsAt == Date(timeIntervalSince1970: 1_790_686_800))

        let result = #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.03,"duration_api_ms":5756}"#
        #expect(StreamEvent.parse(result) == [.turnFinished(error: nil, costUSD: 0.03, apiDuration: 5.756)])
        let failed = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#
        #expect(StreamEvent.parse(failed) == [.turnFinished(error: "boom", costUSD: nil, apiDuration: nil)])
    }

    @Test func parsesContextUsage() {
        let assistant = #"{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":10,"cache_read_input_tokens":17776,"cache_creation_input_tokens":7433,"output_tokens":1}}}"#
        #expect(StreamEvent.parse(assistant).last == .context(tokens: 25219, window: nil))
        let result = #"{"type":"result","is_error":false,"modelUsage":{"claude-haiku-4-5":{"contextWindow":200000},"claude-opus-5-5":{"contextWindow":1000000}}}"#
        #expect(StreamEvent.parse(result).first == .context(tokens: nil, window: 1_000_000))
    }

    @Test func ignoresShellNoiseAndUnknownLines() {
        #expect(StreamEvent.parse("   /\\_/\\    [ Antigravity Core ]") == [])
        #expect(StreamEvent.parse(#"{"type":"system","subtype":"hook_started"}"#) == [])
    }

    @Test func assistantAndToolResultLinesReuseTranscriptParsing() {
        let line = #"{"type":"assistant","message":{"model":"claude-haiku-4-5","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/p/a.txt"}}]}}"#
        let events = StreamEvent.parse(line)
        #expect(events.contains(.transcript(.model("claude-haiku-4-5"))))
        #expect(events.contains { if case .transcript(.assistant(.toolUse(id: "t1", _, _), _, _)) = $0 { true } else { false } })
    }
}

@Suite struct StreamInputTests {
    func object(_ line: String) throws -> [String: Any] {
        #expect(line.hasSuffix("\n"))
        return try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    @Test func encodesUserMessage() throws {
        let o = try object(StreamInput.userMessage("修一下\n登录"))
        #expect(o["type"] as? String == "user")
        let message = try #require(o["message"] as? [String: Any])
        #expect(message["role"] as? String == "user")
        #expect(message["content"] as? String == "修一下\n登录")
    }

    @Test func allowEchoesTheOriginalInput() throws {
        let o = try object(StreamInput.permission(requestID: "r1", allow: true, rawInput: #"{"file_path":"/p","content":"hi"}"#))
        let response = try #require(o["response"] as? [String: Any])
        #expect(response["request_id"] as? String == "r1")
        let decision = try #require(response["response"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        #expect((decision["updatedInput"] as? [String: Any])?["content"] as? String == "hi")
    }

    @Test func denyCarriesAMessage() throws {
        let o = try object(StreamInput.permission(requestID: "r1", allow: false, rawInput: "{}"))
        let decision = try #require((o["response"] as? [String: Any])?["response"] as? [String: Any])
        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["message"] as? String != nil)
    }

    @Test func modeAndModelRequests() throws {
        let mode = try object(StreamInput.setPermissionMode(.acceptEdits, requestID: "m"))
        #expect((mode["request"] as? [String: Any])?["mode"] as? String == "acceptEdits")
        let model = try object(StreamInput.setModel("sonnet", requestID: "s"))
        #expect((model["request"] as? [String: Any])?["subtype"] as? String == "set_model")
    }

    @Test func controlRequests() throws {
        #expect(try object(StreamInput.initialize(requestID: "i")).description.contains("initialize"))
        let interrupt = try object(StreamInput.interrupt(requestID: "x"))
        #expect((interrupt["request"] as? [String: Any])?["subtype"] as? String == "interrupt")
    }

    @Test func streamLaunchArguments() {
        let args = ClaudeLaunch.streamArguments(.resume(sessionID: "abc"))
        #expect(args.starts(with: ["-p", "--input-format", "stream-json", "--output-format", "stream-json"]))
        #expect(args.contains("--include-partial-messages"))
        #expect(args.suffix(4) == ["--permission-prompt-tool", "stdio", "--resume", "abc"])
    }
}

@Suite struct ChatLogTests {
    func tool(_ id: String, _ name: String, _ fields: [String: String]) -> StreamEvent {
        .transcript(.assistant(.toolUse(id: id, name: name, input: ToolInput(fields)), stopReason: nil, timestamp: nil))
    }

    @Test func streamsTextThenReplacesDraftWithFinalBlock() {
        var log = ChatLog()
        log.addPrompt("你好")
        log.apply(.blockStart(.text))
        log.apply(.textDelta("你"))
        log.apply(.textDelta("好呀"))
        #expect(log.draft == "你好呀")
        log.apply(.transcript(.assistant(.text("你好呀！"), stopReason: "end_turn", timestamp: nil)))
        #expect(log.draft == nil)
        #expect(log.items.map(\.kind) == [.prompt("你好"), .reply("你好呀！")])
    }

    @Test func toolCallsResolveWithTheirResults() {
        var log = ChatLog()
        log.apply(tool("t1", "Edit", ["file_path": "/p/View.swift"]))
        log.apply(tool("t2", "Bash", ["command": "swift build"]))
        log.apply(.transcript(.toolResult(toolUseID: "t2", isError: true, taskID: nil, timestamp: nil)))
        log.apply(.transcript(.toolResult(toolUseID: "t1", isError: false, taskID: nil, timestamp: nil)))
        guard case let .tool(first) = log.items[0].kind, case let .tool(second) = log.items[1].kind else {
            Issue.record("expected tools"); return
        }
        #expect(first.state == .done && first.activity.detail == "View.swift" && first.filePath == "/p/View.swift")
        #expect(second.state == .failed)
    }

    @Test func permissionRequestsWaitForAnAnswer() {
        var log = ChatLog()
        log.apply(tool("t1", "Write", ["file_path": "/p/a.txt"]))
        let request = PermissionRequest(requestID: "r1", toolName: "Write", toolUseID: "t1", summary: "a.txt",
                                        input: ToolInput(["file_path": "/p/a.txt"]), rawInput: "{}")
        log.apply(.permission(request))
        #expect(log.pendingPermission?.requestID == "r1")
        log.answer("r1", allowed: false)
        #expect(log.pendingPermission == nil)
        #expect(log.items.last?.kind == .permission(request, answer: .denied))
    }

    @Test func turnEndsClearWorkingStateAndSurfaceErrors() {
        var log = ChatLog()
        log.addPrompt("x")
        #expect(log.isWorking)
        log.apply(.turnFinished(error: "API Error: overloaded", costUSD: nil, apiDuration: nil))
        #expect(!log.isWorking)
        #expect(log.items.last?.kind == .notice("API Error: overloaded"))
    }

    @Test func replaysHistoryFromTranscriptLines() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"帮我看看"},"cwd":"/p"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"好的"}],"stop_reason":"end_turn"}}"#,
        ]
        let log = ChatLog(history: lines)
        #expect(log.items.map(\.kind) == [.prompt("帮我看看"), .reply("好的")])
        #expect(!log.isWorking)
    }
}

@Suite struct MarkdownBlocksTests {
    @Test func splitsParagraphsAndFencedCode() {
        let text = "第一段\n还是第一段\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n# 标题\n- 一\n- 二"
        #expect(MarkdownBlocks.split(text) == [
            .paragraph("第一段\n还是第一段"),
            .code(language: "swift", "let a = 1\n\nlet b = 2"),
            .heading("标题"),
            .paragraph("- 一\n- 二"),
        ])
    }

    @Test func unterminatedFenceStillRendersAsCode() {
        #expect(MarkdownBlocks.split("```\nwhile true") == [.code(language: "", "while true")])
    }
}

@Suite struct SlashCommandTests {
    let commands = [
        SlashCommand(name: "compact", description: "", argumentHint: ""),
        SlashCommand(name: "commit", description: "", argumentHint: ""),
        SlashCommand(name: "review", description: "", argumentHint: ""),
    ]

    @Test func filtersByPrefixOnlyWhileTypingTheCommandName() {
        #expect(SlashCommand.matches(commands, draft: "/co").map(\.name) == ["compact", "commit"])
        #expect(SlashCommand.matches(commands, draft: "/").count == 3)
        #expect(SlashCommand.matches(commands, draft: "/compact now").isEmpty)
        #expect(SlashCommand.matches(commands, draft: "hello /co").isEmpty)
    }

    @Test func hidesInternalAndRemovedCommands() {
        let all = commands + [SlashCommand(name: "__remote-workflow", description: "", argumentHint: ""),
                              SlashCommand(name: "agents", description: "(removed) Ask Claude…", argumentHint: "")]
        #expect(SlashCommand.matches(all, draft: "/").map(\.name) == ["compact", "commit", "review"])
    }
}

@Suite struct InterfaceModeTests {
    @Test func onlyClaudeGetsTheChatSurface() {
        #expect(InterfaceMode.cove.surface(for: .claude) == .chat)
        #expect(InterfaceMode.cove.surface(for: .codex) == .terminal)
        #expect(InterfaceMode.composer.surface(for: .claude) == .terminal)
    }

    @Test func promptAndComposerVisibility() {
        #expect(!InterfaceMode.native.showsComposer && !InterfaceMode.native.hidesCLIPrompt)
        #expect(InterfaceMode.nativeWithComposer.showsComposer && !InterfaceMode.nativeWithComposer.hidesCLIPrompt)
        #expect(InterfaceMode.composer.hidesCLIPrompt)
        #expect(InterfaceMode.cove.hidesCLIPrompt)
    }

    @Test func migratesTheOldToggle() {
        #expect(InterfaceMode.migrated(hideCLIPrompt: nil) == .composer)
        #expect(InterfaceMode.migrated(hideCLIPrompt: true) == .composer)
        #expect(InterfaceMode.migrated(hideCLIPrompt: false) == .nativeWithComposer)
    }
}

@Suite struct AttentionTests {
    func run(_ states: [Attention.State]) -> [Attention.Event?] {
        var attention = Attention()
        return states.map { attention.observe($0) }
    }

    @Test func notifiesOnceWhenWorkFinishes() {
        #expect(run([.working, .working, .idle, .idle]) == [nil, nil, .finished, nil])
    }

    @Test func notifiesWhenApprovalIsNeeded() {
        #expect(run([.working, .needsApproval, .working, .idle]) == [nil, .needsApproval, nil, .finished])
    }

    @Test func firstObservationIsSilent() {
        // 刚打开一个已经空闲的旧会话，不该弹「做完了」。
        #expect(run([.idle, .idle]) == [nil, nil])
    }
}
