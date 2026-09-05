/**
 * Benchmark V4 runner — Intermediate Model Lab
 *
 * node scripts/model-benchmark/v4/run.mjs [--smoke|--screening|--full]
 *   [--estimate-only] [--model=alias] [--skip-screening]
 *   [--finalists=id1,id2]
 *
 * Ne touche aucun setting de production / selectedModel.
 * Unload/load temporaire lab, puis restore du modèle initial.
 */
import path from "node:path";
import { mkdirSync, writeFileSync } from "node:fs";
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
  BENCHMARK_NAME,
  MODELS,
  VERIFICATION_LAYERS,
  PERF_AXES,
  HISTORICAL_ONLY,
} from "./meta.mjs";
import {
  BASELINE_CONFIGS,
  GEMMA_SCREENING_CONFIGS,
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
import {
  qualityFromScored,
  aggregateRuns,
  rankGemmaConfigs,
  findDivergences,
  stabilityAcrossRepeats,
  buildVerdict,
  buildDecisionAnswers,
} from "./scoring.mjs";
import { writeReports, mirrorLatest } from "./report.mjs";

const ARGS = process.argv.slice(2);
const SMOKE = ARGS.includes("--smoke");
const SCREENING_ONLY = ARGS.includes("--screening");
const SKIP_SCREENING = ARGS.includes("--skip-screening");
const ESTIMATE_ONLY = ARGS.includes("--estimate-only");
const MODEL_FILTER =
  (ARGS.find((a) => a.startsWith("--model=")) || "").split("=")[1] || null;
const FINALISTS_ARG =
  (ARGS.find((a) => a.startsWith("--finalists=")) || "").split("=")[1] || null;

const RUN_ID = `v4-${new Date().toISOString().replace(/[:.]/g, "-")}`;
const OUT_ROOT = path.resolve("tmp/model-benchmark/v4-intermediate/results");
const BUDGET_MS =
  Number(
    process.env.BENCH_V4_BUDGET_MIN ||
      (SMOKE ? 20 : SCREENING_ONLY ? 45 : 180)
  ) * 60_000;

const log = (...a) => console.log("[bench-v4]", ...a);
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

function resolveModels(available) {
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
    const hit = available.find((m) => spec.match(m.key));
    return hit
      ? {
          alias: spec.alias,
          role: spec.role,
          available: true,
          key: hit.key,
          quantization: hit.quantization,
          displayName: hit.displayName,
        }
      : {
          alias: spec.alias,
          role: spec.role,
          available: false,
          key: null,
          skipReason: "not_found_in_lm_studio",
        };
  });
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
}) {
  const inputEst = estimateTokens(
    scenario.messages.map((m) => m.content).join("\n")
  );

  if (requestedContext && inputEst > requestedContext - 500) {
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
    timeoutMs: 240_000,
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

async function runJobsOnModel({ model, config, jobs, t0, label }) {
  log(`load ${model.alias} config=${config.id} (${label})`);
  const sysBefore = sampleSystem();
  await safeUnloadAll(label);
  const load = await loadModel(model.key, {
    contextLength: config.contextLength,
    evalBatchSize: config.evalBatchSize,
    flashAttention: config.flashAttention,
    offloadKvCacheToGpu: config.offloadKvCacheToGpu,
    parallel: config.parallel ?? 1,
    gpuOffloadRatio: config.gpuOffloadRatio,
    numExperts: config.numExperts,
  });
  const sysAfter = sampleSystem();

  const modelMeta = {
    alias: model.alias,
    role: model.role,
    modelKey: model.key,
    quantization: model.quantization,
    displayName: model.displayName,
    configId: config.id,
    configLabel: config.label,
    rationale: config.rationale,
    requestedContext: config.contextLength,
    requestedEvalBatch: config.evalBatchSize,
    flashAttention: config.flashAttention,
    offloadKvCacheToGpu: config.offloadKvCacheToGpu,
    gpuOffloadRatio: config.gpuOffloadRatio,
    parallel: config.parallel ?? 1,
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
      requestedContext: config.contextLength,
      effectiveConfig: load.effectiveConfig,
    });
    rows.push(row);
    log(
      `    ${row.verdict} q=${row.qualityScore} ${row.latencyMs}ms tps=${row.genTokPerSec ?? "—"}`
    );
  }

  await safeUnloadAll(`${label}:cleanup`);
  return { rows, modelMeta };
}

