/**
 * Catalogue des modes de panne pour tests / failure injection.
 * Ne jamais activer en production — uniquement via mocks / env de test.
 */

export type FailureDomain =
  | "network"
  | "timeout"
  | "auth"
  | "database"
  | "filesystem"
  | "ai"
  | "search"
  | "streaming"
  | "validation"
  | "cancellation"
  | "infrastructure"
  | "unknown";

export type FailureModeId =
  | "empty_http_body"
  | "sqlite_down"
  | "lm_unavailable"
  | "model_not_ready"
  | "searxng_down"
  | "stream_abort"
  | "stream_cut"
  | "persist_fail"
  | "stale_response"
  | "double_submit"
  | "validation_error"
  | "docker_down"
  | "nextjs_down"
  | "tunnel_down"
  | "pc_offline"
  | "crash_loop"
  | "supervisor_unreachable";

export interface FailureContract {
  id: FailureModeId;
  domain: FailureDomain;
  requiredForStartup: boolean;
  expectedRecovery:
    | "fail_fast"
    | "degrade"
    | "retry_bounded"
    | "cancel_clean"
    | "ignore_stale"
    | "user_retry"
    | "infra_repair"
    | "wake_pc";
  userVisible: string;
}

/** Contrat de fiabilité — source de vérité pour tests et docs. */
export const FAILURE_CONTRACTS: readonly FailureContract[] = [
  {
    id: "empty_http_body",
    domain: "network",
    requiredForStartup: false,
    expectedRecovery: "user_retry",
    userVisible: "Réponse serveur vide — réessayer",
  },
  {
    id: "sqlite_down",
    domain: "database",
    requiredForStartup: true,
    expectedRecovery: "fail_fast",
    userVisible: "Base indisponible",
  },
  {
    id: "lm_unavailable",
    domain: "ai",
    requiredForStartup: false,
    expectedRecovery: "degrade",
    userVisible: "IA indisponible — Mail/Files restent utilisables",
  },
  {
    id: "model_not_ready",
    domain: "ai",
    requiredForStartup: false,
    expectedRecovery: "degrade",
    userVisible: "Modèle non prêt",
  },
  {
    id: "searxng_down",
    domain: "search",
    requiredForStartup: false,
    expectedRecovery: "degrade",
    userVisible: "Recherche web indisponible — chat local OK",
  },
  {
    id: "stream_abort",
    domain: "cancellation",
    requiredForStartup: false,
    expectedRecovery: "cancel_clean",
    userVisible: "Requête annulée — pas de faux message",
  },
  {
    id: "stream_cut",
    domain: "streaming",
    requiredForStartup: false,
    expectedRecovery: "user_retry",
    userVisible: "Stream interrompu — état cohérent + retry",
  },
  {
    id: "persist_fail",
    domain: "database",
    requiredForStartup: false,
    expectedRecovery: "fail_fast",
    userVisible: "Erreur de sauvegarde — pas de done trompeur",
  },
  {
    id: "stale_response",
    domain: "network",
    requiredForStartup: false,
    expectedRecovery: "ignore_stale",
    userVisible: "Réponse obsolète ignorée",
  },
  {
    id: "double_submit",
    domain: "validation",
    requiredForStartup: false,
    expectedRecovery: "ignore_stale",
    userVisible: "Second envoi ignoré",
  },
  {
    id: "validation_error",
    domain: "validation",
    requiredForStartup: false,
    expectedRecovery: "fail_fast",
    userVisible: "Requête invalide",
  },
  {
    id: "docker_down",
    domain: "infrastructure",
    requiredForStartup: false,
    expectedRecovery: "infra_repair",
    userVisible: "Conteneurs indisponibles — Recherche Web dégradée",
  },
  {
    id: "nextjs_down",
    domain: "infrastructure",
    requiredForStartup: true,
    expectedRecovery: "infra_repair",
    userVisible: "Chatbot hors service — réparation ciblée",
  },
  {
    id: "tunnel_down",
    domain: "infrastructure",
    requiredForStartup: false,
    expectedRecovery: "infra_repair",
    userVisible: "Connexion distante interrompue",
  },
  {
    id: "pc_offline",
    domain: "infrastructure",
    requiredForStartup: true,
    expectedRecovery: "wake_pc",
    userVisible: "PC hors ligne — allumer depuis l’app",
  },
  {
    id: "crash_loop",
    domain: "infrastructure",
    requiredForStartup: false,
    expectedRecovery: "degrade",
    userVisible: "Service instable — circuit ouvert, réessayer plus tard",
  },
  {
    id: "supervisor_unreachable",
    domain: "infrastructure",
    requiredForStartup: false,
    expectedRecovery: "degrade",
    userVisible: "Supervision locale indisponible — état partiel",
  },
] as const;

export function contractFor(id: FailureModeId): FailureContract {
  const found = FAILURE_CONTRACTS.find((c) => c.id === id);
  if (!found) {
    throw new Error(`Unknown failure mode: ${id}`);
  }
  return found;
}

/** Services optionnels au démarrage (ne doivent pas bloquer health 200). */
export const OPTIONAL_AT_STARTUP: readonly FailureModeId[] = [
  "lm_unavailable",
  "model_not_ready",
  "searxng_down",
];

export function isOptionalAtStartup(id: FailureModeId): boolean {
  return OPTIONAL_AT_STARTUP.includes(id);
}
