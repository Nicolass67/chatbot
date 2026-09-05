/**
 * Rapport V5-small — Markdown + JSON.
 * Texte V4 et vision V5 séparés. Refs historiques = lecture seule.
 */
import { mkdirSync, writeFileSync, cpSync, existsSync, rmSync } from "node:fs";
import path from "node:path";
import {
  BENCHMARK_NAME,
  HISTORICAL_REFS,
  VERIFICATION_LAYERS,
  PERF_AXES,
  DOCTRINE,
} from "./meta.mjs";
import { THREADING_NOTES } from "./configs.mjs";

function num(n, d = 1) {
  if (n == null || Number.isNaN(n)) return "—";
  return Number(n).toFixed(d);
}

export function writeReports(outDir, report) {
  mkdirSync(outDir, { recursive: true });
  mkdirSync(path.join(outDir, "raw"), { recursive: true });

  writeFileSync(
    path.join(outDir, "report.json"),
    JSON.stringify(report, null, 2),
    "utf8"
  );
  writeFileSync(path.join(outDir, "REPORT.md"), renderMarkdown(report), "utf8");
  writeFileSync(
    path.join(outDir, "metadata.json"),
    JSON.stringify(
      {
        benchmarkVersion: report.benchmarkVersion,
        suiteVersion: report.suiteVersion,
        visionSuiteVersion: report.visionSuiteVersion,
        generatedAt: report.generatedAt,
        elapsedMinutes: report.elapsedMinutes,
        models: report.resolvedModels,
        productionSettingsTouched: false,
        selectedModelChanged: false,
        mode: report.mode,
        historicalRefsOnly: Object.keys(HISTORICAL_REFS),
        doctrine: DOCTRINE,
      },
      null,
      2
    ),
    "utf8"
  );
  writeFileSync(
    path.join(outDir, "raw", "runs.json"),
    JSON.stringify(report.runs, null, 2),
    "utf8"
  );
  if (report.visionRuns) {
    writeFileSync(
      path.join(outDir, "raw", "vision-runs.json"),
      JSON.stringify(report.visionRuns, null, 2),
      "utf8"
    );
  }
  if (report.screening) {
    writeFileSync(
      path.join(outDir, "raw", "screening.json"),
      JSON.stringify(report.screening, null, 2),
      "utf8"
    );
  }
  return {
    jsonPath: path.join(outDir, "report.json"),
    mdPath: path.join(outDir, "REPORT.md"),
  };
}

export function mirrorLatest(resultsRoot, runDir) {
  const latest = path.join(resultsRoot, "..", "latest");
  mkdirSync(path.dirname(latest), { recursive: true });
  if (existsSync(latest)) {
    try {
      rmSync(latest, { recursive: true, force: true });
    } catch {
      /* best effort */
    }
  }
  cpSync(runDir, latest, { recursive: true });
}

