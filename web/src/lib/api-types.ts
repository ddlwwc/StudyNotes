import type {
  AiAppendixItem,
  ArticleAnnotation,
  MediaReferenceInput
} from "@/domain/types";

export interface PublishKeyRegistrationRequest {
  kid: string;
  publicKeyJwk: {
    kty: "OKP";
    crv: "Ed25519";
    x: string;
    kid?: string;
    use?: "sig";
    alg?: "EdDSA";
  };
}

export interface PublishKeyResponse {
  kid: string;
  status: "ACTIVE" | "REVOKED";
  createdAt: string;
}

export interface PublishRequest {
  requestId: string;
  articleId?: string;
  sourceMaterialId: string;
  sourceVersionId?: string | null;
  expectedVersion: number;
  visibility: "PUBLIC" | "UNLISTED";
  title: string;
  summary?: string;
  bodyHtml: string;
  tags?: string[];
  publishAnnotations: boolean;
  publishAi: boolean;
  annotations?: ArticleAnnotation[];
  aiAppendix?: AiAppendixItem[];
  mediaRefs?: MediaReferenceInput[];
}

export interface PublishResponse {
  articleId: string;
  visibility: "PUBLIC" | "UNLISTED" | "WITHDRAWN";
  publicUrl: string;
  unlistedUrl: string;
  version: number;
  versionId: string;
  fingerprint: string;
  publishedAt: string;
  createdArticle: boolean;
  createdVersion: boolean;
  reusedVersion: boolean;
  idempotent: boolean;
}

export interface VisibilityRequest {
  requestId: string;
  expectedVersion: number;
  visibility: "PUBLIC" | "UNLISTED";
}

export interface WithdrawRequest {
  requestId: string;
  expectedVersion: number;
}

export interface RollbackRequest {
  requestId: string;
  expectedVersion: number;
  targetVersion: number;
}

export interface DeleteRequest {
  requestId: string;
  expectedVersion: number;
}

export interface MediaUploadTokenRequest {
  objectKey: string;
  contentHash: string;
  contentType: string;
  size: number;
}

export interface MediaUploadTokenResponse {
  uploadUrl: string;
  token: string;
  objectKey: string;
  expiresAt: string;
  method: "PUT" | "POST";
}

export interface LibraryMediaUploadRequest {
  contentHash: string;
  contentType: string;
  size: number;
}

export interface LibraryMediaUploadResponse {
  uploadUrl: string;
  token: string;
  objectKey: string;
  expiresAt: string;
  method: "PUT" | "POST";
  alreadyExists: boolean;
}

export interface LibraryMediaCompleteRequest {
  objectKey: string;
}

export interface LibraryMediaCompleteResponse {
  objectKey: string;
  status: "READY";
  contentHash: string;
  contentType: string;
  size: number;
}

export interface LibraryMediaReadRequest {
  objectKey: string;
}

export interface LibraryMediaReadResponse {
  url: string;
  expiresAt: string;
}

export interface LibraryMediaPublishPreviewRequest {
  bodyHtml: string;
  mediaRefs?: MediaReferenceInput[];
}

export interface LibraryMediaPublishPreviewResponse {
  ready: boolean;
  media: Array<{
    objectKey: string;
    status:
      | "PENDING"
      | "READY"
      | "DELETING"
      | "MISSING"
      | "MISMATCH"
      | "MISSING_REFERENCE";
    contentHash?: string;
    contentType?: string;
    size?: number;
  }>;
}

export interface LibraryMediaReferenceInput {
  scope: "CURRENT" | "HISTORY";
  objectKey: string;
  reference: string;
}

export interface LibraryMediaHistoricalLocalItem {
  reference: string;
  size: number;
}

export interface LibraryMediaScanRequest {
  sourceId: string;
  references: LibraryMediaReferenceInput[];
  historicalLocalMedia?: LibraryMediaHistoricalLocalItem[];
}

export interface LibraryMediaScanResponse {
  sourceId: string;
  summary: {
    currentCount: number;
    historyCount: number;
    totalSize: number;
    missingCount: number;
    historicalLocalCount: number;
    historicalLocalSize: number;
  };
  media: Array<{
    objectKey: string;
    scopes: Array<"CURRENT" | "HISTORY">;
    references: string[];
    status: "PENDING" | "READY" | "DELETING" | "MISSING";
    contentHash?: string;
    contentType?: string;
    size?: number;
  }>;
}

export interface LibraryMediaCleanupRequest {
  objectKeys: string[];
  confirmed: boolean;
}

export interface LibraryMediaCleanupResponse {
  queued: Array<{
    objectKey: string;
    availableAt: string;
  }>;
  skipped: Array<{
    objectKey: string;
    reason: "REFERENCED" | "NOT_FOUND" | "CONFIRMATION_REQUIRED";
  }>;
}

export interface LibraryMediaCleanupCandidateResponse {
  summary: {
    count: number;
    totalSize: number;
  };
  media: Array<{
    objectKey: string;
    status: "READY";
    contentHash: string;
    contentType: string;
    size: number;
  }>;
}

export interface LibraryMediaStatusResponse {
  ok: boolean;
  bucket: string;
  domain: string;
  uploadUrl: string;
  httpWarning: boolean;
  message?: string;
}
