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
    }

    private func snapshot(
        title: String,
        markdown: String
    ) -> MarkdownEditorSnapshot {
        MarkdownEditorSnapshot(
            materialID: UUID(),
            title: title,
            markdown: markdown,
            fingerprint: "sha256:initial",
            compatibilityBlocks: (
                try? MarkdownEditorCodec().decode(markdown)
            )?.compatibilityBlocks ?? []
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
