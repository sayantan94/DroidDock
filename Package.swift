// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDroid",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "MacDroid", targets: ["MacDroid"])],
    targets: [
        .target(name: "MacDroidCore"),
        .systemLibrary(name: "CLibMTP", pkgConfig: "libmtp", providers: [.brew(["libmtp"])]),
        .executableTarget(name: "MacDroid", dependencies: ["MacDroidCore", "CLibMTP"]),
        .testTarget(name: "MacDroidCoreTests", dependencies: ["MacDroidCore"])
    ]
)
