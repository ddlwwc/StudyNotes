export type Visibility = "PUBLIC" | "UNLISTED" | "WITHDRAWN";

export interface PublicKeyJwk {
  kty: "OKP";
  crv: "Ed25519";
  x: string;
  kid?: string;
  use?: "sig";
  alg?: "EdDSA";
}

export interface PublishKey {
  id: string;
  kid: string;
  publicKeyJwk: PublicKeyJwk;
  status: "ACTIVE" | "REVOKED";
  createdAt: Date;
  revokedAt: Date | null;
}

export interface ArticleAnnotation {
  id: string;
  quote: string;
  note: string;
  blockId?: string;
  blockPath?: string | number[];
  createdAt?: string;
}

export interface AiAppendixItem {
  id: string;
  title: string;
  body: string;
}

export interface MediaMetadata {
  contentHash: string;
  contentType: string;
  size: number;
}

export interface MediaReferenceInput extends MediaMetadata {
  objectKey: string;
  reference: string;
}

export interface MediaAsset extends MediaMetadata {
  id: string;
  objectKey: string;
  status: "PENDING" | "READY";
  createdAt: Date;
}

export interface LibraryMediaAsset extends MediaMetadata {
  id: string;
  objectKey: string;
  status: "PENDING" | "READY" | "DELETING";
  createdAt: Date;
  verifiedAt: Date | null;
}

export type LibraryMediaReferenceScope = "CURRENT" | "HISTORY";

export interface LibraryMediaReference {
  id: string;
  sourceId: string;
  scope: LibraryMediaReferenceScope;
  objectKey: string;
  reference: string;
  updatedAt: Date;
}

