import Foundation

public struct Card: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var question: String
    public var answer: String
    public var sourceNotePath: String?

    public init(id: String, question: String, answer: String, sourceNotePath: String? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.sourceNotePath = sourceNotePath
    }
}

public struct Note: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var tags: [String]
    public var body: String
    public var cards: [Card]

    public init(id: String, title: String, tags: [String] = [], body: String = "", cards: [Card] = []) {
        self.id = id
        self.title = title
        self.tags = tags
        self.body = body
        self.cards = cards
    }
}
