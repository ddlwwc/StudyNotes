import Foundation

@MainActor
public final class BookmarkStore {
    private let defaultsKey = "vault.bookmark"

    public init() {}

    public func save(_ url: URL) throws {
        #if os(macOS)
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let data = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    public func load() throws -> (url: URL, isStale: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
        return (url, isStale)
    }

    public func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
