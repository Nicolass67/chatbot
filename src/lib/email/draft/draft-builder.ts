import type { ChatMessage } from "@/lib/runtime/types";

export type EmailDraftInstructionsOptions = {
  accountEmail?: string | null;
};

export function buildEmailDraftInstructionsBlock(
  writingPrefsBlock: string,
  options?: EmailDraftInstructionsOptions
): string {
  const accountEmail = options?.accountEmail?.trim();
  const selfLine = accountEmail
    ? `- Pour « à moi », « moi-même », « mon adresse » ou un mail de test à soi : mets to="${accountEmail}".`
    : `- Pour « à moi » / « moi-même » : utilise l'adresse Gmail connectée indiquée dans le contexte si disponible.`;

  return `${writingPrefsBlock}

<email_draft_instructions>
Tu prépares des emails via l'outil email_create_draft UNIQUEMENT.
- Dès que l'utilisateur demande d'écrire, rédiger, préparer ou ENVOYER un mail → appelle immédiatement email_create_draft (corps + objet + destinataire).
- INTERDIT de dire que tu ne peux pas envoyer. Tu ne peux pas appeler un outil d'envoi direct : l'utilisateur confirme avec le bouton Envoyer sur la carte brouillon.
- Après création : confirme en 1-2 phrases et indique qu'il peut appuyer sur Envoyer (ou demander des modifications).
${selfLine}
- Applique les préférences de rédaction ci-dessus (ton, formules, signature, langue).
- Ne narre pas tout le brouillon dans le chat : la carte UI l'affiche.
</email_draft_instructions>`;
}

export function injectEmailDraftWritingIntoContext(
  contextMessages: ChatMessage[],
  writingPrefsBlock: string,
  options?: EmailDraftInstructionsOptions
): void {
  const systemMsg = contextMessages[0];
  if (systemMsg?.role !== "system" || typeof systemMsg.content !== "string") {
    return;
  }
  if (systemMsg.content.includes("<email_draft_instructions>")) {
    return;
  }
  systemMsg.content += `\n\n${buildEmailDraftInstructionsBlock(writingPrefsBlock, options)}`;
}
