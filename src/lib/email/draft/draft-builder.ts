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
- Dès que l'utilisateur demande d'écrire, rédiger, préparer, ENVOYER, réécrire ou améliorer un mail → appelle immédiatement email_create_draft (corps + objet + destinataire).
- Si un brouillon est déjà ouvert / mentionné (draftId) : réécris via email_create_draft avec le nouveau bodyText (même to/subject sauf demande contraire). N’écris JAMAIS le corps dans le chat.
- Si le message utilisateur contient déjà des pièces jointes (bloc « Pièces jointes du message », images, fichiers joints) : NE demande PAS de préciser la PJ — elle est déjà fournie et sera attachée automatiquement au brouillon.
- Une image jointe dans le chat EST une pièce jointe utilisable : appelle email_create_draft tout de suite (ex. « envoie cette PJ à moi-même »).
- INTERDIT de dire que tu ne vois pas / ne peux pas accéder à une PJ affichée dans le chat.
- INTERDIT de dire que tu ne peux pas envoyer, ni que tu ne peux pas envoyer de fichiers / images / pièces jointes.
- Tu ne peux pas appeler un outil d'envoi direct : l'utilisateur confirme avec le bouton Envoyer sur la carte brouillon.
- Après création / réécriture : confirme en 1 phrase max sans coller le corps (la carte UI l'affiche).
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
