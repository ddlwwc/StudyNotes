import { spawn } from "node:child_process";
import { access } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const electronDir = path.join(root, "node_modules", "electron");
const electronExecutable = path.join(
  electronDir,
  "dist",
  "Electron.app",
  "Contents",
  "MacOS",
  "Electron"
);

async function isInstalled() {
  try {
    await access(electronExecutable);
    return true;
  } catch {
    return false;
  }
}

if (await isInstalled()) {
  process.exit(0);
}

const child = spawn(process.execPath, [path.join(electronDir, "install.js")], {
  cwd: electronDir,
  env: {
    ...process.env,
    ELECTRON_MIRROR:
      process.env.ELECTRON_MIRROR ?? "https://npmmirror.com/mirrors/electron/"
  },
  stdio: "inherit"
});

child.once("error", (error) => {
  console.error(error);
  process.exit(1);
});
child.once("exit", (code) => {
  process.exit(code ?? 1);
});
