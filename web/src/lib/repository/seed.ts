import type {
  ArticleAnnotation,
  AtomicPublishInput,
  PublishRepository
} from "@/domain/types";
import { computePublishFingerprint } from "@/lib/fingerprint";
import { buildReaderContent } from "@/lib/html";
import { randomUuid } from "@/lib/ids";

interface DemoArticle {
  articleId: string;
  token: string;
  sourceMaterialId: string;
  title: string;
  summary: string;
  tags: string[];
  publishedAt: string;
  bodyHtml: string;
  annotations?: ArticleAnnotation[];
  aiAppendix?: Array<{ id: string; title: string; body: string }>;
  visibility: "PUBLIC" | "UNLISTED";
}

const DEMO_ARTICLES: DemoArticle[] = [
  {
    articleId: "demoCognitiveLoad01",
    token: "demo-cognitive-load-unlisted-token-01",
    sourceMaterialId: "material-cognitive-load",
    title: "认知负荷理论与学习设计",
    summary:
      "理解内在负荷、外在负荷与生成性负荷，以及它们如何影响学习材料的呈现。",
    tags: ["认知心理", "学习科学"],
    publishedAt: "2026-10-31T02:00:00.000Z",
    visibility: "PUBLIC",
    annotations: [
      {
        id: "annotation-03",
        quote: "有效设计应降低无关负荷，并为生成性加工留出空间。",
        note: "关键不只是减少内容，而是让注意力进入关系建构。可与多媒体学习原则一起核对。",
        createdAt: "2026-10-31T02:00:00.000Z"
      }
    ],
    aiAppendix: [
      {
        id: "ai-appendix-01",
        title: "AI 研读附录 · 结构提示",
        body:
          "这篇材料可以按“限制 → 三类负荷 → 设计策略”组织：先说明工作记忆限制，再区分来源，最后落到降低外在负荷与促进生成性加工的具体方法。"
      }
    ],
    bodyHtml: `
      <p class="article-lead">从工作记忆的限制出发，理解学习材料为什么需要被设计。</p>
      <h2>认知负荷是什么？</h2>
      <p>认知负荷理论关注工作记忆在学习过程中的限制。教学设计的目标并不是一味减少信息，而是把有限的认知资源引向与图式建构相关的活动。</p>
      <p>内在负荷来自材料本身的复杂性；外在负荷由不恰当的呈现方式产生；生成性负荷则来自学习者主动组织、解释和连接知识的加工过程。</p>
      <blockquote class="article-takeaway">有效设计应降低无关负荷，并为生成性加工留出空间。</blockquote>
      <h2>三种认知负荷</h2>
      <figure class="cognitive-load-diagram">
        <figcaption>认知负荷的三种来源</figcaption>
        <div class="cognitive-load-grid">
          <section><span>01</span><h3>内在负荷</h3><p>由学习材料本身的复杂性产生</p><small>复杂</small></section>
          <section><span>02</span><h3>外在负荷</h3><p>由不恰当的呈现与组织方式产生</p><small>呈现</small></section>
          <section><span>03</span><h3>生成性负荷</h3><p>投入图式建构与知识连接</p><small>建构</small></section>
        </div>
      </figure>
      <h2>降低外在负荷</h2>
      <p>图文整合、分段呈现和及时反馈需要共同服务于概念之间的关系，而不是停留在视觉层面的整齐。</p>
      <h2>促进生成性加工</h2>
      <p>留出解释、比较和连接的活动空间，让学习者把新材料组织进已有知识结构。</p>
      <h2>学习设计启示</h2>
      <p>先识别负荷来源，再选择呈现策略。减少无关加工与增加有效生成性加工需要同时发生。</p>
    `
  },
  {
    articleId: "demoSpacedRepetition1",
    token: "demo-spaced-repetition-token-01",
    sourceMaterialId: "material-spaced-repetition",
    title: "间隔重复：从记忆曲线到复习节奏",
    summary:
      "用更少但更有规律的复习，把短期记忆逐步转化为可持续调用的长期知识。",
    tags: ["学习方法"],
    publishedAt: "2026-10-30T02:00:00.000Z",
    visibility: "PUBLIC",
    bodyHtml: `
      <h2>记忆并不是一次写入</h2>
      <p>间隔重复把复习安排在遗忘即将发生之前，让每次提取都重新加固知识连接。</p>
      <h2>节奏比次数更重要</h2>
      <p>分散在数天中的少量复习，通常比同一天反复阅读更容易形成长期记忆。</p>
    `
  },
  {
    articleId: "demoMultimediaLearn1",
    token: "demo-multimedia-token-001",
    sourceMaterialId: "material-multimedia",
    title: "多媒体学习的双通道假设",
    summary:
      "文字与图像如何分别进入工作记忆，以及为什么图文整合比信息堆叠更有效。",
    tags: ["认知心理", "多媒体学习"],
    publishedAt: "2026-10-29T02:00:00.000Z",
    visibility: "PUBLIC",
    bodyHtml: `
      <h2>两条加工通道</h2>
      <p>视觉与语言信息通过不同通道进入工作记忆，图文整合能减少无谓的跨通道转换。</p>
      <h2>整合胜过堆叠</h2>
      <p>相关图文靠近呈现并建立明确关系，比分散堆叠更多信息更有效。</p>
    `
  },
  {
    articleId: "demoConceptMap00001",
    token: "demo-concept-map-token-0001",
    sourceMaterialId: "material-concept-map",
    title: "如何设计有效的概念图",
    summary:
      "从节点、关系与层级出发，让概念图成为构建知识结构的工具，而不只是视觉整理。",
    tags: ["知识管理"],
    publishedAt: "2026-10-28T02:00:00.000Z",
    visibility: "PUBLIC",
    bodyHtml: `
      <h2>先定义关系</h2>
      <p>概念图的核心不是节点数量，而是节点之间可解释、可检验的关系。</p>
      <h2>层级服务于理解</h2>
      <p>层级应反映概念抽象程度和依赖关系，而不是视觉上的对称。</p>
    `
  },
  {
    articleId: "demoSystemBoundary01",
    token: "demo-system-boundary-token01",
    sourceMaterialId: "material-system-boundary",
    title: "理解系统设计中的信息边界",
    summary:
      "通过明确数据所有权、写入路径与读取视图，降低复杂系统的耦合与认知成本。",
    tags: ["程序设计", "系统设计"],
    publishedAt: "2026-10-27T02:00:00.000Z",
    visibility: "PUBLIC",
    bodyHtml: `
      <h2>边界首先是所有权</h2>
      <p>明确哪一层拥有数据，可以减少隐式读取和重复写入。</p>
      <h2>读取视图不是写模型</h2>
      <p>为发现和阅读建立的投影应当由权威写入路径统一维护。</p>
    `
  },
  {
    articleId: "demoRetrievalPractice",
    token: "demo-retrieval-practice-token",
    sourceMaterialId: "material-retrieval-practice",
    title: "检索练习为什么比重复阅读更有效",
    summary:
      "主动回忆会迫使知识从记忆中被重新构建，从而形成更稳定、更容易迁移的连接。",
    tags: ["学习方法", "检索练习"],
    publishedAt: "2026-10-26T02:00:00.000Z",
    visibility: "PUBLIC",
    bodyHtml: `
      <h2>主动提取</h2>
      <p>主动回忆会暴露理解缺口，并要求大脑重新组织可用线索。</p>
      <h2>错题不是失败</h2>
      <p>带反馈的检索能修正错误连接，比单纯重读留下更清晰的记忆路径。</p>
    `
  },
  {
    articleId: "demoUnlistedArticle1",
    token: "demo-unlisted-share-token-000001",
    sourceMaterialId: "material-unlisted-demo",
    title: "一份只在链接中出现的阅读笔记",
    summary: "用于验证未列出文章不会进入公开列表、搜索和 sitemap。",
    tags: ["未列出验证"],
    publishedAt: "2026-10-25T02:00:00.000Z",
    visibility: "UNLISTED",
    bodyHtml: `
      <h2>未列出不是私密</h2>
      <p>持有不可猜链接的人仍然可以阅读，因此内容不应被视为机密。</p>
    `
  }
];

