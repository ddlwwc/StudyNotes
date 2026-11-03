import AppKit
import Foundation

public enum WorkspaceRootStoreError: LocalizedError, Equatable {
    case invalidDirectory
    case insufficientPermissions
    case iCloudNotSignedIn
    case iCloudDriveUnavailable
    case bookmarkCreationFailed
    case bookmarkResolutionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            "所选位置不是可访问的文件夹。"
        case .insufficientPermissions:
            "没有读取和写入该学习目录的权限。"
        case .iCloudNotSignedIn:
            "尚未登录 iCloud，请先在系统设置中登录。"
        case .iCloudDriveUnavailable:
            "无法访问 iCloud Drive，请确认已在系统设置中登录 iCloud。"
        case .bookmarkCreationFailed:
            "无法保存该目录的访问权限。"
        case .bookmarkResolutionFailed:
            "无法恢复上次选择的学习目录，请重新选择。"
        }
    }
}

@MainActor
public final class WorkspaceRootStore {
    private static let bookmarkKey = "StudyNotesMac.workspaceBookmark"

    private let userDefaults: UserDefaults
    private var activeURL: URL?
    private var isAccessingSecurityScope = false

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func chooseDirectory() async -> URL? {
        await chooseDirectory(
            startingAt: activeURL?.deletingLastPathComponent()
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents"),
            title: "选择 StudyNotes 学习目录"
        )
    }

    public func chooseICloudDirectory() async throws -> URL? {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            throw WorkspaceRootStoreError.iCloudNotSignedIn
        }

        let iCloudDriveURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: iCloudDriveURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceRootStoreError.iCloudDriveUnavailable
        }

        return await chooseDirectory(
            startingAt: iCloudDriveURL,
            title: "选择 iCloud Drive 中的 StudyNotes 文件夹"
        )
    }

    private func chooseDirectory(startingAt directoryURL: URL, title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = "选择一个本地或 iCloud Drive 文件夹。StudyNotes 会在其中创建 Libraries 目录。"
        panel.prompt = "连接目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = directoryURL

        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }
        return response == .OK ? panel.url : nil
    }

    public func restoreSavedDirectory() throws -> WorkspaceLocation? {
        guard let bookmarkData = userDefaults.data(forKey: Self.bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw WorkspaceRootStoreError.bookmarkResolutionFailed
        }

        let location = try prepareDirectory(url)
        if isStale {
            try persistBookmark(for: url)
        }
        return location
    }

    public func adoptDirectory(at url: URL) throws -> WorkspaceLocation {
        let location = try prepareDirectory(url)
        try persistBookmark(for: url)
        return location
    }

    private func prepareDirectory(_ url: URL) throws -> WorkspaceLocation {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WorkspaceRootStoreError.invalidDirectory
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        guard FileManager.default.isReadableFile(atPath: url.path),
              FileManager.default.isWritableFile(atPath: url.path) else {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            throw WorkspaceRootStoreError.insufficientPermissions
        }

        stopAccessingCurrentDirectory()
        activeURL = url
        isAccessingSecurityScope = didStartAccessing

        return WorkspaceLocation(url: url, storageKind: storageKind(for: url))
    }

    private func persistBookmark(for url: URL) throws {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(bookmarkData, forKey: Self.bookmarkKey)
        } catch {
            throw WorkspaceRootStoreError.bookmarkCreationFailed
        }
    }

    private func stopAccessingCurrentDirectory() {
        guard isAccessingSecurityScope, let activeURL else {
            return
        }
        activeURL.stopAccessingSecurityScopedResource()
        isAccessingSecurityScope = false
    }

    private func storageKind(for url: URL) -> WorkspaceStorageKind {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        if values?.isUbiquitousItem == true || url.path.contains("/Mobile Documents/") {
            return .iCloud
        }
        return .local
    }

    deinit {
        if isAccessingSecurityScope, let activeURL {
            activeURL.stopAccessingSecurityScopedResource()
        }
    }
}
