# Benchmark V4 — Intermediate Model Lab

Campagne lab **9B (Ornith) vs Gemma 26B-A4B QAT vs 27B (Qwen)** pour décider si un modèle intermédiaire vaut le coup.

**Important :** ce benchmark ne modifie **jamais** `selectedModel` ni aucun réglage de production. Il décharge/recharge temporairement les modèles dans LM Studio, puis restaure l’état initial.

## Prérequis

- LM Studio en local (`http://127.0.0.1:1234`)
- Modèles téléchargés : Ornith 1.5 9B, Gemma 4 26B-A4B QAT, Qwen 3.8 27B
- `lms` CLI disponible dans le PATH

## Commandes

Depuis la racine du dépôt :

```bash
# Estimation durée (sans toucher aux modèles chargés)
node scripts/model-benchmark/v4/run.mjs --estimate-only

# Smoke rapide (~4 scénarios, 1 répétition)
node scripts/model-benchmark/v4/run.mjs --smoke

# Screening Gemma seul (6 configs × suite screening)
node scripts/model-benchmark/v4/run.mjs --screening

# Campagne complète : screening Gemma → finalistes → compare 9B / Gemma / 27B
node scripts/model-benchmark/v4/run.mjs

# Sauter le screening (utilise la config Gemma baseline)
node scripts/model-benchmark/v4/run.mjs --skip-screening

# Forcer des finalistes Gemma déjà choisis
node scripts/model-benchmark/v4/run.mjs --finalists=gemma-A-baseline-8k,gemma-B-batch256

# Un seul modèle
node scripts/model-benchmark/v4/run.mjs --model=gemma-4-26b-a4b-qat
```

## Selftest (sans LM Studio)

```bash
node scripts/model-benchmark/v4/selftest.mjs
```

## Résultats

Écrits sous `tmp/model-benchmark/v4-intermediate/results/<runId>/` :

- `REPORT.md` — verdict recommandation (lab uniquement)
- `report.json` — données complètes
- `raw/runs.json` — lignes brutes
- Miroir : `tmp/model-benchmark/v4-intermediate/latest/`

## Interprétation

Le rapport répond aux 12 questions décisives (Gemma bat-il le 9B ? sweet spot 25–40 tok/s ? etc.) et produit une recommandation **NON APPLIQUÉE** à la production.

Le Qwen 3.5 4B est exclu du classement (historique V3 uniquement).
