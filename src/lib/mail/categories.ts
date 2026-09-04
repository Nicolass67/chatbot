export type MailCategory =
  | "primary"
  | "promotions"
  | "social"
  | "updates"
  | "sent"
  | "drafts"
  | "unread"
  | "inbox";

export interface MailCategoryDef {
  id: MailCategory;
  label: string;
  query?: string;
  labelId?: string;
}

export const MAIL_CATEGORIES: MailCategoryDef[] = [
  { id: "primary", label: "Principal", query: "category:primary" },
  { id: "promotions", label: "Promotions", query: "category:promotions" },
  { id: "social", label: "Réseaux sociaux", query: "category:social" },
  { id: "updates", label: "Notifications", query: "category:updates" },
  { id: "sent", label: "Envoyés", query: "in:sent" },
  { id: "drafts", label: "Brouillons", query: "in:drafts" },
  { id: "unread", label: "Non lus", labelId: "UNREAD" },
  { id: "inbox", label: "Boîte de réception", labelId: "INBOX" },
];

export function resolveCategoryParams(category: MailCategory): {
  query?: string;
  label?: string;
} {
  const def = MAIL_CATEGORIES.find((c) => c.id === category);
  if (!def) return { label: "INBOX" };
  return { query: def.query, label: def.labelId };
}

export function parseMailCategory(value: string | null): MailCategory {
  const found = MAIL_CATEGORIES.find((c) => c.id === value);
  return found?.id ?? "primary";
}
