#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { basename, extname } from "node:path";
import process from "node:process";

const [, , inputPath, command = "summary", ...rest] = process.argv;

if (!inputPath) {
  printUsage();
  process.exitCode = 1;
} else {
  try {
    const source = await readSnapshot(inputPath);
    runCommand(source, command, rest);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}

async function readSnapshot(path) {
  const extension = extname(path).toLowerCase();

  if (extension === ".zip") {
    const archive = await readFile(path);
    const entry = readStoredZipEntry(archive, "snapshot.json");
    return JSON.parse(new TextDecoder().decode(entry));
  }

  return JSON.parse(await readFile(path, "utf8"));
}

function runCommand(snapshot, command, args) {
  switch (command) {
    case "summary":
      printSummary(snapshot);
      break;
    case "pages":
      printPages(snapshot);
      break;
    case "screens":
      printScreens(snapshot);
      break;
    case "interactions":
      printInteractions(snapshot);
      break;
    case "text":
      requireSearchTerm(args);
      printTextMatches(snapshot, args.join(" "));
      break;
    case "find":
      requireSearchTerm(args);
      printNodeMatches(snapshot, args.join(" "));
      break;
    case "node":
      requireSearchTerm(args);
      printNodeDetails(snapshot, args[0]);
      break;
    case "json":
      console.log(JSON.stringify(snapshot, null, 2));
      break;
    default:
      throw new Error(`未知命令：${command}\n\n${usageText()}`);
  }
}

function printSummary(snapshot) {
  const source = snapshot.source ?? {};
  const stats = snapshot.stats ?? {};
  const screenshotCount = snapshot.assets?.screenshots?.length ?? 0;
  const imageCount = snapshot.assets?.images?.length ?? 0;

  console.log(`文件：${source.fileName ?? "(unknown)"}`);
  console.log(`fileKey：${source.fileKey ?? "(unknown)"}`);
  console.log(`导出时间：${source.exportedAt ?? "(unknown)"}`);
  console.log(
    `页面 ${stats.pages ?? 0} · 节点 ${stats.nodes ?? 0} · 顶层画板 ${stats.topLevelScreens ?? 0} · 交互节点 ${stats.interactions ?? 0}`
  );
  console.log(`资源：截图 ${screenshotCount} · 图片 ${imageCount}`);
}

function printPages(snapshot) {
  for (const page of snapshot.pages ?? []) {
    const children = Array.isArray(page.children) ? page.children.length : 0;
    console.log(`${page.name}\t${page.id}\t顶层节点 ${children}`);
  }
}

function printScreens(snapshot) {
  const screenshotsByNode = new Map(
    (snapshot.assets?.screenshots ?? []).map((asset) => [asset.nodeId, asset])
  );
  const frameTypes = new Set(["FRAME", "COMPONENT", "COMPONENT_SET"]);

  for (const page of snapshot.pages ?? []) {
    for (const node of page.children ?? []) {
      if (!frameTypes.has(node.type) || node.visible === false) continue;
      const screenshot = screenshotsByNode.get(node.id);
      const size =
        Number.isFinite(node.width) && Number.isFinite(node.height)
          ? `${node.width}x${node.height}`
          : "?";
      console.log(
        `${page.name}\t${node.name}\t${node.id}\t${size}\t${screenshot?.path ?? "(no screenshot)"}`
      );
    }
  }
}

function printInteractions(snapshot) {
  const interactions = snapshot.prototype?.interactions ?? [];

  if (interactions.length === 0) {
    console.log("没有记录到原型交互。");
    return;
  }

  for (const item of interactions) {
    console.log(`${item.pageName}\t${item.nodeName}\t${item.nodeId}`);

    for (const reaction of item.reactions ?? []) {
      const actions = (reaction.actions ?? [])
        .map((action) => {
          const destination = action.destinationId || action.navigation || action.url;
          return `${action.type}${destination ? ` -> ${destination}` : ""}`;
        })
        .join(", ");
      console.log(`  trigger=${reaction.trigger?.type ?? "UNKNOWN"} ${actions}`);
    }

    for (const flow of item.flowStartingPoints ?? []) {
      console.log(`  flow=${flow.name ?? "(unnamed)"} -> ${flow.nodeId}`);
    }
  }
}

function printTextMatches(snapshot, term) {
  const normalizedTerm = term.toLowerCase();
  let count = 0;

  walkSnapshot(snapshot, ({ node, page, path }) => {
    if (node.type !== "TEXT" || typeof node.characters !== "string") return;
    if (!node.characters.toLowerCase().includes(normalizedTerm)) return;

    count += 1;
    const text = compact(node.characters, 160);
    console.log(`${page.name}\t${path}\t${node.id}\t${text}`);
  });

  if (count === 0) {
    console.log(`没有找到包含“${term}”的文字节点。`);
  }
}

function printNodeMatches(snapshot, term) {
  const normalizedTerm = term.toLowerCase();
  let count = 0;

  walkSnapshot(snapshot, ({ node, page, path }) => {
    if (!String(node.name ?? "").toLowerCase().includes(normalizedTerm)) return;
    count += 1;
    console.log(`${page.name}\t${path}\t${node.type}\t${node.id}`);
  });

  if (count === 0) {
    console.log(`没有找到名称包含“${term}”的节点。`);
  }
}

function printNodeDetails(snapshot, nodeId) {
  const match = findNode(snapshot, nodeId);
  if (!match) {
    throw new Error(`找不到节点：${nodeId}`);
  }
  console.log(JSON.stringify(match.node, null, 2));
}

function findNode(snapshot, nodeId) {
  let match = null;

  for (const page of snapshot.pages ?? []) {
    walkNode(page, (node, path) => {
      if (!match && node.id === nodeId) {
        match = { page, node, path };
      }
    });
  }

  return match;
}

function walkSnapshot(snapshot, visitor) {
  for (const page of snapshot.pages ?? []) {
    walkNode(page, (node, path) => visitor({ node, page, path }));
  }
}

function walkNode(root, visitor, parents = []) {
  const path = [...parents, root.name || root.id].join(" / ");
  visitor(root, path);

  for (const child of root.children ?? []) {
    walkNode(child, visitor, [...parents, root.name || root.id]);
  }
}

function readStoredZipEntry(archive, wantedPath) {
  let offset = 0;

  while (offset + 30 <= archive.length) {
    const signature = readUint32LE(archive, offset);
    if (signature !== 0x04034b50) break;

    const method = readUint16LE(archive, offset + 8);
    const compressedSize = readUint32LE(archive, offset + 18);
    const nameLength = readUint16LE(archive, offset + 26);
    const extraLength = readUint16LE(archive, offset + 28);
    const nameStart = offset + 30;
    const dataStart = nameStart + nameLength + extraLength;
    const dataEnd = dataStart + compressedSize;
    const name = new TextDecoder().decode(
      archive.subarray(nameStart, nameStart + nameLength)
    );

    if (name === wantedPath) {
      if (method !== 0) {
        throw new Error(`ZIP 条目 ${wantedPath} 使用了不支持的压缩方式：${method}`);
      }
      return archive.subarray(dataStart, dataEnd);
    }

    offset = dataEnd;
  }

  throw new Error(`ZIP 中找不到 ${wantedPath}。请确认使用 local-export 插件生成的 ZIP。`);
}

function readUint16LE(buffer, offset) {
  return buffer[offset] | (buffer[offset + 1] << 8);
}

function readUint32LE(buffer, offset) {
  return (
    buffer[offset] |
    (buffer[offset + 1] << 8) |
    (buffer[offset + 2] << 16) |
    (buffer[offset + 3] << 24)
  ) >>> 0;
}

function compact(value, maxLength) {
  const text = String(value).replace(/\s+/g, " ").trim();
  return text.length > maxLength ? `${text.slice(0, maxLength - 1)}…` : text;
}

function requireSearchTerm(args) {
  if (args.length === 0) {
    throw new Error("这个命令需要一个搜索词。");
  }
}

function printUsage() {
  console.error(usageText());
}

function usageText() {
  return [
    `用法：node ${basename(process.argv[1])} <snapshot.json|snapshot.zip> [命令]`,
    "",
    "命令：",
    "  summary                文件、页面、节点与资源统计",
    "  pages                  页面列表",
    "  screens                顶层画板与截图路径",
    "  interactions           原型交互和起点",
    "  text <关键词>          搜索文字内容",
    "  find <关键词>          按节点名称搜索",
    "  node <nodeId>          输出单个节点 JSON",
    "  json                   输出完整 snapshot.json"
  ].join("\n");
}
