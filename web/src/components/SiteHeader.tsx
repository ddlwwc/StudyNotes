import Link from "next/link";
import { BookOpen } from "lucide-react";

export function SiteHeader({ reading = false }: { reading?: boolean }) {
  return (
    <header className="site-header">
      <div className="site-header__inner">
        <span className="brand-mark" aria-hidden="true">
          <BookOpen size={16} strokeWidth={1.9} />
        </span>
        <Link className="brand-name" href="/">
          StudyNotes
        </Link>
        <span className="brand-divider" aria-hidden="true" />
        <span className="site-context">
          {reading ? "公开文章阅读" : "公开阅览室"}
        </span>
        <span className="read-only-badge">
          <BookOpen size={15} strokeWidth={1.8} aria-hidden="true" />
          <span>公开内容 · 只读浏览</span>
        </span>
      </div>
    </header>
  );
}
