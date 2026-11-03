import Foundation

public struct NoteMediaStatusResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let bucket: String
    public let domain: String
    public let uploadUrl: String
    public let httpWarning: Bool
    public let message: String?

    public init(
        ok: Bool,
        bucket: String,
        domain: String,
        uploadUrl: String,
        httpWarning: Bool,
        message: String? = nil
    ) {
        self.ok = ok
        self.bucket = bucket
        self.domain = domain
        self.uploadUrl = uploadUrl
        self.httpWarning = httpWarning
        self.message = message
    }
}

public struct NoteMediaUploadCredentialRequest:
    Codable,
    Equatable,
    Sendable {
    public let contentHash: String
    public let contentType: String
    public let size: Int

    public init(contentHash: String, contentType: String, size: Int) {
        self.contentHash = contentHash
        self.contentType = contentType
        self.size = size
    }
}

public enum NoteMediaUploadMethod: String, Codable, Equatable, Sendable {
    case put = "PUT"
    case post = "POST"
}

public struct NoteMediaUploadCredentialResponse:
    Codable,
    Equatable,
    Sendable {
    public let uploadUrl: String
    public let token: String
    public let objectKey: String
    public let expiresAt: Date
    public let method: NoteMediaUploadMethod
    public let alreadyExists: Bool

    public init(
        uploadUrl: String,
        token: String,
        objectKey: String,
        expiresAt: Date,
        method: NoteMediaUploadMethod,
        alreadyExists: Bool
    ) {
        self.uploadUrl = uploadUrl
        self.token = token
        self.objectKey = objectKey
        self.expiresAt = expiresAt
        self.method = method
        self.alreadyExists = alreadyExists
    }
}

public struct NoteMediaCompleteRequest: Codable, Equatable, Sendable {
    public let objectKey: String

    public init(objectKey: String) {
        self.objectKey = objectKey
    }
}

public struct NoteMediaCompleteResponse:
    Codable,
    Equatable,
    Sendable {
    public let objectKey: String
    public let status: String
    public let contentHash: String
    public let contentType: String
    public let size: Int

    public init(
        objectKey: String,
        status: String,
        contentHash: String,
        contentType: String,
        size: Int
    ) {
        self.objectKey = objectKey
        self.status = status
        self.contentHash = contentHash
        self.contentType = contentType
        self.size = size
    }
}

public struct NoteMediaDownloadURLRequest:
    Codable,
    Equatable,
    Sendable {
    public let objectKey: String

    public init(objectKey: String) {
        self.objectKey = objectKey
    }
}

public struct NoteMediaDownloadURLResponse:
    Codable,
    Equatable,
    Sendable {
    public let url: String
    public let expiresAt: Date

    public init(url: String, expiresAt: Date) {
        self.url = url
        self.expiresAt = expiresAt
    }
}

public enum NoteMediaReferenceScope: String, Codable, Equatable, Sendable {
    case current = "CURRENT"
    case history = "HISTORY"
}

public struct NoteMediaReferenceInput:
    Codable,
    Equatable,
    Sendable {
    public let scope: NoteMediaReferenceScope
    public let objectKey: String
    public let reference: String

    public init(
        scope: NoteMediaReferenceScope,
        objectKey: String,
        reference: String
    ) {
        self.scope = scope
        self.objectKey = objectKey
        self.reference = reference
    }
}

public struct NoteMediaHistoricalLocalReference:
    Codable,
    Equatable,
    Sendable {
    public let reference: String
    public let size: Int

    public init(reference: String, size: Int) {
        self.reference = reference
        self.size = size
    }
}

public struct NoteMediaReferenceScanRequest:
    Codable,
    Equatable,
    Sendable {
    public let sourceId: String
    public let references: [NoteMediaReferenceInput]
    public let historicalLocalMedia: [NoteMediaHistoricalLocalReference]

    public init(
        sourceId: String,
        references: [NoteMediaReferenceInput],
        historicalLocalMedia: [NoteMediaHistoricalLocalReference] = []
    ) {
        self.sourceId = sourceId
        self.references = references
        self.historicalLocalMedia = historicalLocalMedia
    }
}

