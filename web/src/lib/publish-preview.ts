import type {
  AiAppendixItem,
  ArticleAnnotation,
  MediaReferenceInput
} from "@/domain/types";

export interface PublishDraft {
  requestId: string;
  articleId?: string;
  sourceMaterialId: string;
  sourceVersionId?: string | null;
  expectedVersion: number;
  visibility: "PUBLIC" | "UNLISTED";
  title: string;
  summary?: string;
  bodyHtml: string;
  tags?: string[];
  annotations?: ArticleAnnotation[];
  aiAppendix?: AiAppendixItem[];
  mediaRefs?: MediaReferenceInput[];
  publishAnnotations?: boolean;
  publishAi?: boolean;
}

export interface PublishRequestPayload {
  requestId: string;
  articleId?: string;
  sourceMaterialId: string;
  sourceVersionId: string | null;
  expectedVersion: number;
  visibility: "PUBLIC" | "UNLISTED";
  title: string;
  summary: string;
  bodyHtml: string;
  tags: string[];
  publishAnnotations: boolean;
  publishAi: boolean;
  annotations?: ArticleAnnotation[];
  aiAppendix?: AiAppendixItem[];
  mediaRefs?: MediaReferenceInput[];
}

export function preparePublishRequest(
  draft: PublishDraft
): PublishRequestPayload {
  const publishAnnotations = draft.publishAnnotations ?? false;
  const publishAi = draft.publishAi ?? false;
  const payload: PublishRequestPayload = {
    requestId: draft.requestId,
    sourceMaterialId: draft.sourceMaterialId,
    sourceVersionId: draft.sourceVersionId ?? null,
    expectedVersion: draft.expectedVersion,
    visibility: draft.visibility,
    title: draft.title.trim(),
    summary: draft.summary?.trim() ?? "",
    bodyHtml: draft.bodyHtml,
    tags: draft.tags ?? [],
    publishAnnotations,
    publishAi
  };

  if (draft.articleId) {
    payload.articleId = draft.articleId;
  }
  if (publishAnnotations && draft.annotations?.length) {
    payload.annotations = draft.annotations;
  }
  if (publishAi && draft.aiAppendix?.length) {
    payload.aiAppendix = draft.aiAppendix;
  }
  if (draft.mediaRefs?.length) {
    payload.mediaRefs = draft.mediaRefs;
  }
  return payload;
}
