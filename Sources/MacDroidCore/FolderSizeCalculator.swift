import Foundation

public struct SizeEntry: Sendable {
    public let id: String
    public let bytes: UInt64
    public let isFolder: Bool
    public init(id: String, bytes: UInt64 = 0, isFolder: Bool = false) {
        self.id = id; self.bytes = bytes; self.isFolder = isFolder
    }
}

public struct FolderSize: Sendable, Equatable {
    public var bytes: UInt64 = 0
    public var files: Int = 0
    public init(bytes: UInt64 = 0, files: Int = 0) { self.bytes = bytes; self.files = files }
}

public enum FolderSizeError: Error { case repeatedFolder, overflow }

/// Reads metadata only. Incomplete scans throw rather than presenting a partial total.
public enum FolderSizeCalculator {
    public static func calculate(root: String, list: (String) async throws -> [SizeEntry]) async throws -> [String: FolderSize] {
        var order = [root]
        var seen: Set<String> = [root]
        var parents: [String: String] = [:]
        var totals: [String: FolderSize] = [:]
        var index = 0
        while index < order.count {
            try Task.checkCancellation()
            let folder = order[index]; index += 1
            let entries = try await list(folder)
            try Task.checkCancellation()
            var total = FolderSize()
            for entry in entries {
                if entry.isFolder {
                    guard seen.insert(entry.id).inserted else { throw FolderSizeError.repeatedFolder }
                    parents[entry.id] = folder; order.append(entry.id)
                } else {
                    let sum = total.bytes.addingReportingOverflow(entry.bytes)
                    guard !sum.overflow else { throw FolderSizeError.overflow }
                    total.bytes = sum.partialValue; total.files += 1
                }
            }
            totals[folder] = total
        }
        for folder in order.reversed() {
            try Task.checkCancellation()
            if let parent = parents[folder], let child = totals[folder] {
                var total = totals[parent] ?? FolderSize()
                let sum = total.bytes.addingReportingOverflow(child.bytes)
                guard !sum.overflow else { throw FolderSizeError.overflow }
                total.bytes = sum.partialValue; total.files += child.files
                totals[parent] = total
            }
        }
        return totals
    }
}