public struct NoteMediaScanSummary: Codable, Equatable, Sendable {
    public let currentCount: Int
    public let historyCount: Int
    public let totalSize: Int
    public let missingCount: Int
    public let historicalLocalCount: Int
    public let historicalLocalSize: Int

    public init(
        currentCount: Int,
        historyCount: Int,
        totalSize: Int,
        missingCount: Int,
        historicalLocalCount: Int,
        historicalLocalSize: Int
    ) {
        self.currentCount = currentCount
        self.historyCount = historyCount
        self.totalSize = totalSize
        self.missingCount = missingCount
        self.historicalLocalCount = historicalLocalCount
        self.historicalLocalSize = historicalLocalSize
    }
}

public enum NoteMediaAssetStatus: String, Codable, Equatable, Sendable {
    case pending = "PENDING"
    case ready = "READY"
    case missing = "MISSING"
    case mismatch = "MISMATCH"
    case missingReference = "MISSING_REFERENCE"
}

public struct NoteMediaScanItem: Codable, Equatable, Sendable {
    public let objectKey: String
    public let scopes: [NoteMediaReferenceScope]
    public let references: [String]
    public let status: NoteMediaAssetStatus
    public let contentHash: String?
    public let contentType: String?
    public let size: Int?

    public init(
        objectKey: String,
        scopes: [NoteMediaReferenceScope],
        references: [String],
        status: NoteMediaAssetStatus,
        contentHash: String? = nil,
        contentType: String? = nil,
        size: Int? = nil
    ) {
        self.objectKey = objectKey
        self.scopes = scopes
        self.references = references
        self.status = status
        self.contentHash = contentHash
        self.contentType = contentType
        self.size = size
    }
}

public struct NoteMediaReferenceScanResponse:
    Codable,
    Equatable,
    Sendable {
    public let sourceId: String
    public let summary: NoteMediaScanSummary
    public let media: [NoteMediaScanItem]

    public init(
        sourceId: String,
        summary: NoteMediaScanSummary,
        media: [NoteMediaScanItem]
    ) {
        self.sourceId = sourceId
        self.summary = summary
        self.media = media
    }
}

public struct NoteMediaCleanupRequest: Codable, Equatable, Sendable {
    public let objectKeys: [String]
    public let confirmed: Bool

    public init(objectKeys: [String], confirmed: Bool) {
        self.objectKeys = objectKeys
        self.confirmed = confirmed
    }
}

public struct NoteMediaCleanupQueuedItem:
    Codable,
    Equatable,
    Sendable {
    public let objectKey: String
    public let availableAt: Date

    public init(objectKey: String, availableAt: Date) {
        self.objectKey = objectKey
        self.availableAt = availableAt
    }
}

public enum NoteMediaCleanupSkipReason:
    String,
    Codable,
    Equatable,
    Sendable {
    case referenced = "REFERENCED"
    case notFound = "NOT_FOUND"
    case confirmationRequired = "CONFIRMATION_REQUIRED"
}

public struct NoteMediaCleanupSkippedItem:
    Codable,
    Equatable,
    Sendable {
    public let objectKey: String
    public let reason: NoteMediaCleanupSkipReason

    public init(
        objectKey: String,
        reason: NoteMediaCleanupSkipReason
    ) {
        self.objectKey = objectKey
        self.reason = reason
    }
}

public struct NoteMediaCleanupResponse: Codable, Equatable, Sendable {
    public let queued: [NoteMediaCleanupQueuedItem]
    public let skipped: [NoteMediaCleanupSkippedItem]

    public init(
        queued: [NoteMediaCleanupQueuedItem],
        skipped: [NoteMediaCleanupSkippedItem]
    ) {
        self.queued = queued
        self.skipped = skipped
    }
}
