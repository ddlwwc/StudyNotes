import { randomBytes, randomUUID } from "node:crypto";

const PUBLIC_ID_ALPHABET =
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

export function randomId(length = 22): string {
  const bytes = randomBytes(length);
  let result = "";
  for (let index = 0; index < length; index += 1) {
    result += PUBLIC_ID_ALPHABET[bytes[index]! % PUBLIC_ID_ALPHABET.length];
  }
  return result;
}

export function randomUuid(): string {
  return randomUUID();
}

export function randomNonce(): string {
  return randomBytes(24).toString("base64url");
}
