const PAGE_NAME = "Web Prototype";
const ROOT_NAME = "StudyNotes / Web Prototype / 3 States";
const SCREEN_WIDTH = 1440;
const SCREEN_HEIGHT = 1024;
const SCREEN_GAP = 80;
const SCREEN_TOP = 64;

const COLOR = {
  white: "#FFFFFF",
  canvas: "#F7F8FA",
  panel: "#FAFBFC",
  border: "#E5E6EB",
  borderStrong: "#D9DCE1",
  text: "#1D2129",
  secondary: "#4E5969",
  muted: "#86909C",
  faint: "#C9CDD4",
  blue: "#3370FF",
  blueHover: "#245BDB",
  blueSoft: "#EAF1FF",
  blueBorder: "#C7D8FF",
  blueInk: "#1747B5",
  yellowSoft: "#FFF8E8",
  yellowBorder: "#F5DBA6",
  yellowInk: "#7A4B00",
  green: "#23A26D",
  redSoft: "#FFF1F0",
  inkSoft: "#F2F3F5"
};

const ICONS = {
  book:
    '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>' +
    '<path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2Z"/>',
  search:
    '<circle cx="11" cy="11" r="7"/>' +
    '<path d="m20 20-4.2-4.2"/>',
  toc:
    '<path d="M8 6h13M8 12h13M8 18h13"/>' +
    '<path d="M3 6h.01M3 12h.01M3 18h.01"/>',
  study:
    '<path d="M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4Z"/>' +
    '<path d="M8 9h8M8 13h5"/>',
  link:
    '<path d="M10 13a5 5 0 0 0 7.5.5l2-2a5 5 0 0 0-7-7l-1.1 1.1"/>' +
    '<path d="M14 11a5 5 0 0 0-7.5-.5l-2 2a5 5 0 0 0 7 7l1.1-1.1"/>',
  download:
    '<path d="M12 3v12"/>' +
    '<path d="m7 10 5 5 5-5"/>' +
    '<path d="M5 21h14"/>',
  chevronRight: '<path d="m9 18 6-6-6-6"/>',
  arrowRight: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  close: '<path d="M18 6 6 18M6 6l12 12"/>',
  spark:
    '<path d="m12 3-1.2 3.2L7.5 7.5l3.3 1.3L12 12l1.2-3.2 3.3-1.3-3.3-1.3L12 3Z"/>' +
    '<path d="m5 14-.8 2.2L2 17l2.2.8L5 20l.8-2.2L8 17l-2.2-.8L5 14Z"/>' +
    '<path d="m19 14-.7 1.8-1.8.7 1.8.7L19 19l.7-1.8 1.8-.7-1.8-.7L19 14Z"/>',
  quote:
    '<path d="M3 21c3 0 7-1 7-8V5c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v5c0 1.1.9 2 2 2h3"/>' +
    '<path d="M15 21c3 0 7-1 7-8V5c0-1.1-.9-2-2-2h-4c-1.1 0-2 .9-2 2v5c0 1.1.9 2 2 2h3"/>'
};

const ARTICLE_CARDS = [
  {
    type: "学习科学",
    title: "认知负荷理论与学习设计",
    summary: "理解内在负荷、外在负荷与生成性负荷，以及它们如何影响学习材料的呈现。",
    tag: "认知心理",
    meta: "公开 · 18 分钟",
    date: "10 月 31 日"
  },
  {
    type: "阅读笔记",
    title: "间隔重复：从记忆曲线到复习节奏",
    summary: "用更少但更有规律的复习，把短期记忆逐步转化为可持续调用的长期知识。",
    tag: "学习方法",
    meta: "公开 · 12 分钟",
    date: "10 月 30 日"
  },
  {
    type: "网页文章",
    title: "多媒体学习的双通道假设",
    summary: "文字与图像如何分别进入工作记忆，以及为什么图文整合比信息堆叠更有效。",
    tag: "认知心理",
    meta: "公开 · 9 分钟",
    date: "10 月 29 日"
  },
  {
    type: "学习笔记",
    title: "如何设计有效的概念图",
    summary: "从节点、关系与层级出发，让概念图成为构建知识结构的工具，而不只是视觉整理。",
    tag: "知识管理",
    meta: "公开 · 15 分钟",
    date: "10 月 28 日"
  },
  {
    type: "技术文章",
    title: "理解系统设计中的信息边界",
    summary: "通过明确数据所有权、写入路径与读取视图，降低复杂系统的耦合与认知成本。",
    tag: "程序设计",
    meta: "公开 · 16 分钟",
    date: "10 月 27 日"
  },
  {
    type: "阅读笔记",
    title: "检索练习为什么比重复阅读更有效",
    summary: "主动回忆会迫使知识从记忆中被重新构建，从而形成更稳定、更容易迁移的连接。",
    tag: "学习方法",
    meta: "公开 · 8 分钟",
    date: "10 月 26 日"
  }
];

let FONTS = null;

main().catch(function (error) {
  console.error(error);
  figma.notify("生成 Web 原型失败：" + error.message, {
    error: true,
    timeout: 9000
  });
  figma.closePlugin();
});

