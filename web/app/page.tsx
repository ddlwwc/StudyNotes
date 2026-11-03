import { ArticleCard } from "@/components/ArticleCard";
import { SearchHero } from "@/components/SearchHero";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { getReadService } from "@/lib/services";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const articles = await getReadService().listPublic();
  const filters = ["全部", "认知科学", "学习方法", "编程技术", "阅读笔记"];
  return (
    <>
      <SiteHeader />
      <SearchHero />
      <main className="library">
        <div className="library__heading">
          <h2>全部公开文章</h2>
          <span className="library__count">共 {articles.length} 篇</span>
        </div>
        <div className="filter-row" aria-label="文章分类">
          {filters.map((filter, index) => (
            <span
              className={`chip${index === 0 ? " chip--active" : ""}`}
              key={filter}
            >
              {filter}
            </span>
          ))}
        </div>
        {articles.length ? (
          <div className="article-grid">
            {articles.map((article) => (
              <ArticleCard article={article} key={article.articleId} />
            ))}
          </div>
        ) : (
          <section className="empty-state">
            <h2>还没有公开文章</h2>
            <p>从 Mac 发布第一篇文章后，它会出现在这里。</p>
          </section>
        )}
        <SiteFooter />
      </main>
    </>
  );
}
