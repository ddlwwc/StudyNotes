import Foundation
import Observation

public struct MarkdownEditorSnapshot: Equatable, Sendable {
    public let materialID: UUID
    public let title: String
    public let markdown: String
    public let fingerprint: String
    public let compatibilityBlocks: [MarkdownCompatibilityBlock]
    public let isLocked: Bool
    public let blocks: [EditorDocumentBlockEnvelope]

    public init(
        materialID: UUID,
        title: String,
        markdown: String,
        fingerprint: String,
        compatibilityBlocks: [MarkdownCompatibilityBlock],
        isLocked: Bool = false,
        blocks: [EditorDocumentBlockEnvelope] = []
    ) {
        self.materialID = materialID
        self.title = title
        self.markdown = markdown
        self.fingerprint = fingerprint
        self.compatibilityBlocks = compatibilityBlocks
        self.isLocked = isLocked
        self.blocks = blocks
    }
}

public struct MarkdownEditorSaveRequest: Equatable, Sendable {
    public let materialID: UUID
    public let title: String
    public let markdown: String
    public let blocks: [EditorDocumentBlockEnvelope]
    public let expectedFingerprint: String
    public let createRecoveryVersion: Bool

    public init(
        materialID: UUID,
        title: String,
        markdown: String,
        blocks: [EditorDocumentBlockEnvelope] = [],
        expectedFingerprint: String,
        createRecoveryVersion: Bool
    ) {
        self.materialID = materialID
        self.title = title
        self.markdown = markdown
        self.blocks = blocks
        self.expectedFingerprint = expectedFingerprint
        self.createRecoveryVersion = createRecoveryVersion
    }
}

public enum MarkdownEditorSaveResult: Equatable, Sendable {
    case saved(title: String, markdown: String, fingerprint: String)
    case conflict(currentFingerprint: String)
    case failed(reason: String)
}

public enum MarkdownEditorTitleConflict: Equatable, Sendable {
    case manifestAndHeading(
        manifestTitle: String,
        headingTitle: String
    )
}

public enum MarkdownEditorActionDecision: Equatable, Sendable {
    case allowed
    case blocked(reason: String)
}

public typealias MarkdownEditorSaveHandler =
    @MainActor @Sendable (MarkdownEditorSaveRequest) async
        -> MarkdownEditorSaveResult

public typealias MarkdownEditorLockHandler =
    @MainActor @Sendable () async -> MarkdownEditorActionDecision

@MainActor
@Observable
public final class MarkdownEditorSession {
    public let materialID: UUID
    public private(set) var title: String
    public private(set) var markdown: String
    public private(set) var compatibilityBlocks: [MarkdownCompatibilityBlock]
    public private(set) var blocks: [EditorDocumentBlockEnvelope]
    public private(set) var saveState: MarkdownSaveState
    public private(set) var titleConflict: MarkdownEditorTitleConflict?
    public private(set) var errorMessage: String?
    public private(set) var isSourceMode = false
    public private(set) var isLocked: Bool
    public private(set) var mode: MarkdownEditorMode
    public private(set) var selection: MarkdownEditorSelection?
    public private(set) var annotations: [MaterialAnnotation] = []
    public private(set) var activeAnnotationID: UUID?
    public private(set) var unresolvedAnnotationIDs: Set<UUID> = []
    public private(set) var annotationLayoutPositions: [UUID: CGFloat] = [:]
    public private(set) var lockErrorMessage: String?

    @ObservationIgnored private let saveHandler: MarkdownEditorSaveHandler
    @ObservationIgnored private let lockHandler: MarkdownEditorLockHandler?
    @ObservationIgnored private let codec: MarkdownEditorCodec
    @ObservationIgnored private let titleSync: MarkdownTitleSync
    @ObservationIgnored private let policy = MarkdownSavePolicy()
    @ObservationIgnored private weak var host: (any MarkdownEditorHosting)?
    @ObservationIgnored private var expectedFingerprint: String
    @ObservationIgnored private var conflictFingerprint: String?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var contentChangeTask: Task<Void, Never>?
    @ObservationIgnored private var contentChangeGeneration = 0
    @ObservationIgnored private var didBecomeReady = false

