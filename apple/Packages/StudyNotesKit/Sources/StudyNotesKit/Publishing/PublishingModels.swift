import Foundation

public enum PublishingVisibility: String, Codable, CaseIterable, Sendable {
    case publicArticle = "PUBLIC"
    case unlisted = "UNLISTED"
    case withdrawn = "WITHDRAWN"
}

public struct PublishingPublicKeyJWK: Codable, Equatable, Sendable {
    public let kty: String
    public let crv: String
    public let x: String
    public let kid: String?
    public let use: String?
    public let alg: String?

    public init(
        x: String,
        kid: String? = nil,
        use: String? = "sig",
        alg: String? = "EdDSA"
    ) {
        self.kty = "OKP"
        self.crv = "Ed25519"
        self.x = x
        self.kid = kid
        self.use = use
        self.alg = alg
    }
}

public struct PublishingKeyRegistrationRequest: Codable, Equatable, Sendable {
    public let kid: String
    public let publicKeyJwk: PublishingPublicKeyJWK

    public init(kid: String, publicKeyJwk: PublishingPublicKeyJWK) {
        self.kid = kid
        self.publicKeyJwk = publicKeyJwk
    }
}

public struct PublishingKeyResponse: Codable, Equatable, Sendable {
    public let kid: String
    public let status: String
    public let createdAt: String
}

public struct PublishingAnnotation: Codable, Equatable, Sendable {
    public let id: String
    public let quote: String
    public let note: String
    public let blockId: String?
    public let createdAt: String?

    public init(
        id: String,
        quote: String,
        note: String,
        blockId: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.quote = quote
        self.note = note
        self.blockId = blockId
        self.createdAt = createdAt
    }
}

public struct PublishingAIAppendixItem: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

public struct PublishingMediaReference: Codable, Equatable, Sendable {
    public let objectKey: String
    public let contentHash: String
    public let contentType: String
    public let size: Int
    public let reference: String

    public init(
        objectKey: String,
        contentHash: String,
        contentType: String,
        size: Int,
        reference: String
    ) {
        self.objectKey = objectKey
        self.contentHash = contentHash
        self.contentType = contentType
        self.size = size
        self.reference = reference
    }
}

public struct PublishingRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let articleId: String?
    public let sourceMaterialId: String
    public let sourceVersionId: String?
    public let expectedVersion: Int
    public let visibility: PublishingVisibility
    public let title: String
    public let summary: String?
    public let bodyHtml: String
    public let tags: [String]
    public let publishAnnotations: Bool
    public let publishAi: Bool
    public let annotations: [PublishingAnnotation]?
    public let aiAppendix: [PublishingAIAppendixItem]?
    public let mediaRefs: [PublishingMediaReference]?

    public init(
        requestId: String,
        articleId: String? = nil,
        sourceMaterialId: String,
        sourceVersionId: String? = nil,
        expectedVersion: Int,
        visibility: PublishingVisibility,
        title: String,
        summary: String? = nil,
        bodyHtml: String,
        tags: [String] = [],
        publishAnnotations: Bool = false,
        publishAi: Bool = false,
        annotations: [PublishingAnnotation]? = nil,
        aiAppendix: [PublishingAIAppendixItem]? = nil,
        mediaRefs: [PublishingMediaReference]? = nil
    ) {
        self.requestId = requestId
        self.articleId = articleId
        self.sourceMaterialId = sourceMaterialId
        self.sourceVersionId = sourceVersionId
        self.expectedVersion = expectedVersion
        self.visibility = visibility
        self.title = title
        self.summary = summary
        self.bodyHtml = bodyHtml
        self.tags = tags
        self.publishAnnotations = publishAnnotations
        self.publishAi = publishAi
        self.annotations = annotations
        self.aiAppendix = aiAppendix
        self.mediaRefs = mediaRefs
    }
}

public struct PublishingResponse: Codable, Equatable, Sendable {
    public let articleId: String
    public let visibility: PublishingVisibility
    public let publicUrl: String
    public let unlistedUrl: String
    public let version: Int
    public let versionId: String
    public let fingerprint: String
    public let publishedAt: String
    public let createdArticle: Bool
    public let createdVersion: Bool
    public let reusedVersion: Bool
    public let idempotent: Bool
}

public struct PublishingVisibilityRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let expectedVersion: Int
    public let visibility: PublishingVisibility

    public init(
        requestId: String,
        expectedVersion: Int,
        visibility: PublishingVisibility
    ) {
        self.requestId = requestId
        self.expectedVersion = expectedVersion
        self.visibility = visibility
    }
}

public struct PublishingWithdrawRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let expectedVersion: Int

    public init(requestId: String, expectedVersion: Int) {
        self.requestId = requestId
        self.expectedVersion = expectedVersion
    }
}

public struct PublishingRollbackRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let expectedVersion: Int
    public let targetVersion: Int

    public init(
        requestId: String,
        expectedVersion: Int,
        targetVersion: Int
    ) {
        self.requestId = requestId
        self.expectedVersion = expectedVersion
        self.targetVersion = targetVersion
    }
}

public struct PublishingDeleteRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let expectedVersion: Int

    public init(requestId: String, expectedVersion: Int) {
        self.requestId = requestId
        self.expectedVersion = expectedVersion
    }
}

