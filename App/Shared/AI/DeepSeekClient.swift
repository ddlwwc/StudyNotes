import Foundation
import StudyCore

public struct DeepSeekConfig: Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-chat"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }
}

public enum DeepSeekError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String)
    case decoding(String)
    case emptyCards(bodyLength: Int)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "还没有配置 DeepSeek API Key"
        case .invalidResponse:
            return "服务端返回了无法解析的响应"
        case .httpStatus(let code, let body):
            return "请求失败（HTTP \(code)）：\(body.prefix(200))"
        case .decoding(let detail):
            return "解析响应失败：\(detail)"
        case .emptyCards(let length):
            if length < 60 {
                return "笔记正文只有 \(length) 字，太短了，模型没有可提取的知识点。多写几句再试。"
            }
            return "模型认为这篇笔记没有可提取的知识点（正文 \(length) 字）。试试把结论、区别、步骤写得更明确些。"
        }
    }
}

public final class DeepSeekClient: LanguageModel, CardGrader, CardGenerator, ScenarioRunner, @unchecked Sendable {
    private let config: DeepSeekConfig
    private let session: URLSession

    public init(config: DeepSeekConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func complete(system: String, messages: [ChatMessage]) async throws -> String {
        guard !config.apiKey.isEmpty else { throw DeepSeekError.missingAPIKey }

        var payload: [[String: String]] = [["role": "system", "content": system]]
        payload.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })

        let body: [String: Any] = [
            "model": config.model,
            "messages": payload,
            "temperature": 0.3,
            "stream": false,
        ]

        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.httpStatus(http.statusCode, String(decoding: data, as: UTF8.self))
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw DeepSeekError.decoding("缺少 choices[0].message.content")
        }
        return content
    }

    public func grade(question: String, referenceAnswer: String, learnerAnswer: String) async throws -> GradeResult {
        let system = """
        你是严格的评分者。根据参考答案评价学习者的回答，只输出一行 JSON：
        {"grade": 1|2|3|4, "feedback": "简短点评"}

        grade 含义：
        1 = 完全答错或没答到要点
        2 = 部分正确但漏了关键内容
        3 = 正确但表述不够精确
        4 = 完全正确且完整
        """

        let user = """
        问题：\(question)

        参考答案：\(referenceAnswer)

        学习者回答：\(learnerAnswer)
        """

        let raw = try await complete(system: system, messages: [ChatMessage(role: "user", content: user)])
        let json = extractJSON(from: raw)
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawGrade = object["grade"] as? Int,
            let grade = Grade(rawValue: min(max(rawGrade, 1), 4))
        else {
            throw DeepSeekError.decoding("无法从模型输出中解析 grade：\(raw.prefix(120))")
        }
        let feedback = (object["feedback"] as? String) ?? ""
        return GradeResult(grade: grade, feedback: feedback)
    }

    public func generateCards(from note: Note) async throws -> [Card] {
        let system = """
        你是学习卡片生成器。把用户笔记拆成便于主动回忆的问答卡片。

        输出规则：只输出 JSON 数组，不要任何解释、不要代码围栏。
        格式：[{"q": "问题", "a": "答案"}]

        提取原则：
        - 笔记里的每个定义、结论、区别、步骤、易错点，都应该成为一张卡片
        - 只要笔记有实质内容，至少生成 3 张卡片
        - 宁可多拆几张，也不要漏掉知识点
        - 问题必须能独立成立，读者不看原文也能明白在问什么
        - 答案 1-3 句，抓住要点，不要抄整段原文

        只有以下情况才返回空数组 []：
        笔记没有正文，或正文只有标题、没有可提取的信息。
        """

        let bodyText = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cards = ModelOutput.parseCards(from: try await requestRaw(system: system, body: bodyText),
                                              sourceNotePath: note.id) {
            return cards
        }

        let retry = system + "\n\n注意：上一次你没有给出任何卡片。这次必须至少提取 3 张。"
        if let cards = ModelOutput.parseCards(from: try await requestRaw(system: retry, body: bodyText),
                                              sourceNotePath: note.id) {
            return cards
        }

        throw DeepSeekError.emptyCards(bodyLength: bodyText.count)
    }

    private func requestRaw(system: String, body: String) async throws -> String {
        try await complete(
            system: system,
            messages: [ChatMessage(role: "user", content: body)]
        )
    }

    public func nextTutorTurn(scenario: Scenario, session: Session) async throws -> String {
        let history = session.turns.map {
            ChatMessage(
                role: $0.speaker == .learner ? "user" : "assistant",
                content: $0.text
            )
        }
        let messages = history.isEmpty
            ? [ChatMessage(role: "user", content: "开始吧。")]
            : history
        return try await complete(system: scenario.systemPrompt, messages: messages)
    }

    func extractJSON(from raw: String) -> String {
        ModelOutput.extractJSON(from: raw)
    }
}
