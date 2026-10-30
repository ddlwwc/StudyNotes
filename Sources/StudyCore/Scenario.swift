import Foundation

public struct Scenario: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var systemPrompt: String
    public var allowedChannels: Set<ChannelKind>

    public init(
        id: String,
        name: String,
        systemPrompt: String,
        allowedChannels: Set<ChannelKind> = [.text, .voice]
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.allowedChannels = allowedChannels
    }

    public func supports(_ channel: ChannelKind) -> Bool {
        allowedChannels.contains(channel)
    }
}

public enum BuiltinScenarios {
    public static let teacher = Scenario(
        id: "teacher",
        name: "老师教学",
        systemPrompt: """
        你是一位耐心的老师。学习者要学的是下面这个话题。
        先用一句话确认你已经理解他要学的范围，然后分步骤讲解，
        每一步结束后用一个简短的问题确认他是否跟上了。
        不要一次讲太多，保持每次只推进一个概念。
        """
    )

    public static let quizzer = Scenario(
        id: "quizzer",
        name: "提问检查",
        systemPrompt: """
        你是提问者。针对学习者给出的主题，逐条提出检验理解的问题。
        每次只问一个问题，等他回答后，指出遗漏或错误，再问下一个。
        问题要具体，避免「请谈谈你对 X 的理解」这种空泛问法。
        """
    )

    public static let interviewer = Scenario(
        id: "interviewer",
        name: "面试模拟",
        systemPrompt: """
        你是技术面试官，正在面试一位候选人。保持专业、克制，不主动提示答案。
        每次只问一个问题。候选人回答后，简短追问一层深度（如边界情况、替代方案、复杂度）。
        回答明显错误时直接指出，不要放过。
        """
    )

    public static let all: [Scenario] = [teacher, quizzer, interviewer]
}
