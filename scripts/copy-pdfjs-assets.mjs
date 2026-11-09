import { cp, copyFile, mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const pdfjsModuleUrl = import.meta.resolve("pdfjs-dist/build/pdf.mjs");
const pdfjsRoot = path.resolve(
  path.dirname(fileURLToPath(pdfjsModuleUrl)),
  ".."
);
const targetRoot = path.join(root, "public", "pdfjs");

await rm(targetRoot, { recursive: true, force: true });
await mkdir(targetRoot, { recursive: true });
await copyFile(
  path.join(pdfjsRoot, "legacy", "build", "pdf.worker.min.mjs"),
  path.join(targetRoot, "pdf.worker.min.mjs")
);
await cp(path.join(pdfjsRoot, "cmaps"), path.join(targetRoot, "cmaps"), {
  recursive: true
});
await cp(
  path.join(pdfjsRoot, "standard_fonts"),
  path.join(targetRoot, "standard_fonts"),
  { recursive: true }
);
