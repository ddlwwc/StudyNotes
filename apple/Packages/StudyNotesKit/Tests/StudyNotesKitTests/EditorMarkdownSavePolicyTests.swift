import Testing
@testable import StudyNotesKit

@Suite("Markdown save policy")
struct MarkdownSavePolicyTests {
    @Test("edits debounce for 800 milliseconds and lifecycle events flush now")
    func saveTiming() {
        let policy = MarkdownSavePolicy()
        var state = MarkdownSaveState()

        #expect(MarkdownSavePolicy.debounceMilliseconds == 800)
        #expect(
            policy.reduce(state: &state, event: .contentChanged)
                == [.scheduleAutosave(afterMilliseconds: 800)]
        )
        #expect(state.hasUnsavedChanges)

        for event in [
            MarkdownSaveEvent.immediateFlush(.materialSwitch),
            .immediateFlush(.windowBlur),
            .immediateFlush(.appBackground)
        ] {
            var dirtyState = MarkdownSaveState(hasUnsavedChanges: true)
            #expect(
                policy.reduce(state: &dirtyState, event: event)
                    == [
                        .cancelAutosave,
                        .saveNow(createRecoveryVersion: false)
                    ]
            )
            #expect(!dirtyState.hasUnsavedChanges)
        }
    }

    @Test("explicit save, end editing, and AI rewrite create one recovery version")
    func versions() {
        let policy = MarkdownSavePolicy()
        var state = MarkdownSaveState()

        for _ in 0..<3 {
            _ = policy.reduce(state: &state, event: .contentChanged)
        }
        #expect(
            policy.reduce(state: &state, event: .debounceElapsed)
                == [.saveNow(createRecoveryVersion: false)]
        )
        _ = policy.reduce(state: &state, event: .saveSucceeded)

        #expect(
            policy.reduce(state: &state, event: .explicitSave)
                == [.saveNow(createRecoveryVersion: true)]
        )
        _ = policy.reduce(state: &state, event: .saveSucceeded)
        #expect(
            policy.reduce(state: &state, event: .endEditing)
                == [.saveNow(createRecoveryVersion: true)]
        )
        _ = policy.reduce(state: &state, event: .saveSucceeded)
        #expect(
            policy.reduce(state: &state, event: .aiRewrite)
                == [.saveNow(createRecoveryVersion: true)]
        )
    }

    @Test("edits made during a save schedule a follow-up instead of being lost")
    func editsDuringSave() {
        let policy = MarkdownSavePolicy()
        var state = MarkdownSaveState()

        _ = policy.reduce(state: &state, event: .contentChanged)
        #expect(
            policy.reduce(state: &state, event: .debounceElapsed)
                == [.saveNow(createRecoveryVersion: false)]
        )
        #expect(
            policy.reduce(state: &state, event: .contentChanged)
                == [.cancelAutosave]
        )
        #expect(state.hasUnsavedChanges)

        #expect(
            policy.reduce(state: &state, event: .saveSucceeded)
                == [.saveNow(createRecoveryVersion: false)]
        )
        #expect(state.status == .saving)
    }

    @Test("a recovery save requested during saving runs after the active save")
    func recoverySaveDuringSave() {
        let policy = MarkdownSavePolicy()
        var state = MarkdownSaveState(status: .saving)

        #expect(
            policy.reduce(state: &state, event: .explicitSave)
                == [.cancelAutosave]
        )
        #expect(
            policy.reduce(state: &state, event: .saveSucceeded)
                == [.saveNow(createRecoveryVersion: true)]
        )
    }

    @Test("failed saves, conflicts, and pending uploads block dependent actions")
    func actionBarrier() {
        let policy = MarkdownSavePolicy()
        let actions: [MarkdownEditorAction] = [
            .aiSummarize,
            .aiExplain,
            .publishPreview,
            .export,
            .versions
        ]
        var failedState = MarkdownSaveState(
            status: .failed(reason: "磁盘不可写"),
            hasUnsavedChanges: true
        )

        for action in actions {
            #expect(
                policy.reduce(
                    state: &failedState,
                    event: .actionRequested(action)
                ) == [.block(action, reason: .saveFailed)]
            )
        }

        var pendingUploadState = MarkdownSaveState(pendingUploadCount: 2)
        #expect(
            policy.reduce(
                state: &pendingUploadState,
                event: .actionRequested(.publishPreview)
            ) == [.block(.publishPreview, reason: .pendingUploads(2))]
        )
        for action in actions where action != .publishPreview {
            #expect(
                policy.reduce(
                    state: &pendingUploadState,
                    event: .actionRequested(action)
                ) == [.allow(action)]
            )
        }

        var dirtyState = MarkdownSaveState(hasUnsavedChanges: true)
        #expect(
            policy.reduce(
                state: &dirtyState,
                event: .actionRequested(.publishPreview)
            ) == [.waitForSave(.publishPreview)]
        )

        var savedState = MarkdownSaveState()
        #expect(
            policy.reduce(
                state: &savedState,
                event: .actionRequested(.export)
            ) == [.allow(.export)]
        )

        var conflictState = MarkdownSaveState()
        _ = policy.reduce(state: &conflictState, event: .conflictDetected)
        #expect(
            policy.reduce(
                state: &conflictState,
                event: .actionRequested(.versions)
            ) == [.block(.versions, reason: .saveConflict)]
        )
    }
}
