import Foundation

@MainActor
public final class ImportEngine {
    public typealias Download = (MediaItem, URL) async throws -> URL
    public private(set) var isRunning = false
    public private(set) var stopRequested = false

    public init() {}
    /// Finishes the in-flight file before stopping, so a cancelled import never
    /// races the camera service while cleaning up its temporary download.
    public func stopAfterCurrentFile() { stopRequested = true }

    public func run(items: [MediaItem], destination: URL, deviceName: String,
                    download: Download,
                    onProgress: (Int, MediaItem) -> Void,
                    onCommit: (MediaItem, URL) -> Void) async throws -> ImportRecord {
        guard !isRunning else { throw CocoaError(.fileLocking) }
        isRunning = true; stopRequested = false
        defer { isRunning = false }
        let committer = try FileCommitter(destination: destination)
        defer { committer.cleanup() }
        var saved: [String] = []
        var failures: [String] = []
        for (index, item) in items.enumerated() {
            if stopRequested || Task.isCancelled { break }
            onProgress(index, item)
            do {
                let downloaded = try await download(item, committer.stagingDirectory)
                let result = try committer.commit(downloaded, named: item.name, expectedBytes: item.byteCount, date: item.date)
                saved.append(result.path)
                onCommit(item, result)
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
                if let issue = error as? ImportError {
                    switch issue {
                    case .disconnected, .stalled: stopRequested = true
                    default: break
                    }
                }
            }
        }
        return ImportRecord(deviceName: deviceName, files: saved, failures: failures,
                            destination: destination.path, stopped: stopRequested || Task.isCancelled)
    }
}
