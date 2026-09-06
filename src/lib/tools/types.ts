import { z } from "zod";
import type { AppSettings } from "@/lib/settings/service";

import type { PolicyContext } from "@/lib/policy";

export type ToolRuntimeLocation = "local" | "remote";

export type WebSearchStatus =
  | "success"
  | "no_results"
  | "provider_error"
  | "timeout"
  | "blocked";

export interface ToolContext {
  signal: AbortSignal;
  settings: AppSettings;
  conversationId: string;
  runtimeLocation: ToolRuntimeLocation;
  /** Identifiant utilisateur (CF Access ou "local" en dev). */
  userId?: string;
  /** PJ du message utilisateur courant — auto-attachées au brouillon mail. */
  pendingAttachmentIds?: string[];
  /** Fil mail actif (assistant Mail) — injecté dans email_create_draft si le modèle omet threadId. */
  activeMailThreadId?: string;
  /** Dernier message du fil actif — pour inReplyToMessageId. */
  activeMailInReplyToMessageId?: string;
  /** Brouillon ouvert côté client — réécriture = update, pas nouveau brouillon orphelin. */
  activeDraftId?: string;
  /** Contexte policy optionnel (email OAuth, confirmation). */
  policyContext?: Partial<
    Omit<PolicyContext, "userId" | "conversationId">
  >;
  /** État taint mutable (mis à jour après lecture de données untrusted). */
  taintState?: import("@/lib/policy").TaintState;
}

export interface Tool<TInput = unknown, TOutput = unknown> {
  name: string;
  description: string;
  inputSchema: z.ZodType<TInput>;
  preferredRuntime: "local" | "remote" | "either";
  execute(input: TInput, ctx: ToolContext): Promise<TOutput>;
}

export interface SearchResult {
  title: string;
  url: string;
  domain: string;
  snippet: string;
  source?: string;
  publishedAt?: string;
}

export interface SourceFreshnessMeta {
  detectedYears: number[];
  freshness: "high" | "medium" | "low";
  warning?: string;
}

export interface SearchResultWithFreshness extends SearchResult {
  freshness?: SourceFreshnessMeta;
}

export interface WebSearchOutput {
  query: string;
  results: SearchResultWithFreshness[];
  status: WebSearchStatus;
  provider?: string;
  error?: string;
  temporalScope?: string;
  referenceDate?: string;
  freshness?: string;
}

export function zodToJsonSchema(schema: z.ZodType): Record<string, unknown> {
  if (schema instanceof z.ZodObject) {
    const shape = schema.shape;
    const properties: Record<string, unknown> = {};
    const required: string[] = [];

    for (const [key, value] of Object.entries(shape)) {
      let zodVal = value as z.ZodType;
      let optional = false;

      if (zodVal instanceof z.ZodOptional) {
        optional = true;
        zodVal = zodVal.unwrap();
      } else if (zodVal instanceof z.ZodDefault) {
        optional = true;
        zodVal = zodVal.removeDefault();
      }

      if (zodVal instanceof z.ZodString) {
        properties[key] = { type: "string", description: zodVal.description };
      } else if (zodVal instanceof z.ZodNumber) {
        properties[key] = { type: "number", description: zodVal.description };
      }

      if (!optional) required.push(key);
    }

    return { type: "object", properties, required };
  }
  return { type: "object" };
}
