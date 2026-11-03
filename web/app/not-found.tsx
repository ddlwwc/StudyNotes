import Link from "next/link";
import { SiteHeader } from "@/components/SiteHeader";

export default function NotFound() {
  return (
    <>
      <SiteHeader />
      <main className="not-found">
        <p className="eyebrow">404</p>
        <h1>这篇文章当前不可访问</h1>
        <p>文章可能已下架、永久删除，或链接不属于当前公开状态。</p>
        <Link className="chip chip--active" href="/">
          返回公开阅览室
        </Link>
      </main>
    </>
  );
}
