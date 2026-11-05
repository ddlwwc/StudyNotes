import Foundation
import Testing
@testable import StudyNotesKit

@MainActor
@Suite("Markdown editor session")
struct MarkdownEditorSessionTests {
    @Test("title changes stop at confirmation before invoking the save handler")
    func titleConfirmation() async {
        let saveCounter = SaveCounter()
        let session = MarkdownEditorSession(
            snapshot: snapshot(
                title: "清单标题",
                markdown: "# 正文标题\n\n正文"
            )
        ) { request in
            _ = await saveCounter.increment()
            return .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }

        await session.requestExplicitSave()

        #expect(
            session.titleConflict == .manifestAndHeading(
                manifestTitle: "清单标题",
                headingTitle: "正文标题"
            )
        )
        #expect(await saveCounter.value == 0)
        #expect(session.markdown == "# 正文标题\n\n正文")

        await session.resolveTitleConflict(usingManifestTitle: true)

        #expect(await saveCounter.value == 1)
        #expect(session.markdown == "# 清单标题\n\n正文")
        #expect(session.saveState.status == .saved)
    }

    @Test("conflicts retain the edit and block dependent actions")
    func conflictBarrier() async {
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n本地正文")
        ) { _ in
            .conflict(currentFingerprint: "sha256:external")
        }
        session.receive(.markdownChanged("# 标题\n\n我的新正文"))

        await session.requestExplicitSave()

        #expect(session.markdown == "# 标题\n\n我的新正文")
        #expect(session.saveState.status == .conflict)
        #expect(
            await session.prepareForAction(.publishPreview)
                == .blocked(reason: "请先处理当前编辑冲突。")
        )
    }

    @Test("edits made while saving are retained and saved again")
    func editDuringSave() async {
        let firstSaveStarted = AsyncSignal()
        let releaseFirstSave = AsyncGate()
        let saveCounter = SaveCounter()
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n初稿")
        ) { request in
            let count = await saveCounter.increment()
            if count == 1 {
                await firstSaveStarted.signal()
                await releaseFirstSave.wait()
            }
            return .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:\(count)"
            )
        }

        session.receive(.markdownChanged("# 标题\n\n保存中"))
        let saveTask = Task { await session.requestExplicitSave() }
        await firstSaveStarted.wait()
        session.receive(.markdownChanged("# 标题\n\n保存中又输入"))
        await releaseFirstSave.open()
        await saveTask.value
        await waitForSaveCount(2, counter: saveCounter)

        #expect(session.markdown == "# 标题\n\n保存中又输入")
        #expect(await saveCounter.value == 2)
        #expect(session.saveState.status == .saved)
    }

    @Test("dependent actions wait for an active save")
    func actionWaitsForSave() async {
        let firstSaveStarted = AsyncSignal()
        let releaseFirstSave = AsyncGate()
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文")
        ) { request in
            await firstSaveStarted.signal()
            await releaseFirstSave.wait()
            return .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }
        session.receive(.markdownChanged("# 标题\n\n更新"))
        let saveTask = Task { await session.requestExplicitSave() }
        await firstSaveStarted.wait()

        let actionTask = Task {
            await session.prepareForAction(.publishPreview)
        }
        await releaseFirstSave.open()
        await saveTask.value

        #expect(await actionTask.value == .allowed)
    }

    @Test("duplicate compatibility block loss is blocked at the final save gate")
    func compatibilityGate() {
        let source = """
        <aside>相同</aside>

        正文

        <aside>相同</aside>
        """
        let blocks = [
            MarkdownCompatibilityBlock(
                kind: .rawHTML,
                source: "<aside>相同</aside>",
                startLine: 1,
                endLine: 1
            ),
            MarkdownCompatibilityBlock(
                kind: .rawHTML,
                source: "<aside>相同</aside>",
                startLine: 5,
                endLine: 5
            )
        ]

        do {
            _ = try MarkdownEditorSavePreparation().prepare(
                manifestTitle: "标题",
                markdown: "# 标题\n\n<aside>相同</aside>\n\n正文",
                compatibilityBlocks: blocks
            )
            Issue.record("Expected compatibility loss to block saving")
        } catch let error as MarkdownEditorCodecError {
            #expect(error == .lostCompatibilityBlock("rawHTML"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(source.contains("<aside>"))
    }

    @Test("inserted media uses one stable library-media reference")
    func mediaInsertionUsesStableReference() throws {
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "媒体", markdown: "# 媒体\n\n正文")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }
        let reference = try NoteMediaReference(
            objectKey: "library-media/\(String(repeating: "a", count: 64)).png"
        )

        session.insertMediaReference(
            reference,
            kind: .image,
            label: "示意图"
        )

        #expect(
            session.markdown
                == "# 媒体\n\n正文\n\n![示意图](\(reference.stringValue))"
        )
        #expect(!session.markdown.contains("http"))

        session.insertMediaReference(reference, kind: .audio, label: "录音")
        session.insertMediaReference(reference, kind: .video, label: "录像")
        #expect(session.markdown.contains("<audio controls"))
        #expect(session.markdown.contains("aria-label=\"录音\""))
        #expect(session.markdown.contains("<video controls"))
        #expect(session.markdown.contains("aria-label=\"录像\""))
    }

    @Test("structured blocks can be inserted, updated and removed")
    func structuredBlockLifecycle() {
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "Blocks", markdown: "# Blocks\n")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: request.expectedFingerprint
            )
        }
        let id = UUID()
        let block = EditorDocumentBlockEnvelope(
            id: id,
            type: "formula",
            fallback: "E = mc^2",
            data: .object(["latex": .string("E = mc^2")])
        )

        session.insertBlock(block)
        #expect(session.blocks == [block])
        #expect(session.markdown.contains("studynotes:block"))
        #expect(session.markdown.contains("type=\"formula\""))

        let updated = EditorDocumentBlockEnvelope(
            id: id,
            type: "formula",
            fallback: "a^2 + b^2 = c^2",
            data: .object(["latex": .string("a^2 + b^2 = c^2")])
        )
        session.updateBlock(updated)
        #expect(session.blocks == [updated])
        #expect(session.markdown.contains("a^2 + b^2 = c^2"))

        session.removeBlock(id: id)
        #expect(session.blocks.isEmpty)
        #expect(!session.markdown.contains("studynotes:block"))
    }

    @Test("structured blocks insert after the active Markdown block")
    func structuredBlockInsertionAnchor() throws {
        let session = MarkdownEditorSession(
            snapshot: snapshot(
                title: "Blocks",
                markdown: "# Blocks\n\nbefore\n\nafter"
            )
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: request.expectedFingerprint
            )
        }
        let block = EditorDocumentBlockEnvelope(
            id: UUID(),
            type: "formula",
            fallback: "x = 1",
            data: .object(["latex": .string("x = 1")])
        )

        session.insertBlock(block, afterText: "before")

        let marker = try #require(
            session.markdown.range(of: "<!-- studynotes:block")
        )
        let before = try #require(session.markdown.range(of: "before"))
        let after = try #require(session.markdown.range(of: "after"))
        #expect(before.lowerBound < marker.lowerBound)
        #expect(marker.lowerBound < after.lowerBound)
    }

    @Test("runtime block messages use the session block lifecycle")
    func runtimeBlockMessages() {
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "Runtime blocks", markdown: "# Runtime blocks\n")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: request.expectedFingerprint
            )
        }
        let original = EditorDocumentBlockEnvelope(
            id: UUID(),
            type: "mermaid",
            fallback: "> **Mermaid**\n> graph TD",
            data: .object([
                "source": .string("graph TD\nA-->B"),
                "renderMode": .string("source")
            ])
        )

        session.receive(.blockInsertRequested(original, anchorText: nil))
        #expect(session.blocks == [original])
        #expect(session.markdown.contains("type=\"mermaid\""))

        let updated = EditorDocumentBlockEnvelope(
            id: original.id,
            type: "mermaid",
            fallback: "> **Mermaid**\n> graph LR",
            data: .object([
                "source": .string("graph LR\nA-->B"),
                "renderMode": .string("source")
            ])
        )
        session.receive(.blockUpdateRequested(updated))
        #expect(session.blocks == [updated])
        #expect(session.markdown.contains("graph LR"))
        #expect(!session.markdown.contains("graph TD"))

        session.receive(.blockRemoveRequested(original.id))
        #expect(session.blocks.isEmpty)
        #expect(!session.markdown.contains("studynotes:block"))
    }

    @Test("new documents start unlocked in edit mode")
    func newDocumentRuntimeDefaults() {
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "新笔记", markdown: "# 新笔记\n\n正文")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }

        #expect(!session.isLocked)
        #expect(session.mode == .edit)
        #expect(session.lockErrorMessage == nil)
    }

    @Test("locked snapshots start in annotate mode and reject edit mode")
    func lockedSnapshotStartsAnnotating() {
        let session = MarkdownEditorSession(
            snapshot: snapshot(
                title: "锁定文档",
                markdown: "# 锁定文档\n\n正文",
                isLocked: true
            )
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }

        #expect(session.isLocked)
        #expect(session.mode == .annotate)
        #expect(
            session.setMode(.edit)
                == .blocked(reason: "文档已锁定，只能继续标注。")
        )
        #expect(session.mode == .annotate)
    }

    @Test("mode arbitration preserves the current annotation selection")
    func modeArbitrationPreservesSelection() {
        let selection = MarkdownEditorSelection(
            quote: "正文",
            prefix: "标题\n\n",
            offset: 4,
            blockPath: [1],
            elementType: .paragraph,
            contentFingerprint: "正文",
            viewportY: 80
        )
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }

        #expect(session.setMode(.annotate) == .allowed)
        session.receive(.selectionChanged(selection))
        #expect(session.selection == selection)
        #expect(session.setMode(.edit) == .allowed)
        #expect(session.selection == selection)
    }

    @Test("new annotations require annotate mode")
    func annotationsRequireAnnotateMode() {
        let selection = MarkdownEditorSelection(
            quote: "正文",
            offset: 4,
            blockPath: [1],
            elementType: .paragraph,
            contentFingerprint: "正文"
        )
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }
        var requestedSelection: MarkdownEditorSelection?
        session.onAnnotationRequested = {
            requestedSelection = $0
        }
        session.receive(.selectionChanged(selection))

        #expect(
            session.requestAnnotation()
                == .blocked(reason: "请先切换到标注模式。")
        )
        #expect(requestedSelection == nil)

        #expect(session.setMode(.annotate) == .allowed)
        #expect(session.requestAnnotation() == .allowed)
        #expect(requestedSelection == selection)
    }

    @Test("locking saves the body before switching to annotate")
    func successfulLockSavesBody() async {
        let saveCounter = SaveCounter()
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文")
        ) { request in
            _ = await saveCounter.increment()
            return .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }
        session.receive(.markdownChanged("# 标题\n\n正文已更新"))

        let decision = await session.lock()

        #expect(decision == .allowed)
        #expect(session.isLocked)
        #expect(session.mode == .annotate)
        #expect(session.saveState.status == .saved)
        let saveCount = await saveCounter.value
        #expect(saveCount == 1)
        #expect(session.lockErrorMessage == nil)
    }

    @Test("failed save blocks locking and retains the edit mode")
    func failedSaveBlocksLock() async {
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文")
        ) { _ in
            .failed(reason: "磁盘不可写")
        }

        let decision = await session.lock()

        #expect(decision == .blocked(reason: "磁盘不可写"))
        #expect(!session.isLocked)
        #expect(session.mode == .edit)
        #expect(session.lockErrorMessage == "磁盘不可写")
    }

    @Test("pending annotation draft can block locking")
    func annotationDraftBlocksLock() async {
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文"),
            saveHandler: { request in
                .saved(
                    title: request.title,
                    markdown: request.markdown,
                    fingerprint: "sha256:saved"
                )
            },
            lockHandler: {
                .blocked(reason: "请先保存或取消标注草稿。")
            }
        )

        let decision = await session.lock()

        #expect(
            decision
                == .blocked(reason: "请先保存或取消标注草稿。")
        )
        #expect(!session.isLocked)
        #expect(session.mode == .edit)
        #expect(session.lockErrorMessage == "请先保存或取消标注草稿。")
    }

    @Test("runtime reports unresolved anchors and layout positions")
    func runtimeAnnotationState() {
        let annotationID = UUID()
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }

        session.receive(
            .unresolvedAnnotationIDsChanged([annotationID])
        )
        session.receive(
            .annotationLayoutChanged([
                annotationID.uuidString: 96
            ])
        )

        #expect(
            session.unresolvedAnnotationIDs == Set([annotationID])
        )
        #expect(
            session.annotationLayoutPositions[annotationID] == 96
        )
    }

    @Test("clicking an existing highlight selects it for the Mac surface")
    func annotationClickSelectsHighlight() {
        let annotationID = UUID()
        var clickedID: UUID?
        let session = MarkdownEditorSession(
            snapshot: snapshot(title: "标题", markdown: "# 标题\n\n正文")
        ) { request in
            .saved(
                title: request.title,
                markdown: request.markdown,
                fingerprint: "sha256:saved"
            )
        }
        session.onAnnotationClicked = {
            clickedID = $0
        }

        session.receive(.annotationClicked(annotationID))

        #expect(session.activeAnnotationID == annotationID)
        #expect(clickedID == annotationID)
        #expect(session.mode == .edit)
    }

    private func snapshot(
        title: String,
        markdown: String,
        isLocked: Bool = false
    ) -> MarkdownEditorSnapshot {
        MarkdownEditorSnapshot(
            materialID: UUID(),
            title: title,
            markdown: markdown,
            fingerprint: "sha256:initial",
            compatibilityBlocks: (
                try? MarkdownEditorCodec().decode(markdown)
            )?.compatibilityBlocks ?? [],
            isLocked: isLocked
        )
    }

    private func waitForSaveCount(
        _ expected: Int,
        counter: SaveCounter
    ) async {
        for _ in 0..<50 {
            if await counter.value >= expected {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor SaveCounter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private actor AsyncSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignaled = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    func wait() async {
        if isSignaled {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
