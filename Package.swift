// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StudyCore",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "StudyCore", targets: ["StudyCore"]),
        .library(name: "StudyApp", targets: ["StudyApp"]),
    ],
    targets: [
        .target(name: "StudyCore"),
        .target(
            name: "StudyApp",
            dependencies: ["StudyCore"],
            path: "App/Shared"
        ),
        .testTarget(name: "StudyCoreTests", dependencies: ["StudyCore"]),
    ]
)
