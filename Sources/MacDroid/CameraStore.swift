import AppKit
@preconcurrency import ImageCaptureCore
import UniformTypeIdentifiers
import MacDroidCore

enum ConnectionState: Equatable {
    case waiting, opening, scanning, ready, problem(String)
    var label: String {
        switch self {
        case .waiting: return "Waiting for your phone"
        case .opening: return "Connecting…"
        case .scanning: return "Reading your photo library…"
        case .ready: return "Connected over USB"
        case .problem: return "Connection needs attention"
        }
    }
}

@MainActor
final class CameraStore: NSObject, ObservableObject {
    @Published var state: ConnectionState = .waiting
    @Published var items: [MediaItem] = []
    @Published var devices: [ICCameraDevice] = []
    @Published var activeDeviceID: String?
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var downloadFraction: Double = 0
    @Published var deviceName = "Your Android phone"
    @Published private(set) var isDemo: Bool
    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var files: [String: ICCameraFile] = [:]
    private var thumbnailRequests: Set<String> = []
    private var catalogUpdate: DispatchWorkItem?
    private var demoURLs: [String: URL] = [:]
    private var pending: (id: UUID, continuation: CheckedContinuation<URL, Error>)?
    private var downloadProgress: Progress?
    private var progressTimer: Timer?
    private var lastProgressAt = Date()
    private var started = false

    init(demo: Bool = false) { isDemo = demo; super.init() }

    func start() {
        guard !started else { return }
        started = true
        if isDemo { loadDemo(); return }
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
        browser.start()
    }

    func shutdown() {
        progressTimer?.invalidate()
        catalogUpdate?.cancel()
        camera?.requestCloseSession()
        browser.stop()
        if isDemo, let url = demoURLs.values.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: url) }
    }

    func pauseForFileTransfer() async {
        guard pending == nil, !isDemo else { return }
        catalogUpdate?.cancel(); catalogUpdate = nil
        let previous = camera
        camera = nil; activeDeviceID = nil; items = []; files = [:]; thumbnails = [:]; devices = []
        state = .waiting
        if let previous, previous.hasOpenSession {
            await withCheckedContinuation { continuation in
                previous.requestCloseSession(options: nil) { _ in continuation.resume() }
            }
        }
        previous?.delegate = nil
        browser.stop(); started = false
    }

    func showDemo() async {
        guard !isDemo else { return }
        await pauseForFileTransfer()
        isDemo = true; started = true; loadDemo()
    }

    func useConnectedPhone() {
        guard isDemo else { return }
        if let directory = demoURLs.values.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: directory) }
        demoURLs = [:]; items = []; thumbnails = [:]
        isDemo = false; started = false; state = .waiting; deviceName = "Your Android phone"
        start()
    }

    func refresh() {
        guard pending == nil, !isDemo else { return }
        if let camera, camera.hasOpenSession {
            rebuildCatalog()
            if state != .ready { state = .scanning }
        } else if let camera { connect(camera) }
        else { browser.stop(); browser.start() }
    }

    func selectDevice(_ id: String) {
        guard pending == nil, let device = devices.first(where: { deviceID($0) == id }) else { return }
        connect(device)
    }

    func deviceID(_ device: ICCameraDevice) -> String {
        device.uuidString ?? "usb-\(device.usbLocationID)-\(device.usbProductID)"
    }

    private func connect(_ device: ICCameraDevice) {
        if camera !== device {
            camera?.requestCloseSession()
            camera?.delegate = nil
        }
        catalogUpdate?.cancel()
        camera = device; activeDeviceID = deviceID(device)
        deviceName = device.name ?? "Android phone"
        items = []; files = [:]; thumbnails = [:]; thumbnailRequests = []
        state = .opening
        device.delegate = self
        if device.hasOpenSession {
            rebuildCatalog()
            state = device.contentCatalogPercentCompleted == 100 ? .ready : .scanning
        } else { device.requestOpenSession() }
    }

    private func itemID(_ file: ICCameraItem) -> String {
        if file.ptpObjectHandle != 0 { return "\(activeDeviceID ?? "")-\(file.ptpObjectHandle)" }
        return file.fileSystemPath ?? "\(ObjectIdentifier(file))"
    }

    private func albumPath(_ file: ICCameraItem) -> String {
        var components: [String] = []
        var parent = file.parentFolder
        while let folder = parent {
            if let name = folder.name { components.insert(name, at: 0) }
            parent = folder.parentFolder
        }
        // Storage names vary across Android manufacturers. Keep folder identity
        // intact so two folders named Camera are not accidentally merged.
        return components.isEmpty ? "Phone photos" : components.joined(separator: " / ")
    }

    private func rebuildCatalog() {
        guard let camera else { return }
        var newFiles: [String: ICCameraFile] = [:]
        var catalog: [MediaItem] = []
        for case let file as ICCameraFile in camera.mediaFiles ?? [] {
            let name = file.name ?? file.originalFilename ?? "Untitled"
            let type = file.uti.flatMap { UTType($0) }
            let kind = MediaItem.kind(for: name) ?? (type?.conforms(to: .image) == true ? .photo : type?.conforms(to: .movie) == true ? .video : nil)
            guard let kind else { continue }
            let id = itemID(file)
            guard newFiles[id] == nil else { continue }
            newFiles[id] = file
            catalog.append(MediaItem(id: id, name: name, album: albumPath(file), byteCount: Int64(file.fileSize),
                                     date: file.exifCreationDate ?? file.creationDate ?? file.fileCreationDate, kind: kind))
        }
        files = newFiles
        items = catalog.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func scheduleCatalogUpdate() {
        // A large Android library can emit thousands of callbacks during discovery.
        guard catalogUpdate == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.catalogUpdate = nil
            self?.rebuildCatalog()
        }
        catalogUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func requestThumbnail(for item: MediaItem) {
        guard thumbnails[item.id] == nil, !thumbnailRequests.contains(item.id), let file = files[item.id], pending == nil else { return }
        thumbnailRequests.insert(item.id)
        let sessionID = activeDeviceID
        file.requestThumbnailData(options: [.imageSourceThumbnailMaxPixelSize: 420]) { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let self, self.activeDeviceID == sessionID, self.files[item.id] === file else { return }
                if let data, let image = NSImage(data: data) { self.thumbnails[item.id] = image }
            }
        }
    }

    func download(_ item: MediaItem, to directory: URL) async throws -> URL {
        if isDemo {
            guard let source = demoURLs[item.id] else { throw ImportError.invalidDownload }
            let result = directory.appendingPathComponent(UUID().uuidString + ".png")
            try await Task.sleep(nanoseconds: 250_000_000)
            try FileManager.default.copyItem(at: source, to: result)
            downloadFraction = 1
            return result
        }
        guard let camera, camera.hasOpenSession, let file = files[item.id] else { throw ImportError.disconnected }
        guard pending == nil else { throw CocoaError(.fileLocking) }
        let id = UUID()
        let filename = id.uuidString + "-" + FileCommitter.safeFilename(item.name)
        downloadFraction = 0; lastProgressAt = Date()
        return try await withCheckedThrowingContinuation { continuation in
            pending = (id, continuation)
            downloadProgress = file.requestDownload(options: [
                .downloadsDirectoryURL: directory,
                .saveAsFilename: filename,
                .overwrite: false,
                .deleteAfterSuccessfulDownload: false,
                .sidecarFiles: false
            ]) { [weak self] savedName, error in
                DispatchQueue.main.async {
                    guard let self, self.pending?.id == id else { return }
                    if let error { self.finishDownload(.failure(error)) }
                    else {
                        // ImageCapture returns a filename, not an arbitrary trusted path.
                        let actualName = savedName.map { ($0 as NSString).lastPathComponent } ?? filename
                        self.finishDownload(.success(directory.appendingPathComponent(actualName)))
                    }
                }
            }
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.pending?.id == id else { return }
                    let fraction = self.downloadProgress?.fractionCompleted ?? 0
                    if fraction > self.downloadFraction { self.lastProgressAt = Date() }
                    self.downloadFraction = fraction
                    // Avoid leaving the UI stuck indefinitely on a locked or vanished phone.
                    if Date().timeIntervalSince(self.lastProgressAt) > 120 {
                        self.camera?.cancelDownload()
                        self.finishDownload(.failure(ImportError.stalled))
                        self.state = .problem(ImportError.stalled.localizedDescription)
                    }
                }
            }
        }
    }

    private func finishDownload(_ result: Result<URL, Error>) {
        progressTimer?.invalidate(); progressTimer = nil; downloadProgress = nil
        let continuation = pending?.continuation
        pending = nil
        continuation?.resume(with: result)
    }

    private func disconnected(_ device: ICDevice) {
        guard device === camera else { return }
        finishDownload(.failure(ImportError.disconnected))
        catalogUpdate?.cancel(); catalogUpdate = nil
        camera = nil; activeDeviceID = nil
        files = [:]; items = []; thumbnails = [:]; thumbnailRequests = []
        deviceName = "Your Android phone"; state = .waiting
    }
}

