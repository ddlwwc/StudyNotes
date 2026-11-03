const PAGE_NAME = "iOS Prototype";
const PLUGIN_TAG = "studynotes.ios.prototype";
const SCREEN_WIDTH = 390;
const SCREEN_HEIGHT = 844;
const SCREEN_GAP = 72;
const SCREEN_START_X = 80;
const SCREEN_START_Y = 150;

const COLORS = {
  white: "#FFFFFF",
  page: "#F2F3F5",
  nav: "#F7F8FA",
  soft: "#FAFBFC",
  border: "#E5E6EB",
  borderStrong: "#D9DCE2",
  text: "#1F2329",
  textSecondary: "#4E5969",
  muted: "#86909C",
  primary: "#3370FF",
  primarySoft: "#EEF4FF",
  primaryBorder: "#C7D8FF",
  green: "#1F9D61",
  greenSoft: "#EDF9F3",
  amber: "#F6C453",
  amberSoft: "#FFF8E7",
  amberBorder: "#E9C96B",
  black: "#111418"
};

const FONTS = {
  regular: { family: "PingFang SC", style: "Regular" },
  medium: { family: "PingFang SC", style: "Medium" },
  semibold: { family: "PingFang SC", style: "Semibold" },
  bold: { family: "PingFang SC", style: "Bold" }
};

const FALLBACK_FONTS = {
  regular: { family: "Inter", style: "Regular" },
  medium: { family: "Inter", style: "Medium" },
  semibold: { family: "Inter", style: "Semi Bold" },
  bold: { family: "Inter", style: "Bold" }
};

const ICONS = {
  library:
    '<path d="M2 4h6a4 4 0 0 1 4 4v12a3 3 0 0 0-3-3H2z"/><path d="M22 4h-6a4 4 0 0 0-4 4v12a3 3 0 0 1 3-3h7z"/>',
  inbox:
    '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  search:
    '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>',
  review:
    '<path d="M3 12a9 9 0 1 0 2.64-6.36L3 8"/><path d="M3 3v5h5"/>',
  chevronRight: '<path d="m9 18 6-6-6-6"/>',
  chevronLeft: '<path d="m15 18-6-6 6-6"/>',
  more:
    '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  cloudCheck:
    '<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.29a4.5 4.5 0 1 1 0 9Z"/><path d="m9 15 2 2 4-4"/>',
  cloud: '<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.29a4.5 4.5 0 1 1 0 9Z"/>',
  download:
    '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
  sparkles:
    '<path d="m12 3-1.6 4.4L6 9l4.4 1.6L12 15l1.6-4.4L18 9l-4.4-1.6z"/><path d="m5 15-.8 2.2L2 18l2.2.8L5 21l.8-2.2L8 18l-2.2-.8z"/>',
  link:
    '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  image:
    '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>',
  textLines:
    '<path d="M4 6h16M4 12h16M4 18h10"/>',
  folder:
    '<path d="M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  book:
    '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
  clock:
    '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  checkCircle:
    '<circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/>',
  plus:
    '<path d="M12 5v14M5 12h14"/>',
  eyeOff:
    '<path d="m3 3 18 18"/><path d="M10.6 10.6a2 2 0 0 0 2.8 2.8"/><path d="M9.9 4.2A10.8 10.8 0 0 1 12 4c5 0 8.5 4 10 8a13 13 0 0 1-2.1 3.4"/><path d="M6.6 6.6A13.2 13.2 0 0 0 2 12c1.5 4 5 8 10 8a10.8 10.8 0 0 0 4.1-.8"/>',
  external:
    '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>'
};

function rgb(hex) {
  const value = hex.replace("#", "");
  return {
    r: parseInt(value.slice(0, 2), 16) / 255,
    g: parseInt(value.slice(2, 4), 16) / 255,
    b: parseInt(value.slice(4, 6), 16) / 255
  };
}

function paint(hex, opacity) {
  return {
    type: "SOLID",
    color: rgb(hex),
    opacity: opacity === undefined ? 1 : opacity
  };
}

function setFill(node, hex, opacity) {
  node.fills = [paint(hex, opacity)];
}

function setStroke(node, hex, weight, align) {
  node.strokes = [paint(hex)];
  node.strokeWeight = weight === undefined ? 1 : weight;
  node.strokeAlign = align || "INSIDE";
}

function append(parent, node) {
  parent.appendChild(node);
  return node;
}

function createFrame(parent, name, x, y, width, height, fill, radius, clip) {
  const node = figma.createFrame();
  append(parent, node);
  node.name = name;
  node.resize(width, height);
  node.x = x;
  node.y = y;
  node.fills = fill ? [paint(fill)] : [];
  node.cornerRadius = radius || 0;
  node.clipsContent = Boolean(clip);
  return node;
}

