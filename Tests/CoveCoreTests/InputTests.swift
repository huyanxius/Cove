import Testing
@testable import CoveCore

@Suite struct KeyRouterTests {
    func route(_ key: KeyStroke.Key, _ mods: KeyStroke.Modifiers = [], empty: Bool) -> KeyRoute {
        KeyRouter.route(KeyStroke(key: key, modifiers: mods), composerIsEmpty: empty)
    }

    @Test func emptyComposerPassesNavigationToTerminal() {
        #expect(route(.up, empty: true) == .terminal([0x1B, 0x5B, 0x41]))
        #expect(route(.down, empty: true) == .terminal([0x1B, 0x5B, 0x42]))
        #expect(route(.right, empty: true) == .terminal([0x1B, 0x5B, 0x43]))
        #expect(route(.left, empty: true) == .terminal([0x1B, 0x5B, 0x44]))
        #expect(route(.escape, empty: true) == .terminal([0x1B]))
        #expect(route(.enter, empty: true) == .terminal([0x0D]))
        #expect(route(.tab, empty: true) == .terminal([0x09]))
        #expect(route(.tab, .shift, empty: true) == .terminal([0x1B, 0x5B, 0x5A]))
    }

    @Test func controlLettersPassThroughWhenEmpty() {
        #expect(route(.character("c"), .control, empty: true) == .terminal([0x03]))
        #expect(route(.character("R"), .control, empty: true) == .terminal([0x12]))
    }

    @Test func typingStaysInComposer() {
        #expect(route(.character("a"), empty: true) == .composer)
        #expect(route(.character("1"), empty: true) == .composer)
        #expect(route(.character("/"), empty: true) == .composer)
    }

    @Test func nonEmptyComposerKeepsEverything() {
        #expect(route(.up, empty: false) == .composer)
        #expect(route(.escape, empty: false) == .composer)
        #expect(route(.enter, empty: false) == .composer)
        #expect(route(.character("c"), .control, empty: false) == .composer)
    }

    @Test func commandShortcutsAlwaysBelongToTheApp() {
        #expect(route(.up, .command, empty: true) == .composer)
        #expect(route(.character("k"), .command, empty: true) == .composer)
    }

    @Test func modifiedEnterIsANewlineNotASubmit() {
        #expect(route(.enter, .shift, empty: true) == .composer)
        #expect(route(.enter, .option, empty: true) == .composer)
    }
}

@Suite struct PasteEncoderTests {
    let start: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
    let end: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]

    @Test func wrapsTextInBracketedPaste() {
        #expect(PasteEncoder.paste("hi") == start + Array("hi".utf8) + end)
    }

    @Test func normalizesLineEndingsAndTrimsTrailingNewlines() {
        #expect(PasteEncoder.paste("a\r\nb\n\n") == start + Array("a\nb".utf8) + end)
    }

    @Test func stripsEmbeddedPasteMarkers() {
        let hostile = "x\u{1B}[201~rm -rf ~\u{1B}[200~y"
        #expect(PasteEncoder.paste(hostile) == start + Array("xrm -rf ~y".utf8) + end)
    }

    @Test func keepsUnicodeIntact() {
        #expect(PasteEncoder.paste("中文 ✓") == start + Array("中文 ✓".utf8) + end)
    }
}
