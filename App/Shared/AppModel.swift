import Foundation
import StudyCore
import Observation

@MainActor
@Observable
public final class AppModel {
    public var vaultURL: URL?
    public var needsVaultSelection = true
    public var startupError: String?

    public let notes = NoteStore()
    public let annotations = AnnotationStore()
    public let reviews = ReviewStore()
    public let scenario = ScenarioStore()
    public let settings = SettingsStore()
    public let player = SpeechPlayer()

    private let bookmarks = BookmarkStore()
    private var vault: Vault?

    public init() {}

    public var hasVault: Bool {
        vaultURL != nil
    }

    public var client: DeepSeekClient? {
        settings.makeClient()
    }

    public func restoreVault() {
        do {
            guard let (url, isStale) = try bookmarks.load() else {
                needsVaultSelection = true
                return
            }
            if isStale {
                needsVaultSelection = true
                startupError = VaultError.bookmarkStale.errorDescription
                return
            }
            try openVault(at: url, persist: false)
        } catch {
            needsVaultSelection = true
            startupError = error.localizedDescription
        }
    }

    public func selectVault(_ url: URL) {
        do {
            try openVault(at: url, persist: true)
            needsVaultSelection = false
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func openVault(at url: URL, persist: Bool) throws {
        vault?.close()
        let opened = try Vault.open(root: url)
        vault = opened
        vaultURL = opened.root
        notes.attach(opened)
        annotations.attach(directory: opened.annotationsURL)
        reviews.attach(opened)
        scenario.attach(opened)
        if persist {
            try bookmarks.save(url)
        }
    }

    public func changeVault() {
        needsVaultSelection = true
    }

    public func closeVault() {
        vault?.close()
        vault = nil
        vaultURL = nil
        notes.detach()
        annotations.attach(directory: nil)
        needsVaultSelection = true
    }
}
