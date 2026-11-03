import AppKit
import Foundation
import StudyNotesMacUI
import SwiftUI

@main
struct StudyNotesMacSnapshotMain {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared

        let outputURL: URL
        if let argument = CommandLine.arguments.dropFirst().first {
            outputURL = URL(fileURLWithPath: argument)
        } else {
            outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(path: "dist/StudyNotesMac-1440x1024.png")
        }

        let renderer = ImageRenderer(content: SnapshotWorkspaceView())
        renderer.proposedSize = ProposedViewSize(width: 1_440, height: 1_024)
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
