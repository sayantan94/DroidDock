import Foundation

public struct MediaItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case photo, video }
    public let id: String
    public let name: String
    public let album: String
    public let byteCount: Int64
    public let date: Date?
    public let kind: Kind

    public init(id: String, name: String, album: String, byteCount: Int64, date: Date?, kind: Kind) {
        self.id = id; self.name = name; self.album = album
        self.byteCount = byteCount; self.date = date; self.kind = kind
    }

    public static func kind(for filename: String) -> Kind? {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ["jpg", "jpeg", "heic", "heif", "png", "gif", "webp", "tif", "tiff", "bmp", "dng", "avif", "raw"].contains(ext) { return .photo }
        if ["mp4", "mov", "m4v", "3gp", "3gpp", "mkv", "avi", "webm"].contains(ext) { return .video }
        return nil
    }
}

public struct ImportRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let deviceName: String
    public let files: [String]
    public let failures: [String]
    public let destination: String
    public let stopped: Bool

    public init(deviceName: String, files: [String], failures: [String], destination: String, stopped: Bool) {
        id = UUID(); date = Date(); self.deviceName = deviceName; self.files = files
        self.failures = failures; self.destination = destination; self.stopped = stopped
    }
}
