import AppKit
import MacDroidCore

@MainActor
final class MTPStore: ObservableObject {
    let service = MTPService()
    @Published var connected = false
    @Published var busy = false
    @Published var transferring = false
    @Published var deviceName = "Android files"
    @Published var storages: [RemoteStorage] = []
    @Published var storageID: UInt32 = 0
    @Published var path: [RemoteFile] = []
    @Published var entries: [RemoteFile] = []
    @Published var selection: Set<UInt32> = []
    @Published var search = ""
    @Published var error: String?
    @Published var message: String?
    @Published var fraction = 0.0
    @Published var currentFile = ""
    @Published var completed = 0
    @Published var total = 0
    @Published var stopRequested = false
    @Published var folderSizes: [String: FolderSize] = [:]
    @Published var calculatingSize = false
    @Published var sizeError: String?
    private var sizeTask: Task<Void, Never>?
    private var sizeGeneration = UUID()
    var folderSize: FolderSize? { folderSizes[String(parentID)] }
    var parentID: UInt32 { path.last?.id ?? UInt32.max }
    var visible: [RemoteFile] { entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var selectedFiles: [RemoteFile] { entries.filter { !$0.isFolder && selection.contains($0.id) } }

    func connect() async {
        guard !busy else { return }
        cancelSizeScan()
        busy = true; error = nil; entries = []; selection = []
        defer { busy = false }
        do {
            let result = try await service.connect()
            deviceName = result.0; storages = result.1; storageID = result.1[0].id
            connected = true; path = []
            entries = try await service.list(storage: storageID, parent: UInt32.max)
            calculateSizes()
        } catch { connected = false; self.error = error.localizedDescription; await service.disconnect() }
    }

    func disconnect() async {
        guard !transferring else { return }
        cancelSizeScan()
        await service.disconnect()
        connected = false; entries = []; selection = []; path = []
    }

    func load(path newPath: [RemoteFile]? = nil, storage: UInt32? = nil) async {
        guard !busy, connected else { return }
        cancelSizeScan()
        busy = true; error = nil; selection = []; search = ""
        defer { busy = false }
        let nextPath = newPath ?? path
        let nextStorage = storage ?? storageID
        do {
            let contents = try await service.list(storage: nextStorage, parent: nextPath.last?.id ?? UInt32.max)
            path = nextPath; storageID = nextStorage; entries = contents
            calculateSizes()
        } catch { self.error = error.localizedDescription }
    }

    func toggle(_ file: RemoteFile) {
        guard !busy else { return }
        if file.isFolder { Task { await load(path: path + [file]) }; return }
        if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
    }

    func copySelected(to destination: URL, record: @escaping (ImportRecord) -> Void) {
        let files = selectedFiles
        guard !busy, !files.isEmpty else { return }
        beginTransfer(total: files.count)
        Task {
            defer { endTransfer() }
            var saved: [String] = []
            var failures: [String] = []
            do {
                let committer = try FileCommitter(destination: destination)
                defer { committer.cleanup() }
                for (index, file) in files.enumerated() {
                    if stopRequested { break }
                    completed = index; fraction = 0; currentFile = file.name
                    do {
                        let temporary = try await service.download(file, to: committer.stagingDirectory, progress: progressHandler())
                        let result = try committer.commit(temporary, named: file.name, expectedBytes: Int64(clamping: file.size), date: file.date)
                        saved.append(result.path); selection.remove(file.id)
                    } catch {
                        failures.append("\(file.name): \(error.localizedDescription)")
                        // Do not repeatedly issue commands to a potentially disconnected USB device.
                        break
                    }
                }
                record(ImportRecord(deviceName: deviceName, files: saved, failures: failures, destination: destination.path, stopped: stopRequested))
                message = "\(saved.count) files copied to your Mac\(stopRequested ? " · Stopped" : "")."
                if !failures.isEmpty { error = failures.joined(separator: "\n") }
            } catch { self.error = error.localizedDescription }
        }
    }

    func chooseFilesToSend() {
        guard connected, !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Send files to \(path.last?.name ?? "phone storage")"
        panel.message = "Files will be copied into the phone folder currently open in DroidDock. Existing names get a numbered suffix."
        panel.prompt = "Send to phone"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.send(panel.urls) }
        }
    }

    private func send(_ urls: [URL]) {
        guard !busy, connected, !urls.isEmpty else { return }
        let destinationStorage = storageID
        let destinationFolder = parentID
        beginTransfer(total: urls.count)
        Task {
            var count = 0
            for (index, url) in urls.enumerated() {
                if stopRequested { break }
                completed = index; fraction = 0; currentFile = url.lastPathComponent
                do {
                    _ = try await service.upload(url, storage: destinationStorage, parent: destinationFolder, progress: progressHandler())
                    count += 1
                } catch { self.error = error.localizedDescription; break }
            }
            message = "\(count) files sent to \(path.last?.name ?? "phone storage")\(stopRequested ? " · Stopped" : "")."
            // Keep a transfer error visible when refreshing the folder contents.
            let transferError = error
            endTransfer()
            await load()
            if let transferError { error = transferError }
        }
    }

    private func beginTransfer(total: Int) {
        cancelSizeScan()
        busy = true; transferring = true; stopRequested = false
        self.total = total; completed = 0; fraction = 0; error = nil; message = nil
    }
    private func endTransfer() { busy = false; transferring = false; currentFile = ""; calculateSizes() }

    private func cancelSizeScan() {
        sizeTask?.cancel(); sizeTask = nil; sizeGeneration = UUID()
        calculatingSize = false; folderSizes = [:]; sizeError = nil
    }

    func calculateSizes() {
        cancelSizeScan()
        guard connected else { return }
        calculatingSize = true
        let generation = sizeGeneration
        let storage = storageID
        let root = String(parentID)
        let initial = entries
        sizeTask = Task { [weak self, service] in
            do {
                let result = try await FolderSizeCalculator.calculate(root: root) { id in
                    if id == root { return initial.map { SizeEntry(id: String($0.id), bytes: $0.size, isFolder: $0.isFolder) } }
                    return try await service.sizeEntries(storage: storage, parent: UInt32(id)!)
                }
                guard let self, self.sizeGeneration == generation else { return }
                self.folderSizes = result; self.calculatingSize = false
            } catch is CancellationError {
                // A newer folder or transfer owns the UI now.
            } catch {
                guard let self, self.sizeGeneration == generation else { return }
                self.calculatingSize = false; self.sizeError = error.localizedDescription
            }
        }
    }
    private func progressHandler() -> (Double) -> Void {
        { [weak self] fraction in Task { @MainActor in self?.fraction = fraction } }
    }
}
