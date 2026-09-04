import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { assertApiErrorShape } from "@/lib/http/api-error";
import {
  buildMailHandoffUrl,
  resolveMailHandoffHref,
} from "@/lib/mail/handoff";
import {
  buildFilesHandoffUrl,
  resolveFilesHandoffHref,
} from "@/lib/files/handoff";

const fixturesDir = path.resolve(
  process.cwd(),
  "contracts/chat/fixtures"
);

function parseSse(text: string): Array<Record<string, unknown>> {
  const events: Array<Record<string, unknown>> = [];
  for (const block of text.split(/\n\n+/)) {
    const line = block.trim();
    if (!line || line.startsWith(":")) continue;
    expect(line.startsWith("data: ")).toBe(true);
    events.push(JSON.parse(line.slice(6)) as Record<string, unknown>);
  }
  return events;
}

describe("contracts SSE fixtures", () => {
  const files = fs.readdirSync(fixturesDir).filter((f) => f.endsWith(".sse.txt"));

  it("has fixtures", () => {
    expect(files.length).toBeGreaterThanOrEqual(5);
  });

  for (const name of files) {
    it(`parses ${name}`, () => {
      const events = parseSse(
        fs.readFileSync(path.join(fixturesDir, name), "utf8")
      );
      expect(events.length).toBeGreaterThan(0);
      for (const ev of events) {
        expect(typeof ev.type).toBe("string");
      }
    });
  }

  it("abort fixture uses ABORTED code", () => {
    const events = parseSse(
      fs.readFileSync(path.join(fixturesDir, "abort.sse.txt"), "utf8")
    );
    const err = events.find((e) => e.type === "error");
    expect(err?.code).toBe("ABORTED");
  });

  it("mail handoff fixture is IDs-first", () => {
    const events = parseSse(
      fs.readFileSync(path.join(fixturesDir, "mail-handoff.sse.txt"), "utf8")
    );
    const handoff = events.find((e) => e.type === "mail_handoff");
    expect(handoff?.threadId).toBeTruthy();
    expect(handoff?.intent).toBe("read_thread");
  });

  it("unknown event does not break stream parse", () => {
    const events = parseSse(
      fs.readFileSync(path.join(fixturesDir, "unknown-event.sse.txt"), "utf8")
    );
    expect(events.some((e) => e.type === "future_event_v2")).toBe(true);
    expect(events.some((e) => e.type === "done")).toBe(true);
  });
});

describe("contracts api error + handoffs", () => {
  it("assertApiErrorShape", () => {
    assertApiErrorShape({ error: "x", code: "NOT_FOUND" });
  });

  it("mail href from IDs without relying on url", () => {
    const built = buildMailHandoffUrl({
      intent: "read_thread",
      threadId: "threadabc123456789",
    });
    expect(resolveMailHandoffHref(built)).toBe(
      "/mail/thread/threadabc123456789"
    );
    expect(built.threadId).toBe("threadabc123456789");
  });

  it("files href from IDs", () => {
    const built = buildFilesHandoffUrl({
      intent: "search",
      query: "doc",
      rootId: "rootabcd12",
    });
    expect(resolveFilesHandoffHref({
      intent: built.intent,
      query: built.query,
      rootId: built.rootId,
    })).toContain("q=doc");
    expect(built.rootId).toBe("rootabcd12");
  });
});
