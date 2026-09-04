#!/usr/bin/env node
import { bootstrapSearxng, stopSearxngStack, printSearxngStatus } from "./lib/searxng-bootstrap.mjs";

const command = process.argv[2] ?? "status";

async function main() {
  switch (command) {
    case "start": {
      const result = await bootstrapSearxng({ fatal: true });
      process.exit(result.ok ? 0 : 1);
      break;
    }
    case "stop": {
      const result = stopSearxngStack();
      process.exit(result.ok ? 0 : 1);
      break;
    }
    case "status": {
      await printSearxngStatus();
      break;
    }
    default:
      console.error(`Commande inconnue: ${command} (start|stop|status)`);
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
