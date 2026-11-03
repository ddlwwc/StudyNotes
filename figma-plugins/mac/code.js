const PALETTE = {
  white: "#FFFFFF",
  ink: "#1D2129",
  text: "#4E5969",
  muted: "#86909C",
  faint: "#C9CDD4",
  border: "#E5E6EB",
  nav: "#F7F8FA",
  panel: "#FAFBFC",
  blue: "#3370FF",
  blueSoft: "#F0F5FF",
  blueLine: "#C9D8FF",
  yellow: "#FFF7D6",
  yellowLine: "#F1D887",
  green: "#00B42A",
  greenSoft: "#E8FFEA",
  red: "#F53F3F",
  purpleSoft: "#F5F2FF",
  cyanSoft: "#E8FAFC",
  orangeSoft: "#FFF3E8"
};

const FONT_CANDIDATES = {
  ui: ["PingFang SC", "Inter", "Arial"],
  serif: ["Songti SC", "Noto Serif SC", "Georgia"]
};

let FONTS = null;

function rgb(hex) {
  const clean = hex.replace("#", "");
  return {
    r: parseInt(clean.slice(0, 2), 16) / 255,
    g: parseInt(clean.slice(2, 4), 16) / 255,
    b: parseInt(clean.slice(4, 6), 16) / 255
  };
}

function solid(hex, opacity = 1) {
  return { type: "SOLID", color: rgb(hex), opacity };
}

function createFrame(parent, name, x, y, width, height, fill = null) {
  const node = figma.createFrame();
  parent.appendChild(node);
  node.name = name;
  node.resize(width, height);
  node.x = x;
  node.y = y;
  node.fills = fill ? [solid(fill)] : [];
  node.clipsContent = false;
  return node;
}

function createRect(parent, name, x, y, width, height, fill, radius = 0) {
  const node = figma.createRectangle();
  parent.appendChild(node);
  node.name = name;
  node.resize(width, height);
  node.x = x;
  node.y = y;
  node.fills = [solid(fill)];
  node.cornerRadius = radius;
  return node;
}

function createEllipse(parent, name, x, y, width, height, fill = null) {
  const node = figma.createEllipse();
  parent.appendChild(node);
  node.name = name;
  node.resize(width, height);
  node.x = x;
  node.y = y;
  node.fills = fill ? [solid(fill)] : [];
  return node;
}

function addStroke(node, color, weight = 1) {
  node.strokes = [solid(color)];
  node.strokeWeight = weight;
  node.strokeAlign = "INSIDE";
}

function addText(parent, name, value, x, y, width, height, options = {}) {
  const node = figma.createText();
  parent.appendChild(node);
  node.name = name;
  node.fontName = options.serif ? FONTS.serif : (options.weight || FONTS.regular);
  node.fontSize = options.size || 14;
  node.lineHeight = { unit: "PIXELS", value: options.lineHeight || Math.round((options.size || 14) * 1.5) };
  node.letterSpacing = { unit: "PIXELS", value: 0 };
  node.textAlignHorizontal = options.align || "LEFT";
  node.textAlignVertical = options.valign || "TOP";
  node.fills = [solid(options.color || PALETTE.ink)];
  node.textAutoResize = "NONE";
  node.resize(width, height);
  node.characters = value;
  node.x = x;
  node.y = y;
  if (options.opacity !== undefined) node.opacity = options.opacity;
  return node;
}

function makeAutoFrame(parent, name, x, y, width, height, options = {}) {
  const node = createFrame(parent, name, x, y, width, height, options.fill || null);
  node.layoutMode = options.direction || "HORIZONTAL";
  node.primaryAxisSizingMode = "FIXED";
  node.counterAxisSizingMode = "FIXED";
  node.primaryAxisAlignItems = options.main || "CENTER";
  node.counterAxisAlignItems = options.cross || "CENTER";
  node.itemSpacing = options.gap || 0;
  node.paddingLeft = options.paddingLeft || 0;
  node.paddingRight = options.paddingRight || 0;
  node.paddingTop = options.paddingTop || 0;
  node.paddingBottom = options.paddingBottom || 0;
  if (options.radius) node.cornerRadius = options.radius;
  if (options.stroke) addStroke(node, options.stroke, options.strokeWeight || 1);
  return node;
}

function addDivider(parent, name, x, y, width, vertical = false) {
  return createRect(
    parent,
    name,
    x,
    y,
    vertical ? 1 : width,
    vertical ? width : 1,
    PALETTE.border
  );
}

function hoverButton(parent, name, x, y, width, height, label, options = {}) {
  const fill = options.primary ? PALETTE.blue : (options.fill || PALETTE.white);
  const button = makeAutoFrame(parent, name, x, y, width, height, {
    fill,
    radius: options.radius === undefined ? 6 : options.radius,
    main: "CENTER",
    cross: "CENTER",
    gap: options.gap || 6,
    stroke: options.stroke || null
  });
  if (options.icon) addSimpleIcon(button, `${name} / 图标`, options.icon, options.iconColor || (options.primary ? PALETTE.white : PALETTE.text), 16);
  addText(
    button,
    `${name} / 文字`,
    label,
    0,
    0,
    Math.max(24, width - (options.icon ? 32 : 12)),
    height,
    {
      size: options.size || 13,
      lineHeight: height,
      color: options.color || (options.primary ? PALETTE.white : PALETTE.text),
      weight: options.weight || FONTS.medium,
      align: "CENTER",
      valign: "CENTER"
    }
  );
  return button;
}

function truncateSingleLine(node) {
  node.textAutoResize = "HEIGHT";
  node.textTruncation = "ENDING";
  node.maxLines = 1;
  return node;
}

