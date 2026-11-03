import Foundation
import XCTest
@testable import StudyNotesIOSCore

final class CoreTests: XCTestCase {
    func testTextAnchorUsesContextWhenQuoteRepeats() {
        let text = "第一段重复内容。\n\n第二段带有重复内容但上下文不同。"
        let anchor = TextAnchor(
            quote: "重复内容",
            prefix: "第二段带有",
            suffix: "但上下文",
            startOffset: 14,
            endOffset: 18,
            blockPath: "block-1"
        )

        let resolved = TextAnchorResolver.resolve(anchor, in: text)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(
            (resolved?.range.upperBound ?? 0) - (resolved?.range.lowerBound ?? 0),
            4
        )
        XCTAssertEqual(resolved?.blockPath, "block-1")
    }

    func testTextAnchorNeedsRecoveryAfterContentChange() {
        let anchor = TextAnchor(
            quote: "已经不存在的原文",
            startOffset: 0,
            endOffset: 8,
            blockPath: "block-0"
        )
        XCTAssertNil(TextAnchorResolver.resolve(anchor, in: "新的正文"))
    }

    func testEquivalentTextAnchorsAreReused() {
        let left = TextAnchor(
            quote: "认知负荷",
            startOffset: 2,
            endOffset: 6,
            blockPath: "block-0"
        )
        let right = TextAnchor(
            quote: "认知负荷",
            startOffset: 2,
            endOffset: 6,
            blockPath: "block-0"
        )
        XCTAssertTrue(
            TextAnchorResolver.anchorsAreEquivalent(.text(left), .text(right))
        )
    }

    func testMarkdownRenderingEscapesSourceAndAddsBlockIDs() {
        let html = MarkdownHTMLRenderer.render(
            source: "# 标题\n\n<script>alert(1)</script>",
            title: "测试",
            kind: .markdown
        )
        XCTAssertTrue(html.contains("data-block-id=\"block-0\""))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testSSEParserHandlesDeltaUsageAndDone() {
        var parser = AIStreamParser()
        let delta = parser.consume(
            line: #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        )
        let usage = parser.consume(
            line: #"data: {"usage":{"prompt_tokens":12,"completion_tokens":8}}"#
        )
        let done = parser.consume(line: "data: [DONE]")

        XCTAssertEqual(delta, [.delta("你好")])
        XCTAssertEqual(usage, [.usage(promptTokens: 12, completionTokens: 8)])
        XCTAssertEqual(
            done,
            [
                .usage(promptTokens: 12, completionTokens: 8),
                .completed
            ]
        )
    }

    func testLibrarySnapshotAndScopedSearch() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesIOS-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try makeFixture(at: rootURL)

        let store = try IOSLibraryStore(rootURL: rootURL)
        let snapshot = try await store.snapshot(isICloud: false)
        XCTAssertEqual(snapshot.knowledgeBases.count, 1)
        XCTAssertEqual(snapshot.materials.count, 1)
        XCTAssertEqual(snapshot.materials[0].folderPath, "学习科学/记忆")
        XCTAssertEqual(snapshot.materials[0].accessState, .downloaded)

        let search = LibrarySearchService(libraryStore: store)
        let metadataHits = await search.search(query: "学习科学", snapshot: snapshot)
        let contentHits = await search.search(query: "工作记忆", snapshot: snapshot)
        XCTAssertTrue(metadataHits.contains { $0.kind == .metadata })
        XCTAssertTrue(contentHits.contains { $0.kind == .content })
    }

    func testInboxCollectWritesInboxItem() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesIOS-Inbox-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: rootURL.appending(path: "Libraries"),
            withIntermediateDirectories: true
        )
        let inbox = try InboxStore(rootURL: rootURL)
        let draft = InboxDraft(
            kind: .url,
            title: "https://example.com/article",
            payloadFileExtension: "txt",
            payloadData: Data("https://example.com/article".utf8)
        )

        let result = try await inbox.collect(draft)
        let items = try await inbox.listItems()

