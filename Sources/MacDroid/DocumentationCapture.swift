import SwiftUI
import AppKit
import MacDroidCore

/// Reproducible images of the real SwiftUI view with explicitly labelled sample
/// data. This path never starts USB discovery or reads the user's phone.
@MainActor
enum DocumentationCapture {
    static func run(model: AppModel) async {
        guard let flag = CommandLine.arguments.firstIndex(of: "--screenshots"),
              CommandLine.arguments.indices.contains(flag + 1) else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            model.destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/DroidDock")
            model.history = []; model.camera.start()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) else { throw CaptureError.windowMissing }
            window.setContentSize(NSSize(width: 1180, height: 790))
            window.appearance = NSAppearance(named: .darkAqua)
            try await save(window, to: directory.appendingPathComponent("macos-photos.png"))

            model.filter = .files
            let date = Date(timeIntervalSince1970: 1_794_268_800)
            let storage = RemoteFile(id: 1, storage: 1, name: "Internal storage", size: 0, date: date, isFolder: true)
            model.mtp.deviceName = "Sample Android phone"
            model.mtp.connected = true
            model.mtp.storages = [RemoteStorage(id: 1, name: "Internal storage", freeBytes: 64_000_000_000)]
            model.mtp.storageID = 1; model.mtp.path = [storage]
            model.mtp.entries = ["DCIM", "Documents", "Download", "Music", "Pictures"].enumerated().map {
                RemoteFile(id: UInt32($0.offset + 2), storage: 1, name: $0.element, size: 0, date: date, isFolder: true)
            } + [RemoteFile(id: 7, storage: 1, name: "notes.txt", size: 2400, date: date, isFolder: false)]
            let sizes: [UInt64] = [329_200_000, 840_000, 12_500_000, 24_600_000, 3_250_000]
            for (i, bytes) in sizes.enumerated() { model.mtp.folderSizes[String(i + 2)] = FolderSize(bytes: bytes, files: i == 0 ? 2 : 1) }
            model.mtp.folderSizes["1"] = FolderSize(bytes: sizes.reduce(2400, +), files: 7)
            try await save(window, to: directory.appendingPathComponent("macos-files.png"))
            NSApp.terminate(nil)
        } catch {
            fputs("Screenshot export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func save(_ window: NSWindow, to url: URL) async throws {
        try await Task.sleep(nanoseconds: 700_000_000)
        guard let view = window.contentView else { throw CaptureError.windowMissing }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CaptureError.renderFailed }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.renderFailed }
        try data.write(to: url)
    }
    private enum CaptureError: Error { case windowMissing, renderFailed }
}