    public var onAttachmentRequested:
        ((MarkdownEditorAttachmentKind) -> Void)?
    public var onSelectionChanged: ((MarkdownEditorSelection?) -> Void)?
    public var onAnnotationRequested: ((MarkdownEditorSelection) -> Void)?
    public var onAnnotationClicked: ((UUID) -> Void)?
    public var onAnnotationLayoutChanged: (([UUID: CGFloat]) -> Void)?
    public var onPrepareLock: MarkdownEditorLockHandler?

    public init(
        snapshot: MarkdownEditorSnapshot,
        codec: MarkdownEditorCodec = MarkdownEditorCodec(),
        saveHandler: @escaping MarkdownEditorSaveHandler,
        lockHandler: MarkdownEditorLockHandler? = nil
    ) {
        materialID = snapshot.materialID
        title = snapshot.title
        markdown = snapshot.markdown
        compatibilityBlocks = snapshot.compatibilityBlocks
        blocks = snapshot.blocks
        expectedFingerprint = snapshot.fingerprint
        saveState = MarkdownSaveState()
        self.codec = codec
        titleSync = MarkdownTitleSync(codec: codec)
        self.saveHandler = saveHandler
        self.lockHandler = lockHandler
        isLocked = snapshot.isLocked
        mode = snapshot.isLocked ? .annotate : .edit
    }

    public var isSaving: Bool {
        saveState.status == .saving
    }

    public var hasUnsavedChanges: Bool {
        saveState.hasUnsavedChanges || saveState.status == .saving
    }

    public var statusLabel: String {
        switch saveState.status {
        case .saved:
            "已保存"
        case .pendingChanges:
            "有未保存更改"
        case .saving:
            "正在保存"
        case .failed:
            "保存失败"
        case .conflict:
            "存在冲突"
        }
    }

    public func attach(_ host: any MarkdownEditorHosting) {
        self.host = host
        if didBecomeReady {
            sendDocumentRuntime()
        }
    }

    public func receive(_ message: MarkdownEditorBridgeMessage) {
        switch message {
        case .ready:
            didBecomeReady = true
            sendDocumentRuntime()
        case let .loadDocument(
            markdown,
            title,
            compatibilityBlocks,
            blocks
        ):
            self.markdown = markdown
            self.title = title
            self.compatibilityBlocks = compatibilityBlocks
            self.blocks = blocks
        case let .blockInsertRequested(block, anchorText):
            insertBlock(block, afterText: anchorText)
        case let .blockUpdateRequested(block):
            updateBlock(block)
        case let .blockRemoveRequested(blockID):
            removeBlock(id: blockID)
        case let .markdownChanged(markdown):
            self.markdown = markdown
            scheduleContentChanged()
        case let .titleChanged(title):
            self.title = title
            scheduleContentChanged()
        case let .sourceChanged(markdown):
            self.markdown = markdown
            if let decoded = try? codec.decode(markdown) {
                compatibilityBlocks = decoded.compatibilityBlocks
            }
            scheduleContentChanged()
        case let .sourceModeChanged(enabled):
            isSourceMode = enabled
            if !enabled {
                sendLoadedDocument()
            }
        case .command(.save), .saveRequested:
            Task { await requestExplicitSave() }
        case .command(.undo), .command(.redo),
             .command(.focusTitle), .command(.enterSourceMode),
             .command(.exitSourceMode):
            break
        case let .attachRequested(kind):
            onAttachmentRequested?(kind)
        case .documentRuntimeChanged:
            break
        case .annotationsChanged:
            break
        case .activeAnnotationChanged:
            break
        case let .selectionChanged(selection):
            self.selection = selection
            onSelectionChanged?(selection)
        case let .annotationRequested(selection):
            self.selection = selection
            if mode == .annotate, selection.hasTarget {
                onAnnotationRequested?(selection)
            }
        case let .annotationClicked(annotationID):
            activeAnnotationID = annotationID
            onAnnotationClicked?(annotationID)
        case let .unresolvedAnnotationIDsChanged(annotationIDs):
            unresolvedAnnotationIDs = Set(annotationIDs)
        case let .annotationLayoutChanged(positions):
            let converted = positions.reduce(into: [UUID: CGFloat]()) {
                result, entry in
                guard let id = UUID(uuidString: entry.key) else {
                    return
                }
                result[id] = CGFloat(entry.value)
            }
            annotationLayoutPositions = converted
            onAnnotationLayoutChanged?(converted)
        case let .failed(reason):
            errorMessage = reason
            Task { await reduce(.saveFailed(reason: reason)) }
        }
    }