async function main() {
  FONTS = await resolveFonts();

  let page = figma.root.children.find(function (node) {
    return node.type === "PAGE" && node.name === PAGE_NAME;
  });

  if (!page) {
    page = figma.createPage();
    page.name = PAGE_NAME;
  }

  if (figma.currentPage !== page) {
    await figma.setCurrentPageAsync(page);
  }

  const previousRoot = page.children.find(function (node) {
    return node.name === ROOT_NAME;
  });
  if (previousRoot) {
    previousRoot.remove();
  }

  const root = figma.createFrame();
  page.appendChild(root);
  root.name = ROOT_NAME;
  root.x = 0;
  root.y = 0;
  root.resize(SCREEN_WIDTH * 3 + SCREEN_GAP * 2, SCREEN_HEIGHT + SCREEN_TOP);
  root.fills = [];
  root.clipsContent = false;

  const screens = [
    buildPublicLibrary(root, 0),
    buildArticleReading(root, SCREEN_WIDTH + SCREEN_GAP),
    buildStudyLayerReading(root, (SCREEN_WIDTH + SCREEN_GAP) * 2)
  ];

  addScreenLabel(root, "01 / 公开文章列表与全站搜索", 0);
  addScreenLabel(root, "02 / 只读文章阅读", SCREEN_WIDTH + SCREEN_GAP);
  addScreenLabel(root, "03 / 研读层展开与导出入口", (SCREEN_WIDTH + SCREEN_GAP) * 2);

  figma.currentPage.selection = screens;
  figma.viewport.scrollAndZoomIntoView([root]);
  figma.notify("Web Prototype 已生成：3 个可编辑状态", { timeout: 5000 });
  figma.closePlugin();
}

async function resolveFonts() {
  const available = await figma.listAvailableFontsAsync();

  function pick(candidates) {
    for (let index = 0; index < candidates.length; index += 1) {
      const candidate = candidates[index];
      const match = available.find(function (item) {
        return (
          item.fontName.family === candidate.family &&
          item.fontName.style === candidate.style
        );
      });
      if (match) {
        return match.fontName;
      }
    }
    return available[0].fontName;
  }

  const fonts = {
    uiRegular: pick([
      { family: "PingFang SC", style: "Regular" },
      { family: "Noto Sans CJK SC", style: "Regular" },
      { family: "Inter", style: "Regular" }
    ]),
    uiMedium: pick([
      { family: "PingFang SC", style: "Medium" },
      { family: "PingFang SC", style: "Regular" },
      { family: "Inter", style: "Medium" },
      { family: "Inter", style: "Regular" }
    ]),
    uiSemibold: pick([
      { family: "PingFang SC", style: "Semibold" },
      { family: "PingFang SC", style: "Medium" },
      { family: "Inter", style: "Semi Bold" },
      { family: "Inter", style: "Bold" }
    ]),
    body: pick([
      { family: "Songti SC", style: "Regular" },
      { family: "Noto Serif CJK SC", style: "Regular" },
      { family: "Source Han Serif SC", style: "Regular" },
      { family: "Inter", style: "Regular" }
    ])
  };

  const unique = [];
  Object.keys(fonts).forEach(function (key) {
    const font = fonts[key];
    const exists = unique.some(function (item) {
      return item.family === font.family && item.style === font.style;
    });
    if (!exists) {
      unique.push(font);
    }
  });

  for (const font of unique) {
    await figma.loadFontAsync(font);
  }

  return fonts;
}

