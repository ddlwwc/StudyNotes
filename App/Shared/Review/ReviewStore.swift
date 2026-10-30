import Foundation
import StudyCore
import Observation

@MainActor
@Observable
public final class ReviewStore {
    public private(set) var states: [String: CardReviewState] = [:]
    public private(set) var lastError: String?

    private var vault: Vault?
    private let fsrs = FSRS()

    public init() {}

    public var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "device.id") {
            return existing
        }
        let generated = UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(String(generated), forKey: "device.id")
        return String(generated)
    }

    private var shardURL: URL? {
        vault?.stateURL.appendingPathComponent("\(deviceID).json")
    }

    public func attach(_ vault: Vault) {
        self.vault = vault
        reload()
    }

    public func detach() {
        vault = nil
    }

    public func reload() {
        guard let vault else { return }
        do {
            let all = try FileManager.default.contentsOfDirectory(
                at: vault.stateURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let shards: [ReviewState] = all
                .filter { $0.pathExtension.lowercased() == "json" }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder.study.decode(ReviewState.self, from: data)
                }
            states = ReviewStateMerge.merge(shards)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func dueCards(from cards: [Card], at now: Date = Date()) -> [Card] {
        var byID: [String: Card] = [:]
        for card in cards where byID[card.id] == nil {
            byID[card.id] = card
        }
        return ReviewStateMerge
            .dueCardIDs(from: states, at: now)
            .compactMap { byID[$0] }
    }

    public func newCards(from cards: [Card]) -> [Card] {
        cards.filter { states[$0.id] == nil }
    }

    public func record(card: Card, grade: Grade, at now: Date = Date()) throws {
        guard let url = shardURL else { throw VaultError.noVaultSelected }

        let existing = states[card.id]
        let nextSchedulerState: SchedulerState
        if let existing {
            nextSchedulerState = fsrs.next(state: existing.state, grade: grade, now: now)
        } else {
            nextSchedulerState = fsrs.initialState(grade: grade, now: now)
        }

        let entry = CardReviewState(state: nextSchedulerState, lastGrade: grade)

        var shard = ReviewState(deviceID: deviceID)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.study.decode(ReviewState.self, from: data) {
            shard = decoded
        }
        shard.cards[card.id] = entry

        let data = try JSONEncoder.study.encode(shard)
        try data.write(to: url, options: .atomic)

        states[card.id] = entry
    }

    public func isNew(_ card: Card) -> Bool {
        states[card.id] == nil
    }
}
