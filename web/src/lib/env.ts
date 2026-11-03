import { AppError } from "@/domain/errors";

function optional(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value ? value : undefined;
}

function required(name: string): string {
  const value = optional(name);
  if (!value) {
    throw new AppError(`缺少服务端配置 ${name}`, 500, "CONFIGURATION_ERROR");
  }
  return value;
}

export function getRuntimeConfig() {
  return {
    repositoryMode: optional("STUDYNOTES_REPOSITORY") ?? "mysql",
    storageMode: optional("STUDYNOTES_STORAGE") ?? "qiniu",
    databaseUrl: optional("DATABASE_URL"),
    baseUrl: optional("STUDYNOTES_BASE_URL") ?? "http://127.0.0.1:8090",
    registrationSecret: optional("PUBLISH_REGISTRATION_SECRET"),
    timestampSkewSeconds: Number(
      optional("PUBLISH_TIMESTAMP_SKEW_SECONDS") ?? "300"
    ),
    mediaUrlTtlSeconds: Number(optional("MEDIA_URL_TTL_SECONDS") ?? "300"),
    libraryMediaKeyHash: optional("LIBRARY_MEDIA_KEY_SHA256"),
    libraryMediaCleanupDelaySeconds: Number(
      optional("LIBRARY_MEDIA_CLEANUP_DELAY_SECONDS") ?? "86400"
    ),
    qiniu: {
      accessKey: optional("QINIU_ACCESS_KEY"),
      secretKey: optional("QINIU_SECRET_KEY"),
      bucket: optional("QINIU_BUCKET"),
      domain: optional("QINIU_DOMAIN"),
      uploadUrl: optional("QINIU_UPLOAD_URL") ?? "https://upload.qiniup.com"
    }
  };
}

export function requireDatabaseUrl(): string {
  return required("DATABASE_URL");
}

export function requireRegistrationSecret(): string {
  return required("PUBLISH_REGISTRATION_SECRET");
}

export function requireQiniuConfig() {
  const config = {
    accessKey: required("QINIU_ACCESS_KEY"),
    secretKey: required("QINIU_SECRET_KEY"),
    bucket: required("QINIU_BUCKET"),
    domain: required("QINIU_DOMAIN").replace(/\/+$/, ""),
    uploadUrl: optional("QINIU_UPLOAD_URL") ?? "https://upload.qiniup.com"
  };
  for (const [name, value] of Object.entries({
    QINIU_ACCESS_KEY: config.accessKey,
    QINIU_SECRET_KEY: config.secretKey,
    QINIU_BUCKET: config.bucket,
    QINIU_DOMAIN: config.domain
  })) {
    if (value.startsWith("replace-with-")) {
      throw new AppError(
        `${name} 仍是示例占位值，请配置真实七牛凭据或改用 STUDYNOTES_STORAGE=memory`,
        500,
        "CONFIGURATION_ERROR"
      );
    }
  }
  return config;
}

export function assertRuntimeStorageConfigured() {
  const mode = optional("STUDYNOTES_STORAGE") ?? "qiniu";
  if (mode === "memory") {
    return;
  }
  if (mode !== "qiniu") {
    throw new AppError(
      `不支持的 STUDYNOTES_STORAGE=${mode}`,
      500,
      "CONFIGURATION_ERROR"
    );
  }
  requireQiniuConfig();
}