function createRect(parent, name, x, y, width, height, fill, radius) {
  const node = figma.createRectangle();
  append(parent, node);
  node.name = name;
  node.resize(width, height);
  node.x = x;
  node.y = y;
  node.fills = fill ? [paint(fill)] : [];
  node.cornerRadius = radius || 0;
  return node;
}

function createEllipse(parent, name, x, y, width, height, fill) {
  const node = figma.createEllipse();
  append(parent, node);
  node.name = name;
  node.resize(width, height);
  node.x = x;
  node.y = y;
  node.fills = fill ? [paint(fill)] : [];
  return node;
}

function createText(parent, name, value, x, y, width, height, options) {
  const config = options || {};
  const node = figma.createText();
  append(parent, node);
  node.name = name;
  node.fontName = FONTS[config.weight || "regular"];
  node.characters = value;
  node.fontSize = config.size || 14;
  node.lineHeight = {
    unit: "PIXELS",
    value: config.lineHeight || Math.round((config.size || 14) * 1.45)
  };
  node.letterSpacing = { unit: "PIXELS", value: config.letterSpacing || 0 };
  node.textAlignHorizontal = config.align || "LEFT";
  node.textAlignVertical = config.valign || "TOP";
  node.textAutoResize = "NONE";
  node.resize(width, height);
  node.x = x;
  node.y = y;
  setFill(node, config.color || COLORS.text);
  return node;
}

function truncateLines(node, maxLines) {
  node.textAutoResize = "HEIGHT";
  node.textTruncation = "ENDING";
  node.maxLines = maxLines;
  return node;
}

function createIcon(parent, name, iconName, x, y, size, color, strokeWidth) {
  const content = ICONS[iconName];
  if (!content) {
    throw new Error("Unknown icon: " + iconName);
  }
  const svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" ' +
    'fill="none" stroke="' +
    color +
    '" stroke-width="' +
    (strokeWidth || 1.8) +
    '" stroke-linecap="round" stroke-linejoin="round">' +
    content +
    "</svg>";
  const node = figma.createNodeFromSvg(svg);
  append(parent, node);
  node.name = name;
  node.resize(size, size);
  node.x = x;
  node.y = y;
  return node;
}

function createDivider(parent, x, y, width, color) {
  return createRect(parent, "分隔线", x, y, width, 1, color || COLORS.border, 0);
}

function createPill(parent, name, x, y, width, height, label, options) {
  const config = options || {};
  const pill = createFrame(
    parent,
    name,
    x,
    y,
    width,
    height,
    config.fill || COLORS.nav,
    config.radius === undefined ? 8 : config.radius,
    true
  );
  if (config.border) {
    setStroke(pill, config.border, 1, "INSIDE");
  }
  let labelX = config.dot ? 20 : 8;
  if (config.icon) {
    createIcon(
      pill,
      "状态图标",
      config.icon,
      8,
      Math.round((height - (config.iconSize || 14)) / 2),
      config.iconSize || 14,
      config.iconColor || config.color || COLORS.textSecondary,
      1.8
    );
    labelX = 8 + (config.iconSize || 14) + 5;
  }
  if (config.dot) {
    createEllipse(
      pill,
      "状态圆点",
      config.dotX === undefined ? 9 : config.dotX,
      Math.round(height / 2) - 3,
      6,
      6,
      config.dotColor || COLORS.green
    );
  }
  createText(
    pill,
    "状态文字",
    label,
    labelX,
    0,
    width - labelX - 6,
    height,
    {
      weight: config.weight || "medium",
      size: config.size || 10.5,
      lineHeight: height,
      color: config.color || COLORS.textSecondary,
      align: config.align || "LEFT",
      valign: "CENTER"
    }
  );
  return pill;
}

function createButton(parent, name, x, y, width, height, label, variant, iconName) {
  const isPrimary = variant === "primary";
  const isSoft = variant === "soft";
  const fill = isPrimary ? COLORS.primary : isSoft ? COLORS.primarySoft : COLORS.white;
  const textColor = isPrimary ? COLORS.white : COLORS.primary;
  const border = isPrimary ? null : isSoft ? null : COLORS.primaryBorder;
  const button = createFrame(parent, name, x, y, width, height, fill, 8, true);
  if (border) {
    setStroke(button, border, 1, "INSIDE");
  }
  const iconSize = 15;
  const hasIcon = Boolean(iconName);
  const textX = hasIcon ? 28 : 8;
  if (hasIcon) {
    createIcon(button, "按钮图标", iconName, 11, (height - iconSize) / 2, iconSize, textColor, 1.9);
  }
  createText(
    button,
    "按钮文字",
    label,
    textX,
    0,
    width - textX - 8,
    height,
    {
      weight: "medium",
      size: 12,
      lineHeight: height,
      color: textColor,
      align: hasIcon ? "LEFT" : "CENTER",
      valign: "CENTER"
    }
  );
  return button;
}

