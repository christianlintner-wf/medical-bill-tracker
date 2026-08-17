// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RechnungenKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RechnungenKit", targets: ["RechnungenKit"])
    ],
    targets: [
        .target(name: "RechnungenKit"),
        .testTarget(name: "RechnungenKitTests", dependencies: ["RechnungenKit"])
    ]
)