function buildPublicLibrary(root, offsetX) {
  const screen = createFrame(root, "01 / Public Library", offsetX, SCREEN_TOP, SCREEN_WIDTH, SCREEN_HEIGHT, {
    fill: COLOR.white,
    clips: true
  });

  const header = createHeader(screen, false);
  header.name = "Public Header";

  const hero = createFrame(screen, "Search Hero", 0, 64, SCREEN_WIDTH, 248, {
    fill: COLOR.canvas
  });
  addRect(hero, "Hero Bottom Border", 0, 247, SCREEN_WIDTH, 1, COLOR.border);

  addText(hero, {
    name: "Hero Eyebrow",
    text: "PUBLIC READING",
    x: 40,
    y: 34,
    width: 240,
    height: 18,
    font: FONTS.uiMedium,
    size: 12,
    color: COLOR.blue,
    lineHeight: 18
  });
  addText(hero, {
    name: "Hero Title",
    text: "公开学习资料",
    x: 40,
    y: 58,
    width: 600,
    height: 46,
    font: FONTS.uiSemibold,
    size: 34,
    color: COLOR.text,
    lineHeight: 44
  });
  addText(hero, {
    name: "Hero Description",
    text: "浏览已发布的学习文章，支持全站搜索、目录、公开研读层与独立导出。",
    x: 40,
    y: 108,
    width: 780,
    height: 26,
    font: FONTS.uiRegular,
    size: 15,
    color: COLOR.secondary,
    lineHeight: 24
  });

  const search = createFrame(hero, "Global Search Field", 40, 154, 925, 52, {
    fill: COLOR.white,
    stroke: COLOR.borderStrong,
    radius: 7
  });
  addIcon(search, "Icon / Search", "search", 17, 16, 20, COLOR.secondary);
  addText(search, {
    name: "Search Placeholder",
    text: "搜索标题、正文、标签或公开研读内容",
    x: 48,
    y: 16,
    width: 720,
    height: 20,
    font: FONTS.uiRegular,
    size: 14,
    color: COLOR.muted,
    lineHeight: 20
  });
  addText(search, {
    name: "Search Shortcut",
    text: "⌘ K",
    x: 850,
    y: 16,
    width: 50,
    height: 20,
    font: FONTS.uiMedium,
    size: 12,
    color: COLOR.muted,
    lineHeight: 20,
    align: "RIGHT"
  });

  addButton(hero, {
    name: "Search Button",
    text: "搜索",
    x: 981,
    y: 154,
    width: 88,
    height: 52,
    fill: COLOR.blue,
    color: COLOR.white,
    font: FONTS.uiMedium
  });

  const quickLabel = addText(hero, {
    name: "Popular Tags Label",
    text: "热门标签",
    x: 40,
    y: 220,
    width: 64,
    height: 18,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.muted,
    lineHeight: 18
  });

  const quickTags = ["认知心理", "学习方法", "程序设计", "知识管理"];
  let quickX = 112;
  quickTags.forEach(function (tag) {
    const width = Math.max(68, tag.length * 13 + 28);
    addTextChip(hero, "Quick Tag / " + tag, tag, quickX, 214, width, false);
    quickX += width + 10;
  });

  const content = createFrame(screen, "Public Article List", 0, 312, SCREEN_WIDTH, 712, {
    fill: COLOR.white
  });
  addText(content, {
    name: "Section Title",
    text: "全部公开文章",
    x: 40,
    y: 34,
    width: 240,
    height: 30,
    font: FONTS.uiSemibold,
    size: 22,
    color: COLOR.text,
    lineHeight: 30
  });
  addText(content, {
    name: "Result Count",
    text: "共 18 篇",
    x: 1200,
    y: 41,
    width: 200,
    height: 20,
    font: FONTS.uiRegular,
    size: 13,
    color: COLOR.muted,
    lineHeight: 20,
    align: "RIGHT"
  });

  const filters = ["全部", "认知科学", "学习方法", "编程技术", "阅读笔记"];
  let filterX = 40;
  filters.forEach(function (filter, index) {
    const width = Math.max(62, filter.length * 13 + 28);
    addTextChip(content, "Filter / " + filter, filter, filterX, 82, width, index === 0);
    filterX += width + 10;
  });

  ARTICLE_CARDS.forEach(function (data, index) {
    const column = index % 3;
    const row = Math.floor(index / 3);
    const x = 40 + column * 460;
    const y = 132 + row * 222;
    addArticleCard(content, data, x, y);
  });

  addRect(content, "Footer Divider", 40, 610, 1360, 1, COLOR.border);
  addText(content, {
    name: "Footer Brand",
    text: "StudyNotes · 公开学习资料",
    x: 40,
    y: 632,
    width: 300,
    height: 20,
    font: FONTS.uiMedium,
    size: 12,
    color: COLOR.secondary,
    lineHeight: 20
  });
  addText(content, {
    name: "Footer Note",
    text: "本站仅展示发布者主动公开的只读内容",
    x: 1040,
    y: 632,
    width: 360,
    height: 20,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.muted,
    lineHeight: 20,
    align: "RIGHT"
  });

  return screen;
}

function buildArticleReading(root, offsetX) {
  const screen = createFrame(root, "02 / Article Reading", offsetX, SCREEN_TOP, SCREEN_WIDTH, SCREEN_HEIGHT, {
    fill: COLOR.white,
    clips: true
  });

  createHeader(screen, true);
  createReadingToolbar(screen, false);
  createTableOfContents(screen, 40, 144, 200, "standard");
  createArticleContent(screen, {
    x: 300,
    y: 146,
    width: 820,
    compact: false,
    withDiagram: true
  });

  addRect(screen, "Reading Progress Track", 0, 63, SCREEN_WIDTH, 2, COLOR.border);
  addRect(screen, "Reading Progress", 0, 63, 520, 2, COLOR.blue);
  return screen;
}

function buildStudyLayerReading(root, offsetX) {
  const screen = createFrame(root, "03 / Article with Study Layer", offsetX, SCREEN_TOP, SCREEN_WIDTH, SCREEN_HEIGHT, {
    fill: COLOR.white,
    clips: true
  });

  createHeader(screen, true);
  createReadingToolbar(screen, true);
  createTableOfContents(screen, 0, 120, 196, "compact");
  createArticleContent(screen, {
    x: 228,
    y: 142,
    width: 748,
    compact: true,
    withDiagram: false
  });
  createStudyLayer(screen, 1004, 120, 436);

  addRect(screen, "Reading Progress Track", 0, 63, SCREEN_WIDTH, 2, COLOR.border);
  addRect(screen, "Reading Progress", 0, 63, 720, 2, COLOR.blue);
  return screen;
}

