import Foundation
import Testing
@testable import StudyNotesKit

@Suite("Document card resolver")
struct DocumentCardResolverTests {
    @Test("missing or cross-knowledge-base cards stay unresolved")
    func resolution() {
        let knowledgeBaseID = UUID()
        let materialID = UUID()
        let material = StudyMaterialSummary(
            id: materialID,
            knowledgeBaseID: knowledgeBaseID,
            kind: .note,
            title: "Target",
            updatedAt: Date(),
            conflictCopies: []
        )
        let references = [
            DocumentCardReference(materialID: materialID, title: "Target"),
            DocumentCardReference(materialID: UUID(), title: "Missing")
        ]

        let resolved = DocumentCardResolver().resolve(
            references,
            in: [material],
            knowledgeBaseID: knowledgeBaseID
        )

        #expect(resolved.count == 2)
        guard case .resolved = resolved[0],
              case .unresolved = resolved[1] else {
            Issue.record("Unexpected resolution results")
            return
        }
    }
}
