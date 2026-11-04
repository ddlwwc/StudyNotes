import AppKit
import Foundation
import StudyNotesMacUI
import SwiftUI

@main
struct StudyNotesMacSnapshotMain {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared

        let arguments = Array(CommandLine.arguments.dropFirst())
        let outputURL: URL
        if let argument = arguments.first(where: {
            !$0.hasPrefix("--")
        }) {
            outputURL = URL(fileURLWithPath: argument)
        } else {
            outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(path: "dist/StudyNotesMac-1440x1024.png")
        }

        let mode: SnapshotWorkspaceMode
        if arguments.contains("--ai-settings-compact") {
            mode = .compactAISettings
        } else if arguments.contains("--ai-settings-empty") {
            mode = .emptyAISettings
        } else if arguments.contains("--ai-settings") {
            mode = .aiSettings
        } else if arguments.contains("--settings") {
            mode = .settings
        } else if arguments.contains("--settings-compact") {
            mode = .compactSettings
        } else if arguments.contains("--reader-outline") {
            mode = .readerOutline
        } else if arguments.contains("--search-results") {
            mode = .searchResults
        } else {
            mode = .tree
        }
        let isDarkMode = arguments.contains("--dark")
        let size = mode.canvasSize
        let hostingView = NSHostingView(
            rootView: SnapshotWorkspaceView(
                mode: mode,
                isDarkMode: isDarkMode
            )
                .frame(width: size.width, height: size.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(
            named: isDarkMode ? .darkAqua : .aqua
        )
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard
            let representation = hostingView.bitmapImageRepForCachingDisplay(
                in: hostingView.bounds
            )
        else {
            throw SnapshotError.renderFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)
        print(outputURL.path)
    }
}

private enum SnapshotError: LocalizedError {
    case renderFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            "AppKit 未能生成快照图像。"
        case .pngEncodingFailed:
            "PNG 编码失败。"
        }
    }
}