    public func flush(_ reason: MarkdownFlushReason) async {
        await settleEditorInput()
        await reduce(.immediateFlush(reason))
    }

    public func requestExplicitSave() async {
        await settleEditorInput()
        await reduce(.explicitSave)
    }

    public func endEditing() async {
        await settleEditorInput()
        await reduce(.endEditing)
    }

    @discardableResult
    public func setMode(
        _ newMode: MarkdownEditorMode
    ) -> MarkdownEditorActionDecision {
        if isLocked, newMode == .edit {
            return .blocked(reason: "文档已锁定，只能继续标注。")
        }
        guard mode != newMode else {
            return .allowed
        }
        mode = newMode
        sendRuntimeState()
        return .allowed
    }

    @discardableResult
    public func requestAnnotation() -> MarkdownEditorActionDecision {
        guard mode == .annotate else {
            return .blocked(reason: "请先切换到标注模式。")
        }
        guard let selection, selection.hasTarget else {
            return .blocked(reason: "请先选择要标注的正文或块。")
        }
        onAnnotationRequested?(selection)
        return .allowed
    }

    @discardableResult
    public func lock() async -> MarkdownEditorActionDecision {
        guard !isLocked else {
            return .allowed
        }
        let previousMode = mode
        lockErrorMessage = nil
        await endEditing()
        await waitForActiveSave()
        if let message = lockBlockingMessage {
            lockErrorMessage = message
            errorMessage = message
            return .blocked(reason: message)
        }
        if let lockHandler = lockHandler ?? onPrepareLock {
            let decision = await lockHandler()
            if case let .blocked(reason) = decision {
                lockErrorMessage = reason
                mode = previousMode
                sendRuntimeState()
                return decision
            }
        }
        isLocked = true
        mode = .annotate
        errorMessage = nil
        lockErrorMessage = nil
        sendRuntimeState()
        return .allowed
    }

    public func updateAnnotations(_ annotations: [MaterialAnnotation]) {
        self.annotations = annotations
        if let activeAnnotationID,
           !annotations.contains(where: { $0.id == activeAnnotationID }) {
            self.activeAnnotationID = nil
        }
        sendAnnotations()
        sendActiveAnnotation()
    }

    public func selectAnnotation(_ id: UUID?) {
        guard activeAnnotationID != id else {
            return
        }
        activeAnnotationID = id
        sendActiveAnnotation()
    }

    public func editorRuntimeDidLoad() {
        sendRuntimeState()
        sendAnnotations()
        sendActiveAnnotation()
    }

    public func prepareForAction(
        _ action: MarkdownEditorAction
    ) async -> MarkdownEditorActionDecision {
        if saveState.status == .saving {
            await waitForActiveSave()
        }
        if case .conflict = saveState.status {
            return .blocked(reason: "请先处理当前编辑冲突。")
        }
        if case let .failed(reason) = saveState.status {
            return .blocked(reason: reason)
        }

        let effects = policy.reduce(
            state: &saveState,
            event: .actionRequested(action)
        )
        for effect in effects {
            switch effect {
            case .allow:
                return .allowed
            case let .block(_, reason):
                return .blocked(reason: blockMessage(reason))
            case .waitForSave:
                await reduce(.debounceElapsed)
                await waitForActiveSave()
                if case .saved = saveState.status {
                    return .allowed
                }
                if case .conflict = saveState.status {
                    return .blocked(reason: "请先处理当前编辑冲突。")
                }
                if case let .failed(reason) = saveState.status {
                    return .blocked(reason: reason)
                }
                return .blocked(reason: "当前编辑内容尚未保存。")
            case .saveNow, .scheduleAutosave, .cancelAutosave:
                break
            }
        }
        return .blocked(reason: "当前编辑内容尚未保存。")
    }

    public func resolveTitleConflict(
        usingManifestTitle: Bool
    ) async {
        guard let titleConflict else {
            return
        }
        switch titleConflict {
        case let .manifestAndHeading(manifestTitle, headingTitle):
            self.titleConflict = nil
            if usingManifestTitle {
                do {
                    markdown = try titleSync.applying(
                        title: manifestTitle,
                        to: markdown
                    )
                    compatibilityBlocks = try codec.decode(
                        markdown
                    ).compatibilityBlocks
                    sendLoadedDocument()
                } catch {
                    errorMessage = error.localizedDescription
                    await reduce(.saveFailed(
                        reason: error.localizedDescription
                    ))
                    return
                }
            } else {
                title = headingTitle
                send(.titleChanged(headingTitle))
            }
            saveState = MarkdownSaveState(
                status: .pendingChanges,
                hasUnsavedChanges: true
            )
            await requestExplicitSave()
        }
    }

