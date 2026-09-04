import { describe, expect, it } from "vitest";
import {
  buildUpstreamHeaders,
  filterResponseHeaders,
  methodAllowsBody,
  rewriteLocation,
} from "./proxy";

describe("rewriteLocation", () => {
  it("keeps relative locations", () => {
    expect(rewriteLocation("/chat/new", "https://chatbot.example.workers.dev")).toBe(
      "/chat/new"
    );
  });

  it("rewrites localhost absolute locations", () => {
    expect(
      rewriteLocation(
        "http://127.0.0.1:3000/chat/new",
        "https://chatbot.example.workers.dev"
      )
    ).toBe("https://chatbot.example.workers.dev/chat/new");
  });
});

describe("buildUpstreamHeaders", () => {
  it("forwards auth and access headers", () => {
    const req = new Request("https://worker.example/vpc-test", {
      headers: {
        "Cf-Access-Jwt-Assertion": "jwt-test",
        Authorization: "Bearer secret",
        "Content-Type": "application/json",
        Host: "worker.example",
      },
    });
    const headers = buildUpstreamHeaders(req);
    expect(headers.get("host")).toBe("127.0.0.1:3000");
    expect(headers.get("cf-access-jwt-assertion")).toBe("jwt-test");
    expect(headers.get("authorization")).toBe("Bearer secret");
    expect(headers.get("x-forwarded-host")).toBe("worker.example");
  });
});

describe("filterResponseHeaders", () => {
  it("rewrites location on responses", () => {
    const headers = new Headers({
      Location: "http://127.0.0.1:3000/chat/new",
      "Content-Type": "text/html",
    });
    const filtered = filterResponseHeaders(
      headers,
      "https://chatbot.example.workers.dev"
    );
    expect(filtered.get("location")).toBe(
      "https://chatbot.example.workers.dev/chat/new"
    );
    expect(filtered.get("content-type")).toBe("text/html");
  });
});

describe("methodAllowsBody", () => {
  it("blocks GET and HEAD bodies", () => {
    expect(methodAllowsBody("GET")).toBe(false);
    expect(methodAllowsBody("POST")).toBe(true);
    expect(methodAllowsBody("PATCH")).toBe(true);
  });
});

describe("proxyToOrigin VPC failures", () => {
  it("returns 503 instead of throwing when VPC is unreachable", async () => {
    const { proxyToOrigin } = await import("./proxy");
    const env = {
      PRIVATE_API: {
        fetch: async () => {
          throw new Error("vpc_connection_failed");
        },
      } as unknown as Fetcher,
    };

    const request = new Request("https://chatbot.example.workers.dev/", {
      headers: { Accept: "text/html" },
    });

    const response = await proxyToOrigin(request, env, "/", "");
    expect(response.status).toBe(503);
    const html = await response.text();
    expect(html).toContain("PC hors ligne");
  });

  it("returns JSON 503 for API routes when VPC is unreachable", async () => {
    const { proxyToOrigin } = await import("./proxy");
    const env = {
      PRIVATE_API: {
        fetch: async () => {
          throw new TypeError("Network connection lost");
        },
      } as unknown as Fetcher,
    };

    const request = new Request("https://chatbot.example.workers.dev/api/health");
    const response = await proxyToOrigin(request, env, "/api/health", "");
    expect(response.status).toBe(503);
    const body = (await response.json()) as { error: string };
    expect(body.error).toBe("backend_offline");
  });
});

describe("proxyToOrigin streaming", () => {
  it("passes through SSE body without buffering", async () => {
    const { proxyToOrigin } = await import("./proxy");
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("data: {\"type\":\"token\"}\n\n"));
        controller.close();
      },
    });

    const env = {
      PRIVATE_API: {
        fetch: async () =>
          new Response(stream, {
            status: 200,
            headers: {
              "Content-Type": "text/event-stream",
              "Cache-Control": "no-cache, no-transform",
              "X-Accel-Buffering": "no",
            },
          }),
      } as unknown as Fetcher,
    };

    const request = new Request("https://chatbot.example.workers.dev/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ conversationId: "test", message: "hi" }),
    });

    const response = await proxyToOrigin(request, env, "/api/chat", "");
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    expect(response.headers.get("x-accel-buffering")).toBe("no");

    const reader = response.body!.getReader();
    const chunk = await reader.read();
    expect(new TextDecoder().decode(chunk.value)).toContain("data:");
  });
});
