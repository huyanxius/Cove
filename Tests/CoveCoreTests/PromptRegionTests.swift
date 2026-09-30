import Testing
@testable import CoveCore

@Suite struct PromptRegionTests {
    let rule = String(repeating: "─", count: 60)

    @Test func findsClaudeInputBox() {
        let screen = ["● done", "", rule, "❯ ", rule, "  Opus 5.5 | ctx: 5%", "  ⏵⏵ auto mode on"]
        #expect(PromptRegion.hiddenFrom(screen) == 2)
    }

    @Test func findsMultilineClaudeInput() {
        let screen = ["text", rule, "❯ first line", "  second line", rule, "status"]
        #expect(PromptRegion.hiddenFrom(screen) == 1)
    }

    @Test func leavesClaudePermissionMenusVisible() {
        let screen = [rule, " Bash command", "   ls -la", " Do you want to proceed?", " ❯ 1. Yes", "   2. No", ""]
        #expect(PromptRegion.hiddenFrom(screen) == nil)
    }

    @Test func findsGeminiStyleBoxForAgy() {
        let screen = ["answer", "╭────────────────────────────╮", "│ >   Type your message      │", "╰────────────────────────────╯", "~/code   model"]
        #expect(PromptRegion.hiddenFrom(screen) == 1)
    }

    @Test func findsCodexComposer() {
        let screen = ["• Ran tests", "", "› Ask Codex to do anything", "", "  ⏎ send   ⌃J newline   ⌃T transcript"]
        #expect(PromptRegion.hiddenFrom(screen) == 2)
    }

    @Test func leavesCodexApprovalMenusVisible() {
        let screen = ["Allow command?", "› 1. Yes, proceed", "  2. No"]
        #expect(PromptRegion.hiddenFrom(screen) == nil)
    }

    @Test func ignoresPromptsFarFromTheBottom() {
        let screen = [rule, "❯ ", rule] + Array(repeating: "content", count: 30)
        #expect(PromptRegion.hiddenFrom(screen) == nil)
    }
}
