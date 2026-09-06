/**
 * Canal d’outil forcé par le client (composer iOS).
 * Restreint les outils exposés pour éviter web↔files↔email mal routés.
 */

import { fileIntentToTools } from "@/lib/request-router/file-intent-tools";
import type { RouteDecision } from "@/lib/request-router/types";

export type ToolChannel = "web" | "files" | "email";

export function parseToolChannel(value: unknown): ToolChannel | undefined {
  if (value === "web" || value === "files" || value === "email") {
    return value;
  }
  return undefined;
}

const EMAIL_TOOL_SET = [
  "email_get_thread",
  "email_create_draft",
  "email_list",
  "email_search",
  "email_analyze",
] as const;

function filesToolSet(): string[] {
  return Array.from(
    new Set([
      ...fileIntentToTools("search"),
      ...fileIntentToTools("list"),
      ...fileIntentToTools("read"),
      ...fileIntentToTools("analyze"),
    ])
  );
}

export interface ToolChannelCaps {
  webSearchAllowed: boolean;
  emailConnected: boolean;
  emailFeatureEnabled: boolean;
  filesConfigured: boolean;
  filesFeatureEnabled: boolean;
}

export interface ToolChannelResolution {
  route: RouteDecision;
  webSearchEnabled: boolean;
  emailEnabled: boolean;
  emailToolCandidates: string[];
  filesEnabled: boolean;
  fileToolCandidates: string[];
  /** Si true, ne pas faire de handoff mail (outils email in-chat). */
  suppressMailHandoff: boolean;
}

export function applyToolChannel(
  route: RouteDecision,
  channel: ToolChannel | undefined,
  caps: ToolChannelCaps
): ToolChannelResolution {
  if (!channel) {
    return {
      route,
      webSearchEnabled:
        caps.webSearchAllowed &&
        route.web.enabled &&
        route.web.mode !== "none",
      emailEnabled: false,
      emailToolCandidates: [],
      filesEnabled: false,
      fileToolCandidates: [],
      suppressMailHandoff: false,
    };
  }

  if (channel === "web") {
    const searchQuery =
      route.web.searchQuery?.trim() ||
      route.files.searchQuery?.trim() ||
      "";
    const next: RouteDecision = {
      ...route,
      knowledge: "current",
      web: {
        ...route.web,
        enabled: caps.webSearchAllowed,
        mode: caps.webSearchAllowed ? "required" : "none",
        mandatory: caps.webSearchAllowed,
        wouldBeUseful: caps.webSearchAllowed,
        searchType:
          route.web.searchType === "none" ? "single" : route.web.searchType,
        searchQuery,
        reason: `${route.web.reason} | canal composer=web`,
      },
      email: {
        ...route.email,
        wouldBeUseful: false,
        intent: "none",
        suggestedTools: [],
        reason: "Canal web forcé — email désactivé",
      },
      files: {
        ...route.files,
        wouldBeUseful: false,
        intent: "none",
        suggestedTools: [],
        reason: "Canal web forcé — fichiers désactivés",
      },
      tools: {
        allowToolCalling: caps.webSearchAllowed,
        candidates: caps.webSearchAllowed ? ["web_search"] : [],
      },
      execution: {
        ...route.execution,
        mode: caps.webSearchAllowed ? "tool" : route.execution.mode,
      },
    };
    return {
      route: next,
      webSearchEnabled: caps.webSearchAllowed,
      emailEnabled: false,
      emailToolCandidates: [],
      filesEnabled: false,
      fileToolCandidates: [],
      suppressMailHandoff: true,
    };
  }

  if (channel === "files") {
    const filesOk = caps.filesFeatureEnabled && caps.filesConfigured;
    const candidates = filesOk ? filesToolSet() : [];
    const searchQuery =
      route.files.searchQuery?.trim() ||
      route.web.searchQuery?.trim() ||
      "";
    const next: RouteDecision = {
      ...route,
      web: {
        ...route.web,
        mode: "none",
        mandatory: false,
        wouldBeUseful: false,
        searchType: "none",
        reason: "Canal files forcé — web désactivé",
      },
      email: {
        ...route.email,
        wouldBeUseful: false,
        intent: "none",
        suggestedTools: [],
        reason: "Canal files forcé — email désactivé",
      },
      files: {
        ...route.files,
        enabled: filesOk,
        wouldBeUseful: filesOk,
        intent: filesOk ? "search" : "none",
        suggestedTools: candidates,
        searchQuery: filesOk ? searchQuery || undefined : undefined,
        reason: filesOk
          ? `${route.files.reason} | canal composer=files`
          : "Files non configurés",
      },
      tools: {
        allowToolCalling: candidates.length > 0,
        candidates,
      },
      execution: {
        ...route.execution,
        mode: candidates.length > 0 ? "tool" : route.execution.mode,
      },
    };
    return {
      route: next,
      webSearchEnabled: false,
      emailEnabled: false,
      emailToolCandidates: [],
      filesEnabled: filesOk,
      fileToolCandidates: candidates,
      suppressMailHandoff: true,
    };
  }

  // email
  const emailOk = caps.emailFeatureEnabled && caps.emailConnected;
  const candidates = emailOk ? [...EMAIL_TOOL_SET] : [];
  const searchQuery =
    route.email.searchQuery?.trim() ||
    route.web.searchQuery?.trim() ||
    "";
  const next: RouteDecision = {
    ...route,
    web: {
      ...route.web,
      mode: "none",
      mandatory: false,
      wouldBeUseful: false,
      searchType: "none",
      reason: "Canal email forcé — web désactivé",
    },
    files: {
      ...route.files,
      wouldBeUseful: false,
      intent: "none",
      suggestedTools: [],
      reason: "Canal email forcé — fichiers désactivés",
    },
    email: {
      ...route.email,
      enabled: emailOk,
      wouldBeUseful: emailOk,
      intent: emailOk ? "search" : "none",
      suggestedTools: candidates,
      searchQuery: emailOk ? searchQuery || undefined : undefined,
      reason: emailOk
        ? `${route.email.reason} | canal composer=email`
        : "Email non connecté",
    },
    tools: {
      allowToolCalling: candidates.length > 0,
      candidates,
    },
    execution: {
      ...route.execution,
      mode: candidates.length > 0 ? "tool" : route.execution.mode,
    },
  };
  return {
    route: next,
    webSearchEnabled: false,
    emailEnabled: emailOk,
    emailToolCandidates: candidates,
    filesEnabled: false,
    fileToolCandidates: [],
    suppressMailHandoff: true,
  };
}
