import type {
  ArticleSummary,
  ArticleView,
  PublishRepository,
  StorageAdapter,
  Visibility
} from "@/domain/types";
import { NotFoundError } from "@/domain/errors";
import { embedMediaAsDataUrls, escapeHtml } from "@/lib/html";

export class ReadService {
  constructor(
    private readonly repository: PublishRepository,
    private readonly storage: StorageAdapter
  ) {}

  async listPublic(limit = 60): Promise<ArticleSummary[]> {
    return this.repository.listPublicArticles(limit);
  }

  async search(query: string, limit = 60): Promise<ArticleSummary[]> {
    return this.repository.searchPublicArticles(query, limit);
  }

  async publicView(articleId: string): Promise<ArticleView> {
    return this.requireView(
      await this.repository.getArticleByPublicId(articleId),
      "PUBLIC"
    );
  }

  async unlistedView(token: string): Promise<ArticleView> {
    return this.requireView(
      await this.repository.getArticleByUnlistedToken(token),
      "UNLISTED"
    );
  }

  async mediaUrl(
    lookup: { type: "public"; articleId: string } | { type: "unlisted"; token: string },
    mediaId: string,
    expiresInSeconds: number
  ): Promise<string> {
    const view =
      lookup.type === "public"
        ? await this.publicView(lookup.articleId)
        : await this.unlistedView(lookup.token);
    const media = view.version.media.find((item) => item.mediaId === mediaId);
    if (!media) {
      throw new NotFoundError("文章媒体不存在");
    }
    return this.storage.createReadUrl(media.objectKey, expiresInSeconds);
  }

