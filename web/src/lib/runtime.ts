import { requireDatabaseUrl, requireQiniuConfig, getRuntimeConfig } from "@/lib/env";
import { MemoryRepository } from "@/lib/repository/memory";
import { MySqlRepository } from "@/lib/repository/mysql";
import { seedMemoryRepository } from "@/lib/repository/seed";
import { MemoryStorageAdapter } from "@/lib/storage/memory";
import { QiniuStorageAdapter } from "@/lib/storage/qiniu";
import type {
  PublishRepository,
  StorageAdapter
} from "@/domain/types";

interface RuntimeSingletons {
  repository?: PublishRepository;
  storage?: StorageAdapter;
  memoryStorage?: MemoryStorageAdapter;
}

const globalRuntime = globalThis as typeof globalThis & {
  __studynotesRuntime?: RuntimeSingletons;
};

function runtime(): RuntimeSingletons {
  globalRuntime.__studynotesRuntime ??= {};
  return globalRuntime.__studynotesRuntime;
}

export function getRepository(): PublishRepository {
  const singletons = runtime();
  if (!singletons.repository) {
    const config = getRuntimeConfig();
    if (config.repositoryMode === "memory") {
      const repository = new MemoryRepository();
      seedMemoryRepository(repository);
      singletons.repository = repository;
    } else {
      singletons.repository = new MySqlRepository(requireDatabaseUrl());
    }
  }
  return singletons.repository;
}

export function getStorage(): StorageAdapter {
  const singletons = runtime();
  if (!singletons.storage) {
    const config = getRuntimeConfig();
    if (config.storageMode === "memory") {
      singletons.memoryStorage = new MemoryStorageAdapter();
      singletons.storage = singletons.memoryStorage;
    } else {
      singletons.storage = new QiniuStorageAdapter(requireQiniuConfig());
    }
  }
  return singletons.storage;
}

export function getMemoryStorage(): MemoryStorageAdapter {
  getStorage();
  const storage = runtime().memoryStorage;
  if (!storage) {
    throw new Error("当前不是内存存储模式");
  }
  return storage;
}
