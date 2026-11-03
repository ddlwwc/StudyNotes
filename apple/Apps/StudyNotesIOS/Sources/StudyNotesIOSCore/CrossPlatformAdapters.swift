import Foundation
import struct StudyNotesKit.CrossPlatformAIStudySession
import struct StudyNotesKit.CrossPlatformAnnotation
import struct StudyNotesKit.CrossPlatformAnnotationAnchor
import enum StudyNotesKit.CrossPlatformAnnotationKind
import enum StudyNotesKit.CrossPlatformAIConversationOrigin
import enum StudyNotesKit.CrossPlatformCodecError
import enum StudyNotesKit.CrossPlatformAIMessageRole
import struct StudyNotesKit.CrossPlatformAIMessage
import struct StudyNotesKit.CrossPlatformRect

extension StudyAnnotation {
    public init(from decoder: Decoder) throws {
        let wire = try CrossPlatformAnnotation(from: decoder)
        let anchor = try wire.anchor.iosAnchor
        self.init(
            id: wire.id,
            materialID: wire.materialID,
            anchor: anchor,
            note: wire.note,
            createdAt: wire.createdAt,
            updatedAt: wire.updatedAt,
            resolution: wire.status == "active" ? .resolved : .needsRecovery
        )
    }

    public func encode(to encoder: Encoder) throws {
        let wire = CrossPlatformAnnotation(
            id: id,
            materialID: materialID,
            anchor: try anchor.crossPlatformAnchor,
            quote: quote ?? "",
            note: note,
            status: resolution == .needsRecovery ? "unresolved" : "active",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try wire.encode(to: encoder)
    }
}

extension AIConversation {
    public init(from decoder: Decoder) throws {
        let wire = try CrossPlatformAIStudySession(from: decoder)
        self.init(
            id: wire.id,
            materialID: wire.materialID,
            providerName: wire.providerName,
            modelID: wire.model,
            action: wire.action,
            scopeDescription: wire.scopeDescription,
            title: wire.title,
            origin: wire.origin.iosOrigin,
            originAnchor: try wire.originAnchor?.iosAnchor,
            status: AIStudySessionStatus(rawValue: wire.status) ?? .pending,
            createdAt: wire.createdAt,
            updatedAt: wire.updatedAt,
            messages: wire.messages.map {
                AIMessage(
                    id: $0.id,
                    role: $0.role.iosRole,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    promptTokens: $0.promptTokens,
                    completionTokens: $0.completionTokens
                )
            }
        )
    }

    public func encode(to encoder: Encoder) throws {
        let wire = CrossPlatformAIStudySession(
            id: id,
            materialID: materialID,
            providerName: providerName,
            model: modelID,
            title: title,
            action: action,
            scopeDescription: scopeDescription,
            origin: origin.crossPlatformOrigin,
            status: status.rawValue,
            originAnchor: try originAnchor?.crossPlatformAnchor,
            messages: messages.map {
                CrossPlatformAIMessage(
                    id: $0.id,
                    role: $0.role.crossPlatformRole,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    promptTokens: $0.promptTokens,
                    completionTokens: $0.completionTokens
                )
            },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try wire.encode(to: encoder)
    }
}

private extension CrossPlatformAnnotationAnchor {
    var iosAnchor: AnnotationAnchor {
        get throws {
            switch kind {
            case .text, .pdfText:
                let startOffset = offset ?? 0
                let quoteLength = (excerpt as NSString).length
                return .text(
                    TextAnchor(
                        quote: excerpt,
                        prefix: prefix,
                        suffix: suffix,
                        startOffset: startOffset,
                        endOffset: startOffset + quoteLength,
                        blockPath: blockPath.first.map { "block-\($0)" } ?? ""
                    )
                )
            case .imageRect:
                return .imageRectangle(try iosRect)
            case .pdfPageRect:
                return .pageRectangle(
                    page: pageIndex ?? 0,
                    rectangle: try iosRect
                )
            case .wholeMaterial:
                return .wholeMaterial
            }
        }
    }

    var iosRect: NormalizedRectangle {
        get throws {
            guard let rect else {
                throw CrossPlatformCodecError.invalidAnnotation("标注缺少 rect。")
            }
            return NormalizedRectangle(
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            )
        }
    }
}

private extension AnnotationAnchor {
    var crossPlatformAnchor: CrossPlatformAnnotationAnchor {
        get throws {
            switch self {
            case let .text(anchor):
                return CrossPlatformAnnotationAnchor(
                    kind: .text,
                    excerpt: anchor.quote,
                    prefix: anchor.prefix,
                    suffix: anchor.suffix,
                    offset: anchor.startOffset,
                    blockPath: Self.blockPath(from: anchor.blockPath)
                )
            case let .imageRectangle(rect):
                return CrossPlatformAnnotationAnchor(
                    kind: .imageRect,
                    rect: rect.crossPlatformRect
                )
            case let .pageRectangle(page, rect):
                return CrossPlatformAnnotationAnchor(
                    kind: .pdfPageRect,
                    blockPath: [],
                    pageIndex: page,
                    rect: rect.crossPlatformRect
                )
            case .wholeMaterial:
                return CrossPlatformAnnotationAnchor(kind: .wholeMaterial)
            }
        }
    }

    static func blockPath(from value: String) -> [Int] {
        guard let number = Int(
            value.replacingOccurrences(of: "block-", with: "")
        ) else {
            return []
        }
        return [number]
    }
}

private extension NormalizedRectangle {
    var crossPlatformRect: CrossPlatformRect {
        CrossPlatformRect(x: x, y: y, width: width, height: height)
    }
}

private extension CrossPlatformAIConversationOrigin {
    var iosOrigin: AIConversationOrigin {
        switch self {
        case .selection:
            .selection
        case .summary:
            .summary
        }
    }
}

private extension AIConversationOrigin {
    var crossPlatformOrigin: CrossPlatformAIConversationOrigin {
        switch self {
        case .selection:
            .selection
        case .summary:
            .summary
        }
    }
}

private extension CrossPlatformAIMessageRole {
    var iosRole: AIMessage.Role {
        switch self {
        case .system:
            .system
        case .user:
            .user
        case .assistant:
            .assistant
        }
    }
}

private extension AIMessage.Role {
    var crossPlatformRole: CrossPlatformAIMessageRole {
        switch self {
        case .system:
            .system
        case .user:
            .user
        case .assistant:
            .assistant
        }
    }
}
