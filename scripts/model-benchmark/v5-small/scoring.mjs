/**
 * Scoring V5-small — agrégats V4 + verdict ultra-rapide vs refs historiques.
 */
import {
  qualityFromScored,
  aggregateRuns,
  findDivergences,
  stabilityAcrossRepeats,
} from "../v4/scoring.mjs";
import { HISTORICAL_REFS } from "./meta.mjs";

export {
  qualityFromScored,
  aggregateRuns,
  findDivergences,
  stabilityAcrossRepeats,
};

export function rankConfigs(entries) {
  return [...entries].sort((a, b) => {
    const q = (b.aggregate.qualityPct ?? 0) - (a.aggregate.qualityPct ?? 0);
    if (Math.abs(q) >= 0.5) return q;
    return (b.aggregate.avgTokPerSec ?? 0) - (a.aggregate.avgTokPerSec ?? 0);
  });
}

function catPct(agg, cat) {
  return agg?.byCategory?.[cat]?.qualityPct ?? null;
}

function bucketPct(agg, key) {
  return agg?.byContextBucket?.[key]?.qualityPct ?? null;
}

export function labelCandidate({ qualityPct, avgTokPerSec, visionPct, long8k }) {
  const ornith = HISTORICAL_REFS["ornith-1.5-9b"];
  const gemma = HISTORICAL_REFS["gemma-4-26b-a4b-qat"];
  const q = qualityPct ?? 0;
  const t = avgTokPerSec ?? 0;

  if (q >= ornith.qualityPct + 5 && t >= ornith.avgTokPerSec * 0.9) {
    if (q >= gemma.qualityPct - 5) {
      return "recommandé comme remplacement du 9B (proche référence Gemma 26B)";
    }
    return "recommandé comme remplacement du 9B";
  }
  if (q >= ornith.qualityPct + 2 && t >= 70) {
    return "intéressant — meilleur que 9B en qualité, à valider";
  }
  if (t >= 90 && q < ornith.qualityPct - 5) {
    return "trop faible (rapide mais nettement moins intelligent que le 9B)";
  }
  if (t < 50 && q < ornith.qualityPct) return "trop lent et trop faible";
  if (t < 50) return "trop lent pour la cible ultra-rapide";
  if (visionPct != null && visionPct < 40 && q >= ornith.qualityPct) {
    return "excellent mais vision faible";
  }
  if (long8k != null && long8k < 50 && q >= ornith.qualityPct - 2) {
    return "intéressant mais long-context faible";
  }
  if (q < ornith.qualityPct - 5) return "trop faible";
  return "intéressant mais insuffisant";
}

