import Testing
@testable import CoveCore

@Suite struct NumStatTests {
    @Test func parsesGitNumstat() {
        let out = "118\t31\tSources/A.swift\n6\t0\tPackage.swift\n-\t-\tlogo.png\n"
        let stats = NumStat.parse(out)
        #expect(stats["Sources/A.swift"] == LineDelta(added: 118, removed: 31))
        #expect(stats["Package.swift"] == LineDelta(added: 6, removed: 0))
        #expect(stats["logo.png"] == nil)
    }

    @Test func handlesRenamesByTakingTheNewPath() {
        let stats = NumStat.parse("3\t1\tsrc/{old => new}/f.swift\n")
        #expect(stats["src/new/f.swift"] == LineDelta(added: 3, removed: 1))
    }
}
