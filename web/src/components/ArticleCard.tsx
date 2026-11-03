import Link from "next/link";
import type { ArticleSummary } from "@/domain/types";

const formatter = new Intl.DateTimeFormat("zh-CN", {
  month: "long",
  day: "numeric"
});

export function ArticleCard({ article }: { article: ArticleSummary }) {
  return (
    <Link className="article-card" href={`/a/${article.articleId}`}>
      <div className="article-card__top">
        <span>{article.tags[0] ?? "学习资料"}</span>
        <span className="article-card__date">
          {formatter.format(article.publishedAt)}
        </span>
      </div>
      <h3>{article.title}</h3>
      <p className="article-card__summary">
        {article.summary || "这是一篇由发布者主动公开的只读学习文章。"}
      </p>
      <div className="article-card__bottom">
        <span className="tag">{article.tags[0] ?? "学习笔记"}</span>
        <span className="article-card__meta">公开 · 约 8 分钟</span>
      </div>
    </Link>
  );
}
