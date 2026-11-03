import Foundation
import Observation
import StudyNotesIOSCore

struct AIRequestDraft: Sendable {
    let action: String
    let context: AIContext
    let prompt: String
}

@MainActor
@Observable
final class ReaderSessionModel {
    let document: MaterialDocument
    var annotations: [StudyAnnotation] = []
    var conversations: [AIConversation] = []
    var providers: [AIProvider]
    var selectedTextAnchor: TextAnchor?
    var focusBlockPath: String?
    var providerID: UUID?
    var activeConversation: AIConversation?
    var streamingText = ""
    var streamError: String?
    var isStreaming = false
    var lastRequest: AIRequestDraft?
    var noticeMessage: String?
    var errorMessage: String?

    @ObservationIgnored private let libraryStore: IOSLibraryStore
    @ObservationIgnored private let providerStore: AIProviderStore
    @ObservationIgnored private let client = OpenAICompatibleClient()
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    init(
        document: MaterialDocument,
        libraryStore: IOSLibraryStore,
        providerStore: AIProviderStore,
        providers: [AIProvider],
        selectedProviderID: UUID?
    ) async throws {
        self.document = document
        self.libraryStore = libraryStore
        self.providerStore = providerStore
        self.providers = providers
        self.providerID = selectedProviderID ?? providers.first?.id
        try await reload()
    }

    var selectedProvider: AIProvider? {
        providers.first { $0.id == providerID } ?? providers.first
    }

    var textHTML: String {
        MarkdownHTMLRenderer.render(
            source: document.sourceText ?? "",
            title: document.material.title,
            kind: document.material.kind
        )
    }

    var plainText: String {
        MarkdownHTMLRenderer.plainText(from: document.sourceText ?? "")
    }

    var wholeContext: AIContext {
        AIContext(
            action: "总结",
            text: plainText,
            scopeDescription: "整份材料"
        )
    }

    func selectedContext(
        action: String = "解释"
    ) -> AIContext? {
        guard let selectedTextAnchor else {
            return nil
        }
        return AIContext(
            action: action,
            text: selectedTextAnchor.quote,
            scopeDescription: "选中文字"
        )
    }

    func reload() async throws {
        annotations = try await libraryStore.loadAnnotations(
            materialID: document.material.id,
            sourceText: document.sourceText
        )
        conversations = try await libraryStore.loadConversations(
            materialID: document.material.id
        )
    }

