/**
 * Selftest V4 — sans LM Studio.
 * node scripts/model-benchmark/v4/selftest.mjs
 */
import { mkdirSync, rmSync, readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { FACTS, has, hasNumber, scoreAbsent } from "./helpers.mjs";
import {
  buildFullSuite,
  describeSuite,
  getSmokeSuite,
  getScreeningSuite,
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
import { writeReports } from "./report.mjs";
import {
  BASELINE_CONFIGS,
  GEMMA_SCREENING_CONFIGS,
} from "./configs.mjs";
import {
  BENCHMARK_VERSION,
  SUITE_VERSION,
  MODELS,
  HISTORICAL_ONLY,
} from "./meta.mjs";

let failed = 0;
function assert(cond, msg) {
  if (!cond) {
    failed += 1;
    console.error("FAIL", msg);
  } else {
    console.log("PASS", msg);
  }
}

const full = buildFullSuite();
const stats = describeSuite(full);
assert(stats.total >= 28, `suite >= 28 (got ${stats.total})`);
assert(stats.smoke >= 3, `smoke >= 3 (got ${stats.smoke})`);
assert(stats.screening >= 10, `screening >= 10 (got ${stats.screening})`);
assert(
  Object.keys(BASELINE_CONFIGS).length === 2,
  "2 baseline configs (9B + 27B)"
);
assert(
  BASELINE_CONFIGS["ornith-1.5-9b"] && BASELINE_CONFIGS["qwen3.8-27b"],
  "baseline keys match MODELS aliases"
);
assert(GEMMA_SCREENING_CONFIGS.length >= 5, "gemma screening configs present");
assert(MODELS.length === 3, "3 ranked models (no 4B)");
assert(HISTORICAL_ONLY.length >= 1, "historical 4B excluded");

const smoke = getSmokeSuite(full);
assert(smoke.every((s) => s.meta?.smoke), "smoke filter");

const screening = getScreeningSuite(full);
assert(
  screening.every((s) => s.meta?.screening),
  "screening filter"
);

const echo = full.find((s) => s.id === "L0_echo_code");
if (echo) {
  const p = echo.score(FACTS.projectCode);
  assert(p.verdict === "PASS", "L0 echo PASS");
}

const absent = full.find((s) => s.id === "L1_unsupported");
if (absent) {
  assert(absent.score("ABSENT").verdict === "PASS", "unsupported PASS on ABSENT");
}

assert(has("Budget 8500 EUR", "8500"), "has number string");
assert(hasNumber("environ 8 500 euros", "8500"), "hasNumber spaced");
assert(scoreAbsent("ABSENT", FACTS.absentCode).ok, "scoreAbsent ok");

const q = qualityFromScored({
  verdict: "PASS",
  dimensions: { factual_correctness: 1 },
});
assert(q > 0.9, "qualityFromScored high");

const mockRuns = [
  {
    alias: "ornith-1.5-9b",
    configId: "9b-8k-batch512",
    scenarioId: "L0_echo_code",
    verdict: "PASS",
    qualityScore: 1,
    category: "factual_correctness",
    categories: ["factual_correctness"],
    contextTarget: 200,
    genTokPerSec: 35,
  },
  {
    alias: "ornith-1.5-9b",
    configId: "9b-8k-batch512",
    scenarioId: "L1_budget_fact",
    verdict: "FAIL",
    qualityScore: 0,
    category: "factual_correctness",
    categories: ["factual_correctness"],
    contextTarget: 300,
    genTokPerSec: 32,
  },
  {
    alias: "gemma-4-26b-a4b-qat",
    configId: "gemma-A-baseline-8k",
    scenarioId: "L0_echo_code",
    verdict: "PASS",
    qualityScore: 1,
    category: "factual_correctness",
    categories: ["factual_correctness"],
    contextTarget: 200,
    genTokPerSec: 28,
    repetition: 1,
  },
  {
    alias: "gemma-4-26b-a4b-qat",
    configId: "gemma-A-baseline-8k",
    scenarioId: "L0_echo_code",
    verdict: "PASS",
    qualityScore: 1,
    category: "factual_correctness",
    categories: ["factual_correctness"],
    contextTarget: 200,
    genTokPerSec: 27,
    repetition: 2,
  },
];

const smallAgg = aggregateRuns(mockRuns.filter((r) => r.alias === "ornith-1.5-9b"));
const midAgg = aggregateRuns(
  mockRuns.filter((r) => r.alias === "gemma-4-26b-a4b-qat")
);
assert(smallAgg.n === 2 && smallAgg.pass === 1, "aggregate small counts");
assert(typeof midAgg.avgTokPerSec === "number", "aggregate tok/s");

const ranked = rankGemmaConfigs([
  { id: "gemma-B", aggregate: { qualityPct: 80, avgTokPerSec: 30 } },
  { id: "gemma-A", aggregate: { qualityPct: 85, avgTokPerSec: 28 } },
]);
assert(ranked[0].id === "gemma-A", "rankGemmaConfigs by quality");

const runsByAlias = {
  "ornith-1.5-9b": [mockRuns[0]],
  "gemma-4-26b-a4b-qat": [mockRuns[2]],
};
const divergences = findDivergences(runsByAlias);
assert(Array.isArray(divergences), "findDivergences array");

const stability = stabilityAcrossRepeats(mockRuns);
assert(stability.pairs >= 1, "stability pairs");

const largeAgg = { ...smallAgg, qualityPct: 92, avgTokPerSec: 18 };
const verdict = buildVerdict({ small: smallAgg, mid: midAgg, large: largeAgg });
assert(typeof verdict.intermediaireRecommended === "boolean", "buildVerdict");

const decisionAnswers = buildDecisionAnswers({
  small: smallAgg,
  mid: midAgg,
  large: largeAgg,
  bestConfigId: "gemma-A-baseline-8k",
  byCategoryCompare: {},
});
assert(decisionAnswers.q1_beats_9b, "buildDecisionAnswers");

const tmpDir = path.resolve("tmp/model-benchmark/v4-intermediate/selftest-run");
mkdirSync(tmpDir, { recursive: true });
const report = {
  benchmarkName: "V4 selftest",
  benchmarkVersion: BENCHMARK_VERSION,
  suiteVersion: SUITE_VERSION,
  runId: "v4-selftest",
  generatedAt: new Date().toISOString(),
  mode: "selftest",
  elapsedMinutes: 0,
  hardware: { gpu: "mock", ramTotalMb: 32000, vramTotalMb: 16384 },
  resolvedModels: MODELS.map((m) => ({ alias: m.alias, available: false })),
  suiteStats: stats,
  models: [
    {
      alias: "ornith-1.5-9b",
      modelKey: "mock-9b",
      configId: "9b-8k-batch512",
      aggregate: smallAgg,
      metrics: { vramAfterLoad: { usedMb: 9000 } },
    },
    {
      alias: "gemma-4-26b-a4b-qat",
      modelKey: "mock-gemma",
      configId: "gemma-A-baseline-8k",
      aggregate: midAgg,
      metrics: { vramAfterLoad: { usedMb: 14000 } },
    },
  ],
  runs: mockRuns,
  totals: { requestsExecuted: mockRuns.length, fullRequests: mockRuns.length },
  verdict,
  decisionAnswers,
  divergences,
  stability,
  notableFailures: [],
  productionSettingsTouched: false,
};
const written = writeReports(tmpDir, report);
assert(existsSync(written.mdPath), "REPORT.md written");
assert(existsSync(written.jsonPath), "report.json written");
const md = readFileSync(written.mdPath, "utf8");
assert(md.includes("Verdict"), "markdown renders verdict section");

try {
  rmSync(tmpDir, { recursive: true, force: true });
} catch {
  /* best effort */
}

assert(BENCHMARK_VERSION && SUITE_VERSION, "versions set");

console.log(failed === 0 ? "\nSELFTEST OK" : `\nSELFTEST FAILED (${failed})`);
console.log("suite", stats);
process.exit(failed === 0 ? 0 : 1);
