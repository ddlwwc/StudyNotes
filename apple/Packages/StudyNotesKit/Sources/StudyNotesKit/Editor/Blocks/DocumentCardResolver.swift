import Foundation

public enum ResolvedDocumentCard: Equatable, Sendable {
    case resolved(DocumentCardReference, StudyMaterialSummary)
    case unresolved(DocumentCardReference)

    public var reference: DocumentCardReference {
        switch self {
        case let .resolved(reference, _), let .unresolved(reference):
            reference
        }
    }
}

public struct DocumentCardResolver: Sendable {
    public init() {}

    public func resolve(
        _ references: [DocumentCardReference],
        in materials: [StudyMaterialSummary],
        knowledgeBaseID: UUID?
    ) -> [ResolvedDocumentCard] {
        let byID = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })
        return references.map { reference in
            guard let material = byID[reference.materialID],
                  knowledgeBaseID == nil
                    || material.knowledgeBaseID == knowledgeBaseID else {
                return .unresolved(reference)
            }
            return .resolved(reference, material)
        }
    }
}