    public func replaceSnapshot(_ snapshot: MarkdownEditorSnapshot) {
        title = snapshot.title
        markdown = snapshot.markdown
        compatibilityBlocks = snapshot.compatibilityBlocks
        blocks = snapshot.blocks
        expectedFingerprint = snapshot.fingerprint
        isLocked = snapshot.isLocked
        mode = snapshot.isLocked ? .annotate : .edit
        selection = nil
        annotations = []
        activeAnnotationID = nil
        unresolvedAnnotationIDs = []
        annotationLayoutPositions = [:]
        lockErrorMessage = nil
        conflictFingerprint = nil
        titleConflict = nil
        errorMessage = nil
        saveState = MarkdownSaveState()
        sendDocumentRuntime()
    }

    public func overrideConflictAndSave() async {
        guard let conflictFingerprint else {
            return
        }
        expectedFingerprint = conflictFingerprint
        self.conflictFingerprint = nil
        saveState = MarkdownSaveState(
            status: .pendingChanges,
            hasUnsavedChanges: true
        )
        await requestExplicitSave()
    }

    public func sendCommand(_ command: MarkdownEditorCommand) {
        send(.command(command))
    }

    public func insertMediaReference(
        _ reference: NoteMediaReference,
        kind: MarkdownEditorAttachmentKind,
        label: String = ""
    ) {
        let normalizedLabel = label
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let markdownSyntax: String
        switch kind {
        case .image:
            markdownSyntax = "![\(normalizedLabel.isEmpty ? "图片" : normalizedLabel)](\(reference.stringValue))"
        case .file:
            markdownSyntax = "[\(normalizedLabel.isEmpty ? "附件" : normalizedLabel)](\(reference.stringValue))"
        case .audio:
            markdownSyntax = """
            <audio controls src="\(reference.stringValue)" aria-label="\(normalizedLabel.isEmpty ? "音频" : normalizedLabel)"></audio>
            """
        case .video:
            markdownSyntax = """
            <video controls src="\(reference.stringValue)" aria-label="\(normalizedLabel.isEmpty ? "视频" : normalizedLabel)"></video>
            """
        }
        if !markdown.isEmpty, !markdown.hasSuffix("\n") {
            markdown += "\n"
        }
        if !markdown.isEmpty, !markdown.hasSuffix("\n\n") {
            markdown += "\n"
        }
        markdown += markdownSyntax
        sendLoadedDocument()
        Task { await reduce(.contentChanged) }
    }

