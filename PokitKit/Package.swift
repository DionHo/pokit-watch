// swift-tools-version: 5.9
import PackageDescription

// PokitKit contains everything that does not need Apple frameworks:
// the byte-level Pokit protocol, range tables and value formatting.
// It builds and tests on Linux as well, which keeps the protocol logic verifiable
// without a Mac.
let package = Package(
    name: "PokitKit",
    platforms: [
        .watchOS(.v10),
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "PokitKit", targets: ["PokitKit"]),
    ],
    targets: [
        .target(name: "PokitKit"),
        .testTarget(name: "PokitKitTests", dependencies: ["PokitKit"]),
    ]
)
