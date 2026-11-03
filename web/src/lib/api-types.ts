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
