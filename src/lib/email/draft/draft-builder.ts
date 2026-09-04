import type { ChatMessage } from "@/lib/runtime/types";

export function buildEmailDraftInstructionsBlock(writingPrefsBlock: string): string {
  return `${writingPrefsBlock}

<email_draft_instructions>
Tu peux rédiger des brouillons email via l'outil email_create_draft uniquement.
- Applique les préférences de rédaction ci-dessus (ton, formules, signature, langue).
- Ne tente jamais d'envoyer directement : l'envoi exige une validation explicite de l'utilisateur.
- Présente le brouillon clairement et propose des ajustements si nécessaire.
</email_draft_instructions>`;
}

export function injectEmailDraftWritingIntoContext(
  contextMessages: ChatMessage[],
  writingPrefsBlock: string
): void {
  const systemMsg = contextMessages[0];
  if (systemMsg?.role !== "system" || typeof systemMsg.content !== "string") {
    return;
  }
  systemMsg.content += `\n\n${buildEmailDraftInstructionsBlock(writingPrefsBlock)}`;
}