extension CameraStore: @preconcurrency ICDeviceBrowserDelegate, @preconcurrency ICCameraDeviceDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        if !devices.contains(where: { $0 === camera }) { devices.append(camera) }
        if self.camera == nil { connect(camera) }
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        devices.removeAll { $0 === device }; disconnected(device)
    }
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        guard device === camera else { return }
        if let error { state = .problem("Couldn’t open your phone: \(error.localizedDescription). Close other photo-transfer apps and reconnect.") }
        else { state = .scanning; rebuildCatalog() }
    }
    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        guard device === camera else { return }
        finishDownload(.failure(ImportError.disconnected))
        state = .problem(error?.localizedDescription ?? "The photo connection closed. Unlock your phone and click Refresh.")
    }
    func didRemove(_ device: ICDevice) { disconnected(device) }
    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        guard device === camera else { return }
        catalogUpdate?.cancel(); catalogUpdate = nil
        rebuildCatalog(); state = .ready
    }
    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) { if camera === self.camera { scheduleCatalogUpdate() } }
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) { if camera === self.camera { scheduleCatalogUpdate() } }
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) { if camera === self.camera { scheduleCatalogUpdate() } }
    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {
        guard camera === self.camera, let thumbnail else { return }
        thumbnails[itemID(item)] = NSImage(cgImage: thumbnail, size: .zero)
    }
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) { if device === camera { refresh() } }
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        if device === camera { state = .problem("Unlock your phone to access its photos.") }
    }
}

extension CameraStore {
    private func loadDemo() {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacDroid-Demo-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for index in 0..<18 {
                let image = DemoArtwork.landscape(index: index)
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else { continue }
                let id = "demo-\(index)"
                let name = "SAMPLE_\(String(format: "%04d", index + 1)).png"
                let url = directory.appendingPathComponent(name)
                try data.write(to: url)
                demoURLs[id] = url; thumbnails[id] = image
                items.append(MediaItem(id: id, name: name, album: index < 12 ? "DCIM / Camera" : "Pictures / Screenshots",
                                       byteCount: Int64(data.count), date: Calendar.current.date(byAdding: .day, value: -(index / 6), to: Date()), kind: .photo))
            }
            deviceName = "Demo phone"; state = .ready
        } catch { state = .problem(error.localizedDescription) }
    }
}