function addSimpleIcon(parent, name, kind, color = PALETTE.text, size = 16) {
  const icon = createFrame(parent, name, 0, 0, size, size);
  icon.clipsContent = false;

  if (kind === "search") {
    const ring = createEllipse(icon, "圆", size * 0.08, size * 0.08, size * 0.58, size * 0.58);
    ring.fills = [];
    addStroke(ring, color, 1.4);
    const handle = createRect(icon, "手柄", size * 0.61, size * 0.64, size * 0.39, 1.5, color, 1);
    handle.rotation = 45;
    return icon;
  }

  if (kind === "inbox") {
    const box = createRect(icon, "收件箱", size * 0.1, size * 0.23, size * 0.8, size * 0.64, PALETTE.white, 2);
    box.fills = [];
    addStroke(box, color, 1.3);
    const slot = createRect(icon, "箱口", size * 0.25, size * 0.56, size * 0.5, 1.4, color, 1);
    slot.rotation = 0;
    return icon;
  }

  if (kind === "clock") {
    const ring = createEllipse(icon, "表盘", size * 0.08, size * 0.08, size * 0.82, size * 0.82);
    ring.fills = [];
    addStroke(ring, color, 1.3);
    createRect(icon, "时针", size * 0.48, size * 0.27, 1.4, size * 0.3, color, 1);
    createRect(icon, "分针", size * 0.48, size * 0.49, size * 0.25, 1.4, color, 1);
    return icon;
  }

  if (kind === "library" || kind === "book") {
    const first = createRect(icon, "书页 1", size * 0.11, size * 0.14, size * 0.36, size * 0.71, PALETTE.white, 2);
    first.fills = kind === "book" ? [solid(PALETTE.blueSoft)] : [];
    addStroke(first, kind === "book" ? PALETTE.blue : color, 1.2);
    const second = createRect(icon, "书页 2", size * 0.53, size * 0.14, size * 0.36, size * 0.71, PALETTE.white, 2);
    second.fills = [];
    addStroke(second, kind === "book" ? PALETTE.blue : color, 1.2);
    return icon;
  }

  if (kind === "spark") {
    const outer = createEllipse(icon, "外圈", size * 0.12, size * 0.12, size * 0.76, size * 0.76, color, 0);
    outer.opacity = 0.16;
    const mid = createEllipse(icon, "内圈", size * 0.31, size * 0.31, size * 0.38, size * 0.38, color, 0);
    const center = createEllipse(icon, "中心", size * 0.42, size * 0.42, size * 0.16, size * 0.16, color, 0);
    return icon;
  }

  if (kind === "plus") {
    createRect(icon, "横", size * 0.18, size * 0.47, size * 0.64, 1.5, color, 1);
    createRect(icon, "竖", size * 0.47, size * 0.18, 1.5, size * 0.64, color, 1);
    return icon;
  }

  if (kind === "publish") {
    const up = createRect(icon, "箭头上", size * 0.46, size * 0.17, 1.5, size * 0.46, color, 1);
    const left = createRect(icon, "箭头左", size * 0.31, size * 0.28, size * 0.22, 1.5, color, 1);
    left.rotation = -45;
    const right = createRect(icon, "箭头右", size * 0.47, size * 0.28, size * 0.22, 1.5, color, 1);
    right.rotation = 45;
    createRect(icon, "底座", size * 0.22, size * 0.74, size * 0.56, 1.5, color, 1);
    return icon;
  }

  if (kind === "grid") {
    createRect(icon, "格 1", size * 0.13, size * 0.13, size * 0.3, size * 0.3, color, 1.5);
    createRect(icon, "格 2", size * 0.57, size * 0.13, size * 0.3, size * 0.3, color, 1.5);
    createRect(icon, "格 3", size * 0.13, size * 0.57, size * 0.3, size * 0.3, color, 1.5);
    createRect(icon, "格 4", size * 0.57, size * 0.57, size * 0.3, size * 0.3, color, 1.5);
    return icon;
  }

  if (kind === "more") {
    createEllipse(icon, "点 1", size * 0.14, size * 0.45, 2, 2, color);
    createEllipse(icon, "点 2", size * 0.47, size * 0.45, 2, 2, color);
    createEllipse(icon, "点 3", size * 0.8, size * 0.45, 2, 2, color);
    return icon;
  }

  if (kind === "collapse") {
    createRect(icon, "侧栏", size * 0.12, size * 0.16, size * 0.76, size * 0.68, PALETTE.white, 2);
    addStroke(icon.children[0], color, 1.2);
    createRect(icon, "中线", size * 0.57, size * 0.17, 1.2, size * 0.66, color, 1);
    return icon;
  }

  if (kind === "tag") {
    const body = createRect(icon, "标签", size * 0.1, size * 0.25, size * 0.76, size * 0.5, PALETTE.white, 2);
    body.fills = [];
    addStroke(body, color, 1.2);
    createEllipse(icon, "孔", size * 0.28, size * 0.43, size * 0.14, size * 0.14, color);
    return icon;
  }

  const circle = createEllipse(icon, "通用图标", size * 0.16, size * 0.16, size * 0.68, size * 0.68, color);
  circle.opacity = 0.2;
  return icon;
}

function addLogo(parent) {
  const mark = createFrame(parent, "品牌标记", 20, 12, 30, 30, PALETTE.blue);
  mark.cornerRadius = 7;
  createRect(mark, "白色页面 1", 8, 7, 10, 16, PALETTE.white, 2);
  createRect(mark, "白色页面 2", 15, 9, 7, 14, PALETTE.blue, 1);
  createRect(mark, "白色页面 2 描边", 15, 9, 7, 14, PALETTE.white, 1).fills = [];
  mark.children[2].strokes = [solid(PALETTE.white)];
  mark.children[2].strokeWeight = 1.3;
}

