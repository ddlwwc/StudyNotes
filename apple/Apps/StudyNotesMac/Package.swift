// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StudyNotesMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "StudyNotesMac", targets: ["StudyNotesMac"]),
        .executable(name: "StudyNotesMacSnapshot", targets: ["StudyNotesMacSnapshot"])
    ],
    dependencies: [
        .package(path: "../../Packages/StudyNotesKit")
    ],
    targets: [
        .target(
            name: "StudyNotesMacUI",
            dependencies: [
                .product(name: "StudyNotesKit", package: "StudyNotesKit")
            ]
        ),
        .executableTarget(
            name: "StudyNotesMac",
            dependencies: ["StudyNotesMacUI"]
        ),
        .executableTarget(
            name: "StudyNotesMacSnapshot",
            dependencies: ["StudyNotesMacUI"]
        )
    ]
)