  async exportHtml(
    lookup: { type: "public"; articleId: string } | { type: "unlisted"; token: string }
  ): Promise<{ filename: string; html: string }> {
    const view =
      lookup.type === "public"
        ? await this.publicView(lookup.articleId)
        : await this.unlistedView(lookup.token);
    const embedded = await embedMediaAsDataUrls(
      view.version.readerHtml,
      view.version.media,
      (key) => this.storage.readObject(key)
    );
    const title = escapeHtml(view.version.title);
    const summary = escapeHtml(view.version.summary);
    const tags = view.version.tags
      .map((tag) => `<span>${escapeHtml(tag)}</span>`)
      .join("");
    const published = new Intl.DateTimeFormat("zh-CN", {
      year: "numeric",
      month: "long",
      day: "numeric"
    }).format(view.version.publishedAt);
    const toc = view.version.toc
      .map(
        (item) =>
          `<li class="toc-level-${item.level}"><a href="#${escapeHtml(item.id)}">${escapeHtml(item.text)}</a></li>`
      )
      .join("");
    const appendix = view.version.aiAppendix.length
      ? `
        <details class="ai-appendix">
          <summary>AI 研读附录 · ${view.version.aiAppendix.length} 项</summary>
          ${view.version.aiAppendix
            .map(
              (item) => `
                <section>
                  <h2>${escapeHtml(item.title)}</h2>
                  ${paragraphs(item.body)}
                </section>`
            )
            .join("")}
        </details>`
      : "";
    const html = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>${title} · StudyNotes</title>
  <style>${EXPORT_CSS}</style>
</head>
<body>
  <header class="export-header"><strong>StudyNotes</strong><span>公开内容 · 独立 HTML</span></header>
  <main class="export-layout">
    <nav class="export-toc" aria-label="文章目录">
      <h2>文章目录</h2>
      <ol>${toc}</ol>
    </nav>
    <article>
      <p class="article-meta">公开文章 · ${escapeHtml(published)}</p>
      <h1>${title}</h1>
      <p class="article-summary">${summary}</p>
      <div class="article-tags">${tags}</div>
      <div class="article-body">${embedded}</div>
      ${appendix}
    </article>
  </main>
</body>
</html>`;
    return {
      filename: `${safeFilename(view.version.title)}.html`,
      html
    };
  }

  private async requireView(
    article: Awaited<ReturnType<PublishRepository["getArticleByPublicId"]>>,
    visibility: Visibility
  ): Promise<ArticleView> {
    if (!article) {
      throw new NotFoundError();
    }
    if (article.visibility !== visibility) {
      throw new NotFoundError();
    }
    const view = await this.repository.getArticleView(article);
    if (!view) {
      throw new NotFoundError();
    }
    return view;
  }
}

function paragraphs(value: string): string {
  return value
    .split(/\n{2,}/)
    .map((part) => `<p>${escapeHtml(part).replaceAll("\n", "<br>")}</p>`)
    .join("");
}

function safeFilename(title: string): string {
  return (
    title
      .replace(/[\\/:*?"<>|]/g, "-")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 120) || "StudyNotes-article"
  );
}

const EXPORT_CSS = `
:root{color-scheme:light;--text:#1d2129;--secondary:#4e5969;--muted:#86909c;--border:#e5e6eb;--panel:#fafbfc;--blue:#3370ff;--blue-soft:#eaf1ff;--yellow-soft:#fff8e8;--yellow-border:#f5dba6}
*{box-sizing:border-box}body{margin:0;background:#fff;color:var(--text);font-family:"PingFang SC","Noto Sans CJK SC",sans-serif}
.export-header{height:64px;display:flex;align-items:center;justify-content:space-between;padding:0 40px;border-bottom:1px solid var(--border)}
.export-header strong{font-size:18px}.export-header span{font-size:12px;color:var(--secondary)}
.export-layout{max-width:1240px;margin:0 auto;display:grid;grid-template-columns:220px minmax(0,780px);gap:80px;padding:56px 40px}
.export-toc{position:sticky;top:32px;align-self:start;border-right:1px solid var(--border);padding-right:28px}
.export-toc h2{font-size:14px;margin:0 0 18px}.export-toc ol{list-style:none;margin:0;padding:0}.export-toc li{margin:10px 0}.export-toc a{color:var(--secondary);text-decoration:none;font-size:13px}.toc-level-3{padding-left:14px}.toc-level-4{padding-left:28px}
article h1{font-size:42px;line-height:1.28;margin:12px 0 16px}.article-meta{font-size:12px;color:var(--blue);margin:0}.article-summary{font-size:16px;line-height:1.8;color:var(--secondary)}
.article-tags{display:flex;gap:8px;margin:20px 0 32px}.article-tags span{border:1px solid var(--border);border-radius:6px;padding:5px 10px;font-size:12px;color:var(--secondary)}
.article-body{font-family:"Songti SC","Noto Serif CJK SC",serif;font-size:17px;line-height:1.9}.article-body h2,.article-body h3{font-family:"PingFang SC","Noto Sans CJK SC",sans-serif}.article-body h2{font-size:24px;margin:40px 0 14px}.article-body p{margin:0 0 20px}.article-body blockquote{margin:28px 0;padding:20px 24px;border-left:3px solid var(--blue);background:var(--blue-soft);color:#1747b5}.article-body img{max-width:100%;height:auto;border-radius:7px}
.public-annotation{margin:18px 0 26px;padding:16px 18px;border:1px solid var(--yellow-border);background:var(--yellow-soft);border-radius:7px}.public-annotation__label{font:600 11px/1.4 "PingFang SC",sans-serif;color:#7a4b00}.public-annotation blockquote{margin:8px 0;padding:0;border:0;background:none}.public-annotation p{font:400 13px/1.7 "PingFang SC",sans-serif;color:var(--secondary);margin:0}
.cognitive-load-diagram{margin:28px 0;padding:20px;background:var(--panel);border:1px solid var(--border);border-radius:7px}.cognitive-load-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.cognitive-load-grid section{padding:16px;border:1px solid var(--border);background:#fff;border-radius:6px}.cognitive-load-grid span{font-size:11px;color:var(--blue)}.cognitive-load-grid h3{font-size:15px;margin:6px 0}.cognitive-load-grid p{font-size:14px;color:var(--secondary)}.cognitive-load-grid small{color:var(--muted)}
.ai-appendix{margin:48px 0;padding:20px 24px;border:1px solid #c7d8ff;background:var(--blue-soft);border-radius:7px}.ai-appendix summary{font-weight:600;color:#1747b5;cursor:pointer}.ai-appendix section{margin-top:20px}.ai-appendix h2{font-size:18px}.ai-appendix p{font:400 14px/1.8 "PingFang SC",sans-serif;color:var(--secondary)}
@media(max-width:800px){.export-header{padding:0 20px}.export-layout{display:block;padding:32px 20px}.export-toc{position:static;border:0;padding:0 0 24px}.article h1{font-size:32px}.cognitive-load-grid{grid-template-columns:1fr}}
@media print{.export-header{display:none}.export-layout{display:block;padding:0}.export-toc{position:static;border:0;padding:0 0 24px}.ai-appendix{break-inside:avoid}}
`;
