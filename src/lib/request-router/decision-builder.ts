import { buildWebSearchQuery } from "@/lib/tools/web-search/heuristics";
import type {
  ObjectiveContext,
  RequestContext,
  RouteDecision,
  RouteSource,
  SemanticClassification,
} from "./types";
import {
  emailIntentToTools,
  resolveEmailIntent,
  resolveEmailRouteBlock,
} from "./email-intent";
import { fileIntentToTools, resolveFileIntent } from "./file-intent-tools";

function resolveExecution(
  objective: ObjectiveContext,
  classification: SemanticClassification
): SemanticClassification["execution"] {
  if (objective.chatMode === "agent") return "agent";
  if (
    classification.web.mode === "required" &&
    classification.web.searchType === "research"
  ) {
    return "research";
  }
  if (classification.web.mode === "optional") return "tool";
  if (classification.web.mode === "required") return "direct";
  return classification.execution;
}

function resolveVision(
  objective: ObjectiveContext,
  classification: SemanticClassification
): { required: boolean; reason: string } {
  if (!objective.modelCapabilities.vision) {
    return {
      required: false,
      reason: "Le modèle actif ne supporte pas la vision.",
    };
  }
  if (classification.vision.required) {
    return {
      required: true,
      reason: objective.hasAttachments
        ? "Analyse visuelle requise pour les pièces jointes."
        : "Analyse visuelle requise par la requête.",
    };
  }
  if (objective.hasAttachments) {
    return {
      required: false,
      reason: "Pièce jointe présente mais non requise pour répondre.",
    };
  }
  return { required: false, reason: "Aucune analyse visuelle requise." };
}

function resolveTools(
  ctx: RequestContext,
  objective: ObjectiveContext,
  classification: SemanticClassification,
  executionMode: SemanticClassification["execution"]
): { allowToolCalling: boolean; candidates: string[] } {
  const candidates: string[] = [];
  if (
    objective.webSearchEnabled &&
    classification.web.mode !== "none" &&
    (classification.tools.allowToolCalling ||
      executionMode === "tool" ||
      executionMode === "research")
  ) {
    candidates.push("web_search");
  }

  const emailIntent = resolveEmailIntent(classification);
  if ((ctx.emailEnabled ?? false) && emailIntent !== "none") {
    for (const tool of emailIntentToTools(emailIntent)) {
      if (!candidates.includes(tool)) {
        candidates.push(tool);
      }
    }
  }

  const fileIntent = resolveFileIntent(classification);
  if (
    (ctx.filesEnabled ?? false) &&
    (ctx.filesConfigured ?? false) &&
    fileIntent !== "none"
  ) {
    for (const tool of fileIntentToTools(fileIntent)) {
      if (!candidates.includes(tool)) {
        candidates.push(tool);
      }
    }
  }

  const emailToolsRequested = candidates.some((tool) =>
    tool.startsWith("email_")
  );
  const fileToolsRequested = candidates.some((tool) =>
    tool.startsWith("file_")
  );

  return {
    allowToolCalling:
      candidates.length > 0 &&
      (classification.tools.allowToolCalling ||
        executionMode === "tool" ||
        executionMode === "research" ||
        emailToolsRequested ||
        fileToolsRequested),
    candidates,
  };
}

function resolveSearchQuery(
  ctx: RequestContext,
  classification: SemanticClassification
): string {
  const priors = (ctx.recentUserMessages ?? [])
    .map((m) => m.trim())
    .filter(Boolean);
  // Exclude current message if already present in recentUserMessages.
  const priorOnly =
    priors.length > 0 && priors[priors.length - 1] === ctx.message.trim()
      ? priors.slice(0, -1)
      : priors;
  const classified = classification.web.searchQuery?.trim();
  return buildWebSearchQuery({
    userMessage: ctx.message.trim(),
    route: classified ? { searchQuery: classified } : undefined,
    recentUserMessages: priorOnly,
  });
}

export function buildRouteDecision(params: {
  ctx: RequestContext;
  objective: ObjectiveContext;
  classification: SemanticClassification;
  source: RouteSource;
  latencyMs: number;
}): RouteDecision {
  const { ctx, objective, classification, source, latencyMs } = params;
  const executionMode = resolveExecution(objective, classification);
  const vision = resolveVision(objective, classification);
  const tools = resolveTools(ctx, objective, classification, executionMode);
  const email = resolveEmailRouteBlock({
    emailEnabled: ctx.emailEnabled ?? false,
    emailConnected: ctx.emailConnected ?? false,
    intent: resolveEmailIntent(classification),
    searchQuery: classification.email?.searchQuery,
    reason:
      classification.email?.intent && classification.email.intent !== "none"
        ? classification.reason
        : undefined,
  });

  const fileIntent = resolveFileIntent(classification);
  const filesEnabled = (ctx.filesEnabled ?? false) && (ctx.filesConfigured ?? false);
  const filesIntentResolved = filesEnabled ? fileIntent : "none";
  const files = {
    enabled: filesEnabled,
    wouldBeUseful: filesIntentResolved !== "none",
    intent: filesIntentResolved,
    suggestedTools:
      filesIntentResolved === "none"
        ? []
        : fileIntentToTools(filesIntentResolved),
    searchQuery:
      filesIntentResolved === "search"
        ? classification.files?.searchQuery
        : undefined,
    reason: !ctx.filesEnabled
      ? "Files désactivé."
      : !ctx.filesConfigured
        ? "Aucune root Files configurée."
        : filesIntentResolved === "none"
          ? "Pas de tâche fichiers."
          : classification.reason,
  };

  const semanticWouldBeUseful =
    classification.web.mode !== "none" ||
    classification.knowledge === "current" ||
    (!ctx.webSearchEnabled && objective.explicitWebCommand);
  const webEnabled = ctx.webSearchEnabled;
  const webMode = webEnabled ? classification.web.mode : "none";
  const searchType = webEnabled ? classification.web.searchType : "none";
  const mandatory = webMode === "required";
  const autoSearch =
    webEnabled &&
    mandatory &&
    ctx.chatMode === "chat" &&
    ctx.imageCount === 0 &&
    searchType !== "none";

  const suggestAgent =
    ctx.chatMode === "chat" &&
    searchType === "research" &&
    executionMode === "research";

  const searchQuery = resolveSearchQuery(ctx, classification);

  return {
    knowledge: classification.knowledge,
    web: {
      enabled: webEnabled,
      mode: webMode,
      searchType,
      wouldBeUseful: semanticWouldBeUseful,
      mandatory,
      autoSearch,
      searchQuery,
      reason: classification.reason,
    },
    email,
    files,
    research: {
      objective: classification.research?.objective,
    },
    execution: {
      mode: executionMode,
      suggestAgent,
    },
    vision,
    tools,
    temporal: objective.temporal,
    confidence: classification.confidence,
    source,
    reason: classification.reason,
    latencyMs,
  };
}

