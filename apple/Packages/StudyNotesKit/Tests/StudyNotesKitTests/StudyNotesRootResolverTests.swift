import Foundation
import Testing
@testable import StudyNotesKit

@Suite("StudyNotes root resolution")
struct StudyNotesRootResolverTests {
    @Test("signed-out iCloud resolution reports an explicit unavailable state")
    func signedOutICloudIsExplicit() {
        let resolver = StudyNotesRootResolver(
            preferredStorage: .iCloud,
            localRootURL: URL(filePath: "/tmp/local-study-notes"),
            iCloudContainerURL: nil,
            isICloudSignedIn: false
        )

        #expect(resolver.resolve() == .iCloudNotSignedIn)
    }

    @Test("signed-in resolution distinguishes a missing container")
    func missingICloudContainerIsExplicit() {
        let resolver = StudyNotesRootResolver(
            preferredStorage: .iCloud,
            localRootURL: URL(filePath: "/tmp/local-study-notes"),
            iCloudContainerURL: nil,
            isICloudSignedIn: true
        )

        #expect(resolver.resolve() == .iCloudContainerUnavailable)
    }

    @Test("local preference uses the injected local root")
    func localPreferenceUsesLocalRoot() {
        let localRootURL = URL(filePath: "/tmp/local-study-notes")
        let resolver = StudyNotesRootResolver(
            preferredStorage: .local,
            localRootURL: localRootURL,
            iCloudContainerURL: URL(filePath: "/tmp/icloud-study-notes"),
            isICloudSignedIn: false
        )

        #expect(resolver.resolve() == .available(.local(localRootURL)))
    }

    @Test("available iCloud container is returned explicitly")
    func availableICloudContainerIsReturned() {
        let iCloudRootURL = URL(filePath: "/tmp/icloud-study-notes")
        let resolver = StudyNotesRootResolver(
            preferredStorage: .iCloud,
            localRootURL: URL(filePath: "/tmp/local-study-notes"),
            iCloudContainerURL: iCloudRootURL,
            isICloudSignedIn: true
        )

        #expect(resolver.resolve() == .available(.iCloud(iCloudRootURL)))
    }

    @Test("store exposes and enforces injected unavailable root status")
    func storeUsesInjectedRootProvider() async {
        let provider = FixedStudyNotesRootProvider(status: .iCloudNotSignedIn)
        let store = StudyNotesStore(rootProvider: provider)

        #expect(await store.rootStatus() == .iCloudNotSignedIn)

        do {
            _ = try await store.loadIndex()
            Issue.record("Expected loadIndex to throw for an unavailable root")
        } catch let error as StudyNotesStorageUnavailableError {
            #expect(error.reason == .iCloudNotSignedIn)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