function createHeader(parent, readingMode) {
  const header = createFrame(parent, "Site Header", 0, 0, SCREEN_WIDTH, 64, {
    fill: COLOR.white
  });
  addRect(header, "Header Border", 0, 63, SCREEN_WIDTH, 1, COLOR.border);

  const brandMark = createFrame(header, "Brand Mark", 32, 18, 28, 28, {
    fill: COLOR.blue,
    radius: 7
  });
  addRect(brandMark, "Page Back", 7, 6, 12, 16, COLOR.white, 2);
  addRect(brandMark, "Page Front", 11, 9, 10, 14, COLOR.blueHover, 2);
  addRect(brandMark, "Page Fold", 11, 9, 10, 5, COLOR.white, 2);

  addText(header, {
    name: "Brand Name",
    text: "StudyNotes",
    x: 70,
    y: 20,
    width: 130,
    height: 24,
    font: FONTS.uiSemibold,
    size: 17,
    color: COLOR.text,
    lineHeight: 24
  });
  addRect(header, "Brand Divider", 198, 20, 1, 24, COLOR.border);
  addText(header, {
    name: "Site Context",
    text: readingMode ? "公开文章阅读" : "公开阅览室",
    x: 218,
    y: 21,
    width: 160,
    height: 22,
    font: FONTS.uiRegular,
    size: 13,
    color: COLOR.secondary,
    lineHeight: 22
  });

  const readOnlyBadge = createFrame(header, "Read Only Badge", 1194, 18, 208, 28, {
    fill: COLOR.canvas,
    stroke: COLOR.border,
    radius: 6
  });
  addIcon(readOnlyBadge, "Icon / Book", "book", 10, 6, 16, COLOR.secondary);
  addText(readOnlyBadge, {
    name: "Read Only Label",
    text: "公开内容 · 只读浏览",
    x: 34,
    y: 5,
    width: 160,
    height: 18,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.secondary,
    lineHeight: 18
  });

  return header;
}

function createReadingToolbar(parent, studyExpanded) {
  const toolbar = createFrame(parent, "Reading Toolbar", 0, 64, SCREEN_WIDTH, 56, {
    fill: COLOR.white
  });
  addRect(toolbar, "Toolbar Border", 0, 55, SCREEN_WIDTH, 1, COLOR.border);

  addText(toolbar, {
    name: "Toolbar Breadcrumb",
    text: "公开阅览室  /  认知负荷理论与学习设计",
    x: 40,
    y: 17,
    width: 620,
    height: 22,
    font: FONTS.uiRegular,
    size: 13,
    color: COLOR.muted,
    lineHeight: 22
  });

  addToolbarAction(toolbar, "目录", "toc", 1000, false);
  addToolbarAction(toolbar, "研读层", "study", 1082, studyExpanded);
  addToolbarAction(toolbar, "复制链接", "link", 1180, false);
  addToolbarAction(toolbar, "导出", "download", 1292, false);

  return toolbar;
}

function addToolbarAction(parent, label, iconName, x, active) {
  const width = label === "研读层" ? 92 : label === "复制链接" ? 100 : 82;
  const button = createFrame(parent, "Toolbar Action / " + label, x, 12, width, 32, {
    fill: active ? COLOR.blueSoft : COLOR.white,
    stroke: active ? COLOR.blueBorder : null,
    radius: 6
  });
  addIcon(button, "Icon / " + label, iconName, 9, 8, 16, active ? COLOR.blue : COLOR.secondary);
  addText(button, {
    name: "Action Label",
    text: label,
    x: 31,
    y: 6,
    width: width - 38,
    height: 20,
    font: FONTS.uiRegular,
    size: 13,
    color: active ? COLOR.blue : COLOR.secondary,
    lineHeight: 20
  });
}

function createTableOfContents(parent, x, y, width, mode) {
  const panel = createFrame(parent, "Table of Contents", x, y, width, 880, {
    fill: COLOR.panel
  });
  addRect(panel, "TOC Right Border", width - 1, 0, 1, 880, COLOR.border);

  addText(panel, {
    name: "TOC Heading",
    text: "文章目录",
    x: mode === "compact" ? 20 : 24,
    y: 24,
    width: width - 40,
    height: 22,
    font: FONTS.uiSemibold,
    size: 14,
    color: COLOR.text,
    lineHeight: 22
  });

  const items = [
    "认知负荷是什么",
    "三种认知负荷",
    "降低外在负荷",
    "促进生成性加工",
    "学习设计启示"
  ];
  const startX = mode === "compact" ? 12 : 18;

  items.forEach(function (item, index) {
    if (index === 0) {
      const active = createFrame(panel, "TOC Item / Active", startX, 64, width - startX - 12, 38, {
        fill: COLOR.blueSoft,
        radius: 6
      });
      addRect(active, "Active Indicator", 0, 9, 2, 20, COLOR.blue, 1);
      addText(active, {
        name: "TOC Label",
        text: item,
        x: 12,
        y: 8,
        width: width - 50,
        height: 22,
        font: FONTS.uiMedium,
        size: 13,
        color: COLOR.blue,
        lineHeight: 22
      });
      return;
    }

    addText(panel, {
      name: "TOC Item / " + item,
      text: item,
      x: startX + 12,
      y: 64 + index * 40 + 8,
      width: width - startX - 38,
      height: 22,
      font: FONTS.uiRegular,
      size: 13,
      color: COLOR.secondary,
      lineHeight: 22
    });
  });

  addRect(panel, "TOC Divider", startX, 286, width - startX * 2, 1, COLOR.border);
  addText(panel, {
    name: "Reading Progress Label",
    text: "阅读进度",
    x: startX + 12,
    y: 308,
    width: width - 48,
    height: 20,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.muted,
    lineHeight: 20
  });
  const track = createFrame(panel, "Progress Track", startX + 12, 336, width - startX * 2 - 24, 4, {
    fill: COLOR.border,
    radius: 2
  });
  addRect(track, "Progress Fill", 0, 0, (width - startX * 2 - 24) * 0.42, 4, COLOR.blue, 2);

  return panel;
}

