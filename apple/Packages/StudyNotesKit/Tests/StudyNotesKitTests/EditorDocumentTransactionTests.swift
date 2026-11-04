import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Editor document transaction")
struct EditorDocumentTransactionTests {
    @Test("fixed bypass corpus decodes into persistable block envelopes")
    func fixedBypassCorpusDecodes() throws {
        let data = try Data(
            contentsOf: try #require(
                Bundle.module.url(
                    forResource: "bypass-blocks",
                    withExtension: "json",
                    subdirectory: "Fixtures/Editor"
                )
            )
        )
        let corpus = try JSONDecoder().decode(BypassCorpus.self, from: data)

        #expect(corpus.version == 1)
        #expect(corpus.blocks.count == 2)
        #expect(corpus.blocks.allSatisfy { $0.version == 1 })
        #expect(Set(corpus.blocks.map(\.id)).count == corpus.blocks.count)
        #expect(corpus.blocks.first?.fallback.contains("Ada") == true)
    }

    @Test("fixed transaction sample decodes with its base fingerprint and block")
    func fixedTransactionSampleDecodes() throws {
        let transactionID = UUID(
            uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        )!
        let materialID = UUID(
            uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        )!
        let blockID = UUID(
            uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"
        )!
        let generationID = UUID(
            uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd"
        )!
        let contentFingerprint = String(repeating: "b", count: 64)
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "id": "\(transactionID.uuidString)",
              "materialID": "\(materialID.uuidString)",
              "createdAt": "2027-01-15T08:30:00Z",
              "baseContentFingerprint": "\(String(repeating: "a", count: 64))",
              "generationID": "\(generationID.uuidString)",
              "contentFingerprint": "\(contentFingerprint)",
              "title": "恢复样本",
              "markdown": "<!-- studynotes:block id=\\"\(blockID.uuidString)\\" type=\\"data-table\\" version=\\"1\\" -->\\n表格\\n<!-- /studynotes:block -->",
              "blocks": [
                {
                  "id": "\(blockID.uuidString)",
                  "type": "data-table",
                  "version": 1,
                  "fallback": "表格",
                  "data": {"records": []}
                }
              ]
            }
            """.utf8
        )

        let transaction = try CrossPlatformJSON.decoder().decode(
            EditorDocumentTransaction.self,
            from: data
        )

        #expect(transaction.id == transactionID)
        #expect(transaction.materialID == materialID)
        #expect(transaction.generationID == generationID)
        #expect(transaction.contentFingerprint == contentFingerprint)
        #expect(transaction.blocks.map(\.id) == [blockID])
        #expect(transaction.blocks.first?.type == "data-table")
    }

    @Test("manifest, transaction and bypass schemas are present and versioned")
    func documentSchemasAreVersioned() throws {
        let contractsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../../../contracts")
        let names = [
            "editor-document-manifest.schema.json",
            "editor-document-transaction.schema.json",
            "editor-bypass-block.schema.json"
        ]
        for name in names {
            let data = try Data(
                contentsOf: contractsURL.appending(path: name)
            )
            let object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            #expect(object["$schema"] as? String != nil)
            #expect(object["title"] as? String != nil)
            #expect(object["properties"] as? [String: Any] != nil)
        }
    }
}

private struct BypassCorpus: Decodable {
    let version: Int
    let blocks: [EditorDocumentBlockEnvelope]
}
