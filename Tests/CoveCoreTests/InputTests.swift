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
        #expect(route(.character("/"), empty: false) == .composer)
    }

    @Test func slashOnEmptyComposerHandsOverToTheCLIInput() {
        #expect(route(.character("/"), empty: true) == .handoff([0x2F]))
        #expect(route(.character("!"), .shift, empty: true) == .handoff([0x21]))
        #expect(route(.character("/"), .command, empty: true) == .composer)
    }

    @Test func backspaceOnEmptyComposerStaysPut() {
        #expect(route(.backspace, empty: true) == .composer)
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

    @Test func arrowsUseSS3InApplicationCursorMode() {
        let up = KeyRouter.route(KeyStroke(key: .up), composerIsEmpty: true, applicationCursor: true)
        #expect(up == .terminal([0x1B, 0x4F, 0x41]))
        let left = KeyRouter.route(KeyStroke(key: .left), composerIsEmpty: true, applicationCursor: true)
        #expect(left == .terminal([0x1B, 0x4F, 0x44]))
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

    @Test func fallsBackToRawTextWhenTheAppDidNotEnableBracketedPaste() {
        #expect(PasteEncoder.paste("a\nb", bracketed: false) == Array("a\nb".utf8))
    }

    @Test func keepsUnicodeIntact() {
        #expect(PasteEncoder.paste("中文 ✓") == start + Array("中文 ✓".utf8) + end)
    }
}

@Suite struct DirectInputTests {
    /// 依次喂按键，返回每一步是否交还键盘。
    func run(_ strokes: [KeyStroke]) -> [Bool] {
        var input = DirectInput()
        return strokes.map { input.record($0) }
    }

    @Test func enterGivesTheKeyboardBack() {
        #expect(run([KeyStroke(key: .character("c")), KeyStroke(key: .enter)]) == [false, true])
    }

    @Test func deletingTheSlashGivesTheKeyboardBack() {
        #expect(run([KeyStroke(key: .character("m")), KeyStroke(key: .backspace), KeyStroke(key: .backspace)])
            == [false, false, true])
    }

    @Test func menuNavigationKeepsTheKeyboard() {
        #expect(run([KeyStroke(key: .down), KeyStroke(key: .escape), KeyStroke(key: .enter, modifiers: .shift)])
            == [false, false, false])
    }

    @Test func stickyModeNeverEndsByItself() {
        var input = DirectInput(sticky: true)
        let results = [KeyStroke(key: .enter), KeyStroke(key: .character("c"), modifiers: .control),
                       KeyStroke(key: .backspace)].map { input.record($0) }
        #expect(results == [false, false, false])
    }

    @Test func afterTabCompletionOnlyEnterOrInterruptEnds() {
        #expect(run([KeyStroke(key: .tab), KeyStroke(key: .backspace), KeyStroke(key: .backspace),
                     KeyStroke(key: .character("c"), modifiers: .control)]) == [false, false, false, true])
    }
}

@Suite struct AttachmentReferenceTests {
    @Test func quotesPathsWithSpaces() {
        #expect(AttachmentReference.text(for: ["/a/b.png", "/Users/me/My Docs/x.md"]) == #" /a/b.png "/Users/me/My Docs/x.md" "#)
        #expect(AttachmentReference.text(for: []) == "")
    }
}
