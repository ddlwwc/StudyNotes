import { spawn } from "node:child_process";
import { access, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const backendDir = path.join(root, "backend");
const buildVenv = path.join(backendDir, ".venv-build");
const python = path.join(buildVenv, "bin", "python");

async function exists(filePath) {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { ...options, stdio: "inherit" });
    child.once("error", reject);
    child.once("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code ?? "unknown"}`));
      }
    });
  });
}

if (!(await exists(python))) {
  await run("python3", ["-m", "venv", buildVenv], { cwd: root });
}

await run(
  python,
  [
    "-m",
    "pip",
    "install",
    "-r",
    path.join(backendDir, "requirements.txt"),
    "-r",
    path.join(backendDir, "requirements-build.txt")
  ],
  { cwd: root }
);

await mkdir(path.join(backendDir, "dist"), { recursive: true });
await run(
  python,
  [
    "-m",
    "PyInstaller",
    "--clean",
    "--noconfirm",
    "--onefile",
    "--name",
    "studynotes-api",
    "--distpath",
    path.join(backendDir, "dist"),
    "--workpath",
    path.join(backendDir, "build", "pyinstaller"),
    "--specpath",
    path.join(backendDir, "build", "spec"),
    "--paths",
    backendDir,
    "--collect-all",
    "uvicorn",
    path.join(backendDir, "api_entry.py")
  ],
  { cwd: root }
);

console.log(`StudyNotes backend: ${path.join(backendDir, "dist", "studynotes-api")}`);
