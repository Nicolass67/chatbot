/** AbortError (DOMException ou Error) — ne pas finaliser comme un succès vide. */
export function isAbortLikeError(error: unknown): boolean {
  if (error instanceof DOMException && error.name === "AbortError") return true;
  if (error instanceof Error && error.name === "AbortError") return true;
  return false;
}
