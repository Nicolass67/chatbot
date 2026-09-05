/**
 * Configs V5-small — screening léger par candidat.
 * Ne touche aucun setting production.
 */

/** Configs de screening communes (petits modèles → VRAM confortable). */
export const SCREENING_CONFIGS = [
  {
    id: "A-baseline-8k",
    label: "A baseline 8K FA+KVGPU maxGPU batch512",
    contextLength: 8192,
    evalBatchSize: 512,
    flashAttention: true,
    offloadKvCacheToGpu: true,
    parallel: 1,
    gpuOffloadRatio: 1,
    rationale: "Baseline proche usage chatbot",
  },
  {
    id: "B-batch256",
    label: "B batch 256",
    contextLength: 8192,
    evalBatchSize: 256,
    flashAttention: true,
    offloadKvCacheToGpu: true,
    parallel: 1,
    gpuOffloadRatio: 1,
    rationale: "Batch plus bas — stabilité",
  },
  {
    id: "C-fa-off",
    label: "C flash attention OFF",
    contextLength: 8192,
    evalBatchSize: 512,
    flashAttention: false,
    offloadKvCacheToGpu: true,
    parallel: 1,
    gpuOffloadRatio: 1,
    rationale: "Mesurer impact FA",
  },
  {
    id: "D-12k",
    label: "D context 12K",
    contextLength: 12288,
    evalBatchSize: 512,
    flashAttention: true,
    offloadKvCacheToGpu: true,
    parallel: 1,
    gpuOffloadRatio: 1,
    rationale: "Contexte étendu pour 8K+ scenarios",
  },
];

/** Quantifications ciblées (téléchargement). Screening quant = optionnel / petit. */
export const QUANT_PLAN = {
  "gemma-4-e4b-qat": {
    preferred: "Q4_0",
    reason: "Seule variante GGUF catalogue LM Studio / HF QAT (QAT-native).",
    ggufFile: "gemma-4-E4B-it-QAT-Q4_0.gguf",
    mmproj: "mmproj-gemma-4-E4B-it-QAT-BF16.gguf",
    hub: "lmstudio-community/gemma-4-E4B-it-QAT-GGUF",
  },
  "qwen3.5-2b": {
    preferred: "Q8_0",
    reason: "Petite taille → privilégier Q8 pour qualité; alternatives Q6_K / Q4_K_M.",
    ggufFile: "Qwen3.5-2B-Q8_0.gguf",
    mmproj: "mmproj-Qwen3.5-2B-BF16.gguf",
    hub: "lmstudio-community/Qwen3.5-2B-GGUF",
    alternates: ["Q6_K", "Q4_K_M"],
  },
  "ministral-3-3b-reasoning": {
    preferred: "Q8_0",
    reason: "Petite taille → privilégier Q8 pour qualité; alternatives Q6_K / Q4_K_M.",
    ggufFile: "Ministral-3-3B-Reasoning-2512-Q8_0.gguf",
    mmproj: "mmproj-Ministral-3-3B-Reasoning-2512-F16.gguf",
    hub: "lmstudio-community/Ministral-3-3B-Reasoning-2512-GGUF",
    alternates: ["Q6_K", "Q4_K_M"],
  },
};

export const INFERENCE_DEFAULTS = {
  temperature: 0.1,
  maxTokens: 360,
  reasoningEffort: "none",
};

export const STABILITY_REPEATS = 2;
export const SCREENING_REPEATS = 1;

export const THREADING_NOTES = {
  download:
    "lms get gère le transfert; pas de flag multithread public documenté. V5 a lancé 3 `lms get` en parallèle.",
  cpuThreadsInference:
    "Non exposé dans `lms load` ni dans POST /api/v1/models/load de cette install.",
  parallelFlag:
    "`--parallel` = concurrence de prédictions, PAS le nombre de threads CPU.",
  gpuOffload: "`lms load --gpu off|max|0..1` supporté.",
};