async function loadFonts() {
  const loaded = {};
  const keys = Object.keys(FONTS);
  for (const key of keys) {
    const preferred = FONTS[key];
    try {
      await figma.loadFontAsync(preferred);
      loaded[key] = preferred;
    } catch (error) {
      const fallback = FALLBACK_FONTS[key];
      await figma.loadFontAsync(fallback);
      loaded[key] = fallback;
    }
  }
  Object.keys(loaded).forEach((key) => {
    FONTS[key] = loaded[key];
  });
}

function createStatusBar(screen) {
  const bar = createFrame(screen, "iOS 状态栏", 0, 0, SCREEN_WIDTH, 44, COLORS.white, 0, false);
  createText(bar, "时间", "9:41", 22, 12, 52, 20, {
    weight: "semibold",
    size: 13,
    lineHeight: 18,
    color: COLORS.black
  });

  const signal = createFrame(bar, "蜂窝信号", 311, 16, 18, 12, null, 0, false);
  [3, 5, 7, 9].forEach((height, index) => {
    createRect(
      signal,
      "信号柱 " + (index + 1),
      index * 4,
      12 - height,
      2.5,
      height,
      COLORS.black,
      1
    );
  });
  createIcon(bar, "Wi-Fi", "link", 337, 13, 14, COLORS.black, 2.1);
  const battery = createFrame(bar, "电池", 356, 14, 18, 10, null, 0, false);
  const shell = createRect(battery, "电池外壳", 0, 0, 17, 10, null, 2);
  setStroke(shell, COLORS.black, 1, "INSIDE");
  createRect(battery, "电量", 2, 2, 12, 6, COLORS.black, 1);
  createRect(battery, "电极", 18, 3.5, 1.5, 3, COLORS.black, 0);
  return bar;
}

function createHomeIndicator(screen) {
  return createRect(screen, "Home Indicator", 128, 832, 134, 5, COLORS.black, 3);
}

function createBottomNavigation(screen, active) {
  const nav = createFrame(screen, "底部四入口", 0, 772, SCREEN_WIDTH, 72, COLORS.nav, 0, true);
  createRect(nav, "顶部分隔线", 0, 0, SCREEN_WIDTH, 1, COLORS.border, 0);

  const items = [
    { id: "资料库", label: "资料库", icon: "library" },
    { id: "收件箱", label: "收件箱", icon: "inbox" },
    { id: "搜索", label: "搜索", icon: "search" },
    { id: "复习", label: "复习", icon: "review" }
  ];

  items.forEach((item, index) => {
    const selected = item.id === active;
    const color = selected ? COLORS.primary : COLORS.muted;
    const tab = createFrame(
      nav,
      (selected ? "当前 · " : "") + item.label,
      index * 97.5,
      0,
      97.5,
      66,
      null,
      0,
      true
    );
    if (selected) {
      createRect(tab, "选中指示条", 35.75, 0, 26, 2, COLORS.primary, 1);
    }
    createIcon(tab, item.label + "图标", item.icon, 37.75, 11, 22, color, selected ? 2 : 1.8);
    createText(tab, item.label + "文字", item.label, 0, 38, 97.5, 18, {
      weight: selected ? "semibold" : "medium",
      size: 10.5,
      lineHeight: 16,
      color,
      align: "CENTER"
    });
  });

  createHomeIndicator(screen);
  return nav;
}

function createScreenCard(parent, name, x, y, width, height, fill) {
  const card = createFrame(parent, name, x, y, width, height, fill || COLORS.white, 8, true);
  setStroke(card, COLORS.border, 1, "INSIDE");
  return card;
}