    public func insertBlock(
        _ block: EditorDocumentBlockEnvelope,
        afterText anchorText: String? = nil
    ) {
        do {
            try block.validate()
            guard !blocks.contains(where: { $0.id == block.id }) else {
                throw EditorBlockError.duplicateBlockID(block.id)
            }
            blocks.append(block)
            insertMarkdown(
                Self.markdown(for: block),
                afterText: anchorText
            )
            sendLoadedDocument()
            Task { await reduce(.contentChanged) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateBlock(_ block: EditorDocumentBlockEnvelope) {
        guard let index = blocks.firstIndex(where: { $0.id == block.id })
        else {
            errorMessage = "没有找到要更新的复杂块。"
            return
        }
        do {
            try block.validate()
            let previous = blocks[index]
            blocks[index] = block
            if let range = markdown.range(
                of: Self.markdown(for: previous),
                options: [.literal]
            ) {
                markdown.replaceSubrange(range, with: Self.markdown(for: block))
            }
            sendLoadedDocument()
            Task { await reduce(.contentChanged) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func removeBlock(id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id })
        else {
            return
        }
        let block = blocks.remove(at: index)
        if let range = markdown.range(
            of: Self.markdown(for: block),
            options: [.literal]
        ) {
            markdown.removeSubrange(range)
            normalizeBlockSpacing()
        }
        sendLoadedDocument()
        Task { await reduce(.contentChanged) }
    }

    public static func markdown(
        for block: EditorDocumentBlockEnvelope
    ) -> String {
        """
        <!-- studynotes:block id="\(block.id.uuidString)" type="\(block.type)" version="\(block.version)" -->
        \(block.fallback)
        <!-- /studynotes:block -->
        """
    }

    private func appendToMarkdown(_ value: String) {
        if !markdown.isEmpty, !markdown.hasSuffix("\n") {
            markdown += "\n"
        }
        if !markdown.isEmpty, !markdown.hasSuffix("\n\n") {
            markdown += "\n"
        }
        markdown += value
        if !markdown.hasSuffix("\n") {
            markdown += "\n"
        }
    }

    private func insertMarkdown(
        _ value: String,
        afterText anchorText: String?
    ) {
        let normalizedAnchor = anchorText?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let normalizedAnchor, !normalizedAnchor.isEmpty,
           let anchorRange = markdown.range(of: normalizedAnchor) {
            let insertionPoint = paragraphEnd(after: anchorRange.upperBound)
            let separator = insertionPoint == markdown.endIndex ? "\n\n" : "\n"
            markdown.insert(contentsOf: separator + value, at: insertionPoint)
            return
        }
        appendToMarkdown(value)
    }

    private func paragraphEnd(after start: String.Index) -> String.Index {
        if let boundary = markdown[start...].range(of: "\n\n")?.lowerBound {
            return boundary
        }
        return markdown.endIndex
    }

    private func normalizeBlockSpacing() {
        while markdown.contains("\n\n\n") {
            markdown = markdown.replacingOccurrences(
                of: "\n\n\n",
                with: "\n\n"
            )
        }
    }

    private func reduce(_ event: MarkdownSaveEvent) async {
        let effects = policy.reduce(state: &saveState, event: event)
        for effect in effects {
            switch effect {
            case let .scheduleAutosave(milliseconds):
                scheduleAutosave(after: milliseconds)
            case .cancelAutosave:
                autosaveTask?.cancel()
                autosaveTask = nil
            case let .saveNow(createRecoveryVersion):
                await performSave(
                    createRecoveryVersion: createRecoveryVersion
                )
            case .block:
                break
            case .waitForSave, .allow:
                break
            }
        }
    }

    private func scheduleContentChanged() {
        contentChangeGeneration += 1
        let generation = contentChangeGeneration
        let previous = contentChangeTask
        contentChangeTask = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard let self, generation == self.contentChangeGeneration else {
                return
            }
            await self.reduce(.contentChanged)
        }
    }

    private func settleEditorInput() async {
        if isSourceMode {
            send(.command(.exitSourceMode))
            for _ in 0..<50 where isSourceMode {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        while true {
            let generation = contentChangeGeneration
            if let task = contentChangeTask {
                await task.value
            }
            if generation == contentChangeGeneration {
                contentChangeTask = nil
                return
            }
        }
    }

    private func scheduleAutosave(after milliseconds: Int) {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(
                for: .milliseconds(milliseconds)
            )
            guard !Task.isCancelled else {
                return
            }
            await self?.reduce(.debounceElapsed)
        }
    }

    private func performSave(createRecoveryVersion: Bool) async {
        let requestedMarkdown = markdown
        let requestedTitle = title
        let prepared: MarkdownEditorPreparedSave
        do {
            prepared = try MarkdownEditorSavePreparation(
                codec: codec,
                titleSync: titleSync
            ).prepare(
                manifestTitle: requestedTitle,
                markdown: requestedMarkdown,
                compatibilityBlocks: compatibilityBlocks
            )
        } catch {
            errorMessage = error.localizedDescription
            await reduce(.saveFailed(reason: error.localizedDescription))
            return
        }

        switch prepared {
        case let .titleConfirmation(manifestTitle, headingTitle):
            titleConflict = .manifestAndHeading(
                manifestTitle: manifestTitle,
                headingTitle: headingTitle
            )
            errorMessage = "清单标题与正文首个一级标题不一致，请选择保留哪一个。"
            await reduce(.conflictDetected)
            return
        case let .ready(title, markdown):
            let outcome = await saveHandler(
                MarkdownEditorSaveRequest(
                    materialID: materialID,
                    title: title,
                    markdown: markdown,
                    blocks: blocks,
                    expectedFingerprint: expectedFingerprint,
                    createRecoveryVersion: createRecoveryVersion
                )
            )
            switch outcome {
            case let .saved(savedTitle, savedMarkdown, fingerprint):
                expectedFingerprint = fingerprint
                conflictFingerprint = nil
                errorMessage = nil
                if self.markdown == requestedMarkdown {
                    self.markdown = savedMarkdown
                }
                if self.title == requestedTitle {
                    self.title = savedTitle
                }
                if let decoded = try? codec.decode(self.markdown) {
                    compatibilityBlocks = decoded.compatibilityBlocks
                }
                await reduce(.saveSucceeded)
                sendAnnotations()
            case let .conflict(currentFingerprint):
                conflictFingerprint = currentFingerprint
                errorMessage = "文件已被其他设备或工具修改，当前编辑内容未覆盖磁盘。"
                await reduce(.conflictDetected)
            case let .failed(reason):
                errorMessage = reason
                await reduce(.saveFailed(reason: reason))
            }
        }
    }

    private func sendLoadedDocument() {
        guard didBecomeReady else {
            return
        }
        send(
            .loadDocument(
                markdown: markdown,
                title: title,
                compatibilityBlocks: compatibilityBlocks,
                blocks: blocks
            )
        )
    }

    private func sendDocumentRuntime() {
        sendLoadedDocument()
        sendRuntimeState()
        sendAnnotations()
        sendActiveAnnotation()
    }

    private func sendRuntimeState() {
        send(
            .documentRuntimeChanged(
                isLocked: isLocked,
                mode: mode
            )
        )
    }

    private func sendAnnotations() {
        send(
            .annotationsChanged(
                annotations.map {
                    MarkdownEditorAnnotationPayload(annotation: $0)
                }
            )
        )
    }

    private func sendActiveAnnotation() {
        send(.activeAnnotationChanged(activeAnnotationID))
    }

    private func send(_ message: MarkdownEditorBridgeMessage) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await host?.send(message)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func blockMessage(
        _ reason: MarkdownActionBlockReason
    ) -> String {
        switch reason {
        case .saveFailed:
            "请先解决保存失败，再继续当前操作。"
        case .saveConflict:
            "请先处理编辑冲突，再继续当前操作。"
        case let .pendingUploads(count):
            "还有 \(count) 个媒体文件正在等待上传或失败。"
        }
    }

    private func waitForActiveSave() async {
        for _ in 0..<250 {
            guard saveState.status == .saving else {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private var lockBlockingMessage: String? {
        if let titleConflict {
            switch titleConflict {
            case let .manifestAndHeading(manifestTitle, headingTitle):
                return "标题尚未确认：清单为“\(manifestTitle)”，正文为“\(headingTitle)”。"
            }
        }
        switch saveState.status {
        case .saved:
            return nil
        case let .failed(reason):
            return reason
        case .conflict:
            return "存在编辑冲突，请先选择保留的版本。"
        case .pendingChanges:
            return "正文尚未保存，已阻止锁定。"
        case .saving:
            return "正文仍在保存，请稍后重试。"
        }
    }
}

public enum MarkdownEditorPreparedSave: Equatable, Sendable {
    case ready(title: String, markdown: String)
    case titleConfirmation(
        manifestTitle: String,
        headingTitle: String
    )
}

public struct MarkdownEditorSavePreparation: Sendable {
    private let codec: MarkdownEditorCodec
    private let titleSync: MarkdownTitleSync

    public init(
        codec: MarkdownEditorCodec = MarkdownEditorCodec(),
        titleSync: MarkdownTitleSync? = nil
    ) {
        self.codec = codec
        self.titleSync = titleSync ?? MarkdownTitleSync(codec: codec)
    }

    public func prepare(
        manifestTitle: String,
        markdown: String,
        compatibilityBlocks: [MarkdownCompatibilityBlock]
    ) throws -> MarkdownEditorPreparedSave {
        let normalized = try codec.decode(markdown).markdown
        let safeMarkdown = try codec.encode(
            MarkdownEditorDocument(
                markdown: normalized,
                compatibilityBlocks: compatibilityBlocks
            )
        )
        switch try titleSync.plan(
            manifestTitle: manifestTitle,
            markdown: safeMarkdown
        ) {
        case let .synchronized(title, markdown):
            return .ready(title: title, markdown: markdown)
        case let .confirmation(manifestTitle, headingTitle):
            return .titleConfirmation(
                manifestTitle: manifestTitle,
                headingTitle: headingTitle
            )
        }
    }
}
