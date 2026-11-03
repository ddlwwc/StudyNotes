// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StudyNotesIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)
    ],
    products: [
        .library(name: "StudyNotesIOSCore", targets: ["StudyNotesIOSCore"]),
        .executable(name: "StudyNotesIOS", targets: ["StudyNotesIOS"])
    ],
    dependencies: [
        .package(path: "../../Packages/StudyNotesKit")
    ],
    targets: [
        .target(
            name: "StudyNotesIOSCore",
            dependencies: [
                .product(name: "StudyNotesKit", package: "StudyNotesKit")
            ]
        ),
        .executableTarget(
            name: "StudyNotesIOS",
            dependencies: [
                "StudyNotesIOSCore",
                .product(name: "StudyNotesKit", package: "StudyNotesKit")
            ]
        ),
        .testTarget(
            name: "StudyNotesIOSCoreTests",
            dependencies: [
                "StudyNotesIOSCore",
                .product(name: "StudyNotesKit", package: "StudyNotesKit")
            ]
        )
    ]
)
