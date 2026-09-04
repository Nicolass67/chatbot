#!/usr/bin/env node
/**
 * Smoke test API email V2 (sans navigateur).
 * Usage: node scripts/e2e-email-smoke.mjs [baseUrl]
 */
const baseUrl = (process.argv[2] ?? process.env.PUBLIC_BASE_URL ?? "http://localhost:3000").replace(/\/$/, "");

async function request(path, options = {}) {
  const url = `${baseUrl}${path}`;
  const res = await fetch(url, {
    ...options,
    headers: {
      "x-user-id": "e2e-smoke",
      "Content-Type": "application/json",
      ...(options.headers ?? {}),
    },
  });
  const text = await res.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  return { status: res.status, body };
}

function assert(condition, message) {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exitCode = 1;
    throw new Error(message);
  }
}

async function main() {
  console.log(`E2E email V2 smoke → ${baseUrl}\n`);

  const health = await request("/api/health");
  assert(health.status === 200, `/api/health → ${health.status}`);
  console.log("OK  /api/health");

  const oauth = await request("/api/oauth/accounts");
  assert(oauth.status === 200, `/api/oauth/accounts → ${oauth.status}`);
  console.log(
    `OK  /api/oauth/accounts configured=${oauth.body?.configured} accounts=${oauth.body?.accounts?.length ?? 0}`
  );

  const mailMessages = await request("/api/mail/messages?label=INBOX");
  assert(
    mailMessages.status === 200 ||
      mailMessages.status === 403 ||
      mailMessages.status === 503,
    `/api/mail/messages → ${mailMessages.status}`
  );
  console.log(`OK  /api/mail/messages → ${mailMessages.status}`);

  const missingDraft = await request("/api/email/drafts/nonexistent-draft-id");
  assert(
    missingDraft.status === 404 || missingDraft.status === 503,
    `draft absent → ${missingDraft.status} (attendu 404 ou 503 si email off)`
  );
  console.log(`OK  draft introuvable → ${missingDraft.status}`);

  const userB = await fetch(`${baseUrl}/api/email/drafts/nonexistent-draft-id`, {
    headers: { "x-user-id": "other-user" },
  });
  assert(
    userB.status === 404 || userB.status === 503,
    `isolation user → ${userB.status}`
  );
  console.log(`OK  isolation x-user-id → ${userB.status}`);

  if (process.exitCode) {
    console.error("\nSmoke test terminé avec erreurs.");
    process.exit(process.exitCode);
  }
  console.log("\nSmoke test email V2 OK.");
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
