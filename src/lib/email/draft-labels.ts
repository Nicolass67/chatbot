import type { EmailDraftStatus } from "@/lib/email/draft/types";

type BadgeVariant = "default" | "accent" | "success" | "warning" | "error" | "muted";

export function emailDraftStatusLabel(status: EmailDraftStatus): string {
  switch (status) {
    case "draft":
      return "Brouillon";
    case "validated":
      return "Validé";
    case "sent":
      return "Envoyé";
    case "cancelled":
      return "Annulé";
    default:
      return status;
  }
}

export function emailDraftStatusVariant(status: EmailDraftStatus): BadgeVariant {
  switch (status) {
    case "validated":
      return "success";
    case "sent":
      return "accent";
    case "cancelled":
      return "muted";
    default:
      return "warning";
  }
}
