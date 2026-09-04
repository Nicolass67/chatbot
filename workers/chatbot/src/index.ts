import { probeFreeboxReachability } from "./freebox-probe";
import {
  handleBootRequestConsume,
  handleBootRequestGet,
} from "./boot-request-handler";
import { checkBackendState, backendOfflineProxyResponse } from "./backend";
import { proxyToOrigin } from "./proxy";
import { handleStatus } from "./status";
import { handleRestartServices } from "./restart-services";
import { handleShutdownPc } from "./shutdown-pc";
import { handleStartServices } from "./start-services";
import { handleWake, type WakeEnv } from "./wake";

export interface Env extends WakeEnv {
  PRIVATE_API: Fetcher;
  BOOT_MACHINE_TOKEN?: string;
  HEALTH_CHECK_TOKEN?: string;
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

async function handleVpcTest(env: Env): Promise<Response> {
  try {
    const healthHeaders = new Headers();
    const healthToken = env.HEALTH_CHECK_TOKEN?.trim();
    if (healthToken) {
      healthHeaders.set("Authorization", `Bearer ${healthToken}`);
    }
    const upstream = await env.PRIVATE_API.fetch(
      "http://127.0.0.1:3000/api/health",
      { headers: healthHeaders }
    );
    const contentType = upstream.headers.get("content-type") ?? "";
    const rawBody = await upstream.text();

    let upstreamBody: unknown = rawBody;
    if (contentType.includes("application/json")) {
      try {
        upstreamBody = JSON.parse(rawBody);
      } catch {
        upstreamBody = rawBody;
      }
    }

    return json({
      ok: true,
      upstreamStatus: upstream.status,
      upstreamContentType: contentType || null,
      upstreamBody,
    });
  } catch (error) {
    return json(
      {
        ok: false,
        error: "vpc_connection_failed",
        message:
          error instanceof Error ? error.message : "Connexion VPC impossible",
      },
      502
    );
  }
}

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (url.pathname === "/freebox-probe") {
        if (request.method !== "GET") {
          return json({ error: "method_not_allowed" }, 405);
        }
        return json(
          await probeFreeboxReachability({
            apiDomain: env.FREEBOX_API_DOMAIN,
            httpsPort: env.FREEBOX_HTTPS_PORT,
          })
        );
      }

      if (url.pathname === "/status") {
        if (request.method !== "GET") {
          return json({ error: "method_not_allowed" }, 405);
        }
        return handleStatus(env);
      }

      if (url.pathname === "/vpc-test") {
        if (request.method !== "GET") {
          return json({ error: "method_not_allowed" }, 405);
        }
        return handleVpcTest(env);
      }

      if (url.pathname === "/wake") {
        if (request.method !== "POST") {
          return json({ error: "method_not_allowed" }, 405);
        }
        return handleWake(request, env);
      }

      if (url.pathname === "/start-services") {
        if (request.method !== "POST") {
          return json({ error: "method_not_allowed" }, 405);
        }
        return handleStartServices(request, env);
      }

      if (url.pathname === "/restart-services") {
        if (request.method !== "POST") {
          return json({ error: "method_not_allowed" }, 405);
        }
        return handleRestartServices(request, env);
      }

      if (url.pathname === "/shutdown-pc") {
        if (request.method !== "POST") {
          return json({ error: "method_not_allowed" }, 405);
        }
        return handleShutdownPc(request, env);
      }

      if (url.pathname === "/boot-request") {
        if (request.method === "GET") {
          return handleBootRequestGet(request, env);
        }
        if (request.method === "POST") {
          return handleBootRequestConsume(request, env);
        }
        return json({ error: "method_not_allowed" }, 405);
      }

      const backend = await checkBackendState(env);
      if (backend === "offline") {
        return backendOfflineProxyResponse(request);
      }

      return proxyToOrigin(request, env, url.pathname, url.search);
    } catch {
      return json(
        {
          error: "worker_internal_error",
          message: "Erreur interne du Worker",
          status_url: "/status",
        },
        500
      );
    }
  },
};

export default worker;
