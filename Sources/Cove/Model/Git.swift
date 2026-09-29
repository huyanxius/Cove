import CoveCore
import Foundation

/// 检查器里点开一个文件时，去 git 里取它的实际差异。
enum Git {
    enum DiffResult: Equatable {
        case diff([DiffLine])
        /// 文件不在 git 仓库里，没有基准可比：把当前全文当作新增展示。
        case outsideRepository([DiffLine])
        case unchanged
        case notRepository
        case failed(String)
    }

    /// 以文件所在目录为工作目录，文件可以不在会话 cwd 之下（Agent 常改 ~/.claude 之类的地方）。
    static func diff(path: String) async -> DiffResult {
        await Task.detached(priority: .userInitiated) {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
            guard FileManager.default.fileExists(atPath: directory) else { return .failed("Folder no longer exists.") }
            let probe = run(["rev-parse", "--is-inside-work-tree"], in: directory)
            if probe.error.contains("not permitted") || probe.error.contains("Unable to read") {
                return .failed("macOS 没有允许 Cove 读取这个文件夹。到 系统设置 → 隐私与安全性 → 完整磁盘取用 里允许 Cove。")
            }
            guard probe.status == 0 else {
                // --no-index 不需要仓库，拿 /dev/null 当基准就能得到「全文新增」的 diff。
                guard FileManager.default.fileExists(atPath: path) else { return .notRepository }
                let whole = run(["diff", "--no-color", "--no-index", "--", "/dev/null", path], in: directory)
                return whole.output.isEmpty ? .notRepository : .outsideRepository(UnifiedDiff.parse(whole.output))
            }

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
            if tracked.error.contains("not permitted") || tracked.error.contains("Unable to read current working directory") {
                return .failed("macOS 没有允许 Cove 读取这个文件夹。到 系统设置 → 隐私与安全性 → 完整磁盘取用 里允许 Cove。")
            }
            if tracked.status != 0 { return .failed(tracked.error.isEmpty ? "git diff failed." : tracked.error) }
            return .unchanged
        }.value
    }

    /// 每个文件相对 HEAD 的增删行数。未被跟踪的新文件按总行数算作新增；取不到的文件不出现在结果里。
    static func numstat(paths: [String]) async -> [String: LineDelta] {
        await Task.detached(priority: .utility) {
            var result: [String: LineDelta] = [:]
            for path in paths {
                let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
                guard FileManager.default.fileExists(atPath: directory) else { continue }
                var output = run(["diff", "--numstat", "HEAD", "--", path], in: directory)
                if output.status != 0 { output = run(["diff", "--numstat", "--", path], in: directory) }
                if let delta = NumStat.parse(output.output).values.first {
                    result[path] = delta
                } else if run(["ls-files", "--error-unmatch", "--", path], in: directory).status != 0,
                          let data = FileManager.default.contents(atPath: path) {
                    let lines = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
                    result[path] = LineDelta(added: max(lines, data.isEmpty ? 0 : 1), removed: 0)
                }
            }
            return result
        }.value
    }

    static func run(_ arguments: [String], in directory: String) -> (status: Int32, output: String, error: String) {
        exec("/usr/bin/git", ["-C", directory] + arguments, in: nil)
    }

    /// 跑一个外部程序，读完 stdout / stderr 再等退出。
    static func exec(_ executable: String, _ arguments: [String], in directory: String?) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
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
