import Foundation
import Security
import XCTest
import StudyNotesKit
@testable import StudyNotesIOSCore

final class CrossPlatformTests: XCTestCase {
    func testIOSAnnotationsAndAISessionAreReadableByStudyNotesKit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let iosStore = try StudyNotesIOSCore.IOSLibraryStore(rootURL: fixture.rootURL)
        let snapshot = try await iosStore.snapshot(isICloud: false)
        let material = try XCTUnwrap(snapshot.materials.first)
        let textAnchor = StudyNotesIOSCore.TextAnchor(
            quote: "工作记忆",
            prefix: "记忆",
            suffix: "是有限",
            startOffset: 8,
            endOffset: 12,
            blockPath: "block-1"
        )
        let textAnnotation = StudyNotesIOSCore.StudyAnnotation(
            materialID: material.id,
            anchor: .text(textAnchor),
            note: "iOS 文字标注"
        )
        let imageAnnotation = StudyNotesIOSCore.StudyAnnotation(
            materialID: material.id,
            anchor: .imageRectangle(
                StudyNotesIOSCore.NormalizedRectangle(
                    x: 0.12,
                    y: 0.24,
                    width: 0.3,
                    height: 0.2
                )
            ),
            note: "iOS 图片标注"
        )
        let pageAnnotation = StudyNotesIOSCore.StudyAnnotation(
            materialID: material.id,
            anchor: .pageRectangle(
                page: 2,
                rectangle: StudyNotesIOSCore.NormalizedRectangle(
                    x: 0.4,
                    y: 0.5,
                    width: 0.2,
                    height: 0.1
                )
            ),
            note: "iOS 页面标注"
        )
        _ = try await iosStore.saveAnnotation(
            textAnnotation,
            materialID: material.id,
            sourceText: fixture.text
        )
        _ = try await iosStore.saveAnnotation(
            imageAnnotation,
            materialID: material.id,
            sourceText: fixture.text
        )
        _ = try await iosStore.saveAnnotation(
            pageAnnotation,
            materialID: material.id,
            sourceText: fixture.text
        )

        let session = StudyNotesIOSCore.AIConversation(
            materialID: material.id,
            providerName: "DeepSeek",
            modelID: "deepseek-chat",
            action: "解释",
            scopeDescription: "选中文字",
            originAnchor: .text(textAnchor),
            status: .completed,
            messages: [
                StudyNotesIOSCore.AIMessage(
                    role: .user,
                    content: "解释工作记忆"
                ),
                StudyNotesIOSCore.AIMessage(
                    role: .assistant,
                    content: "工作记忆容量有限。",
                    promptTokens: 18,
                    completionTokens: 9
                )
            ]
        )
        try await iosStore.saveConversation(session)

        let kitStore = StudyNotesStore(rootURL: fixture.rootURL)
        let kitAnnotations = try await kitStore.loadAnnotations(
            materialID: material.id
        )
        XCTAssertEqual(kitAnnotations.count, 3)
        let kitText = try XCTUnwrap(
            kitAnnotations.first { $0.id == textAnnotation.id }
        )
        XCTAssertEqual(kitText.anchor.kind, .text)
        XCTAssertEqual(kitText.anchor.excerpt, "工作记忆")
        XCTAssertEqual(kitText.anchor.blockPath, [1])
        XCTAssertEqual(kitText.quote, "工作记忆")
        XCTAssertEqual(kitText.note, "iOS 文字标注")
        XCTAssertEqual(kitText.status, .active)

        let kitImage = try XCTUnwrap(
            kitAnnotations.first { $0.id == imageAnnotation.id }
        )
        XCTAssertEqual(kitImage.anchor.kind, .imageRect)
        XCTAssertEqual(kitImage.anchor.rect?.x ?? -1, 0.12, accuracy: 0.001)
        XCTAssertEqual(kitImage.anchor.rect?.height ?? -1, 0.2, accuracy: 0.001)
        let kitPage = try XCTUnwrap(
            kitAnnotations.first { $0.id == pageAnnotation.id }
        )
        XCTAssertEqual(kitPage.anchor.kind, .pdfPageRect)
        XCTAssertEqual(kitPage.anchor.pageIndex, 2)
        XCTAssertEqual(kitPage.anchor.rect?.x ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(kitPage.status, .unresolved)

        let kitSessions = try await kitStore.loadConversations(
            materialID: material.id
        )
        let kitSession = try XCTUnwrap(
            kitSessions.first { $0.id == session.id }
        )
        XCTAssertEqual(kitSession.model, "deepseek-chat")
        XCTAssertEqual(kitSession.action, "解释")
        XCTAssertEqual(kitSession.scopeDescription, "选中文字")
        XCTAssertEqual(kitSession.status, .completed)
        XCTAssertEqual(kitSession.messages.count, 2)
        XCTAssertEqual(kitSession.messages[1].promptTokens, 18)
        XCTAssertEqual(kitSession.messages[1].completionTokens, 9)

        let annotationJSON = try String(
            contentsOf: fixture.packageURL
                .appending(path: "annotations/\(textAnnotation.id.uuidString).json"),
            encoding: .utf8
        )
        XCTAssertTrue(annotationJSON.contains("\"kind\" : \"text\""))
        XCTAssertFalse(annotationJSON.contains("\"resolution\""))
    }

