/**
 * Filtre les IDs LM Studio utilisables comme modèle de chat.
 * Exclut embeddings, draft MTP (speculative decoding), etc.
 */
export function isSelectableChatModel(
  modelId: string,
  displayName?: string | null
): boolean {
  const id = modelId.trim();
  if (!id) return false;
  const leaf = id.split(/[/\\]/).pop() ?? id;
  const hay = `${id} ${displayName ?? ""}`.toLowerCase();

  if (/embed|embedding|nomic-embed|text-embedding/.test(hay)) return false;
  if (/(^|[-_.])mtp($|[-_.])/.test(leaf.toLowerCase())) return false;
  if (/\b(mtp|draft|speculative)\b/.test(hay)) return false;

  return true;
}