function createArticleContent(parent, options) {
  const article = createFrame(parent, "Article Body", options.x, options.y, options.width, 870, {
    fill: COLOR.white
  });
  const compact = options.compact;
  const titleSize = compact ? 33 : 38;
  const titleHeight = compact ? 46 : 54;

  addText(article, {
    name: "Article Type",
    text: "学习科学 · 认知心理",
    x: 0,
    y: 0,
    width: options.width,
    height: 20,
    font: FONTS.uiMedium,
    size: 12,
    color: COLOR.blue,
    lineHeight: 20
  });
  addText(article, {
    name: "Article Title",
    text: "认知负荷理论与学习设计",
    x: 0,
    y: compact ? 26 : 30,
    width: options.width,
    height: titleHeight,
    font: FONTS.uiSemibold,
    size: titleSize,
    color: COLOR.text,
    lineHeight: compact ? 44 : 50
  });
  addText(article, {
    name: "Article Subtitle",
    text: "从工作记忆的限制出发，理解学习材料为什么需要被设计。",
    x: 0,
    y: compact ? 82 : 96,
    width: options.width,
    height: 26,
    font: FONTS.uiRegular,
    size: compact ? 15 : 16,
    color: COLOR.secondary,
    lineHeight: 25
  });
  addText(article, {
    name: "Article Meta",
    text: "公开文章 · 约 18 分钟 · 更新于 10 月 31 日",
    x: 0,
    y: compact ? 120 : 136,
    width: options.width,
    height: 20,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.muted,
    lineHeight: 20
  });
  addRect(article, "Header Divider", 0, compact ? 158 : 178, options.width, 1, COLOR.border);

  const sectionTop = compact ? 184 : 206;
  addText(article, {
    name: "Section Heading / 认知负荷是什么",
    text: "认知负荷是什么？",
    x: 0,
    y: sectionTop,
    width: options.width,
    height: 34,
    font: FONTS.uiSemibold,
    size: compact ? 21 : 22,
    color: COLOR.text,
    lineHeight: 32
  });

  addText(article, {
    name: "Body Paragraph / 01",
    text:
      "认知负荷理论关注工作记忆在学习过程中的限制。教学设计的目标并不是一味减少信息，而是把有限的认知资源引向与图式建构相关的活动。",
    x: 0,
    y: sectionTop + 46,
    width: options.width,
    height: compact ? 82 : 88,
    font: FONTS.body,
    size: compact ? 16 : 17,
    color: COLOR.text,
    lineHeight: compact ? 31 : 34
  });
  addText(article, {
    name: "Body Paragraph / 02",
    text:
      "内在负荷来自材料本身的复杂性；外在负荷由不恰当的呈现方式产生；生成性负荷则来自学习者主动组织、解释和连接知识的加工过程。",
    x: 0,
    y: sectionTop + (compact ? 138 : 146),
    width: options.width,
    height: compact ? 112 : 88,
    font: FONTS.body,
    size: compact ? 16 : 17,
    color: COLOR.text,
    lineHeight: compact ? 31 : 34
  });

  const quoteY = sectionTop + (compact ? 268 : 254);
  const quote = createFrame(article, "Highlighted Takeaway", 0, quoteY, options.width, compact ? 104 : 112, {
    fill: COLOR.blueSoft,
    radius: 6
  });
  addRect(quote, "Quote Accent", 0, 0, 3, compact ? 104 : 112, COLOR.blue, 2);
  addIcon(quote, "Icon / Quote", "quote", 18, 19, 18, COLOR.blue);
  addText(quote, {
    name: "Takeaway Text",
    text: "有效设计应降低无关负荷，并为生成性加工留出空间。",
    x: 50,
    y: 17,
    width: options.width - 82,
    height: compact ? 54 : 58,
    font: FONTS.uiMedium,
    size: compact ? 15 : 16,
    color: COLOR.blueInk,
    lineHeight: compact ? 26 : 28
  });
  addText(quote, {
    name: "Takeaway Caption",
    text: "公开标注 03 · 本段已纳入研读层",
    x: 50,
    y: compact ? 74 : 80,
    width: options.width - 82,
    height: 18,
    font: FONTS.uiRegular,
    size: 11,
    color: COLOR.secondary,
    lineHeight: 18
  });

  if (!compact && options.withDiagram) {
    addText(article, {
      name: "Section Heading / 三种认知负荷",
      text: "三种认知负荷",
      x: 0,
      y: 596,
      width: options.width,
      height: 32,
      font: FONTS.uiSemibold,
      size: 22,
      color: COLOR.text,
      lineHeight: 32
    });
    addCognitiveLoadDiagram(article, 0, 650, options.width);
  } else if (compact) {
    addText(article, {
      name: "Section Heading / 降低外在负荷",
      text: "降低外在负荷",
      x: 0,
      y: 600,
      width: options.width,
      height: 30,
      font: FONTS.uiSemibold,
      size: 21,
      color: COLOR.text,
      lineHeight: 30
    });
    addText(article, {
      name: "Body Paragraph / 03",
      text:
        "图文整合、分段呈现和及时反馈需要共同服务于概念之间的关系，而不是停留在视觉层面的整齐。",
      x: 0,
      y: 642,
      width: options.width,
      height: 70,
      font: FONTS.body,
      size: 16,
      color: COLOR.text,
      lineHeight: 31
    });
  }

  return article;
}

