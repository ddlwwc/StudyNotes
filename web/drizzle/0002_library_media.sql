CREATE TABLE `library_media_assets` (
  `id` varchar(36) NOT NULL,
  `object_key` varchar(512) NOT NULL,
  `content_hash` varchar(71) NOT NULL,
  `content_type` varchar(128) NOT NULL,
  `size` int NOT NULL,
  `status` varchar(16) NOT NULL,
  `created_at` timestamp(3) NOT NULL,
  `verified_at` timestamp(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `library_media_assets_object_key_unique` (`object_key`),
  UNIQUE KEY `library_media_assets_content_hash_unique` (`content_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `library_media_references` (
  `id` varchar(36) NOT NULL,
  `source_id` varchar(128) NOT NULL,
  `scope` varchar(16) NOT NULL,
  `object_key` varchar(512) NOT NULL,
  `reference` varchar(1024) NOT NULL,
  `updated_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `library_media_references_source_idx` (`source_id`),
  KEY `library_media_references_object_idx` (`object_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `library_media_cleanup_jobs` (
  `id` varchar(36) NOT NULL,
  `object_key` varchar(512) NOT NULL,
  `status` varchar(16) NOT NULL,
  `attempts` int NOT NULL,
  `last_error` text,
  `available_at` timestamp(3) NOT NULL,
  `created_at` timestamp(3) NOT NULL,
  `updated_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `library_media_cleanup_jobs_object_key_unique` (`object_key`),
  KEY `library_media_cleanup_jobs_status_available_idx` (`status`, `available_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
