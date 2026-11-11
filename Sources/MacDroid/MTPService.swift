import Foundation
import CLibMTP
import MacDroidCore

struct RemoteStorage: Identifiable, Sendable {
    let id: UInt32
    let name: String
    let freeBytes: UInt64
}
struct RemoteFile: Identifiable, Hashable, Sendable {
    let id: UInt32
    let storage: UInt32
    let name: String
    let size: UInt64
    let date: Date?
    let isFolder: Bool
    var symbol: String {
        if isFolder { return "folder.fill" }
        switch MediaItem.kind(for: name) {
        case .photo: return "photo"
        case .video: return "film"
        default:
            if ["mp3", "wav", "flac", "m4a", "ogg"].contains((name as NSString).pathExtension.lowercased()) { return "music.note" }
            return "doc"
        }
    }
}
struct MTPFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class MTPProgressBox {
    let update: (Double) -> Void
    var lastUpdate = Date.distantPast
    init(_ update: @escaping (Double) -> Void) { self.update = update }
}
private let mtpProgressCallback: LIBMTP_progressfunc_t = { sent, total, context in
    guard let context else { return 0 }
    let box = Unmanaged<MTPProgressBox>.fromOpaque(context).takeUnretainedValue()
    if Date().timeIntervalSince(box.lastUpdate) > 0.1 || sent == total {
        box.lastUpdate = Date()
        box.update(total == 0 ? 0 : min(1, Double(sent) / Double(total)))
    }
    return 0
}