export function seedMemoryRepository(repository: PublishRepository): void {
  for (const [index, demo] of DEMO_ARTICLES.entries()) {
    const annotations = demo.annotations ?? [];
    const aiAppendix = demo.aiAppendix ?? [];
    const reader = buildReaderContent(demo.bodyHtml, annotations);
    const fingerprint = computePublishFingerprint({
      title: demo.title,
      summary: demo.summary,
      bodyHtml: reader.bodyHtml,
      tags: demo.tags,
      annotations,
      aiAppendix,
      mediaRefs: []
    });
    const input: AtomicPublishInput = {
      keyId: "seed",
      requestId: `seed-request-${index + 1}`,
      requestHash: fingerprint,
      sourceMaterialId: demo.sourceMaterialId,
      sourceVersionId: "seed-version",
      expectedVersion: 0,
      visibility: demo.visibility,
      title: demo.title,
      summary: demo.summary,
      fingerprint,
      bodyHtml: reader.bodyHtml,
      readerHtml: reader.readerHtml,
      toc: reader.toc,
      tags: demo.tags,
      annotations,
      aiAppendix,
      media: [],
      versionId: randomUuid(),
      newArticleRowId: randomUuid(),
      newArticlePublicId: demo.articleId,
      newUnlistedToken: demo.token,
      publishedAt: new Date(demo.publishedAt)
    };
    void repository.executePublish(input);
  }
}
