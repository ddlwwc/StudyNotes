import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

test("exports a normalized snapshot and streams assets in chunks", async () => {
  const code = await readFile("figma-plugins/local-export/code.js", "utf8");
  const messages = [];
  const pngBytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]);

  const page = {
    id: "0:1",
    type: "PAGE",
    name: "Prototype",
    children: []
  };
  const frame = {
    id: "4:63",
    type: "FRAME",
    name: "编写与发布",
    visible: true,
    x: 10,
    y: 20,
    width: 390,
    height: 844,
    fills: [{ type: "IMAGE", imageHash: "image-hash" }],
    strokes: [],
    reactions: [
      {
        trigger: { type: "ON_CLICK" },
        actions: [{ type: "NODE", destinationId: "4:70" }]
      }
    ],
    flowStartingPoints: [],
    parent: page,
    children: [],
    async exportAsync() {
      return pngBytes;
    }
  };
  const text = {
    id: "4:64",
    type: "TEXT",
    name: "标题",
    visible: true,
    characters: "发布一篇文章",
    width: 200,
    height: 32,
    fills: [],
    strokes: [],
    reactions: [],
    flowStartingPoints: [],
    parent: frame,
    children: []
  };
  frame.children.push(text);
  page.children.push(frame);

  const figma = {
    fileKey: "test-file-key",
    root: {
      name: "Study Notes Test",
      children: [page]
    },
    ui: {
      onmessage: null,
      postMessage(message) {
        messages.push(message);
      }
    },
    showUI() {},
    getImageByHash() {
      return {
        async getBytesAsync() {
          return pngBytes;
        }
      };
    },
    async getLocalPaintStylesAsync() {
      return [];
    },
    async getLocalTextStylesAsync() {
      return [];
    },
    async getLocalEffectStylesAsync() {
      return [];
    },
    async getLocalGridStylesAsync() {
      return [];
    },
    variables: {
      async getLocalVariableCollectionsAsync() {
        return [];
      },
      async getLocalVariablesAsync() {
        return [];
      }
    }
  };

  vm.runInNewContext(code, {
    figma,
    __html__: "<html></html>",
    Date,
    Map,
    Set,
    JSON,
    String,
    Number,
    Math,
    Array,
    Object,
    Error,
    Uint8Array,
    DataView,
    Promise,
    console
  });

  await figma.ui.onmessage({ type: "export" });

  const snapshotJson = messages
    .filter((message) => message.type === "snapshot-chunk")
    .map((message) => message.chunk)
    .join("");
  const snapshot = JSON.parse(snapshotJson);

  assert.equal(snapshot.source.fileKey, "test-file-key");
  assert.equal(snapshot.source.fileName, "Study Notes Test");
  assert.equal(snapshot.stats.pages, 1);
  assert.equal(snapshot.stats.nodes, 3);
  assert.equal(snapshot.stats.topLevelScreens, 1);
  assert.equal(snapshot.stats.interactions, 1);
  assert.equal(snapshot.pages[0].children[0].children[0].characters, "发布一篇文章");
  assert.equal(snapshot.assets.screenshots.length, 1);
  assert.equal(snapshot.assets.images.length, 1);
  assert.equal(snapshot.assets.images[0].imageHash, "image-hash");
  assert.ok(messages.some((message) => message.type === "asset-start"));
  assert.ok(messages.some((message) => message.type === "asset-chunk"));
  assert.ok(messages.some((message) => message.type === "snapshot-end"));
  assert.ok(messages.some((message) => message.type === "complete"));
});
