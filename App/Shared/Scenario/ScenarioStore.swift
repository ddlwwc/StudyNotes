import Foundation
import StudyCore
import Observation

@MainActor
@Observable
public final class ScenarioStore {
    public private(set) var sessions: [Session] = []
    public private(set) var lastError: String?

    private var vault: Vault?

    public init() {}

    public func attach(_ vault: Vault) {
        self.vault = vault
    }

    public func detach() {
        vault = nil
    }

    public func sessionURL(for session: Session) -> URL? {
        guard let vault else { return nil }
        let stamp = Self.formatter.string(from: session.startedAt)
        return vault.sessionsURL.appendingPathComponent("\(stamp)-\(session.scenarioID).md")
    }

    public func save(_ session: Session) throws {
        guard let url = sessionURL(for: session) else { throw VaultError.noVaultSelected }
        let markdown = render(session)
        try FileIO.write(markdown, to: url)
    }

    public func render(_ session: Session) -> String {
        let name = BuiltinScenarios.all.first { $0.id == session.scenarioID }?.name ?? session.scenarioID
        let stamp = Self.formatter.string(from: session.startedAt)

        var lines: [String] = [
            "---",
            "tags: [session, \(session.scenarioID)]",
            "---",
            "# \(name) — \(stamp)",
            "",
        ]
        for turn in session.turns {
            let speaker = turn.speaker == .learner ? "我" : "对方"
            let channel = turn.channel == .voice ? "（语音）" : ""
            lines.append("**\(speaker)**\(channel)：\(turn.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

@MainActor
@Observable
public final class ScenarioRuntime {
    public private(set) var session: Session
    public private(set) var isThinking = false
    public var errorMessage: String?

    private let runner: ScenarioRunner?
    private let scenario: Scenario

    public init(scenario: Scenario, runner: ScenarioRunner?) {
        self.scenario = scenario
        self.runner = runner
        self.session = Session(scenarioID: scenario.id)
    }

    public func start() async {
        guard session.turns.isEmpty else { return }
        await advance()
    }

    public func submit(_ text: String, channel: ChannelKind = .text) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.append(Turn(speaker: .learner, text: trimmed, channel: channel))
        await advance()
    }

    public func advance() async {
        guard let runner else {
            errorMessage = "还没有配置 API Key"
            return
        }
        isThinking = true
        defer { isThinking = false }
        do {
            let reply = try await runner.nextTutorTurn(scenario: scenario, session: session)
            session.append(Turn(speaker: .tutor, text: reply, channel: .text))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
