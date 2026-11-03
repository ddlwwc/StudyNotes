import Foundation
import StudyNotesKit
import Testing

@Suite("Device preferences")
@MainActor
struct DevicePreferencesTests {
    @Test("reading preferences use readable device defaults")
    func readingPreferencesUseDefaults() {
        let preferences = ReadingPreferences()

        #expect(preferences.theme == .system)
        #expect(preferences.fontSize == 16)
        #expect(preferences.lineWidth == 648)
        #expect(preferences.lineHeight == 1.82)
        #expect(preferences.codeFont == "SFMono-Regular")
    }

    @Test("reading preferences clamp unsafe typography values")
    func readingPreferencesClampValues() {
        var preferences = ReadingPreferences(
            fontSize: 100,
            lineWidth: 10,
            lineHeight: 9,
            codeFont: "   "
        )

        #expect(preferences.fontSize == 24)
        #expect(preferences.lineWidth == 420)
        #expect(preferences.lineHeight == 2.2)
        #expect(preferences.codeFont == "SFMono-Regular")

        preferences.fontSize = -1
        preferences.lineWidth = 10_000
        preferences.lineHeight = 0

        #expect(preferences.fontSize == 12)
        #expect(preferences.lineWidth == 900)
        #expect(preferences.lineHeight == 1.4)
    }

    @Test("workspace widths clamp and restore without changing collapse state")
    func workspacePreferencesClampAndRestore() {
        var preferences = WorkspacePreferences(
            libraryWidth: 1,
            materialsWidth: 10_000,
            studyWidth: .nan,
            isLibraryCollapsed: true,
            isMaterialsCollapsed: false,
            isStudyCollapsed: true
        )

        #expect(preferences.libraryWidth == 160)
        #expect(preferences.materialsWidth == 480)
        #expect(preferences.studyWidth == 260)
        #expect(preferences.isLibraryCollapsed)
        #expect(!preferences.isMaterialsCollapsed)
        #expect(preferences.isStudyCollapsed)

        preferences.libraryWidth = 1_000
        preferences.materialsWidth = 0
        preferences.studyWidth = 100
        #expect(preferences.libraryWidth == 320)
        #expect(preferences.materialsWidth == 240)
        #expect(preferences.studyWidth == 220)

        preferences.restoreDefaultWidths()
        #expect(preferences.libraryWidth == 184)
        #expect(preferences.materialsWidth == 276)
        #expect(preferences.studyWidth == 260)
        #expect(preferences.isLibraryCollapsed)
        #expect(preferences.isStudyCollapsed)
    }

    @Test("codable values cannot bypass preference clamping")
    func codableValuesStayClamped() throws {
        let readingData = Data(
            """
            {
              "theme": "dark",
              "fontSize": 100,
              "lineWidth": 10,
              "lineHeight": 10,
              "codeFont": "  "
            }
            """.utf8
        )
        let workspaceData = Data(
            """
            {
              "libraryWidth": 1,
              "materialsWidth": 10000,
              "studyWidth": 1,
              "isLibraryCollapsed": true,
              "isMaterialsCollapsed": false,
              "isStudyCollapsed": true
            }
            """.utf8
        )

        let reading = try JSONDecoder().decode(
            ReadingPreferences.self,
            from: readingData
        )
        let workspace = try JSONDecoder().decode(
            WorkspacePreferences.self,
            from: workspaceData
        )

        #expect(reading.theme == .dark)
        #expect(reading.fontSize == 24)
        #expect(reading.lineWidth == 420)
        #expect(reading.lineHeight == 2.2)
        #expect(reading.codeFont == "SFMono-Regular")
        #expect(workspace.libraryWidth == 160)
        #expect(workspace.materialsWidth == 480)
        #expect(workspace.studyWidth == 220)
        #expect(workspace.isLibraryCollapsed)
        #expect(workspace.isStudyCollapsed)
    }

    @Test("device preferences round-trip through an injected local suite")
    func devicePreferencesRoundTrip() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DevicePreferencesStore(userDefaults: defaults)
        let reading = ReadingPreferences(
            theme: .dark,
            fontSize: 20,
            lineWidth: 700,
            lineHeight: 1.9,
            codeFont: "Menlo"
        )
        let workspace = WorkspacePreferences(
            libraryWidth: 220,
            materialsWidth: 360,
            studyWidth: 300,
            isLibraryCollapsed: true,
            isMaterialsCollapsed: false,
            isStudyCollapsed: true
        )

        try store.save(readingPreferences: reading)
        try store.save(workspacePreferences: workspace)

        let reloaded = DevicePreferencesStore(userDefaults: defaults)
        #expect(reloaded.loadReadingPreferences() == reading)
        #expect(reloaded.loadWorkspacePreferences() == workspace)
    }

    @Test("clear removes device preferences without clearing unrelated defaults")
    func clearRemovesDevicePreferences() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DevicePreferencesStore(userDefaults: defaults)
        defaults.set("keep", forKey: "StudyNotesKitTests.unrelated")
        try store.save(
            readingPreferences: ReadingPreferences(theme: .dark)
        )
        try store.save(
            workspacePreferences: WorkspacePreferences(
                isLibraryCollapsed: true
            )
        )

        store.clear()

        #expect(store.loadReadingPreferences() == ReadingPreferences())
        #expect(store.loadWorkspacePreferences() == WorkspacePreferences())
        #expect(
            defaults.string(forKey: "StudyNotesKitTests.unrelated") == "keep"
        )
    }

    @Test("separate suites keep per-device preferences isolated")
    func suitesAreIsolated() throws {
        let (firstDefaults, firstSuite) = makeIsolatedDefaults()
        let (secondDefaults, secondSuite) = makeIsolatedDefaults()
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        let firstStore = DevicePreferencesStore(userDefaults: firstDefaults)
        let secondStore = DevicePreferencesStore(userDefaults: secondDefaults)
        let firstReading = ReadingPreferences(theme: .light)
        let secondWorkspace = WorkspacePreferences(
            libraryWidth: 240,
            isMaterialsCollapsed: true
        )

        try firstStore.save(readingPreferences: firstReading)
        try secondStore.save(workspacePreferences: secondWorkspace)

        #expect(secondStore.loadReadingPreferences() == ReadingPreferences())
        #expect(firstStore.loadWorkspacePreferences() == WorkspacePreferences())
        #expect(firstStore.loadReadingPreferences() == firstReading)
        #expect(secondStore.loadWorkspacePreferences() == secondWorkspace)
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "StudyNotesKitTests.DevicePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
