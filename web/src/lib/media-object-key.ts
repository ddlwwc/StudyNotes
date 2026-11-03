import { extensionForContentType } from "@/lib/media-content-type";

export function libraryObjectKey(
  contentHash: string,
  contentType: string
): string {
  return `library-media/${hashHex(contentHash)}.${extensionForContentType(contentType)}`;
}

export function publishedObjectKey(
  contentHash: string,
  contentType: string
): string {
  return `published-media/${hashHex(contentHash)}.${extensionForContentType(contentType)}`;
}

function hashHex(contentHash: string): string {
  return contentHash.slice("sha256:".length);
}
