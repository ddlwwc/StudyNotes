import {
  index,
  int,
  json,
  mysqlTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  varchar
} from "drizzle-orm/mysql-core";
import type {
  AiAppendixItem,
  ArticleAnnotation,
  PublicKeyJwk,
  TableOfContentsItem,
  Visibility
} from "@/domain/types";

export const publishKeys = mysqlTable(
  "publish_keys",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    kid: varchar("kid", { length: 128 }).notNull(),
    publicKeyJwk: json("public_key_jwk").$type<PublicKeyJwk>().notNull(),
    status: varchar("status", { length: 16 }).notNull(),
    createdAt: timestamp("created_at", { fsp: 3 }).notNull(),
    revokedAt: timestamp("revoked_at", { fsp: 3 })
  },
  (table) => [uniqueIndex("publish_keys_kid_unique").on(table.kid)]
);

export const requestNonces = mysqlTable(
  "request_nonces",
  {
    keyId: varchar("key_id", { length: 128 }).notNull(),
    nonce: varchar("nonce", { length: 128 }).notNull(),
    seenAt: timestamp("seen_at", { fsp: 3 }).notNull(),
    expiresAt: timestamp("expires_at", { fsp: 3 }).notNull()
  },
  (table) => [
    primaryKey({ columns: [table.keyId, table.nonce] }),
    index("request_nonces_expiry_idx").on(table.expiresAt)
  ]
);

export const publishLocks = mysqlTable("publish_locks", {
  lockKey: varchar("lock_key", { length: 512 }).primaryKey(),
  createdAt: timestamp("created_at", { fsp: 3 }).notNull()
});

export const articles = mysqlTable(
  "articles",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    articleId: varchar("article_id", { length: 32 }).notNull(),
    unlistedToken: varchar("unlisted_token", { length: 64 }).notNull(),
    sourceMaterialId: varchar("source_material_id", { length: 128 }).notNull(),
    visibility: varchar("visibility", { length: 16 })
      .$type<Visibility>()
      .notNull(),
    currentVersionId: varchar("current_version_id", { length: 36 }),
    createdAt: timestamp("created_at", { fsp: 3 }).notNull(),
    updatedAt: timestamp("updated_at", { fsp: 3 }).notNull()
  },
  (table) => [
    uniqueIndex("articles_public_id_unique").on(table.articleId),
    uniqueIndex("articles_unlisted_token_unique").on(table.unlistedToken),
    uniqueIndex("articles_source_material_unique").on(table.sourceMaterialId)
  ]
);

export const articleVersions = mysqlTable(
  "article_versions",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    articleRowId: varchar("article_row_id", { length: 36 }).notNull(),
    version: int("version").notNull(),
    sourceVersionId: varchar("source_version_id", { length: 128 }),
    fingerprint: varchar("fingerprint", { length: 71 }).notNull(),
    title: varchar("title", { length: 300 }).notNull(),
    summary: text("summary").notNull(),
    bodyHtml: text("body_html").notNull(),
    readerHtml: text("reader_html").notNull(),
    toc: json("toc").$type<TableOfContentsItem[]>().notNull(),
    tags: json("tags").$type<string[]>().notNull(),
    annotations: json("annotations")
      .$type<ArticleAnnotation[]>()
      .notNull(),
    aiAppendix: json("ai_appendix")
      .$type<AiAppendixItem[]>()
      .notNull(),
    visibilityAtPublish: varchar("visibility_at_publish", { length: 16 })
      .$type<Visibility>()
      .notNull(),
    publishedAt: timestamp("published_at", { fsp: 3 }).notNull()
  },
  (table) => [
    uniqueIndex("article_versions_article_version_unique").on(
      table.articleRowId,
      table.version
    ),
    uniqueIndex("article_versions_article_fingerprint_unique").on(
      table.articleRowId,
      table.fingerprint
    )
  ]
);

export const publishRequests = mysqlTable(
  "publish_requests",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    keyId: varchar("key_id", { length: 128 }).notNull(),
    requestId: varchar("request_id", { length: 128 }).notNull(),
    requestHash: varchar("request_hash", { length: 71 }).notNull(),
    articleRowId: varchar("article_row_id", { length: 36 }),
    responseJson: json("response_json").$type<unknown>().notNull(),
    createdAt: timestamp("created_at", { fsp: 3 }).notNull()
  },
  (table) => [
    uniqueIndex("publish_requests_key_request_unique").on(
      table.keyId,
      table.requestId
    ),
    index("publish_requests_article_idx").on(table.articleRowId)
  ]
);

export const mediaAssets = mysqlTable(
  "media_assets",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    objectKey: varchar("object_key", { length: 512 }).notNull(),
    contentHash: varchar("content_hash", { length: 71 }).notNull(),
    contentType: varchar("content_type", { length: 128 }).notNull(),
    size: int("size").notNull(),
    status: varchar("status", { length: 16 }).notNull(),
    createdAt: timestamp("created_at", { fsp: 3 }).notNull()
  },
  (table) => [
    uniqueIndex("media_assets_object_key_unique").on(table.objectKey)
  ]
);