function renderMarkdown(r) {
  const lines = [];
  const rank = r.ranking || {};
  lines.push(`# ${r.benchmarkName || BENCHMARK_NAME}`);
  lines.push("");
  lines.push(
    `**Benchmark:** ${r.benchmarkVersion} | **Suite texte:** ${r.suiteVersion} | **Suite vision:** ${r.visionSuiteVersion}`
  );
  lines.push(`**Run ID:** \`${r.runId}\``);
  lines.push(`**Généré:** ${r.generatedAt}`);
  lines.push(
    `**Mode:** ${r.mode} | **Durée:** ${num(r.elapsedMinutes, 1)} min | **Req. texte:** ${r.totals?.textRequests ?? "—"} | **Vision:** ${r.totals?.visionRequests ?? "—"}`
  );
  lines.push(
    `**Hardware:** ${r.hardware?.gpu ?? "?"} / RAM ${r.hardware?.ramTotalMb ?? "?"} MB / VRAM ${r.hardware?.vramTotalMb ?? "?"} MB`
  );
  lines.push("");
  lines.push(
    `> LAB ONLY — production intacte (selectedModel non modifié). Aucune CI / IPA / déploiement.`
  );
  lines.push("");

  lines.push(`## 1. Classement final`);
  lines.push("");
  lines.push(`| Rang | Modèle | Qualité % | tok/s | Label |`);
  lines.push(`|------|--------|-----------|-------|-------|`);
  for (const o of rank.ordered || []) {
    lines.push(
      `| ${o.rank} | ${o.alias} | ${num(o.qualityPct)} | ${num(o.avgTokPerSec)} | ${o.label} |`
    );
  }
  lines.push("");
  lines.push(
    `- **Meilleur petit modèle global:** ${rank.bestGlobal?.alias ?? "—"} (${num(rank.bestGlobal?.qualityPct)}% / ${num(rank.bestGlobal?.avgTokPerSec)} tok/s)`
  );
  lines.push(
    `- **Meilleur pour ~100 tok/s:** ${rank.bestNear100Toks?.alias ?? "—"} (${num(rank.bestNear100Toks?.qualityPct)}% / ${num(rank.bestNear100Toks?.avgTokPerSec)} tok/s)`
  );
  lines.push(
    `- **Meilleur qualité/vitesse:** ${rank.bestQualitySpeed?.alias ?? "—"}`
  );
  lines.push(
    `- **À éliminer:** ${(rank.eliminate || []).join(", ") || "aucun"}`
  );
  lines.push("");
  lines.push(`### Remplacement Ornith 9B ?`);
  lines.push("");
  const replace = (r.verdicts || []).filter((v) =>
    String(v.questions?.can_replace_9b || "").startsWith("OUI")
  );
  if (replace.length) {
    for (const v of replace) {
      lines.push(
        `- **${v.alias}** — ${v.label} (Δqualité ${num(v.deltaQualityVsOrnith)} pts, Δtok/s ${num(v.deltaTokVsOrnith)})`
      );
    }
  } else {
    lines.push(`- Aucun candidat clair au remplacement du 9B sur ce run.`);
  }
  lines.push("");

  lines.push(`## 2. Tableau final candidats`);
  lines.push("");
  lines.push(
    `| Nouveau modèle | Qualité | Tok/s | 8K+ | Vision | Files | Web | Agent |`
  );
  lines.push(
    `|----------------|---------|-------|-----|--------|-------|-----|-------|`
  );
  for (const v of r.verdicts || []) {
    lines.push(
      `| ${v.alias} | ${num(v.qualityPct)}% | ${num(v.avgTokPerSec)} | ${num(v.long8kPct)}% | ${v.visionPct == null ? "—" : num(v.visionPct) + "%"} | ${num(v.filesPct)}% | ${num(v.webPct)}% | ${num(v.agentPct)}% |`
    );
  }
  lines.push("");

  lines.push(`## 3. Références historiques (NON retestées)`);
  lines.push("");
  lines.push(`| Réf | Rôle | Qualité | tok/s |`);
  lines.push(`|-----|------|---------|-------|`);
  for (const ref of Object.values(HISTORICAL_REFS)) {
    lines.push(
      `| ${ref.label} | ${ref.role} | ${ref.qualityPct == null ? "—" : num(ref.qualityPct) + "%"} | ${ref.avgTokPerSec == null ? "—" : num(ref.avgTokPerSec)} |`
    );
  }
  lines.push("");
  lines.push(
    `> Gemma 26B-A4B = **référence haute efficacité / haute qualité** (pas un « intermédiaire »).`
  );
  lines.push("");

  lines.push(`## 4. Comparaisons vs références`);
  lines.push("");
  for (const v of r.verdicts || []) {
    lines.push(`### ${v.alias}`);
    lines.push("");
    lines.push(
      `- vs Ornith 9B: Δqualité **${num(v.deltaQualityVsOrnith)}** pts, Δtok/s **${num(v.deltaTokVsOrnith)}**`
    );
    lines.push(
      `- vs Gemma 26B: Δqualité **${num(v.deltaQualityVsGemma26b)}** pts, Δtok/s **${num(v.deltaTokVsGemma26b)}**`
    );
    lines.push(
      `- vs Qwen 27B: Δqualité **${num(v.deltaQualityVsQwen27b)}** pts, Δtok/s **${num(v.deltaTokVsQwen27b)}**`
    );
    lines.push(`- Verdict: **${v.label}**`);
    lines.push("");
    for (const [k, val] of Object.entries(v.questions || {})) {
      lines.push(`  - ${k}: ${val}`);
    }
    lines.push("");
  }

  lines.push(`## 5. Modèles & configs exactes`);
  lines.push("");
  lines.push(
    `| Alias | Key | Quant | Ctx | Batch | FA | KV GPU | GPU | VRAM MB | tok/s | Qualité % |`
  );
  lines.push(
    `|-------|-----|-------|-----|-------|----|--------|-----|---------|-------|-----------|`
  );
  for (const m of r.models || []) {
    lines.push(
      `| ${m.alias} | \`${m.modelKey}\` | ${m.quantization ?? "—"} | ${m.requestedContext ?? "—"} | ${m.requestedEvalBatch ?? "—"} | ${m.effectiveConfig?.flash_attention ?? m.flashAttention ?? "—"} | ${m.effectiveConfig?.offload_kv_cache_to_gpu ?? m.offloadKvCacheToGpu ?? "—"} | ${m.gpuOffloadRatio ?? "—"} | ${m.metrics?.vramAfterLoad?.usedMb ?? "—"} | ${num(m.aggregate?.avgTokPerSec)} | ${num(m.aggregate?.qualityPct)} |`
    );
  }
  lines.push("");
  if (r.downloadManifest?.length) {
    lines.push(`### Fichiers GGUF / téléchargement`);
    lines.push("");
    for (const d of r.downloadManifest) {
      lines.push(
        `- **${d.alias}**: key=\`${d.modelKey}\` quant=${d.quantization} files=${(d.files || []).join(", ") || "—"} vision=${d.visionCapability} note=${d.note || "—"}`
      );
    }
    lines.push("");
  }

  if (r.screening?.length) {
    lines.push(`## 6. Screening configs`);
    lines.push("");
    for (const s of r.screening) {
      lines.push(`### ${s.alias}`);
      lines.push("");
      lines.push(`| Config | Qualité % | Pass % | tok/s | Erreurs |`);
      lines.push(`|--------|-----------|--------|-------|---------|`);
      for (const c of s.ranked || []) {
        lines.push(
          `| ${c.id} | ${num(c.aggregate.qualityPct)} | ${num(c.aggregate.passPct)} | ${num(c.aggregate.avgTokPerSec)} | ${c.aggregate.errors} |`
        );
      }
      lines.push(`Finaliste: **${s.finalist || "—"}**`);
      lines.push("");
    }
  }

  lines.push(`## 7. Scores texte par catégorie`);
  lines.push("");
  for (const m of r.models || []) {
    lines.push(`### ${m.alias}`);
    lines.push("");
    lines.push(`| Catégorie | n | Pass % | Qualité % |`);
    lines.push(`|-----------|---|--------|-----------|`);
    for (const [cat, agg] of Object.entries(m.aggregate?.byCategory || {})) {
      if (!agg.n) continue;
      lines.push(
        `| ${cat} | ${agg.n} | ${num(agg.passPct)} | ${num(agg.qualityPct)} |`
      );
    }
    lines.push("");
  }

  lines.push(`## 8. Scores par bucket de contexte`);
  lines.push("");
  lines.push(`| Modèle | ≤1k | 1k–4k | 4k–8k | 8k+ |`);
  lines.push(`|--------|-----|-------|-------|-----|`);
  for (const m of r.models || []) {
    const b = m.aggregate?.byContextBucket || {};
    lines.push(
      `| ${m.alias} | ${num(b["<=1k"]?.qualityPct)} | ${num(b["1k-4k"]?.qualityPct)} | ${num(b["4k-8k"]?.qualityPct)} | ${num(b["8k+"]?.qualityPct)} |`
    );
  }
  lines.push("");

  lines.push(`## 9. Vision (suite séparée V5-VISION)`);
  lines.push("");
  lines.push(`> Scores vision **non mélangés** aux scores texte V4.`);
  lines.push("");
  if (r.vision?.length) {
    lines.push(`| Modèle | Qualité vision % | Pass % | n | Erreurs |`);
    lines.push(`|--------|------------------|--------|---|---------|`);
    for (const v of r.vision) {
      lines.push(
        `| ${v.alias} | ${num(v.aggregate?.qualityPct)} | ${num(v.aggregate?.passPct)} | ${v.aggregate?.n ?? 0} | ${v.aggregate?.errors ?? 0} |`
      );
    }
    lines.push("");
  } else {
    lines.push(`- (pas de résultats vision)`);
  }
  lines.push("");

  lines.push(`## 10. Stabilité / erreurs`);
  lines.push("");
  lines.push(
    `- Stabilité répétitions: ${num(r.stability?.stabilityPct)}% (${r.stability?.stable ?? 0}/${r.stability?.pairs ?? 0})`
  );
  lines.push(`- Divergences inter-candidats: ${(r.divergences || []).length}`);
  lines.push("");

  lines.push(`## 11. Threading / perf axes`);
  lines.push("");
  for (const [k, v] of Object.entries(PERF_AXES)) {
    lines.push(`- **${k}:** ${v}`);
  }
  lines.push("");
  for (const [k, v] of Object.entries(THREADING_NOTES)) {
    lines.push(`- **${k}:** ${v}`);
  }
  lines.push("");

  lines.push(`## 12. Couches de vérification`);
  lines.push("");
  for (const [k, v] of Object.entries(VERIFICATION_LAYERS)) {
    lines.push(`- **${k}:** ${v}`);
  }
  lines.push("");

  lines.push(`## 13. Limites`);
  lines.push("");
  lines.push(`- Fixtures Web/Mail/Files (pas d'API live).`);
  lines.push(`- Vision = sous-suite séparée (images synthétiques PNG).`);
  lines.push(`- Threads CPU d'inférence non exposés par l'API load utilisée.`);
  lines.push(`- Historiques V4 lus uniquement — jamais rechargés pour ce run.`);
  lines.push(`- VRAM = contrainte technique, pas critère de ranking qualité.`);
  lines.push(`- Aucun changement production / selectedModel / CI / IPA.`);
  lines.push("");

  lines.push(`## 14. Échecs notables`);
  lines.push("");
  for (const f of (r.notableFailures || []).slice(0, 50)) {
    lines.push(
      `- \`${f.alias}\` / \`${f.scenarioId}\`: ${f.verdict} — ${(f.preview || "").slice(0, 120)}`
    );
  }
  if (!(r.notableFailures || []).length) lines.push(`- (aucun ou non listé)`);
  lines.push("");

  lines.push(`## 15. STOP`);
  lines.push("");
  lines.push(
    `Fin du benchmark V5-small. Aucune action production. Décision utilisateur ultérieure.`
  );
  lines.push("");
  return lines.join("\n");
}
