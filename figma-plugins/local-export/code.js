const PLUGIN_NAME = "StudyNotes Local Snapshot";
const SCHEMA_VERSION = 1;
const SCREENSHOT_TYPES = new Set(["FRAME", "COMPONENT", "COMPONENT_SET"]);
const MESSAGE_CHUNK_SIZE = 256 * 1024;

let running = false;

figma.showUI(__html__, {
  width: 440,
  height: 420,
  themeColors: true
});

figma.ui.onmessage = async (message) => {
  if (!message || message.type !== "export") {
    return;
  }

  if (running) {
    post("progress", { message: "导出正在进行中" });
    return;
  }

  running = true;
  try {
    await exportSnapshot();
    post("complete", {});
  } catch (error) {
    post("error", {
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    running = false;
  }
};

async function exportSnapshot() {
  const exportedAt = new Date().toISOString();
  const pages = figma.root.children.filter((node) => node.type === "PAGE");
  const screenshotNodes = [];
  const imageNodeIds = new Map();
  const interactions = [];
  const pageRecords = [];
  const visitedNodeIds = new Set();

  post("progress", {
    message: `读取 ${pages.length} 个页面`,
    current: 0,
    total: pages.length
  });

  for (let pageIndex = 0; pageIndex < pages.length; pageIndex += 1) {
    const page = pages[pageIndex];
    const pageRecord = normalizeNode(page);
    pageRecords.push(pageRecord);

    walkNodes(page, (node) => {
      visitedNodeIds.add(node.id);
      collectNodeImages(node, imageNodeIds);
      collectInteractions(page, node, interactions);

      if (
        node.parent === page &&
        SCREENSHOT_TYPES.has(node.type) &&
        node.visible
      ) {
        screenshotNodes.push({ page, node });
      }
    });

    post("progress", {
      message: `已读取：${page.name}`,
      current: pageIndex + 1,
      total: pages.length
    });
  }

  const snapshot = {
    schemaVersion: SCHEMA_VERSION,
    source: {
      provider: "figma",
      plugin: PLUGIN_NAME,
      fileKey: safeValue(() => figma.fileKey),
      fileName: figma.root.name,
      exportedAt
    },
    stats: {
      pages: pages.length,
      nodes: visitedNodeIds.size,
      topLevelScreens: screenshotNodes.length,
      interactions: interactions.length
    },
    pages: pageRecords,
    prototype: {
      interactions
    },
    styles: await readStyles(),
    variables: await readVariables(),
    assets: {
      screenshots: [],
      images: [],
      warnings: []
    }
  };

  const assetNames = new Set();
  const totalAssets = screenshotNodes.length + imageNodeIds.size;
  let exportedAssets = 0;

  for (const item of screenshotNodes) {
    const filename = uniqueAssetPath(
      assetNames,
      `screenshots/${slug(item.page.name)}/${slug(item.node.name)}.png`
    );

    try {
      const bytes = await item.node.exportAsync({
        format: "PNG",
        constraint: { type: "SCALE", value: 1 }
      });

      snapshot.assets.screenshots.push({
        nodeId: item.node.id,
        nodeName: item.node.name,
        pageId: item.page.id,
        pageName: item.page.name,
        width: item.node.width,
        height: item.node.height,
        path: filename,
        mimeType: "image/png"
      });
      postAsset(filename, bytes);
    } catch (error) {
      snapshot.assets.warnings.push({
        type: "screenshot",
        nodeId: item.node.id,
        nodeName: item.node.name,
        message: errorMessage(error)
      });
    }

    exportedAssets += 1;
    postAssetProgress(exportedAssets, totalAssets, item.node.name);
  }

  for (const [imageHash, nodeIds] of imageNodeIds) {
    try {
      const image = figma.getImageByHash(imageHash);
      if (!image) {
        throw new Error("Figma 未返回对应图片");
      }

      const bytes = await image.getBytesAsync();
      const format = detectImageFormat(bytes);
      const filename = uniqueAssetPath(
        assetNames,
        `images/${slug(imageHash)}.${format.extension}`
      );

      snapshot.assets.images.push({
        imageHash,
        nodeIds,
        path: filename,
        mimeType: format.mimeType
      });
      postAsset(filename, bytes);
    } catch (error) {
      snapshot.assets.warnings.push({
        type: "image",
        imageHash,
        nodeIds,
        message: errorMessage(error)
      });
    }

    exportedAssets += 1;
    postAssetProgress(exportedAssets, totalAssets, imageHash);
  }

  snapshot.assets.exportedCount =
    snapshot.assets.screenshots.length + snapshot.assets.images.length;

  postSnapshot(
    `${slug(figma.root.name || "figma")}-snapshot.json`,
    JSON.stringify(snapshot, null, 2)
  );
}

function normalizeNode(node, depth = 0) {
  const record = {
    id: node.id,
    type: node.type,
    name: node.name,
    depth,
    visible: safeValue(() => node.visible),
    locked: safeValue(() => node.locked),
    x: safeValue(() => node.x),
    y: safeValue(() => node.y),
    width: safeValue(() => node.width),
    height: safeValue(() => node.height),
    rotation: safeValue(() => node.rotation),
    opacity: safeValue(() => node.opacity),
    blendMode: safeValue(() => node.blendMode),
    isMask: safeValue(() => node.isMask),
    fills: safeValue(() => node.fills),
    strokes: safeValue(() => node.strokes),
    strokeWeight: safeValue(() => node.strokeWeight),
    strokeAlign: safeValue(() => node.strokeAlign),
    strokeCap: safeValue(() => node.strokeCap),
    strokeJoin: safeValue(() => node.strokeJoin),
    dashPattern: safeValue(() => node.dashPattern),
    effects: safeValue(() => node.effects),
    effectStyleId: safeValue(() => node.effectStyleId),
    constraints: safeValue(() => node.constraints),
    layoutAlign: safeValue(() => node.layoutAlign),
    layoutGrow: safeValue(() => node.layoutGrow),
    layoutPositioning: safeValue(() => node.layoutPositioning),
    layoutMode: safeValue(() => node.layoutMode),
    itemSpacing: safeValue(() => node.itemSpacing),
    counterAxisSpacing: safeValue(() => node.counterAxisSpacing),
    paddingLeft: safeValue(() => node.paddingLeft),
    paddingRight: safeValue(() => node.paddingRight),
    paddingTop: safeValue(() => node.paddingTop),
    paddingBottom: safeValue(() => node.paddingBottom),
    primaryAxisSizingMode: safeValue(() => node.primaryAxisSizingMode),
    counterAxisSizingMode: safeValue(() => node.counterAxisSizingMode),
    primaryAxisAlignItems: safeValue(() => node.primaryAxisAlignItems),
    counterAxisAlignItems: safeValue(() => node.counterAxisAlignItems),
    clipsContent: safeValue(() => node.clipsContent),
    cornerRadius: safeValue(() => node.cornerRadius),
    topLeftRadius: safeValue(() => node.topLeftRadius),
    topRightRadius: safeValue(() => node.topRightRadius),
    bottomLeftRadius: safeValue(() => node.bottomLeftRadius),
    bottomRightRadius: safeValue(() => node.bottomRightRadius),
    reactions: safeValue(() => node.reactions),
    flowStartingPoints: safeValue(() => node.flowStartingPoints),
    annotations: safeValue(() => node.annotations),
    boundVariables: safeValue(() => node.boundVariables),
    exportSettings: safeValue(() => node.exportSettings)
  };

  addIfPresent(record, "layoutGrids", () => node.layoutGrids);
  addIfPresent(record, "gridRowCount", () => node.gridRowCount);
  addIfPresent(record, "gridColumnCount", () => node.gridColumnCount);
  addIfPresent(record, "characters", () => node.characters);
  addIfPresent(record, "fontName", () => node.fontName);
  addIfPresent(record, "fontSize", () => node.fontSize);
  addIfPresent(record, "lineHeight", () => node.lineHeight);
  addIfPresent(record, "letterSpacing", () => node.letterSpacing);
  addIfPresent(record, "textAlignHorizontal", () => node.textAlignHorizontal);
  addIfPresent(record, "textAlignVertical", () => node.textAlignVertical);
  addIfPresent(record, "textAutoResize", () => node.textAutoResize);
  addIfPresent(record, "textTruncation", () => node.textTruncation);
  addIfPresent(record, "maxLines", () => node.maxLines);
  addIfPresent(record, "textCase", () => node.textCase);
  addIfPresent(record, "hyperlink", () => node.hyperlink);
  addIfPresent(record, "paragraphSpacing", () => node.paragraphSpacing);
  addIfPresent(record, "paragraphIndent", () => node.paragraphIndent);
  addIfPresent(record, "listSpacing", () => node.listSpacing);
  addIfPresent(record, "componentId", () => node.componentId);
  addIfPresent(record, "key", () => node.key);
  addIfPresent(record, "description", () => node.description);
  addIfPresent(record, "componentProperties", () => node.componentProperties);
  addIfPresent(record, "overrides", () => node.overrides);
  addIfPresent(record, "mainComponent", () => {
    const component = node.mainComponent;
    return component
      ? {
          id: component.id,
          name: component.name,
          key: safeValue(() => component.key)
        }
      : null;
  });

  if (node.type === "COMPONENT_SET" || node.type === "COMPONENT") {
    const propertyOwner =
      node.type === "COMPONENT_SET"
        ? node
        : node.parent?.type === "COMPONENT_SET"
          ? node.parent
          : node;

    if (propertyOwner.type === "COMPONENT_SET") {
      addIfPresent(record, "variantGroupProperties", () => propertyOwner.variantGroupProperties);
    }
    addIfPresent(record, "componentPropertyDefinitions", () => propertyOwner.componentPropertyDefinitions);
  }

  if ("children" in node && Array.isArray(node.children)) {
    record.children = node.children.map((child) =>
      normalizeNode(child, depth + 1)
    );
  }

  return record;
}

function addIfPresent(target, key, getter) {
  const value = safeValue(getter);
  if (value !== undefined) {
    target[key] = value;
  }
}

function safeValue(getter) {
  try {
    return getter();
  } catch (_error) {
    return undefined;
  }
}

function walkNodes(root, visitor) {
  visitor(root);
  if ("children" in root && Array.isArray(root.children)) {
    for (const child of root.children) {
      walkNodes(child, visitor);
    }
  }
}

function collectNodeImages(node, imageNodeIds) {
  const paints = [
    ...(Array.isArray(safeValue(() => node.fills)) ? node.fills : []),
    ...(Array.isArray(safeValue(() => node.strokes)) ? node.strokes : [])
  ];

  for (const paint of paints) {
    if (paint && paint.type === "IMAGE" && paint.imageHash) {
      const ids = imageNodeIds.get(paint.imageHash) || [];
      if (!ids.includes(node.id)) {
        ids.push(node.id);
      }
      imageNodeIds.set(paint.imageHash, ids);
    }
  }
}

function collectInteractions(page, node, interactions) {
  const reactions = safeValue(() => node.reactions) || [];
  const flowStartingPoints = safeValue(() => node.flowStartingPoints) || [];

  if (reactions.length === 0 && flowStartingPoints.length === 0) {
    return;
  }

  interactions.push({
    pageId: page.id,
    pageName: page.name,
    nodeId: node.id,
    nodeName: node.name,
    nodeType: node.type,
    reactions,
    flowStartingPoints
  });
}

async function readStyles() {
  const styles = {
    paint: [],
    text: [],
    effect: [],
    grid: []
  };

  if (figma.getLocalPaintStylesAsync) {
    styles.paint = (await figma.getLocalPaintStylesAsync()).map((style) => ({
      id: style.id,
      key: safeValue(() => style.key),
      name: style.name,
      type: style.type,
      remote: style.remote,
      paints: style.paints
    }));
  }

  if (figma.getLocalTextStylesAsync) {
    styles.text = (await figma.getLocalTextStylesAsync()).map((style) => ({
      id: style.id,
      key: safeValue(() => style.key),
      name: style.name,
      type: style.type,
      remote: style.remote,
      fontName: style.fontName,
      fontSize: style.fontSize,
      lineHeight: style.lineHeight,
      letterSpacing: style.letterSpacing,
      textCase: safeValue(() => style.textCase)
    }));
  }

  if (figma.getLocalEffectStylesAsync) {
    styles.effect = (await figma.getLocalEffectStylesAsync()).map((style) => ({
      id: style.id,
      key: safeValue(() => style.key),
      name: style.name,
      type: style.type,
      remote: style.remote,
      effects: style.effects
    }));
  }

  if (figma.getLocalGridStylesAsync) {
    styles.grid = (await figma.getLocalGridStylesAsync()).map((style) => ({
      id: style.id,
      key: safeValue(() => style.key),
      name: style.name,
      type: style.type,
      remote: style.remote,
      layoutGrids: style.layoutGrids
    }));
  }

  return styles;
}

async function readVariables() {
  const variables = {
    collections: [],
    variables: [],
    error: null
  };

  if (
    !figma.variables ||
    !figma.variables.getLocalVariableCollectionsAsync ||
    !figma.variables.getLocalVariablesAsync
  ) {
    return variables;
  }

  try {
    variables.collections = (
      await figma.variables.getLocalVariableCollectionsAsync()
    ).map((collection) => ({
      id: collection.id,
      key: safeValue(() => collection.key),
      name: collection.name,
      modes: collection.modes,
      defaultModeId: collection.defaultModeId,
      variableIds: collection.variableIds
    }));

    variables.variables = (await figma.variables.getLocalVariablesAsync()).map(
      (variable) => ({
        id: variable.id,
        key: safeValue(() => variable.key),
        name: variable.name,
        description: safeValue(() => variable.description),
        resolvedType: variable.resolvedType,
        variableCollectionId: variable.variableCollectionId,
        valuesByMode: variable.valuesByMode,
        scopes: safeValue(() => variable.scopes),
        codeSyntax: safeValue(() => variable.codeSyntax)
      })
    );
  } catch (error) {
    variables.error = errorMessage(error);
  }

  return variables;
}

function postAsset(path, bytes) {
  const base64 = bytesToBase64(bytes);
  post("asset-start", {
    path,
    byteLength: bytes.length
  });

  for (let index = 0; index < base64.length; index += MESSAGE_CHUNK_SIZE) {
    post("asset-chunk", {
      chunk: base64.slice(index, index + MESSAGE_CHUNK_SIZE)
    });
  }

  post("asset-end", {});
}

function postSnapshot(filename, json) {
  post("snapshot-start", {
    filename,
    characterLength: json.length
  });

  for (let index = 0; index < json.length; index += MESSAGE_CHUNK_SIZE) {
    post("snapshot-chunk", {
      chunk: json.slice(index, index + MESSAGE_CHUNK_SIZE)
    });
  }

  post("snapshot-end", {});
}

function postAssetProgress(current, total, label) {
  post("progress", {
    message: `导出资源：${label || "完成"}`,
    current,
    total
  });
}

function post(type, payload) {
  figma.ui.postMessage({
    type,
    ...(payload || {})
  });
}

function slug(value) {
  const normalized = String(value || "untitled")
    .normalize("NFKD")
    .replace(/[^\w\u4e00-\u9fff.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");

  return normalized || "untitled";
}

function uniqueAssetPath(usedPaths, candidate) {
  if (!usedPaths.has(candidate)) {
    usedPaths.add(candidate);
    return candidate;
  }

  const dotIndex = candidate.lastIndexOf(".");
  const base = dotIndex === -1 ? candidate : candidate.slice(0, dotIndex);
  const extension = dotIndex === -1 ? "" : candidate.slice(dotIndex);
  let index = 2;

  while (usedPaths.has(`${base}-${index}${extension}`)) {
    index += 1;
  }

  const path = `${base}-${index}${extension}`;
  usedPaths.add(path);
  return path;
}

function detectImageFormat(bytes) {
  if (isPng(bytes)) {
    return { extension: "png", mimeType: "image/png" };
  }
  if (isJpeg(bytes)) {
    return { extension: "jpg", mimeType: "image/jpeg" };
  }
  if (isGif(bytes)) {
    return { extension: "gif", mimeType: "image/gif" };
  }
  if (isWebp(bytes)) {
    return { extension: "webp", mimeType: "image/webp" };
  }
  return { extension: "bin", mimeType: "application/octet-stream" };
}

function isPng(bytes) {
  return (
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47
  );
}

function isJpeg(bytes) {
  return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

function isGif(bytes) {
  return (
    bytes[0] === 0x47 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x38
  );
}

function isWebp(bytes) {
  return (
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46 &&
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50
  );
}

function bytesToBase64(bytes) {
  const alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let output = "";

  for (let index = 0; index < bytes.length; index += 3) {
    const a = bytes[index];
    const b = index + 1 < bytes.length ? bytes[index + 1] : 0;
    const c = index + 2 < bytes.length ? bytes[index + 2] : 0;
    const triplet = (a << 16) | (b << 8) | c;

    output += alphabet[(triplet >> 18) & 63];
    output += alphabet[(triplet >> 12) & 63];
    output += index + 1 < bytes.length ? alphabet[(triplet >> 6) & 63] : "=";
    output += index + 2 < bytes.length ? alphabet[triplet & 63] : "=";
  }

  return output;
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}