function createHeader(screen, title, subtitle, rightMode) {
  const header = createFrame(screen, "页面头部", 0, 44, SCREEN_WIDTH, 88, COLORS.white, 0, true);
  createText(header, "页面标题", title, 20, 7, 250, 38, {
    weight: "semibold",
    size: 27,
    lineHeight: 34,
    color: COLORS.text
  });
  if (subtitle) {
    createText(header, "页面副标题", subtitle, 20, 43, 300, 20, {
      weight: "regular",
      size: 11.5,
      lineHeight: 18,
      color: COLORS.muted
    });
  }
  if (rightMode === "avatar") {
    const avatar = createFrame(header, "个人资料入口", 344, 10, 30, 30, COLORS.primarySoft, 15, true);
    createText(avatar, "头像文字", "SN", 0, 0, 30, 30, {
      weight: "semibold",
      size: 10,
      lineHeight: 30,
      color: COLORS.primary,
      align: "CENTER",
      valign: "CENTER"
    });
  }
  createDivider(header, 0, 87, SCREEN_WIDTH, COLORS.border);
  return header;
}

function createHomeScreen() {
  const screen = createFrame(
    figma.currentPage,
    "iOS Prototype / 01 资料库首页",
    SCREEN_START_X,
    SCREEN_START_Y,
    SCREEN_WIDTH,
    SCREEN_HEIGHT,
    COLORS.white,
    28,
    true
  );
  setStroke(screen, COLORS.borderStrong, 1, "INSIDE");
  screen.setPluginData(PLUGIN_TAG, "1");
  createStatusBar(screen);
  const header = createHeader(screen, "资料库", null, "avatar");

  createPill(header, "iCloud 同步状态", 20, 47, 164, 26, "iCloud 已同步 · 刚刚", {
    fill: COLORS.greenSoft,
    dot: true,
    dotColor: COLORS.green,
    color: COLORS.green,
    weight: "medium"
  });

  const body = createFrame(screen, "内容区 / 资料库", 0, 132, SCREEN_WIDTH, 640, COLORS.white, 0, true);
  createText(body, "区块标题 / 最近阅读", "最近阅读", 18, 17, 120, 24, {
    weight: "semibold",
    size: 16,
    lineHeight: 22
  });
  createText(body, "查看更多", "查看全部", 308, 19, 64, 20, {
    weight: "medium",
    size: 11,
    lineHeight: 18,
    color: COLORS.primary,
    align: "RIGHT"
  });

  const recent = createScreenCard(body, "最近阅读 / 认知负荷理论", 16, 50, 358, 116, COLORS.white);
  const cover = createFrame(recent, "材料封面", 14, 16, 66, 84, COLORS.primarySoft, 8, true);
  createIcon(cover, "文档图标", "book", 23, 24, 20, COLORS.primary, 1.8);
  createText(cover, "阅读进度", "72%", 0, 57, 66, 17, {
    weight: "semibold",
    size: 10,
    lineHeight: 15,
    color: COLORS.primary,
    align: "CENTER"
  });
  createPill(recent, "离线状态", 280, 14, 62, 22, "已离线", {
    fill: COLORS.greenSoft,
    icon: "checkCircle",
    iconSize: 12,
    iconColor: COLORS.green,
    color: COLORS.green,
    size: 9.5
  });
  const recentTitle = createText(recent, "材料标题", "认知负荷理论与学习设计", 94, 16, 182, 44, {
    weight: "semibold",
    size: 15.5,
    lineHeight: 22,
    color: COLORS.text
  });
  truncateLines(recentTitle, 2);
  const recentMeta = createText(recent, "材料信息", "网页文章 · 18 分钟", 94, 66, 160, 18, {
    weight: "regular",
    size: 10.5,
    lineHeight: 16,
    color: COLORS.muted
  });
  truncateLines(recentMeta, 1);
  createIcon(recent, "继续阅读", "chevronRight", 327, 49, 17, COLORS.muted, 1.8);
  createPill(recent, "研读层数量", 217, 66, 50, 20, "标注 7", {
    fill: COLORS.nav,
    color: COLORS.textSecondary,
    size: 9.5
  });

  createText(body, "区块标题 / 知识库", "知识库", 18, 185, 120, 24, {
    weight: "semibold",
    size: 16,
    lineHeight: 22
  });
  createPill(body, "新建知识库入口", 302, 181, 70, 26, "新建", {
    fill: COLORS.primarySoft,
    icon: "plus",
    iconSize: 12,
    iconColor: COLORS.primary,
    color: COLORS.primary,
    size: 10
  });

  const libraries = [
    {
      name: "学习科学",
      detail: "12 份材料 · 4 个文件夹",
      status: "已同步",
      color: COLORS.primary
    },
    {
      name: "产品设计",
      detail: "8 份材料 · 2 个文件夹",
      status: "已同步",
      color: COLORS.primary
    },
    {
      name: "编程与系统",
      detail: "21 份材料 · 3 项按需下载",
      status: "按需下载",
      color: COLORS.primary
    }
  ];

  libraries.forEach((item, index) => {
    const row = createScreenCard(body, "知识库 / " + item.name, 16, 220 + index * 62, 358, 52, COLORS.white);
    const iconTile = createFrame(row, "知识库图标底", 10, 9, 32, 32, COLORS.primarySoft, 7, true);
    createIcon(iconTile, "知识库图标", "folder", 7, 7, 18, item.color, 1.8);
    const libraryName = createText(row, "知识库名称", item.name, 52, 8, 160, 20, {
      weight: "semibold",
      size: 13,
      lineHeight: 18
    });
    truncateLines(libraryName, 1);
    const libraryDetail = createText(row, "知识库摘要", item.detail, 52, 27, 215, 16, {
      weight: "regular",
      size: 9.5,
      lineHeight: 14,
      color: COLORS.muted
    });
    truncateLines(libraryDetail, 1);
    if (item.status === "按需下载") {
      createPill(row, "按需下载状态", 247, 15, 74, 22, "按需下载", {
        fill: COLORS.nav,
        icon: "cloud",
        iconSize: 11,
        iconColor: COLORS.textSecondary,
        color: COLORS.textSecondary,
        size: 8.5
      });
    } else {
      createText(row, "同步状态", item.status, 255, 18, 58, 16, {
        weight: "regular",
        size: 9,
        lineHeight: 15,
        color: COLORS.green,
        align: "RIGHT"
      });
    }
    createIcon(row, "进入知识库", "chevronRight", 332, 17, 16, COLORS.muted, 1.8);
  });

  const storage = createFrame(body, "iCloud 存储说明", 16, 420, 358, 76, COLORS.nav, 8, true);
  createPill(storage, "同步状态", 12, 12, 96, 24, "iCloud 已同步", {
    fill: COLORS.white,
    dot: true,
    dotColor: COLORS.green,
    color: COLORS.green,
    size: 9.5
  });
  createText(storage, "存储说明标题", "目录与元数据已同步", 120, 15, 210, 20, {
    weight: "medium",
    size: 11.5,
    lineHeight: 17,
    color: COLORS.textSecondary
  });
  createText(storage, "存储空间说明", "正文按需下载 · iCloud 可用 4.2 GB", 12, 45, 300, 18, {
    weight: "regular",
    size: 10,
    lineHeight: 16,
    color: COLORS.muted
  });

  createBottomNavigation(screen, "资料库");
  return screen;
}

