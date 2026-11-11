import AppKit
import Combine
import MacDroidCore

enum LibraryFilter: Hashable {
    case all, photos, videos, album(String), history, files
    var title: String {
        switch self {
        case .all: return "All photos & videos"
        case .photos: return "Photos"
        case .videos: return "Videos"
        case let .album(name): return name.components(separatedBy: " / ").last ?? name
        case .history: return "Transfer history"
        case .files: return "Your phone, folder by folder."
        }
    }
}
enum SortOrder: String, CaseIterable { case newest = "Newest first", oldest = "Oldest first", name = "Filename" }

@MainActor
final class AppModel: ObservableObject {
    let camera: CameraStore
    let usb = USBMonitor()
    let mtp = MTPStore()
    private var mtpChanges: AnyCancellable?
    private var usbChanges: AnyCancellable?
    private var usbReconnect: AnyCancellable?
    @Published private(set) var usingFileConnection = true
    @Published var switchingMode = false
    let engine = ImportEngine()
    @Published var selection: Set<String> = []
    @Published var imported: Set<String> = []
    @Published var filter: LibraryFilter = .files
    @Published var search = ""
    @Published var sort: SortOrder = .newest
    @Published var destination: URL
    @Published var showGuide = false
    @Published var preview: MediaItem?
    @Published var isImporting = false
    @Published var stopRequested = false
    @Published var currentFile = ""
    @Published var completed = 0
    @Published var total = 0
    @Published var history: [ImportRecord] = []
    @Published var lastResult: ImportRecord?
    @Published var errorMessage: String?
    private var historyURL: URL

    init(demo: Bool = false) {
        camera = CameraStore(demo: demo)
        if demo { filter = .all; usingFileConnection = false }
        let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        destination = UserDefaults.standard.string(forKey: "destination").map { URL(fileURLWithPath: $0) } ?? base.appendingPathComponent("DroidDock", isDirectory: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DroidDock")
        historyURL = support.appendingPathComponent(demo ? "demo-history.json" : "history.json")
        if let data = try? Data(contentsOf: historyURL), let records = try? JSONDecoder().decode([ImportRecord].self, from: data) { history = records }
        mtpChanges = mtp.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        usbChanges = usb.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        usbReconnect = usb.$connectionFingerprint.dropFirst().removeDuplicates().sink { [weak self] fingerprint in
            guard !fingerprint.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.usingFileConnection, !self.camera.isDemo,
                      !self.mtp.connected, !self.mtp.busy, !self.switchingMode else { return }
                await self.mtp.connect()
            }
        }
    }

    var visibleItems: [MediaItem] {
        camera.items.filter { item in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .photos: matchesFilter = item.kind == .photo
            case .videos: matchesFilter = item.kind == .video
            case .album(let name): matchesFilter = item.album == name
            case .history, .files: matchesFilter = false
            }
            return matchesFilter && (search.isEmpty || item.name.localizedCaseInsensitiveContains(search) || item.album.localizedCaseInsensitiveContains(search))
        }.sorted {
            switch sort {
            case .newest: return ($0.date ?? .distantPast, $0.name) > ($1.date ?? .distantPast, $1.name)
            case .oldest: return ($0.date ?? .distantPast, $0.name) < ($1.date ?? .distantPast, $1.name)
            case .name: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    var selectedItems: [MediaItem] { camera.items.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.byteCount } }
    var albums: [String] { Array(Set(camera.items.map(\.album))).sorted() }
    var canImport: Bool { !selection.isEmpty && !isImporting && camera.state == .ready }

    func start() {
        usb.start()
        if camera.isDemo { camera.start() }
        else { Task { await mtp.connect() } }
    }

    func toggle(_ item: MediaItem) {
        guard !isImporting else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }
    func selectAll() { if !isImporting { selection.formUnion(visibleItems.map(\.id)) } }
    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose where to copy your photos"
        panel.prompt = "Choose folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.destination = url
                UserDefaults.standard.set(url.path, forKey: "destination")
            }
        }
    }
    func reveal(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { errorMessage = "This folder has moved or is no longer available: \(path)"; return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func importSelected() {
        guard canImport else { return }
        let items = selectedItems
        let folder = destination
        let deviceName = camera.deviceName
        total = items.count; completed = 0; stopRequested = false
        lastResult = nil; isImporting = true
        Task {
            defer { isImporting = false; currentFile = "" }
            do {
                let result = try await engine.run(items: items, destination: folder, deviceName: deviceName,
                    download: { [camera] item, directory in try await camera.download(item, to: directory) },
                    onProgress: { [weak self] index, item in self?.completed = index; self?.currentFile = item.name },
                    onCommit: { [weak self] item, _ in self?.selection.remove(item.id); self?.imported.insert(item.id) })
                lastResult = result
                recordImport(result)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func stopImport() { stopRequested = true; engine.stopAfterCurrentFile() }
    func navigate(_ next: LibraryFilter) {
        guard !isImporting, !mtp.busy, !switchingMode else { return }
        filter = next
        if next == .history { return }
        if next == .files && !usingFileConnection {
            usingFileConnection = true
            switchingMode = true
            Task {
                await camera.pauseForFileTransfer()
                await mtp.connect()
                switchingMode = false
            }
        } else if usingFileConnection && next != .files {
            usingFileConnection = false
            switchingMode = true
            Task { await mtp.disconnect(); camera.start(); switchingMode = false }
        }
    }
    func recordImport(_ record: ImportRecord) {
        if camera.isDemo { return }
        history.insert(record, at: 0); history = Array(history.prefix(100))
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
        } catch { errorMessage = "The files were copied, but history could not be saved: \(error.localizedDescription)" }
    }

    func showDemo() {
        guard !isImporting, !mtp.busy else { return }
        Task {
            await mtp.disconnect()
            await camera.showDemo()
            usingFileConnection = false; filter = .all; selection = []; lastResult = nil
        }
    }

    func useConnectedPhone() {
        selection = []; imported = []; lastResult = nil
        Task {
            camera.useConnectedPhone()
            await camera.pauseForFileTransfer()
            usingFileConnection = true; filter = .files
            await mtp.connect()
        }
    }
    func connectionChanged() {
        selection = []; imported = []; preview = nil
        if case .album = filter { filter = .all }
    }
}

func byteString(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
