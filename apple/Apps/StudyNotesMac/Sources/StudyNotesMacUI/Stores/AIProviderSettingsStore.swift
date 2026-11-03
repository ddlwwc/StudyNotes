import Foundation
import StudyNotesKit

enum AIProviderSettingsStore {
    private static let defaultsKey = "studynotes.ai.providerProfiles.v1"

    static func load() -> [AIProviderProfile] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let profiles = try? JSONDecoder().decode([AIProviderProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    static func save(_ profiles: [AIProviderProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
