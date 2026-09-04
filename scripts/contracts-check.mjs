import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const contractsDir = path.join(root, "contracts");

const KNOWN_ERROR_CODES = new Set(
  JSON.parse(
    fs.readFileSync(
      path.join(contractsDir, "errors/api-error.schema.json"),
      "utf8"
    )
  ).properties.code.enum
);

function parseSseFixture(text) {
  const events = [];
  for (const block of text.split(/\n\n+/)) {
    const line = block.trim();
    if (!line || line.startsWith(":")) continue;
    if (!line.startsWith("data: ")) {
      throw new Error(`Invalid SSE line (expected data:): ${line.slice(0, 80)}`);
    }
    events.push(JSON.parse(line.slice(6)));
  }
  return events;
}

function assertEventShape(event, fixture) {
  if (!event || typeof event !== "object" || typeof event.type !== "string") {
    throw new Error(`${fixture}: event missing type`);
  }
  switch (event.type) {
    case "token":
      if (typeof event.content !== "string") {
        throw new Error(`${fixture}: token.content`);
      }
      break;
    case "done":
    case "assistant_start":
    case "assistant_discard":
      if (typeof event.messageId !== "string") {
        throw new Error(`${fixture}: ${event.type}.messageId`);
      }
      break;
    case "error":
      if (typeof event.message !== "string") {
        throw new Error(`${fixture}: error.message`);
      }
      if (event.code != null && !KNOWN_ERROR_CODES.has(event.code)) {
        throw new Error(`${fixture}: unknown error code ${event.code}`);
      }
      break;
    case "mail_handoff":
      if (typeof event.intent !== "string" || typeof event.reason !== "string") {
        throw new Error(`${fixture}: mail_handoff intent/reason`);
      }
      break;
    case "files_handoff":
      if (typeof event.intent !== "string" || typeof event.reason !== "string") {
        throw new Error(`${fixture}: files_handoff intent/reason`);
      }
      break;
    default:
      // forward compatible — unknown types allowed
      break;
  }
}

function main() {
  const version = fs.readFileSync(path.join(contractsDir, "VERSION"), "utf8").trim();
  if (!/^\d+$/.test(version)) {
    throw new Error(`contracts/VERSION must be integer, got ${version}`);
  }

  const required = [
    "errors/api-error.schema.json",
    "chat/orchestrator-events.schema.json",
    "handoffs/mail-handoff.schema.json",
    "handoffs/files-handoff.schema.json",
  ];
  for (const rel of required) {
    const p = path.join(contractsDir, rel);
    if (!fs.existsSync(p)) throw new Error(`Missing ${rel}`);
    JSON.parse(fs.readFileSync(p, "utf8"));
  }

  const fixturesDir = path.join(contractsDir, "chat/fixtures");
  const fixtures = fs.readdirSync(fixturesDir).filter((f) => f.endsWith(".sse.txt"));
  if (fixtures.length < 5) {
    throw new Error("Expected at least 5 SSE fixtures");
  }

  for (const name of fixtures) {
    const text = fs.readFileSync(path.join(fixturesDir, name), "utf8");
    const events = parseSseFixture(text);
    if (events.length === 0) throw new Error(`${name}: empty`);
    for (const ev of events) assertEventShape(ev, name);
  }

  // Baseline anti-drift: schema digests
  const baselineDir = path.join(contractsDir, "baseline");
  fs.mkdirSync(baselineDir, { recursive: true });
  const digest = {};
  for (const rel of required) {
    digest[rel] = fs.readFileSync(path.join(contractsDir, rel), "utf8");
  }
  digest["VERSION"] = version;
  const baselinePath = path.join(baselineDir, "schemas.snapshot.json");
  const nextSnapshot = JSON.stringify(digest, null, 2) + "\n";

  if (process.argv.includes("--update-baseline")) {
    fs.writeFileSync(baselinePath, nextSnapshot);
    console.log("baseline updated");
    return;
  }

  if (!fs.existsSync(baselinePath)) {
    fs.writeFileSync(baselinePath, nextSnapshot);
    console.log("baseline created");
    return;
  }

  const prev = fs.readFileSync(baselinePath, "utf8");
  if (prev !== nextSnapshot) {
    const prevObj = JSON.parse(prev);
    if (prevObj.VERSION === version) {
      throw new Error(
        "Schema content changed without bumping contracts/VERSION. Bump VERSION or run: node scripts/contracts-check.mjs --update-baseline"
      );
    }
    // Version bumped — refresh baseline automatically in CI after intentional bump
    fs.writeFileSync(baselinePath, nextSnapshot);
    console.log("baseline refreshed after VERSION bump");
  }

  console.log(`contracts OK (v${version}, ${fixtures.length} fixtures)`);
}

try {
  main();
} catch (err) {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
}
