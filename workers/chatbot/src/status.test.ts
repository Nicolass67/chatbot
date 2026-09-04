import { describe, expect, it } from "vitest";
import { handleStatus } from "./status";

describe("handleStatus", () => {
  it("returns worker ok and backend offline without throwing", async () => {
    const env = {
      PRIVATE_API: {
        fetch: async () => {
          throw new Error("tunnel_down");
        },
      } as unknown as Fetcher,
    };

    const response = await handleStatus(env);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { worker: string; backend: string };
    expect(body).toEqual({ worker: "ok", backend: "offline" });
  });

  it("returns backend online when health succeeds", async () => {
    const env = {
      PRIVATE_API: {
        fetch: async () => new Response("{}", { status: 200 }),
      } as unknown as Fetcher,
    };

    const response = await handleStatus(env);
    const body = (await response.json()) as { backend: string };
    expect(body.backend).toBe("online");
  });
});
