import Foundation
import Testing
@testable import CoveCore

@Suite struct SessionSummaryTests {
    let url = URL(fileURLWithPath: "/tmp/s.jsonl")
    let now = Date(timeIntervalSince1970: 1_000)

    func summarize(_ lines: [String]) -> SessionSummary? {
        SessionSummarizer.summarize(id: "s", fileURL: url, modified: now, lines: lines.map { Substring($0) })
    }

    let prompt = #"{"type":"user","message":{"content":"first question"},"cwd":"/Users/me/cove","gitBranch":"main"}"#

    @Test func customTitleWinsOverAITitleAndPrompt() {
        let s = summarize([
            prompt,
            #"{"type":"ai-title","aiTitle":"auto one"}"#,
            #"{"type":"custom-title","customTitle":"mine"}"#,
            #"{"type":"ai-title","aiTitle":"auto two"}"#,
        ])
        #expect(s?.title == "mine")
    }

    @Test func lastAITitleWinsOverPrompt() {
        let s = summarize([prompt, #"{"type":"ai-title","aiTitle":"auto one"}"#, #"{"type":"ai-title","aiTitle":"auto two"}"#])
        #expect(s?.title == "auto two")
    }

    @Test func fallsBackToFirstPromptFlattenedAndTruncated() {
        let long = String(repeating: "长", count: 100)
        let s = summarize([#"{"type":"user","message":{"content":"line one\n\nline two"}}"#,
                           #"{"type":"user","message":{"content":"\#(long)"}}"#])
        #expect(s?.title == "line one line two")
        #expect(s?.promptCount == 2)
        let t = summarize([#"{"type":"user","message":{"content":"\#(long)"}}"#])
        #expect(t?.title.count == 81)
        #expect(t?.title.hasSuffix("…") == true)
    }

    @Test func carriesCwdBranchAndProjectName() {
        let s = summarize([prompt])
        #expect(s?.cwd == "/Users/me/cove")
        #expect(s?.gitBranch == "main")
        #expect(s?.projectName == "cove")
        #expect(s?.lastActivity == now)
    }

    @Test func emptySessionsAreDropped() {
        #expect(summarize([#"{"type":"mode","mode":"normal"}"#]) == nil)
    }

    @Test func indexerScansTopLevelTranscriptsNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("-Users-me-cove")
        let sub = project.appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func write(_ name: String, in dir: URL, title: String, age: TimeInterval) throws {
            let file = dir.appendingPathComponent(name)
            try (prompt + "\n" + #"{"type":"ai-title","aiTitle":"\#(title)"}"# + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        try write("old.jsonl", in: project, title: "Old", age: 500)
        try write("new.jsonl", in: project, title: "New", age: 10)
        try write("agent.jsonl", in: sub, title: "Sub", age: 1)

        let sessions = SessionIndexer(root: root).scan()
        #expect(sessions.map(\.title) == ["New", "Old"])
        #expect(sessions.first?.id == "new")
    }

    @Test func locatesTranscriptByIDAcrossProjects() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("-Users-me-中文-dir")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "".write(to: project.appendingPathComponent("abc.jsonl"), atomically: true, encoding: .utf8)
        let indexer = SessionIndexer(root: root)
        #expect(indexer.transcriptURL(for: "abc")?.lastPathComponent == "abc.jsonl")
        #expect(indexer.transcriptURL(for: "missing") == nil)
    }
}
