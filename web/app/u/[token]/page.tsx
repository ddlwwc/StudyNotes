import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ArticleExperience } from "@/components/ArticleExperience";
import { SiteHeader } from "@/components/SiteHeader";
import { rewriteMediaReferences } from "@/lib/html";
import { getReadService } from "@/lib/services";

export const dynamic = "force-dynamic";

interface UnlistedPageProps {
  params: Promise<{ token: string }>;
}

export async function generateMetadata({
  params
}: UnlistedPageProps): Promise<Metadata> {
  const { token } = await params;
  try {
    const view = await getReadService().unlistedView(token);
    return {
      title: view.version.title,
      robots: { index: false, follow: false, nocache: true }
    };
  } catch {
    return { robots: { index: false, follow: false, nocache: true } };
  }
}

export default async function UnlistedArticlePage({
  params
}: UnlistedPageProps) {
  const { token } = await params;
  let view;
  try {
    view = await getReadService().unlistedView(token);
  } catch {
    notFound();
  }
  const readerHtml = rewriteMediaReferences(
    view.version.readerHtml,
    view.version.media,
    `/u/${token}`
  );
  return (
    <>
      <SiteHeader reading />
      <ArticleExperience
        title={view.version.title}
        summary={view.version.summary}
        publishedAt={view.version.publishedAt.toISOString()}
        readerHtml={readerHtml}
        toc={view.version.toc}
        annotations={view.version.annotations}
        aiAppendix={view.version.aiAppendix}
        exportHref={`/u/${token}/export`}
        visibilityLabel="未列出文章"
      />
    </>
  );
}