function createReadingScreen() {
  const screen = createFrame(
    figma.currentPage,
    "iOS Prototype / 02 阅读与轻量标注",
    SCREEN_START_X + SCREEN_WIDTH + SCREEN_GAP,
    SCREEN_START_Y,
    SCREEN_WIDTH,
    SCREEN_HEIGHT,
    COLORS.white,
    28,
    true
  );
  setStroke(screen, COLORS.borderStrong, 1, "INSIDE");
  screen.setPluginData(PLUGIN_TAG, "1");
  createStatusBar(screen);

  const header = createFrame(screen, "阅读页头部", 0, 44, SCREEN_WIDTH, 48, COLORS.white, 0, false);
  createIcon(header, "返回资料库", "chevronLeft", 17, 10, 22, COLORS.text, 2);
  createText(header, "所在位置", "学习科学 / 认知心理学", 49, 15, 220, 18, {
    weight: "medium",
    size: 11,
    lineHeight: 16,
    color: COLORS.muted
  });
  createIcon(header, "更多操作", "more", 348, 10, 22, COLORS.textSecondary, 2.1);
  createDivider(screen, 0, 91, SCREEN_WIDTH, COLORS.border);

  const reading = createFrame(screen, "阅读内容", 0, 92, SCREEN_WIDTH, 680, COLORS.white, 0, true);
  createText(reading, "材料标题", "认知负荷理论与学习设计", 20, 12, 345, 64, {
    weight: "semibold",
    size: 24,
    lineHeight: 32,
    color: COLORS.text
  });
  createText(reading, "材料元信息", "网页文章 · 约 18 分钟", 20, 76, 190, 18, {
    weight: "regular",
    size: 10.5,
    lineHeight: 16,
    color: COLORS.muted
  });
  createPill(reading, "下载状态", 294, 72, 76, 24, "已离线", {
    fill: COLORS.greenSoft,
    icon: "checkCircle",
    iconSize: 12,
    iconColor: COLORS.green,
    color: COLORS.green,
    size: 9.5
  });
  createDivider(reading, 20, 106, 350, COLORS.border);

  createText(
    reading,
    "正文第一段",
    "认知负荷理论关注工作记忆在学习过程中的限制。教学设计的核心，是把有限的认知资源引向图式构建。",
    20,
    122,
    350,
    54,
    {
      weight: "regular",
      size: 14,
      lineHeight: 25,
      color: COLORS.textSecondary
    }
  );
  createText(
    reading,
    "正文第二段",
    "内在负荷来自材料本身的复杂度；外在负荷则由不恰当的呈现方式产生。",
    20,
    182,
    350,
    46,
    {
      weight: "regular",
      size: 14,
      lineHeight: 24,
      color: COLORS.textSecondary
    }
  );

  const highlight = createFrame(reading, "文字标注 / 03", 20, 234, 350, 62, COLORS.amberSoft, 6, true);
  createRect(highlight, "标注锚点", 0, 0, 3, 62, COLORS.amber, 0);
  createText(highlight, "锚点编号", "03", 10, 5, 24, 16, {
    weight: "semibold",
    size: 9,
    lineHeight: 14,
    color: "#8B6B14"
  });
  createText(
    highlight,
    "高亮文字",
    "有效设计应降低无关负荷，并为生成性加工留出空间。",
    12,
    20,
    326,
    38,
    {
      weight: "medium",
      size: 13.5,
      lineHeight: 22,
      color: COLORS.text
    }
  );

  createText(
    reading,
    "正文第三段",
    "因此，图文整合、分段呈现与及时反馈需要共同服务于概念之间的关系，而不是停留在视觉层面的整齐。",
    20,
    312,
    350,
    54,
    {
      weight: "regular",
      size: 13.5,
      lineHeight: 24,
      color: COLORS.textSecondary
    }
  );
  createText(
    reading,
    "正文第四段",
    "理解三种负荷的作用机制，有助于在学习设计中做出更合理的取舍。",
    20,
    379,
    350,
    28,
    {
      weight: "regular",
      size: 13.5,
      lineHeight: 23,
      color: COLORS.textSecondary
    }
  );

  const annotation = createScreenCard(reading, "轻量标注浮层", 12, 424, 366, 240, COLORS.white);
  const annotationHeader = createFrame(
    annotation,
    "标注浮层头部",
    0,
    0,
    366,
    42,
    COLORS.white,
    0,
    true
  );
  createDivider(annotationHeader, 0, 41, 366, COLORS.border);
  createText(annotationHeader, "浮层标题", "轻量标注", 14, 11, 90, 20, {
    weight: "semibold",
    size: 13,
    lineHeight: 18
  });
  createPill(annotationHeader, "私人可见", 88, 9, 72, 24, "仅自己可见", {
    fill: COLORS.nav,
    icon: "eyeOff",
    iconSize: 11,
    iconColor: COLORS.muted,
    color: COLORS.muted,
    size: 8.5
  });
  createText(annotationHeader, "关闭浮层", "完成", 305, 12, 44, 18, {
    weight: "medium",
    size: 10.5,
    lineHeight: 16,
    color: COLORS.primary,
    align: "RIGHT"
  });

  createText(annotation, "标注说明", "高亮文字已锚定原文位置，编辑后会在 iCloud 同步。", 14, 53, 336, 18, {
    weight: "regular",
    size: 9.5,
    lineHeight: 15,
    color: COLORS.muted
  });
  const noteField = createFrame(annotation, "标注内容输入框", 14, 78, 338, 64, COLORS.nav, 8, true);
  setStroke(noteField, COLORS.border, 1, "INSIDE");
  createText(
    noteField,
    "标注内容",
    "关键不只是删减内容，而是让注意力进入关系建构。",
    12,
    10,
    314,
    42,
    {
      weight: "regular",
      size: 11.5,
      lineHeight: 18,
      color: COLORS.textSecondary
    }
  );
  createButton(annotation, "AI 解释选中内容", 14, 151, 186, 40, "AI 解释选中内容", "soft", "sparkles");
  createButton(annotation, "加入复习", 208, 151, 144, 40, "加入复习", "outline", "review");
  createText(annotation, "AI 上下文范围", "按需触发 · 仅发送选中文字", 14, 201, 188, 17, {
    weight: "regular",
    size: 9,
    lineHeight: 14,
    color: COLORS.muted
  });
  createPill(annotation, "AI 供应商", 245, 197, 107, 24, "DeepSeek", {
    fill: COLORS.nav,
    icon: "sparkles",
    iconSize: 10,
    iconColor: COLORS.primary,
    color: COLORS.primary,
    size: 9
  });

  createBottomNavigation(screen, "资料库");
  return screen;
}

