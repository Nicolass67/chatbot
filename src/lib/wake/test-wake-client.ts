export interface WakeTestResult {
  status: number;
  body: unknown;
}

/** Client POST /wake — session Cloudflare Access incluse via cookies same-origin. */
export async function postWakeTest(
  fetchFn: typeof fetch = fetch
): Promise<WakeTestResult> {
  const response = await fetchFn("/wake", { method: "POST" });
  const text = await response.text();

  try {
    return { status: response.status, body: JSON.parse(text) as unknown };
  } catch {
    return { status: response.status, body: text };
  }
}

export function formatWakeTestResult(result: WakeTestResult): string {
  return `HTTP ${result.status}\n${JSON.stringify(result.body, null, 2)}`;
}
