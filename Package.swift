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
    targets.append(.target(name: "RadianceMusic", dependencies: ["RadianceKit"], path: "Sources/RadianceMusic"))
}

let package = Package(
    name: "RadianceMusic",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v5]
)