function addCognitiveLoadDiagram(parent, x, y, width) {
  const diagram = createFrame(parent, "Diagram / 认知负荷的三种来源", x, y, width, 218, {
    fill: COLOR.canvas,
    stroke: COLOR.border,
    radius: 7
  });
  addText(diagram, {
    name: "Diagram Title",
    text: "认知负荷的三种来源",
    x: 20,
    y: 16,
    width: width - 40,
    height: 22,
    font: FONTS.uiMedium,
    size: 13,
    color: COLOR.secondary,
    lineHeight: 22
  });

  const cardWidth = (width - 112) / 3;
  const labels = [
    ["内在负荷", "由学习材料本身的复杂性产生", "复杂"],
    ["外在负荷", "由不恰当的呈现与组织方式产生", "呈现"],
    ["生成性负荷", "投入图式建构与知识连接", "建构"]
  ];

  labels.forEach(function (item, index) {
    const cardX = 20 + index * (cardWidth + 26);
    const card = createFrame(diagram, "Diagram Card / " + item[0], cardX, 50, cardWidth, 146, {
      fill: COLOR.white,
      stroke: COLOR.border,
      radius: 6
    });
    const marker = createFrame(card, "Category Marker", 16, 18, 28, 28, {
      fill: COLOR.blueSoft,
      radius: 6
    });
    addText(marker, {
      name: "Marker Text",
      text: String(index + 1).padStart(2, "0"),
      x: 4,
      y: 4,
      width: 20,
      height: 18,
      font: FONTS.uiMedium,
      size: 10,
      color: COLOR.blue,
      lineHeight: 18,
      align: "CENTER"
    });
    addText(card, {
      name: "Card Title",
      text: item[0],
      x: 52,
      y: 20,
      width: cardWidth - 68,
      height: 24,
      font: FONTS.uiSemibold,
      size: 15,
      color: COLOR.text,
      lineHeight: 24
    });
    addText(card, {
      name: "Card Description",
      text: item[1],
      x: 16,
      y: 66,
      width: cardWidth - 32,
      height: 54,
      font: FONTS.body,
      size: 14,
      color: COLOR.secondary,
      lineHeight: 25
    });
    addText(card, {
      name: "Card Keyword",
      text: item[2],
      x: 16,
      y: 123,
      width: cardWidth - 32,
      height: 16,
      font: FONTS.uiRegular,
      size: 10,
      color: COLOR.muted,
      lineHeight: 16
    });

    if (index < labels.length - 1) {
      addIcon(
        diagram,
        "Diagram Arrow / " + index,
        "arrowRight",
        cardX + cardWidth + 5,
        112,
        16,
        COLOR.muted
      );
    }
  });
}

