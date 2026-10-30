import Foundation

public enum ChannelKind: String, Codable, Sendable {
    case text
    case voice
}

public enum Speaker: String, Codable, Sendable {
    case learner
    case tutor
}

public struct Turn: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var speaker: Speaker
    public var text: String
    public var channel: ChannelKind
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        channel: ChannelKind,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.channel = channel
        self.timestamp = timestamp
    }
}

public struct Session: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var scenarioID: String
    public var startedAt: Date
    public var turns: [Turn]

    public init(
        id: UUID = UUID(),
        scenarioID: String,
        startedAt: Date = Date(),
        turns: [Turn] = []
    ) {
        self.id = id
        self.scenarioID = scenarioID
        self.startedAt = startedAt
        self.turns = turns
    }

    public var transcript: String {
        turns.map { turn in
            let name = turn.speaker == .learner ? "我" : "对方"
            return "**\(name)**：\(turn.text)"
        }.joined(separator: "\n\n")
    }

    public mutating func append(_ turn: Turn) {
        turns.append(turn)
    }
}
