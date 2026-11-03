import { ArticleCard } from "@/components/ArticleCard";
import { SearchHero } from "@/components/SearchHero";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { getReadService } from "@/lib/services";

export const dynamic = "force-dynamic";

interface SearchPageProps {
  searchParams: Promise<{ q?: string }>;
}

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const { q = "" } = await searchParams;
  const query = q.trim();
  const articles = await getReadService().search(query);
  return (
    <>
      <SiteHeader />
      <SearchHero query={query} />
      <main className="library">
        <div className="library__heading">
          <h2>{query ? `“${query}” 的搜索结果` : "全部公开文章"}</h2>
          <span className="library__count">共 {articles.length} 篇</span>
        </div>
        <div className="filter-row" aria-label="搜索范围">
          <span className="chip chip--active">全部</span>
          <span className="chip">标题</span>
          <span className="chip">正文</span>
          <span className="chip">标签</span>
          <span className="chip">公开研读层</span>
        </div>
        {articles.length ? (
          <div className="article-grid">
            {articles.map((article) => (
              <ArticleCard article={article} key={article.articleId} />
            ))}
          </div>
        ) : (
          <section className="empty-state">
            <h2>没有找到匹配的公开文章</h2>
            <p>可以换一个标题、正文关键词或标签重新搜索。</p>
          </section>
        )}
        <SiteFooter />
      </main>
    </>
  );
}