function estimateCampaign({ resolved, fullJobs, screeningJobs, runScreening }) {
  const secPer = {
    "ornith-1.5-9b": 2.8,
    "gemma-4-26b-a4b-qat": 4.5,
    "qwen3.8-27b": 7.5,
  };
  let secs = 0;
  const active = resolved.filter((m) => m.available);
  if (runScreening && active.some((m) => m.alias === "gemma-4-26b-a4b-qat")) {
    secs +=
      GEMMA_SCREENING_CONFIGS.length *
      screeningJobs *
      (secPer["gemma-4-26b-a4b-qat"] || 4);
  }
  for (const m of active) {
    secs += 12;
    secs += fullJobs * (secPer[m.alias] || 3.5);
  }
  secs *= 1.25;
  return {
    modelsAvailable: active.length,
    fullJobsPerModel: fullJobs,
    screeningJobsPerConfig: screeningJobs,
    screeningConfigs: runScreening ? GEMMA_SCREENING_CONFIGS.length : 0,
    estimatedMinutes: Number((secs / 60).toFixed(1)),
    overBudget: secs * 1000 > BUDGET_MS,
    budgetMinutes: BUDGET_MS / 60_000,
  };
}

function buildComparePlan({ small, gemma, large, finalistConfigs }) {
  const plan = [];
  if (small?.available && (!MODEL_FILTER || MODEL_FILTER === small.alias)) {
    plan.push({
      model: small,
      config: BASELINE_CONFIGS["ornith-1.5-9b"],
    });
  }
  if (gemma?.available && (!MODEL_FILTER || MODEL_FILTER === gemma.alias)) {
    for (const cfg of finalistConfigs.length
      ? finalistConfigs
      : [GEMMA_SCREENING_CONFIGS[0]]) {
      plan.push({ model: gemma, config: cfg });
    }
  }
  if (large?.available && (!MODEL_FILTER || MODEL_FILTER === large.alias)) {
    plan.push({
      model: large,
      config: BASELINE_CONFIGS["qwen3.8-27b"],
    });
  }
  return plan;
}

