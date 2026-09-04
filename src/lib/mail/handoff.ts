import type { EmailIntent } from "@/lib/request-router/types";

const ALLOWED_LABELS = new Set(["INBOX", "UNREAD", "SENT", "DRAFT", "STARRED"]);
const GMAIL_ID_PATTERN = /^[a-zA-Z0-9_-]{10,30}$/;

export interface MailHandoffParams {
  intent: EmailIntent;
  query?: string;
  threadId?: string;
  label?: string;
}

/** Référence métier — le client choisit sa destination UI. */
export interface MailHandoffRef {
  intent: EmailIntent;
  query?: string;
  threadId?: string;
  label?: string;
  reason: string;
}

export interface MailHandoffResult extends MailHandoffRef {
  /** @deprecated Dérivé Web Next — préférer les IDs + resolveMailHandoffHref */
  url: string;
}

function sanitizeQuery(query: string | undefined): string | undefined {
  if (!query?.trim()) return undefined;
  const trimmed = query.trim().slice(0, 500);
  return trimmed.replace(/[<>"'`\\]/g, "");
}

function sanitizeLabel(label: string | undefined): string | undefined {
  if (!label?.trim()) return undefined;
  const upper = label.trim().toUpperCase();
  return ALLOWED_LABELS.has(upper) ? upper : undefined;
}

function sanitizeThreadId(threadId: string | undefined): string | undefined {
  if (!threadId?.trim()) return undefined;
  const trimmed = threadId.trim();
  return GMAIL_ID_PATTERN.test(trimmed) ? trimmed : undefined;
}

/** Construit le path Web `/mail…` depuis la référence métier (client React). */
export function resolveMailHandoffHref(ref: {
  intent: EmailIntent;
  query?: string;
  threadId?: string;
  label?: string;
}): string {
  const query = sanitizeQuery(ref.query);
  const label = sanitizeLabel(ref.label);
  const threadId = sanitizeThreadId(ref.threadId);

  if (ref.intent === "read_thread" && threadId) {
    return `/mail/thread/${encodeURIComponent(threadId)}`;
  }
  if (ref.intent === "search" && query) {
    return `/mail?q=${encodeURIComponent(query)}`;
  }
  if (ref.intent === "list" && label) {
    return `/mail?label=${encodeURIComponent(label)}`;
  }
  if (ref.intent === "list") {
    return "/mail?label=INBOX";
  }
  return "/mail";
}

export function buildMailHandoffUrl(params: MailHandoffParams): MailHandoffResult {
  const query = sanitizeQuery(params.query);
  const label = sanitizeLabel(params.label);
  const threadId = sanitizeThreadId(params.threadId);

  let reason = "Consultation de la section Mail.";
  if (params.intent === "read_thread" && threadId) {
    reason = "Ouverture du fil email demandé.";
  } else if (params.intent === "search" && query) {
    reason = "Recherche email demandée.";
  } else if (params.intent === "list" && label) {
    reason = "Liste de messages email demandée.";
  } else if (params.intent === "list") {
    reason = "Consultation de la boîte de réception.";
  }

  const ref: MailHandoffRef = {
    intent: params.intent,
    query,
    threadId,
    label: params.intent === "list" && !label && !threadId && !query ? "INBOX" : label,
    reason,
  };

  // list sans label → INBOX (comportement historique)
  if (params.intent === "list" && !ref.label && !ref.threadId && !ref.query) {
    ref.label = "INBOX";
  }

  return {
    ...ref,
    url: resolveMailHandoffHref(ref),
  };
}

export function handoffMessageForIntent(intent: EmailIntent): string {
  switch (intent) {
    case "list":
      return "Je vous oriente vers votre boîte mail pour consulter vos messages.";
    case "search":
      return "Je vous oriente vers la recherche dans votre boîte mail.";
    case "read_thread":
      return "Je vous oriente vers le fil de conversation email.";
    case "analyze":
      return "Je vous oriente vers Mail pour analyser vos emails avec l'assistant contextuel.";
    case "draft":
      return "Je vous oriente vers Mail pour rédiger ou préparer une réponse.";
    default:
      return "Consultez la section Mail pour gérer vos emails.";
  }
}
