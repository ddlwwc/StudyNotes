import { load, type CheerioAPI } from "cheerio";
import sanitizeHtml from "sanitize-html";
import type {
  ArticleAnnotation,
  TableOfContentsItem,
  VersionMedia
} from "@/domain/types";
import { ValidationError } from "@/domain/errors";

const ALLOWED_TAGS = [
  "h1",
  "h2",
  "h3",
  "h4",
  "p",
  "br",
  "strong",
  "em",
  "blockquote",
  "ul",
  "ol",
  "li",
  "a",
  "img",
  "figure",
  "figcaption",
  "code",
  "pre",
  "hr",
  "table",
  "thead",
  "tbody",
  "tr",
  "th",
  "td",
  "mark",
  "aside",
  "details",
  "summary"
];

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function sanitizeArticleHtml(source: string): string {
  return sanitizeHtml(source, {
    allowedTags: ALLOWED_TAGS,
    allowedAttributes: {
      a: ["href", "title", "target", "rel", "download", "data-object-key"],
      img: ["alt", "title", "width", "height", "data-object-key"],
      "*": ["id", "class", "data-block-id"]
    },
    allowedSchemes: ["http", "https", "mailto", "media"],
    allowedSchemesByTag: {
      img: []
    },
    transformTags: {
      a: (_tagName, attributes) => ({
        tagName: "a",
        attribs: attachmentAttributes(attributes)
      }),
      img: (_tagName, attributes) => {
        const objectKey = mediaObjectKey(attributes.src) ?? attributes["data-object-key"];
        const { src: _src, ...rest } = attributes;
        void _src;
        return {
          tagName: "img",
          attribs: objectKey ? { ...rest, "data-object-key": objectKey } : rest
        };
      }
    }
  });
}

export function referencedMediaKeys(html: string): string[] {
  const $ = load(html);
  const keys = new Set<string>();
  $("[data-object-key]").each((_index, element) => {
    const node = $(element);
    const key =
      node.attr("data-object-key") ??
      mediaObjectKey(node.attr("src")) ??
      mediaObjectKey(node.attr("href"));
    if (key) {
      keys.add(key);
    }
  });
  return [...keys];
}

export function plainTextFromHtml(html: string): string {
  const $ = load(html);
  return $("body").text().replace(/\s+/g, " ").trim();
}

function slugify(value: string, index: number): string {
  const ascii = value
    .trim()
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}]+/gu, "-")
    .replace(/^-+|-+$/g, "");
  return ascii || `section-${index + 1}`;
}

function assignHeadingIds($: CheerioAPI): TableOfContentsItem[] {
  const used = new Set<string>();
  const toc: TableOfContentsItem[] = [];
  $("h2, h3, h4").each((index, element) => {
    const node = $(element);
    const text = node.text().replace(/\s+/g, " ").trim();
    if (!text) {
      return;
    }
    const base = node.attr("id")?.trim() || slugify(text, index);
    let id = base;
    let suffix = 2;
    while (used.has(id)) {
      id = `${base}-${suffix}`;
      suffix += 1;
    }
    used.add(id);
    node.attr("id", id);
    toc.push({
      id,
      text,
      level: Number(element.tagName.slice(1))
    });
  });
  return toc;
}

function annotationMarkup(annotation: ArticleAnnotation): string {
  const note = escapeHtml(annotation.note).replaceAll("\n", "<br>");
  return [
    `<aside class="public-annotation" data-annotation-id="${escapeHtml(annotation.id)}">`,
    '<span class="public-annotation__label">公开标注</span>',
    `<blockquote>${escapeHtml(annotation.quote)}</blockquote>`,
    `<p>${note}</p>`,
    "</aside>"
  ].join("");
}

