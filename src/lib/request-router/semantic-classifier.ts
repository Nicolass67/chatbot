import { z } from "zod";
import type { ObjectiveContext } from "./types";

export const semanticClassificationSchema = z.object({
  knowledge: z.enum(["static", "current", "unknown"]),
  web: z.object({
    mode: z.enum(["none", "optional", "required"]),
    searchType: z.enum(["none", "single", "research"]),
    searchQuery: z.string().min(1).optional(),
  }),
  email: z
    .object({
      intent: z.enum(["none", "list", "search", "read_thread", "analyze", "draft"]),
      searchQuery: z.string().min(1).optional(),
    })
    .optional(),
  files: z
    .object({
      intent: z.enum([
        "none",
        "search",
        "list",
        "read",
        "analyze",
        "organize",
      ]),
      searchQuery: z.string().min(1).optional(),
    })
    .optional(),
  research: z
    .object({
      objective: z.string().min(1).optional(),
    })
    .optional(),
  execution: z.enum(["direct", "tool", "research", "agent"]),
  vision: z.object({ required: z.boolean() }),
  tools: z.object({ allowToolCalling: z.boolean() }),
  confidence: z.number().min(0).max(1),
  reason: z.string().min(1),
});

function extractJsonFromContent(content: string): unknown {
  const trimmed = content.trim();
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const jsonStr = fenceMatch ? fenceMatch[1].trim() : trimmed;
  const start = jsonStr.indexOf("{");
  const end = jsonStr.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error("Réponse routeur sans JSON valide");
  }
  return JSON.parse(jsonStr.slice(start, end + 1));
}

export function parseSemanticClassification(content: string) {
  const raw = extractJsonFromContent(content);
  const parsed = semanticClassificationSchema.parse(raw);
  return {
    ...parsed,
    email: parsed.email ?? { intent: "none" as const },
    files: parsed.files ?? { intent: "none" as const },
  };
}

