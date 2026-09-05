/**
 * Benchmark V5-small — Ultra-fast small model lab
 * Exécute UNIQUEMENT les 3 nouveaux candidats.
 * Références V4 = historiques (jamais retestées ici).
 */
export const BENCHMARK_VERSION = "v5.0.0-small";
export const SUITE_VERSION = "suite-v4.0.0"; // même suite texte que V4
export const VISION_SUITE_VERSION = "suite-v5-vision.0.0";
export const BENCHMARK_NAME =
  "Ultra-fast Small Model Lab (Gemma E4B QAT / Qwen 3.5 2B / Ministral 3 3B Reasoning)";

/** Uniquement les 3 candidats lab — PAS les historiques. */
export const MODELS = [
  {
    alias: "gemma-4-e4b-qat",
    role: "ultra_rapide_candidat_prioritaire",
    modelKeyHint: "google/gemma-4-e4b-qat",
    match: (k) =>
      /gemma-4-e4b-qat/i.test(k) ||
      (/gemma-4-e4b/i.test(k) && /qat/i.test(k)),
  },
  {
    alias: "qwen3.5-2b",
    role: "ultra_petit_candidat",
    modelKeyHint: "qwen/qwen3.5-2b",
    preferredVariant: "q8_0",
    match: (k) =>
      /^qwen3\.5-2b(-0)?$/i.test(k) ||
      /^qwen\/qwen3\.5-2b(@.*)?$/i.test(k) ||
      /qwen3\.5-2b/i.test(k),
  },
  {
    alias: "ministral-3-3b-reasoning",
    role: "ultra_compact_reasoning",
    modelKeyHint: "mistralai/ministral-3-3b-reasoning",
    preferredVariant: "q8_0",
    match: (k) =>
      /^ministral-3-3b-reasoning(-0)?$/i.test(k) ||
      /^mistralai\/ministral-3-3b-reasoning(@.*)?$/i.test(k) ||
      (/ministral-3-3b/i.test(k) && /reasoning/i.test(k)),
  },
];

/**
 * Références historiques V4 — NE PAS retester.
 * Source: tmp/model-benchmark/v4-intermediate/latest (run v4-2026-09-05T22-54-32-951Z)
 */
export const HISTORICAL_REFS = {
  "ornith-1.5-9b": {
    alias: "ornith-1.5-9b",
    role: "historique_petit_a_remplacer",
    label: "Ornith 1.5 9B Q8_0",
    qualityPct: 73.4,
    avgTokPerSec: 64.2,
    passPct: 73.4,
    sourceRunId: "v4-2026-09-05T22-54-32-951Z",
    note: "Ancien petit modèle utilisateur — candidat au remplacement.",
  },
  "gemma-4-26b-a4b-qat": {
    alias: "gemma-4-26b-a4b-qat",
    role: "reference_haute_efficacite",
    label: "Gemma 4 26B-A4B QAT Q4_0",
    qualityPct: 96.9,
    avgTokPerSec: 60.5,
    passPct: 96.9,
    sourceRunId: "v4-2026-09-05T22-54-32-951Z",
    note: "Référence haute qualité / haute efficacité — PAS un intermédiaire.",
  },
  "qwen3.8-27b": {
    alias: "qwen3.8-27b",
    role: "reference_gros",
    label: "Qwen 3.8 27B IQ3_S",
    qualityPct: 93.8,
    avgTokPerSec: 30.1,
    passPct: 93.8,
    sourceRunId: "v4-2026-09-05T22-54-32-951Z",
    note: "Référence gros modèle.",
  },
  "qwen3.5-4b": {
    alias: "qwen3.5-4b",
    role: "historique_uniquement",
    label: "Qwen 3.5 4B Q8_0",
    qualityPct: null,
    avgTokPerSec: null,
    sourceRunId: "v3",
    note: "Historique uniquement — hors classement utilisateur.",
  },
};

export const HISTORICAL_ONLY = Object.values(HISTORICAL_REFS).map((r) => ({
  alias: r.alias,
  role: r.role,
  note: r.note,
}));

export const VERIFICATION_LAYERS = {
  CODE_VERIFIED: "Harness / scoring déterministe (suite V4 réutilisée)",
  PIPELINE_VERIFIED: "Load/unload LM Studio lab + chat + persistance",
  REAL_LLM_VERIFIED: "Réponses des 3 nouveaux modèles locaux réellement interrogés",
  REAL_WEB_VERIFIED: false,
  REAL_MAIL_VERIFIED: false,
  REAL_FILES_VERIFIED: false,
  REAL_VISION_VERIFIED:
    "Sous-suite V5-VISION séparée (images injectées via API chat)",
  NOTE: "Web/Mail/Files = fixtures texte V4. Vision = suite séparée, scores NON mélangés au texte V4. CPU threads non exposés par l'API load.",
};

export const PERF_AXES = {
  A_download_parallelism:
    "lms get: pas de flag multithread public; 3 téléchargements parallèles utilisés. Threads internes non documentés/réglables.",
  B_cpu_threads_inference:
    "Threads CPU d'inférence — NON exposés dans lms load / API load utilisés ici.",
  C_inference_parallel:
    "parallel = prédictions concurrentes (lms --parallel), pas des threads CPU.",
  D_gpu_offload: "Ratio offload GPU via lms load --gpu off|max|0..1",
  E_kv_cache: "offload_kv_cache_to_gpu via API load",
  F_vision:
    "mmproj / vision input — validé par injection image réelle (pas capability déclarative seule).",
};

export const DOCTRINE = {
  rankingOrder: [
    "QUALITÉ / COHÉRENCE / COMPRÉHENSION",
    "TOK/S",
    "STABILITÉ",
    "RESSOURCES (faisabilité seulement)",
  ],
  targetTokPerSec: 100,
  gemma26bRole: "reference_haute_efficacite",
  neverCallGemma26b: "intermediaire",
  production: "JAMAIS modifier selectedModel / production",
};
