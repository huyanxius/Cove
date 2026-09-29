import Foundation
import SQLite3

/// codex 的会话列表：读 codex 自己维护的线程索引 `~/.codex/state_N.sqlite`，也就是
/// `codex resume` 选择器背后那张表。别去扫 `sessions/**/rollout-*.jsonl`：一千多个文件，
/// 每个第一行都带着几十 KB 的系统提示。
///
/// 只要用户自己开的线程（`thread_source = 'user'`）：子代理、guardian 审查、agent 派生的
/// 线程也在这张表里，但用户没法、也不想在侧栏里点开它们。已归档的、一句话都没说过的也不要。
public enum CodexSessions {
    public static var defaultDatabase: URL? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        // 文件名里的数字是 schema 版本（state_5），升级后会变，取最大的那个。
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        let latest = names.filter { $0.hasPrefix("state_") && $0.hasSuffix(".sqlite") }
            .max { version($0) < version($1) }
        return latest.map { home.appendingPathComponent($0) }
    }

    static func version(_ name: String) -> Int {
        Int(name.dropFirst("state_".count).dropLast(".sqlite".count)) ?? -1
    }

    public static func scan(database: URL?) -> [SessionSummary] {
        guard let database else { return [] }
        let sql = """
            SELECT id, cwd, title, first_user_message, updated_at, updated_at_ms, git_branch
            FROM threads
            WHERE archived = 0 AND has_user_event = 1 AND thread_source = 'user'
            ORDER BY updated_at DESC
            """
        return SQLiteRows.query(database, sql) { row in
            guard let id = row.text(0) else { return nil }
            let title = [row.text(2), row.text(3)].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            let updated = row.double(5).map { $0 / 1000 } ?? row.double(4) ?? 0
            return SessionSummary(id: id, fileURL: database, title: SessionSummarizer.flatten(title),
                                  cwd: row.text(1).flatMap { $0.isEmpty ? nil : $0 }, gitBranch: row.text(6),
                                  lastActivity: Date(timeIntervalSince1970: updated), promptCount: 0, cli: .codex)
        }
    }
}

/// agy（Antigravity CLI）的会话列表：`~/.gemini/antigravity-cli/conversation_summaries.db`。
///
/// 工作目录存成 `file://` URI 的 JSON 数组（空格编码成 %20），取第一个；没开工作区的会话
/// 这一列为空串，cwd 记 nil。`nesting_depth > 0` 是子对话，不列。
public enum AgySessions {
    public static var defaultDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/conversation_summaries.db")
    }

    public static func scan(database: URL) -> [SessionSummary] {
        let sql = """
            SELECT conversation_id, title, preview, workspace_uris, last_modified_time
            FROM conversation_summaries
            WHERE nesting_depth = 0
            ORDER BY last_modified_time DESC
            """
        return SQLiteRows.query(database, sql) { row in
            guard let id = row.text(0) else { return nil }
            let title = [row.text(1), row.text(2)].compactMap { $0 }.first { !$0.isEmpty } ?? "Antigravity"
            return SessionSummary(id: id, fileURL: database, title: SessionSummarizer.flatten(title),
                                  cwd: workspace(row.text(3)), gitBranch: nil,
                                  lastActivity: timestamp(row.text(4)) ?? .distantPast, promptCount: 0, cli: .agy)
        }
    }

    static func workspace(_ json: String?) -> String? {
        guard let data = json?.data(using: .utf8),
              let uris = try? JSONSerialization.jsonObject(with: data) as? [String],
              let first = uris.first, let url = URL(string: first), url.isFileURL else { return nil }
        return url.path
    }

    /// `2026-09-28 12:01:48.48352+00:00`：Go 的时间格式，小数位数不固定。
    static func timestamp(_ text: String?) -> Date? {
        guard let text else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let normalized = text.replacingOccurrences(of: " ", with: "T")
        if let date = iso.date(from: normalized) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: normalized)
    }
}

/// 只读查询一个别的程序正在写的 SQLite 库。
///
/// 先按普通只读打开：codex 的库是 WAL 模式，这样能读到还没合并进主文件的新线程。
/// 打不开（WAL 库旁边没有可用的 -shm，比如 agy 的库）再退到 `immutable=1`，代价是可能
/// 读到稍旧的数据——4 秒后下一轮刷新会补上。任何失败都返回空数组：侧栏少一类会话，不该崩。
enum SQLiteRows {
    struct Row {
        let statement: OpaquePointer

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func double(_ column: Int32) -> Double? {
            sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
        }
    }

    static func query<T>(_ database: URL, _ sql: String, _ transform: (Row) -> T?) -> [T] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        for suffix in ["?mode=ro", "?immutable=1"] {
            var db: OpaquePointer?
            defer { sqlite3_close(db) }
            guard sqlite3_open_v2("file:" + database.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + suffix,
                                  &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { continue }
            sqlite3_busy_timeout(db, 200)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { continue }
            defer { sqlite3_finalize(statement) }
            var result: [T] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                if let value = transform(Row(statement: statement)) { result.append(value) }
                status = sqlite3_step(statement)
            }
            if status == SQLITE_DONE { return result }
        }
        return []
    }
}
