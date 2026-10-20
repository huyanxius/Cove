import CoveCore
import Foundation
import Observation

/// 首次启动的安装检查，沿用会话实际使用的登录 shell，包含用户的 PATH 和 alias。
@MainActor
@Observable
final class CLISetup {
    private(set) var installed: Set<CLIKind> = []
    private(set) var isChecking = false
    private(set) var didCheck = false

    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        installed = await Task.detached(priority: .userInitiated) { Self.detect() }.value
        didCheck = true
        isChecking = false
    }

    nonisolated private static func detect() -> Set<CLIKind> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-l", "-i", "-c", CLIAvailability.detectionScript]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        // shell 配置可能等待终端输入；检查超时后允许用户重新检测。
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CLIAvailability.installed(in: String(decoding: data, as: UTF8.self))
    }
}
