import XCTest
@testable import MacDroidCore

final class FolderSizeTests: XCTestCase {
    func testNestedFoldersIncludeAllFilesAndEmptyFolders() async throws {
        let tree: [String: [SizeEntry]] = [
            "root": [.init(id: "photo", bytes: 10), .init(id: "DCIM", isFolder: true), .init(id: "empty", isFolder: true)],
            "DCIM": [.init(id: "video", bytes: 8_000_000_000), .init(id: "nested", isFolder: true)],
            "nested": [.init(id: "zero", bytes: 0)], "empty": []]
        let result = try await FolderSizeCalculator.calculate(root: "root") { tree[$0]! }
        XCTAssertEqual(result["root"], FolderSize(bytes: 8_000_000_010, files: 3))
        XCTAssertEqual(result["DCIM"], FolderSize(bytes: 8_000_000_000, files: 2))
        XCTAssertEqual(result["empty"], FolderSize())
    }

    func testUnreadableFolderDoesNotProduceMisleadingTotal() async {
        do {
            _ = try await FolderSizeCalculator.calculate(root: "root") { id in
                if id == "root" { return [.init(id: "private", isFolder: true)] }
                throw ImportError.disconnected
            }
            XCTFail("Expected failed scan")
        } catch { XCTAssertTrue(error is ImportError) }
    }

    func testCyclesFailInsteadOfScanningForever() async {
        do {
            _ = try await FolderSizeCalculator.calculate(root: "root") { _ in [.init(id: "root", isFolder: true)] }
            XCTFail("Expected cycle rejection")
        } catch { XCTAssertTrue(error is FolderSizeError) }
    }

    func testCancellationStopsBeforeNextFolder() async {
        let task = Task {
            try await FolderSizeCalculator.calculate(root: "root") { _ in
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return []
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
