import type { MediaMetadata } from "@/domain/types";

export function normalizeContentType(value: string): string {
  return value.split(";")[0]!.trim().toLowerCase();
}

export function sameMediaMetadata(
  left: MediaMetadata,
  right: MediaMetadata
): boolean {
  return (
    left.contentHash === right.contentHash &&
    normalizeContentType(left.contentType) ===
      normalizeContentType(right.contentType) &&
    left.size === right.size
  );
}

export function extensionForContentType(contentType: string): string {
  const normalized = normalizeContentType(contentType);
  return (
    {
      "image/png": "png",
      "image/jpeg": "jpg",
      "image/gif": "gif",
      "image/webp": "webp",
      "image/heic": "heic",
      "application/pdf": "pdf",
      "text/plain": "txt",
      "text/markdown": "md",
      "application/zip": "zip"
    }[normalized] ?? "bin"
  );
}
