public enum MarkdownSaveStatus: Equatable, Sendable {
    case saved
    case pendingChanges
    case saving
    case failed(reason: String)
    case conflict
}

public struct MarkdownSaveState: Equatable, Sendable {
    public var status: MarkdownSaveStatus
    public var hasUnsavedChanges: Bool
    public var pendingUploadCount: Int
    public internal(set) var pendingRecoveryVersion: Bool

    public init(
        status: MarkdownSaveStatus = .saved,
        hasUnsavedChanges: Bool = false,
        pendingUploadCount: Int = 0,
        pendingRecoveryVersion: Bool = false
    ) {
        self.status = status
        self.hasUnsavedChanges = hasUnsavedChanges
        self.pendingUploadCount = pendingUploadCount
        self.pendingRecoveryVersion = pendingRecoveryVersion
    }
}

public enum MarkdownFlushReason: String, Equatable, Sendable {
    case materialSwitch
    case windowBlur
    case appBackground
}

public enum MarkdownEditorAction: String, Equatable, Sendable {
    case aiSummarize
    case aiExplain
    case publishPreview
    case export
    case versions
}

public enum MarkdownSaveEvent: Equatable, Sendable {
    case contentChanged
    case debounceElapsed
    case immediateFlush(MarkdownFlushReason)
    case explicitSave
    case endEditing
    case aiRewrite
    case saveStarted
    case saveSucceeded
    case saveFailed(reason: String)
    case conflictDetected
    case pendingUploadsChanged(Int)
    case actionRequested(MarkdownEditorAction)
}

public enum MarkdownActionBlockReason: Equatable, Sendable {
    case saveFailed
    case saveConflict
    case pendingUploads(Int)
}

public enum MarkdownSaveEffect: Equatable, Sendable {
    case scheduleAutosave(afterMilliseconds: Int)
    case cancelAutosave
    case saveNow(createRecoveryVersion: Bool)
    case block(MarkdownEditorAction, reason: MarkdownActionBlockReason)
    case waitForSave(MarkdownEditorAction)
    case allow(MarkdownEditorAction)
}

public struct MarkdownSavePolicy: Sendable {
    public static let debounceMilliseconds = 800

    public init() {}

    public func reduce(
        state: inout MarkdownSaveState,
        event: MarkdownSaveEvent
    ) -> [MarkdownSaveEffect] {
        switch event {
        case .contentChanged:
            state.hasUnsavedChanges = true
            switch state.status {
            case .failed, .conflict:
                return [.cancelAutosave]
            case .saving:
                return [.cancelAutosave]
            case .saved, .pendingChanges:
                state.status = .pendingChanges
                return [
                    .scheduleAutosave(
                        afterMilliseconds: Self.debounceMilliseconds
                    )
                ]
            }

        case .debounceElapsed:
            guard state.hasUnsavedChanges else {
                return []
            }
            switch state.status {
            case .failed, .conflict, .saving:
                return []
            case .saved, .pendingChanges:
                break
            }
            state.status = .saving
            state.hasUnsavedChanges = false
            return [.saveNow(createRecoveryVersion: false)]

        case .immediateFlush:
            guard state.hasUnsavedChanges,
                  state.status != .conflict else {
                return []
            }
            if state.status == .saving {
                return [.cancelAutosave]
            }
            state.status = .saving
            state.hasUnsavedChanges = false
            state.pendingRecoveryVersion = false
            return [
                .cancelAutosave,
                .saveNow(createRecoveryVersion: false)
            ]

        case .explicitSave, .endEditing, .aiRewrite:
            if state.status == .saving {
                state.pendingRecoveryVersion = true
                return [.cancelAutosave]
            }
            state.status = .saving
            state.hasUnsavedChanges = false
            state.pendingRecoveryVersion = false
            return [.saveNow(createRecoveryVersion: true)]

        case .saveStarted:
            state.status = .saving
            return []

        case .saveSucceeded:
            if state.hasUnsavedChanges || state.pendingRecoveryVersion {
                let createRecoveryVersion = state.pendingRecoveryVersion
                state.status = .saving
                state.hasUnsavedChanges = false
                state.pendingRecoveryVersion = false
                return [
                    .saveNow(
                        createRecoveryVersion: createRecoveryVersion
                    )
                ]
            }
            state.status = .saved
            state.hasUnsavedChanges = false
            state.pendingRecoveryVersion = false
            return []

        case .saveFailed(let reason):
            state.status = .failed(reason: reason)
            state.hasUnsavedChanges = true
            state.pendingRecoveryVersion = false
            return []

        case .conflictDetected:
            state.status = .conflict
            state.hasUnsavedChanges = true
            state.pendingRecoveryVersion = false
            return []

        case .pendingUploadsChanged(let count):
            state.pendingUploadCount = max(0, count)
            return []

        case .actionRequested(let action):
            let blockReason: MarkdownActionBlockReason? = switch state.status {
            case .failed:
                .saveFailed
            case .conflict:
                .saveConflict
            case .saved, .pendingChanges, .saving:
                nil
            }
            let pendingMediaBlocksAction =
                action == .publishPreview && state.pendingUploadCount > 0
            if let blockReason {
                return [.block(action, reason: blockReason)]
            }
            if pendingMediaBlocksAction {
                return [
                    .block(
                        action,
                        reason: .pendingUploads(state.pendingUploadCount)
                    )
                ]
            }
            if state.hasUnsavedChanges || state.status != .saved {
                return [.waitForSave(action)]
            }
            return [.allow(action)]
        }
    }
}
