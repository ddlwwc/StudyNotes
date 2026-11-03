import {
  createHash,
  createPrivateKey,
  createPublicKey,
  sign,
  verify,
  type KeyObject
} from "node:crypto";
import { AuthenticationError, ValidationError } from "@/domain/errors";
import type { PublicKeyJwk } from "@/domain/types";

export interface SignatureHeaders {
  keyId: string;
  timestamp: string;
  nonce: string;
  signature: string;
  contentSha256: string;
}

export interface SignedRequestInput {
  method: string;
  pathname: string;
  searchParams?: URLSearchParams;
  body: string;
}

export function sha256(value: string | Buffer): string {
  return `sha256:${createHash("sha256").update(value).digest("hex")}`;
}

export function canonicalizeQuery(searchParams?: URLSearchParams): string {
  if (!searchParams) {
    return "";
  }
  const entries = [...searchParams.entries()].sort(([leftKey, leftValue], [rightKey, rightValue]) => {
    if (leftKey === rightKey) {
      return leftValue.localeCompare(rightValue);
    }
    return leftKey.localeCompare(rightKey);
  });
  return entries
    .map(
      ([key, value]) =>
        `${encodeURIComponent(key)}=${encodeURIComponent(value)}`
    )
    .join("&");
}

export function canonicalPathAndQuery(input: SignedRequestInput): string {
  const query = canonicalizeQuery(input.searchParams);
  return query ? `${input.pathname}?${query}` : input.pathname;
}

export function createCanonicalString(
  input: SignedRequestInput,
  timestamp: string,
  nonce: string,
  bodyHash: string
): string {
  return [
    input.method.toUpperCase(),
    canonicalPathAndQuery(input),
    timestamp,
    nonce,
    bodyHash
  ].join("\n");
}

export function signRequest(
  input: SignedRequestInput,
  privateKey: KeyObject,
  options: { timestamp?: string; nonce: string }
): SignatureHeaders {
  const timestamp =
    options.timestamp ?? Math.floor(Date.now() / 1000).toString();
  const bodyHash = sha256(input.body);
  const canonical = createCanonicalString(
    input,
    timestamp,
    options.nonce,
    bodyHash
  );
  const signature = sign(null, Buffer.from(canonical), privateKey).toString(
    "base64url"
  );

  return {
    keyId: "",
    timestamp,
    nonce: options.nonce,
    signature,
    contentSha256: bodyHash
  };
}

export function verifyRequestSignature(
  input: SignedRequestInput,
  headers: SignatureHeaders,
  publicKeyJwk: PublicKeyJwk
): void {
  const computedHash = sha256(input.body);
  if (computedHash !== headers.contentSha256) {
    throw new AuthenticationError("请求体摘要不匹配");
  }

  const canonical = createCanonicalString(
    input,
    headers.timestamp,
    headers.nonce,
    headers.contentSha256
  );

  let publicKey: KeyObject;
  try {
    publicKey = createPublicKey({
      key: publicKeyJwk as unknown as JsonWebKey,
      format: "jwk"
    });
  } catch {
    throw new AuthenticationError("发布公钥格式无效");
  }

  const valid = verify(
    null,
    Buffer.from(canonical),
    publicKey,
    Buffer.from(headers.signature, "base64url")
  );
  if (!valid) {
    throw new AuthenticationError();
  }
}

export function assertTimestampFresh(
  timestamp: string,
  skewSeconds: number,
  now = Date.now()
): Date {
  if (!/^\d{10}$/.test(timestamp)) {
    throw new AuthenticationError("请求时间戳格式无效");
  }
  const requestSeconds = Number(timestamp);
  const nowSeconds = Math.floor(now / 1000);
  if (Math.abs(nowSeconds - requestSeconds) > skewSeconds) {
    throw new AuthenticationError("请求时间戳已过期");
  }
  return new Date(requestSeconds * 1000);
}

export function assertNonceFormat(nonce: string): void {
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(nonce)) {
    throw new ValidationError("请求随机数格式无效");
  }
}

export function parsePrivateKeyJwk(jwk: JsonWebKey): KeyObject {
  return createPrivateKey({ key: jwk, format: "jwk" });
}

export function publicJwkFromPrivateKey(jwk: JsonWebKey): PublicKeyJwk {
  if (
    jwk.kty !== "OKP" ||
    jwk.crv !== "Ed25519" ||
    typeof jwk.x !== "string"
  ) {
    throw new ValidationError("不是有效的 Ed25519 JWK");
  }
  return {
    kty: "OKP",
    crv: "Ed25519",
    x: jwk.x,
    use: "sig",
    alg: "EdDSA"
  };
}
