import Foundation
import Testing
@testable import StudyNotesKit

@Suite("StudyNotes store document transactions")
struct StudyNotesStoreDocumentTransactionTests {
    @Test("editor save commits one generation without creating a revision")
    func editorSaveCommitsGenerationWithoutRevision() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "事务")
        let note = try await store.createMarkdownNote(
            title: "旧标题",
            in: knowledgeBase.id,
            markdown: "# 旧标题"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let blockID = UUID()
        let markdown = """
        # 新标题

        <!-- studynotes:block id="\(blockID.uuidString)" type="data-table" version="1" -->
        可读表格
        <!-- /studynotes:block -->
        """
        let block = EditorDocumentBlockEnvelope(
            id: blockID,
            type: "data-table",
            fallback: "可读表格",
            data: .object([
                "schema": .object(["fields": .array([])]),
                "records": .array([])
            ])
        )

        let saved = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "新标题",
                markdown: markdown,
                blocks: [block],
                expectedContentFingerprint: initial.contentFingerprint
            )
        )

        let generationID = try #require(saved.currentGenerationID)
        #expect(saved.title == "新标题")
        #expect(saved.markdown == markdown)
        #expect(saved.blocks == [block])
        #expect(!saved.isLocked)
        #expect(saved.contentFingerprint.count == 64)
        #expect(try await store.loadTextRevisions(id: note.summary.id).count == 1)

        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let manifestJSON = try #require(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: packageURL.appending(path: "manifest.json")
                )
            ) as? [String: Any]
        )
        #expect(manifestJSON["locked"] as? Bool == false)
        #expect(
            manifestJSON["currentGenerationID"] as? String
                == generationID.uuidString
        )
        #expect(
            manifestJSON["contentFingerprint"] as? String
                == saved.contentFingerprint
        )
        let generationURL = packageURL
            .appending(path: "content")
            .appending(path: "generations")
            .appending(path: generationID.uuidString)
        #expect(
            try String(
                contentsOf: generationURL.appending(path: "document.md"),
                encoding: .utf8
            ) == markdown
        )
        #expect(
            FileManager.default.fileExists(
                atPath: generationURL
                    .appending(path: "blocks")
                    .appending(path: blockID.uuidString)
                    .appending(path: "block.json")
                    .path
            )
        )
        let transactionDirectory = packageURL
            .appending(path: "content")
            .appending(path: "transactions")
        if FileManager.default.fileExists(atPath: transactionDirectory.path) {
            #expect(
                try FileManager.default.contentsOfDirectory(
                    at: transactionDirectory,
                    includingPropertiesForKeys: nil
                ).filter { $0.pathExtension == "json" }.isEmpty
            )
        }

        let document = try await store.loadMaterialDocument(id: note.summary.id)
        #expect(document.markdown == markdown)
        #expect(document.summary.title == "新标题")
    }

    @Test("invalid bypass blocks fail with the exact block ID and leave content unchanged")
    func invalidBypassBlocksAreLocated() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "校验")
        let note = try await store.createMarkdownNote(
            title: "校验",
            in: knowledgeBase.id,
            markdown: "# 原文"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let blockID = UUID()
        let versionTwoMarkdown = """
        <!-- studynotes:block id="\(blockID.uuidString)" type="data-table" version="2" -->
        可读表格
        <!-- /studynotes:block -->
        """
        let versionTwoBlock = EditorDocumentBlockEnvelope(
            id: blockID,
            type: "data-table",
            version: 2,
            fallback: "可读表格",
            data: .object([:])
        )

        do {
            _ = try await store.saveEditorDocument(
                EditorDocumentSaveRequest(
                    materialID: note.summary.id,
                    title: "校验",
                    markdown: versionTwoMarkdown,
                    blocks: [versionTwoBlock],
                    expectedContentFingerprint: initial.contentFingerprint
                )
            )
            Issue.record("Expected an unsupported block version error")
        } catch let error as StudyNotesError {
            #expect(
                error == .editorDocumentBlockVersionUnsupported(
                    blockID: blockID,
                    version: 2
                )
            )
        }

        let missingID = UUID()
        let missingMarkdown = """
        <!-- studynotes:block id="\(missingID.uuidString)" type="data-table" version="1" -->
        缺失
        <!-- /studynotes:block -->
        """
        do {
            _ = try await store.saveEditorDocument(
                EditorDocumentSaveRequest(
                    materialID: note.summary.id,
                    title: "校验",
                    markdown: missingMarkdown,
                    blocks: [],
                    expectedContentFingerprint: initial.contentFingerprint
                )
            )
            Issue.record("Expected a missing block error")
        } catch let error as StudyNotesError {
            #expect(error == .editorDocumentBlockMissing(blockID: missingID))
        }

        let unserializableID = UUID()
        let unserializableMarkdown = """
        <!-- studynotes:block id="\(unserializableID.uuidString)" type="data-table" version="1" -->
        无法序列化
        <!-- /studynotes:block -->
        """
        do {
            _ = try await store.saveEditorDocument(
                EditorDocumentSaveRequest(
                    materialID: note.summary.id,
                    title: "校验",
                    markdown: unserializableMarkdown,
                    blocks: [
                        EditorDocumentBlockEnvelope(
                            id: unserializableID,
                            type: "data-table",
                            fallback: "无法序列化",
                            data: .object(["value": .number(.nan)])
                        )
                    ],
                    expectedContentFingerprint: initial.contentFingerprint
                )
            )
            Issue.record("Expected a block serialization error")
        } catch let error as StudyNotesError {
            guard case let .editorDocumentBlockInvalid(failedID, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(failedID == unserializableID)
        }

        let unchanged = try await store.loadEditorDocument(id: note.summary.id)
        #expect(unchanged.markdown == "# 原文")
        #expect(unchanged.currentGenerationID == nil)
    }

    @Test("external fingerprint changes conflict and successful save removes the old generation")
    func externalChangesConflictAndOldGenerationIsRemoved() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "冲突")
        let note = try await store.createMarkdownNote(
            title: "冲突",
            in: knowledgeBase.id,
            markdown: "# 初始"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let first = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "冲突",
                markdown: "# 第一代",
                blocks: [],
                expectedContentFingerprint: initial.contentFingerprint
            )
        )
        let firstGenerationID = try #require(first.currentGenerationID)
        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let firstDocumentURL = packageURL
            .appending(path: "content")
            .appending(path: "generations")
            .appending(path: firstGenerationID.uuidString)
            .appending(path: "document.md")
        try Data("# 外部修改".utf8).write(
            to: firstDocumentURL,
            options: .atomic
        )

        do {
            _ = try await store.saveEditorDocument(
                EditorDocumentSaveRequest(
                    materialID: note.summary.id,
                    title: "冲突",
                    markdown: "# 本地覆盖",
                    blocks: [],
                    expectedContentFingerprint: first.contentFingerprint
                )
            )
            Issue.record("Expected an external fingerprint conflict")
        } catch let error as StudyNotesError {
            #expect(
                error == .editorDocumentConflict(
                    expected: first.contentFingerprint,
                    current: ContentFingerprint.sha256("# 外部修改")
                )
            )
        }
        #expect(
            try String(contentsOf: firstDocumentURL, encoding: .utf8)
                == "# 外部修改"
        )

        let externallyChanged = try await store.loadEditorDocument(id: note.summary.id)
        let second = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "冲突",
                markdown: "# 第二代",
                blocks: [],
                expectedContentFingerprint: externallyChanged.contentFingerprint
            )
        )
        #expect(second.currentGenerationID != firstGenerationID)
        #expect(
            !FileManager.default.fileExists(
                atPath: firstDocumentURL.deletingLastPathComponent().path
            )
        )
    }

    @Test("uncommitted generations stay invisible while the newest transaction is recoverable")
    func transactionRecoveryIgnoresIncompleteGenerations() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "恢复")
        let note = try await store.createMarkdownNote(
            title: "恢复",
            in: knowledgeBase.id,
            markdown: "# 已提交"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let incompleteGenerationURL = packageURL
            .appending(path: "content")
            .appending(path: "generations")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: incompleteGenerationURL,
            withIntermediateDirectories: true
        )
        try Data("# 未完成".utf8).write(
            to: incompleteGenerationURL.appending(path: "document.md")
        )

        let visible = try await store.loadEditorDocument(id: note.summary.id)
        #expect(visible.markdown == "# 已提交")
        #expect(visible.currentGenerationID == nil)

        let transaction = EditorDocumentTransaction(
            id: UUID(),
            materialID: note.summary.id,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            baseContentFingerprint: initial.contentFingerprint,
            generationID: UUID(),
            contentFingerprint: ContentFingerprint.sha256("# 恢复后的正文"),
            title: "恢复后的标题",
            markdown: "# 恢复后的正文",
            blocks: []
        )
        let transactionsURL = packageURL
            .appending(path: "content")
            .appending(path: "transactions")
        try FileManager.default.createDirectory(
            at: transactionsURL,
            withIntermediateDirectories: true
        )
        try CrossPlatformJSON.encoder().encode(transaction).write(
            to: transactionsURL.appending(
                path: "\(transaction.id.uuidString).json"
            )
        )

        let recovered = try #require(
            try await store.loadPendingEditorDocumentTransaction(
                id: note.summary.id
            )
        )
        #expect(recovered == transaction)
        #expect(
            try await store.loadEditorDocument(id: note.summary.id).markdown
                == "# 已提交"
        )

        _ = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: recovered.title,
                markdown: recovered.markdown,
                blocks: recovered.blocks,
                expectedContentFingerprint: recovered.baseContentFingerprint
            )
        )
        #expect(
            try await store.loadPendingEditorDocumentTransaction(
                id: note.summary.id
            ) == nil
        )
        #expect(
            try await store.loadEditorDocument(id: note.summary.id).markdown
                == "# 恢复后的正文"
        )
    }

    @Test("lock state persists and pending transactions block locking")
    func lockStatePersistsAndGuardsEditing() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "锁定")
        let note = try await store.createMarkdownNote(
            title: "锁定",
            in: knowledgeBase.id,
            markdown: "# 正文"
        )
        let unlocked = try await store.loadEditorDocument(id: note.summary.id)
        #expect(!unlocked.isLocked)

        let locked = try await store.setEditorDocumentLocked(
            id: note.summary.id,
            isLocked: true
        )
        #expect(locked.isLocked)
        let reopened = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index-2.sqlite")
        )
        #expect(try await reopened.loadEditorDocument(id: note.summary.id).isLocked)

        do {
            _ = try await store.saveEditorDocument(
                EditorDocumentSaveRequest(
                    materialID: note.summary.id,
                    title: "锁定",
                    markdown: "# 修改",
                    blocks: [],
                    expectedContentFingerprint: locked.contentFingerprint
                )
            )
            Issue.record("Expected a locked document error")
        } catch let error as StudyNotesError {
            #expect(error == .editorDocumentLocked)
        }

        _ = try await store.setEditorDocumentLocked(
            id: note.summary.id,
            isLocked: false
        )
        let unlockedContent = try await store.loadEditorDocument(id: note.summary.id)
        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let transaction = EditorDocumentTransaction(
            id: UUID(),
            materialID: note.summary.id,
            createdAt: Date(),
            baseContentFingerprint: unlockedContent.contentFingerprint,
            generationID: UUID(),
            contentFingerprint: ContentFingerprint.sha256("# 草稿"),
            title: "锁定",
            markdown: "# 草稿",
            blocks: []
        )
        let transactionsURL = packageURL
            .appending(path: "content")
            .appending(path: "transactions")
        try FileManager.default.createDirectory(
            at: transactionsURL,
            withIntermediateDirectories: true
        )
        try CrossPlatformJSON.encoder().encode(transaction).write(
            to: transactionsURL.appending(
                path: "\(transaction.id.uuidString).json"
            )
        )

        do {
            _ = try await store.setEditorDocumentLocked(
                id: note.summary.id,
                isLocked: true
            )
            Issue.record("Expected a pending transaction lock error")
        } catch let error as StudyNotesError {
            #expect(error == .editorDocumentHasPendingTransaction)
        }
    }

    @Test("derived rebuild failure keeps committed content and records a retry state")
    func derivedRebuildFailureDoesNotRollbackContent() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "派生")
        let note = try await store.createMarkdownNote(
            title: "派生",
            in: knowledgeBase.id,
            markdown: "# 原始"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let annotationsURL = packageURL.appending(path: "annotations")
        try Data("not a directory".utf8).write(to: annotationsURL)

        let saved = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "派生",
                markdown: "# 已提交",
                blocks: [],
                expectedContentFingerprint: initial.contentFingerprint
            )
        )
        #expect(saved.markdown == "# 已提交")
        #expect(saved.derivedRebuildPending)
        #expect(
            try await store.loadMaterialDocument(id: note.summary.id)
                .derivedRebuildPending
        )

        try FileManager.default.removeItem(at: annotationsURL)
        let rebuilt = try await store.retryEditorDocumentDerivedRebuild(
            id: note.summary.id
        )
        #expect(!rebuilt.derivedRebuildPending)
        #expect(rebuilt.markdown == "# 已提交")
    }

    @Test("current generation reports missing and malformed block files by block ID")
    func currentGenerationValidatesBlockFiles() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "块文件")
        let note = try await store.createMarkdownNote(
            title: "块文件",
            in: knowledgeBase.id,
            markdown: "# 原文"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let blockID = UUID()
        let markdown = """
        <!-- studynotes:block id="\(blockID.uuidString)" type="data-table" version="1" -->
        降级内容
        <!-- /studynotes:block -->
        """
        let saved = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "块文件",
                markdown: markdown,
                blocks: [
                    EditorDocumentBlockEnvelope(
                        id: blockID,
                        type: "data-table",
                        fallback: "降级内容",
                        data: .object([:])
                    )
                ],
                expectedContentFingerprint: initial.contentFingerprint
            )
        )
        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let blockURL = packageURL
            .appending(path: "content")
            .appending(path: "generations")
            .appending(
                path: try #require(saved.currentGenerationID).uuidString
            )
            .appending(path: "blocks")
            .appending(path: blockID.uuidString)
            .appending(path: "block.json")
        try FileManager.default.removeItem(at: blockURL)

        do {
            _ = try await store.loadEditorDocument(id: note.summary.id)
            Issue.record("Expected a missing block file error")
        } catch let error as StudyNotesError {
            #expect(error == .editorDocumentBlockMissing(blockID: blockID))
        }

        try Data("{not-json".utf8).write(to: blockURL)
        do {
            _ = try await store.loadEditorDocument(id: note.summary.id)
            Issue.record("Expected a malformed block file error")
        } catch let error as StudyNotesError {
            guard case let .editorDocumentBlockInvalid(failedID, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(failedID == blockID)
        }
    }

    @Test("external block changes participate in fingerprint conflicts")
    func externalBlockChangesConflict() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "块冲突")
        let note = try await store.createMarkdownNote(
            title: "块冲突",
            in: knowledgeBase.id,
            markdown: "# 原文"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let blockID = UUID()
        let markdown = """
        <!-- studynotes:block id="\(blockID.uuidString)" type="data-table" version="1" -->
        降级内容
        <!-- /studynotes:block -->
        """
        let originalBlock = EditorDocumentBlockEnvelope(
            id: blockID,
            type: "data-table",
            fallback: "降级内容",
            data: .object(["value": .string("A")])
        )
        let saved = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "块冲突",
                markdown: markdown,
                blocks: [originalBlock],
                expectedContentFingerprint: initial.contentFingerprint
            )
        )
        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let blockURL = packageURL
            .appending(path: "content")
            .appending(path: "generations")
            .appending(
                path: try #require(saved.currentGenerationID).uuidString
            )
            .appending(path: "blocks")
            .appending(path: blockID.uuidString)
            .appending(path: "block.json")
        let externallyChangedBlock = EditorDocumentBlockEnvelope(
            id: blockID,
            type: "data-table",
            fallback: "降级内容",
            data: .object(["value": .string("B")])
        )
        try CrossPlatformJSON.encoder().encode(externallyChangedBlock).write(
            to: blockURL,
            options: .atomic
        )
        let externallyChanged = try await store.loadEditorDocument(
            id: note.summary.id
        )
        #expect(externallyChanged.contentFingerprint != saved.contentFingerprint)

        do {
            _ = try await store.saveEditorDocument(
                EditorDocumentSaveRequest(
                    materialID: note.summary.id,
                    title: "块冲突",
                    markdown: markdown,
                    blocks: [originalBlock],
                    expectedContentFingerprint: saved.contentFingerprint
                )
            )
            Issue.record("Expected a block fingerprint conflict")
        } catch let error as StudyNotesError {
            #expect(
                error == .editorDocumentConflict(
                    expected: saved.contentFingerprint,
                    current: externallyChanged.contentFingerprint
                )
            )
        }
    }

    @Test("a transaction already pointed to by manifest is not offered for recovery")
    func committedTransactionIsNotRecoverable() async throws {
        let directory = try EditorTransactionTemporaryDirectory()
        defer { directory.remove() }
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: directory.url.appending(path: "index.sqlite")
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "已提交事务")
        let note = try await store.createMarkdownNote(
            title: "已提交事务",
            in: knowledgeBase.id,
            markdown: "# 原文"
        )
        let initial = try await store.loadEditorDocument(id: note.summary.id)
        let saved = try await store.saveEditorDocument(
            EditorDocumentSaveRequest(
                materialID: note.summary.id,
                title: "已提交事务",
                markdown: "# 已提交",
                blocks: [],
                expectedContentFingerprint: initial.contentFingerprint
            )
        )
        let packageURL = try editorTransactionPackageURL(
            rootURL: directory.url,
            materialID: note.summary.id
        )
        let transaction = EditorDocumentTransaction(
            id: UUID(),
            materialID: note.summary.id,
            createdAt: Date(),
            baseContentFingerprint: initial.contentFingerprint,
            generationID: try #require(saved.currentGenerationID),
            contentFingerprint: saved.contentFingerprint,
            title: saved.title,
            markdown: saved.markdown,
            blocks: saved.blocks
        )
        let transactionsURL = packageURL
            .appending(path: "content")
            .appending(path: "transactions")
        try FileManager.default.createDirectory(
            at: transactionsURL,
            withIntermediateDirectories: true
        )
        try CrossPlatformJSON.encoder().encode(transaction).write(
            to: transactionsURL.appending(
                path: "\(transaction.id.uuidString).json"
            )
        )

        #expect(
            try await store.loadPendingEditorDocumentTransaction(
                id: note.summary.id
            ) == nil
        )
    }
}

private struct EditorTransactionTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(
                path: "StudyNotesEditorTransactionTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private func editorTransactionPackageURL(
    rootURL: URL,
    materialID: UUID
) throws -> URL {
    guard let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey]
    ) else {
        throw EditorTransactionTestError.packageNotFound
    }
    while let candidate = enumerator.nextObject() as? URL {
        guard candidate.pathExtension == "studyitem" else {
            continue
        }
        let manifestURL = candidate.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              manifest["id"] as? String == materialID.uuidString else {
            continue
        }
        return candidate
    }
    throw EditorTransactionTestError.packageNotFound
}

private enum EditorTransactionTestError: Error {
    case packageNotFound
}
