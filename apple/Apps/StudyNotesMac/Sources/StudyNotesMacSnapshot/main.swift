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
        if arguments.contains("--settings") {
            mode = .settings
        } else if arguments.contains("--settings-compact") {
            mode = .compactSettings
        } else if arguments.contains("--search-results") {
            mode = .searchResults
        } else {
            mode = .tree
        }
        let renderer = ImageRenderer(content: SnapshotWorkspaceView(mode: mode))
        renderer.proposedSize = ProposedViewSize(
            width: mode.canvasSize.width,
            height: mode.canvasSize.height
        )
        renderer.scale = 1

        guard let image = renderer.cgImage else {
            throw SnapshotError.renderFailed
        }

        let representation = NSBitmapImageRep(cgImage: image)
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
            "ImageRenderer 未能生成图像。"
        case .pngEncodingFailed:
            "PNG 编码失败。"
        }
    }
}
