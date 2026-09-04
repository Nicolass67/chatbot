export interface ShutdownPcResult {
  status: number;
  body: unknown;
}

/** Client POST /shutdown-pc — session Cloudflare Access incluse via cookies same-origin. */
export async function postShutdownPc(
  fetchFn: typeof fetch = fetch
): Promise<ShutdownPcResult> {
  const response = await fetchFn("/shutdown-pc", { method: "POST" });
  const text = await response.text();

  try {
    return { status: response.status, body: JSON.parse(text) as unknown };
  } catch {
    return { status: response.status, body: text };
  }
}

export function formatShutdownPcResult(result: ShutdownPcResult): string {
  return `HTTP ${result.status}\n${JSON.stringify(result.body, null, 2)}`;
}

export function isShutdownPcSuccess(result: ShutdownPcResult): boolean {
  if (result.status !== 200) return false;
  const body = result.body as { ok?: boolean } | null;
  return body?.ok === true;
}