export interface LibraryMediaCleanupJob {
  id: string;
  objectKey: string;
  status: "PENDING" | "PROCESSING" | "FAILED";
  attempts: number;
  lastError: string | null;
  availableAt: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface VersionMedia extends MediaMetadata {
  id: string;
  mediaId: string;
  objectKey: string;
  reference: string;
}

export interface TableOfContentsItem {
  id: string;
  text: string;
  level: number;
}

export interface ArticleRecord {
  id: string;
  articleId: string;
  unlistedToken: string;
  sourceMaterialId: string;
  visibility: Visibility;
  currentVersionId: string | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface ArticleVersionRecord {
  id: string;
  articleRowId: string;
  version: number;
  sourceVersionId: string | null;
  fingerprint: string;
  title: string;
  summary: string;
  bodyHtml: string;
  readerHtml: string;
  toc: TableOfContentsItem[];
  tags: string[];
  annotations: ArticleAnnotation[];
  aiAppendix: AiAppendixItem[];
  media: VersionMedia[];
  visibilityAtPublish: Visibility;
  publishedAt: Date;
}

export interface ArticleView {
  article: ArticleRecord;
  version: ArticleVersionRecord;
}

export interface ArticleSummary {
  articleId: string;
  versionId: string;
  title: string;
  summary: string;
  tags: string[];
  publishedAt: Date;
  updatedAt: Date;
}

export interface StoredRequest {
  requestId: string;
  keyId: string;
  requestHash: string;
  response: unknown;
  createdAt: Date;
}

export interface AtomicPublishInput {
  keyId: string;
  requestId: string;
  requestHash: string;
  articlePublicId?: string;
  sourceMaterialId: string;
  sourceVersionId: string | null;
  expectedVersion: number;
  visibility: Visibility;
  title: string;
  summary: string;
  fingerprint: string;
  bodyHtml: string;
  readerHtml: string;
  toc: TableOfContentsItem[];
  tags: string[];
  annotations: ArticleAnnotation[];
  aiAppendix: AiAppendixItem[];
  media: VersionMedia[];
  versionId: string;
  newArticleRowId: string;
  newArticlePublicId: string;
  newUnlistedToken: string;
  publishedAt: Date;
}

export interface PublishOutcome {
  articleId: string;
  unlistedToken: string;
  visibility: Visibility;
  version: number;
  versionId: string;
  fingerprint: string;
  publishedAt: string;
  createdArticle: boolean;
  createdVersion: boolean;
  reusedVersion: boolean;
  idempotent: boolean;
}

export interface VisibilityInput {
  keyId: string;
  requestId: string;
  requestHash: string;
  articlePublicId: string;
  expectedVersion: number;
  visibility: Visibility;
}

export interface VisibilityOutcome {
  articleId: string;
  visibility: Visibility;
  currentVersion: number;
  idempotent: boolean;
}

export interface RollbackInput {
  keyId: string;
  requestId: string;
  requestHash: string;
  articlePublicId: string;
  expectedVersion: number;
  targetVersion: number;
}

export interface RollbackOutcome {
  articleId: string;
  currentVersion: number;
  versionId: string;
  fingerprint: string;
  idempotent: boolean;
}

export interface DeleteInput {
  keyId: string;
  requestId: string;
  requestHash: string;
  articlePublicId: string;
  expectedVersion: number;
}

export interface DeleteOutcome {
  articleId: string;
  deleted: true;
  idempotent: boolean;
}

export interface MediaCleanupJob {
  id: string;
  objectKey: string;
  articlePublicId: string;
  status: "PENDING" | "PROCESSING" | "FAILED";
  attempts: number;
  lastError: string | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface PublishStatus {
  articleId: string;
  sourceMaterialId: string;
  visibility: Visibility;
  currentVersion: number | null;
  publicUrl: string;
  unlistedUrl: string;
  fingerprint: string | null;
  updatedAt: string;
}

export interface PublishRepository {
  health(): Promise<boolean>;
  registerPublishKey(publishKey: PublishKey): Promise<PublishKey>;
  getPublishKey(kid: string): Promise<PublishKey | null>;
  revokePublishKey(kid: string, revokedAt: Date): Promise<void>;
  consumeNonce(
    keyId: string,
    nonce: string,
    seenAt: Date,
    expiresAt: Date
  ): Promise<boolean>;
  getPublishOutcomeByRequest(
    keyId: string,
    requestId: string,
    requestHash: string
  ): Promise<PublishOutcome | null>;
  executePublish(input: AtomicPublishInput): Promise<PublishOutcome>;
  executeVisibilityChange(input: VisibilityInput): Promise<VisibilityOutcome>;
  executeRollback(input: RollbackInput): Promise<RollbackOutcome>;
  executeWithdraw(input: VisibilityInput): Promise<VisibilityOutcome>;
  deleteArticle(input: DeleteInput): Promise<DeleteOutcome>;
  getArticleByPublicId(articleId: string): Promise<ArticleRecord | null>;
  getArticleByUnlistedToken(token: string): Promise<ArticleRecord | null>;
  getArticleView(article: ArticleRecord): Promise<ArticleView | null>;
  getVersion(articleRowId: string, version: number): Promise<ArticleVersionRecord | null>;
  getMediaAsset(mediaId: string): Promise<MediaAsset | null>;
  getMediaAssetByObjectKey(objectKey: string): Promise<MediaAsset | null>;
  createMediaAsset(asset: MediaAsset): Promise<MediaAsset>;
  getLibraryMediaAssetByContentHash(
    contentHash: string
  ): Promise<LibraryMediaAsset | null>;
  getLibraryMediaAssetByObjectKey(
    objectKey: string
  ): Promise<LibraryMediaAsset | null>;
  listLibraryMediaAssets(): Promise<LibraryMediaAsset[]>;
  createLibraryMediaAsset(asset: LibraryMediaAsset): Promise<LibraryMediaAsset>;
  markLibraryMediaReady(mediaId: string, verifiedAt: Date): Promise<void>;
  markLibraryMediaDeletingIfUnreferenced(objectKey: string): Promise<boolean>;
  replaceLibraryMediaReferences(
    sourceId: string,
    references: LibraryMediaReference[]
  ): Promise<void>;
  getLibraryMediaReferences(
    objectKeys: string[]
  ): Promise<LibraryMediaReference[]>;
  enqueueLibraryMediaCleanup(
    objectKeys: string[],
    availableAt: Date
  ): Promise<LibraryMediaCleanupJob[]>;
  claimLibraryMediaCleanupJobs(
    limit: number,
    now: Date
  ): Promise<LibraryMediaCleanupJob[]>;
  completeLibraryMediaCleanupJob(jobId: string): Promise<void>;
  failLibraryMediaCleanupJob(jobId: string, message: string): Promise<void>;
  deleteLibraryMediaAsset(objectKey: string): Promise<void>;
  markMediaReady(mediaId: string): Promise<void>;
  claimMediaCleanupJobs(limit: number): Promise<MediaCleanupJob[]>;
  completeMediaCleanupJob(jobId: string): Promise<void>;
  failMediaCleanupJob(jobId: string, message: string): Promise<void>;
  listPublicArticles(limit: number): Promise<ArticleSummary[]>;
  searchPublicArticles(query: string, limit: number): Promise<ArticleSummary[]>;
  getPublishStatus(articlePublicId: string): Promise<PublishStatus | null>;
  getVersionMedia(versionId: string): Promise<VersionMedia[]>;
}

export interface UploadCredentialInput {
  objectKey: string;
  contentHash: string;
  contentType: string;
  size: number;
  expiresInSeconds: number;
}

export interface UploadCredential {
  uploadUrl: string;
  token: string;
  objectKey: string;
  expiresAt: string;
  method: "PUT" | "POST";
}

export interface ObjectMetadata {
  objectKey: string;
  contentHash: string;
  contentType: string;
  size: number;
}

export type ObjectVerificationInput = Omit<MediaReferenceInput, "reference">;

export interface StorageAdapter {
  createUploadCredential(input: UploadCredentialInput): Promise<UploadCredential>;
  verifyObject(input: ObjectVerificationInput): Promise<ObjectMetadata>;
  health(): Promise<boolean>;
  copyObject(
    sourceObjectKey: string,
    destinationObjectKey: string,
    contentType: string
  ): Promise<void>;
  createReadUrl(objectKey: string, expiresInSeconds: number): Promise<string>;
  readObject(objectKey: string): Promise<Buffer>;
  deleteObject(objectKey: string): Promise<void>;
}
