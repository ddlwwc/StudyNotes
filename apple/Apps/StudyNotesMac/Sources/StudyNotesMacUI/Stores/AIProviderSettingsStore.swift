import Foundation
import StudyNotesKit

struct AIProviderSettingsStore {
    private let defaultsKey = "studynotes.ai.providerProfiles.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [AIProviderProfile] {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let profiles = try? JSONDecoder().decode([AIProviderProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    func save(_ profiles: [AIProviderProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }
        userDefaults.set(data, forKey: defaultsKey)
    }
}
