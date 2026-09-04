import {
  freeboxBaseUrl,
  isFreeboxTlsTrustFailure,
  type FreeboxConfig,
} from "./freebox";

/** Diagnostic sûr — aucun secret, pour tests Worker → Freebox. */
export async function probeFreeboxReachability(
  config: Pick<FreeboxConfig, "apiDomain" | "httpsPort">,
  fetchFn: typeof fetch = fetch
): Promise<Record<string, unknown>> {
  const url = `${freeboxBaseUrl(config)}/api/v4/login/`;
  try {
    const response = await fetchFn(url, {
      method: "GET",
      headers: { Accept: "application/json" },
    });
    const contentType = response.headers.get("content-type");
    const raw = await response.text();
    let parsed: unknown = null;
    let parseError: string | null = null;
    try {
      parsed = JSON.parse(raw);
    } catch (error) {
      parseError =
        error instanceof Error ? error.message : "json_parse_failed";
    }

    const tlsTrustFailed = isFreeboxTlsTrustFailure(response, raw);

    return {
      ok: parsed !== null && !tlsTrustFailed,
      url,
      status: response.status,
      contentType,
      bodyLength: raw.length,
      bodyPreview: raw.slice(0, 160).replace(/[\r\n]+/g, " "),
      parseError,
      tlsTrustFailed,
      hasChallenge:
        typeof parsed === "object" &&
        parsed !== null &&
        "result" in parsed &&
        typeof (parsed as { result?: { challenge?: string } }).result
          ?.challenge === "string",
    };
  } catch (error) {
    return {
      ok: false,
      url,
      error: error instanceof Error ? error.name : "fetch_failed",
      message: error instanceof Error ? error.message : "fetch_failed",
    };
  }
}
