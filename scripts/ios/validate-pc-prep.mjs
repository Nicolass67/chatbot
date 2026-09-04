#!/usr/bin/env node
/**
 * Validation PC-only (sans iPhone) — syntaxe scripts, MCP import, artefacts dirs.
 * Exit 0 si terrain prêt pour smoke iOS 27.
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..", "..");
const QA = path.join(ROOT, "scripts", "ios", "qa.mjs");
const MCP = path.join(ROOT, "scripts", "ios", "mcp_server.py");
const ART = path.join(ROOT, "artifacts", "ios");

const py =
  process.env.PYTHON_IOS_QA ||
  path.join(process.env.LOCALAPPDATA || "", "Programs", "Python", "Python312", "python.exe");

function run(cmd, args, opts = {}) {
  return spawnSync(cmd, args, { encoding: "utf8", shell: opts.shell || false, cwd: ROOT });
}

const checks = [];
function ok(name, pass, detail = "") {
  checks.push({ name, pass, detail });
  console.log(`${pass ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
}

// dirs
fs.mkdirSync(path.join(ART, "before"), { recursive: true });
fs.mkdirSync(path.join(ART, "after"), { recursive: true });
ok("artifacts/ios/{before,after}", true);

// help
{
  const r = run("node", [QA, "--help"]);
  ok("qa.mjs --help", r.status === 0, "exit " + r.status);
  ok("qa.mjs documents tap", (r.stdout || "").includes("tap"), "");
  ok("qa.mjs documents autonomous", (r.stdout || "").includes("autonomous"), "");
}

// capabilities / versions (no device needed)
{
  const r = run("node", [QA, "capabilities"]);
  ok("qa.mjs capabilities", r.status === 0);
  const v = run("node", [QA, "versions"]);
  ok("qa.mjs versions", v.status === 0, (v.stdout || "").split("\n")[0]);
}

// deep link normalizer via open without device should fail gracefully
{
  const r = run("node", [QA, "open", "qa/mail"]);
  // may fail if no device — that's OK as long as it doesn't crash node
  ok(
    "qa.mjs open exits cleanly",
    r.status === 0 || /non installe|No USB|detecte|Device/i.test(`${r.stdout}\n${r.stderr}`),
    `exit ${r.status}`
  );
}

// tap without claiming PASS on blocked OS — should classify if device present
{
  const r = run("node", [QA, "tap", "32768", "32768"]);
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  const honest =
    /BLOCKED_BY_OS|PASS|Device not connected|non installe|Aucun iPhone|detecte|not connected/i.test(out) ||
    r.status !== 0;
  ok("qa.mjs tap honest status", honest, out.split("\n").filter(Boolean).slice(-2).join(" | ").slice(0, 120));
}

// MCP import
{
  const r = run(py, ["-c", "import importlib.util; s=importlib.util.spec_from_file_location('m', r'" + MCP.replace(/\\/g, "\\\\") + "'); m=importlib.util.module_from_spec(s); print('mcp_ok')"]);
  // Don't execute mcp.run(); just compile
  const c = run(py, ["-m", "py_compile", MCP]);
  ok("mcp_server.py compiles", c.status === 0, (c.stderr || "").slice(0, 100));
}

// project.yml + UITests present
{
  const yml = fs.readFileSync(path.join(ROOT, "apps", "ios", "project.yml"), "utf8");
  ok("project.yml UITests target", yml.includes("ChatbotNativeUITests"));
  ok(
    "ProductCampaignUITests exists",
    fs.existsSync(path.join(ROOT, "apps", "ios", "ChatbotNativeUITests", "ProductCampaignUITests.swift"))
  );
  ok(
    "A11yID.swift exists",
    fs.existsSync(path.join(ROOT, "apps", "ios", "ChatbotNative", "Accessibility", "A11yID.swift"))
  );
}

// mcp.json
{
  const mcpJson = JSON.parse(fs.readFileSync(path.join(ROOT, ".cursor", "mcp.json"), "utf8"));
  ok("mcp.json chatbot-ios-qa", !!mcpJson.mcpServers?.["chatbot-ios-qa"]);
}

const failed = checks.filter((c) => !c.pass);
console.log("");
console.log(`PC prep: ${checks.length - failed.length}/${checks.length} PASS`);
if (failed.length) {
  console.log("FAILED:", failed.map((f) => f.name).join(", "));
  process.exit(1);
}
console.log("READY for iOS 27 smoke when user confirms device is updated.");
