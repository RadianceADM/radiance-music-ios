// swift-tools-version: 6.0
// Radiance Music for iPhone and iPad (xtool + SwiftPM; built on ribs02, never on a Mac).
//
// RadianceKit: songs, library, lyrics, search, the share wire: Foundation only, so `swift test` runs on Linux.
// RadianceMusic: the app (SwiftUI, AVFoundation, MediaPlayer): built for iOS by `xtool dev build`.
// RADIANCE_KIT_ONLY=1 leaves the app out (the Linux tests; the manifest is read on the Linux host either way).

import Foundation
import PackageDescription

let kitOnly = ProcessInfo.processInfo.environment["RADIANCE_KIT_ONLY"] == "1"

var products: [Product] = []
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "RadianceKit", path: "Sources/RadianceKit"),
    .testTarget(
        name: "RadianceKitTests",
        dependencies: ["RadianceKit"],
        path: "Tests/RadianceKitTests",
        resources: [.copy("Samples")]
    ),
]

if !kitOnly {
    // an xtool project has exactly one library product: the app
    products.append(.library(name: "RadianceMusic", targets: ["RadianceMusic"]))
    // the splitter's models run on ONNX Runtime (as Android's): its iPhone build, from Microsoft's package
    dependencies.append(.package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"))
    targets.append(.target(name: "RadianceMusic", dependencies: [
        "RadianceKit",
        .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
    ], path: "Sources/RadianceMusic"))
}

let package = Package(
    name: "RadianceMusic",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
