import { startServices, stopServices } from "./services.mjs";

const services = await startServices();

console.log(`StudyNotes web: ${services.webUrl}`);
console.log(`StudyNotes API: ${services.apiUrl}`);

let stopping = false;

async function stop(exitCode = 0) {
  if (stopping) {
    return;
  }

  stopping = true;
  await stopServices(services);
  process.exit(exitCode);
}

process.on("SIGINT", () => void stop());
process.on("SIGTERM", () => void stop());

for (const child of [services.webProcess, services.apiProcess]) {
  child.once("exit", (code) => {
    if (!stopping) {
      console.error("A StudyNotes development service exited unexpectedly.");
      void stop(code ?? 1);
    }
  });
}

await new Promise(() => {});