function createStudyLayer(parent, x, y, width) {
  const panel = createFrame(parent, "Study Layer", x, y, width, 904, {
    fill: COLOR.panel
  });
  addRect(panel, "Study Layer Border", 0, 0, 1, 904, COLOR.border);

  addText(panel, {
    name: "Study Layer Title",
    text: "研读层",
    x: 24,
    y: 24,
    width: 180,
    height: 30,
    font: FONTS.uiSemibold,
    size: 20,
    color: COLOR.text,
    lineHeight: 30
  });
  addText(panel, {
    name: "Study Layer Disclosure",
    text: "由发布者主动公开",
    x: 232,
    y: 29,
    width: width - 256,
    height: 20,
    font: FONTS.uiRegular,
    size: 11,
    color: COLOR.muted,
    lineHeight: 20,
    align: "RIGHT"
  });

  const tabs = createFrame(panel, "Study Layer Tabs", 24, 70, width - 48, 40, {
    fill: COLOR.inkSoft,
    radius: 6
  });
  const activeTab = createFrame(tabs, "Tab / 公开标注", 4, 4, (width - 64) / 2, 32, {
    fill: COLOR.white,
    radius: 5
  });
  addText(activeTab, {
    name: "Public Annotations Tab Label",
    text: "公开标注  4",
    x: 0,
    y: 6,
    width: (width - 64) / 2,
    height: 20,
    font: FONTS.uiMedium,
    size: 12,
    color: COLOR.text,
    lineHeight: 20,
    align: "CENTER"
  });
  addText(tabs, {
    name: "AI Appendix Tab Label",
    text: "AI 附录  1",
    x: (width - 64) / 2 + 4,
    y: 10,
    width: (width - 64) / 2,
    height: 20,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.secondary,
    lineHeight: 20,
    align: "CENTER"
  });

  const annotation1 = createFrame(panel, "Public Annotation / 03", 24, 132, width - 48, 202, {
    fill: COLOR.yellowSoft,
    stroke: COLOR.yellowBorder,
    radius: 7
  });
  addText(annotation1, {
    name: "Annotation Number",
    text: "03",
    x: 18,
    y: 16,
    width: 40,
    height: 18,
    font: FONTS.uiSemibold,
    size: 12,
    color: COLOR.yellowInk,
    lineHeight: 18
  });
  addText(annotation1, {
    name: "Annotation Date",
    text: "10 月 31 日",
    x: width - 160,
    y: 16,
    width: 94,
    height: 18,
    font: FONTS.uiRegular,
    size: 11,
    color: COLOR.muted,
    lineHeight: 18,
    align: "RIGHT"
  });
  addText(annotation1, {
    name: "Annotated Excerpt",
    text: "“有效设计应降低无关负荷，并为生成性加工留出空间。”",
    x: 18,
    y: 48,
    width: width - 84,
    height: 58,
    font: FONTS.body,
    size: 15,
    color: COLOR.yellowInk,
    lineHeight: 27
  });
  addText(annotation1, {
    name: "Annotation Note",
    text: "关键不只是减少内容，而是让注意力进入关系建构。可与多媒体学习原则一起核对。",
    x: 18,
    y: 116,
    width: width - 84,
    height: 66,
    font: FONTS.uiRegular,
    size: 13,
    color: COLOR.secondary,
    lineHeight: 23
  });

  const annotation2 = createFrame(panel, "Public Annotation / 02", 24, 350, width - 48, 148, {
    fill: COLOR.white,
    stroke: COLOR.border,
    radius: 7
  });
  addText(annotation2, {
    name: "Annotation Number",
    text: "02",
    x: 18,
    y: 16,
    width: 40,
    height: 18,
    font: FONTS.uiSemibold,
    size: 12,
    color: COLOR.blue,
    lineHeight: 18
  });
  addText(annotation2, {
    name: "Annotated Excerpt",
    text: "“图文整合、分段呈现与及时反馈需要共同服务于概念关系。”",
    x: 18,
    y: 48,
    width: width - 84,
    height: 54,
    font: FONTS.body,
    size: 15,
    color: COLOR.text,
    lineHeight: 26
  });
  addText(annotation2, {
    name: "Annotation Note",
    text: "呈现方式应当帮助建立结构，而不只是提高页面整齐度。",
    x: 18,
    y: 108,
    width: width - 84,
    height: 24,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.secondary,
    lineHeight: 22
  });

  const appendix = createFrame(panel, "AI Study Appendix", 24, 520, width - 48, 226, {
    fill: COLOR.blueSoft,
    stroke: COLOR.blueBorder,
    radius: 7
  });
  addIcon(appendix, "Icon / AI Appendix", "spark", 18, 17, 18, COLOR.blue);
  addText(appendix, {
    name: "AI Appendix Heading",
    text: "AI 研读附录 · 结构提示",
    x: 46,
    y: 16,
    width: width - 104,
    height: 24,
    font: FONTS.uiSemibold,
    size: 14,
    color: COLOR.blueInk,
    lineHeight: 24
  });
  addText(appendix, {
    name: "AI Appendix Body",
    text:
      "这篇材料可以按“限制 → 三类负荷 → 设计策略”组织：先说明工作记忆限制，再区分来源，最后落到降低外在负荷与促进生成性加工的具体方法。",
    x: 18,
    y: 58,
    width: width - 84,
    height: 112,
    font: FONTS.uiRegular,
    size: 13,
    color: COLOR.secondary,
    lineHeight: 24
  });
  addText(appendix, {
    name: "AI Appendix Caption",
    text: "公开附录仅包含创作者主动发布的 AI 研读结果",
    x: 18,
    y: 184,
    width: width - 84,
    height: 20,
    font: FONTS.uiRegular,
    size: 10,
    color: COLOR.muted,
    lineHeight: 20
  });

  addRect(panel, "Study Layer Footer Divider", 24, 780, width - 48, 1, COLOR.border);
  addText(panel, {
    name: "Export Availability Label",
    text: "导出与分享",
    x: 24,
    y: 802,
    width: 100,
    height: 22,
    font: FONTS.uiMedium,
    size: 13,
    color: COLOR.text,
    lineHeight: 22
  });
  const exportButton = createFrame(panel, "Export Current Article Button", 24, 838, width - 48, 42, {
    fill: COLOR.white,
    stroke: COLOR.borderStrong,
    radius: 6
  });
  addIcon(exportButton, "Icon / Export", "download", 16, 12, 18, COLOR.secondary);
  addText(exportButton, {
    name: "Export Button Label",
    text: "导出当前文章的独立 HTML 包",
    x: 46,
    y: 10,
    width: width - 104,
    height: 22,
    font: FONTS.uiRegular,
    size: 12,
    color: COLOR.secondary,
    lineHeight: 22
  });

  return panel;
}

