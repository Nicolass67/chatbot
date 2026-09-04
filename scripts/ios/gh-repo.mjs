/**
 * Resolve GitHub owner/repo for iOS CI scripts.
 * Prefer IOS_GH_REPO, then `gh repo view`, then a generic placeholder.
 */
import { spawnSync } from "node:child_process";

const FALLBACK = "your-org/your-repo";

export function resolveGhRepo(cwd = process.cwd()) {
  const fromEnv = process.env.IOS_GH_REPO?.trim();
  if (fromEnv) return fromEnv;

  const r = spawnSync(
    "gh",
    ["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
    { encoding: "utf8", cwd, shell: false }
  );
  if (r.status === 0) {
    const name = (r.stdout || "").trim();
    if (name && name.includes("/")) return name;
  }
  return FALLBACK;
}
