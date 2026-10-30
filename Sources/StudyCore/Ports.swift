import Foundation

public protocol SpeechSynthesizer: Sendable {
    func speak(_ text: String) async throws
    func stop() async
}

public protocol LanguageModel: Sendable {
    func complete(system: String, messages: [ChatMessage]) async throws -> String
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public protocol CardGrader: Sendable {
    func grade(question: String, referenceAnswer: String, learnerAnswer: String) async throws -> GradeResult
}

public struct GradeResult: Equatable, Sendable {
    public var grade: Grade
    public var feedback: String

    public init(grade: Grade, feedback: String) {
        self.grade = grade
        self.feedback = feedback
    }
}

public protocol CardGenerator: Sendable {
    func generateCards(from note: Note) async throws -> [Card]
}

public protocol ScenarioRunner: Sendable {
    func nextTutorTurn(scenario: Scenario, session: Session) async throws -> String
}
