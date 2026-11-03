export class AppError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code: string,
    public readonly details?: unknown
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class ValidationError extends AppError {
  constructor(message: string, details?: unknown) {
    super(message, 422, "VALIDATION_ERROR", details);
  }
}

export class AuthenticationError extends AppError {
  constructor(message = "发布请求签名验证失败", details?: unknown) {
    super(message, 401, "AUTHENTICATION_FAILED", details);
  }
}

export class ReplayError extends AppError {
  constructor(message = "请求随机数已使用") {
    super(message, 409, "REPLAY_DETECTED");
  }
}

export class NotFoundError extends AppError {
  constructor(message = "文章不存在") {
    super(message, 404, "NOT_FOUND");
  }
}

export class ConflictError extends AppError {
  constructor(message = "发布版本冲突", details?: unknown) {
    super(message, 409, "VERSION_CONFLICT", details);
  }
}

export class IdempotencyMismatchError extends AppError {
  constructor() {
    super("同一请求标识携带了不同请求内容", 409, "IDEMPOTENCY_MISMATCH");
  }
}

export class ExternalServiceError extends AppError {
  constructor(message: string, details?: unknown) {
    super(message, 502, "EXTERNAL_SERVICE_ERROR", details);
  }
}
