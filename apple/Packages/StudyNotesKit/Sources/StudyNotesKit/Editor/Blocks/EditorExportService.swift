import Foundation

public struct EditorExportService {
    private let fileManager: FileManager
    private let fallback: EditorMarkdownFallback

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        fallback = EditorMarkdownFallback()
    }

    @discardableResult
    public func writeReadableMarkdown(
        markdown: String,
        blocks: [EditorBlockEnvelope],
        destinationURL: URL
    ) throws -> URL {
        let readable = try fallback.readableMarkdown(
            markdown,
            blocks: blocks
        )
        try Data(readable.utf8).write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    @discardableResult
    public func writePackage(
        markdown: String,
        blocks: [EditorBlockEnvelope],
        annotationsJSON: Data?,
        conversationsJSON: Data?,
        destinationURL: URL
    ) throws -> URL {
        let parent = destinationURL.deletingLastPathComponent()
        let temporary = parent.appending(
            path: ".export-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: temporary,
            withIntermediateDirectories: false
        )
        do {
            let files = try fallback.packageFiles(
                markdown: markdown,
                blocks: blocks,
                annotationsJSON: annotationsJSON,
                conversationsJSON: conversationsJSON
            )
            for relativePath in files.keys.sorted() {
                let target = temporary.appending(path: relativePath)
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try files[relativePath]?.write(to: target, options: .atomic)
            }
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporary, to: destinationURL)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}
