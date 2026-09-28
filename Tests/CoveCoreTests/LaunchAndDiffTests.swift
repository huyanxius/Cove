import Testing
@testable import CoveCore

@Suite struct ClaudeLaunchTests {
    @Test func buildsArgumentsForNewAndResume() {
        #expect(ClaudeLaunch.claudeArguments(.new(sessionID: "abc")) == ["--session-id", "abc"])
        #expect(ClaudeLaunch.claudeArguments(.resume(sessionID: "abc")) == ["--resume", "abc"])
    }

    @Test func quotesForPOSIXShells() {
        #expect(ClaudeLaunch.shellQuote("plain") == "'plain'")
        #expect(ClaudeLaunch.shellQuote("it's") == #"'it'\''s'"#)
        #expect(ClaudeLaunch.shellQuote("$(rm)") == "'$(rm)'")
    }

    @Test func runsClaudeThroughAnInteractiveLoginShellSoAliasesApply() {
        let command = ClaudeLaunch.shellCommand(shell: "/bin/zsh", claudeArguments: ["--resume", "a b"])
        #expect(command.executable == "/bin/zsh")
        #expect(command.args == ["-l", "-i", "-c", "claude '--resume' 'a b'"])
    }
}

@Suite struct UnifiedDiffTests {
    let sample = """
    diff --git a/f.swift b/f.swift
    index 1..2 100644
    --- a/f.swift
    +++ b/f.swift
    @@ -10,3 +10,4 @@ struct A {
     let a = 1
    -let b = 2
    +let b = 3
    +let c = 4
     let d = 5
    \\ No newline at end of file
    """

    @Test func classifiesLines() {
        let kinds = UnifiedDiff.parse(sample).map(\.kind)
        #expect(kinds == [.meta, .meta, .meta, .meta, .hunk, .context, .removed, .added, .added, .context, .meta])
    }

    @Test func numbersLinesFromHunkHeader() {
        let lines = UnifiedDiff.parse(sample)
        #expect(lines[5].oldLine == 10 && lines[5].newLine == 10)
        #expect(lines[6].oldLine == 11 && lines[6].newLine == nil)
        #expect(lines[7].oldLine == nil && lines[7].newLine == 11)
        #expect(lines[8].newLine == 12)
        #expect(lines[9].oldLine == 12 && lines[9].newLine == 13)
    }

    @Test func stripsTheMarkerColumn() {
        #expect(UnifiedDiff.parse(sample)[7].text == "let b = 3")
    }

    @Test func emptyInputIsEmpty() {
        #expect(UnifiedDiff.parse("").isEmpty)
    }
}