        XCTAssertEqual(result.status, .collected)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, draft.id)
        XCTAssertEqual(items[0].status, .collected)
    }

    func testInboxFailureKeepsRetryableDraft() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesIOS-InboxRetry-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: rootURL.appending(path: "Libraries"),
            withIntermediateDirectories: true
        )
        let inbox = try InboxStore(rootURL: rootURL)
        let inboxURL = rootURL.appending(path: "Inbox", directoryHint: .isDirectory)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: inboxURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: inboxURL.path
            )
        }
        let draft = InboxDraft(
            kind: .text,
            title: "待重试",
            payloadFileExtension: "txt",
            payloadData: Data("失败后保留".utf8)
        )

        let failed = try await inbox.collect(draft)
        guard case .failed = failed.status else {
            return XCTFail("收件箱写入失败时应返回失败状态")
        }
        let pendingItems = try await inbox.listItems()
        XCTAssertEqual(pendingItems.first?.id, draft.id)
        XCTAssertEqual(pendingItems.first?.status, .pending)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: inboxURL.path
        )
        let retried = try await inbox.retry(itemID: draft.id)
        XCTAssertEqual(retried.status, .collected)
    }

    func testAnnotationReuseAndRecoveryAfterContentChange() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesIOS-Anchor-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try makeFixture(at: rootURL)
        let store = try IOSLibraryStore(rootURL: rootURL)
        let snapshot = try await store.snapshot(isICloud: false)
        let material = try XCTUnwrap(snapshot.materials.first)
        let document = try await store.loadDocument(
            materialID: material.id,
            isICloud: false
        )
        let anchor = TextAnchor(
            quote: "工作记忆",
            prefix: "记忆",
            suffix: "是有限",
            startOffset: 8,
            endOffset: 12,
            blockPath: "block-1"
        )
        let first = StudyAnnotation(
            materialID: material.id,
            anchor: .text(anchor),
            note: "第一版备注"
        )
        _ = try await store.saveAnnotation(
            first,
            materialID: material.id,
            sourceText: document.sourceText
        )

        let duplicate = StudyAnnotation(
            materialID: material.id,
            anchor: .text(anchor),
            note: "编辑后的备注"
        )
        let saved = try await store.saveAnnotation(
            duplicate,
            materialID: material.id,
            sourceText: document.sourceText
        )
        XCTAssertEqual(saved.id, first.id)
        XCTAssertEqual(saved.note, "编辑后的备注")

        let changedSource = "# 记忆\n\n内容已经改写了。"
        let annotations = try await store.loadAnnotations(
            materialID: material.id,
            sourceText: changedSource
        )
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations[0].resolution, .needsRecovery)
        XCTAssertEqual(annotations[0].note, "编辑后的备注")
    }

    func testAIConversationPersistsInMaterialPackage() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesIOS-AI-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try makeFixture(at: rootURL)
        let store = try IOSLibraryStore(rootURL: rootURL)
        let snapshot = try await store.snapshot(isICloud: false)
        let material = try XCTUnwrap(snapshot.materials.first)
        let conversation = AIConversation(
            materialID: material.id,
            providerName: "DeepSeek",
            modelID: "deepseek-chat",
            action: "解释",
            scopeDescription: "选中文字",
            messages: [
                AIMessage(role: .user, content: "解释工作记忆"),
                AIMessage(role: .assistant, content: "工作记忆容量有限。")
            ]
        )

        try await store.saveConversation(conversation)
        let loaded = try await store.loadConversations(materialID: material.id)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, conversation.id)
        XCTAssertEqual(loaded.first?.messages.map(\.id), conversation.messages.map(\.id))
        XCTAssertEqual(loaded.first?.messages.map(\.content), conversation.messages.map(\.content))
    }

    func testSearchDoesNotReadFullTextForMetadataOnlyMaterial() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesIOS-Scope-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: rootURL.appending(path: "Libraries"),
            withIntermediateDirectories: true
        )
        let store = try IOSLibraryStore(rootURL: rootURL)
        let materialID = UUID()
        let manifest = MaterialManifestRecord(
            id: materialID,
            knowledgeBaseID: UUID(),
            kind: "markdown",
            title: "未下载材料",
            createdAt: Date(),
            updatedAt: Date(),
            tags: ["范围"]
        )
        let snapshot = IOSLibrarySnapshot(
            knowledgeBases: [],
            materials: [
                LibraryMaterial(
                    manifest: manifest,
                    knowledgeBaseName: "学习科学",
                    packageURL: rootURL.appending(path: "missing.studyitem"),
                    accessState: .metadataOnly
                )
            ],
            rootURL: rootURL,
            isICloud: true
        )
        let search = LibrarySearchService(libraryStore: store)

        let metadataHits = await search.search(query: "范围", snapshot: snapshot)
        let bodyHits = await search.search(query: "隐藏正文", snapshot: snapshot)
        XCTAssertTrue(metadataHits.contains { $0.kind == .metadata })
        XCTAssertTrue(bodyHits.isEmpty)
    }

    private func makeFixture(at rootURL: URL) throws {
        let knowledgeBaseID = UUID()
        let materialID = UUID()
        let libraryURL = rootURL
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBaseID.uuidString, directoryHint: .isDirectory)
        let packageURL = libraryURL
            .appending(path: "学习科学", directoryHint: .isDirectory)
            .appending(path: "记忆", directoryHint: .isDirectory)
            .appending(path: "\(materialID.uuidString).studyitem", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: packageURL.appending(path: "content", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let encoder = StudyNotesFileSupport.encoder()
        let knowledgeBase = KnowledgeBaseSummary(
            id: knowledgeBaseID,
            name: "学习科学",
            createdAt: Date()
        )
        try encoder.encode(knowledgeBase).write(
            to: libraryURL.appending(path: "knowledge-base.json")
        )
        let manifest = MaterialManifestRecord(
            id: materialID,
            knowledgeBaseID: knowledgeBaseID,
            kind: "markdown",
            title: "记忆与学习",
            createdAt: Date(),
            updatedAt: Date(),
            folderPath: "学习科学/记忆",
            tags: ["记忆"]
        )
        try encoder.encode(manifest).write(
            to: packageURL.appending(path: "manifest.json")
        )
        try Data("# 记忆\n\n工作记忆是有限资源。".utf8).write(
            to: packageURL.appending(path: "content/note.md")
        )
    }
}
