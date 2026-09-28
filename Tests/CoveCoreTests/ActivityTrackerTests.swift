import Foundation
import Testing
@testable import CoveCore

@Suite struct ActivityTrackerTests {
    func toolUse(_ id: String, _ name: String, _ input: [String: String]) -> TranscriptEvent {
        .assistant(.toolUse(id: id, name: name, input: ToolInput(input)), stopReason: "tool_use", timestamp: nil)
    }
    func result(_ id: String, error: Bool = false, task: String? = nil) -> TranscriptEvent {
        .toolResult(toolUseID: id, isError: error, taskID: task, timestamp: nil)
    }
    let prompt = TranscriptEvent.humanPrompt(text: "go", timestamp: nil, cwd: nil, gitBranch: nil)

    @Test func phaseFollowsATurn() {
        var tracker = ActivityTracker()
        #expect(tracker.phase == .idle)
        tracker.apply(prompt)
        #expect(tracker.phase == .thinking(since: nil))
        tracker.apply(toolUse("t1", "Bash", ["command": "swift build", "description": "Build the package"]))
        #expect(tracker.phase == .running(ToolActivity(toolName: "Bash", verb: "Running", detail: "Build the package"), since: nil))
        tracker.apply(result("t1"))
        #expect(tracker.phase == .thinking(since: nil))
        tracker.apply(.assistant(.text("All done."), stopReason: "end_turn", timestamp: nil))
        #expect(tracker.phase == .awaitingUser(since: nil))
    }

    @Test func streamingTextWithoutStopReasonIsStillThinking() {
        var tracker = ActivityTracker()
        tracker.apply(prompt)
        tracker.apply(.assistant(.text("Let me look"), stopReason: nil, timestamp: nil))
        #expect(tracker.phase == .thinking(since: nil))
    }

    @Test func describesCommonTools() {
        #expect(ToolActivity.describe(name: "Bash", input: ToolInput(["command": "ls -la\npwd"])).detail == "ls -la")
        #expect(ToolActivity.describe(name: "Edit", input: ToolInput(["file_path": "/a/b/View.swift"])) ==
            ToolActivity(toolName: "Edit", verb: "Editing", detail: "View.swift"))
        #expect(ToolActivity.describe(name: "Read", input: ToolInput(["file_path": "/x/README.md"])).verb == "Reading")
        #expect(ToolActivity.describe(name: "Grep", input: ToolInput(["pattern": "TODO"])).detail == "TODO")
        #expect(ToolActivity.describe(name: "WebFetch", input: ToolInput(["url": "https://github.com/a/b"])).detail == "github.com")
        #expect(ToolActivity.describe(name: "mcp__computer-use__screenshot", input: ToolInput([:])) ==
            ToolActivity(toolName: "mcp__computer-use__screenshot", verb: "Using", detail: "computer-use · screenshot"))
    }

    @Test func rebuildsTaskBoard() {
        var tracker = ActivityTracker()
        tracker.apply(toolUse("c1", "TaskCreate", ["subject": "Write parser"]))
        tracker.apply(result("c1", task: "1"))
        tracker.apply(toolUse("c2", "TaskCreate", ["subject": "Wire UI"]))
        tracker.apply(result("c2", task: "2"))
        tracker.apply(toolUse("u1", "TaskUpdate", ["taskId": "1", "status": "completed"]))
        tracker.apply(result("u1"))
        tracker.apply(toolUse("u2", "TaskUpdate", ["taskId": "2", "status": "in_progress", "subject": "Wire the UI"]))
        tracker.apply(result("u2"))
        #expect(tracker.board.tasks.map(\.subject) == ["Write parser", "Wire the UI"])
        #expect(tracker.board.completedCount == 1)
        #expect(tracker.board.tasks.last?.status == .inProgress)
        tracker.apply(toolUse("u3", "TaskUpdate", ["taskId": "1", "status": "deleted"]))
        tracker.apply(result("u3"))
        #expect(tracker.board.tasks.map(\.id) == ["2"])
    }

    @Test func failedCreateDoesNotAddTask() {
        var tracker = ActivityTracker()
        tracker.apply(toolUse("c1", "TaskCreate", ["subject": "x"]))
        tracker.apply(result("c1", error: true))
        #expect(tracker.board.tasks.isEmpty)
    }

    @Test func recordsSuccessfulFileChangesMostRecentFirst() {
        var tracker = ActivityTracker()
        tracker.apply(toolUse("w1", "Write", ["file_path": "/p/New.swift"]))
        tracker.apply(result("w1"))
        tracker.apply(toolUse("e1", "Edit", ["file_path": "/p/Old.swift"]))
        tracker.apply(result("e1"))
        tracker.apply(toolUse("e2", "Edit", ["file_path": "/p/Broken.swift"]))
        tracker.apply(result("e2", error: true))
        tracker.apply(toolUse("e3", "Edit", ["file_path": "/p/New.swift"]))
        tracker.apply(result("e3"))
        #expect(tracker.changes.files.map(\.path) == ["/p/New.swift", "/p/Old.swift"])
        #expect(tracker.changes.files.first?.editCount == 2)
        #expect(tracker.changes.files.first?.created == true)
        #expect(tracker.changes.files.last?.created == false)
    }

    @Test func takesLineCountsFromCostState() {
        var tracker = ActivityTracker()
        tracker.apply(.cost(linesAdded: 40, linesRemoved: 3, costUSD: 0.5))
        tracker.apply(.cost(linesAdded: 52, linesRemoved: 7, costUSD: 0.7))
        #expect(tracker.linesAdded == 52)
        #expect(tracker.linesRemoved == 7)
    }

    @Test func interruptionHandsTheTurnBackToTheUser() {
        var tracker = ActivityTracker()
        tracker.apply(prompt)
        tracker.apply(toolUse("t1", "Bash", ["command": "ls"]))
        tracker.apply(.interrupted(timestamp: nil))
        #expect(tracker.phase == .awaitingUser(since: nil))
        tracker.apply(result("t1"))
        #expect(tracker.phase == .awaitingUser(since: nil))
    }
}
