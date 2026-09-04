import type { AgentExecutionContext, AgentPlan } from "./types";
import type { TemporalContext } from "./temporal";
import { formatTemporalContextBlock, resolveEffectiveScope } from "./temporal";
import { formatResearchBlockForDecider } from "./research-flow";
import { formatFreshnessBlock } from "./freshness-policy";
import { RESPONSE_FORMAT_INSTRUCTIONS } from "@/lib/prompts/response-format";

export function buildPlannerSystemPrompt(temporal: TemporalContext): string {
  const temporalBlock = formatTemporalContextBlock(temporal);
  const needsResearchPlan =
    temporal.isTimeSensitive &&
    (resolveEffectiveScope(temporal) === "current" ||
      resolveEffectiveScope(temporal) === "recent");

  const researchBlock = needsResearchPlan
    ? `
Plan recommandé pour une demande d'information actuelle (3 étapes) :
1. Recherche Web ciblée
2. Analyse des sources collectées
3. Synthèse / réponse finale
`
    : "";

  return `Tu es un planificateur d'agent IA. Analyse l'objectif de l'utilisateur et produis un plan d'exécution structuré.

Contexte temporel :
${temporalBlock}
${researchBlock}

Réponds UNIQUEMENT avec un objet JSON valide (sans markdown, sans commentaire) :
{
  "steps": [
    { "id": "step-1", "title": "Titre court de l'étape" },
    ...
  ]
}

Règles :
- Entre 3 et 4 étapes (5 maximum pour les tâches très complexes)
- IDs uniques : step-1, step-2, etc.
- Titres concis en français
- Couvrir : collecte Web si nécessaire, analyse, synthèse
- Adapte le plan à la complexité de la tâche`;
}

export function buildPlannerUserPrompt(
  goal: string,
  temporal: TemporalContext,
  contextHint?: string
): string {
  let prompt = `Objectif utilisateur :\n${goal}\n\n${formatTemporalContextBlock(temporal)}`;
  if (contextHint) {
    prompt += `\n\nContexte documentaire :\n${contextHint}`;
  }
  return prompt;
}

export function buildDeciderSystemPrompt(
  plan: AgentPlan,
  availableTools: string[],
  temporal: TemporalContext,
  researchBlock?: string
): string {
  const temporalBlock = formatTemporalContextBlock(temporal);

  const researchRules = researchBlock
    ? `
RÈGLES — Recherche approfondie :
1. Appuie-toi uniquement sur les sources Web collectées
2. Ne relance JAMAIS une requête déjà effectuée (consulte les observations)
3. Maximum 1-2 recherches par tour ; évite les recherches quasi-identiques
4. Si Web échoue : ne pas inventer — signaler l'impossibilité de confirmer
5. finish interdit tant qu'aucune source Web exploitable n'a été collectée
`
    : "";

  return `Tu es le décideur d'un agent IA autonome. À chaque tour, choisis la prochaine action.

Contexte temporel :
${temporalBlock}
${researchBlock ? `\n${researchBlock}\n` : ""}
${researchRules}

Plan actuel :
${formatPlanForPrompt(plan)}

Outils disponibles : ${availableTools.join(", ")}

Réponds UNIQUEMENT avec un objet JSON valide (sans markdown) :
{
  "type": "tool_calls" | "revise_plan" | "advance_step" | "finish",
  ...
}

Types de décision :

1. tool_calls — exécuter un ou plusieurs outils
   { "type": "tool_calls", "calls": [{ "tool": "web_search", "input": { "query": "..." } }], "parallel": true, "stepId": "step-2" }
   - parallel: true par défaut pour plusieurs recherches indépendantes ; false seulement si une recherche dépend d'une autre
   - stepId : étape du plan concernée
   - Pour web_search : NE PAS ajouter une année passée si l'utilisateur ne l'a pas demandée

2. advance_step — marquer une étape terminée ou ignorée
   { "type": "advance_step", "stepId": "step-1", "status": "done" }

3. revise_plan — modifier le plan si nécessaire
   { "type": "revise_plan", "steps": [{ "id": "step-3", "title": "Nouveau titre" }], "reason": "..." }

4. finish — tâche terminée, prêt pour la synthèse finale
   { "type": "finish", "reason": "Informations suffisantes collectées" }

Règles temporelles :
- Portée actuelle : rechercher des informations récentes, ne pas utiliser d'années historiques dans les requêtes
- Portée historique : respecter l'année demandée par l'utilisateur
- Vérifier la cohérence temporelle des requêtes web avant de les proposer

Règles générales :
- Utilise web_search pour toute information factuelle externe
- Préfère 1 recherche ciblée ; 2 maximum si la première est clairement insuffisante
- Interdit : enchaîner plus de 3 recherches web_search pour une question ordinaire
- Dès que tu as plusieurs sources distinctes et pertinentes : appelle finish
- Ne relance PAS une recherche « pour vérifier » si les sources couvrent déjà la question
- parallel: true pour plusieurs requêtes indépendantes dans le MÊME tour (évite la séquence await)
- Marque les étapes done au fur et à mesure
- Appelle finish dès que tu as assez d'informations VÉRIFIÉES pour répondre
- Réponds en français dans les champs texte`;
}

