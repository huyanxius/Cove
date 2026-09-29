import Foundation
import SQLite3
import Testing
@testable import CoveCore

/// 用真的 SQLite 文件喂给索引器：表结构只建它读到的那几列，和 codex / agy 的库同名同型。
@Suite struct ExternalSessionsTests {
    func database(_ statements: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cove-\(UUID().uuidString).db")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in statements { #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK) }
        return url
    }

    @Test func codexKeepsOnlyUserThreads() throws {
        let url = try database([
            """
            CREATE TABLE threads (id TEXT, cwd TEXT, title TEXT, first_user_message TEXT, updated_at INTEGER,
              updated_at_ms INTEGER, archived INTEGER, has_user_event INTEGER, thread_source TEXT, git_branch TEXT)
            """,
            "INSERT INTO threads VALUES ('a', '/p', '修登录', '修登录\n详细说明', 1790000000, 1790000000500, 0, 1, 'user', 'main')",
            "INSERT INTO threads VALUES ('b', '/p', '', '只有首条消息', 1790000100, NULL, 0, 1, 'user', NULL)",
            "INSERT INTO threads VALUES ('sub', '/p', 'x', 'x', 1790000200, NULL, 0, 1, 'subagent', NULL)",
            "INSERT INTO threads VALUES ('old', '/p', 'x', 'x', 1790000300, NULL, 1, 1, 'user', NULL)",
            "INSERT INTO threads VALUES ('empty', '/p', '', '', 1790000400, NULL, 0, 0, 'user', NULL)",
        ])
        let sessions = CodexSessions.scan(database: url)
        #expect(sessions.map(\.id) == ["b", "a"])
        #expect(sessions.allSatisfy { $0.cli == .codex })
        #expect(sessions[0].title == "只有首条消息")
        #expect(sessions[1].title == "修登录")
        #expect(sessions[1].gitBranch == "main")
        #expect(sessions[1].lastActivity == Date(timeIntervalSince1970: 1_790_000_000.5))
    }

    @Test func agyReadsWorkspaceFromFileURI() throws {
        let url = try database([
            """
            CREATE TABLE conversation_summaries (conversation_id TEXT, title TEXT, preview TEXT,
              workspace_uris TEXT, last_modified_time DATETIME, nesting_depth INTEGER)
            """,
            #"INSERT INTO conversation_summaries VALUES ('c1', '', '你好', '["file:///Users/me/Application%20Support/x"]', '2026-09-28 12:01:48.48352+00:00', 0)"#,
            #"INSERT INTO conversation_summaries VALUES ('c2', 'Token Quota', 'p', '', '2026-09-16 18:51:18+00:00', 0)"#,
            #"INSERT INTO conversation_summaries VALUES ('child', 't', 'p', '', '2026-09-29 00:00:00+00:00', 1)"#,
        ])
        let sessions = AgySessions.scan(database: url)
        #expect(sessions.map(\.id) == ["c1", "c2"])
        #expect(sessions[0].cwd == "/Users/me/Application Support/x")
        #expect(sessions[0].title == "你好")
        #expect(sessions[0].cli == .agy)
        #expect(sessions[1].cwd == nil)
        #expect(sessions[1].title == "Token Quota")
        #expect(abs(sessions[0].lastActivity.timeIntervalSince1970 - 1_790_596_908.48352) < 0.01)
    }

    @Test func missingDatabaseYieldsNothing() {
        #expect(CodexSessions.scan(database: URL(fileURLWithPath: "/nonexistent/x.sqlite")).isEmpty)
    }

    @Test func resumeArgumentsPerCLI() {
        #expect(CLIKind.claude.arguments(resume: "id") == ["--resume", "id"])
        #expect(CLIKind.codex.arguments(resume: "id") == ["resume", "id"])
        #expect(CLIKind.agy.arguments(resume: "id") == ["--conversation", "id"])
        #expect(CLIKind.codex.arguments(resume: nil) == [])
    }
}
