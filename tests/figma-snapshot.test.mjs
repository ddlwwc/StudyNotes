import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const scriptPath = resolve("scripts/figma-snapshot.mjs");

const snapshot = {
  schemaVersion: 1,
  source: {
    provider: "figma",
    fileKey: "test-file-key",
    fileName: "Study Notes Test",
    exportedAt: "2026-11-03T00:00:00.000Z"
  },
  stats: {
    pages: 1,
    nodes: 3,
    topLevelScreens: 1,
    interactions: 1
  },
  pages: [
    {
      id: "0:1",
      type: "PAGE",
      name: "Prototype",
      children: [
        {
          id: "4:63",
          type: "FRAME",
          name: "编写与发布",
          visible: true,
          width: 390,
          height: 844,
          children: [
            {
              id: "4:64",
              type: "TEXT",
              name: "标题",
              visible: true,
              characters: "发布一篇文章",
              children: []
            }
          ]
        }
      ]
    }
  ],
  prototype: {
    interactions: [
      {
        pageId: "0:1",
        pageName: "Prototype",
        nodeId: "4:63",
        nodeName: "编写与发布",
        nodeType: "FRAME",
        reactions: [
          {
            trigger: { type: "ON_CLICK" },
            actions: [{ type: "NODE", destinationId: "4:70" }]
          }
        ],
        flowStartingPoints: []
      }
    ]
  },
  assets: {
    screenshots: [
      {
        nodeId: "4:63",
        nodeName: "编写与发布",
        pageId: "0:1",
        pageName: "Prototype",
        width: 390,
        height: 844,
        path: "screenshots/Prototype/编写与发布.png",
        mimeType: "image/png"
      }
    ],
    images: [],
    warnings: []
  }
};

test("reads snapshot JSON and prints a summary", async () => {
  const directory = await mkdtemp(join(tmpdir(), "figma-snapshot-"));
  const file = join(directory, "snapshot.json");

  try {
    await writeFile(file, JSON.stringify(snapshot), "utf8");
    const result = run([file, "summary"]);

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Study Notes Test/);
    assert.match(result.stdout, /页面 1 · 节点 3/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("reads snapshot.json directly from a stored ZIP archive", async () => {
  const directory = await mkdtemp(join(tmpdir(), "figma-snapshot-"));
  const file = join(directory, "snapshot.zip");

  try {
    const archive = createStoredZip([
      {
        path: "snapshot.json",
        data: new TextEncoder().encode(JSON.stringify(snapshot))
      }
    ]);
    await writeFile(file, archive);
    const result = run([file, "screens"]);

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Prototype\t编写与发布\t4:63/);
    assert.match(result.stdout, /screenshots\/Prototype\/编写与发布.png/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("searches text without Figma MCP", async () => {
  const directory = await mkdtemp(join(tmpdir(), "figma-snapshot-"));
  const file = join(directory, "snapshot.json");

  try {
    await writeFile(file, JSON.stringify(snapshot), "utf8");
    const result = run([file, "text", "发布"]);

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Prototype\tPrototype \/ 编写与发布 \/ 标题\t4:64/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

function run(args) {
  return spawnSync(process.execPath, [scriptPath, ...args], {
    cwd: process.cwd(),
    encoding: "utf8"
  });
}

function createStoredZip(files) {
  const encoder = new TextEncoder();
  const localParts = [];
  const centralParts = [];
  const now = new Date(2026, 10, 3, 12, 0, 0);
  const dosTime =
    (now.getHours() << 11) |
    (now.getMinutes() << 5) |
    Math.floor(now.getSeconds() / 2);
  const dosDate =
    ((now.getFullYear() - 1980) << 9) |
    ((now.getMonth() + 1) << 5) |
    now.getDate();
  let offset = 0;

  for (const file of files) {
    const name = encoder.encode(file.path);
    const checksum = crc32(file.data);

    const localHeader = new Uint8Array(30 + name.length);
    const localView = new DataView(localHeader.buffer);
    localView.setUint32(0, 0x04034b50, true);
    localView.setUint16(4, 20, true);
    localView.setUint16(6, 0x0800, true);
    localView.setUint16(8, 0, true);
    localView.setUint16(10, dosTime, true);
    localView.setUint16(12, dosDate, true);
    localView.setUint32(14, checksum, true);
    localView.setUint32(18, file.data.length, true);
    localView.setUint32(22, file.data.length, true);
    localView.setUint16(26, name.length, true);
    localHeader.set(name, 30);
    localParts.push(localHeader, file.data);

    const centralHeader = new Uint8Array(46 + name.length);
    const centralView = new DataView(centralHeader.buffer);
    centralView.setUint32(0, 0x02014b50, true);
    centralView.setUint16(4, 20, true);
    centralView.setUint16(6, 20, true);
    centralView.setUint16(8, 0x0800, true);
    centralView.setUint16(10, 0, true);
    centralView.setUint16(12, dosTime, true);
    centralView.setUint16(14, dosDate, true);
    centralView.setUint32(16, checksum, true);
    centralView.setUint32(20, file.data.length, true);
    centralView.setUint32(24, file.data.length, true);
    centralView.setUint16(28, name.length, true);
    centralView.setUint32(42, offset, true);
    centralHeader.set(name, 46);
    centralParts.push(centralHeader);

    offset += localHeader.length + file.data.length;
  }

  const centralSize = centralParts.reduce(
    (total, part) => total + part.length,
    0
  );
  const endRecord = new Uint8Array(22);
  const endView = new DataView(endRecord.buffer);
  endView.setUint32(0, 0x06054b50, true);
  endView.setUint16(8, files.length, true);
  endView.setUint16(10, files.length, true);
  endView.setUint32(12, centralSize, true);
  endView.setUint32(16, offset, true);

  return concatBytes([...localParts, ...centralParts, endRecord]);
}

function concatBytes(parts) {
  const output = new Uint8Array(
    parts.reduce((total, part) => total + part.length, 0)
  );
  let offset = 0;

  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }

  return output;
}

let crcTable;

function crc32(bytes) {
  if (!crcTable) {
    crcTable = new Uint32Array(256);
    for (let index = 0; index < 256; index += 1) {
      let value = index;
      for (let bit = 0; bit < 8; bit += 1) {
        value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
      }
      crcTable[index] = value >>> 0;
    }
  }

  let value = 0xffffffff;
  for (const byte of bytes) {
    value = crcTable[(value ^ byte) & 0xff] ^ (value >>> 8);
  }
  return (value ^ 0xffffffff) >>> 0;
}