export function buildDeciderUserPrompt(ctx: AgentExecutionContext): string {
  const observations =
    ctx.observations.length === 0
      ? "Aucune observation pour l'instant."
      : ctx.observations
          .map(
            (o, i) =>
              `[${i + 1}] ${o.tool} (étape ${o.stepId ?? "?"}): ${o.summary}`
          )
          .join("\n");

  const temporalBlock = ctx.temporalContext
    ? formatTemporalContextBlock(ctx.temporalContext)
    : "";

  const researchBlock = ctx.researchState
    ? formatResearchBlockForDecider(ctx.researchState)
    : "";

  const freshnessBlock = ctx.freshnessState?.requiresFreshWebData
    ? formatFreshnessBlock(ctx.freshnessState)
    : "";

  const executedQueries =
    ctx.executedQueries && ctx.executedQueries.length > 0
      ? `\nRecherches déjà effectuées (ne pas relancer) :\n${ctx.executedQueries.map((q) => `- ${q}`).join("\n")}`
      : "";

  return `Objectif : ${ctx.goal}
${temporalBlock ? `\n${temporalBlock}\n` : ""}
${researchBlock ? `\n${researchBlock}\n` : ""}
${freshnessBlock ? `\nPolitique de fraîcheur (serveur) :\n${freshnessBlock}\n` : ""}
Observations accumulées :
${observations}
${executedQueries}

Itération ${ctx.stepCount + 1} / max ${ctx.limits.maxSteps}
Appels outils : ${ctx.toolCallCount} / max ${ctx.limits.maxToolCalls}

Quelle est la prochaine action ?`;
}

export function buildSynthesisSystemPrompt(
  observations: string,
  sourcesBlock: string,
  temporal: TemporalContext,
  freshnessNotes: string,
  researchContextBlock?: string,
  options?: {
    currentDataVerified: boolean;
    forceHonestResponse: boolean;
    userGoal?: string;
  }
): string {
  const temporalBlock = formatTemporalContextBlock(temporal);

  const honestyBlock = options?.forceHonestResponse
    ? `
RÉPONSE OBLIGATOIRE — Échec des recherches Web :
Tu DOIS indiquer clairement que tu ne peux PAS confirmer les informations demandées.
INTERDIT d'inventer des faits actuels à partir de ta mémoire interne.
`
    : options?.currentDataVerified === false
      ? `
ATTENTION — Données partiellement vérifiées :
- Ne présente PAS la réponse comme basée sur des données actuelles confirmées
- Signale explicitement toute donnée non vérifiable dans les sources
`
      : "";

  return `Tu es un assistant IA qui synthétise les résultats d'une enquête menée par un agent.

Contexte temporel :
${temporalBlock}
${honestyBlock}
${researchContextBlock ? `\n${researchContextBlock}\n` : ""}
${observations ? `Observations de l'agent :\n${observations}\n` : ""}
${sourcesBlock ? `${sourcesBlock}\n` : ""}
${freshnessNotes ? `${freshnessNotes}\n` : ""}

Vérification finale obligatoire :
- Les informations utilisées correspondent-elles à la période demandée ?
- Si les données sont anciennes ou contradictoires : le dire explicitement
- Ne cite pas d'année passée comme référence actuelle sauf si l'utilisateur l'a demandée
- Appuie-toi uniquement sur les sources Web fournies

Produis une réponse finale **complète** en français :
- Structure claire (titres, listes à puces, sous-sections)
- Cite les sources avec des liens
- Conclusion si demandée et SI les données le permettent
- Ne mentionne pas le fonctionnement interne de l'agent

${RESPONSE_FORMAT_INSTRUCTIONS}`;
}

function formatPlanForPrompt(plan: AgentPlan): string {
  return plan.steps
    .map((s) => {
      const icon =
        s.status === "done"
          ? "[✓]"
          : s.status === "active"
            ? "[◉]"
            : s.status === "skipped"
              ? "[—]"
              : "[ ]";
      return `${icon} ${s.id}: ${s.title}`;
    })
    .join("\n");
}

export function formatObservationsForSynthesis(
  observations: AgentExecutionContext["observations"]
): string {
  const recent = observations.slice(-6);
  return recent
    .map(
      (o) =>
        `- ${o.tool}: ${o.summary}\n  Résultat: ${JSON.stringify(o.output).slice(0, 400)}`
    )
    .join("\n");
}
