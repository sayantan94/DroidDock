import Foundation
import IOKit

@MainActor
final class USBMonitor: ObservableObject {
    @Published var accessoryMessage: String?
    @Published var connectionFingerprint = ""
    private var timer: Timer?

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var found: String?
        var connections: [String] = []
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(device, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let values = properties?.takeRetainedValue() as? [String: Any],
                  let vendor = values["idVendor"] as? Int, let product = values["idProduct"] as? Int else { continue }
            let session = (values["sessionID"] as? NSNumber)?.stringValue ?? ""
            connections.append("\(vendor):\(product):\(session)")
            if vendor == 0x18d1 && (0x2d00...0x2d05).contains(product) {
                let name = values["USB Product Name"] as? String ?? "Your phone"
                found = "The Mac sees \(name) in Android accessory mode. Another connection app or background service may be switching it into this mode. Close that service, then reconnect with File transfer selected."
            }
        }
        if accessoryMessage != found { accessoryMessage = found }
        let fingerprint = connections.sorted().joined(separator: "|")
        if connectionFingerprint != fingerprint { connectionFingerprint = fingerprint }
    }
}
