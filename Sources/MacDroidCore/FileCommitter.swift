import Foundation

/// All imports land in an isolated directory on the destination volume. Only a
/// complete, size-checked regular file is moved into the user's visible folder.
public struct FileCommitter {
    public let destination: URL
    public let stagingDirectory: URL
    private let manager = FileManager.default

    public init(destination: URL) throws {
        self.destination = destination
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        stagingDirectory = destination.appendingPathComponent(".macdroid-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
    }

    public static func safeFilename(_ name: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        var result = name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Leave room for a collision suffix within typical filesystem name limits.
        while result.utf8.count > 220 { result.removeLast() }
        if result.isEmpty || result == "." || result == ".." { return "Untitled" }
        if result.hasPrefix(".") { result = "_" + result.dropFirst() }
        return result
    }

    public func commit(_ downloaded: URL, named name: String, expectedBytes: Int64, date: Date?) throws -> URL {
        let root = stagingDirectory.standardizedFileURL.path + "/"
        guard downloaded.standardizedFileURL.path.hasPrefix(root) else { throw ImportError.invalidDownload }
        let values = try downloaded.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ImportError.invalidDownload }
        let actual = Int64(values.fileSize ?? 0)
        guard expectedBytes < 0 || actual == expectedBytes else {
            throw ImportError.incompleteFile(expected: expectedBytes, actual: actual)
        }
        let safe = Self.safeFilename(name)
        let ext = (safe as NSString).pathExtension
        let stem = (safe as NSString).deletingPathExtension
        for index in 1...100_000 {
            let candidate = index == 1 ? safe : "\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)")
            let target = destination.appendingPathComponent(candidate)
            if manager.fileExists(atPath: target.path) { continue }
            do {
                // moveItem fails if a competing importer created the target.
                try manager.moveItem(at: downloaded, to: target)
                if let date { try? manager.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: target.path) }
                return target
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            }
        }
        throw ImportError.tooManyDuplicates
    }

    public func cleanup() { try? manager.removeItem(at: stagingDirectory) }
}

public enum ImportError: LocalizedError {
    case invalidDownload
    case incompleteFile(expected: Int64, actual: Int64)
    case tooManyDuplicates
    case disconnected
    case stalled

    public var errorDescription: String? {
        switch self {
        case .invalidDownload: return "The phone did not return a valid file. Reconnect it and try again."
        case let .incompleteFile(expected, actual): return "Incomplete copy (\(actual) of \(expected) bytes). The partial file was not kept."
        case .tooManyDuplicates: return "Too many files share this name. Choose another destination."
        case .disconnected: return "The phone disconnected. Completed copies are safe; reconnect to copy the remaining files."
        case .stalled: return "The phone stopped responding. Unlock it, reconnect the cable, and try again."
        }
    }
}