function normalizedText(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function blockPathParts(value: string | number[] | undefined): number[] | null {
  if (value === undefined) {
    return null;
  }
  const parts = Array.isArray(value)
    ? value.map(String)
    : value.trim().split(/[./]/);
  if (
    parts.length === 0 ||
    parts.some((part) => !/^\d+$/.test(part))
  ) {
    return null;
  }
  return parts.map(Number);
}

export function buildReaderContent(
  sourceHtml: string,
  annotations: ArticleAnnotation[]
): { bodyHtml: string; readerHtml: string; toc: TableOfContentsItem[] } {
  const bodyHtml = sanitizeArticleHtml(sourceHtml);
  const $ = load(`<main id="article-body">${bodyHtml}</main>`, null, false);
  $("img:not([data-object-key])").remove();
  $("a[href^='media:']:not([data-object-key])").remove();

  annotations.forEach((annotation) => {
    const quote = normalizedText(annotation.quote);
    let target = $();

    for (const anchor of [annotation.blockPath, annotation.blockId]) {
      const path = blockPathParts(anchor);
      if (path) {
        let scope = $("main");
        for (const index of path) {
          scope = scope.children().eq(index);
          if (!scope.length) {
            break;
          }
        }
        if (scope.length) {
          if (!normalizedText(scope.text()).includes(quote)) {
            throw new ValidationError(
              `公开标注 ${annotation.id} 的块定位不包含摘录`
            );
          }
          target = scope;
        }
      } else if (typeof anchor === "string") {
        target = $("[id], [data-block-id]")
          .filter(
            (_index, element) =>
              $(element).attr("id") === anchor ||
              $(element).attr("data-block-id") === anchor
          )
          .first();
        if (target.length && !normalizedText(target.text()).includes(quote)) {
          throw new ValidationError(
            `公开标注 ${annotation.id} 的块定位不包含摘录`
          );
        }
      }
      if (target.length) {
        break;
      }
      if (anchor !== undefined) {
        throw new ValidationError(
          `公开标注 ${annotation.id} 的块定位无法在正文中找到`
        );
      }
    }

    if (!target.length) {
      const candidates = $("h1, h2, h3, h4, p, li, blockquote, td")
        .filter(
          (_index, element) =>
            normalizedText($(element).text()).includes(quote)
        )
        .toArray();
      if (candidates.length > 1) {
        throw new ValidationError(
          `公开标注 ${annotation.id} 的摘录重复，必须提供 blockId 或 blockPath`
        );
      }
      target = candidates.length ? $(candidates[0]!) : $();
    }

    if (!target.length) {
      throw new ValidationError(`公开标注 ${annotation.id} 的锚点无法在正文中定位`);
    }

    target.addClass("has-public-annotation");
    target.attr("data-has-annotation", "true");
    target.after(annotationMarkup(annotation));
  });

  const toc = assignHeadingIds($);
  return {
    bodyHtml,
    readerHtml: $("main").html() ?? bodyHtml,
    toc
  };
}

export function rewriteMediaReferences(
  html: string,
  media: VersionMedia[],
  basePath: string
): string {
  const byKey = new Map(media.map((item) => [item.objectKey, item]));
  const $ = load(`<main id="article-body">${html}</main>`, null, false);
  $("[data-object-key]").each((_index, element) => {
    const node = $(element);
    const key = $(element).attr("data-object-key");
    const asset = key ? byKey.get(key) : undefined;
    if (!asset) {
      $(element).remove();
      return;
    }
    const url = `${basePath}/media/${asset.mediaId}`;
    if (element.tagName === "img") {
      node.attr("src", url);
      node.attr("loading", "lazy");
      node.attr("decoding", "async");
    } else if (element.tagName === "a") {
      node.attr("href", url);
      node.attr("download", "attachment");
    }
  });
  return $("main").html() ?? html;
}

export async function embedMediaAsDataUrls(
  html: string,
  media: VersionMedia[],
  readObject: (objectKey: string) => Promise<Buffer>
): Promise<string> {
  const byKey = new Map(media.map((item) => [item.objectKey, item]));
  const dataByKey = new Map<string, string>();
  for (const item of media) {
    const bytes = await readObject(item.objectKey);
    dataByKey.set(
      item.objectKey,
      `data:${item.contentType};base64,${bytes.toString("base64")}`
    );
  }

  const $ = load(`<main id="article-body">${html}</main>`, null, false);
  $("[data-object-key]").each((_index, element) => {
    const node = $(element);
    const key = $(element).attr("data-object-key");
    const data = key ? dataByKey.get(key) : undefined;
    const asset = key ? byKey.get(key) : undefined;
    if (!data || !asset) {
      $(element).remove();
      return;
    }
    if (element.tagName === "img") {
      node.attr("src", data);
    } else if (element.tagName === "a") {
      node.attr("href", data);
      node.attr("download", "attachment");
    }
    node.removeAttr("data-object-key");
  });
  return $("main").html() ?? html;
}

export function rewriteMediaObjectKeys(
  html: string,
  replacements: Map<string, string>
): string {
  if (!replacements.size) {
    return html;
  }
  const $ = load(`<main id="article-body">${html}</main>`, null, false);
  $("[data-object-key]").each((_index, element) => {
    const node = $(element);
    const key = node.attr("data-object-key");
    if (key && replacements.has(key)) {
      node.attr("data-object-key", replacements.get(key));
    }
  });
  $("[src], [href]").each((_index, element) => {
    const node = $(element);
    for (const attribute of ["src", "href"] as const) {
      const value = node.attr(attribute);
      if (!value?.startsWith("media://qiniu/")) {
        continue;
      }
      const key = value.slice("media://qiniu/".length);
      if (replacements.has(key)) {
        node.attr(attribute, `media://qiniu/${replacements.get(key)}`);
      }
    }
  });
  return $("main").html() ?? html;
}

function attachmentAttributes(
  attributes: Record<string, string>
): Record<string, string> {
  const objectKey = mediaObjectKey(attributes.href);
  if (objectKey) {
    return { ...attributes, "data-object-key": objectKey };
  }
  if (attributes.href?.startsWith("media:")) {
    const { href: _href, ...rest } = attributes;
    void _href;
    return rest;
  }
  return attributes.href?.startsWith("http") === true
    ? {
        ...attributes,
        target: "_blank",
        rel: "noopener noreferrer"
      }
    : attributes;
}

function mediaObjectKey(value: string | undefined): string | undefined {
  const prefix = "media://qiniu/";
  return value?.startsWith(prefix) ? value.slice(prefix.length) : undefined;
}
