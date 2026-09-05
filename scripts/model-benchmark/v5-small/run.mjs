/**
 * Benchmark V5-small runner — Ultra-fast Small Model Lab
 *
 * node scripts/model-benchmark/v5-small/run.mjs [--smoke|--screening|--full]
 *   [--estimate-only] [--model=alias] [--skip-screening] [--skip-vision]
 *
 * Exécute UNIQUEMENT les 3 nouveaux candidats (pas les historiques V4).
 * Ne touche aucun setting de production / selectedModel.
 * Unload/load temporaire lab, puis restore du modèle initial.
 */
import path from "node:path";
import { mkdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import {
  listAvailableLlms,
  listLoadedInstances,
  unloadAll,
  loadModel,
  chatCompletion,
  modelKeysMatch,
  estimateTokens,
} from "../lm.mjs";
import { sampleSystem } from "../system.mjs";
import {
  BENCHMARK_VERSION,
  SUITE_VERSION,
  VISION_SUITE_VERSION,
  BENCHMARK_NAME,
  MODELS,
  VERIFICATION_LAYERS,
  PERF_AXES,
  HISTORICAL_ONLY,
  HISTORICAL_REFS,
  DOCTRINE,
} from "./meta.mjs";
import {
  SCREENING_CONFIGS,
  QUANT_PLAN,
  INFERENCE_DEFAULTS,
  STABILITY_REPEATS,
  SCREENING_REPEATS,
  THREADING_NOTES,
} from "./configs.mjs";
import {
  buildFullSuite,
  getScreeningSuite,
  getSmokeSuite,
  describeSuite,
} from "./suite.mjs";
import { buildVisionSuite, describeVisionSuite } from "./vision-suite.mjs";
import {
  qualityFromScored,
  aggregateRuns,
  rankConfigs,
  findDivergences,
  stabilityAcrossRepeats,
  buildCandidateVerdict,
  buildRanking,
} from "./scoring.mjs";
import { writeReports, mirrorLatest } from "./report.mjs";

const ARGS = process.argv.slice(2);
const SMOKE = ARGS.includes("--smoke");
const SCREENING_ONLY = ARGS.includes("--screening");
const SKIP_SCREENING = ARGS.includes("--skip-screening");
const SKIP_VISION = ARGS.includes("--skip-vision");
const ESTIMATE_ONLY = ARGS.includes("--estimate-only");
const MODEL_FILTER =
  (ARGS.find((a) => a.startsWith("--model=")) || "").split("=")[1] || null;

const RUN_ID = `v5-small-${new Date().toISOString().replace(/[:.]/g, "-")}`;
const OUT_ROOT = path.resolve("tmp/model-benchmark/v5-small/results");
const BUDGET_MS =
  Number(
    process.env.BENCH_V5_BUDGET_MIN ||
      (SMOKE ? 25 : SCREENING_ONLY ? 60 : 180)
  ) * 60_000;

const log = (...a) => console.log("[bench-v5-small]", ...a);
const rem = (t0) => BUDGET_MS - (Date.now() - t0);

/** @type {Array<{ modelKey: string, config?: Record<string, unknown> }>} */
let restoreSnapshot = [];

function logUnloadWarning(context) {
  const keys =
    restoreSnapshot.map((i) => i.modelKey).join(", ") || "(aucun modèle chargé)";
  log(
    `ATTENTION [${context}]: déchargement temporaire LM Studio (${keys}).`,
    "selectedModel / production NON modifiés — restore en fin de campagne."
  );
}

async function safeUnloadAll(context) {
  logUnloadWarning(context);
  return unloadAll();
}

function runLmsJson(args) {
  const result = spawnSync("lms", args, {
    encoding: "utf8",
    timeout: 60_000,
    shell: process.platform === "win32",
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  if (result.status !== 0) return null;
  try {
    const raw = String(result.stdout || "").replace(/^\uFEFF/, "");
    return JSON.parse(raw || "null");
  } catch {
    return null;
  }
}

/** Disk listing via `lms ls --json` (peut contenir BOM). */
function listDiskModels() {
  const data = runLmsJson(["ls", "--json"]);
  return Array.isArray(data) ? data : [];
}

function quantName(q) {
  return String(q || "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

/**
 * Prefère une entrée API déjà en quant voulue (ex. import standalone Q8_0).
 * Les clés hub `@q8_0` apparaissent dans `lms ls` mais ne sont souvent PAS
 * chargeables via API/CLI tant que la variante sélectionnée reste Q4.
 */
function pickPreferredKey(spec, apiHits, diskModels) {
  const preferred = quantName(spec.preferredVariant || "");
  const disk =
    diskModels.find(
      (d) =>
        spec.match(d.modelKey) ||
        (d.variants || []).some((v) => spec.match(v))
    ) || null;
  const variants = disk?.variants || [];

  if (preferred) {
    const preferredApi = apiHits.find(
      (m) => quantName(m.quantization) === preferred
    );
    if (preferredApi) {
      return {
        key: preferredApi.key,
        quantization: preferredApi.quantization,
        displayName: preferredApi.displayName,
        capabilities: preferredApi.capabilities,
        variantSource: "api_preferred_quant",
        allVariants: variants,
      };
    }
  }

  // Prefer canonical hub key if present among hits.
  const hubHit =
    apiHits.find((m) => modelKeysMatch(m.key, spec.modelKeyHint)) ||
    apiHits[0] ||
    null;
  if (hubHit) {
    return {
      key: hubHit.key,
      quantization: hubHit.quantization,
      displayName: hubHit.displayName,
      capabilities: hubHit.capabilities,
      variantSource: preferred
        ? `api_fallback_selected (wanted ${preferred})`
        : "api_selected",
      allVariants: variants,
      note: preferred
        ? `Variante ${preferred} non chargeable comme clé distincte — utilise la variante sélectionnée hub.`
        : null,
    };
  }

  if (disk?.selectedVariant || disk?.modelKey) {
    return {
      key: disk.selectedVariant || disk.modelKey,
      quantization: disk.quantization?.name ?? null,
      displayName: disk.displayName || null,
      capabilities: null,
      variantSource: "disk_selected",
      allVariants: variants,
    };
  }

  return null;
}

function resolveModels(available) {
  const diskModels = listDiskModels();
  return MODELS.map((spec) => {
    if (MODEL_FILTER && spec.alias !== MODEL_FILTER) {
      return {
        alias: spec.alias,
        role: spec.role,
        available: false,
        key: null,
        skipReason: "filtered_out",
      };
    }
    const apiHits = available.filter((m) => spec.match(m.key));
    const diskHit = diskModels.find(
      (d) =>
        spec.match(d.modelKey) ||
        (d.variants || []).some((v) => spec.match(v))
    );
    if (!apiHits.length && !diskHit) {
      return {
        alias: spec.alias,
        role: spec.role,
        available: false,
        key: null,
        skipReason: "not_found_in_lm_studio",
        modelKeyHint: spec.modelKeyHint,
        preferredVariant: spec.preferredVariant || null,
      };
    }
    const picked = pickPreferredKey(spec, apiHits, diskModels);
    return {
      alias: spec.alias,
      role: spec.role,
      available: Boolean(picked?.key),
      key: picked?.key || null,
      quantization: picked?.quantization ?? null,
      displayName: picked?.displayName || null,
      preferredVariant: spec.preferredVariant || null,
      variantSource: picked?.variantSource || null,
      allVariants: picked?.allVariants || [],
      capabilities: picked?.capabilities || null,
      modelKeyHint: spec.modelKeyHint,
      note: picked?.note || null,
    };
  });
}

function messageText(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((p) => {
        if (typeof p === "string") return p;
        if (p?.type === "text") return p.text || "";
        if (p?.type === "image_url") return "[image]";
        return "";
      })
      .join("\n");
  }
  return String(content || "");
}

function expandJobs(scenarios, repeats) {
  const jobs = [];
  for (const sc of scenarios) {
    const reps = repeats ?? sc.repeats ?? 1;
    for (let repetition = 1; repetition <= reps; repetition++) {
      jobs.push({ scenario: sc, repetition, reps });
    }
  }
  return jobs;
}

async function restoreLoaded(snapshot) {
  await safeUnloadAll("restore");
  if (!snapshot?.length) return { ok: true, restored: [] };
  const restored = [];
  for (const inst of snapshot) {
    const cfg = inst.config || {};
    const r = await loadModel(inst.modelKey, {
      contextLength: cfg.context_length ?? undefined,
      evalBatchSize: cfg.eval_batch_size ?? undefined,
      flashAttention: cfg.flash_attention ?? undefined,
      offloadKvCacheToGpu: cfg.offload_kv_cache_to_gpu ?? undefined,
      parallel: cfg.parallel ?? 1,
    });
    restored.push({ key: inst.modelKey, ok: r.ok, error: r.error });
  }
  return { ok: restored.every((x) => x.ok), restored };
}

async function runOneJob({
  modelKey,
  alias,
  configId,
  quantization,
  scenario,
  repetition,
  reps,
  requestedContext,
  effectiveConfig,
  phase,
}) {
  const inputEst = estimateTokens(
    scenario.messages.map((m) => messageText(m.content)).join("\n")
  );

  if (requestedContext && inputEst > requestedContext - 256) {
    return {
      runId: RUN_ID,
      alias,
      configId,
      modelKey,
      quantization,
      scenarioId: scenario.id,
      title: scenario.title,
      category: scenario.meta?.category,
      categories: scenario.meta?.categories || [scenario.meta?.category],
      contextTarget: scenario.meta?.contextTarget ?? 0,
      repetition,
      reps,
      phase,
      estimatedInputTokens: inputEst,
      skipped: true,
      skipReason: "input_exceeds_context_budget",
      verdict: "SKIP",
      qualityScore: null,
      genTokPerSec: null,
      latencyMs: 0,
      error: null,
      contentPreview: "",
      effectiveConfig,
      productionSettingsTouched: false,
    };
  }

  const chat = await chatCompletion({
    model: modelKey,
    messages: scenario.messages,
    maxTokens: INFERENCE_DEFAULTS.maxTokens,
    temperature: INFERENCE_DEFAULTS.temperature,
    timeoutMs: phase === "vision" ? 180_000 : 240_000,
  });

  if (!chat.ok) {
    return {
      runId: RUN_ID,
      alias,
      configId,
      modelKey,
      quantization,
      scenarioId: scenario.id,
      title: scenario.title,
      category: scenario.meta?.category,
      categories: scenario.meta?.categories || [scenario.meta?.category],
      contextTarget: scenario.meta?.contextTarget ?? 0,
      repetition,
      reps,
      phase,
      estimatedInputTokens: inputEst,
      latencyMs: chat.ms,
      verdict: "ERROR",
      qualityScore: 0,
      genTokPerSec: null,
      error: chat.error,
      contentPreview: "",
      dimensions: {},
      respondedModel: chat.respondedModel,
      modelMismatch: chat.respondedModel
        ? !modelKeysMatch(modelKey, chat.respondedModel)
        : null,
      effectiveConfig,
      productionSettingsTouched: false,
    };
  }

  const scored = scenario.score(chat.content);
  return {
    runId: RUN_ID,
    alias,
    configId,
    modelKey,
    quantization,
    scenarioId: scenario.id,
    title: scenario.title,
    category: scenario.meta?.category,
    categories: scenario.meta?.categories || [scenario.meta?.category],
    contextTarget: scenario.meta?.contextTarget ?? 0,
    repetition,
    reps,
    phase,
    estimatedInputTokens: inputEst,
    promptTokens: chat.promptTokens ?? null,
    completionTokens: chat.completionTokens ?? null,
    genTokPerSec: chat.genTokPerSec ?? null,
    latencyMs: chat.ms,
    verdict: scored.verdict,
    qualityScore: qualityFromScored(scored),
    dimensions: scored.dimensions || {},
    scoreDetails: scored.details ?? null,
    contentPreview: chat.contentPreview ?? chat.content.slice(0, 400),
    error: null,
    respondedModel: chat.respondedModel,
    finishReason: chat.finishReason ?? null,
    modelMismatch: chat.respondedModel
      ? !modelKeysMatch(modelKey, chat.respondedModel)
      : null,
    effectiveConfig,
    productionSettingsTouched: false,
  };
}

async function runJobsOnModel({ model, config, jobs, t0, label, phase }) {
  const maxScenarioCtx = Math.max(
    0,
    ...jobs.map((j) => j.scenario.meta?.contextTarget ?? 0)
  );
  const contextLength = Math.min(
    16384,
    Math.max(config.contextLength ?? 8192, maxScenarioCtx + 512)
  );
  const loadConfig = { ...config, contextLength };

  log(
    `load ${model.alias} config=${config.id} ctx=${contextLength} key=${model.key} (${label})`
  );
  const sysBefore = sampleSystem();
  await safeUnloadAll(label);
  const load = await loadModel(model.key, {
    contextLength,
    evalBatchSize: loadConfig.evalBatchSize,
    flashAttention: loadConfig.flashAttention,
    offloadKvCacheToGpu: loadConfig.offloadKvCacheToGpu,
    parallel: loadConfig.parallel ?? 1,
    gpuOffloadRatio: loadConfig.gpuOffloadRatio,
  });
  const sysAfter = sampleSystem();

  const modelMeta = {
    alias: model.alias,
    role: model.role,
    modelKey: model.key,
    quantization: load.quantization ?? model.quantization,
    displayName: model.displayName,
    configId: config.id,
    configLabel: config.label,
    rationale: config.rationale,
    requestedContext: contextLength,
    requestedEvalBatch: loadConfig.evalBatchSize,
    flashAttention: loadConfig.flashAttention,
    offloadKvCacheToGpu: loadConfig.offloadKvCacheToGpu,
    gpuOffloadRatio: loadConfig.gpuOffloadRatio,
    parallel: loadConfig.parallel ?? 1,
    loadOk: load.ok,
    loadError: load.error || load.cliError || null,
    loadTimeMs: load.loadTimeMs ?? null,
    echoLoadConfig: load.echoLoadConfig ?? null,
    effectiveConfig: load.effectiveConfig ?? null,
    metrics: {
      vramBefore: sysBefore?.vram,
      vramAfterLoad: sysAfter?.vram,
      ramAfterLoad: sysAfter?.ram,
    },
  };

  if (!load.ok) {
    log(`LOAD FAIL ${model.alias}: ${modelMeta.loadError}`);
    return { rows: [], modelMeta };
  }

  const rows = [];
  for (let i = 0; i < jobs.length; i++) {
    if (rem(t0) < 60_000) {
      log(`BUDGET low during ${label}`);
      break;
    }
    const { scenario, repetition, reps } = jobs[i];
    log(`  [${i + 1}/${jobs.length}] ${scenario.id} rep=${repetition}`);
    const row = await runOneJob({
      modelKey: load.modelKey || model.key,
      alias: model.alias,
      configId: config.id,
      quantization: load.quantization ?? model.quantization,
      scenario,
      repetition,
      reps,
      requestedContext: contextLength,
      effectiveConfig: load.effectiveConfig,
      phase,
    });
    rows.push(row);
    log(
      `    ${row.verdict} q=${row.qualityScore} ${row.latencyMs}ms tps=${row.genTokPerSec ?? "—"}`
    );
  }

  await safeUnloadAll(`${label}:cleanup`);
  return { rows, modelMeta };
}

function estimateCampaign({
  resolved,
  fullJobs,
  screeningJobs,
  visionJobs,
  runScreening,
  runVision,
}) {
  const secPer = {
    "gemma-4-e4b-qat": 1.8,
    "qwen3.5-2b": 1.2,
    "ministral-3-3b-reasoning": 1.5,
  };
  let secs = 0;
  const active = resolved.filter((m) => m.available);
  for (const m of active) {
    secs += 10; // load overhead
    const per = secPer[m.alias] || 2;
    if (runScreening) {
      secs += SCREENING_CONFIGS.length * screeningJobs * per;
    }
    secs += fullJobs * per;
    if (runVision) secs += visionJobs * (per + 1.5);
  }
  secs *= 1.2;
  return {
    modelsAvailable: active.length,
    fullJobsPerModel: fullJobs,
    screeningJobsPerConfig: screeningJobs,
    screeningConfigs: runScreening ? SCREENING_CONFIGS.length : 0,
    visionJobsPerModel: runVision ? visionJobs : 0,
    estimatedMinutes: Number((secs / 60).toFixed(1)),
    overBudget: secs * 1000 > BUDGET_MS,
    budgetMinutes: BUDGET_MS / 60_000,
  };
}

function buildDownloadManifest(resolved) {
  return resolved.map((m) => {
    const plan = QUANT_PLAN[m.alias] || {};
    return {
      alias: m.alias,
      modelKey: m.key,
      quantization: m.quantization,
      preferred: plan.preferred || m.preferredVariant || null,
      files: [plan.ggufFile, plan.mmproj].filter(Boolean),
      hub: plan.hub || null,
      visionCapability: m.capabilities?.vision ?? null,
      note: m.available
        ? `variantSource=${m.variantSource}`
        : m.skipReason || "missing",
    };
  });
}

async function main() {
  const t0 = Date.now();
  const mode = SMOKE ? "smoke" : SCREENING_ONLY ? "screening" : "full";
  log("start", RUN_ID, mode, BENCHMARK_VERSION);
  log("doctrine", DOCTRINE.gemma26bRole, "| never:", DOCTRINE.neverCallGemma26b);

  const hw = sampleSystem();
  const available = await listAvailableLlms();
  const resolved = resolveModels(available);
  for (const m of resolved) {
    log(
      m.available
        ? `RESOLVED ${m.alias} (${m.role}) -> ${m.key} quant=${m.quantization} (${m.variantSource})`
        : `SKIP ${m.alias}: ${m.skipReason}`
    );
  }

  const initialLoaded = await listLoadedInstances();
  restoreSnapshot = initialLoaded.map((i) => ({
    modelKey: i.modelKey,
    config: i.config,
  }));
  log(
    "initial_loaded",
    restoreSnapshot.map((i) => i.modelKey).join(", ") || "(none)"
  );
  if (restoreSnapshot.length) {
    log(
      "NOTE: le lab va décharger/recharger temporairement, puis restaurer:",
      restoreSnapshot.map((i) => i.modelKey).join(", ")
    );
  }

  const fullSuite = buildFullSuite();
  const suiteStats = describeSuite(fullSuite);
  const visionSuite = buildVisionSuite();
  const visionStats = describeVisionSuite(visionSuite);

  let scenarios;
  if (SMOKE) scenarios = getSmokeSuite(fullSuite);
  else if (SCREENING_ONLY) scenarios = getScreeningSuite(fullSuite);
  else scenarios = fullSuite;

  log("suite", JSON.stringify(suiteStats));
  log("vision_suite", JSON.stringify(visionStats));
  log("selected_scenarios", scenarios.length);

  const compareScenarios = SMOKE ? getSmokeSuite(fullSuite) : fullSuite;
  const compareRepeats = SMOKE ? 1 : STABILITY_REPEATS;
  const compareJobs = expandJobs(compareScenarios, compareRepeats);
  const screenScenarios = getScreeningSuite(fullSuite);
  const screenJobs = expandJobs(screenScenarios, SCREENING_REPEATS);
  const visionJobs = expandJobs(visionSuite, 1);

  const runScreening =
    !SKIP_SCREENING && !SMOKE && resolved.some((m) => m.available);
  const runVision = !SKIP_VISION && !SCREENING_ONLY;

  const estimate = estimateCampaign({
    resolved,
    fullJobs: SCREENING_ONLY ? 0 : compareJobs.length,
    screeningJobs: screenJobs.length,
    visionJobs: visionJobs.length,
    runScreening,
    runVision,
  });
  log("estimate", JSON.stringify(estimate));

  if (ESTIMATE_ONLY) {
    console.log(
      JSON.stringify(
        {
          ok: true,
          mode,
          suiteStats,
          visionStats,
          models: resolved,
          estimate,
          historicalExcluded: HISTORICAL_ONLY,
          historicalRefs: HISTORICAL_REFS,
          productionSettingsTouched: false,
          downloadManifest: buildDownloadManifest(resolved),
        },
        null,
        2
      )
    );
    return;
  }

  if (!resolved.some((m) => m.available)) {
    console.error(
      "[bench-v5-small] Aucun candidat V5-small disponible dans LM Studio"
    );
    process.exit(2);
  }

  let outDir = path.join(OUT_ROOT, RUN_ID);
  let restore = { ok: true, restored: [] };

  try {
    const allRows = [];
    const visionRows = [];
    const modelMetas = [];
    const screeningByAlias = [];
    /** @type {Record<string, object>} */
    const bestConfigByAlias = {};

    const active = resolved.filter((m) => m.available);

    // --- SCREENING per candidate ---
    if (runScreening) {
      log("=== SCREENING configs per candidat ===");
      for (const model of active) {
        if (rem(t0) < BUDGET_MS * 0.25) {
          log("BUDGET soft-stop screening");
          break;
        }
        const screenEntries = [];
        for (const cfg of SCREENING_CONFIGS) {
          if (rem(t0) < BUDGET_MS * 0.2) {
            log("BUDGET soft-stop screening configs");
            break;
          }
          const { rows, modelMeta } = await runJobsOnModel({
            model,
            config: cfg,
            jobs: screenJobs,
            t0,
            label: `screening:${model.alias}:${cfg.id}`,
            phase: "screening",
          });
          allRows.push(...rows);
          const agg = aggregateRuns(
            rows.map((r) => ({
              ...r,
              qualityScore: r.qualityScore ?? 0,
              genTokPerSec: r.genTokPerSec,
            }))
          );
          screenEntries.push({
            id: cfg.id,
            label: cfg.label,
            aggregate: agg,
            loadOk: modelMeta.loadOk,
            loadError: modelMeta.loadError,
            vramMb: modelMeta.metrics?.vramAfterLoad?.usedMb ?? null,
          });
          if (modelMeta.loadOk) {
            modelMetas.push({ ...modelMeta, phase: "screening" });
          }
        }

        const ranked = rankConfigs(
          screenEntries
            .filter((e) => e.loadOk !== false && e.aggregate.n > 0)
            .map((e) => ({
              id: e.id,
              label: e.label,
              aggregate: e.aggregate,
              vramMb: e.vramMb,
            }))
        );
        const finalist =
          SCREENING_CONFIGS.find((c) => c.id === ranked[0]?.id) ||
          SCREENING_CONFIGS[0];
        bestConfigByAlias[model.alias] = finalist;
        screeningByAlias.push({
          alias: model.alias,
          ranked: ranked.map((r) => ({
            id: r.id,
            label: r.label,
            aggregate: r.aggregate,
            vramMb: r.vramMb,
          })),
          finalist: finalist?.id || null,
          eliminated: screenEntries
            .filter((e) => e.id !== finalist?.id)
            .map((e) => ({
              id: e.id,
              reason: !e.loadOk
                ? `load_failed: ${e.loadError}`
                : "lower_quality_or_speed",
            })),
        });
        log(
          `finalist ${model.alias}:`,
          finalist?.id || "(none)",
          ranked[0]
            ? `q=${ranked[0].aggregate.qualityPct} tps=${ranked[0].aggregate.avgTokPerSec}`
            : ""
        );
      }
    } else {
      for (const model of active) {
        bestConfigByAlias[model.alias] = SCREENING_CONFIGS[0];
        log(
          `skip screening → ${model.alias} uses`,
          SCREENING_CONFIGS[0].id
        );
      }
    }

    // --- FULL text suite on best config ---
    if (!SCREENING_ONLY) {
      log(
        "=== FULL text compare ===",
        active
          .map(
            (m) =>
              `${m.alias}:${(bestConfigByAlias[m.alias] || SCREENING_CONFIGS[0]).id}`
          )
          .join(", ")
      );

      for (const model of active) {
        if (rem(t0) < 90_000) {
          log("BUDGET stop full compare");
          break;
        }
        const cfg = bestConfigByAlias[model.alias] || SCREENING_CONFIGS[0];
        const { rows, modelMeta } = await runJobsOnModel({
          model,
          config: cfg,
          jobs: compareJobs,
          t0,
          label: `full:${model.alias}:${cfg.id}`,
          phase: "full",
        });
        allRows.push(...rows);
        modelMetas.push({ ...modelMeta, phase: "full" });
      }
    }

    // --- VISION suite (scores séparés) ---
    if (runVision) {
      log("=== VISION suite (séparée) ===");
      for (const model of active) {
        if (rem(t0) < 60_000) {
          log("BUDGET stop vision");
          break;
        }
        const cfg = bestConfigByAlias[model.alias] || SCREENING_CONFIGS[0];
        // Vision needs modest context; reuse best config but cap reasonably.
        const visionConfig = {
          ...cfg,
          id: cfg.id,
          contextLength: Math.min(cfg.contextLength ?? 8192, 8192),
        };
        const { rows, modelMeta } = await runJobsOnModel({
          model,
          config: visionConfig,
          jobs: visionJobs,
          t0,
          label: `vision:${model.alias}:${cfg.id}`,
          phase: "vision",
        });
        visionRows.push(...rows);
        modelMetas.push({ ...modelMeta, phase: "vision" });
      }
    }

    const fullPhaseRows = allRows.filter((r) => r.phase === "full");
    const rowsForAgg = fullPhaseRows.length
      ? fullPhaseRows
      : allRows.filter((r) => r.phase !== "vision");

    const modelsOut = [];
    const seen = new Set();
    for (const meta of modelMetas.filter(
      (m) => m.phase === "full" || (!fullPhaseRows.length && m.phase !== "vision")
    )) {
      const key = `${meta.alias}::${meta.configId}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const rows = rowsForAgg.filter(
        (r) => r.alias === meta.alias && r.configId === meta.configId
      );
      const agg = aggregateRuns(rows);
      modelsOut.push({ ...meta, aggregate: agg });
    }

    const visionOut = [];
    const visionSeen = new Set();
    for (const meta of modelMetas.filter((m) => m.phase === "vision")) {
      if (visionSeen.has(meta.alias)) continue;
      visionSeen.add(meta.alias);
      const rows = visionRows.filter((r) => r.alias === meta.alias);
      visionOut.push({
        alias: meta.alias,
        modelKey: meta.modelKey,
        configId: meta.configId,
        loadOk: meta.loadOk,
        aggregate: aggregateRuns(rows),
      });
    }

    const verdicts = modelsOut
      .filter((m) => m.loadOk !== false)
      .map((m) => {
        const vis = visionOut.find((v) => v.alias === m.alias);
        return buildCandidateVerdict(m, vis?.aggregate || null);
      });
    const ranking = buildRanking(verdicts);

    const runsByAlias = {};
    for (const r of rowsForAgg) {
      if (!runsByAlias[r.alias]) runsByAlias[r.alias] = [];
      runsByAlias[r.alias].push(r);
    }
    const divergences = findDivergences(runsByAlias);
    const stability = stabilityAcrossRepeats(rowsForAgg);

    const notableFailures = [
      ...rowsForAgg,
      ...visionRows,
    ]
      .filter((r) => r.verdict !== "PASS" && r.verdict !== "SKIP")
      .slice(0, 50)
      .map((r) => ({
        alias: r.alias,
        scenarioId: r.scenarioId,
        phase: r.phase,
        verdict: r.verdict,
        preview: r.contentPreview,
      }));

    outDir = path.join(OUT_ROOT, RUN_ID);
    mkdirSync(outDir, { recursive: true });

    const report = {
      benchmarkName: BENCHMARK_NAME,
      benchmarkVersion: BENCHMARK_VERSION,
      suiteVersion: SUITE_VERSION,
      visionSuiteVersion: VISION_SUITE_VERSION,
      runId: RUN_ID,
      generatedAt: new Date().toISOString(),
      mode,
      elapsedMinutes: (Date.now() - t0) / 60_000,
      hardware: {
        gpu: hw?.vram?.name ?? null,
        ramTotalMb: hw?.ram?.totalMb ?? null,
        vramTotalMb: hw?.vram?.totalMb ?? null,
      },
      resolvedModels: resolved,
      suiteStats,
      visionStats,
      estimate,
      screening: screeningByAlias,
      models: modelsOut,
      vision: visionOut,
      runs: allRows,
      visionRuns: visionRows,
      totals: {
        textRequests: allRows.length,
        visionRequests: visionRows.length,
        fullRequests: fullPhaseRows.length,
        screeningRequests: allRows.filter((r) => r.phase === "screening")
          .length,
      },
      verdicts,
      ranking,
      divergences,
      stability,
      notableFailures,
      verificationLayers: VERIFICATION_LAYERS,
      perfAxes: PERF_AXES,
      threadingNotes: THREADING_NOTES,
      historicalExcluded: HISTORICAL_ONLY,
      historicalRefs: HISTORICAL_REFS,
      downloadManifest: buildDownloadManifest(resolved),
      doctrine: DOCTRINE,
      productionSettingsTouched: false,
      selectedModelChanged: false,
      note:
        "Gemma 26B-A4B = référence haute efficacité (HISTORICAL_REFS) — jamais retestée ici, jamais appelée « intermédiaire ».",
    };

    const written = writeReports(outDir, report);
    mirrorLatest(OUT_ROOT, outDir);

    log("wrote", written.mdPath);
    log("wrote", written.jsonPath);
    log("done", outDir);
    log(
      "ranking",
      (ranking.ordered || [])
        .map((o) => `#${o.rank} ${o.alias} q=${o.qualityPct} tps=${o.avgTokPerSec}`)
        .join(" | ") || "(empty)"
    );
    console.log(
      JSON.stringify(
        {
          ok: true,
          runId: RUN_ID,
          outDir,
          bestGlobal: ranking.bestGlobal?.alias || null,
          ranking: ranking.ordered,
          productionSettingsTouched: false,
        },
        null,
        2
      )
    );
  } finally {
    log("restore prior model (best effort)...");
    restore = await restoreLoaded(restoreSnapshot);
    try {
      mkdirSync(outDir, { recursive: true });
      writeFileSync(
        path.join(outDir, "RESTORE.json"),
        JSON.stringify(
          {
            initialLoaded: restoreSnapshot,
            restore,
            restoredAt: new Date().toISOString(),
          },
          null,
          2
        ),
        "utf8"
      );
    } catch (e) {
      log("WARN could not write RESTORE.json", e);
    }
    if (!restore.ok) {
      log("WARN restore incomplete", JSON.stringify(restore));
    } else {
      log(
        "restore OK",
        restore.restored?.map((r) => r.key).join(", ") || "(none)"
      );
    }
  }
}

const entry = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (/[/\\]run\.mjs$/i.test(entry)) {
  main().catch((e) => {
    console.error("[bench-v5-small] FATAL", e);
    process.exitCode = 1;
  });
}
