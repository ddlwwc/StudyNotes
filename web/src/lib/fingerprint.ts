import { createHash } from "node:crypto";
import type {
  AiAppendixItem,
  ArticleAnnotation,
  MediaReferenceInput
} from "@/domain/types";

export interface FingerprintInput {
  title: string;
  summary: string;
  bodyHtml: string;
  tags: string[];
  annotations: ArticleAnnotation[];
  aiAppendix: AiAppendixItem[];
  mediaRefs: MediaReferenceInput[];
}

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(stableValue);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, nested]) => [key, stableValue(nested)])
    );
  }
  return value;
}

export function computePublishFingerprint(input: FingerprintInput): string {
  const canonical = JSON.stringify(
    stableValue({
      title: input.title.trim(),
      summary: input.summary.trim(),
      bodyHtml: input.bodyHtml,
      tags: input.tags.map((tag) => tag.trim()).sort(),
      annotations: input.annotations,
      aiAppendix: input.aiAppendix,
      mediaRefs: input.mediaRefs
        .map((media) => ({
          objectKey: media.objectKey,
          contentHash: media.contentHash,
          contentType: media.contentType,
          size: media.size,
          reference: media.reference
        }))
        .sort((left, right) => left.objectKey.localeCompare(right.objectKey))
    })
  );
  return `sha256:${createHash("sha256").update(canonical).digest("hex")}`;
}