function createInboxItem(parent, index, data) {
  const item = createScreenCard(
    parent,
    "收件箱项目 / " + data.title,
    16,
    200 + index * 86,
    358,
    74,
    COLORS.white
  );
  const tile = createFrame(item, "来源图标底", 12, 15, 42, 42, data.fill, 8, true);
  createIcon(tile, "来源图标", data.icon, 11, 11, 20, data.color, 1.8);
  const inboxTitle = createText(item, "收集标题", data.title, 66, 9, 224, 22, {
    weight: "semibold",
    size: 12.5,
    lineHeight: 18,
    color: COLORS.text
  });
  truncateLines(inboxTitle, 1);
  const inboxMeta = createText(item, "来源与时间", data.meta, 66, 31, 210, 17, {
    weight: "regular",
    size: 9.5,
    lineHeight: 15,
    color: COLORS.muted
  });
  truncateLines(inboxMeta, 1);
  createIcon(item, "项目更多操作", "chevronRight", 327, 27, 17, COLORS.muted, 1.8);
  createPill(item, "同步状态", 266, 31, 56, 20, data.status, {
    fill: data.status === "待同步" ? COLORS.amberSoft : COLORS.greenSoft,
    color: data.status === "待同步" ? "#8B6B14" : COLORS.green,
    size: 8,
    align: "CENTER"
  });
  return item;
}

