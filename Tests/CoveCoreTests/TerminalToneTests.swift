import Testing
@testable import CoveCore

@Suite struct TerminalToneTests {
    @Test func followsClaudeThemeSetting() {
        #expect(TerminalTone.resolve(claudeTheme: "dark", systemIsDark: false) == .dark)
        #expect(TerminalTone.resolve(claudeTheme: "dark-daltonized", systemIsDark: false) == .dark)
        #expect(TerminalTone.resolve(claudeTheme: "light", systemIsDark: true) == .light)
        #expect(TerminalTone.resolve(claudeTheme: "light-ansi", systemIsDark: true) == .light)
    }

    @Test func autoFollowsTheSystem() {
        #expect(TerminalTone.resolve(claudeTheme: "auto", systemIsDark: true) == .dark)
        #expect(TerminalTone.resolve(claudeTheme: "auto", systemIsDark: false) == .light)
    }

    @Test func unsetMeansCLIDefaultWhichIsDark() {
        #expect(TerminalTone.resolve(claudeTheme: nil, systemIsDark: false) == .dark)
    }

    @Test func readsThemeFromSettingsJSON() {
        #expect(TerminalTone.claudeTheme(fromSettings: #"{"model":"x","theme":"light"}"#) == "light")
        #expect(TerminalTone.claudeTheme(fromSettings: "{}") == nil)
        #expect(TerminalTone.claudeTheme(fromSettings: "garbage") == nil)
    }
}
