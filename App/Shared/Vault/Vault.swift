import Foundation
import StudyCore

public enum VaultError: LocalizedError {
    case noVaultSelected
    case bookmarkStale
    case accessDenied(URL)

    public var errorDescription: String? {
        switch self {
        case .noVaultSelected:
            return "还没有选择笔记目录"
        case .bookmarkStale:
            return "笔记目录已移动或重命名，需要重新选择"
        case .accessDenied(let url):
            return "没有权限访问 \(url.lastPathComponent)"
        }
    }
}

@MainActor
public final class Vault {
    public private(set) var root: URL
    private var isAccessing = false

    private init(root: URL) {
        self.root = root
    }

    deinit {
        if isAccessing {
            root.stopAccessingSecurityScopedResource()
        }
    }

    public static func open(root: URL) throws -> Vault {
        let vault = Vault(root: root)
        vault.isAccessing = root.startAccessingSecurityScopedResource()
        try VaultLayout.ensureDirectories(in: root)
        return vault
    }

    public var notesURL: URL { root.appendingPathComponent(VaultLayout.notesDirectory, isDirectory: true) }
    public var stateURL: URL { root.appendingPathComponent(VaultLayout.stateDirectory, isDirectory: true) }
    public var sessionsURL: URL { root.appendingPathComponent(VaultLayout.sessionsDirectory, isDirectory: true) }
    public var annotationsURL: URL {
        root.appendingPathComponent(VaultLayout.annotationsDirectory, isDirectory: true)
    }

    public func close() {
        if isAccessing {
            root.stopAccessingSecurityScopedResource()
            isAccessing = false
        }
    }
}