public struct PublishingVisibilityResponse: Codable, Equatable, Sendable {
    public let articleId: String
    public let visibility: PublishingVisibility
    public let currentVersion: Int
    public let idempotent: Bool
}

public struct PublishingRollbackResponse: Codable, Equatable, Sendable {
    public let articleId: String
    public let currentVersion: Int
    public let versionId: String
    public let fingerprint: String
    public let idempotent: Bool
}

public struct PublishingDeleteResponse: Codable, Equatable, Sendable {
    public let articleId: String
    public let deleted: Bool
}

public struct PublishingStatusResponse: Codable, Equatable, Sendable {
    public let articleId: String
    public let sourceMaterialId: String
    public let visibility: PublishingVisibility
    public let currentVersion: Int?
    public let publicUrl: String
    public let unlistedUrl: String
    public let fingerprint: String?
    public let updatedAt: String

    public init(
        articleId: String,
        sourceMaterialId: String,
        visibility: PublishingVisibility,
        currentVersion: Int?,
        publicUrl: String,
        unlistedUrl: String,
        fingerprint: String?,
        updatedAt: String
    ) {
        self.articleId = articleId
        self.sourceMaterialId = sourceMaterialId
        self.visibility = visibility
        self.currentVersion = currentVersion
        self.publicUrl = publicUrl
        self.unlistedUrl = unlistedUrl
        self.fingerprint = fingerprint
        self.updatedAt = updatedAt
    }
}

public struct PublishingUploadTokenRequest: Codable, Equatable, Sendable {
    public let objectKey: String
    public let contentHash: String
    public let contentType: String
    public let size: Int

    public init(
        objectKey: String,
        contentHash: String,
        contentType: String,
        size: Int
    ) {
        self.objectKey = objectKey
        self.contentHash = contentHash
        self.contentType = contentType
        self.size = size
    }
}

public enum PublishingUploadMethod: String, Codable, Equatable, Sendable {
    case put = "PUT"
    case post = "POST"
}

public struct PublishingUploadTokenResponse: Codable, Equatable, Sendable {
    public let uploadUrl: String
    public let token: String
    public let objectKey: String
    public let expiresAt: String
    public let method: PublishingUploadMethod
}

public struct UploadedPublishingMedia: Equatable, Sendable {
    public let itemID: String
    public let reference: PublishingMediaReference

    public init(itemID: String, reference: PublishingMediaReference) {
        self.itemID = itemID
        self.reference = reference
    }
}

public struct PublishingAPIError: Error, Equatable, Sendable, LocalizedError {
    public let statusCode: Int
    public let code: String
    public let message: String
    public let expectedVersion: Int?
    public let currentVersion: Int?

    public init(
        statusCode: Int,
        code: String,
        message: String,
        expectedVersion: Int? = nil,
        currentVersion: Int? = nil
    ) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
        self.expectedVersion = expectedVersion
        self.currentVersion = currentVersion
    }

    public var errorDescription: String? {
        if code == "VERSION_CONFLICT", let currentVersion {
            return "发布版本冲突：服务端当前为第 \(currentVersion) 版，请刷新状态后重试。\(message)"
        }
        return "\(message)（HTTP \(statusCode)，\(code)）"
    }
}

public enum PublishingClientError: Error, Equatable, Sendable, LocalizedError {
    case invalidBaseURL
    case missingCredential
    case invalidCredential
    case invalidResponse
    case invalidRegistrationSecret
    case invalidBodyHTML
    case missingMediaReference(String)
    case emptyAnnotationNote(String)
    case mediaFileMissing(String)
    case mediaFileChanged(String)
    case mediaTooLarge(String)
    case unsupportedUploadMethod
    case uploadRejected(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "发布服务器地址必须是有效的 HTTP 或 HTTPS 地址。"
        case .missingCredential:
            "尚未生成或登记发布密钥。"
        case .invalidCredential:
            "发布密钥格式无效，请重新生成并登记。"
        case .invalidResponse:
            "发布服务返回了无法识别的响应。"
        case .invalidRegistrationSecret:
            "发布密钥注册凭据至少需要 16 个字符。"
        case .invalidBodyHTML:
            "发布预览中没有可提取的正文。"
        case .missingMediaReference(let fileName):
            "正文引用的媒体 \(fileName) 尚未成功上传。"
        case .emptyAnnotationNote(let id):
            "公开标注 \(id) 没有备注；请补充备注或关闭公开标注。"
        case .mediaFileMissing(let fileName):
            "本地媒体文件不存在：\(fileName)。"
        case .mediaFileChanged(let fileName):
            "本地媒体内容已变化，请刷新发布预览：\(fileName)。"
        case .mediaTooLarge(let fileName):
            "媒体文件大小必须在 1 字节到 50 MB 之间：\(fileName)。"
        case .unsupportedUploadMethod:
            "发布服务返回了不支持的媒体上传方法。"
        case .uploadRejected(let status, let detail):
            detail.isEmpty
                ? "媒体上传失败（HTTP \(status)）。"
                : "媒体上传失败（HTTP \(status)）：\(detail)"
        }
    }
}
