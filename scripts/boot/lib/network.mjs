import { spawnSync } from "node:child_process";
import { createConnection } from "node:net";

/**
 * @param {number} timeoutMs
 */
export async function waitForInternet(timeoutMs = 120_000) {
  const started = Date.now();
  let attempt = 0;
  while (Date.now() - started < timeoutMs) {
    try {
      const response = await fetch("https://cloudflare.com/cdn-cgi/trace", {
        signal: AbortSignal.timeout(5000),
      });
      if (response.ok) return { ok: true };
    } catch {
      // retry
    }
    await sleep(Math.min(1000 + attempt * 500, 3000));
    attempt += 1;
  }
  return { ok: false, error: "internet_timeout" };
}

/**
 * @param {string} host
 * @param {number} port
 * @param {number} timeoutMs
 */
export function isTcpPortOpen(host, port, timeoutMs = 1500) {
  return new Promise((resolve) => {
    const socket = createConnection({ host, port, timeout: timeoutMs });
    const done = (value) => {
      socket.destroy();
      resolve(value);
    };
    socket.on("connect", () => done(true));
    socket.on("error", () => done(false));
    socket.on("timeout", () => done(false));
  });
}

/**
 * @param {number} timeoutMs
 */
export function isCloudflaredServiceRunning() {
  for (const serviceName of ["Cloudflared", "cloudflared"]) {
    const query = spawnSync("sc", ["query", serviceName], {
      encoding: "utf8",
      timeout: 10_000,
    });
    if (query.status === 0 && /RUNNING|EN COURS/i.test(query.stdout ?? "")) {
      return true;
    }
  }
  return false;
}

/**
 * @param {number} timeoutMs
 */
export async function waitForCloudflaredService(timeoutMs = 45_000) {
  if (isCloudflaredServiceRunning()) {
    return { ok: true };
  }

  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (isCloudflaredServiceRunning()) {
      return { ok: true };
    }
    await sleep(2000);
  }
  return { ok: false, error: "cloudflared_timeout" };
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

export { sleep };
