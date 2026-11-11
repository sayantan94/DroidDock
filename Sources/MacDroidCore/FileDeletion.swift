import Foundation

public struct DeletionTarget: Equatable, Sendable {
    public let id: String
    public let location: String
    public let name: String
    public let bytes: UInt64
    public let isFolder: Bool
    public init(id: String, location: String, name: String, bytes: UInt64, isFolder: Bool = false) {
        self.id = id; self.location = location; self.name = name; self.bytes = bytes; self.isFolder = isFolder
    }
    public func requireMatch(_ current: DeletionTarget) throws {
        guard !isFolder, !current.isFolder, !id.isEmpty, self == current else {
            throw DeletionError(message: "This file changed since it was selected. Refresh the folder and select it again.")
        }
    }
}

public struct DeletionError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(message: String) { self.message = message }
}

public struct DeletionResult {
    public let deleted: [DeletionTarget]
    public let failure: String?
    public let stopped: Bool
}

public enum FileDeletion {
    /// A rejected confirmation never calls the backend. Validate the entire
    /// frozen selection before deleting anything, then stop on the first error.
    @MainActor
    public static func run(targets: [DeletionTarget], confirmed: Bool,
                           shouldStop: () -> Bool = { false },
                           beforeDelete: (Int, DeletionTarget) -> Void = { _, _ in },
                           deleteVerified: (DeletionTarget) async throws -> Void,
                           didDelete: (DeletionTarget) -> Void = { _ in }) async -> DeletionResult {
        guard confirmed else { return DeletionResult(deleted: [], failure: nil, stopped: false) }
        guard targets.allSatisfy({ !$0.isFolder && !$0.id.isEmpty && !$0.location.isEmpty }),
              Set(targets.map(\.id)).count == targets.count else {
            return DeletionResult(deleted: [], failure: "Select individual files once each. Folders cannot be deleted.", stopped: false)
        }
        var deleted: [DeletionTarget] = []
        for (index, target) in targets.enumerated() {
            if shouldStop() || Task.isCancelled { return DeletionResult(deleted: deleted, failure: nil, stopped: true) }
            beforeDelete(index, target)
            do { try await deleteVerified(target); deleted.append(target); didDelete(target) }
            catch { return DeletionResult(deleted: deleted, failure: "\(target.name): \(error.localizedDescription)", stopped: false) }
        }
        return DeletionResult(deleted: deleted, failure: nil, stopped: false)
    }
}
