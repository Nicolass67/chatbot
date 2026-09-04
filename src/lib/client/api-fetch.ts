/**
 * Fetch client robuste pour l’UI :
 * - 401 → event chatbot:auth-required (toast + reload)
 * - network error → event chatbot:network-error
 */

export class ApiAuthError extends Error {
  readonly status = 401;
  constructor(message = "Session expirée") {
    super(message);
    this.name = "ApiAuthError";
  }
}

export class ApiNetworkError extends Error {
  constructor(message = "Réseau indisponible") {
    super(message);
    this.name = "ApiNetworkError";
  }
}

export async function apiFetch(
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> {
  let response: Response;
  try {
    response = await fetch(input, init);
  } catch (error) {
    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent("chatbot:network-error", {
          detail: { message: error instanceof Error ? error.message : String(error) },
        })
      );
    }
    throw new ApiNetworkError(
      error instanceof Error ? error.message : "Réseau indisponible"
    );
  }

  if (response.status === 401) {
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("chatbot:auth-required"));
    }
    throw new ApiAuthError();
  }

  return response;
}