function createInboxScreen() {
  const screen = createFrame(
    figma.currentPage,
    "iOS Prototype / 03 收件箱快速收集",
    SCREEN_START_X + (SCREEN_WIDTH + SCREEN_GAP) * 2,
    SCREEN_START_Y,
    SCREEN_WIDTH,
    SCREEN_HEIGHT,
    COLORS.white,
    28,
    true
  );
  setStroke(screen, COLORS.borderStrong, 1, "INSIDE");
  screen.setPluginData(PLUGIN_TAG, "1");
  createStatusBar(screen);
  const header = createHeader(screen, "收件箱", null, "avatar");

  createPill(header, "收件箱数量", 102, 12, 42, 26, "3 项", {
    fill: COLORS.primarySoft,
    color: COLORS.primary,
    size: 9.5,
    align: "CENTER"
  });
  createPill(header, "iCloud 收件箱状态", 20, 47, 178, 26, "iCloud 收件箱 · 就绪", {
    fill: COLORS.greenSoft,
    dot: true,
    dotColor: COLORS.green,
    color: COLORS.green,
    size: 9.5
  });

  const body = createFrame(screen, "内容区 / 收件箱", 0, 132, SCREEN_WIDTH, 640, COLORS.white, 0, true);
  createText(body, "区块标题 / 快速收集", "快速收集", 18, 17, 120, 24, {
    weight: "semibold",
    size: 16,
    lineHeight: 22
  });
  createText(body, "收集说明", "写入 iCloud，回 Mac 统一整理", 154, 20, 218, 18, {
    weight: "regular",
    size: 9.5,
    lineHeight: 15,
    color: COLORS.muted,
    align: "RIGHT"
  });

  const quickActions = [
    { label: "链接", hint: "抓取网页", icon: "link" },
    { label: "图片", hint: "保存截图", icon: "image" },
    { label: "文本", hint: "粘贴片段", icon: "textLines" }
  ];
  quickActions.forEach((action, index) => {
    const x = 16 + index * 121;
    const card = createScreenCard(body, "快速收集 / " + action.label, x, 52, 116, 76, COLORS.white);
    const tile = createFrame(card, "动作图标底", 10, 10, 30, 30, COLORS.primarySoft, 7, true);
    createIcon(tile, "动作图标", action.icon, 7, 7, 16, COLORS.primary, 1.8);
    createText(card, "动作名称", action.label, 48, 11, 54, 20, {
      weight: "semibold",
      size: 13,
      lineHeight: 18
    });
    createText(card, "动作说明", action.hint, 10, 49, 92, 16, {
      weight: "regular",
      size: 9,
      lineHeight: 14,
      color: COLORS.muted
    });
  });

  createText(body, "区块标题 / 等待整理", "等待整理", 18, 148, 120, 24, {
    weight: "semibold",
    size: 16,
    lineHeight: 22
  });
  createPill(body, "全部项目筛选", 248, 145, 58, 24, "全部 3", {
    fill: COLORS.primarySoft,
    color: COLORS.primary,
    size: 9,
    align: "CENTER"
  });
  createPill(body, "待同步筛选", 312, 145, 60, 24, "待同步 1", {
    fill: COLORS.nav,
    color: COLORS.textSecondary,
    size: 8.5,
    align: "CENTER"
  });

  createInboxItem(body, 0, {
    title: "从复杂到清晰：知识组织的四个原则",
    meta: "网页链接 · 来自 iOS · 今天 10:42",
    status: "待同步",
    icon: "link",
    color: COLORS.primary,
    fill: COLORS.primarySoft
  });
  createInboxItem(body, 1, {
    title: "学习方法章节截图",
    meta: "图片 · 2.4 MB · 今天 09:18",
    status: "已同步",
    icon: "image",
    color: COLORS.green,
    fill: COLORS.greenSoft
  });
  createInboxItem(body, 2, {
    title: "间隔重复的三个关键变量",
    meta: "文本片段 · 来自 Mac · 昨天",
    status: "已同步",
    icon: "textLines",
    color: COLORS.primary,
    fill: COLORS.primarySoft
  });

  const info = createFrame(body, "整理范围说明", 16, 466, 358, 86, COLORS.nav, 8, true);
  createIcon(info, "知识库图标", "folder", 14, 17, 20, COLORS.primary, 1.8);
  createText(info, "说明标题", "收件箱只负责轻量收集", 44, 14, 230, 20, {
    weight: "semibold",
    size: 11.5,
    lineHeight: 17
  });
  createText(
    info,
    "说明正文",
    "知识库选择、文件夹移动与标签整理请回到 Mac 完成。",
    14,
    44,
    326,
    28,
    {
      weight: "regular",
      size: 10,
      lineHeight: 16,
      color: COLORS.muted
    }
  );
  createPill(info, "按需下载说明", 246, 14, 98, 22, "按需下载", {
    fill: COLORS.white,
    icon: "cloud",
    iconSize: 11,
    iconColor: COLORS.textSecondary,
    color: COLORS.textSecondary,
    size: 8.5
  });

  createBottomNavigation(screen, "收件箱");
  return screen;
}

