import Foundation

public struct SSEUsage: Equatable, Sendable {
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(promptTokens: Int?, completionTokens: Int?) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public struct OpenAIChatMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OpenAIChatRequest: Codable, Equatable, Sendable {
    public let model: String
    public let messages: [OpenAIChatMessage]
    public let stream: Bool

    public init(
        model: String,
        messages: [OpenAIChatMessage],
        stream: Bool = true
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

public struct AIStreamParser: Sendable {
    private var usage: SSEUsage?

    public init() {}

    public mutating func consume(line: String) -> [AIStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else {
            return []
        }
        let payload = trimmed
            .dropFirst(5)
            .trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else {
            return []
        }
        if payload == "[DONE]" {
            var events: [AIStreamEvent] = []
            if let usage {
                events.append(
                    .usage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens
                    )
                )
            }
            events.append(.completed)
            return events
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var events: [AIStreamEvent] = []
        if let choices = object["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String,
           !content.isEmpty {
            events.append(.delta(content))
        }
        if let usageObject = object["usage"] as? [String: Any] {
            let prompt = usageObject["prompt_tokens"] as? Int
            let completion = usageObject["completion_tokens"] as? Int
            usage = SSEUsage(
                promptTokens: prompt,
                completionTokens: completion
            )
            events.append(
                .usage(promptTokens: prompt, completionTokens: completion)
            )
        }
        return events
    }
}

public final class OpenAICompatibleClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(
        provider: AIProvider,
        apiKey: String,
        context: AIContext,
        priorMessages: [AIMessage] = [],
        userPrompt: String
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(
                        provider: provider,
                        apiKey: apiKey,
                        context: context,
                        priorMessages: priorMessages,
                        userPrompt: userPrompt
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw StudyNotesIOSError.malformedStream
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw URLError(
                            .badServerResponse,
                            userInfo: [
                                NSLocalizedDescriptionKey: "AI 供应商返回 HTTP \(httpResponse.statusCode)。"
                            ]
                        )
                    }
                    var parser = AIStreamParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in parser.consume(line: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func endpoint(for provider: AIProvider) throws -> URL {
        guard let baseURL = URL(string: provider.baseURL) else {
            throw StudyNotesIOSError.invalidProvider
        }
        if baseURL.path.hasSuffix("/chat/completions") {
            return baseURL
        }
        if baseURL.path.hasSuffix("/v1") || baseURL.path.hasSuffix("/v1/") {
            return baseURL.appending(path: "chat/completions")
        }
        return baseURL
            .appending(path: "v1")
            .appending(path: "chat/completions")
    }

    private func makeRequest(
        provider: AIProvider,
        apiKey: String,
        context: AIContext,
        priorMessages: [AIMessage],
        userPrompt: String
    ) throws -> URLRequest {
        guard provider.isConfigured else {
            throw StudyNotesIOSError.invalidProvider
        }
        var request = URLRequest(url: try endpoint(for: provider))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [OpenAIChatMessage] = [
            OpenAIChatMessage(
                role: "system",
                content: "你是 StudyNotes 中围绕当前学习材料工作的研读助手。"
            ),
            OpenAIChatMessage(
                role: "system",
                content: "\(context.action)的上下文：\n\(context.text)"
            )
        ]
        messages.append(contentsOf: priorMessages.map {
            OpenAIChatMessage(role: $0.role.rawValue, content: $0.content)
        })
        messages.append(
            OpenAIChatMessage(role: "user", content: userPrompt)
        )
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatRequest(model: provider.modelID, messages: messages)
        )
        return request
    }
}