export function buildCandidateVerdict(modelOut, visionAgg = null) {
  const ornith = HISTORICAL_REFS["ornith-1.5-9b"];
  const gemma = HISTORICAL_REFS["gemma-4-26b-a4b-qat"];
  const qwen27 = HISTORICAL_REFS["qwen3.8-27b"];
  const agg = modelOut.aggregate || {};
  const q = agg.qualityPct ?? 0;
  const t = agg.avgTokPerSec ?? 0;
  const visionPct = visionAgg?.qualityPct ?? null;
  const long8k = bucketPct(agg, "8k+");

  return {
    alias: modelOut.alias,
    modelKey: modelOut.modelKey,
    quantization: modelOut.quantization,
    configId: modelOut.configId,
    qualityPct: q,
    avgTokPerSec: t,
    passPct: agg.passPct ?? null,
    long8kPct: long8k,
    visionPct,
    filesPct: catPct(agg, "files_grounding"),
    webPct: catPct(agg, "web_grounding"),
    mailPct: catPct(agg, "mail_grounding"),
    agentPct: catPct(agg, "agent_planning"),
    deltaQualityVsOrnith: Math.round((q - ornith.qualityPct) * 10) / 10,
    deltaTokVsOrnith: Math.round((t - ornith.avgTokPerSec) * 10) / 10,
    deltaQualityVsGemma26b: Math.round((q - gemma.qualityPct) * 10) / 10,
    deltaTokVsGemma26b: Math.round((t - gemma.avgTokPerSec) * 10) / 10,
    deltaQualityVsQwen27b: Math.round((q - qwen27.qualityPct) * 10) / 10,
    deltaTokVsQwen27b: Math.round((t - qwen27.avgTokPerSec) * 10) / 10,
    label: labelCandidate({
      qualityPct: q,
      avgTokPerSec: t,
      visionPct,
      long8k,
    }),
    questions: {
      beats_9b: q > ornith.qualityPct + 1 ? "OUI" : "NON",
      by_how_much: `${Math.round((q - ornith.qualityPct) * 10) / 10} pts qualité`,
      faster: t >= ornith.avgTokPerSec ? "OUI" : "NON",
      better_long_context:
        long8k != null && long8k > 40 ? `8k+=${long8k}%` : `faible (${long8k}%)`,
      better_web: (catPct(agg, "web_grounding") ?? 0) >= 70 ? "solide" : "faible",
      better_files:
        (catPct(agg, "files_grounding") ?? 0) >= 70 ? "solide" : "faible",
      better_agent:
        (catPct(agg, "agent_planning") ?? 0) >= 70 ? "solide" : "faible",
      vision:
        visionPct == null
          ? "non mesuré / échec injection"
          : visionPct >= 60
            ? `OK (${visionPct}%)`
            : `faible (${visionPct}%)`,
      can_replace_9b:
        q > ornith.qualityPct + 5 && t >= ornith.avgTokPerSec * 0.9
          ? "OUI (candidat)"
          : "NON",
      close_to_gemma26b:
        q >= gemma.qualityPct - 5
          ? "proche"
          : `écart ${Math.round((gemma.qualityPct - q) * 10) / 10} pts`,
    },
  };
}

export function buildRanking(verdicts) {
  const ranked = [...verdicts].sort((a, b) => {
    const q = (b.qualityPct ?? 0) - (a.qualityPct ?? 0);
    if (Math.abs(q) >= 0.5) return q;
    return (b.avgTokPerSec ?? 0) - (a.avgTokPerSec ?? 0);
  });
  const near100 = [...verdicts]
    .filter((v) => (v.avgTokPerSec ?? 0) >= 80)
    .sort((a, b) => {
      const q = (b.qualityPct ?? 0) - (a.qualityPct ?? 0);
      if (Math.abs(q) >= 0.5) return q;
      return (
        Math.abs(100 - (a.avgTokPerSec ?? 0)) -
        Math.abs(100 - (b.avgTokPerSec ?? 0))
      );
    });
  const qualitySpeed = [...verdicts].sort((a, b) => {
    const score = (v) =>
      (v.qualityPct ?? 0) * 0.7 + Math.min(v.avgTokPerSec ?? 0, 120) * 0.3;
    return score(b) - score(a);
  });
  const eliminate = ranked.filter(
    (v) =>
      (v.qualityPct ?? 0) < HISTORICAL_REFS["ornith-1.5-9b"].qualityPct - 5 ||
      ((v.avgTokPerSec ?? 0) < 50 &&
        (v.qualityPct ?? 0) < HISTORICAL_REFS["ornith-1.5-9b"].qualityPct)
  );

  return {
    bestGlobal: ranked[0] || null,
    bestNear100Toks: near100[0] || null,
    bestQualitySpeed: qualitySpeed[0] || null,
    second: ranked[1] || null,
    third: ranked[2] || null,
    eliminate: eliminate.map((e) => e.alias),
    ordered: ranked.map((r, i) => ({
      rank: i + 1,
      alias: r.alias,
      qualityPct: r.qualityPct,
      avgTokPerSec: r.avgTokPerSec,
      label: r.label,
    })),
  };
}