function addArticleCard(parent, data, x, y) {
  const card = createFrame(parent, "Article Card / " + data.title, x, y, 440, 202, {
    fill: COLOR.white,
    stroke: COLOR.border,
    radius: 7
  });

  addText(card, {
    name: "Article Type",
    text: data.type,
    x: 20,
    y: 18,
    width: 120,
    height: 18,
    font: FONTS.uiMedium,
    size: 11,
    color: COLOR.blue,
    lineHeight: 18
  });
  addText(card, {
    name: "Article Date",
    text: data.date,
    x: 320,
    y: 18,
    width: 100,
    height: 18,
    font: FONTS.uiRegular,
    size: 11,
    color: COLOR.muted,
    lineHeight: 18,
    align: "RIGHT"
  });
  addText(card, {
    name: "Article Title",
    text: data.title,
    x: 20,
    y: 46,
    width: 400,
    height: 28,
    font: FONTS.uiSemibold,
    size: 18,
    color: COLOR.text,
    lineHeight: 28
  });
  addText(card, {
    name: "Article Summary",
    text: data.summary,
    x: 20,
    y: 82,
    width: 400,
    height: 54,
    font: FONTS.body,
    size: 13,
    color: COLOR.secondary,
    lineHeight: 23
  });
  addTextChip(card, "Tag / " + data.tag, data.tag, 20, 154, data.tag.length * 13 + 24, false);
  addText(card, {
    name: "Read Meta",
    text: data.meta,
    x: 270,
    y: 160,
    width: 150,
    height: 18,
    font: FONTS.uiRegular,
    size: 11,
    color: COLOR.muted,
    lineHeight: 18,
    align: "RIGHT"
  });

  return card;
}

function addButton(parent, options) {
  const button = createFrame(parent, options.name, options.x, options.y, options.width, options.height, {
    fill: options.fill || COLOR.white,
    stroke: options.stroke || null,
    radius: 7
  });
  if (options.icon) {
    addIcon(
      button,
      "Icon / " + options.text,
      options.icon,
      16,
      (options.height - 18) / 2,
      18,
      options.color || COLOR.text
    );
  }
  addText(button, {
    name: "Button Label",
    text: options.text,
    x: options.icon ? 42 : 0,
    y: (options.height - 22) / 2,
    width: options.width - (options.icon ? 58 : 0),
    height: 22,
    font: options.font || FONTS.uiMedium,
    size: options.size || 13,
    color: options.color || COLOR.text,
    lineHeight: 22,
    align: options.icon && !options.align ? "LEFT" : options.align || "CENTER"
  });
  return button;
}

function addTextChip(parent, name, text, x, y, width, active) {
  const chip = createFrame(parent, name, x, y, width, 30, {
    fill: active ? COLOR.blueSoft : COLOR.white,
    stroke: active ? COLOR.blueBorder : COLOR.border,
    radius: 6
  });
  addText(chip, {
    name: "Chip Label",
    text: text,
    x: 0,
    y: 5,
    width: width,
    height: 20,
    font: FONTS.uiRegular,
    size: 12,
    color: active ? COLOR.blue : COLOR.secondary,
    lineHeight: 20,
    align: "CENTER"
  });
  return chip;
}

function addScreenLabel(parent, text, x) {
  addText(parent, {
    name: "State Label / " + text,
    text: text,
    x: x,
    y: 22,
    width: SCREEN_WIDTH,
    height: 22,
    font: FONTS.uiMedium,
    size: 13,
    color: COLOR.secondary,
    lineHeight: 22
  });
}

function createFrame(parent, name, x, y, width, height, options) {
  const config = options || {};
  const frame = figma.createFrame();
  parent.appendChild(frame);
  frame.name = name;
  frame.x = x;
  frame.y = y;
  frame.resize(width, height);
  frame.fills = config.fill ? [solid(config.fill)] : [];
  frame.strokes = config.stroke ? [solid(config.stroke)] : [];
  frame.strokeWeight = config.stroke ? 1 : 0;
  frame.strokeAlign = "INSIDE";
  frame.cornerRadius = config.radius || 0;
  frame.clipsContent = Boolean(config.clips);
  return frame;
}

function addRect(parent, name, x, y, width, height, fill, radius) {
  const rect = figma.createRectangle();
  parent.appendChild(rect);
  rect.name = name;
  rect.x = x;
  rect.y = y;
  rect.resize(width, height);
  rect.fills = [solid(fill)];
  rect.cornerRadius = radius || 0;
  return rect;
}

function addText(parent, options) {
  const node = figma.createText();
  parent.appendChild(node);
  node.name = options.name;
  node.fontName = options.font;
  node.fontSize = options.size;
  node.characters = options.text;
  node.fills = [solid(options.color)];
  node.lineHeight = {
    unit: "PIXELS",
    value: options.lineHeight || Math.round(options.size * 1.45)
  };
  node.letterSpacing = {
    unit: "PIXELS",
    value: options.letterSpacing || 0
  };
  node.textAlignHorizontal = options.align || "LEFT";
  node.textAlignVertical = options.verticalAlign || "TOP";
  node.textAutoResize = "NONE";
  node.resize(options.width, options.height);
  node.x = options.x;
  node.y = options.y;
  return node;
}

function addIcon(parent, name, iconName, x, y, size, color) {
  const path = ICONS[iconName];
  if (!path) {
    throw new Error("Unknown icon: " + iconName);
  }
  const svg =
    '<svg width="' +
    size +
    '" height="' +
    size +
    '" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">' +
    '<g stroke="' +
    color +
    '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
    path +
    "</g></svg>";
  const icon = figma.createNodeFromSvg(svg);
  parent.appendChild(icon);
  icon.name = name;
  icon.x = x;
  icon.y = y;
  icon.resize(size, size);
  return icon;
}

function solid(hex) {
  const value = hex.replace("#", "");
  return {
    type: "SOLID",
    color: {
      r: parseInt(value.slice(0, 2), 16) / 255,
      g: parseInt(value.slice(2, 4), 16) / 255,
      b: parseInt(value.slice(4, 6), 16) / 255
    }
  };
}
