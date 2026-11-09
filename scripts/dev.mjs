import { fork } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const supervisor = fork(path.join(root, "desktop", "supervisor.cjs"), {
  cwd: root,
  stdio: ["ignore", "inherit", "inherit", "ipc"]
});

let stopping = false;

function stop() {
  if (stopping) {
    return;
  }
  stopping = true;
  if (supervisor.connected) {
    supervisor.send({ type: "stop" });
  }
}

supervisor.on("message", (message) => {
  if (message.phase === "ready") {
    console.log(`StudyNotes web: ${message.webUrl}`);
    console.log(`StudyNotes API: ${message.apiUrl}`);
  } else if (message.phase === "error") {
    console.error(message.message);
    process.exitCode = 1;
    stop();
  }
});

supervisor.on("error", (error) => {
  console.error(error);
  process.exitCode = 1;
});

supervisor.on("exit", (code) => {
  if (!stopping && code !== 0) {
    process.exitCode = code ?? 1;
  }
});

supervisor.send({
  type: "start",
  options: {
    appRoot: root,
    dataDir:
      process.env.STUDY_NOTES_DATA_DIR ?? path.join(root, "data"),
    packaged: false
  }
});

process.on("SIGINT", stop);
process.on("SIGTERM", stop);
