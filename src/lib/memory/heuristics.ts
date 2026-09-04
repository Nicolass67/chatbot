/**
 * @deprecated Ne plus utiliser pour décider d'extraire de la mémoire.
 * Le classifieur LLM (`classifyMemoryIntent`) est la seule source de vérité.
 * Conservé pour compat / tests — toujours false.
 */
export function shouldExtractMemory(_userMessage: string): boolean {
  return false;
}