export const libraryMediaAssets = mysqlTable(
  "library_media_assets",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    objectKey: varchar("object_key", { length: 512 }).notNull(),
    contentHash: varchar("content_hash", { length: 71 }).notNull(),
    contentType: varchar("content_type", { length: 128 }).notNull(),
    size: int("size").notNull(),
    status: varchar("status", { length: 16 })
      .$type<"PENDING" | "READY" | "DELETING">()
      .notNull(),
    createdAt: timestamp("created_at", { fsp: 3 }).notNull(),
    verifiedAt: timestamp("verified_at", { fsp: 3 })
  },
  (table) => [
    uniqueIndex("library_media_assets_object_key_unique").on(table.objectKey),
    uniqueIndex("library_media_assets_content_hash_unique").on(
      table.contentHash
    )
  ]
);

export const libraryMediaReferences = mysqlTable(
  "library_media_references",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    sourceId: varchar("source_id", { length: 128 }).notNull(),
    scope: varchar("scope", { length: 16 })
      .$type<"CURRENT" | "HISTORY">()
      .notNull(),
    objectKey: varchar("object_key", { length: 512 }).notNull(),
    reference: varchar("reference", { length: 1024 }).notNull(),
    updatedAt: timestamp("updated_at", { fsp: 3 }).notNull()
  },
  (table) => [
    index("library_media_references_source_idx").on(table.sourceId),
    index("library_media_references_object_idx").on(table.objectKey)
  ]
);

export const libraryMediaCleanupJobs = mysqlTable(
  "library_media_cleanup_jobs",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    objectKey: varchar("object_key", { length: 512 }).notNull(),
    status: varchar("status", { length: 16 })
      .$type<"PENDING" | "PROCESSING" | "FAILED">()
      .notNull(),
    attempts: int("attempts").notNull(),
    lastError: text("last_error"),
    availableAt: timestamp("available_at", { fsp: 3 }).notNull(),
    createdAt: timestamp("created_at", { fsp: 3 }).notNull(),
    updatedAt: timestamp("updated_at", { fsp: 3 }).notNull()
  },
  (table) => [
    uniqueIndex("library_media_cleanup_jobs_object_key_unique").on(
      table.objectKey
    ),
    index("library_media_cleanup_jobs_status_available_idx").on(
      table.status,
      table.availableAt
    )
  ]
);

export const articleVersionMedia = mysqlTable(
  "article_version_media",
  {
    versionId: varchar("version_id", { length: 36 }).notNull(),
    mediaId: varchar("media_id", { length: 36 }).notNull(),
    reference: varchar("reference", { length: 1024 }).notNull()
  },
  (table) => [
    primaryKey({ columns: [table.versionId, table.mediaId] }),
    index("article_version_media_media_idx").on(table.mediaId)
  ]
);

export const articleSearch = mysqlTable(
  "article_search",
  {
    articleRowId: varchar("article_row_id", { length: 36 }).primaryKey(),
    articleId: varchar("article_id", { length: 32 }).notNull(),
    versionId: varchar("version_id", { length: 36 }).notNull(),
    title: varchar("title", { length: 300 }).notNull(),
    summary: text("summary").notNull(),
    bodyText: text("body_text").notNull(),
    tagsText: text("tags_text").notNull(),
    studyText: text("study_text").notNull(),
    publishedAt: timestamp("published_at", { fsp: 3 }).notNull(),
    updatedAt: timestamp("updated_at", { fsp: 3 }).notNull()
  },
  (table) => [index("article_search_article_idx").on(table.articleId)]
);

export const mediaCleanupJobs = mysqlTable(
  "media_cleanup_jobs",
  {
    id: varchar("id", { length: 36 }).primaryKey(),
    objectKey: varchar("object_key", { length: 512 }).notNull(),
    articlePublicId: varchar("article_public_id", { length: 32 }).notNull(),
    status: varchar("status", { length: 16 })
      .$type<"PENDING" | "PROCESSING" | "FAILED">()
      .notNull(),
    attempts: int("attempts").notNull(),
    lastError: text("last_error"),
    createdAt: timestamp("created_at", { fsp: 3 }).notNull(),
    updatedAt: timestamp("updated_at", { fsp: 3 }).notNull()
  },
  (table) => [
    uniqueIndex("media_cleanup_jobs_object_key_unique").on(table.objectKey),
    index("media_cleanup_jobs_status_updated_idx").on(
      table.status,
      table.updatedAt
    )
  ]
);

export type PublishKeyRow = typeof publishKeys.$inferSelect;
export type ArticleRow = typeof articles.$inferSelect;
export type ArticleVersionRow = typeof articleVersions.$inferSelect;
export type MediaAssetRow = typeof mediaAssets.$inferSelect;
export type LibraryMediaAssetRow = typeof libraryMediaAssets.$inferSelect;
export type LibraryMediaCleanupJobRow =
  typeof libraryMediaCleanupJobs.$inferSelect;
export type MediaCleanupJobRow = typeof mediaCleanupJobs.$inferSelect;
export const publishContractMetadata = {
  signedGetUsesEmptyBodyHash: true,
  articleSearchUsesFulltextIndex: true
};
