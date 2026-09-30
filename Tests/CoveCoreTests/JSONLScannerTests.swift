import Foundation
import Testing
@testable import CoveCore

@Suite struct JSONLScannerTests {
    @Test func keepsTitleAndHumanLinesAndDropsToolResults() {
        let text = """
        {"type":"mode","mode":"normal"}
        {"type":"ai-title","aiTitle":"T"}
        {"parentUuid":"x","type":"user","message":{"content":"hi"}}
        {"type":"user","message":{"content":[{"tool_use_id":"a","type":"tool_result"}]}}
        {"type":"assistant","message":{}}
        """
        let lines = JSONLScanner.lines(in: Data(text.utf8), matching: JSONLScanner.summaryFilter)
        #expect(lines.count == 2)
        #expect(lines.first?.contains("ai-title") == true)
        #expect(lines.last?.contains(#""hi""#) == true)
    }

    @Test func onlyLooksInsideTheWindow() {
        let late = "{" + String(repeating: " ", count: 2000) + #""type":"user"}"#
        let filter = JSONLScanner.Filter(include: [#""type":"user""#], window: 1024)
        #expect(JSONLScanner.lines(in: Data(late.utf8), matching: filter).isEmpty)
    }

    @Test func handlesMissingTrailingNewlineAndBlankLines() {
        let text = "\n\n{\"type\":\"user\",\"n\":1}\n\n{\"type\":\"user\",\"n\":2}"
        let filter = JSONLScanner.Filter(include: [#""type":"user""#])
        #expect(JSONLScanner.lines(in: Data(text.utf8), matching: filter).count == 2)
    }

    @Test func skipsOverlongLines() {
        let huge = #"{"type":"user","blob":""# + String(repeating: "A", count: 300_000) + #""}"#
        let text = huge + "\n" + #"{"type":"user","n":1}"#
        #expect(JSONLScanner.lines(in: Data(text.utf8), matching: JSONLScanner.summaryFilter).count == 1)
    }
}
