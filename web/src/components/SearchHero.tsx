import { Search } from "lucide-react";

const TAGS = ["认知心理", "学习方法", "程序设计", "知识管理"];

export function SearchHero({ query = "" }: { query?: string }) {
  return (
    <section className="public-hero">
      <div className="public-hero__inner">
        <p className="eyebrow">PUBLIC READING</p>
        <h1>公开学习资料</h1>
        <p className="public-hero__description">
          浏览已发布的学习文章，支持全站搜索、目录、公开研读层与独立导出。
        </p>
        <form className="search-form" action="/search" method="get">
          <label className="search-field">
            <Search size={20} strokeWidth={1.8} aria-hidden="true" />
            <input
              type="search"
              name="q"
              defaultValue={query}
              placeholder="搜索标题、正文、标签或公开研读内容"
              aria-label="全站搜索"
            />
            <span className="search-shortcut">⌘ K</span>
          </label>
          <button className="primary-button" type="submit">
            搜索
          </button>
        </form>
        <div className="quick-tags" aria-label="热门标签">
          <span className="quick-tags__label">热门标签</span>
          {TAGS.map((tag) => (
            <a
              className="chip"
              href={`/search?q=${encodeURIComponent(tag)}`}
              key={tag}
            >
              {tag}
            </a>
          ))}
        </div>
      </div>
    </section>
  );
}
