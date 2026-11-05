import AppKit
import CoreText
import Foundation
import PDFKit
import Testing
@testable import StudyNotesKit

@Suite("Mac material reading and study layer")
struct MaterialReadingTests {
    @Test("markdown import keeps its source immutable and restores ten recent versions")
    func markdownImportAndVersions() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "阅读")
        let fileURL = directory.url.appending(path: "文章.md")
        let original = "# 原文\n\n第一版正文"
        try Data(original.utf8).write(to: fileURL)

        let batch = try await store.importFiles(
            at: [fileURL],
            knowledgeBaseID: knowledgeBase.id,
            tags: ["导入"]
        )
        #expect(batch.importedCount == 1)
        let first = try #require(batch.results.first)
        #expect(first.summary.kind == .markdown)
        #expect(first.summary.title == "原文")

        let duplicate = try await store.importFiles(
            at: [fileURL],
            knowledgeBaseID: knowledgeBase.id
        )
        #expect(duplicate.duplicateCount == 1)
        #expect(duplicate.results.first?.duplicateOf == first.summary.id)

        let packageURL = try materialPackageURL(
            id: first.summary.id,
            knowledgeBaseID: knowledgeBase.id,
            rootURL: directory.url
        )
        let sourceURL = packageURL
            .appending(path: "source")
            .appending(path: "original.md")
        for index in 0..<12 {
            _ = try await store.saveReaderCopy(
                id: first.summary.id,
                text: "# 原文\n\n第 \(index + 2) 版正文"
            )
        }

        #expect(try String(contentsOf: sourceURL, encoding: .utf8) == original)
        let revisions = try await store.loadTextRevisions(id: first.summary.id)
        #expect(revisions.count == 10)
        let restored = try await store.restoreRevision(
            id: first.summary.id,
            revisionID: try #require(revisions.last?.id)
        )
        #expect(restored.text == revisions.last?.text)
        let document = try await store.loadMaterialDocument(id: first.summary.id)
        #expect(document.markdown == restored.text)
    }

    @Test("editor saves can update the manifest title without creating autosave versions")
    func editorSaveUpdatesTitleAndControlsRecoveryVersions() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "编辑")
        let note = try await store.createMarkdownNote(
            title: "旧标题",
            in: knowledgeBase.id,
            markdown: "# 旧标题\n\n第一版"
        )

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: "# 新标题\n\n自动保存",
            title: "新标题",
            createRecoveryVersion: false
        )

        var document = try await store.loadMaterialDocument(
            id: note.summary.id
        )
        #expect(document.summary.title == "新标题")
        #expect(document.markdown == "# 新标题\n\n自动保存")
        #expect(try await store.loadTextRevisions(id: note.summary.id).count == 1)

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: "# 新标题\n\n显式保存",
            title: "新标题",
            createRecoveryVersion: true
        )

        document = try await store.loadMaterialDocument(id: note.summary.id)
        #expect(document.markdown == "# 新标题\n\n显式保存")
        #expect(try await store.loadTextRevisions(id: note.summary.id).count == 2)
    }

    @Test("HTML import removes navigation and shares one clean article view")
    func htmlImportCleansArticle() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "网页")
        let fileURL = directory.url.appending(path: "fixture.html")
        try Data(
            """
            <html><head><title>清洗后的标题</title></head><body>
            <nav>导航内容</nav>
            <article><h1>清洗后的标题</h1><p>正文第一段。</p><h2>小节</h2><p>正文第二段。</p></article>
            <footer>页脚内容</footer>
            </body></html>
            """.utf8
        ).write(to: fileURL)

        let result = try #require(
            try await store.importFiles(
                at: [fileURL],
                knowledgeBaseID: knowledgeBase.id
            ).results.first
        )
        let document = try await store.loadMaterialDocument(id: result.summary.id)

        #expect(result.summary.kind == .html)
        #expect(document.markdown.contains("正文第一段"))
        #expect(!document.markdown.contains("导航内容"))
        #expect(!document.markdown.contains("页脚内容"))
        #expect(
            document.renderedHTML.contains(
                "<h2 id=\"heading-1\" data-element-type=\"heading\" data-block-path=\"2\">小节</h2>"
            )
        )
        #expect(document.headings.map(\.title) == ["清洗后的标题", "小节"])
    }

    @Test("GFM tables render header cells and column alignment")
    func gfmTableRendering() {
        let content = ReaderContentBuilder.build(
            markdown: """
            | 名称 | 数量 | 说明 |
            | :--- | ---: | :---: |
            | Alpha | 42 | **重点** |
            | Beta | 7 | `inline` |
            """,
            title: "表格阅读"
        )

        #expect(content.html.contains("<table"))
        #expect(content.html.contains("<thead>"))
        #expect(content.html.contains("<th align=\"left\">名称</th>"))
        #expect(content.html.contains("<th align=\"right\">数量</th>"))
        #expect(content.html.contains("<th align=\"center\">说明</th>"))
        #expect(content.html.contains("<td align=\"right\">42</td>"))
        #expect(content.html.contains("<strong>重点</strong>"))
        #expect(content.html.contains("<code>inline</code>"))
        #expect(
            !content.html.contains(
                "border: 1px solid #d1d5db; text-align: left;"
            )
        )
    }

    @Test("reader HTML exposes stable paths for annotatable elements")
    func readerElementAnchorMetadata() {
        let content = ReaderContentBuilder.build(
            markdown: """
            # 标题

            开头段落。

            ---

            - 列表 A
            - 列表 B

            ![架构图](media://diagram.png)

            | 名称 | 数量 |
            | --- | --- |
            | Alpha | 42 |

            ```swift
            let value = 42
            ```
            """,
            title: "元素"
        )

        #expect(content.html.contains("data-element-type=\"heading\" data-block-path=\"0\""))
        #expect(content.html.contains("data-element-type=\"paragraph\" data-block-path=\"1\""))
        #expect(content.html.contains("data-element-type=\"listItem\" data-block-path=\"3/1\""))
        #expect(content.html.contains("data-element-type=\"image\" data-block-path=\"4/0\""))
        #expect(content.html.contains("data-element-type=\"table\" data-block-path=\"5\""))
        #expect(content.html.contains("data-element-type=\"codeBlock\" data-block-path=\"6\""))
    }

    @Test("PDF and image imports reopen with native metadata and unchanged source bytes")
    func pdfAndImageImport() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "原生阅读")
        let pdfURL = directory.url.appending(path: "text.pdf")
        let imageURL = directory.url.appending(path: "diagram.png")
        let pdfData = try makeTextPDF(text: "PDF 文本层")
        let imageData = try makePNG()
        try pdfData.write(to: pdfURL)
        try imageData.write(to: imageURL)

        let batch = try await store.importFiles(
            at: [pdfURL, imageURL],
            knowledgeBaseID: knowledgeBase.id
        )
        #expect(Set(batch.results.map(\.summary.kind)) == Set([.pdf, .image]))
        let pdfResult = try #require(batch.results.first { $0.summary.kind == .pdf })
        let imageResult = try #require(batch.results.first { $0.summary.kind == .image })

        let reopenedPDF = try await store.loadMaterialDocument(id: pdfResult.summary.id)
        let reopenedImage = try await store.loadMaterialDocument(id: imageResult.summary.id)
        #expect(reopenedPDF.pageCount == 1)
        #expect(reopenedPDF.hasTextLayer == true)
        #expect(reopenedImage.sourceFileURL?.pathExtension == "png")
        #expect(try Data(contentsOf: try #require(reopenedPDF.sourceFileURL)) == pdfData)
        #expect(try Data(contentsOf: try #require(reopenedImage.sourceFileURL)) == imageData)
    }

    @Test("controlled web fixture produces a local, offline-readable article")
    func webArticleFetchLocalizesMedia() async throws {
        let pageURL = URL(string: "https://example.com/article")!
        let imageURL = URL(string: "https://example.com/image.png")!
        let png = try makePNG()
        let fetcher = WebArticleFetcher { request in
            if request.url == pageURL {
                let html = """
                <html><head><title>离线网页</title></head><body>
                <nav>无关导航</nav>
                <article><h1>离线网页</h1><p>正文引用图片。</p>
                <img src="\(imageURL.absoluteString)" alt="本地图"></article>
                </body></html>
                """
                return (
                    Data(html.utf8),
                    HTTPURLResponse(
                        url: pageURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "text/html; charset=utf-8"]
                    )!
                )
            }
            return (
                png,
                HTTPURLResponse(
                    url: imageURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )!
            )
        }
        let draft = try await fetcher.fetch(url: pageURL)
        #expect(draft.title == "离线网页")
        #expect(draft.media.count == 1)
        #expect(!draft.markdown.contains("无关导航"))

        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "网页")
        let result = try await store.importWebArticle(
            draft,
            title: draft.title,
            markdown: draft.markdown,
            knowledgeBaseID: knowledgeBase.id
        )
        #expect(result.summary.kind == .webArticle)
        #expect(result.summary.originalSourceURL == pageURL)
        let document = try await store.loadMaterialDocument(id: result.summary.id)
        #expect(document.markdown.contains("正文引用图片"))
        #expect(document.mediaURLs["image-01.png"] != nil)
        #expect(document.renderedHTML.contains("正文引用图片"))
    }

    @Test("text annotations update in place and become unresolved after content changes")
    func textAnnotationResolution() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "标注")
        let note = try await store.createMarkdownNote(
            title: "认知负荷",
            in: knowledgeBase.id,
            markdown: "工作记忆有限。有效设计应降低无关负荷，并留出生成性加工空间。"
        )
        let anchor = AnnotationAnchor(
            kind: .text,
            excerpt: "有效设计应降低无关负荷",
            prefix: "工作记忆有限。",
            suffix: "，并留出",
            offset: 7
        )
        let first = try await store.upsertAnnotation(
            MaterialAnnotation(
                materialID: note.summary.id,
                anchor: anchor,
                quote: anchor.excerpt,
                note: "关键论点"
            )
        )
        let updated = try await store.upsertAnnotation(
            MaterialAnnotation(
                materialID: note.summary.id,
                anchor: anchor,
                quote: anchor.excerpt,
                note: "更新后的备注"
            )
        )
        #expect(updated.id == first.id)
        #expect(try await store.loadAnnotations(materialID: note.summary.id).count == 1)

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: "新增开头。\n\n工作记忆有限。有效设计应降低无关负荷，并留出生成性加工空间。"
        )
        let refreshed = try #require(
            try await store.loadAnnotations(materialID: note.summary.id).first
        )
        #expect(refreshed.status == .active)
        #expect(refreshed.anchor.offset == 14)
        #expect(refreshed.anchor.blockPath == [1])
        #expect(refreshed.anchor.contentSummary == anchor.excerpt)

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: "内容已经完全不同。"
        )
        let unresolved = try #require(
            try await store.loadAnnotations(materialID: note.summary.id).first
        )
        #expect(unresolved.status == .unresolved)
        #expect(unresolved.note == "更新后的备注")
    }

    @Test("element annotations recover after block shifts and become unresolved after edits")
    func elementAnnotationResolution() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "元素标注")
        let target = "这是目标段落，包含关键结论。"
        let note = try await store.createMarkdownNote(
            title: "恢复",
            in: knowledgeBase.id,
            markdown: """
            # 概览

            前置段落。

            \(target)

            中间段落。

            \(target)

            - 列表项
            """
        )
        let anchor = AnnotationAnchor(
            kind: .text,
            prefix: "前置段落。",
            suffix: "中间段落。",
            blockPath: [2],
            elementType: .paragraph,
            contentFingerprint: ContentFingerprint.sha256(target),
            contentSummary: target
        )
        _ = try await store.upsertAnnotation(
            MaterialAnnotation(
                materialID: note.summary.id,
                anchor: anchor,
                quote: target,
                note: "整段备注"
            )
        )
        #expect(
            try await store.loadAnnotations(materialID: note.summary.id).first?.status
                == .active
        )

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: """
            # 概览

            新增一段。

            前置段落。

            \(target)

            中间段落。

            \(target)

            - 列表项
            """
        )
        #expect(
            try await store.loadAnnotations(materialID: note.summary.id).first?.status
                == .active
        )

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: """
            # 概览

            新增一段。

            前置段落。

            这是已经改写的目标段落。

            中间段落。

            \(target)

            - 列表项
            """
        )
        let unresolved = try #require(
            try await store.loadAnnotations(materialID: note.summary.id).first
        )
        #expect(unresolved.status == .unresolved)
        #expect(unresolved.note == "整段备注")
    }

    @Test("all element annotation types recover through summaries after block shifts")
    func allElementAnnotationTypesResolve() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "全部元素")
        let note = try await store.createMarkdownNote(
            title: "元素",
            in: knowledgeBase.id,
            markdown: """
            # 标题

            开头段落。

            > 引用内容。

            - 列表 A
            - 列表 B

            ![架构图](media://diagram.png)

            | 名称 | 数量 |
            | --- | --- |
            | Alpha | 42 |

            ```swift
            let value = 42
            ```
            """
        )
        let anchors: [(AnnotationElementType, [Int], String)] = [
            (.heading, [0], "标题"),
            (.paragraph, [1], "开头段落。"),
            (.blockquote, [2], "引用内容。"),
            (.listItem, [3, 1], "列表 B"),
            (.image, [4, 0], "架构图"),
            (.table, [5], "名称 | 数量 / Alpha | 42"),
            (.codeBlock, [6], "let value = 42")
        ]
        for (type, path, summary) in anchors {
            _ = try await store.upsertAnnotation(
                MaterialAnnotation(
                    materialID: note.summary.id,
                    anchor: AnnotationAnchor(
                        kind: .text,
                        blockPath: path,
                        elementType: type,
                        contentSummary: summary
                    ),
                    quote: summary,
                    note: type.rawValue
                )
            )
        }
        #expect(try await store.loadAnnotations(materialID: note.summary.id).count == anchors.count)

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: """
            # 标题

            插入段落。

            开头段落。

            > 引用内容。

            - 列表 A
            - 列表 B

            ![架构图](media://diagram.png)

            | 名称 | 数量 |
            | --- | --- |
            | Alpha | 42 |

            ```swift
            let value = 42
            ```
            """
        )
        let annotations = try await store.loadAnnotations(materialID: note.summary.id)
        #expect(annotations.count == anchors.count)
        #expect(annotations.allSatisfy { $0.status == .active })
    }

    @Test("images in every block family keep canonical anchors")
    func nestedImageAnchors() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "图片")
        let markdown = """
        # ![标题图](media://heading.png)

        > ![引用图](media://quote.png)

        - ![列表图](media://list.png)

        | ![](media://table.png) | 值 |
        | --- | --- |
        | A | 1 |
        """
        let note = try await store.createMarkdownNote(
            title: "图片",
            in: knowledgeBase.id,
            markdown: markdown
        )
        let anchors: [([Int], String)] = [
            ([0, 0], "标题图"),
            ([1, 0], "引用图"),
            ([2, 0, 0], "列表图"),
            ([3, 0], "media://table.png")
        ]
        for (path, summary) in anchors {
            _ = try await store.upsertAnnotation(
                MaterialAnnotation(
                    materialID: note.summary.id,
                    anchor: AnnotationAnchor(
                        kind: .text,
                        blockPath: path,
                        elementType: .image,
                        contentSummary: summary
                    ),
                    quote: summary,
                    note: "图片备注"
                )
            )
        }
        let initialAnnotations = try await store.loadAnnotations(
            materialID: note.summary.id
        )
        #expect(initialAnnotations.allSatisfy { $0.status == .active })

        let content = ReaderContentBuilder.build(
            markdown: markdown,
            title: "图片"
        )
        #expect(content.html.contains("data-block-path=\"0/0\""))
        #expect(content.html.contains("data-block-path=\"1/0\""))
        #expect(content.html.contains("data-block-path=\"2/0/0\""))
        #expect(content.html.contains("data-block-path=\"3/0\""))

        _ = try await store.saveReaderCopy(
            id: note.summary.id,
            text: "插入段落。\n\n\(markdown)"
        )
        #expect(
            try await store.loadAnnotations(materialID: note.summary.id)
                .allSatisfy { $0.status == .active }
        )
    }

    @Test("element anchors persist as compatible text anchors")
    func elementAnchorPersistence() throws {
        let anchor = AnnotationAnchor(
            kind: .text,
            prefix: "前一段",
            suffix: "后一段",
            blockPath: [2, 1],
            elementType: .table,
            contentFingerprint: "sha256:table-content",
            contentSummary: "名称、数量与说明"
        )
        let annotation = MaterialAnnotation(
            materialID: UUID(),
            anchor: anchor,
            quote: anchor.contentSummary ?? "",
            note: "表格备注"
        )

        let data = try CrossPlatformJSON.encoder().encode(annotation)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let anchorJSON = try #require(json["anchor"] as? [String: Any])
        #expect(anchorJSON["kind"] as? String == "text")
        #expect(anchorJSON["elementType"] as? String == "table")
        #expect(anchorJSON["contentFingerprint"] as? String == "sha256:table-content")
        #expect(anchorJSON["contentSummary"] as? String == "名称、数量与说明")

        let decoded = try CrossPlatformJSON.decoder().decode(
            MaterialAnnotation.self,
            from: data
        )
        #expect(decoded.anchor == anchor)
    }

    @Test("legacy text image and PDF anchors remain readable")
    func legacyAnchorCompatibility() throws {
        let decoder = CrossPlatformJSON.decoder()
        let text = try decoder.decode(
            CrossPlatformAnnotationAnchor.self,
            from: Data(
                """
                {
                  "type": "text",
                  "text": {
                    "quote": "旧文字",
                    "prefix": "前",
                    "suffix": "后",
                    "startOffset": 3,
                    "endOffset": 6,
                    "blockPath": "1/2"
                  }
                }
                """.utf8
            )
        )
        let image = try decoder.decode(
            CrossPlatformAnnotationAnchor.self,
            from: Data(
                """
                {
                  "type": "imageRectangle",
                  "rectangle": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4}
                }
                """.utf8
            )
        )
        let pdf = try decoder.decode(
            CrossPlatformAnnotationAnchor.self,
            from: Data(
                """
                {
                  "type": "pageRectangle",
                  "page": 2,
                  "rectangle": {"x": 0.2, "y": 0.1, "width": 0.5, "height": 0.6}
                }
                """.utf8
            )
        )

        #expect(text.kind == .text)
        #expect(text.blockPath == [1, 2])
        #expect(text.offset == 3)
        #expect(text.elementType == nil)
        #expect(text.contentFingerprint == nil)
        #expect(text.contentSummary == nil)
        #expect(image.kind == .imageRect)
        #expect(pdf.kind == .pdfPageRect)
        #expect(pdf.pageIndex == 2)
    }

    @Test("image and PDF page annotations round-trip normalized coordinates")
    func mediaAnnotationCoordinates() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "媒体标注")
        let imageURL = directory.url.appending(path: "image.png")
        let pdfURL = directory.url.appending(path: "image-only.pdf")
        try makePNG().write(to: imageURL)
        try makeImagePDF().write(to: pdfURL)
        let batch = try await store.importFiles(
            at: [imageURL, pdfURL],
            knowledgeBaseID: knowledgeBase.id
        )
        let image = try #require(batch.results.first { $0.summary.kind == .image })
        let pdf = try #require(batch.results.first { $0.summary.kind == .pdf })

        let imageAnnotation = try await store.upsertAnnotation(
            MaterialAnnotation(
                materialID: image.summary.id,
                anchor: AnnotationAnchor(
                    kind: .imageRect,
                    rect: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
                ),
                quote: "",
                note: "图片区域"
            )
        )
        let pdfAnnotation = try await store.upsertAnnotation(
            MaterialAnnotation(
                materialID: pdf.summary.id,
                anchor: AnnotationAnchor(
                    kind: .pdfPageRect,
                    pageIndex: 0,
                    rect: NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.2)
                ),
                quote: "",
                note: "扫描页区域"
            )
        )
        #expect(imageAnnotation.anchor.rect?.width == 0.3)
        #expect(pdfAnnotation.anchor.pageIndex == 0)
        #expect(
            try await store.loadAnnotations(materialID: image.summary.id).first?.status
                == .active
        )
        #expect(
            try await store.loadAnnotations(materialID: pdf.summary.id).first?.status
                == .active
        )
    }

    @Test("notes link to many materials and AI results can be promoted")
    func linksConversationsAndPromotion() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "关联")
        let note = try await store.createMarkdownNote(
            title: "主笔记",
            in: knowledgeBase.id,
            markdown: "主笔记正文"
        )
        let first = try await store.createMarkdownNote(
            title: "材料一",
            in: knowledgeBase.id,
            markdown: "材料一"
        )
        let second = try await store.createMarkdownNote(
            title: "材料二",
            in: knowledgeBase.id,
            markdown: "材料二"
        )
        let linked = try await store.setLinkedMaterials(
            for: note.summary.id,
            linkedMaterialIDs: [first.summary.id, second.summary.id]
        )
        #expect(Set(linked.linkedMaterialIDs) == Set([first.summary.id, second.summary.id]))

        let conversation = try await store.saveConversation(
            AIConversation(
                materialID: note.summary.id,
                title: "解释主笔记",
                origin: .selection,
                originAnchor: AnnotationAnchor(
                    kind: .text,
                    excerpt: "主笔记正文",
                    offset: 0
                ),
                messages: [
                    AIMessage(role: .user, content: "请总结"),
                    AIMessage(role: .assistant, content: "这是一段可以提升的学习结论。")
                ],
                providerName: "测试供应商",
                model: "test-model"
            )
        )
        let conversations = try await store.loadConversations(materialID: note.summary.id)
        #expect(conversations.count == 1)
        var continued = conversation
        continued.title = "继续追问"
        continued.messages.append(
            AIMessage(role: .user, content: "继续解释这个结论")
        )
        continued.messages.append(
            AIMessage(role: .assistant, content: "这是继续追问后的回答。")
        )
        _ = try await store.saveConversation(continued)
        let continuedConversations = try await store.loadConversations(
            materialID: note.summary.id
        )
        #expect(continuedConversations.first?.title == "继续追问")
        #expect(
            continuedConversations.first?.messages.map(\.content) == [
                "请总结",
                "这是一段可以提升的学习结论。",
                "继续解释这个结论",
                "这是继续追问后的回答。"
            ]
        )
        let assistant = try #require(
            conversations.first?.messages.first { $0.role == .assistant }
        )
        let promotion = try await store.promoteAIResult(
            conversationID: conversation.id,
            messageID: assistant.id,
            materialID: note.summary.id,
            target: .note,
            knowledgeBaseID: knowledgeBase.id
        )
        let promoted = try await store.loadMaterialDocument(id: promotion.material.id)
        #expect(promoted.markdown == assistant.content)

        let annotationPromotion = try await store.promoteAIResult(
            conversationID: conversation.id,
            messageID: assistant.id,
            materialID: note.summary.id,
            target: .annotation,
            knowledgeBaseID: knowledgeBase.id
        )
        #expect(annotationPromotion.annotation?.note == assistant.content)
        #expect(try await store.loadAnnotations(materialID: note.summary.id).count == 1)

        let materialPromotion = try await store.promoteAIResult(
            conversationID: conversation.id,
            messageID: assistant.id,
            materialID: note.summary.id,
            target: .material,
            knowledgeBaseID: knowledgeBase.id
        )
        let independent = try await store.loadMaterialDocument(
            id: materialPromotion.material.id
        )
        #expect(independent.markdown == assistant.content)

        try await store.deleteConversation(
            id: conversation.id,
            materialID: note.summary.id
        )
        #expect(try await store.loadConversations(materialID: note.summary.id).isEmpty)
    }

    @Test("FTS5 trigram search supports Chinese, filters, rebuild, and corruption recovery")
    func fullTextSearch() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let indexURL = directory.url.appending(path: "derived/search.sqlite")
        let store = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: indexURL
        )
        let knowledgeBase = try await store.createKnowledgeBase(named: "搜索")
        let note = try await store.createMarkdownNote(
            title: "学习科学",
            in: knowledgeBase.id,
            markdown: "认知负荷理论关注工作记忆的有限容量。",
            tags: ["认知"]
        )
        _ = try await store.upsertAnnotation(
            MaterialAnnotation(
                materialID: note.summary.id,
                anchor: AnnotationAnchor(
                    kind: .text,
                    excerpt: "认知负荷理论",
                    offset: 0
                ),
                quote: "认知负荷理论",
                note: "关键术语"
            )
        )
        _ = try await store.saveConversation(
            AIConversation(
                materialID: note.summary.id,
                title: "AI 结果",
                origin: .summary,
                messages: [
                    AIMessage(role: .assistant, content: "生成性加工需要在工作记忆中建立图式。")
                ],
                providerName: "测试供应商",
                model: "test-model"
            )
        )

        let longHits = try await store.search("认知负荷理论")
        #expect(longHits.contains { $0.materialID == note.summary.id })
        let shortHits = try await store.search("认知")
        #expect(shortHits.contains { $0.materialID == note.summary.id })
        let aiHits = try await store.search("生成性加工")
        #expect(aiHits.first?.matchedLayer == .ai)
        let filtered = try await store.search(
            "认知",
            filter: SearchFilter(knowledgeBaseID: knowledgeBase.id, kind: .note, tag: "认知")
        )
        #expect(filtered.count == 1)
        let wrongFilter = try await store.search(
            "认知",
            filter: SearchFilter(kind: .pdf)
        )
        #expect(wrongFilter.isEmpty)

        let rebuiltStore = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: indexURL
        )
        #expect(try await rebuiltStore.search("工作记忆").isEmpty == false)
        try Data("not sqlite".utf8).write(to: indexURL, options: .atomic)
        let recoveredStore = StudyNotesStore(
            rootURL: directory.url,
            derivedDataURL: indexURL
        )
        #expect(try await recoveredStore.search("认知负荷").isEmpty == false)
    }

    @Test("publish preview hides the study layer until explicitly enabled")
    func publishPreviewPrivacy() async throws {
        let directory = try TestDirectory()
        defer { directory.remove() }
        let store = try await makeStore(in: directory.url)
        let knowledgeBase = try await store.createKnowledgeBase(named: "发布")
        let note = try await store.createMarkdownNote(
            title: "公开文章",
            in: knowledgeBase.id,
            markdown: "这是公开正文。"
        )
        let annotationAnchor = AnnotationAnchor(
            kind: .text,
            excerpt: "公开正文",
            offset: 3
        )
        _ = try await store.upsertAnnotation(
            MaterialAnnotation(
                materialID: note.summary.id,
                anchor: annotationAnchor,
                quote: "公开正文",
                note: "私人标注备注"
            )
        )
        _ = try await store.saveConversation(
            AIConversation(
                materialID: note.summary.id,
                title: "私人研读",
                origin: .summary,
                messages: [
                    AIMessage(role: .assistant, content: "私人 AI 研读结论")
                ],
                providerName: "测试供应商",
                model: "test-model"
            )
        )

        let hidden = try await store.publishPreview(materialID: note.summary.id)
        #expect(!hidden.includeAnnotations)
        #expect(!hidden.includeAI)
        #expect(!hidden.html.contains("私人标注备注"))
        #expect(!hidden.html.contains("私人 AI 研读结论"))

        let visible = try await store.publishPreview(
            materialID: note.summary.id,
            includeAnnotations: true,
            includeAI: true
        )
        #expect(visible.html.contains("私人标注备注"))
        #expect(visible.html.contains("私人 AI 研读结论"))
        #expect(visible.contentFingerprint != hidden.contentFingerprint)

        let mapping = PublishMapping(
            articleID: "article-1",
            publicURL: URL(string: "https://example.com/a/article-1")!,
            lastPublishedVersion: "version-1",
            visibility: .publicArticle,
            contentFingerprint: visible.contentFingerprint,
            updatedAt: Date()
        )
        let updated = try await store.savePublishMapping(
            materialID: note.summary.id,
            mapping: mapping
        )
        #expect(updated.publishMapping == mapping)
    }

    @Test("SSE parser yields deltas and completion without retrying")
    func sseParser() {
        #expect(
            SSEParser.event(
                from: #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
            ) == .delta("你好")
        )
        #expect(SSEParser.event(from: "data: [DONE]") == .completed)
        #expect(SSEParser.event(from: "event: message") == nil)
    }

    @Test("text anchors use block path to disambiguate repeated excerpts")
    func textAnchorBlockPath() throws {
        let text = "前言\n\n第一段重复摘录，前文甲。\n\n第二段重复摘录，前文乙。"
        let anchor = AnnotationAnchor(
            kind: .text,
            excerpt: "重复摘录",
            prefix: "第二段",
            suffix: "，前文乙",
            offset: 0,
            blockPath: [2]
        )
        let range = try #require(TextAnchorResolver.range(for: anchor, in: text))
        let matched = (text as NSString).substring(with: range)
        #expect(matched == "重复摘录")
        #expect(range.location > (text as NSString).range(of: "第一段").location)
    }
}