    func testMacAnnotationsAndAISessionAreReadableByIOS() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let kitStore = StudyNotesStore(rootURL: fixture.rootURL)
        let textAnchor = AnnotationAnchor(
            kind: .text,
            excerpt: "工作记忆",
            prefix: "记忆",
            suffix: "是有限",
            offset: 8,
            blockPath: [1]
        )
        let annotation = try await kitStore.upsertAnnotation(
            MaterialAnnotation(
                materialID: fixture.materialID,
                anchor: textAnchor,
                quote: "工作记忆",
                note: "Mac 标注"
            )
        )
        let imageAnnotation = try await kitStore.upsertAnnotation(
            MaterialAnnotation(
                materialID: fixture.materialID,
                anchor: AnnotationAnchor(
                    kind: .imageRect,
                    rect: NormalizedRect(
                        x: 0.2,
                        y: 0.3,
                        width: 0.25,
                        height: 0.15
                    )
                ),
                quote: "",
                note: "Mac 图片标注"
            )
        )
        let pageAnnotation = try await kitStore.upsertAnnotation(
            MaterialAnnotation(
                materialID: fixture.materialID,
                anchor: AnnotationAnchor(
                    kind: .pdfPageRect,
                    pageIndex: 3,
                    rect: NormalizedRect(
                        x: 0.15,
                        y: 0.2,
                        width: 0.5,
                        height: 0.3
                    )
                ),
                quote: "",
                note: "Mac 页面标注"
            )
        )
        let session = try await kitStore.saveConversation(
            AIConversation(
                materialID: fixture.materialID,
                title: "整篇总结",
                origin: .summary,
                action: "总结",
                scopeDescription: "整份材料",
                status: .stopped,
                messages: [
                    AIMessage(
                        role: .assistant,
                        content: "Mac 端生成的总结",
                        promptTokens: 31,
                        completionTokens: 14
                    )
                ],
                providerName: "OpenAI",
                model: "gpt-test"
            )
        )

        let iosStore = try StudyNotesIOSCore.IOSLibraryStore(rootURL: fixture.rootURL)
        let annotations = try await iosStore.loadAnnotations(
            materialID: fixture.materialID,
            sourceText: fixture.text
        )
        XCTAssertEqual(annotations.count, 3)
        let iosText = try XCTUnwrap(annotations.first { $0.id == annotation.id })
        XCTAssertEqual(iosText.quote, "工作记忆")
        XCTAssertEqual(iosText.note, "Mac 标注")
        guard case let .text(decodedAnchor) = iosText.anchor else {
            return XCTFail("应解码为文字锚点")
        }
        XCTAssertEqual(decodedAnchor.startOffset, 8)
        XCTAssertEqual(decodedAnchor.endOffset, 12)
        XCTAssertEqual(decodedAnchor.blockPath, "block-1")
        let iosImage = try XCTUnwrap(
            annotations.first { $0.id == imageAnnotation.id }
        )
        guard case let .imageRectangle(rect) = iosImage.anchor else {
            return XCTFail("应解码为图片矩形锚点")
        }
        XCTAssertEqual(rect.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(rect.width, 0.25, accuracy: 0.001)
        let iosPage = try XCTUnwrap(
            annotations.first { $0.id == pageAnnotation.id }
        )
        guard case let .pageRectangle(page, pageRect) = iosPage.anchor else {
            return XCTFail("应解码为 PDF 页面矩形锚点")
        }
        XCTAssertEqual(page, 3)
        XCTAssertEqual(pageRect.x, 0.15, accuracy: 0.001)
        XCTAssertEqual(pageRect.height, 0.3, accuracy: 0.001)

        let sessions = try await iosStore.loadConversations(
            materialID: fixture.materialID
        )
        let iosSession = try XCTUnwrap(sessions.first { $0.id == session.id })
        XCTAssertEqual(iosSession.model, "gpt-test")
        XCTAssertEqual(iosSession.action, "总结")
        XCTAssertEqual(iosSession.scopeDescription, "整份材料")
        XCTAssertEqual(iosSession.status, .stopped)
        XCTAssertEqual(iosSession.messages.first?.promptTokens, 31)
    }

