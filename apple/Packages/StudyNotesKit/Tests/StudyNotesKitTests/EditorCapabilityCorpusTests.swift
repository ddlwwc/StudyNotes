import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Frozen Mac editor capability corpus")
struct EditorCapabilityCorpusTests {
    @Test("capability IDs are unique and every required item has a test")
    func matrixIsFrozenAndActionable() throws {
        let data = try Data(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../../../../contracts/editor-capabilities.json")
        )
        let matrix = try JSONDecoder().decode(Matrix.self, from: data)

        #expect(matrix.version == 1)
        #expect(!matrix.capabilities.isEmpty)
        #expect(
            Set(matrix.capabilities.map(\.id)).count
                == matrix.capabilities.count
        )
        for capability in matrix.capabilities {
            #expect(
                capability.id.range(
                    of: #"^ED-[A-Z]+-[0-9]{2}$"#,
                    options: .regularExpression
                ) != nil
            )
            #expect(!capability.entry.isEmpty)
            #expect(!capability.disabledWhen.isEmpty)
            #expect(!capability.test.isEmpty)
            if capability.status == .required {
                #expect(!capability.states.isEmpty)
            }
        }
    }

    @Test("fixed editor corpora load without online services")
    func corporaLoad() throws {
        let markdown = try String(
            contentsOf: try fixtureURL("core", extension: "md"),
            encoding: .utf8
        )
        let html = try String(
            contentsOf: try fixtureURL("compatibility", extension: "html"),
            encoding: .utf8
        )
        let bypass = try JSONDecoder().decode(
            BypassCorpus.self,
            from: Data(
                contentsOf: try fixtureURL(
                    "bypass-blocks",
                    extension: "json"
                )
            )
        )
        let interactions = try JSONDecoder().decode(
            InteractionCorpus.self,
            from: Data(
                contentsOf: try fixtureURL(
                    "interactions",
                    extension: "json"
                )
            )
        )
        let decoded = try MarkdownEditorCodec().decode(markdown)

        #expect(decoded.compatibilityBlocks.count >= 4)
        #expect(html.contains("<script>"))
        #expect(Set(bypass.blocks.map(\.id)).count == bypass.blocks.count)
        #expect(bypass.blocks.allSatisfy { $0.version == 1 })
        #expect(interactions.scenarios.contains {
            $0.id == "transaction-recovery"
        })
        #expect(!markdown.contains("https://cdn."))
        #expect(!html.contains("<script src="))
    }

    private func fixtureURL(
        _ name: String,
        extension fileExtension: String
    ) throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: "Fixtures/Editor"
            )
        )
    }
}

private struct Matrix: Decodable {
    let version: Int
    let frozenAt: String
    let capabilities: [Capability]
}

private struct Capability: Decodable {
    enum Status: String, Decodable {
        case required
        case manual
        case deferred
    }

    let id: String
    let area: String
    let label: String
    let entry: String
    let shortcut: String
    let disabledWhen: String
    let input: String
    let output: String
    let markdown: String
    let bypass: Bool
    let states: [String]
    let connectivity: String
    let test: String
    let status: Status
}

private struct BypassCorpus: Decodable {
    struct Block: Decodable {
        let id: String
        let type: String
        let version: Int
        let fallback: String
    }

    let version: Int
    let blocks: [Block]
}

private struct InteractionCorpus: Decodable {
    struct Scenario: Decodable {
        let id: String
        let steps: [String]
        let expect: [String]
    }

    let version: Int
    let scenarios: [Scenario]
}
