import Foundation
import StudyNotesKit
import Testing
@testable import StudyNotesMacUI

@Suite("Mac workspace and settings seams")
@MainActor
struct WorkspaceModelTests {
    @Test("pane collapse, resize, reset, and relaunch restore are device-local")
    func panePreferencesPersist() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)

        model.togglePane(.library)
        model.setPaneWidth(.library, width: 10_000)
        model.setPaneWidth(.materials, width: 1)
        model.setPaneWidth(.study, width: 300)

        #expect(!model.isLibraryPaneVisible)
        #expect(model.libraryPaneWidth == 320)
        #expect(model.materialPaneWidth == 240)
        #expect(model.studyPaneWidth == 300)

        model.restoreDefaultWidth(.study)
        let relaunched = makeModel(defaults: defaults)
        #expect(!relaunched.isLibraryPaneVisible)
        #expect(relaunched.libraryPaneWidth == 320)
        #expect(relaunched.materialPaneWidth == 240)
        #expect(relaunched.studyPaneWidth == WorkspacePreferences.defaultStudyWidth)
    }

    @Test("reading preferences clamp and survive relaunch")
    func readingPreferencesPersist() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        model.readingPreferences = ReadingPreferences(
            theme: .dark,
            fontSize: 100,
            lineWidth: 1,
            lineHeight: 9,
            codeFont: "   "
        )

        let relaunched = makeModel(defaults: defaults)
        #expect(relaunched.readingPreferences.theme == .dark)
        #expect(relaunched.readingPreferences.fontSize == 24)
        #expect(relaunched.readingPreferences.lineWidth == 420)
        #expect(relaunched.readingPreferences.lineHeight == 2.2)
        #expect(relaunched.readingPreferences.codeFont == "SFMono-Regular")
    }

    @Test("publishing defaults are unlisted with private annotations and AI")
    func publishingDefaults() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)

        #expect(model.appSettings.defaultPublishVisibility == .unlisted)
        #expect(!model.appSettings.publishAnnotationsByDefault)
        #expect(!model.appSettings.publishAIByDefault)

        model.updateAppSettings {
            $0.defaultPublishVisibility = .publicArticle
            $0.publishAnnotationsByDefault = true
            $0.publishAIByDefault = true
        }
        #expect(model.appSettings.defaultPublishVisibility == .publicArticle)
        #expect(model.appSettings.publishAnnotationsByDefault)
        #expect(model.appSettings.publishAIByDefault)
    }

    @Test("publishing panel starts from the stored default visibility")
    func publishingPanelUsesStoredDefault() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settingsStore = AppSettingsStore(userDefaults: defaults)

        let unlisted = PublishingPanelModel(
            credentialStore: MemoryPublishingCredentialStore(),
            settingsStore: settingsStore
        )
        #expect(unlisted.visibility == .unlisted)
        unlisted.visibility = .publicArticle
        #expect(settingsStore.load().defaultPublishVisibility == .unlisted)

        try? settingsStore.update {
            $0.defaultPublishVisibility = .publicArticle
        }
        let publicArticle = PublishingPanelModel(
            credentialStore: MemoryPublishingCredentialStore(),
            settingsStore: settingsStore
        )
        #expect(publicArticle.visibility == .publicArticle)
    }

    @Test("connection tester reports success, failure, and HTTP risk")
    func connectionTester() async {
        let success = ServiceConnectionTester { request in
            #expect(request.url?.path == "/api/v1/health")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"ok":true}"#.utf8), response)
        }
        let successResult = await success.test(
            .publishing,
            serverURLText: "http://127.0.0.1:8090"
        )
        #expect(successResult.usesHTTP)
        #expect(
            successResult.status
                == .succeeded("服务可达。")
        )

        let failure = ServiceConnectionTester { _ in
            throw URLError(.cannotConnectToHost)
        }
        let failureResult = await failure.test(
            .publishing,
            serverURLText: "https://example.com"
        )
        guard case .failed = failureResult.status else {
            Issue.record("Expected a failed connection status")
            return
        }
        #expect(!failureResult.usesHTTP)
    }

    @Test("note media key is stored only through the injected secret store")
    func mediaKeyUsesSecretStore() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = MemorySecretStore()
        let model = makeModel(defaults: defaults, mediaSecretStore: secrets)

        #expect(!model.hasNoteMediaKey)
        #expect(model.saveNoteMediaKey(" bearer-secret-0123456789abcdefghijklmn "))
        #expect(model.hasNoteMediaKey)
        #expect(
            model.noteMediaKeyForConnectionTest()
                == "bearer-secret-0123456789abcdefghijklmn"
        )
        #expect(defaults.data(forKey: "StudyNotes.AppSettings.v1") == nil)
    }

    @Test("drop rules reject folder cycles and allow cross-library material moves")
    func dropRules() {
        let knowledgeBaseID = UUID()
        let folder = WorkspaceDragPayload(
            kind: .folder,
            knowledgeBaseID: knowledgeBaseID,
            folderPath: "A"
        )
        let items = WorkspaceDragPayload(
            kind: .materials,
            knowledgeBaseID: knowledgeBaseID,
            materialIDs: [UUID()]
        )

        #expect(!WorkspaceDropRules.allows(
            folder,
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "A")
        ))
        #expect(!WorkspaceDropRules.allows(
            folder,
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "A/B")
        ))
        #expect(WorkspaceDropRules.allows(
            folder,
            on: .knowledgeBaseRoot(knowledgeBaseID)
        ))
        #expect(WorkspaceDropRules.allows(
            items,
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "B")
        ))
        #expect(WorkspaceDropRules.allows(
            items,
            on: .knowledgeBaseRoot(UUID())
        ))
        #expect(!WorkspaceDropRules.allows(
            WorkspaceDragPayload(kind: .materials, knowledgeBaseID: knowledgeBaseID),
            on: .knowledgeBaseRoot(knowledgeBaseID)
        ))
        #expect(WorkspaceDropRules.allows(
            WorkspaceDragPayload(
                kind: .materials,
                knowledgeBaseID: nil,
                materialIDs: [UUID()]
            ),
            on: .folder(knowledgeBaseID: knowledgeBaseID, path: "B")
        ))
    }

    @Test("settings center exposes the five canonical pages")
    func settingsPages() {
        #expect(WorkspaceSettingsPage.allCases.count == 5)
        #expect(WorkspaceSettingsPage.allCases.map(\.title) == [
            "学习目录",
            "AI 配置",
            "发布配置",
            "密钥与凭据",
            "阅读偏好"
        ])
    }

    private func makeModel(
        defaults: UserDefaults,
        mediaSecretStore: any SecretStoring = MemorySecretStore()
    ) -> WorkspaceModel {
        WorkspaceModel(
            secretStore: MemorySecretStore(),
            mediaSecretStore: mediaSecretStore,
            devicePreferences: DevicePreferencesStore(userDefaults: defaults),
            appSettingsStore: AppSettingsStore(userDefaults: defaults)
        )
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "StudyNotesMacUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}

private final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(_ secret: String, account: String) throws {
        lock.withLock {
            values[account] = secret
        }
    }

    func load(account: String) throws -> String? {
        lock.withLock {
            values[account]
        }
    }

    func delete(account: String) throws {
        lock.withLock {
            _ = values.removeValue(forKey: account)
        }
    }
}

private final class MemoryPublishingCredentialStore:
    PublishingCredentialStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private var credential: PublishingCredential?

    func load() throws -> PublishingCredential? {
        lock.withLock { credential }
    }

    func save(_ credential: PublishingCredential) throws {
        lock.withLock {
            self.credential = credential
        }
    }

    func delete() throws {
        lock.withLock {
            credential = nil
        }
    }
}