    func testIOSInboxDraftIsVisibleAndMaterializedByStudyNotesKit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let inbox = try StudyNotesIOSCore.InboxStore(rootURL: fixture.rootURL)
        let draft = StudyNotesIOSCore.InboxDraft(
            kind: .text,
            title: "待整理片段",
            payloadFileExtension: "txt",
            payloadData: Data("这是从 iOS 收件箱同步的文本。".utf8)
        )
        let collected = try await inbox.collect(draft)
        XCTAssertEqual(collected.status, .collected)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.rootURL
                    .appending(path: "Inbox/\(draft.id.uuidString).studyitem")
                    .path
            ),
            "收件动作本身不能创建完整材料"
        )

        let kitStore = StudyNotesStore(rootURL: fixture.rootURL)
        let initialIndex = try await kitStore.loadIndex()
        XCTAssertTrue(initialIndex.inboxMaterials.contains { $0.id == draft.id })
        let preview = try await kitStore.loadMaterialDocument(id: draft.id)
        XCTAssertTrue(preview.markdown.contains("这是从 iOS 收件箱同步的文本。"))

        _ = try await kitStore.moveMaterials(
            ids: [draft.id],
            toKnowledgeBaseID: fixture.knowledgeBaseID
        )
        let finalIndex = try await kitStore.loadIndex()
        XCTAssertTrue(finalIndex.materials.contains { $0.id == draft.id })
        XCTAssertFalse(finalIndex.inboxMaterials.contains { $0.id == draft.id })
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.rootURL
                    .appending(path: "Inbox/\(draft.id.uuidString).inboxitem")
                    .path
            )
        )
        let material = try await kitStore.loadMaterialDocument(id: draft.id)
        XCTAssertEqual(material.summary.kind, .note)
        XCTAssertTrue(material.markdown.contains("这是从 iOS 收件箱同步的文本。"))
    }

    func testLegacyIOSAnnotationAndSessionJSONRemainReadableByStudyNotesKit() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let annotationID = UUID()
        let conversationID = UUID()
        let legacyAnnotation = """
        {
          "id": "\(annotationID.uuidString)",
          "materialID": "\(fixture.materialID.uuidString)",
          "anchor": {
            "type": "text",
            "text": {
              "quote": "工作记忆",
              "prefix": "记忆",
              "suffix": "是有限",
              "startOffset": 8,
              "endOffset": 12,
              "blockPath": "block-1"
            }
          },
          "note": "旧版 iOS 标注",
          "createdAt": "2026-11-03T00:00:00Z",
          "updatedAt": "2026-11-03T00:00:00Z",
          "resolution": "needsRecovery"
        }
        """
        let legacySession = """
        {
          "id": "\(conversationID.uuidString)",
          "materialID": "\(fixture.materialID.uuidString)",
          "providerName": "DeepSeek",
          "modelID": "deepseek-chat",
          "action": "总结",
          "scopeDescription": "整份材料",
          "createdAt": "2026-11-03T00:00:00Z",
          "updatedAt": "2026-11-03T00:00:00Z",
          "messages": [{
            "id": "\(UUID().uuidString)",
            "role": "assistant",
            "content": "旧版 iOS 会话",
            "createdAt": "2026-11-03T00:00:00Z"
          }]
        }
        """
        try FileManager.default.createDirectory(
            at: fixture.packageURL.appending(path: "annotations"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fixture.packageURL.appending(path: "ai"),
            withIntermediateDirectories: true
        )
        try Data(legacyAnnotation.utf8).write(
            to: fixture.packageURL
                .appending(path: "annotations/\(annotationID.uuidString).json")
        )
        try Data(legacySession.utf8).write(
            to: fixture.packageURL
                .appending(path: "ai/\(conversationID.uuidString).json")
        )

        let kitStore = StudyNotesStore(rootURL: fixture.rootURL)
        let annotations = try await kitStore.loadAnnotations(
            materialID: fixture.materialID
        )
        XCTAssertEqual(annotations.first?.id, annotationID)
        XCTAssertEqual(annotations.first?.anchor.kind, .text)
        XCTAssertEqual(annotations.first?.anchor.blockPath, [1])
        XCTAssertEqual(annotations.first?.note, "旧版 iOS 标注")
        let sessions = try await kitStore.loadConversations(
            materialID: fixture.materialID
        )
        XCTAssertEqual(sessions.first?.id, conversationID)
        XCTAssertEqual(sessions.first?.model, "deepseek-chat")
        XCTAssertEqual(sessions.first?.action, "总结")
        XCTAssertEqual(sessions.first?.scopeDescription, "整份材料")
        XCTAssertEqual(sessions.first?.origin, .summary)
    }

    func testUnreadableStudyFilesArePreservedWithDiagnostics() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let annotationsURL = fixture.packageURL.appending(path: "annotations")
        let aiURL = fixture.packageURL.appending(path: "ai")
        try FileManager.default.createDirectory(
            at: annotationsURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: aiURL,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: annotationsURL.appending(path: "\(UUID().uuidString).json")
        )
        try Data("not-json".utf8).write(
            to: aiURL.appending(path: "\(UUID().uuidString).json")
        )
        try Data("still-not-json".utf8).write(
            to: annotationsURL.appending(path: "\(UUID().uuidString).json")
        )
        try Data("still-not-json".utf8).write(
            to: aiURL.appending(path: "\(UUID().uuidString).json")
        )

        let iosStore = try StudyNotesIOSCore.IOSLibraryStore(rootURL: fixture.rootURL)
        _ = try await iosStore.loadAnnotations(
            materialID: fixture.materialID,
            sourceText: fixture.text
        )
        _ = try await iosStore.loadConversations(materialID: fixture.materialID)
        let kitStore = StudyNotesStore(rootURL: fixture.rootURL)
        _ = try await kitStore.loadAnnotations(materialID: fixture.materialID)
        _ = try await kitStore.loadConversations(materialID: fixture.materialID)

        XCTAssertGreaterThanOrEqual(
            try FileManager.default.contentsOfDirectory(
                at: annotationsURL.appending(path: "conflicts"),
                includingPropertiesForKeys: nil
            ).count { $0.pathExtension == "json" },
            2
        )
        XCTAssertGreaterThanOrEqual(
            try FileManager.default.contentsOfDirectory(
                at: aiURL.appending(path: "conflicts"),
                includingPropertiesForKeys: nil
            ).count { $0.pathExtension == "txt" },
            2
        )
    }

    func testAPIKeyStorageIsAlwaysLocalToThisDevice() throws {
        let provider = StudyNotesIOSCore.AIProvider(
            name: "Local",
            baseURL: "https://example.com/v1",
            modelID: "local-model",
            syncKeychain: true
        )
        XCTAssertFalse(provider.syncKeychain)

        let encoded = try StudyNotesIOSCore.StudyNotesFileSupport.encoder().encode(provider)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["syncKeychain"] as? Bool, false)

        let legacy = """
        {
          "id": "\(provider.id.uuidString)",
          "name": "Legacy",
          "baseURL": "https://example.com/v1",
          "modelID": "legacy-model",
          "syncKeychain": true
        }
        """
        let decoded = try StudyNotesIOSCore.StudyNotesFileSupport.decoder().decode(
            StudyNotesIOSCore.AIProvider.self,
            from: Data(legacy.utf8)
        )
        XCTAssertFalse(decoded.syncKeychain)

        let query = StudyNotesIOSCore.KeychainStore.baseQuery(
            service: "com.studynotes.test",
            account: provider.id.uuidString
        )
        let synchronizable = try XCTUnwrap(
            query[kSecAttrSynchronizable as String] as? NSNumber
        )
        XCTAssertFalse(synchronizable.boolValue)
    }

    private func makeFixture() throws -> CrossPlatformFixture {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "StudyNotesCrossPlatform-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let knowledgeBaseID = UUID()
        let materialID = UUID()
        let text = "# 记忆\n\n工作记忆是有限资源。"
        let libraryURL = rootURL
            .appending(path: "Libraries", directoryHint: .isDirectory)
            .appending(path: knowledgeBaseID.uuidString, directoryHint: .isDirectory)
        let packageURL = libraryURL
            .appending(path: "学习科学", directoryHint: .isDirectory)
            .appending(path: "\(materialID.uuidString).studyitem", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: packageURL.appending(path: "content", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let encoder = StudyNotesIOSCore.StudyNotesFileSupport.encoder()
        let knowledgeBase = StudyNotesIOSCore.KnowledgeBaseSummary(
            id: knowledgeBaseID,
            name: "学习科学",
            createdAt: Date()
        )
        try encoder.encode(knowledgeBase).write(
            to: libraryURL.appending(path: "knowledge-base.json")
        )
        let manifest = StudyNotesIOSCore.MaterialManifestRecord(
            id: materialID,
            knowledgeBaseID: knowledgeBaseID,
            kind: "note",
            title: "记忆与学习",
            createdAt: Date(),
            updatedAt: Date(),
            folderPath: "学习科学",
            tags: ["记忆"]
        )
        try encoder.encode(manifest).write(
            to: packageURL.appending(path: "manifest.json")
        )
        try Data(text.utf8).write(
            to: packageURL.appending(path: "content/note.md")
        )
        return CrossPlatformFixture(
            rootURL: rootURL,
            knowledgeBaseID: knowledgeBaseID,
            materialID: materialID,
            packageURL: packageURL,
            text: text
        )
    }
}

private struct CrossPlatformFixture {
    let rootURL: URL
    let knowledgeBaseID: UUID
    let materialID: UUID
    let packageURL: URL
    let text: String
}
