import Foundation
import StudyNotesKit

struct MediaTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(
                path: "StudyNotesMediaTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

final class MediaLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}

final class MediaMemorySecretStore:
    SecretStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(_ secret: String, account: String) throws {
        lock.lock()
        values[account] = secret
        lock.unlock()
    }

    func load(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func delete(account: String) throws {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }
}
