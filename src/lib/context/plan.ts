import type { RouteDecision } from "@/lib/request-router/types";
import { isFollowUpTurn } from "@/lib/context/conversation-continuity";

export type HistoryMode = "minimal" | "standard" | "extended";
export type PersonalRelevance = "none" | "light" | "needed";
export type AnswerContract = "plain" | "sourced" | "personal" | "action";
export type MemoryBudget = 0 | 1 | 2 | 4 | 8;

export interface ContextPlan {
  memoryBudget: MemoryBudget;
  historyMode: HistoryMode;
  personalRelevance: PersonalRelevance;
  includeMemories: boolean;
  includeDocuments: boolean;
  includeWeb: boolean;
  preferActiveFile: boolean;
  preferActiveMail: boolean;
  expandFollowUpQuery: boolean;
  answerContract: AnswerContract;
}

export interface BuildContextPlanInput {
  route: RouteDecision;
  message: string;
  hasAttachments: boolean;
  hasActiveFile: boolean;
  hasActiveMail: boolean;
  recentUserMessages?: string[];
}

const PERSONAL_RE =
  /\b(mes? préférences?|pour moi|me convient|me conviendrait|selon moi|personnalis|à mon goût|comme d['']habitude)\b/i;

function clampMemoryBudget(n: number): MemoryBudget {
  if (n <= 0) return 0;
  if (n === 1) return 1;
  if (n <= 2) return 2;
  if (n <= 4) return 4;
  return 8;
}

/**
 * Deterministic context plan from route + light signals.
 * Distinguishes knowledge relevance vs personal relevance.
 */
export function buildContextPlan(input: BuildContextPlanInput): ContextPlan {
  const msg = input.message.trim();
  const hasPrior = (input.recentUserMessages?.length ?? 0) > 0;
  const followUp = isFollowUpTurn(msg, hasPrior);
  const personalHit = PERSONAL_RE.test(msg);

  let personalRelevance: PersonalRelevance = "none";
  if (personalHit) personalRelevance = "needed";
  else if (followUp && (input.recentUserMessages?.length ?? 0) > 0) {
    personalRelevance = "light";
  }

  const staticKnowledge = input.route.knowledge === "static";
  const webRequired = input.route.web.mode === "required";
  const webUseful = input.route.web.mode === "optional" || webRequired;
  const filesIntent = input.route.files.intent !== "none";
  const emailIntent = input.route.email.intent !== "none";

  // Toujours un budget ≥ 2 : les souvenirs stables (âge, préférences…) doivent
  // influencer chaque réponse, même sur une question factuelle « froide ».
  let memoryBudget: MemoryBudget = 4;
  if (staticKnowledge && personalRelevance === "none" && !followUp) {
    memoryBudget = 2;
  } else if (staticKnowledge && personalRelevance === "light") {
    memoryBudget = 2;
  } else if (staticKnowledge && personalRelevance === "needed") {
    memoryBudget = 4;
  } else if (webRequired && personalRelevance === "none") {
    memoryBudget = 2;
  } else if (personalRelevance === "needed") {
    memoryBudget = 4;
  }

  if (followUp && memoryBudget < 2) {
    memoryBudget = 2;
  }

  memoryBudget = clampMemoryBudget(memoryBudget);

  // Dès qu’il y a un historique utilisateur, ne jamais passer en "minimal" :
  // sinon les follow-ups longs perdent le sujet (gazinières → « modèles » LLM).
  let historyMode: HistoryMode = "standard";
  if (hasPrior) {
    historyMode =
      input.route.execution.mode === "agent" || filesIntent
        ? "extended"
        : "standard";
  } else if (
    staticKnowledge &&
    !input.hasAttachments &&
    personalRelevance === "none"
  ) {
    historyMode = "minimal";
  } else if (input.route.execution.mode === "agent" || filesIntent) {
    historyMode = "extended";
  }

  if (followUp && memoryBudget < 2) {
    memoryBudget = 2;
  }
  if (memoryBudget < 2) {
    memoryBudget = 2;
  }

  let answerContract: AnswerContract = "plain";
  if (webRequired || webUseful) answerContract = "sourced";
  else if (personalRelevance === "needed") answerContract = "personal";
  else if (emailIntent || filesIntent) answerContract = "action";

  return {
    memoryBudget,
    historyMode,
    personalRelevance,
    includeMemories: memoryBudget > 0,
    includeDocuments:
      input.hasAttachments || filesIntent || input.hasActiveFile,
    includeWeb: webUseful,
    preferActiveFile: input.hasActiveFile,
    preferActiveMail: input.hasActiveMail,
    expandFollowUpQuery: followUp,
    answerContract,
  };
}

export function historyMessageLimit(
  plan: ContextPlan,
  recentMessagesCount: number
): number {
  switch (plan.historyMode) {
    case "minimal":
      return Math.min(4, recentMessagesCount);
    case "extended":
      return Math.max(recentMessagesCount, Math.min(20, recentMessagesCount + 6));
    default:
      return recentMessagesCount;
  }
}
