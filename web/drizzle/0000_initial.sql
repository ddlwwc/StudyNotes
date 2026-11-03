CREATE TABLE `publish_keys` (
  `id` varchar(36) NOT NULL,
  `kid` varchar(128) NOT NULL,
  `public_key_jwk` json NOT NULL,
  `status` varchar(16) NOT NULL,
  `created_at` timestamp(3) NOT NULL,
  `revoked_at` timestamp(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `publish_keys_kid_unique` (`kid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `request_nonces` (
  `key_id` varchar(128) NOT NULL,
  `nonce` varchar(128) NOT NULL,
  `seen_at` timestamp(3) NOT NULL,
  `expires_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`key_id`, `nonce`),
  KEY `request_nonces_expiry_idx` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `articles` (
  `id` varchar(36) NOT NULL,
  `article_id` varchar(32) NOT NULL,
  `unlisted_token` varchar(64) NOT NULL,
  `source_material_id` varchar(128) NOT NULL,
  `visibility` varchar(16) NOT NULL,
  `current_version_id` varchar(36),
  `created_at` timestamp(3) NOT NULL,
  `updated_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `articles_public_id_unique` (`article_id`),
  UNIQUE KEY `articles_unlisted_token_unique` (`unlisted_token`),
  UNIQUE KEY `articles_source_material_unique` (`source_material_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `article_versions` (
  `id` varchar(36) NOT NULL,
  `article_row_id` varchar(36) NOT NULL,
  `version` int NOT NULL,
  `source_version_id` varchar(128),
  `fingerprint` varchar(71) NOT NULL,
  `title` varchar(300) NOT NULL,
  `summary` text NOT NULL,
  `body_html` longtext NOT NULL,
  `reader_html` longtext NOT NULL,
  `toc` json NOT NULL,
  `tags` json NOT NULL,
  `annotations` json NOT NULL,
  `ai_appendix` json NOT NULL,
  `visibility_at_publish` varchar(16) NOT NULL,
  `published_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `article_versions_article_version_unique` (`article_row_id`, `version`),
  UNIQUE KEY `article_versions_article_fingerprint_unique` (`article_row_id`, `fingerprint`),
  CONSTRAINT `article_versions_article_fk`
    FOREIGN KEY (`article_row_id`) REFERENCES `articles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `publish_requests` (
  `id` varchar(36) NOT NULL,
  `key_id` varchar(128) NOT NULL,
  `request_id` varchar(128) NOT NULL,
  `request_hash` varchar(71) NOT NULL,
  `article_row_id` varchar(36),
  `response_json` json NOT NULL,
  `created_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `publish_requests_key_request_unique` (`key_id`, `request_id`),
  KEY `publish_requests_article_idx` (`article_row_id`),
  CONSTRAINT `publish_requests_article_fk`
    FOREIGN KEY (`article_row_id`) REFERENCES `articles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `media_assets` (
  `id` varchar(36) NOT NULL,
  `object_key` varchar(512) NOT NULL,
  `content_hash` varchar(71) NOT NULL,
  `content_type` varchar(128) NOT NULL,
  `size` int NOT NULL,
  `status` varchar(16) NOT NULL,
  `created_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `media_assets_object_key_unique` (`object_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `article_version_media` (
  `version_id` varchar(36) NOT NULL,
  `media_id` varchar(36) NOT NULL,
  `reference` varchar(1024) NOT NULL,
  PRIMARY KEY (`version_id`, `media_id`),
  KEY `article_version_media_media_idx` (`media_id`),
  CONSTRAINT `article_version_media_version_fk`
    FOREIGN KEY (`version_id`) REFERENCES `article_versions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `article_version_media_media_fk`
    FOREIGN KEY (`media_id`) REFERENCES `media_assets` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `article_search` (
  `article_row_id` varchar(36) NOT NULL,
  `article_id` varchar(32) NOT NULL,
  `version_id` varchar(36) NOT NULL,
  `title` varchar(300) NOT NULL,
  `summary` text NOT NULL,
  `body_text` longtext NOT NULL,
  `tags_text` text NOT NULL,
  `study_text` longtext NOT NULL,
  `published_at` timestamp(3) NOT NULL,
  `updated_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`article_row_id`),
  KEY `article_search_article_idx` (`article_id`),
  CONSTRAINT `article_search_article_fk`
    FOREIGN KEY (`article_row_id`) REFERENCES `articles` (`id`) ON DELETE CASCADE,
  FULLTEXT KEY `article_search_fts`
    (`title`, `summary`, `body_text`, `tags_text`, `study_text`) WITH PARSER ngram
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
