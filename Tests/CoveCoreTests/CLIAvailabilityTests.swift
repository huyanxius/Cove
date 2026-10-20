import Foundation
import Testing
@testable import CoveCore

@Suite struct CLIAvailabilityTests {
    @Test func ignoresShellBannersAndUnrecognizedTools() {
        let output = "Welcome!\nclaude\nCOVE_CLI_FOUND:codex\nCOVE_CLI_FOUND:unknown\nCOVE_CLI_FOUND:agy\n"
        #expect(CLIAvailability.installed(in: output) == [.codex, .agy])
    }

    @Test func excludesCommandsWithABrokenInterpreter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = root.appendingPathComponent("claude")
        try "#!/missing/interpreter\n".write(to: broken, atomically: true, encoding: .utf8)
        let working = root.appendingPathComponent("codex")
        try "#!/bin/sh\necho codex-test\n".write(to: working, atomically: true, encoding: .utf8)
        for url in [broken, working] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", CLIAvailability.detectionScript]
        process.environment = ["PATH": root.path]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(CLIAvailability.installed(in: String(decoding: data, as: UTF8.self)) == [.codex])
    }

    @Test func preservesAnInstalledPreference() {
        #expect(CLIAvailability.preferred(.codex, installed: [.claude, .codex]) == .codex)
    }

    @Test func selectsAnInstalledAlternative() {
        #expect(CLIAvailability.preferred(.claude, installed: [.codex]) == .codex)
        #expect(CLIAvailability.preferred(.agy, installed: [.claude, .codex]) == .claude)
    }

    @Test func leavesTheChoiceWhenNoToolIsFound() {
        #expect(CLIAvailability.preferred(.codex, installed: []) == .codex)
    }
}
