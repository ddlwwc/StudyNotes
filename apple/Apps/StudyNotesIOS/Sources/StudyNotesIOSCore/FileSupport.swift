import Foundation
import enum StudyNotesKit.CrossPlatformJSON

public enum StudyNotesFileSupport {
    public static let iCloudContainerIdentifier = "iCloud.com.studynotes.app"
    public static let appGroupIdentifier = "group.com.studynotes.app"

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let baseURL: URL
        if let sharedURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            baseURL = sharedURL
        } else {
            baseURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let directory = baseURL.appending(
            path: "StudyNotes",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public static func resolveRoot(
        fileManager: FileManager = .default,
        allowLocalFallback: Bool
    ) -> IOSRootState {
        if ProcessInfo.processInfo.environment["STUDYNOTES_FORCE_LOCAL"] == "1" {
            return fallbackRoot(fileManager: fileManager)
        }
        guard fileManager.ubiquityIdentityToken != nil else {
            return allowLocalFallback ? fallbackRoot(fileManager: fileManager) : .iCloudNotSignedIn
        }
        guard let containerURL = fileManager.url(
            forUbiquityContainerIdentifier: iCloudContainerIdentifier
        ) else {
            return allowLocalFallback ? fallbackRoot(fileManager: fileManager) : .iCloudContainerUnavailable
        }
        let documentsURL = containerURL.appending(
            path: "Documents",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.createDirectory(
                at: documentsURL,
                withIntermediateDirectories: true
            )
            return .available(documentsURL, isICloud: true)
        } catch {
            return allowLocalFallback ? fallbackRoot(fileManager: fileManager) : .iCloudContainerUnavailable
        }
    }

    public static func fallbackRoot(
        fileManager: FileManager = .default
    ) -> IOSRootState {
        guard let baseURL = try? applicationSupportDirectory(fileManager: fileManager) else {
            return .iCloudContainerUnavailable
        }
        let rootURL = baseURL.appending(
            path: "LocalWorkspace",
            directoryHint: .isDirectory
        )
        try? fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        return .localFallback(rootURL)
    }

    public static func coordinatedRead<T>(
        at url: URL,
        coordinator: NSFileCoordinator = NSFileCoordinator(filePresenter: nil),
        _ body: () throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { _ in
            result = Result { try body() }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw StudyNotesIOSError.unreadableContent
        }
        return try result.get()
    }

    public static func coordinatedWrite<T>(
        at url: URL,
        coordinator: NSFileCoordinator = NSFileCoordinator(filePresenter: nil),
        _ body: () throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { _ in
            result = Result { try body() }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw StudyNotesIOSError.unreadableContent
        }
        return try result.get()
    }

    public static func writeAtomically(
        _ data: Data,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try coordinatedWrite(at: destinationURL) {
            let temporaryURL = directoryURL.appending(
                path: ".tmp-\(UUID().uuidString)"
            )
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    public static func encoder() -> JSONEncoder {
        CrossPlatformJSON.encoder()
    }

    public static func decoder() -> JSONDecoder {
        CrossPlatformJSON.decoder()
    }
}
