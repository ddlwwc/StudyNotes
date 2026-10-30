import Foundation

public enum FileIOError: LocalizedError {
    case notDownloaded(URL)
    case readFailed(URL, Error)
    case writeFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .notDownloaded(let url):
            return "\(url.lastPathComponent) 还在 iCloud 上，尚未下载到本机"
        case .readFailed(let url, let error):
            return "读取 \(url.lastPathComponent) 失败：\(error.localizedDescription)"
        case .writeFailed(let url, let error):
            return "写入 \(url.lastPathComponent) 失败：\(error.localizedDescription)"
        }
    }
}

public enum VaultLayout {
    public static let notesDirectory = "notes"
    public static let stateDirectory = "state"
    public static let sessionsDirectory = "sessions"
    public static let annotationsDirectory = "annotations"

    public static let allDirectories = [
        notesDirectory,
        stateDirectory,
        sessionsDirectory,
        annotationsDirectory,
    ]

    public static func ensureDirectories(in root: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw VaultLayoutError.missing(root)
        }
        guard isDirectory.boolValue else {
            throw VaultLayoutError.notADirectory(root)
        }
        for name in allDirectories {
            let url = root.appendingPathComponent(name, isDirectory: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }
}

public enum VaultLayoutError: LocalizedError {
    case missing(URL)
    case notADirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .missing(let url):
            return "目录不存在：\(url.lastPathComponent)"
        case .notADirectory(let url):
            return "\(url.lastPathComponent) 不是一个目录"
        }
    }
}

public enum iCloudStatus: Equatable, Sendable {
    case local
    case notDownloaded
    case unknown
}

public enum FileIO {

    public static func status(of url: URL) -> iCloudStatus {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus else {
            return .unknown
        }
        switch status {
        case .current, .downloaded:
            return .local
        case .notDownloaded:
            return .notDownloaded
        default:
            return .unknown
        }
    }

    public static func requestDownload(of url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    public static func read(_ url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FileIOError.readFailed(url, error)
        }
    }

    public static func write(_ content: String, to url: URL) throws {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw FileIOError.writeFailed(url, error)
        }
    }

    public static func listMarkdownFiles(in directory: URL) throws -> [URL] {
        let items = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return items
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func availableNoteName(in directory: URL, base: String) -> URL {
        var candidate = directory.appendingPathComponent("\(base).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter).md")
            counter += 1
        }
        return candidate
    }
}
