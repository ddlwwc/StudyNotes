import { spawn } from "node:child_process";
import { access, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const backendDir = path.join(root, "backend");
const venvDir = path.join(backendDir, ".venv");
const python = path.join(venvDir, "bin", "python");
const marker = path.join(venvDir, ".dependencies-installed");

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
  console.log("Creating the StudyNotes backend environment...");
  await run("python3", ["-m", "venv", venvDir], { cwd: root });
}

if (!(await exists(marker))) {
  console.log("Installing StudyNotes backend dependencies...");
  await run(
    python,
    ["-m", "pip", "install", "-r", path.join(backendDir, "requirements.txt")],
    { cwd: root }
  );
  await writeFile(marker, `${new Date().toISOString()}\n`, "utf8");
}
