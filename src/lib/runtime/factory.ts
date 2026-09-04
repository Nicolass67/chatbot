import { getEnv } from "@/lib/config/env";
import type { LocalAIRuntime } from "./types";
import { createLmStudioLocalRuntime } from "@/lib/lm-studio/client";

let runtime: LocalAIRuntime | null = null;

export function getLocalAIRuntime(): LocalAIRuntime {
  if (!runtime) {
    const mode = getEnv().RUNTIME_MODE;
    if (mode === "remote") {
      throw new Error(
        "RUNTIME_MODE=remote n'est pas encore implémenté (V2). Utilisez RUNTIME_MODE=local."
      );
    }
    runtime = createLmStudioLocalRuntime();
  }
  return runtime;
}

export function resetLocalAIRuntime(): void {
  runtime = null;
}
