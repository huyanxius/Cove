import Foundation
import Testing
@testable import CoveCore

@Suite struct SessionOrganizerTests {
    func summary(_ id: String, _ cli: CLIKind = .claude, title: String = "t", cwd: String = "/p", age: TimeInterval) -> SessionSummary {
        SessionSummary(id: id, fileURL: URL(fileURLWithPath: "/dev/null"), title: title, cwd: cwd, gitBranch: nil,
                       lastActivity: Date(timeIntervalSince1970: 1_000_000 - age), promptCount: 0, cli: cli)
    }

    var all: [SessionSummary] {
        [summary("a", age: 10), summary("b", .codex, age: 5), summary("s", cwd: "/scratch/x", age: 1),
         summary("p", .agy, age: 50), summary("z", age: 2)]
    }

    func organize(_ marks: SessionMarks = SessionMarks(), _ filter: SessionFilter = SessionFilter()) -> SessionOrganizer.Sections {
        SessionOrganizer.organize(all, marks: marks, filter: filter) { $0.cwd?.hasPrefix("/scratch") == true }
    }

    @Test func splitsPinnedScratchAndOthersByRecency() {
        var marks = SessionMarks()
        marks.pinned = ["p"]
        let sections = organize(marks)
        #expect(sections.pinned.map(\.id) == ["p"])
        #expect(sections.scratch.map(\.id) == ["s"])
        #expect(sections.others.map(\.id) == ["z", "b", "a"])
    }

    @Test func filtersByCLI() {
        #expect(organize(SessionMarks(), SessionFilter(cli: .codex)).others.map(\.id) == ["b"])
    }

    @Test func archivedSessionsOnlyShowInTheArchiveView() {
        var marks = SessionMarks()
        marks.archived = ["a", "p"]
        marks.pinned = ["p"]
        let normal = organize(marks)
        #expect(!(normal.pinned + normal.scratch + normal.others).contains { ["a", "p"].contains($0.id) })
        let archive = organize(marks, SessionFilter(archivedOnly: true))
        #expect(archive.pinned.isEmpty && archive.others.map(\.id) == ["a", "p"])
    }

    @Test func customTitlesWinAndAreSearchable() {
        var marks = SessionMarks()
        marks.titles = ["b": "登录重构"]
        let sections = organize(marks, SessionFilter(query: "登录"))
        #expect(sections.others.map(\.id) == ["b"])
        #expect(sections.others.first?.title == "登录重构")
    }

    @Test func forgettingClearsEveryMark() {
        var marks = SessionMarks()
        marks.pinned = ["x"]; marks.archived = ["x"]; marks.titles = ["x": "n"]
        marks.forget("x")
        #expect(marks == SessionMarks())
    }

    @Test func resumeCommandsPerCLI() {
        #expect(SessionOrganizer.resumeCommand(for: summary("id1", age: 0)) == "cd '/p' && claude '--resume' 'id1'")
        #expect(SessionOrganizer.resumeCommand(for: summary("t9", .codex, age: 0)) == "cd '/p' && codex 'resume' 't9'")
        #expect(SessionOrganizer.resumeCommand(for: summary("c1", .agy, age: 0)) == "cd '/p' && agy '--conversation' 'c1'")
    }
}
