import XCTest
@testable import MacDroidCore

final class ImportTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDuplicateFilenamesPreserveBothOriginals() throws {
        let folder = try temporaryFolder()
        try Data("old".utf8).write(to: folder.appendingPathComponent("photo.jpg"))
        let committer = try FileCommitter(destination: folder)
        defer { committer.cleanup() }
        let staged = committer.stagingDirectory.appendingPathComponent("download")
        try Data("new!".utf8).write(to: staged)
        let result = try committer.commit(staged, named: "photo.jpg", expectedBytes: 4, date: nil)
        XCTAssertEqual(result.lastPathComponent, "photo (2).jpg")
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("photo.jpg")), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: result), Data("new!".utf8))
    }

    func testPartialDownloadNeverBecomesVisible() throws {
        let folder = try temporaryFolder()
        let committer = try FileCommitter(destination: folder)
        let staged = committer.stagingDirectory.appendingPathComponent("partial")
        try Data("partial".utf8).write(to: staged)
        XCTAssertThrowsError(try committer.commit(staged, named: "photo.jpg", expectedBytes: 900, date: nil))
        committer.cleanup()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testEmptyDocumentsAreValidButMissingBytesAreNot() throws {
        let folder = try temporaryFolder()
        let committer = try FileCommitter(destination: folder)
        defer { committer.cleanup() }
        let staged = committer.stagingDirectory.appendingPathComponent("empty")
        try Data().write(to: staged)
        let result = try committer.commit(staged, named: "notes.txt", expectedBytes: 0, date: nil)
        XCTAssertEqual(try Data(contentsOf: result).count, 0)
        try Data().write(to: staged)
        XCTAssertThrowsError(try committer.commit(staged, named: "photo.jpg", expectedBytes: 200, date: nil))
    }

    func testUnsafePathsAndSymlinksCannotEscapeDestination() throws {
        XCTAssertEqual(FileCommitter.safeFilename("../../private/photo.jpg"), "_._.._private_photo.jpg")
        XCTAssertEqual(FileCommitter.safeFilename(".."), "Untitled")
        let folder = try temporaryFolder()
        let committer = try FileCommitter(destination: folder)
        defer { committer.cleanup() }
        let external = folder.appendingPathComponent("original")
        try Data("keep".utf8).write(to: external)
        XCTAssertThrowsError(try committer.commit(external, named: "stolen", expectedBytes: 4, date: nil))
        let link = committer.stagingDirectory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertThrowsError(try committer.commit(link, named: "stolen", expectedBytes: 4, date: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    @MainActor
    func testStopFinishesCurrentFileAndCleansStaging() async throws {
        let folder = try temporaryFolder()
        let engine = ImportEngine()
        let items = (0..<3).map { MediaItem(id: "\($0)", name: "\($0).jpg", album: "Camera", byteCount: 4, date: nil, kind: .photo) }
        let result = try await engine.run(items: items, destination: folder, deviceName: "Test",
            download: { item, stage in
                engine.stopAfterCurrentFile()
                let file = stage.appendingPathComponent(item.name)
                try Data("test".utf8).write(to: file)
                return file
            }, onProgress: { _, _ in }, onCommit: { _, _ in })
        XCTAssertEqual(result.files.count, 1)
        XCTAssertTrue(result.stopped)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["0.jpg"])
    }

    @MainActor
    func testDisconnectKeepsCompletedFilesAndStopsQueue() async throws {
        let folder = try temporaryFolder()
        let engine = ImportEngine()
        let items = (0..<3).map { MediaItem(id: "\($0)", name: "\($0).jpg", album: "Camera", byteCount: 4, date: nil, kind: .photo) }
        let result = try await engine.run(items: items, destination: folder, deviceName: "Test",
            download: { item, stage in
                if item.id == "1" { throw ImportError.disconnected }
                let file = stage.appendingPathComponent(item.name)
                try Data("test".utf8).write(to: file)
                return file
            }, onProgress: { _, _ in }, onCommit: { _, _ in })
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.stopped)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["0.jpg"])
    }
}