export function buildClassifierSystemPrompt(objective: ObjectiveContext): string {
  return `Tu es un routeur sémantique pour un chatbot local. Tu ne réponds PAS à l'utilisateur.
Tu produis UNIQUEMENT un objet JSON valide, sans markdown ni texte autour.

Date actuelle: ${objective.clock.currentDateTime} (${objective.clock.timezone}).

Définitions:
- knowledge "static": la réponse repose sur des connaissances stables (concepts, définitions, mécanismes, mathématiques, histoire fixe).
- knowledge "current": la réponse dépend du présent ou de faits susceptibles d'avoir changé depuis l'entraînement du modèle.
- knowledge "unknown": le caractère temporel est ambigu.

- web.mode "required": une source externe fiable est indispensable pour répondre correctement, OU l'utilisateur demande explicitement une vérification externe, OU la réponse dépend d'informations susceptibles d'avoir changé.
- web.mode "optional": le Web peut enrichir la réponse sans être indispensable.
- web.mode "none": le Web n'apporte rien d'essentiel.

- web.searchType "single": une recherche ciblée suffit probablement.
- web.searchType "research": plusieurs sources, comparaisons, synthèse ou vérifications croisées sont nécessaires.
- web.searchType "none": pas de recherche.

- web.searchQuery: reformulation courte et fidèle pour un moteur de recherche (dans la langue la plus pertinente). Si un contexte conversationnel récent est fourni, RÉSOUS les références (ça, ceux, modèles, maintenant, etc.) en y intégrant le sujet du tour précédent (ex. aspirateurs → « meilleurs modèles aspirateurs 2026 »). N'ajoute PAS de contraintes non demandées (pays, année, disponibilité, stock, etc.) sauf si l'utilisateur les mentionne.

- research.objective: objectif informationnel pour une recherche approfondie (si searchType=research). Décris le besoin, pas une catégorie de domaine.

- execution "direct": réponse directe sans outil.
- execution "tool": outil(s) ponctuel(s), typiquement une recherche Web.
- execution "research": plusieurs recherches/étapes avant synthèse (mode chat).
- execution "agent": réservé si le mode agent est déjà actif.

- vision.required: true seulement si l'utilisateur demande d'analyser une image jointe pertinente pour la réponse.

Email (boîte Gmail personnelle de l'utilisateur — PAS de recherche Web):
- email.intent "none": pas de tâche liée à la boîte mail personnelle.
- email.intent "list": l'utilisateur veut voir/lister des emails récents (inbox, non lus, etc.).
- email.intent "search": l'utilisateur cherche des emails précis (expéditeur, sujet, période, mot-clé).
- email.intent "read_thread": l'utilisateur veut lire un fil / conversation email complet.
- email.intent "analyze": l'utilisateur veut une analyse, tri, priorités, ou identifier ce qui nécessite une réponse.
- email.intent "draft": l'utilisateur veut rédiger/préparer un email ou une réponse (sans envoi direct).
- email.searchQuery: requête Gmail reformulée si intent=search (syntaxe Gmail: from:, is:unread, subject:, etc.).
- Ne confonds PAS une question générale sur le courrier électronique ("comment fonctionne SMTP") avec une tâche sur SA boîte mail.
- Ne classifie JAMAIS un envoi direct ("envoie l'email", "send it") comme autre chose que "draft" — l'envoi exige toujours confirmation utilisateur.
- Si email.intent ≠ "none", mets généralement web.mode="none" et tools.allowToolCalling=true (sauf message purement conversationnel).

Files (documents locaux sur le PC de l'utilisateur — PAS le Web, PAS Gmail):
- files.intent "none": pas de tâche sur les fichiers locaux.
- files.intent "search": retrouver un ou plusieurs documents locaux (facture, contrat, PDF, dossier, etc.).
- files.intent "list": parcourir / lister un dossier local.
- files.intent "read": ouvrir / lire un document déjà identifié.
- files.intent "analyze": résumer / analyser / comparer des documents locaux.
- files.intent "organize": renommer, déplacer, créer un dossier (organisation).
- files.searchQuery: reformulation courte pour recherche locale si intent=search.
- Distingue clairement: question conceptuelle vs document personnel local vs email vs actualité web.
- CRITIQUE — « rechercher / recherches / cherche » SANS mot fichier/PDF/dossier/document/facture = Web, PAS files. Ex. « recherches les adresses des restaurants à Strasbourg » → files.intent="none", web.mode="required".
- files.intent ≠ "none" UNIQUEMENT si l'utilisateur parle explicitement de fichiers/documents locaux sur son PC.
- Si files.intent ≠ "none" ET qu'il n'y a PAS de demande web/internet/adresses publiques, mets web.mode="none" et tools.allowToolCalling=true.
- Si l'utilisateur demande internet / web / adresses / lieux publics : web.mode="required", files.intent="none".
- Ne classifie PAS une mutation destructive (suppression) — non supportée; oriente vers search/organize sans delete.

Priorité de sécurité: en cas de doute sur une information actuelle, préférer web.mode "required" plutôt que "none".
Ne confonds pas une question sur le CONCEPT d'un sujet (ex: "comment fonctionne X") avec une demande d'ÉTAT ACTUEL.

JSON attendu:
{
  "knowledge": "static|current|unknown",
  "web": { "mode": "none|optional|required", "searchType": "none|single|research", "searchQuery": "..." },
  "email": { "intent": "none|list|search|read_thread|analyze|draft", "searchQuery": "..." },
  "files": { "intent": "none|search|list|read|analyze|organize", "searchQuery": "..." },
  "research": { "objective": "..." },
  "execution": "direct|tool|research|agent",
  "vision": { "required": false },
  "tools": { "allowToolCalling": false },
  "confidence": 0.0,
  "reason": "..."
}`;
}

export function buildClassifierUserPrompt(objective: ObjectiveContext): string {
  const lines = [
    `Message utilisateur:\n${objective.trimmedMessage}`,
    `Mode: ${objective.chatMode}`,
    `Web activé: ${objective.webSearchEnabled ? "oui" : "non"}`,
    `Email activé: ${objective.emailEnabled ? "oui" : "non"}`,
    `Gmail connecté: ${objective.emailConnected ? "oui" : "non"}`,
    `Files activé: ${objective.filesEnabled ? "oui" : "non"}`,
    `Roots Files configurées: ${objective.filesConfigured ? "oui" : "non"}`,
    `Images jointes: ${objective.imageCount}`,
    `Pièces jointes: ${objective.attachmentCount}`,
    `Capacités modèle — vision: ${objective.modelCapabilities.vision ? "oui" : "non"}, tools: ${objective.modelCapabilities.toolCalling ? "oui" : "non"}`,
  ];

  if (objective.temporal.userMentionedYears.length > 0) {
    lines.push(
      `Années mentionnées: ${objective.temporal.userMentionedYears.join(", ")}`
    );
  }
  if (objective.temporal.scope !== "unspecified") {
    lines.push(`Scope temporel détecté: ${objective.temporal.scope}`);
  }
  if (objective.conversationalContext) {
    lines.push(`Contexte conversationnel récent:\n${objective.conversationalContext}`);
  }

  lines.push("Classifie cette requête.");
  return lines.join("\n\n");
}

