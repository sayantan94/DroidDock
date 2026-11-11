import XCTest
@testable import MacDroidCore

final class DeletionAndMonthTests: XCTestCase {
    private func target(_ id: String, folder: Bool = false, bytes: UInt64 = 4) -> DeletionTarget {
        DeletionTarget(id: id, location: "storage/folder", name: "\(id).jpg", bytes: bytes, isFolder: folder)
    }

    @MainActor func testCancelledConfirmationNeverTouchesPhone() async {
        var calls = 0
        let result = await FileDeletion.run(targets: [target("a")], confirmed: false, deleteVerified: { _ in calls += 1 })
        XCTAssertEqual(calls, 0); XCTAssertTrue(result.deleted.isEmpty)
    }

    @MainActor func testInvalidBatchIsRejectedBeforeAnyDeletion() async {
        for files in [[target("a"), target("folder", folder: true)], [target("a"), target("a")]] {
            var calls = 0
            let result = await FileDeletion.run(targets: files, confirmed: true, deleteVerified: { _ in calls += 1 })
            XCTAssertEqual(calls, 0); XCTAssertNotNil(result.failure)
        }
    }

    @MainActor func testFailurePreservesCompletedResultsAndStopsRemainingFiles() async {
        var calls: [String] = []
        let result = await FileDeletion.run(targets: [target("a"), target("b"), target("c")], confirmed: true,
            deleteVerified: { file in
                calls.append(file.id)
                if file.id == "b" { throw ImportError.disconnected }
            })
        XCTAssertEqual(calls, ["a", "b"])
        XCTAssertEqual(result.deleted.map(\.id), ["a"])
        XCTAssertNotNil(result.failure)
    }

    @MainActor func testStopFinishesCurrentDeletionOnly() async {
        var stop = false
        let result = await FileDeletion.run(targets: [target("a"), target("b")], confirmed: true,
            shouldStop: { stop }, deleteVerified: { _ in stop = true })
        XCTAssertEqual(result.deleted.map(\.id), ["a"]); XCTAssertTrue(result.stopped)
    }

    func testChangedIdentityOrMetadataCannotBeDeleted() throws {
        let expected = target("a")
        XCTAssertNoThrow(try expected.requireMatch(expected))
        XCTAssertThrowsError(try expected.requireMatch(target("b")))
        XCTAssertThrowsError(try expected.requireMatch(target("a", bytes: 900)))
        XCTAssertThrowsError(try expected.requireMatch(target("a", folder: true)))
        XCTAssertThrowsError(try expected.requireMatch(DeletionTarget(id: "a", location: "other/folder", name: "a.jpg", bytes: 4)))
    }

    func testMonthGroupsKeepYearsDistinctAndUnknownDatesLast() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func month(_ year: Int, _ month: Int, _ day: Int) -> FileMonth {
            FileMonth(date: calendar.date(from: DateComponents(year: year, month: month, day: day)), calendar: calendar)
        }
        let november = month(2026, 11, 1)
        XCTAssertEqual(november, month(2026, 11, 30))
        XCTAssertNotEqual(november, month(2025, 11, 1))
        let unknown = FileMonth(date: nil, calendar: calendar)
        XCTAssertEqual([unknown, month(2025, 11, 1), november, month(2026, 10, 31)].sorted(by: >),
                       [november, month(2026, 10, 31), month(2025, 11, 1), unknown])
    }
}
