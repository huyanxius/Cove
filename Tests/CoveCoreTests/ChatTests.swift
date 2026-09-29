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

    @Test func surfacesRejectedControlRequestsAndStatusModes() {
        let error = #"{"type":"control_response","response":{"subtype":"error","request_id":"m","error":"Cannot set permission mode to bypassPermissions"}}"#
        #expect(StreamEvent.parse(error) == [.controlError("Cannot set permission mode to bypassPermissions")])
        let status = #"{"type":"system","subtype":"status","status":null,"permissionMode":"plan"}"#
        #expect(StreamEvent.parse(status) == [.permissionMode("plan")])
        var log = ChatLog()
        log.apply(.controlError("nope"))
        #expect(log.items.last?.kind == .notice("操作没有生效：nope"))
        #expect(ClaudeLaunch.streamArguments(.new(sessionID: "a"), allowBypass: true).contains("--allow-dangerously-skip-permissions"))
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
    typealias S = MarkdownBlocks.Segment

    @Test func splitsParagraphsHeadingsAndCode() {
        let text = "第一段\n还是第一段\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n## 标题"
        #expect(MarkdownBlocks.split(text) == [
            .paragraph(S("第一段\n还是第一段", start: 0)),
            .code(language: "swift", S("let a = 1\n\nlet b = 2", start: 20)),
            .heading(level: 2, S("标题", start: 48)),
        ])
    }

    @Test func parsesListsTasksQuotesAndRules() {
        let text = "- 一\n  - 二\n1. 三\n- [ ] 未完成\n- [x] 完成\n\n> 引用\n> 第二行\n\n---"
        let blocks = MarkdownBlocks.split(text)
        guard case let .list(items) = blocks[0] else { Issue.record("expected list"); return }
        #expect(items.map(\.marker) == [.bullet, .bullet, .number(1), .task(done: false), .task(done: true)])
        #expect(items.map(\.level) == [0, 1, 0, 0, 0])
        #expect(items.map(\.text.text) == ["一", "二", "三", "未完成", "完成"])
        guard case let .quote(lines) = blocks[1] else { Issue.record("expected quote"); return }
        #expect(lines.map(\.text) == ["引用", "第二行"])
        #expect(blocks[2] == .rule)
    }

    @Test func parsesTablesWithAlignment() {
        let text = "| 功能 | 状态 | 备注 |\n|:---|:---:|---:|\n| 流式 | 正常 | 左 |\n| 长 | 测试 |"
        #expect(MarkdownBlocks.split(text) == [
            .table(header: ["功能", "状态", "备注"], alignments: [.leading, .center, .trailing],
                   rows: [["流式", "正常", "左"], ["长", "测试", ""]]),
        ])
    }

    @Test func boldLineIsNotAList() {
        #expect(MarkdownBlocks.split("**粗体**开头") == [.paragraph(S("**粗体**开头", start: 0))])
    }

    @Test func unterminatedFenceStillRendersAsCode() {
        #expect(MarkdownBlocks.split("```\nwhile true") == [.code(language: "", S("while true", start: 4))])
    }

    /// 每段文字按起点取回原文，必须一字不差——流式渐显靠它对齐到达时间。
    @Test func segmentsPointBackIntoTheSource() {
        let text = "ab\n\n  ## 标题 \n- [ ] 任务\n> 引用\n```swift\nlet a = 1\n```\n第一行\n第二行"
        let characters = Array(text)
        var segments: [S] = []
        for block in MarkdownBlocks.split(text) {
            switch block {
            case let .paragraph(s), let .heading(_, s), let .code(_, s): segments.append(s)
            case let .list(items): segments += items.map(\.text)
            case let .quote(lines): segments += lines
            case .table, .rule: break
            }
        }
        #expect(segments.count == 6)
        for segment in segments {
            #expect(String(characters[segment.start..<segment.start + segment.text.count]) == segment.text)
        }
    }
}

@Suite struct CodeHighlighterTests {
    func kinds(_ code: String, _ language: String) -> [String: CodeHighlighter.Kind] {
        let chars = Array(code)
        var result: [String: CodeHighlighter.Kind] = [:]
        for span in CodeHighlighter.spans(code, language: language) { result[String(chars[span.range])] = span.kind }
        return result
    }

    @Test func highlightsCommonTokens() {
        let found = kinds("function greet(name) {\n  return `hi ${name}`; // 注释\n}\nlet n = 42", "ts")
        #expect(found["function"] == .keyword)
        #expect(found["return"] == .keyword)
        #expect(found["`hi ${name}`"] == .string)
        #expect(found["// 注释"] == .comment)
        #expect(found["42"] == .number)
    }

    @Test func hashIsACommentOnlyWhereItShouldBe() {
        #expect(kinds("x = 1 # note", "python")["# note"] == .comment)
        #expect(kinds("a # b", "swift")["# b"] == nil)
        #expect(CodeHighlighter.spans("plain text block", language: "").isEmpty)
    }

    @Test func diffColorsWholeLines() {
        let found = kinds("@@ -1 +1 @@\n- old line\n+ new line\n same", "diff")
        #expect(found["- old line"] == .removed)
        #expect(found["+ new line"] == .added)
        #expect(found["@@ -1 +1 @@"] == .hunk)
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

@Suite struct InlineMarkdownTests {
    func boldText(_ value: AttributedString) -> [String] {
        value.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { String(value[$0.range].characters) }
    }

    @Test func boldWorksWhenPunctuationMeetsChinese() {
        let value = InlineMarkdown.attributed("前端是拿**若依(RuoYi)**改的")
        #expect(String(value.characters) == "前端是拿若依(RuoYi)改的")
        #expect(boldText(value) == ["若依(RuoYi)"])
    }

    @Test func keepsOtherInlineSyntax() {
        let value = InlineMarkdown.attributed("看 `gitee.com` 和 **两处**")
        #expect(String(value.characters) == "看 gitee.com 和 两处")
        #expect(boldText(value) == ["两处"])
    }
}
