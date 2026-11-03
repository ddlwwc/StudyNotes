import Testing
@testable import StudyNotesKit

@Suite("Markdown title sync")
struct MarkdownTitleSyncTests {
    @Test("matching titles synchronize without changing the document")
    func matchingTitles() throws {
        let markdown = """
        ---
        title: 旧数据
        ---
        # 学习计划

        保留正文。
        """
        let sync = MarkdownTitleSync()

        let plan = try sync.plan(
            manifestTitle: "学习计划",
            markdown: markdown
        )

        #expect(plan == .synchronized(
            title: "学习计划",
            markdown: markdown
        ))
    }

    @Test("different legacy titles require confirmation")
    func titleMismatch() throws {
        let markdown = "# 正文中的旧标题\n\n后续内容"
        let sync = MarkdownTitleSync()

        let plan = try sync.plan(
            manifestTitle: "清单标题",
            markdown: markdown
        )

        #expect(plan == .confirmation(
            manifestTitle: "清单标题",
            headingTitle: "正文中的旧标题"
        ))
    }

    @Test("applying a title replaces or inserts only the first level-one heading")
    func applyTitle() throws {
        let sync = MarkdownTitleSync()
        let existing = """
        ---
        title: 元数据
        ---
        # 旧标题

        第一段。

        ## 小标题
        """
        let inserted = """
        ---
        title: 元数据
        ---
        正文。

        ## 后面的标题
        """

        #expect(try sync.applying(title: "新标题", to: existing) == """
        ---
        title: 元数据
        ---
        # 新标题

        第一段。

        ## 小标题
        """)
        #expect(try sync.applying(title: "新标题", to: inserted) == """
        ---
        title: 元数据
        ---
        # 新标题

        正文。

        ## 后面的标题
        """)
    }

    @Test("recognizes a level-one heading with CommonMark indentation")
    func indentedHeading() throws {
        let sync = MarkdownTitleSync()

        #expect(
            try sync.plan(
                manifestTitle: "新标题",
                markdown: "   # 旧标题\n\n正文"
            ) == .confirmation(
                manifestTitle: "新标题",
                headingTitle: "旧标题"
            )
        )
    }
}
