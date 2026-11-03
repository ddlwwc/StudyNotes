// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StudyNotesKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(name: "StudyNotesKit", targets: ["StudyNotesKit"])
    ],
    targets: [
        .target(name: "StudyNotesKit"),
        .testTarget(
            name: "StudyNotesKitTests",
            dependencies: ["StudyNotesKit"]
        )
    ]
)