/// libmtp is synchronous and not thread-safe. Every call and pointer stays on
/// this one queue; the UI only receives independent Swift value types.
final class MTPService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.macdroid.mtp", qos: .userInitiated)
    private var device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>?
    private var initialized = false

    private func work<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: body)) }
        }
    }

    func connect() async throws -> (String, [RemoteStorage]) {
        try await work { [self] in
            if let device { LIBMTP_Release_Device(device); self.device = nil }
            if !initialized { LIBMTP_Init(); initialized = true }
            var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
            var count: Int32 = 0
            let status = LIBMTP_Detect_Raw_Devices(&raw, &count)
            defer { free(raw) }
            guard status == LIBMTP_ERROR_NONE, count > 0, let raw else {
                throw MTPFailure(message: "No file-transfer device found. Unlock your phone, choose File transfer / Android Auto in its USB notification, then reconnect the cable and try again.")
            }
            guard count == 1 else { throw MTPFailure(message: "Connect one Android phone at a time for file browsing.") }
            guard let connected = LIBMTP_Open_Raw_Device_Uncached(raw) else {
                throw MTPFailure(message: "Couldn’t open the phone. Close other Android transfer apps, Image Capture and Photos, then reconnect in File transfer mode.")
            }
            device = connected
            guard LIBMTP_Get_Storage(connected, 0) == 0 else { throw failure("Couldn’t read phone storage") }
            let namePointer = LIBMTP_Get_Friendlyname(connected) ?? LIBMTP_Get_Modelname(connected)
            let name = namePointer.map { String(cString: $0) } ?? "Android phone"
            free(namePointer)
            var stores: [RemoteStorage] = []
            var storage = connected.pointee.storage
            while let current = storage {
                let s = current.pointee
                stores.append(RemoteStorage(id: s.id, name: s.StorageDescription.map { String(cString: $0) } ?? "Internal storage", freeBytes: s.FreeSpaceInBytes))
                storage = s.next
            }
            guard !stores.isEmpty else { throw MTPFailure(message: "The phone is connected but hasn’t shared any storage. Unlock it and allow file access.") }
            return (name, stores)
        }
    }

    func disconnect() async {
        _ = try? await work { [self] in
            if let device { LIBMTP_Release_Device(device) }
            device = nil
        }
    }

    private func failure(_ action: String) -> MTPFailure {
        guard let device else { return MTPFailure(message: "Phone disconnected. Reconnect and try again.") }
        var stack = LIBMTP_Get_Errorstack(device)
        var messages: [String] = []
        while let error = stack {
            if let text = error.pointee.error_text { messages.append(String(cString: text)) }
            stack = error.pointee.next
        }
        LIBMTP_Clear_Errorstack(device)
        return MTPFailure(message: action + ". " + (messages.isEmpty ? "Unlock and reconnect your phone, then try again." : messages.joined(separator: " ")))
    }

    private func listSync(storage: UInt32, parent: UInt32) throws -> [RemoteFile] {
        guard let device else { throw ImportError.disconnected }
        LIBMTP_Clear_Errorstack(device)
        var file = LIBMTP_Get_Files_And_Folders(device, storage, parent)
        if file == nil, LIBMTP_Get_Errorstack(device) != nil { throw failure("Couldn’t read this folder") }
        var result: [RemoteFile] = []
        while let current = file {
            let f = current.pointee
            result.append(RemoteFile(id: f.item_id, storage: f.storage_id,
                name: f.filename.map { String(cString: $0) } ?? "Untitled", size: f.filesize,
                date: f.modificationdate > 0 ? Date(timeIntervalSince1970: Double(f.modificationdate)) : nil,
                isFolder: f.filetype == LIBMTP_FILETYPE_FOLDER))
            file = f.next
            LIBMTP_destroy_file_t(current)
        }
        return result.sorted { a, b in a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }
    func list(storage: UInt32, parent: UInt32) async throws -> [RemoteFile] {
        try await work { [self] in try listSync(storage: storage, parent: parent) }
    }

    func download(_ file: RemoteFile, to directory: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        try await work { [self] in
            guard let device else { throw ImportError.disconnected }
            let result = directory.appendingPathComponent(UUID().uuidString)
            let box = MTPProgressBox(progress)
            let pointer = Unmanaged.passRetained(box).toOpaque()
            defer { Unmanaged<MTPProgressBox>.fromOpaque(pointer).release() }
            LIBMTP_Clear_Errorstack(device)
            guard LIBMTP_Get_File_To_File(device, file.id, result.path, mtpProgressCallback, pointer) == 0 else {
                throw failure("Couldn’t copy \(file.name)")
            }
            return result
        }
    }

    func upload(_ source: URL, storage: UInt32, parent: UInt32, progress: @escaping (Double) -> Void) async throws -> String {
        try await work { [self] in
            guard let device else { throw ImportError.disconnected }
            let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw MTPFailure(message: "Choose regular files to send to the phone.") }
            let existing = try listSync(storage: storage, parent: parent)
            let safe = FileCommitter.safeFilename(source.lastPathComponent)
            let ext = (safe as NSString).pathExtension
            let stem = (safe as NSString).deletingPathExtension
            var name = safe
            var index = 2
            let names = Set(existing.map { $0.name.lowercased() })
            while names.contains(name.lowercased()) {
                name = "\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)"); index += 1
            }
            guard let metadata = LIBMTP_new_file_t() else { throw MTPFailure(message: "Couldn’t allocate transfer metadata.") }
            defer { LIBMTP_destroy_file_t(metadata) }
            metadata.pointee.filename = strdup(name)
            metadata.pointee.filesize = UInt64(values.fileSize ?? 0)
            metadata.pointee.parent_id = parent == UInt32.max ? 0 : parent
            metadata.pointee.storage_id = storage
            metadata.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
            let box = MTPProgressBox(progress)
            let pointer = Unmanaged.passRetained(box).toOpaque()
            defer { Unmanaged<MTPProgressBox>.fromOpaque(pointer).release() }
            LIBMTP_Clear_Errorstack(device)
            guard LIBMTP_Send_File_From_File(device, source.path, metadata, mtpProgressCallback, pointer) == 0 else {
                throw failure("Couldn’t send \(name). Check the phone for an incomplete copy")
            }
            guard let uploaded = LIBMTP_Get_Filemetadata(device, metadata.pointee.item_id) else { throw failure("Upload finished but couldn’t be verified") }
            defer { LIBMTP_destroy_file_t(uploaded) }
            guard uploaded.pointee.filesize == metadata.pointee.filesize else { throw MTPFailure(message: "The phone reported an incomplete copy of \(name). Try again.") }
            return name
        }
    }
}
