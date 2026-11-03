import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Markdown editor codec")
struct MarkdownEditorCodecTests {
    @Test("round-trips basic Chinese Markdown blocks")
    func basicRoundTrip() throws {
        let source = """
        # 学习计划

        这是第一段。

        ```swift
        let title = "笔记"
        ```

        | 项目 | 状态 |
        | --- | --- |
        | 阅读 | 未开始 |

        - [ ] 阅读
        - [x] 整理
        """
            .replacingOccurrences(of: "\n", with: "\r\n")
        let expected = source.replacingOccurrences(of: "\r\n", with: "\n")
        let codec = MarkdownEditorCodec()

        let document = try codec.decode(source)

        #expect(document.markdown == expected)
        #expect(try codec.encode(document) == expected)
    }

    @Test("preserves compatibility blocks without rewriting their source")
    func compatibilityBlocks() throws {
        let source = """
        ---
        title: 旧标题
        ---
        # 学习

        正文引用[^note]。

        <aside class="warning">
        原始 HTML
        </aside>

        ~~~mermaid
        graph TD
          A --> B
        ~~~

        [^note]: 脚注内容
        """
        let codec = MarkdownEditorCodec()

        let document = try codec.decode(source)

        #expect(document.compatibilityBlocks.map(\.kind) == [
            .frontMatter,
            .footnoteReference,
            .rawHTML,
            .unknownFencedBlock,
            .footnoteDefinition
        ])
        #expect(try codec.encode(document) == source)
    }

    @Test("rejects ambiguous source with a specific error reason")
    func rejectsLossySource() {
        let codec = MarkdownEditorCodec()

        do {
            _ = try codec.decode("---\ntitle: 缺少结束行")
            Issue.record("Expected invalid Front Matter to fail")
        } catch let error as MarkdownEditorCodecError {
            #expect(error == .invalidFrontMatter(line: 1))
            #expect(error.localizedDescription.contains("Front Matter"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try codec.decode("```swift\nlet value = 1")
            Issue.record("Expected an unclosed fence to fail")
        } catch let error as MarkdownEditorCodecError {
            #expect(error == .unclosedFence(line: 1))
            #expect(error.localizedDescription.contains("围栏块"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let missingBlock = MarkdownEditorDocument(
            markdown: "只剩正文",
            compatibilityBlocks: [
                MarkdownCompatibilityBlock(
                    kind: .rawHTML,
                    source: "<aside>兼容内容</aside>",
                    startLine: 1,
                    endLine: 1
                )
            ]
        )
        do {
            _ = try codec.encode(missingBlock)
            Issue.record("Expected a lost compatibility block to fail")
        } catch let error as MarkdownEditorCodecError {
            #expect(error == .lostCompatibilityBlock("rawHTML"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("rejects removing one of two identical compatibility blocks")
    func duplicateCompatibilityBlocksMustRemainIntact() throws {
        let codec = MarkdownEditorCodec()
        let source = """
        <aside>同一段原始 HTML</aside>

        正文

        <aside>同一段原始 HTML</aside>
        """
        let document = try codec.decode(source)
        let removedOne = MarkdownEditorDocument(
            markdown: "<aside>同一段原始 HTML</aside>\n\n正文",
            compatibilityBlocks: document.compatibilityBlocks
        )

        do {
            _ = try codec.encode(removedOne)
            Issue.record("Expected duplicate compatibility loss to fail")
        } catch let error as MarkdownEditorCodecError {
            #expect(error == .lostCompatibilityBlock("rawHTML"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
