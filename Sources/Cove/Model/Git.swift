import CoveCore
import Foundation

/// 检查器里点开一个文件时，去 git 里取它的实际差异。
enum Git {
    enum DiffResult: Equatable {
        case diff([DiffLine])
        case unchanged
        case notRepository
        case failed(String)
    }

    /// 以文件所在目录为工作目录，文件可以不在会话 cwd 之下（Agent 常改 ~/.claude 之类的地方）。
    static func diff(path: String) async -> DiffResult {
        await Task.detached(priority: .userInitiated) {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
            guard FileManager.default.fileExists(atPath: directory) else { return .failed("Folder no longer exists.") }
            guard run(["rev-parse", "--is-inside-work-tree"], in: directory).status == 0 else { return .notRepository }

            // 对比 HEAD 以便把已暂存的改动也算进来；还没有任何提交的仓库没有 HEAD，退回工作区对比。
            var tracked = run(["diff", "--no-color", "HEAD", "--", path], in: directory)
            if tracked.status != 0 { tracked = run(["diff", "--no-color", "--", path], in: directory) }
            if tracked.status == 0, !tracked.output.isEmpty { return .diff(UnifiedDiff.parse(tracked.output)) }

            // 未被跟踪的新文件：git diff 对它沉默，改用与 /dev/null 比较，整份显示为新增。
            if run(["ls-files", "--error-unmatch", "--", path], in: directory).status != 0,
               FileManager.default.fileExists(atPath: path) {
                let untracked = run(["diff", "--no-color", "--no-index", "--", "/dev/null", path], in: directory)
                if !untracked.output.isEmpty { return .diff(UnifiedDiff.parse(untracked.output)) }
            }
            if tracked.status != 0 { return .failed(tracked.error.isEmpty ? "git diff failed." : tracked.error) }
            return .unchanged
        }.value
    }

    private static func run(_ arguments: [String], in directory: String) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return (-1, "", error.localizedDescription) }
        // 先读完再等退出：大 diff 会写满管道缓冲区，反过来会互相等死。
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let error = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self), String(decoding: error, as: UTF8.self))
    }
}
