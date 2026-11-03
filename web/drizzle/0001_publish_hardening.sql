CREATE TABLE `publish_locks` (
  `lock_key` varchar(512) NOT NULL,
  `created_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`lock_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--> statement-breakpoint
CREATE TABLE `media_cleanup_jobs` (
  `id` varchar(36) NOT NULL,
  `object_key` varchar(512) NOT NULL,
  `article_public_id` varchar(32) NOT NULL,
  `status` varchar(16) NOT NULL,
  `attempts` int NOT NULL,
  `last_error` text,
  `created_at` timestamp(3) NOT NULL,
  `updated_at` timestamp(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `media_cleanup_jobs_object_key_unique` (`object_key`),
  KEY `media_cleanup_jobs_status_updated_idx` (`status`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
