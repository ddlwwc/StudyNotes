const { RuntimeSupervisor } = require("./runtime.cjs");

let runtime;
let stopping = false;

function send(message) {
  if (process.connected) {
    process.send(message);
  }
}

async function stop() {
  if (stopping) {
    return;
  }

  stopping = true;
  await runtime?.stop();
  process.exit(0);
}

process.on("message", async (message) => {
  if (message?.type === "stop") {
    await stop();
    return;
  }

  if (message?.type !== "start" || runtime || stopping) {
    return;
  }

  try {
    runtime = new RuntimeSupervisor(message.options);
    runtime.on("status", send);
    await runtime.start();
  } catch (error) {
    send({ phase: "error", message: error.stack ?? String(error) });
    await stop();
  }
});

process.on("disconnect", () => void stop());
for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) {
  process.on(signal, () => void stop());
}