function buildHeader(parent) {
  const header = createFrame(parent, "全局顶栏", 0, 0, 1440, 56, PALETTE.white);
  addDivider(header, "顶栏底边", 0, 55, 1440);
  addLogo(header);
  addText(header, "产品名", "StudyNotes", 60, 16, 120, 24, {
    size: 16,
    lineHeight: 24,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  createEllipse(header, "同步状态点", 170, 24, 7, 7, PALETTE.green);
  addText(header, "同步状态", "iCloud 已同步", 184, 18, 112, 20, {
    size: 12,
    lineHeight: 20,
    color: PALETTE.text
  });

  const actions = createFrame(header, "主操作区", 944, 12, 476, 32);
  actions.layoutMode = "HORIZONTAL";
  actions.primaryAxisSizingMode = "FIXED";
  actions.counterAxisSizingMode = "FIXED";
  actions.primaryAxisAlignItems = "MAX";
  actions.counterAxisAlignItems = "CENTER";
  actions.itemSpacing = 8;
  hoverButton(actions, "导入", 0, 0, 70, 32, "导入", { icon: "inbox", size: 13, fill: PALETTE.white });
  hoverButton(actions, "新建笔记", 0, 0, 92, 32, "新建笔记", { icon: "plus", size: 13, fill: PALETTE.white });
  hoverButton(actions, "AI 研读", 0, 0, 92, 32, "AI 研读", { icon: "spark", size: 13, fill: PALETTE.white });
  hoverButton(actions, "发布", 0, 0, 76, 32, "发布", {
    primary: true,
    icon: "publish",
    size: 13,
    radius: 6
  });
  return header;
}

function navRow(parent, label, y, options = {}) {
  const row = createFrame(
    parent,
    `导航 / ${label}`,
    8,
    y,
    168,
    options.height || 36,
    options.selected ? PALETTE.blueSoft : null
  );
  if (options.selected) row.cornerRadius = 4;
  addSimpleIcon(row, "图标", options.icon || "book", options.selected ? PALETTE.blue : PALETTE.text, 16).x = options.indent || 10;
  row.children[row.children.length - 1].y = ((options.height || 36) - 16) / 2;
  addText(row, "文字", label, (options.indent || 10) + 24, 0, 116, options.height || 36, {
    size: 13,
    lineHeight: options.height || 36,
    color: options.selected ? PALETTE.blue : PALETTE.text,
    weight: options.selected ? FONTS.medium : FONTS.regular,
    valign: "CENTER"
  });
  if (options.badge) {
    const badge = createFrame(row, `数量 ${options.badge}`, 142, (options.height - 20) / 2, 20, 20, PALETTE.red);
    badge.cornerRadius = 10;
    addText(badge, "数字", String(options.badge), 0, 0, 20, 20, {
      size: 10,
      lineHeight: 20,
      color: PALETTE.white,
      weight: FONTS.medium,
      align: "CENTER",
      valign: "CENTER"
    });
  }
  if (options.chevron) {
    addText(row, "展开提示", options.chevron, 146, 0, 14, options.height || 36, {
      size: 12,
      lineHeight: options.height || 36,
      color: PALETTE.muted,
      align: "CENTER",
      valign: "CENTER"
    });
  }
  return row;
}

function buildLeftNavigation(parent, activeKnowledge = "学习科学") {
  const nav = createFrame(parent, "左侧知识目录", 0, 56, 184, 968, PALETTE.nav);
  addDivider(nav, "目录右边框", 183, 0, 968, true);

  navRow(nav, "搜索", 14, { icon: "search" });
  navRow(nav, "收件箱", 54, { icon: "inbox", badge: 3 });
  navRow(nav, "最近阅读", 94, { icon: "clock" });
  navRow(nav, "待复习", 134, { icon: "book" });
  addDivider(nav, "全局入口分隔", 12, 184, 160);

  addText(nav, "知识库标题", "知识库", 12, 198, 96, 24, {
    size: 12,
    lineHeight: 24,
    color: PALETTE.text,
    weight: FONTS.medium
  });
  const addButton = createFrame(nav, "新建知识库", 152, 198, 22, 22);
  addSimpleIcon(addButton, "加号", "plus", PALETTE.text, 14).x = 4;
  addButton.children[0].y = 4;

  navRow(nav, "学习科学", 230, {
    icon: "library",
    selected: activeKnowledge === "学习科学",
    chevron: "›"
  });

  let nextKnowledgeY = 266;
  if (activeKnowledge === "学习科学") {
    navRow(nav, "认知心理学", 266, {
      icon: "book",
      selected: true,
      indent: 32,
      height: 34
    });
    const folderRows = ["阅读与记忆", "教学设计", "研究方法"];
    folderRows.forEach((item, index) => {
      navRow(nav, item, 302 + index * 32, {
        icon: "book",
        indent: 32,
        height: 32
      });
    });
    nextKnowledgeY = 402;
  }

  const knowledge = [
    { name: "产品设计", icon: "grid", selected: activeKnowledge === "产品设计" },
    { name: "编程与系统", icon: "grid", selected: activeKnowledge === "编程与系统" },
    { name: "语言学习", icon: "book", selected: activeKnowledge === "语言学习" },
    { name: "收藏与待整理", icon: "tag", selected: false }
  ];

  knowledge.forEach((item, index) => {
    navRow(nav, item.name, nextKnowledgeY + index * 36, {
      icon: item.icon,
      selected: item.selected,
      chevron: index < 3 ? "›" : null
    });
  });

  const status = createFrame(nav, "底部同步状态", 12, 916, 160, 36, PALETTE.white);
  status.cornerRadius = 6;
  createEllipse(status, "同步点", 10, 15, 6, 6, PALETTE.green);
  addText(status, "同步说明", "iCloud 已同步", 24, 7, 112, 22, {
    size: 11,
    lineHeight: 22,
    color: PALETTE.text
  });
  return nav;
}

function materialItem(parent, y, item, selected = false) {
  const row = createFrame(parent, `材料 / ${item.title}`, 0, y, 210, 88, selected ? PALETTE.blueSoft : PALETTE.white);
  if (selected) createRect(row, "选中线", 0, 0, 3, 88, PALETTE.blue);
  addDivider(row, "分隔线", 16, 87, 194);

  const iconBox = createFrame(row, "材料类型", 16, 17, 24, 24, selected ? PALETTE.white : PALETTE.blueSoft);
  iconBox.cornerRadius = 5;
  if (selected) addStroke(iconBox, PALETTE.blueLine);
  addSimpleIcon(iconBox, "文档图标", "book", PALETTE.blue, 14).x = 5;
  iconBox.children[0].y = 5;

  const title = addText(row, "标题", item.title, 50, 13, 144, 28, {
    size: 13,
    lineHeight: 22,
    weight: selected ? FONTS.semibold : FONTS.medium,
    color: selected ? PALETTE.ink : PALETTE.text
  });
  truncateSingleLine(title);
  const meta = addText(row, "类型与时间", `${item.type} · ${item.time}`, 50, 43, 112, 20, {
    size: 11,
    lineHeight: 18,
    color: PALETTE.muted
  });
  truncateSingleLine(meta);
  if (item.notes) {
    addSimpleIcon(row, "标注数图标", "tag", PALETTE.muted, 13).x = 171;
    row.children[row.children.length - 1].y = 48;
    addText(row, "标注数", String(item.notes), 190, 43, 18, 20, {
      size: 11,
      lineHeight: 20,
      color: PALETTE.muted
    });
  }
  return row;
}

function buildMaterialList(parent) {
  const list = createFrame(parent, "材料列表", 184, 56, 210, 968, PALETTE.white);
  addDivider(list, "列表右边框", 209, 0, 968, true);

  const breadcrumb = addText(list, "面包屑", "学习科学 / 认知心理学", 16, 16, 144, 24, {
    size: 12,
    lineHeight: 24,
    color: PALETTE.text,
    weight: FONTS.medium
  });
  truncateSingleLine(breadcrumb);
  addSimpleIcon(list, "更多操作", "more", PALETTE.muted, 18).x = 176;
  list.children[list.children.length - 1].y = 19;

  const search = createFrame(list, "列表搜索", 12, 52, 186, 34, PALETTE.nav);
  search.cornerRadius = 6;
  addSimpleIcon(search, "搜索图标", "search", PALETTE.muted, 14).x = 10;
  search.children[0].y = 10;
  const searchPlaceholder = addText(search, "占位文字", "搜索当前知识库", 32, 0, 132, 34, {
    size: 12,
    lineHeight: 34,
    color: PALETTE.muted,
    valign: "CENTER"
  });
  truncateSingleLine(searchPlaceholder);

  addText(list, "材料筛选", "全部  12", 16, 102, 76, 28, {
    size: 12,
    lineHeight: 28,
    color: PALETTE.blue,
    weight: FONTS.medium
  });
  addText(list, "排序说明", "最近更新", 148, 102, 54, 28, {
    size: 11,
    lineHeight: 28,
    color: PALETTE.muted
  });
  addDivider(list, "筛选区底边", 0, 136, 210);

  const items = [
    { title: "认知负荷理论与学习设计", type: "网页文章", time: "今天 09:40", notes: 7 },
    { title: "间隔重复：从记忆曲线到复习节奏", type: "文档", time: "10月31日", notes: 4 },
    { title: "多媒体学习的双通道假设", type: "网页文章", time: "10月31日", notes: 2 },
    { title: "如何设计有效的概念图", type: "笔记", time: "10月29日", notes: 3 },
    { title: "工作记忆的容量限制", type: "网页文章", time: "10月29日", notes: 1 },
    { title: "生成性学习与自我解释", type: "文档", time: "10月28日", notes: 4 },
    { title: "检索练习为什么有效", type: "网页文章", time: "10月26日", notes: 2 },
    { title: "学习目标与反馈闭环", type: "笔记", time: "10月24日", notes: 1 }
  ];
  items.forEach((item, index) => materialItem(list, 138 + index * 88, item, index === 0));
  return list;
}

function toolbarAction(parent, x, label, icon, width = 72) {
  const group = createFrame(parent, `阅读操作 / ${label}`, x, 12, width, 28);
  addSimpleIcon(group, "图标", icon, PALETTE.text, 15).x = 0;
  group.children[0].y = 6;
  addText(group, "文字", label, 21, 0, width - 21, 28, {
    size: 11,
    lineHeight: 28,
    color: PALETTE.text,
    valign: "CENTER"
  });
  return group;
}

function selectionToolbar(parent, x, y) {
  const bubble = makeAutoFrame(parent, "文本选区操作", x, y, 280, 40, {
    fill: PALETTE.white,
    radius: 7,
    stroke: PALETTE.border,
    gap: 8,
    paddingLeft: 12,
    paddingRight: 12
  });
  bubble.effects = [
    {
      type: "DROP_SHADOW",
      color: { r: 0.12, g: 0.18, b: 0.29, a: 0.1 },
      offset: { x: 0, y: 2 },
      radius: 6,
      spread: 0,
      visible: true,
      blendMode: "NORMAL"
    }
  ];
  hoverButton(bubble, "高亮", 0, 0, 72, 28, "高亮", { icon: "tag", size: 11 });
  hoverButton(bubble, "高亮并笔记", 0, 0, 104, 28, "高亮并笔记", { icon: "plus", size: 11 });
  hoverButton(bubble, "AI 解释", 0, 0, 76, 28, "AI 解释", { icon: "spark", size: 11 });
  return bubble;
}

function diagramBox(parent, x, y, title, subtitle, tone, marker) {
  const box = createFrame(parent, `图示 / ${title}`, x, y, 190, 142, tone);
  box.cornerRadius = 6;
  addSimpleIcon(box, "标记", marker, PALETTE.blue, 28).x = 81;
  box.children[0].y = 18;
  addText(box, "标题", title, 8, 57, 174, 24, {
    size: 13,
    lineHeight: 24,
    weight: FONTS.semibold,
    color: PALETTE.ink,
    align: "CENTER"
  });
  addText(box, "说明", subtitle, 16, 88, 158, 42, {
    size: 11,
    lineHeight: 19,
    color: PALETTE.text,
    align: "CENTER"
  });
  return box;
}

function buildReadingScreen(page) {
  const board = createFrame(page, "Mac / 阅读标注", 0, 0, 1440, 1024, PALETTE.white);
  board.clipsContent = true;
  board.strokes = [solid(PALETTE.border)];
  board.strokeWeight = 1;
  board.setPluginData("studynotes-mac-generated", "reading");

  buildHeader(board);
  buildLeftNavigation(board, "学习科学");
  buildMaterialList(board);

  const reading = createFrame(board, "阅读工作区", 460, 56, 720, 968, PALETTE.white);
  addDivider(reading, "工具栏底边", 0, 52, 720);

  addText(reading, "阅读面包屑", "学习科学 / 认知心理学", 24, 14, 220, 24, {
    size: 12,
    lineHeight: 24,
    color: PALETTE.text
  });

  toolbarAction(reading, 478, "目录", "grid", 52);
  toolbarAction(reading, 542, "文档内搜索", "search", 88);
  toolbarAction(reading, 642, "编辑副本", "book", 72);
  addDivider(reading, "工具栏按钮分隔", 464, 12, 24, true);
  addSimpleIcon(reading, "专注模式", "collapse", PALETTE.muted, 18).x = 682;
  reading.children[reading.children.length - 1].y = 17;

  addText(reading, "文章标题", "认知负荷理论与学习设计", 36, 82, 648, 44, {
    size: 30,
    lineHeight: 40,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  addText(reading, "文章信息", "网页文章 · 约 18 分钟 · 更新于 10月31日", 36, 126, 430, 22, {
    size: 12,
    lineHeight: 22,
    color: PALETTE.muted
  });
  addText(reading, "版本信息", "阅读副本 v3 · 已保存 10:42", 500, 126, 184, 22, {
    size: 11,
    lineHeight: 22,
    color: PALETTE.green,
    align: "RIGHT"
  });
  addDivider(reading, "标题分隔", 36, 158, 648);

  addText(
    reading,
    "正文 1",
    "认知负荷理论关注工作记忆在学习过程中的限制。教学设计的目标并不是一味减少信息，而是把有限的学习资源引向与图式建构相关的活动。",
    36,
    184,
    648,
    68,
    { serif: true, size: 16, lineHeight: 30, color: PALETTE.text }
  );
  addText(
    reading,
    "正文 2",
    "内在负荷来自材料本身的复杂性；外在负荷则由不恰当的呈现方式产生。",
    36,
    264,
    648,
    32,
    { serif: true, size: 16, lineHeight: 30, color: PALETTE.text }
  );

  addText(reading, "标注序号", "03", 8, 304, 20, 28, {
    size: 11,
    lineHeight: 26,
    color: "#B87500",
    align: "CENTER"
  });
  const highlighted = createFrame(reading, "已标注文本", 36, 300, 648, 34, PALETTE.yellow);
  highlighted.cornerRadius = 3;
  addText(
    highlighted,
    "标注原文",
    "有效设计应降低无关负荷，并为生成性加工留出空间。",
    8,
    0,
    632,
    34,
    { serif: true, size: 16, lineHeight: 34, color: PALETTE.text, valign: "CENTER" }
  );
  selectionToolbar(reading, 214, 342);

  addText(
    reading,
    "正文 3",
    "因此，图文整合、分段呈现与及时反馈需要共同服务于概念之间的关系，而不是停留在视觉层面的整齐。",
    36,
    398,
    648,
    62,
    { serif: true, size: 16, lineHeight: 30, color: PALETTE.text }
  );

  const diagram = createFrame(reading, "认知负荷图示", 36, 472, 648, 238, PALETTE.white);
  addStroke(diagram, PALETTE.border);
  diagram.cornerRadius = 7;
  addText(diagram, "图示标题", "认知负荷的三个来源", 16, 14, 616, 26, {
    size: 14,
    lineHeight: 26,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  diagramBox(diagram, 16, 56, "内在负荷", "学习内容的固有难度\n和元素间关联", PALETTE.blueSoft, "grid");
  diagramBox(diagram, 229, 56, "外在负荷", "与学习无关的认知消耗\n呈现方式造成", PALETTE.purpleSoft, "book");
  diagramBox(diagram, 442, 56, "生成性负荷", "投入意义建构与迁移\n等高级认知活动", PALETTE.cyanSoft, "spark");
  addText(diagram, "箭头 1", "→", 207, 108, 20, 30, {
    size: 18,
    lineHeight: 30,
    color: PALETTE.muted,
    align: "CENTER"
  });
  addText(diagram, "箭头 2", "→", 420, 108, 20, 30, {
    size: 18,
    lineHeight: 30,
    color: PALETTE.muted,
    align: "CENTER"
  });

  addText(
    reading,
    "正文 4",
    "理解这三种负荷的作用机制，有助于在教学设计中做出合理取舍。关键不是简单地追求“更少的内容”，而是通过适合的呈现与活动设计，让有限的认知资源更多地服务于知识的深入理解和灵活应用。",
    36,
    732,
    648,
    96,
    { serif: true, size: 16, lineHeight: 30, color: PALETTE.text }
  );
  addDivider(reading, "正文分隔", 36, 854, 648);
  addText(reading, "章节标题", "本节要点", 36, 876, 648, 28, {
    size: 17,
    lineHeight: 28,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  addText(
    reading,
    "要点 1",
    "01  三种负荷共同影响学习者的认知资源分配。",
    36,
    914,
    648,
    26,
    { size: 13, lineHeight: 26, color: PALETTE.text }
  );
  addText(
    reading,
    "要点 2",
    "02  降低无关负荷并不等于删掉所有复杂内容。",
    36,
    944,
    648,
    26,
    { size: 13, lineHeight: 26, color: PALETTE.text }
  );

  buildStudyPanel(board);
  return board;
}

function annotationCard(parent, y, number, date, quote, note, selected = false) {
  const card = createFrame(
    parent,
    `标注 ${number}`,
    14,
    y,
    232,
    selected ? 164 : 142,
    selected ? "#FFFBEF" : PALETTE.white
  );
  card.cornerRadius = 6;
  addStroke(card, selected ? PALETTE.yellowLine : PALETTE.border);
  addText(card, "编号", number, 12, 10, 24, 20, {
    size: 12,
    lineHeight: 20,
    color: selected ? "#B87500" : PALETTE.text,
    weight: FONTS.medium
  });
  addText(card, "时间", date, 130, 10, 90, 20, {
    size: 10,
    lineHeight: 20,
    color: PALETTE.muted,
    align: "RIGHT"
  });
  addText(card, "摘录", quote, 12, 34, 208, selected ? 52 : 44, {
    serif: true,
    size: 12,
    lineHeight: 19,
    color: PALETTE.text
  });
  addText(card, "我的笔记", note, 12, selected ? 90 : 81, 208, selected ? 40 : 32, {
    size: 11,
    lineHeight: 18,
    color: PALETTE.muted
  });
  if (selected) {
    addSimpleIcon(card, "定位图标", "publish", PALETTE.blue, 12).x = 12;
    card.children[card.children.length - 1].y = 138;
    addText(card, "定位原文", "定位原文", 29, 132, 58, 22, {
      size: 10,
      lineHeight: 22,
      color: PALETTE.blue
    });
    addSimpleIcon(card, "复习图标", "clock", PALETTE.blue, 12).x = 132;
    card.children[card.children.length - 1].y = 138;
    addText(card, "加入复习", "加入复习", 149, 132, 66, 22, {
      size: 10,
      lineHeight: 22,
      color: PALETTE.blue
    });
  }
  return card;
}

function buildStudyPanel(parent) {
  const panel = createFrame(parent, "右侧研读栏", 1180, 56, 260, 968, PALETTE.panel);
  addDivider(panel, "研读栏左边框", 0, 0, 968, true);
  addText(panel, "研读栏标题", "研读层", 16, 12, 180, 28, {
    size: 15,
    lineHeight: 28,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  addSimpleIcon(panel, "收起研读栏", "collapse", PALETTE.muted, 18).x = 224;
  panel.children[panel.children.length - 1].y = 17;
  addDivider(panel, "研读栏标题分隔", 0, 52, 260);

  addText(panel, "标注页签", "标注  7", 16, 60, 100, 32, {
    size: 13,
    lineHeight: 32,
    color: PALETTE.ink,
    weight: FONTS.medium
  });
  addText(panel, "AI 页签", "AI 研读", 116, 60, 72, 32, {
    size: 13,
    lineHeight: 32,
    color: PALETTE.muted
  });
  createRect(panel, "选中页签线", 16, 92, 52, 2, PALETTE.blue, 1);
  addDivider(panel, "页签分隔", 0, 94, 260);

  annotationCard(
    panel,
    108,
    "03",
    "10月31日 10:42",
    "“有效设计应降低无关负荷，并为生成性加工留出空间。”",
    "关键不只是减少内容，而是让注意力进入关系建构。可联系多媒体学习原则继续核对。",
    true
  );
  annotationCard(
    panel,
    286,
    "02",
    "10月31日 09:18",
    "“外在负荷由不恰当的呈现方式产生。”",
    "分段呈现与减少装饰性信息。"
  );
  annotationCard(
    panel,
    442,
    "01",
    "10月30日 18:06",
    "“图式建构是学习发生的核心。”",
    "后续补充概念图例子。"
  );

  const aiPrompt = createFrame(panel, "AI 研读输入区", 0, 738, 260, 230, PALETTE.white);
  addDivider(aiPrompt, "AI 区域顶边", 0, 0, 260);
  addText(aiPrompt, "AI 标题", "向 AI 提问当前选段", 14, 14, 170, 24, {
    size: 12,
    lineHeight: 24,
    weight: FONTS.medium,
    color: PALETTE.ink
  });
  addText(aiPrompt, "折叠提示", "⌃", 230, 14, 16, 24, {
    size: 13,
    lineHeight: 24,
    color: PALETTE.muted,
    align: "CENTER"
  });
  addText(aiPrompt, "发送范围", "仅发送当前选段 · 182 字", 14, 42, 190, 22, {
    size: 10,
    lineHeight: 22,
    color: PALETTE.muted
  });
  addText(aiPrompt, "模型", "DeepSeek  v", 184, 42, 62, 22, {
    size: 10,
    lineHeight: 22,
    color: PALETTE.blue,
    align: "RIGHT"
  });
  const input = createFrame(aiPrompt, "问题输入框", 14, 72, 232, 64, PALETTE.white);
  input.cornerRadius = 6;
  addStroke(input, PALETTE.border);
  addText(input, "输入占位", "解释这段内容与外在负荷的关系", 10, 8, 212, 40, {
    size: 11,
    lineHeight: 19,
    color: PALETTE.text
  });
  addText(input, "输入提示", "Enter 发送  ·  Shift+Enter 换行", 10, 44, 212, 16, {
    size: 9,
    lineHeight: 16,
    color: PALETTE.muted
  });
  hoverButton(aiPrompt, "解释选段", 14, 148, 232, 34, "解释选段", {
    primary: true,
    icon: "spark",
    size: 12
  });
  addText(aiPrompt, "上下文说明", "不会自动发送图片或整篇材料", 14, 190, 232, 20, {
    size: 9,
    lineHeight: 20,
    color: PALETTE.muted,
    align: "CENTER"
  });
  return panel;
}

function quickAction(parent, x, y, title, description, icon, tone) {
  const card = createFrame(parent, `快捷操作 / ${title}`, x, y, 213, 78, PALETTE.white);
  card.cornerRadius = 7;
  addStroke(card, PALETTE.border);
  const iconBox = createFrame(card, "操作图标", 14, 18, 36, 36, tone);
  iconBox.cornerRadius = 6;
  addSimpleIcon(iconBox, "图标", icon, PALETTE.blue, 18).x = 9;
  iconBox.children[0].y = 9;
  addText(card, "标题", title, 62, 14, 136, 24, {
    size: 13,
    lineHeight: 24,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  addText(card, "说明", description, 62, 39, 138, 20, {
    size: 10,
    lineHeight: 20,
    color: PALETTE.muted
  });
  return card;
}

function knowledgeRow(parent, y, name, detail, count, tone, selected = false) {
  const row = createFrame(parent, `知识库 / ${name}`, 0, y, 596, 62, selected ? PALETTE.blueSoft : PALETTE.white);
  if (selected) row.cornerRadius = 6;
  addDivider(row, "分隔线", 0, 61, 596);
  const mark = createFrame(row, "知识库标记", 12, 14, 32, 32, tone);
  mark.cornerRadius = 6;
  addSimpleIcon(mark, "图标", "library", selected ? PALETTE.blue : PALETTE.text, 16).x = 8;
  mark.children[0].y = 8;
  addText(row, "名称", name, 56, 10, 190, 24, {
    size: 13,
    lineHeight: 24,
    weight: FONTS.medium,
    color: selected ? PALETTE.blue : PALETTE.ink
  });
  addText(row, "说明", detail, 56, 34, 310, 20, {
    size: 10,
    lineHeight: 20,
    color: PALETTE.muted
  });
  addText(row, "材料数", `${count} 份材料`, 458, 0, 96, 62, {
    size: 11,
    lineHeight: 62,
    color: PALETTE.muted,
    align: "RIGHT",
    valign: "CENTER"
  });
  return row;
}

function inboxRow(parent, y, title, type, selected = false) {
  const row = createFrame(parent, `收件箱 / ${title}`, 0, y, 292, 68, selected ? PALETTE.blueSoft : PALETTE.white);
  if (selected) row.cornerRadius = 6;
  addDivider(row, "分隔线", 12, 67, 268);
  const icon = createFrame(row, "类型图标", 12, 17, 30, 30, PALETTE.blueSoft);
  icon.cornerRadius = 5;
  addSimpleIcon(icon, "图标", type === "网页" ? "book" : "inbox", PALETTE.blue, 15).x = 7;
  icon.children[0].y = 7;
  addText(row, "标题", title, 52, 11, 218, 24, {
    size: 12,
    lineHeight: 24,
    weight: FONTS.medium,
    color: PALETTE.text
  });
  addText(row, "来源", `${type} · 待整理`, 52, 34, 210, 20, {
    size: 10,
    lineHeight: 20,
    color: PALETTE.muted
  });
  return row;
}

function buildWorkspaceScreen(page) {
  const board = createFrame(page, "Mac / 知识库工作台", 0, 1128, 1440, 1024, PALETTE.white);
  board.clipsContent = true;
  board.strokes = [solid(PALETTE.border)];
  board.strokeWeight = 1;
  board.setPluginData("studynotes-mac-generated", "workspace");

  buildHeader(board);
  buildLeftNavigation(board, "学习科学");

  const list = createFrame(board, "工作台侧栏", 184, 56, 276, 968, PALETTE.nav);
  addDivider(list, "侧栏右边框", 275, 0, 968, true);
  addText(list, "侧栏标题", "开始", 18, 18, 120, 30, {
    size: 18,
    lineHeight: 30,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  hoverButton(list, "全局搜索", 18, 62, 240, 36, "搜索材料、笔记与标注", {
    icon: "search",
    size: 11,
    fill: PALETTE.white,
    stroke: PALETTE.border,
    color: PALETTE.muted
  });
  navRow(list, "收件箱", 118, { icon: "inbox", badge: 3 });
  navRow(list, "最近阅读", 158, { icon: "clock" });
  navRow(list, "待复习", 198, { icon: "book" });
  addDivider(list, "导航分隔", 16, 246, 244);
  addText(list, "知识库标题", "我的知识库", 18, 264, 160, 24, {
    size: 12,
    lineHeight: 24,
    color: PALETTE.text,
    weight: FONTS.medium
  });
  const knowledgeNames = ["学习科学", "产品设计", "编程与系统", "语言学习", "收藏与待整理"];
  knowledgeNames.forEach((name, index) => {
    navRow(list, name, 296 + index * 36, {
      icon: index === 0 ? "library" : "grid",
      selected: index === 0
    });
  });
  addDivider(list, "知识库分隔", 16, 484, 244);
  addText(list, "标签标题", "常用标签", 18, 500, 180, 24, {
    size: 12,
    lineHeight: 24,
    color: PALETTE.text,
    weight: FONTS.medium
  });
  const tags = ["认知科学", "学习设计", "阅读方法", "记忆"];
  tags.forEach((tag, index) => {
    const tagRow = createFrame(list, `标签 / ${tag}`, 18, 532 + index * 34, 240, 30);
    addSimpleIcon(tagRow, "标签图标", "tag", PALETTE.muted, 13).x = 4;
    tagRow.children[0].y = 8;
    addText(tagRow, "名称", tag, 26, 0, 180, 30, {
      size: 11,
      lineHeight: 30,
      color: PALETTE.text
    });
  });
  const listStatus = createFrame(list, "侧栏同步状态", 16, 916, 244, 36, PALETTE.white);
  listStatus.cornerRadius = 6;
  createEllipse(listStatus, "同步点", 10, 15, 6, 6, PALETTE.green);
  addText(listStatus, "同步文字", "iCloud 已同步 · 3.2 GB 可用", 24, 7, 208, 22, {
    size: 10,
    lineHeight: 22,
    color: PALETTE.text
  });

  const content = createFrame(board, "知识库工作台内容", 460, 56, 980, 968, PALETTE.white);
  addText(content, "页面标题", "知识库工作台", 32, 28, 300, 36, {
    size: 24,
    lineHeight: 36,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  addText(content, "页面摘要", "收集、整理，再回到阅读。当前有 12 份材料等待继续研读。", 32, 66, 620, 24, {
    size: 12,
    lineHeight: 24,
    color: PALETTE.muted
  });
  hoverButton(content, "整理收件箱", 792, 32, 156, 34, "整理收件箱  3", {
    fill: PALETTE.white,
    icon: "inbox",
    stroke: PALETTE.border,
    size: 11
  });

  const quickTitleX = 32;
  addText(content, "快捷操作标题", "开始工作", 32, 112, 200, 26, {
    size: 14,
    lineHeight: 26,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  quickAction(content, 32, 146, "导入材料", "文件、网页与文件夹", "inbox", PALETTE.blueSoft);
  quickAction(content, 258, 146, "新建笔记", "创建 Markdown 笔记", "plus", PALETTE.greenSoft);
  quickAction(content, 484, 146, "AI 研读", "解释、总结或思维导图", "spark", PALETTE.purpleSoft);
  quickAction(content, 710, 146, "发布文章", "生成只读 Web 文章", "publish", PALETTE.orangeSoft);

  addText(content, "知识库区块标题", "知识库", 32, 254, 120, 26, {
    size: 14,
    lineHeight: 26,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  hoverButton(content, "新建知识库", 522, 252, 106, 28, "新建知识库", {
    fill: PALETTE.white,
    icon: "plus",
    stroke: PALETTE.border,
    size: 10
  });
  addDivider(content, "知识库标题分隔", 32, 288, 596);
  knowledgeRow(content, 294, "学习科学", "认知心理学、阅读与记忆、教学设计", 48, PALETTE.blueSoft, true);
  knowledgeRow(content, 356, "产品设计", "研究方法、交互原型、设计系统", 26, PALETTE.purpleSoft);
  knowledgeRow(content, 418, "编程与系统", "Java、网络与系统设计", 34, PALETTE.cyanSoft);
  knowledgeRow(content, 480, "语言学习", "英语阅读、词汇与表达", 18, PALETTE.greenSoft);
  knowledgeRow(content, 542, "收藏与待整理", "尚未归档的网页与零散笔记", 9, PALETTE.orangeSoft);

  addText(content, "最近阅读标题", "最近阅读", 32, 638, 140, 26, {
    size: 14,
    lineHeight: 26,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  addText(content, "查看全部", "查看全部", 550, 638, 78, 26, {
    size: 10,
    lineHeight: 26,
    color: PALETTE.blue,
    align: "RIGHT"
  });
  const recent = [
    ["认知负荷理论与学习设计", "学习科学 / 认知心理学", "10分钟前", 7],
    ["从用户目标到交互原型", "产品设计 / 交互原型", "昨天", 4],
    ["Java 并发模型梳理", "编程与系统 / Java", "10月30日", 3]
  ];
  recent.forEach((item, index) => {
    const row = createFrame(content, `最近阅读 / ${item[0]}`, 32, 674 + index * 62, 596, 58, PALETTE.white);
    addDivider(row, "分隔线", 0, 57, 596);
    const iconBox = createFrame(row, "类型", 4, 12, 32, 32, PALETTE.blueSoft);
    iconBox.cornerRadius = 5;
    addSimpleIcon(iconBox, "文档", index === 2 ? "book" : "library", PALETTE.blue, 15).x = 8;
    iconBox.children[0].y = 8;
    addText(row, "标题", item[0], 48, 7, 294, 24, {
      size: 12,
      lineHeight: 24,
      weight: FONTS.medium,
      color: PALETTE.ink
    });
    addText(row, "位置", item[1], 48, 31, 310, 18, {
      size: 10,
      lineHeight: 18,
      color: PALETTE.muted
    });
    addText(row, "时间", item[2], 420, 0, 86, 58, {
      size: 10,
      lineHeight: 58,
      color: PALETTE.muted,
      align: "RIGHT",
      valign: "CENTER"
    });
    addText(row, "标注数", `${item[3]} 条标注`, 512, 0, 66, 58, {
      size: 10,
      lineHeight: 58,
      color: PALETTE.muted,
      align: "RIGHT",
      valign: "CENTER"
    });
  });

  const aside = createFrame(content, "工作台右侧概览", 656, 112, 292, 806, PALETTE.panel);
  aside.cornerRadius = 7;
  addStroke(aside, PALETTE.border);
  addText(aside, "收件箱标题", "收件箱", 16, 14, 120, 28, {
    size: 14,
    lineHeight: 28,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  addText(aside, "收件箱数量", "3 项待整理", 194, 14, 82, 28, {
    size: 10,
    lineHeight: 28,
    color: PALETTE.muted,
    align: "RIGHT"
  });
  addDivider(aside, "收件箱分隔", 16, 50, 260);
  inboxRow(aside, 56, "大模型时代的认知脚手架", "网页", true);
  inboxRow(aside, 124, "学习目标设计清单.md", "文件");
  inboxRow(aside, 192, "阅读方法摘录与待办", "文本");
  hoverButton(aside, "进入收件箱", 16, 272, 260, 34, "进入收件箱并统一整理", {
    fill: PALETTE.white,
    icon: "inbox",
    stroke: PALETTE.border,
    size: 10
  });

  addDivider(aside, "区域分隔", 16, 326, 260);
  addText(aside, "本周研读标题", "本周研读", 16, 344, 160, 26, {
    size: 14,
    lineHeight: 26,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  const stats = [
    ["阅读时长", "4h 26m", "#3370FF"],
    ["新增标注", "18", "#FF9A2E"],
    ["AI 研读", "6", "#7B61FF"]
  ];
  stats.forEach((stat, index) => {
    const statRow = createFrame(aside, `统计 / ${stat[0]}`, 16, 386 + index * 58, 260, 48, PALETTE.white);
    statRow.cornerRadius = 6;
    createRect(statRow, "颜色标记", 0, 8, 3, 32, stat[2], 2);
    addText(statRow, "指标", stat[0], 14, 0, 150, 48, {
      size: 11,
      lineHeight: 48,
      color: PALETTE.text,
      valign: "CENTER"
    });
    addText(statRow, "数值", stat[1], 172, 0, 72, 48, {
      size: 18,
      lineHeight: 48,
      weight: FONTS.semibold,
      color: PALETTE.ink,
      align: "RIGHT",
      valign: "CENTER"
    });
  });

  addDivider(aside, "继续阅读分隔", 16, 574, 260);
  addText(aside, "继续阅读标题", "继续阅读", 16, 590, 140, 26, {
    size: 14,
    lineHeight: 26,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  const continueCard = createFrame(aside, "继续阅读材料", 16, 626, 260, 154, PALETTE.white);
  continueCard.cornerRadius = 6;
  addStroke(continueCard, PALETTE.border);
  createRect(continueCard, "封面色块", 0, 0, 260, 60, PALETTE.blueSoft, 6);
  addText(continueCard, "材料标题", "认知负荷理论与\n学习设计", 14, 76, 232, 52, {
    size: 15,
    lineHeight: 23,
    weight: FONTS.semibold,
    color: PALETTE.ink
  });
  createRect(continueCard, "阅读进度底", 14, 138, 232, 3, PALETTE.border, 2);
  createRect(continueCard, "阅读进度", 14, 138, 152, 3, PALETTE.blue, 2);
  addText(aside, "阅读建议", "继续上次阅读：第 4 / 9 节", 16, 798, 260, 20, {
    size: 10,
    lineHeight: 20,
    color: PALETTE.muted
  });

  return board;
}

async function resolveFonts() {
  const available = await figma.listAvailableFontsAsync();
  const all = available.map((entry) => entry.fontName);

  function pickFamily(candidates) {
    for (const family of candidates) {
      const matches = all.filter((font) => font.family === family);
      if (matches.length) return matches;
    }
    return all.filter((font) => font.family === "Inter");
  }

  function pickStyle(fonts, styles) {
    for (const style of styles) {
      const match = fonts.find((font) => font.style.toLowerCase() === style.toLowerCase());
      if (match) return match;
    }
    return fonts[0];
  }

  const uiFonts = pickFamily(FONT_CANDIDATES.ui);
  const serifFonts = pickFamily(FONT_CANDIDATES.serif);
  const result = {
    regular: pickStyle(uiFonts, ["Regular", "Book", "Normal", "Medium"]),
    medium: pickStyle(uiFonts, ["Medium", "Regular", "Semibold", "Bold"]),
    semibold: pickStyle(uiFonts, ["Semibold", "SemiBold", "Medium", "Bold", "Regular"]),
    serif: pickStyle(serifFonts, ["Regular", "Book", "Normal", "Light"])
  };

  const unique = [];
  Object.keys(result).forEach((key) => {
    if (!unique.some((font) => font.family === result[key].family && font.style === result[key].style)) {
      unique.push(result[key]);
    }
  });
  await Promise.all(unique.map((font) => figma.loadFontAsync(font)));
  return result;
}

async function selectPage(page) {
  if (figma.currentPage === page) return;
  if (typeof figma.setCurrentPageAsync === "function") {
    await figma.setCurrentPageAsync(page);
  } else {
    figma.currentPage = page;
  }
}

async function main() {
  FONTS = await resolveFonts();

  let page = figma.root.children.find((node) => node.type === "PAGE" && node.name === "Mac Prototype");
  if (!page) page = figma.createPage();
  page.name = "Mac Prototype";
  await selectPage(page);
  page.setPluginData("studynotes-mac-prototype", "true");

  for (const node of [...page.children]) {
    if (node.getPluginData("studynotes-mac-generated")) node.remove();
  }

  const reading = buildReadingScreen(page);
  const workspace = buildWorkspaceScreen(page);

  figma.currentPage.selection = [reading];
  figma.viewport.scrollAndZoomIntoView([reading]);
  figma.closePlugin("Mac 原型已生成：阅读标注与知识库工作台，共 2 个可编辑画板。");
}

main().catch((error) => {
  console.error("StudyNotes Mac prototype generation failed:", error);
  figma.notify(`Mac 原型生成失败：${error.message}`, { error: true, timeout: 10000 });
  figma.closePlugin();
});