async function main() {
  const t0 = Date.now();
  const mode = SMOKE ? "smoke" : SCREENING_ONLY ? "screening" : "full";
  log("start", RUN_ID, mode, BENCHMARK_VERSION);

  const hw = sampleSystem();
  const available = await listAvailableLlms();
  const resolved = resolveModels(available);
  for (const m of resolved) {
    log(
      m.available
        ? `RESOLVED ${m.alias} (${m.role}) -> ${m.key} quant=${m.quantization}`
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
  let scenarios;
  if (SMOKE) scenarios = getSmokeSuite(fullSuite);
  else if (SCREENING_ONLY) scenarios = getScreeningSuite(fullSuite);
  else scenarios = fullSuite;

  log("suite", JSON.stringify(suiteStats));
  log("selected_scenarios", scenarios.length);

  const compareScenarios = SMOKE ? getSmokeSuite(fullSuite) : fullSuite;
  const compareRepeats = SMOKE ? 1 : STABILITY_REPEATS;
  const compareJobs = expandJobs(compareScenarios, compareRepeats);
  const screenScenarios = getScreeningSuite(fullSuite);
  const screenJobs = expandJobs(screenScenarios, SCREENING_REPEATS);
  const runScreening =
    !SKIP_SCREENING &&
    !SMOKE &&
    !FINALISTS_ARG &&
    resolved.some((m) => m.alias === "gemma-4-26b-a4b-qat" && m.available);

  const estimate = estimateCampaign({
    resolved,
    fullJobs: SCREENING_ONLY ? 0 : compareJobs.length,
    screeningJobs: screenJobs.length,
    runScreening,
  });
  log("estimate", JSON.stringify(estimate));

  if (ESTIMATE_ONLY) {
    console.log(
      JSON.stringify(
        {
          ok: true,
          mode,
          suiteStats,
          models: resolved,
          estimate,
          historicalExcluded: HISTORICAL_ONLY,
          productionSettingsTouched: false,
        },
        null,
        2
      )
    );
    return;
  }

  if (!resolved.some((m) => m.available)) {
    console.error("[bench-v4] Aucun modèle V4 disponible dans LM Studio");
    process.exit(2);
  }

  let outDir = path.join(OUT_ROOT, RUN_ID);
  let restore = { ok: true, restored: [] };

  try {
  const allRows = [];
  const modelMetas = [];
  let screening = null;
  let bestGemmaConfigId = null;

  const gemma = resolved.find((m) => m.alias === "gemma-4-26b-a4b-qat");
  const small = resolved.find((m) => m.alias === "ornith-1.5-9b");
  const large = resolved.find((m) => m.alias === "qwen3.8-27b");

  let finalistConfigs = [];
  if (FINALISTS_ARG) {
    finalistConfigs = FINALISTS_ARG.split(",")
      .map((s) => s.trim())
      .filter(Boolean)
      .map((id) => GEMMA_SCREENING_CONFIGS.find((c) => c.id === id))
      .filter(Boolean);
    log("finalists_from_cli", finalistConfigs.map((c) => c.id).join(", "));
  } else if (
    gemma?.available &&
    !SKIP_SCREENING &&
    !SMOKE &&
    !FINALISTS_ARG
  ) {
    log("=== SCREENING Gemma configs ===");
    const screenEntries = [];

    for (const cfg of GEMMA_SCREENING_CONFIGS) {
      if (rem(t0) < BUDGET_MS * 0.4) {
        log("BUDGET soft-stop screening");
        break;
      }
      const { rows, modelMeta } = await runJobsOnModel({
        model: gemma,
        config: cfg,
        jobs: screenJobs,
        t0,
        label: `screening:${cfg.id}`,
      });
      allRows.push(...rows.map((r) => ({ ...r, phase: "screening" })));
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
      if (modelMeta.loadOk) modelMetas.push({ ...modelMeta, phase: "screening" });
    }

    const ranked = rankGemmaConfigs(
      screenEntries
        .filter((e) => e.loadOk !== false && e.aggregate.n > 0)
        .map((e) => ({
          id: e.id,
          label: e.label,
          aggregate: e.aggregate,
          vramMb: e.vramMb,
        }))
    );
    finalistConfigs = ranked
      .slice(0, 2)
      .map((r) => GEMMA_SCREENING_CONFIGS.find((c) => c.id === r.id))
      .filter(Boolean);
    if (!finalistConfigs.length && ranked[0]) {
      finalistConfigs = [
        GEMMA_SCREENING_CONFIGS.find((c) => c.id === ranked[0].id),
      ].filter(Boolean);
    }
    bestGemmaConfigId = finalistConfigs[0]?.id || ranked[0]?.id || null;
    screening = {
      ranked: ranked.map((r) => ({
        id: r.id,
        label: r.label,
        aggregate: r.aggregate,
        vramMb: r.vramMb,
      })),
      finalists: finalistConfigs.map((c) => c.id),
      eliminated: screenEntries
        .filter((e) => !finalistConfigs.some((f) => f.id === e.id))
        .map((e) => ({
          id: e.id,
          reason: !e.loadOk
            ? `load_failed: ${e.loadError}`
            : "lower_quality_or_speed",
        })),
    };
    log("finalists", screening.finalists.join(", ") || "(none)");
  } else if (gemma?.available) {
    finalistConfigs = [GEMMA_SCREENING_CONFIGS[0]];
    bestGemmaConfigId = finalistConfigs[0].id;
    log("skip screening → use baseline", bestGemmaConfigId);
  }

  if (!SCREENING_ONLY) {
    const plan = buildComparePlan({ small, gemma, large, finalistConfigs });

    log(
      "=== FULL compare ===",
      plan.map((p) => `${p.model.alias}:${p.config.id}`).join(", ")
    );

    for (const step of plan) {
      if (rem(t0) < 90_000) {
        log("BUDGET stop full compare");
        break;
      }
      const { rows, modelMeta } = await runJobsOnModel({
        model: step.model,
        config: step.config,
        jobs: compareJobs,
        t0,
        label: `full:${step.model.alias}:${step.config.id}`,
      });
      allRows.push(...rows.map((r) => ({ ...r, phase: "full" })));
      modelMetas.push({ ...modelMeta, phase: "full" });
    }
  }

  const fullPhaseRows = allRows.filter((r) => r.phase === "full");
  const rowsForAgg = fullPhaseRows.length ? fullPhaseRows : allRows;

  const modelsOut = [];
  const seen = new Set();
  for (const meta of modelMetas.filter(
    (m) => m.phase === "full" || !fullPhaseRows.length
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

  const gemmaFull = modelsOut.filter(
    (m) => m.alias === "gemma-4-26b-a4b-qat" && m.loadOk !== false
  );
  const rankedGemmaFull = rankGemmaConfigs(
    gemmaFull.map((m) => ({ id: m.configId, aggregate: m.aggregate }))
  );
  bestGemmaConfigId = rankedGemmaFull[0]?.id || bestGemmaConfigId;
  const bestGemma = gemmaFull.find((m) => m.configId === bestGemmaConfigId);
  const smallAgg = modelsOut.find(
    (m) => m.alias === "ornith-1.5-9b"
  )?.aggregate;
  const largeAgg = modelsOut.find((m) => m.alias === "qwen3.8-27b")?.aggregate;
  const midAgg = bestGemma?.aggregate;

  const byCategoryCompare = {};
  for (const cat of Object.keys(smallAgg?.byCategory || {})) {
    byCategoryCompare[cat] = {
      small: smallAgg?.byCategory?.[cat]?.qualityPct ?? 0,
      mid: midAgg?.byCategory?.[cat]?.qualityPct ?? 0,
      large: largeAgg?.byCategory?.[cat]?.qualityPct ?? 0,
    };
  }

  const verdict = buildVerdict({
    small: smallAgg || null,
    mid: midAgg || null,
    large: largeAgg || null,
  });

  const decisionAnswers = buildDecisionAnswers({
    small: smallAgg
      ? { ...smallAgg, byContextBucket: smallAgg.byContextBucket }
      : null,
    mid: midAgg
      ? { ...midAgg, byContextBucket: midAgg.byContextBucket }
      : null,
    large: largeAgg
      ? { ...largeAgg, byContextBucket: largeAgg.byContextBucket }
      : null,
    bestConfigId: bestGemmaConfigId,
    byCategoryCompare,
  });

  const runsByAlias = {};
  for (const r of rowsForAgg) {
    if (!runsByAlias[r.alias]) runsByAlias[r.alias] = [];
    runsByAlias[r.alias].push(r);
  }
  const divergences = findDivergences(runsByAlias);
  const stability = stabilityAcrossRepeats(rowsForAgg);

  const notableFailures = rowsForAgg
    .filter((r) => r.verdict !== "PASS" && r.verdict !== "SKIP")
    .slice(0, 40)
    .map((r) => ({
      alias: r.alias,
      scenarioId: r.scenarioId,
      verdict: r.verdict,
      preview: r.contentPreview,
    }));

  outDir = path.join(OUT_ROOT, RUN_ID);
  mkdirSync(outDir, { recursive: true });

  const report = {
    benchmarkName: BENCHMARK_NAME,
    benchmarkVersion: BENCHMARK_VERSION,
    suiteVersion: SUITE_VERSION,
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
    estimate,
    screening,
    models: modelsOut,
    runs: allRows,
    totals: {
      requestsExecuted: allRows.length,
      fullRequests: fullPhaseRows.length,
    },
    verdict,
    decisionAnswers,
    divergences,
    stability,
    notableFailures,
    verificationLayers: VERIFICATION_LAYERS,
    perfAxes: PERF_AXES,
    threadingNotes: THREADING_NOTES,
    historicalExcluded: HISTORICAL_ONLY,
    productionSettingsTouched: false,
    selectedModelChanged: false,
    bestGemmaConfigId,
  };

  const written = writeReports(outDir, report);
  mirrorLatest(OUT_ROOT, outDir);

  log("wrote", written.mdPath);
  log("wrote", written.jsonPath);
  log("done", outDir);
  log(
    "verdict",
    verdict.intermediaireRecommended ? "RECOMMENDED" : "NOT_RECOMMENDED",
    verdict.reason
  );
  console.log(
    JSON.stringify(
      {
        ok: true,
        runId: RUN_ID,
        outDir,
        recommended: verdict.intermediaireRecommended,
        bestGemmaConfigId,
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
    }
  }
}

main().catch((e) => {
  console.error("[bench-v4] FATAL", e);
  process.exitCode = 1;
});