private func makeStore(in rootURL: URL) async throws -> StudyNotesStore {
    StudyNotesStore(
        rootURL: rootURL,
        derivedDataURL: rootURL.appending(path: "derived/search.sqlite")
    )
}

private func materialPackageURL(
    id: UUID,
    knowledgeBaseID: UUID,
    folderPath: String = "",
    rootURL: URL
) throws -> URL {
    var directory = rootURL
        .appending(path: "Libraries")
        .appending(path: knowledgeBaseID.uuidString)
    if !folderPath.isEmpty {
        directory.append(path: folderPath)
    }
    let url = directory.appending(path: "\(id.uuidString).studyitem")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw TestFixtureError.missingPackage
    }
    return url
}

private func makePNG() throws -> Data {
    let image = NSImage(size: NSSize(width: 320, height: 200))
    image.lockFocus()
    NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.9, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 320, height: 200).fill()
    NSColor.white.setFill()
    NSRect(x: 40, y: 40, width: 160, height: 100).fill()
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

private func makeImagePDF() throws -> Data {
    let imageData = try makePNG()
    let image = NSImage(data: imageData)
    let document = PDFDocument()
    let requiredImage = try #require(image)
    let page = try #require(PDFPage(image: requiredImage))
    document.insert(page, at: 0)
    return try #require(document.dataRepresentation())
}

private func makeTextPDF(text: String) throws -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let consumer = try #require(CGDataConsumer(data: data))
    let context = try #require(
        CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        )
    )
    context.beginPDFPage(nil)
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
    )
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let path = CGPath(rect: CGRect(x: 72, y: 680, width: 468, height: 80), transform: nil)
    let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: 0, length: attributed.length),
        path,
        nil
    )
    CTFrameDraw(frame, context)
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

private struct TestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "StudyNotesMaterialTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum TestFixtureError: Error {
    case missingPackage
}
