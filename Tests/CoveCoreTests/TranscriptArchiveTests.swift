import Foundation
import Testing
@testable import CoveCore

@Suite struct TranscriptArchiveTests {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("cove-archive-\(UUID().uuidString)")
    var source: URL { base.appendingPathComponent("projects") }
    var archive: TranscriptArchive { TranscriptArchive(source: source, destination: base.appendingPathComponent("backup")) }

    func write(_ text: String, project: String, id: String) throws -> URL {
        let url = source.appendingPathComponent(project).appendingPathComponent("\(id).jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func copiesOnlyNewOrChangedFiles() throws {
        let line = #"{"type":"user","message":{"role":"user","content":"hi"},"cwd":"/p"}"#
        let file = try write(line + "\n", project: "-p", id: "a")
        #expect(archive.sync() == 1)
        #expect(archive.sync() == 0)
        try (line + "\n" + line + "\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(archive.sync() == 1)
    }

    @Test func keepsDeletedSessionsAndRestoresThem() throws {
        let line = #"{"type":"user","message":{"role":"user","content":"旧会话"},"cwd":"/p"}"#
        let file = try write(line + "\n", project: "-p", id: "old")
        archive.sync()
        try FileManager.default.removeItem(at: file)

        let orphans = archive.orphans()
        #expect(orphans.map(\.lastPathComponent) == ["old.jsonl"])
        let indexer = SessionIndexer(root: source, archive: archive)
        let listed = indexer.scan()
        #expect(listed.map(\.id) == ["old"])
        #expect(listed.first?.isArchivedOnly == true)

        let restored = try archive.restore(orphans[0])
        #expect(restored == file)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(indexer.scan().first?.isArchivedOnly == false)
    }
}
