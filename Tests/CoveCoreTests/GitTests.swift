import Foundation
import Testing
@testable import CoveCore

@Suite struct RepoStatusTests {
    @Test func parsesBranchAndFiles() {
        let output = """
        # branch.oid 305863a
        # branch.head feat/m0-shell
        # branch.upstream origin/feat/m0-shell
        # branch.ab +2 -1
        1 .M N... 100644 100644 100644 abc abc Sources/Cove/Model/App Model.swift
        1 A. N... 000000 100644 100644 000 abc new.swift
        1 D. N... 100644 000000 000000 abc 000 gone.swift
        2 R. N... 100644 100644 100644 abc abc R100 renamed.swift\told.swift
        u UU N... 100644 100644 100644 100644 a b c conflict.swift
        ? notes/todo 1.md
        """
        let status = RepoStatus.parse(output)
        #expect(status.branch == "feat/m0-shell")
        #expect(status.upstream == "origin/feat/m0-shell")
        #expect(status.ahead == 2 && status.behind == 1)
        #expect(status.files.map(\.path) == ["Sources/Cove/Model/App Model.swift", "new.swift", "gone.swift",
                                             "renamed.swift", "conflict.swift", "notes/todo 1.md"])
        #expect(status.files.map(\.badge) == ["M", "A", "D", "R", "!", "U"])
    }

    @Test func detachedHeadAndNoUpstream() {
        let status = RepoStatus.parse("# branch.oid abc\n# branch.head (detached)\n")
        #expect(status.branch == nil && status.upstream == nil && status.ahead == 0)
    }
}

@Suite struct GitHubRemoteTests {
    @Test func convertsCommonRemoteForms() {
        let web = URL(string: "https://github.com/huyanxius/Cove")
        #expect(GitHubRemote.webURL(fromRemote: "git@github.com:huyanxius/Cove.git") == web)
        #expect(GitHubRemote.webURL(fromRemote: "https://github.com/huyanxius/Cove.git\n") == web)
        #expect(GitHubRemote.webURL(fromRemote: "ssh://git@github.com/huyanxius/Cove") == web)
        #expect(GitHubRemote.webURL(fromRemote: "git@gitlab.com:a/b.git") == nil)
    }

    @Test func buildsBranchAndCompareLinks() {
        let repo = URL(string: "https://github.com/a/b")!
        #expect(GitHubRemote.branchURL(repo: repo, branch: "feat/x").absoluteString == "https://github.com/a/b/tree/feat/x")
        #expect(GitHubRemote.compareURL(repo: repo, branch: "feat/x").absoluteString == "https://github.com/a/b/compare/feat/x?expand=1")
    }
}

@Suite struct PullRequestTests {
    @Test func parsesChecksOfBothKinds() throws {
        let json = #"{"number":12,"title":"feat: shell","state":"OPEN","url":"https://github.com/a/b/pull/12","isDraft":false,"statusCheckRollup":[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://x/1"},{"__typename":"CheckRun","name":"lint","status":"IN_PROGRESS","conclusion":""},{"__typename":"StatusContext","context":"ci/legacy","state":"SUCCESS"},{"__typename":"CheckRun","name":"docs","status":"COMPLETED","conclusion":"SKIPPED"}]}"#
        let pr = try #require(PullRequest.parse(json))
        #expect(pr.number == 12)
        #expect(pr.checks.map(\.state) == [.failed, .pending, .passed, .skipped])
        #expect(pr.failing.map(\.name) == ["test"])
        #expect(pr.pending)
        #expect(AgentPrompts.fixChecks(pr).contains("PR #12") && AgentPrompts.fixChecks(pr).contains("test"))
    }

    @Test func noPullRequestYieldsNil() {
        #expect(PullRequest.parse("") == nil)
    }
}

@Suite struct ReviewPromptTests {
    @Test func listsEveryComment() {
        let text = AgentPrompts.review(file: "Sources/A.swift", comments: [
            ReviewComment(line: 12, code: "  let x = 1", note: "改成常量"),
            ReviewComment(line: nil, code: "oldCall()", note: "为什么删了"),
        ])
        #expect(text.contains("`Sources/A.swift`"))
        #expect(text.contains("第 12 行 `let x = 1`：改成常量"))
        #expect(text.contains("（已删除的行） `oldCall()`：为什么删了"))
    }
}
