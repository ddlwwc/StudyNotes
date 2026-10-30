import Foundation

public struct Deck: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var tags: [String]
    public var cardIDs: Set<String>

    public init(id: String, name: String, tags: [String] = [], cardIDs: Set<String> = []) {
        self.id = id
        self.name = name
        self.tags = tags
        self.cardIDs = cardIDs
    }

    public func matches(_ note: Note) -> Bool {
        if !note.cards.contains(where: { cardIDs.contains($0.id) }) {
            let noteTags = Set(note.tags)
            guard !tags.isEmpty, !noteTags.isDisjoint(with: tags) else { return false }
        }
        return true
    }

    public func resolve(from notes: [Note]) -> [Card] {
        notes.flatMap(\.cards).filter { card in
            if cardIDs.contains(card.id) { return true }
            guard !tags.isEmpty else { return false }
            guard let source = notes.first(where: { $0.id == card.sourceNotePath }) else { return false }
            return !Set(source.tags).isDisjoint(with: tags)
        }
    }
}