    func saveTextAnnotation(
        anchor: TextAnchor,
        note: String
    ) async {
        let existing = annotations.first {
            TextAnchorResolver.anchorsAreEquivalent($0.anchor, .text(anchor))
        }
        let draft = StudyAnnotation(
            id: existing?.id ?? UUID(),
            materialID: document.material.id,
            anchor: .text(anchor),
            note: note.isEmpty ? (existing?.note ?? "") : note
        )
        do {
            let saved = try await libraryStore.saveAnnotation(
                draft,
                materialID: document.material.id,
                sourceText: document.sourceText
            )
            if let index = annotations.firstIndex(where: { $0.id == saved.id }) {
                annotations[index] = saved
            } else {
                annotations.append(saved)
            }
            annotations.sort { $0.createdAt < $1.createdAt }
            selectedTextAnchor = nil
            noticeMessage = note.isEmpty ? "已添加高亮" : "高亮与备注已保存"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveImageAnnotation(
        rectangle: NormalizedRectangle,
        note: String
    ) async {
        let existing = annotations.first {
            TextAnchorResolver.anchorsAreEquivalent(
                $0.anchor,
                .imageRectangle(rectangle)
            )
        }
        let draft = StudyAnnotation(
            id: existing?.id ?? UUID(),
            materialID: document.material.id,
            anchor: .imageRectangle(rectangle),
            note: note.isEmpty ? (existing?.note ?? "") : note
        )
        do {
            let saved = try await libraryStore.saveAnnotation(
                draft,
                materialID: document.material.id,
                sourceText: nil
            )
            if let index = annotations.firstIndex(where: { $0.id == saved.id }) {
                annotations[index] = saved
            } else {
                annotations.append(saved)
            }
            noticeMessage = note.isEmpty ? "已标注图片区域" : "图片区域标注已保存"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateAnnotationNote(
        _ annotation: StudyAnnotation,
        note: String
    ) async {
        var updated = annotation
        updated.note = note
        updated.updatedAt = Date()
        do {
            let saved = try await libraryStore.saveAnnotation(
                updated,
                materialID: document.material.id,
                sourceText: document.sourceText
            )
            if let index = annotations.firstIndex(where: { $0.id == saved.id }) {
                annotations[index] = saved
            }
            noticeMessage = "标注备注已更新"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAnnotation(_ annotation: StudyAnnotation) async {
        do {
            try await libraryStore.deleteAnnotation(
                id: annotation.id,
                materialID: document.material.id
            )
            annotations.removeAll { $0.id == annotation.id }
            noticeMessage = "标注已删除"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func jump(to annotation: StudyAnnotation) {
        guard case let .text(anchor) = annotation.anchor else {
            return
        }
        focusBlockPath = anchor.blockPath
    }

    func startAI(
        action: String,
        context: AIContext,
        prompt: String
    ) async {
        let request = AIRequestDraft(
            action: action,
            context: context,
            prompt: prompt
        )
        lastRequest = request
        await execute(request: request)
    }

    func retryAI() async {
        guard let lastRequest else {
            return
        }
        activeConversation = nil
        streamingText = ""
        await execute(request: lastRequest)
    }

    func stopAI() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        guard var conversation = activeConversation else {
            return
        }
        conversation.status = .stopped
        conversation.updatedAt = Date()
        activeConversation = conversation
        persistConversation()
    }

    func selectConversation(_ conversation: AIConversation) {
        activeConversation = conversation
        streamingText = conversation.messages.last(where: {
            $0.role == .assistant
        })?.content ?? ""
    }

    func hasAPIKey() async -> Bool {
        guard let provider = selectedProvider else {
            return false
        }
        return await providerStore.hasAPIKey(for: provider.id)
    }

    private func execute(request: AIRequestDraft) async {
        guard let provider = selectedProvider,
              provider.isConfigured else {
            streamError = StudyNotesIOSError.invalidProvider.localizedDescription
            return
        }
        let storedKey: String?
        do {
            storedKey = try await providerStore.apiKey(for: provider.id)
        } catch {
            streamError = error.localizedDescription
            return
        }
        guard let apiKey = storedKey, !apiKey.isEmpty else {
            streamError = StudyNotesIOSError.missingAPIKey.localizedDescription
            return
        }

        streamTask?.cancel()
        streamError = nil
        streamingText = ""
        isStreaming = true
        var conversation = activeConversation ?? AIConversation(
            materialID: document.material.id,
            providerName: provider.name,
            modelID: provider.modelID,
            action: request.action,
            scopeDescription: request.context.scopeDescription
        )
        conversation.status = .active
        conversation.updatedAt = Date()
        let userMessage = AIMessage(role: .user, content: request.prompt)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()
        let assistantID = UUID()
        conversation.messages.append(
            AIMessage(id: assistantID, role: .assistant, content: "")
        )
        activeConversation = conversation

        let priorMessages = Array(
            conversation.messages
                .filter {
                    $0.id != assistantID
                        && $0.id != userMessage.id
                        && !$0.content.isEmpty
                }
                .suffix(8)
        )
        let stream = client.stream(
            provider: provider,
            apiKey: apiKey,
            context: request.context,
            priorMessages: priorMessages,
            userPrompt: request.prompt
        )

        streamTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case let .delta(delta):
                        streamingText += delta
                        updateAssistant(
                            id: assistantID,
                            content: streamingText,
                            promptTokens: nil,
                            completionTokens: nil
                        )
                    case let .usage(promptTokens, completionTokens):
                        updateAssistant(
                            id: assistantID,
                            content: streamingText,
                            promptTokens: promptTokens,
                            completionTokens: completionTokens
                        )
                    case .completed:
                        break
                    }
                }
                finishStream(assistantID: assistantID, status: .completed)
            } catch is CancellationError {
                finishStream(assistantID: assistantID, status: .stopped)
            } catch {
                streamError = error.localizedDescription
                isStreaming = false
                if var conversation = activeConversation {
                    conversation.status = .failed
                    conversation.updatedAt = Date()
                    activeConversation = conversation
                }
                persistConversation()
            }
        }
    }

    private func updateAssistant(
        id: UUID,
        content: String,
        promptTokens: Int?,
        completionTokens: Int?
    ) {
        guard var conversation = activeConversation,
              let index = conversation.messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversation.messages[index].content = content
        if let promptTokens {
            conversation.messages[index].promptTokens = promptTokens
        }
        if let completionTokens {
            conversation.messages[index].completionTokens = completionTokens
        }
        conversation.updatedAt = Date()
        activeConversation = conversation
    }

    private func finishStream(
        assistantID: UUID,
        status: AIStudySessionStatus
    ) {
        guard var conversation = activeConversation else {
            isStreaming = false
            return
        }
        if let index = conversation.messages.firstIndex(where: { $0.id == assistantID }),
           conversation.messages[index].content.isEmpty {
            conversation.messages.remove(at: index)
        }
        conversation.status = status
        conversation.updatedAt = Date()
        activeConversation = conversation
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        isStreaming = false
        persistConversation()
    }

    private func persistConversation() {
        guard let conversation = activeConversation else {
            return
        }
        Task {
            try? await libraryStore.saveConversation(conversation)
        }
    }
}
