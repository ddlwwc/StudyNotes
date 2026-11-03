import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ArticleExperience } from "@/components/ArticleExperience";
import { SiteHeader } from "@/components/SiteHeader";
import { rewriteMediaReferences } from "@/lib/html";
import { getReadService } from "@/lib/services";

export const dynamic = "force-dynamic";

interface ArticlePageProps {
  params: Promise<{ articleId: string }>;
}

export async function generateMetadata({
  params
}: ArticlePageProps): Promise<Metadata> {
  const { articleId } = await params;
  try {
    const view = await getReadService().publicView(articleId);
    return {
      title: view.version.title,
      robots: { index: false, follow: false, nocache: true }
    };
  } catch {
    return { robots: { index: false, follow: false, nocache: true } };
  }
}

export default async function PublicArticlePage({ params }: ArticlePageProps) {
  const { articleId } = await params;
  let view;
  try {
    view = await getReadService().publicView(articleId);
  } catch {
    notFound();
  }
  const readerHtml = rewriteMediaReferences(
    view.version.readerHtml,
    view.version.media,
    `/a/${articleId}`
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
        exportHref={`/a/${articleId}/export`}
        visibilityLabel="公开文章"
      />
    </>
  );
}