async function findOrCreatePage() {
  const existing = figma.root.children.find((node) => node.type === "PAGE" && node.name === PAGE_NAME);
  const page = existing || figma.createPage();
  page.name = PAGE_NAME;
  if (figma.setCurrentPageAsync) {
    await figma.setCurrentPageAsync(page);
  } else {
    figma.currentPage = page;
  }
  page.backgrounds = [paint(COLORS.page)];
  return page;
}

function cleanPreviousOutput(page) {
  const nodes = page.children.slice();
  for (const node of nodes) {
    const isTagged = node.getPluginData(PLUGIN_TAG) === "1";
    const isGeneratedName =
      node.name === "StudyNotes / iOS 原型" ||
      node.name === "StudyNotes / iOS 原型说明" ||
      node.name.indexOf("iOS 原型 / ") === 0;
    if (isTagged || isGeneratedName) {
      node.remove();
    }
  }
}

function createPageHeading() {
  const title = createText(
    figma.currentPage,
    "StudyNotes / iOS 原型",
    "StudyNotes / iOS",
    SCREEN_START_X,
    26,
    520,
    42,
    {
      weight: "semibold",
      size: 30,
      lineHeight: 38,
      color: COLORS.text
    }
  );
  title.setPluginData(PLUGIN_TAG, "1");

  const description = createText(
    figma.currentPage,
    "StudyNotes / iOS 原型说明",
    "轻量收集 · 按需离线 · 轻标注 · AI 显式触发",
    SCREEN_START_X,
    72,
    680,
    24,
    {
      weight: "regular",
      size: 13,
      lineHeight: 20,
      color: COLORS.textSecondary
    }
  );
  description.setPluginData(PLUGIN_TAG, "1");

  const labels = ["01 · 资料库首页", "02 · 阅读与轻量标注", "03 · 收件箱快速收集"];
  labels.forEach((label, index) => {
    const node = createText(
      figma.currentPage,
      "iOS 原型 / " + label,
      label,
      SCREEN_START_X + index * (SCREEN_WIDTH + SCREEN_GAP),
      112,
      SCREEN_WIDTH,
      22,
      {
        weight: "medium",
        size: 12,
        lineHeight: 18,
        color: COLORS.textSecondary
      }
    );
    node.setPluginData(PLUGIN_TAG, "1");
  });
}

async function main() {
  await loadFonts();
  const page = await findOrCreatePage();
  cleanPreviousOutput(page);
  createPageHeading();
  const screens = [createHomeScreen(), createReadingScreen(), createInboxScreen()];
  figma.currentPage.selection = screens;
  figma.viewport.scrollAndZoomIntoView(screens);
  figma.notify("iOS Prototype：3 个可编辑画板已生成");
  figma.closePlugin();
}

main().catch((error) => {
  console.error(error);
  figma.notify("iOS Prototype 生成失败：" + error.message, { error: true, timeout: 10000 });
  figma.closePlugin();
});
