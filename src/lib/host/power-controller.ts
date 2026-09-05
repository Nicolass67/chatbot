import type { PowerController } from "@/lib/runtime/types";
import { scheduleHostPcShutdown } from "@/lib/host/shutdown-pc";

export type PowerActionResult = {
  ok: boolean;
  action: "wake" | "shutdown" | "restart" | "status";
  message: string;
  error?: string;
};

/**
 * Host power facade implementing runtime PowerController.
 * - shutdown/restart: local Windows commands
 * - wake: optional CHATBOT_WAKE_URL (Worker /wake) — no secrets hardcoded
 */
export class HostPowerController implements PowerController {
  constructor(
    private readonly opts: {
      wakeUrl?: string;
      wakeToken?: string;
      fetchImpl?: typeof fetch;
    } = {}
  ) {}

  async wake(): Promise<void> {
    const result = await this.wakePc();
    if (!result.ok) throw new Error(result.message);
  }

  async shutdown(): Promise<void> {
    const result = this.shutdownPc();
    if (!result.ok) throw new Error(result.message);
  }

  async restart(): Promise<void> {
    const result = this.restartPc();
    if (!result.ok) throw new Error(result.message);
  }

  async getPowerStatus(): Promise<"on" | "off" | "unknown"> {
    const fetchImpl = this.opts.fetchImpl ?? fetch;
    const urls = [
      `http://127.0.0.1:${process.env.CHATBOT_SUPERVISOR_PORT || 3927}/health`,
      "http://127.0.0.1:3000/api/health",
    ];
    for (const url of urls) {
      try {
        const ctrl = new AbortController();
        const t = setTimeout(() => ctrl.abort(), 2_000);
        const res = await fetchImpl(url, { signal: ctrl.signal });
        clearTimeout(t);
        if (res.ok || res.status === 503) return "on";
      } catch {
        // try next
      }
    }
    return "unknown";
  }

  shutdownPc(delaySeconds = 60): PowerActionResult {
    const result = scheduleHostPcShutdown(delaySeconds);
    if (!result.ok) {
      return {
        ok: false,
        action: "shutdown",
        message: result.message,
        error: result.error,
      };
    }
    return {
      ok: true,
      action: "shutdown",
      message: result.message,
    };
  }

  restartPc(delaySeconds = 30): PowerActionResult {
    if (process.platform !== "win32") {
      return {
        ok: false,
        action: "restart",
        message: "Redémarrage disponible uniquement sur Windows",
        error: "unsupported_platform",
      };
    }
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { spawn } = require("node:child_process") as typeof import("node:child_process");
      spawn(
        "shutdown.exe",
        ["/r", "/t", String(delaySeconds), "/c", "Chatbot restart"],
        { detached: true, stdio: "ignore", windowsHide: true }
      ).unref();
      return {
        ok: true,
        action: "restart",
        message: `Redémarrage planifié dans ${delaySeconds}s`,
      };
    } catch (e) {
      return {
        ok: false,
        action: "restart",
        message: e instanceof Error ? e.message : String(e),
        error: "spawn_failed",
      };
    }
  }

  async wakePc(): Promise<PowerActionResult> {
    const url = this.opts.wakeUrl ?? process.env.CHATBOT_WAKE_URL;
    if (!url) {
      return {
        ok: false,
        action: "wake",
        message:
          "Wake-on-LAN via Worker (/wake). Configure CHATBOT_WAKE_URL si l’appel local est requis.",
        error: "not_configured",
      };
    }
    const fetchImpl = this.opts.fetchImpl ?? fetch;
    try {
      const headers: Record<string, string> = { Accept: "application/json" };
      const token = this.opts.wakeToken ?? process.env.CHATBOT_WAKE_TOKEN;
      if (token) headers.Authorization = `Bearer ${token}`;
      const res = await fetchImpl(url, { method: "POST", headers });
      if (!res.ok) {
        return {
          ok: false,
          action: "wake",
          message: `Wake échoué (HTTP ${res.status})`,
          error: "wake_http_error",
        };
      }
      return { ok: true, action: "wake", message: "Signal de réveil envoyé" };
    } catch (e) {
      return {
        ok: false,
        action: "wake",
        message: e instanceof Error ? e.message : String(e),
        error: "wake_failed",
      };
    }
  }
}

export function createHostPowerController(): HostPowerController {
  return new HostPowerController();
}
