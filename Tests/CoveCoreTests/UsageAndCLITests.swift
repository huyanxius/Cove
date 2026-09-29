import Foundation
import Testing
@testable import CoveCore

@Suite struct UsageSnapshotTests {
    let sample = #"""
    {"session_id":"s1","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
     "context_window":{"used_percentage":37.5,"total_input_tokens":120000,"total_output_tokens":8000,
       "current_usage":{"cache_creation_input_tokens":2000,"cache_read_input_tokens":90000}},
     "rate_limits":{"five_hour":{"used_percentage":33,"resets_at":"2026-09-28T09:00:00Z"},
                    "seven_day":{"used_percentage":20,"resets_at":1790600000}},
     "cost":{"total_cost_usd":1.25,"total_duration_ms":600000,"total_api_duration_ms":240000}}
    """#

    @Test func parsesStatusLineInput() throws {
        let u = try #require(UsageSnapshot.parse(Data(sample.utf8)))
        #expect(u.modelName == "Opus 5.5")
        #expect(u.modelID == "claude-opus-5-5")
        #expect(u.contextPercent == 37.5)
        #expect(u.fiveHourPercent == 33)
        #expect(u.sevenDayPercent == 20)
        #expect(u.fiveHourResetsAt != nil)
        #expect(u.sevenDayResetsAt == Date(timeIntervalSince1970: 1790600000))
        #expect(u.inputTokens == 120000 && u.outputTokens == 8000)
        #expect(u.reportedCostUSD == 1.25)
        #expect(u.apiDuration == 240)
    }

    @Test func mergingKeepsLastKnownValues() {
        var old = UsageSnapshot(); old.fiveHourPercent = 45; old.sevenDayPercent = 33; old.contextPercent = 5
        var new = UsageSnapshot(); new.contextPercent = 6; new.modelName = "Opus"
        let merged = new.merged(over: old)
        #expect(merged.fiveHourPercent == 45 && merged.sevenDayPercent == 33)
        #expect(merged.contextPercent == 6 && merged.modelName == "Opus")
    }

    @Test func missingFieldsStayNil() {
        let u = UsageSnapshot.parse(Data(#"{"model":{"display_name":"Sonnet 5"}}"#.utf8))
        #expect(u?.modelName == "Sonnet 5")
        #expect(u?.fiveHourPercent == nil)
        #expect(UsageSnapshot.parse(Data("nope".utf8)) == nil)
    }
}

@Suite struct PriceTableTests {
    @Test func estimatesByModelFamily() {
        let opus = PriceTable.estimate(model: "claude-opus-5-5", input: 1_000_000, output: 1_000_000)
        #expect(abs((opus ?? 0) - 30) < 0.0001)
        let sonnet = PriceTable.estimate(model: "claude-sonnet-5", input: 1_000_000, output: 0)
        #expect(sonnet == 3)
        #expect(PriceTable.estimate(model: "claude-haiku-4-5", input: 0, output: 1_000_000) == 5)
        #expect(PriceTable.estimate(model: "gpt-x", input: 1, output: 1) == nil)
    }
}

@Suite struct CLIKindTests {
    @Test func buildsLaunchArguments() {
        #expect(CLIKind.codex.arguments(resume: nil) == [])
        #expect(CLIKind.agy.executable == "agy")
        #expect(CLIKind.claude.executable == "claude")
        #expect(CLIKind.allCases.map(\.displayName) == ["Claude Code", "Codex", "Antigravity"])
    }

    @Test func claudeSettingsCarryThemeAndStatusLine() throws {
        let json = ClaudeLaunch.settingsJSON(theme: "light", statusLineCommand: "sh '/a b/s.sh'")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["theme"] as? String == "light")
        let status = try #require(object["statusLine"] as? [String: Any])
        #expect(status["command"] as? String == "sh '/a b/s.sh'")
        #expect(status["type"] as? String == "command")
    }

    @Test func settingsArgumentUsesProvidedJSON() {
        #expect(ClaudeLaunch.claudeArguments(.new(sessionID: "a"), settingsJSON: "{}") == ["--session-id", "a", "--settings", "{}"])
    }
}

@Suite struct ScratchSpaceTests {
    @Test func recognizesScratchFolders() {
        let root = URL(fileURLWithPath: "/Users/me/Library/Application Support/Cove/Scratch")
        #expect(ScratchSpace.isScratch(cwd: "/Users/me/Library/Application Support/Cove/Scratch/20260928-1500", root: root))
        #expect(!ScratchSpace.isScratch(cwd: "/Users/me/code", root: root))
        #expect(!ScratchSpace.isScratch(cwd: nil, root: root))
    }

    @Test func namesFoldersByTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_790_577_000)
        #expect(ScratchSpace.folderName(for: date, calendar: calendar) == "20260928-0630")
    }
}
