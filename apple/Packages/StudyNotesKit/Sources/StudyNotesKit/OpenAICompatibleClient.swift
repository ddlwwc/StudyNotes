import Foundation

public enum AIStreamEvent: Equatable, Sendable {
    case delta(String)
    case completed
}

public struct OpenAICompatibleClient: Sendable {
    public typealias ByteStream = @Sendable (URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse)

    private let streamTransport: ByteStream

    public init(
        streamTransport: @escaping ByteStream = { request in
            try await URLSession.shared.bytes(for: request)
        }
    ) {
        self.streamTransport = streamTransport
    }

    public func stream(
        profile: AIProviderProfile,
        apiKey: String,
        messages: [AIMessage]
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(
                        profile: profile,
                        apiKey: apiKey,
                        messages: messages
                    )
                    let (bytes, response) = try await streamTransport(request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIStreamError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var detail = ""
                        for try await line in bytes.lines {
                            detail += line
                            if detail.count >= 1_000 {
                                break
                            }
                        }
                        throw AIStreamError.httpStatus(
                            httpResponse.statusCode,
                            detail.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if let event = SSEParser.event(from: line) {
                            continuation.yield(event)
                            if event == .completed {
                                break
                            }
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

    private func makeRequest(
        profile: AIProviderProfile,
        apiKey: String,
        messages: [AIMessage]
    ) throws -> URLRequest {
        let endpoint = profile.baseURL
            .appending(path: "chat")
            .appending(path: "completions")
        guard endpoint.scheme == "http" || endpoint.scheme == "https" else {
            throw AIStreamError.invalidEndpoint
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let payload = ChatRequest(
            model: profile.model,
            messages: messages.map { ChatMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }
}

public enum SSEParser {
    public static func event(from line: String) -> AIStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else {
            return nil
        }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .completed
        }
        guard let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(StreamEnvelope.self, from: data),
              let delta = envelope.choices.first?.delta.content,
              !delta.isEmpty else {
            return nil
        }
        return .delta(delta)
    }
}

public enum AIStreamError: Error, Equatable, Sendable, LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int, String)
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "AI 供应商基础地址无效。"
        case .invalidResponse:
            "AI 供应商返回了无法识别的响应。"
        case .httpStatus(let status, let detail):
            detail.isEmpty
                ? "AI 请求失败（HTTP \(status)）。"
                : "AI 请求失败（HTTP \(status)）：\(detail)"
        case .missingAPIKey:
            "请先在 AI 供应商设置中保存 API Key。"
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct StreamEnvelope: Decodable {
    let choices: [StreamChoice]
}

private struct StreamChoice: Decodable {
    let delta: StreamDelta
}

private struct StreamDelta: Decodable {
    let content: String?
}
