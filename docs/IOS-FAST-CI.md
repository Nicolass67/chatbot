# Fast CI + Zero-Touch Deploy (iOS Native)

Boucle rapide **avant** rework Mobile 3.0 device-first : build IPA sans tests lourds → download lié au SHA → install (isideload / iLoader) → launch → screenshot.

## Architecture

| Workflow | Fichier | Contenu | Quand |
|----------|---------|---------|--------|
| **Fast QA** | `.github/workflows/ios-native-qa.yml` | xcodegen + **1** `xcodebuild` Release unsigned + IPA + `qa-meta.json` | `workflow_dispatch` / `workflow_call` uniquement (via `ios:fast-build` / `ios:deploy`) |
| **Full CI** | `.github/workflows/ios-native.yml` | Unit tests + UI tests Simulator + IPA | `push` `apps/ios/**`, PR paths, `workflow_dispatch` |

```
Modify Swift → ios:deploy
  → ios-native-qa.yml (Fast)
  → artifact chatbot-ios-native-qa-unsigned + qa-meta.json
  → verify SHA / bundle / build
  → isideload (primary) ou iLoader GUI (fallback)
  → pymobiledevice3 launch + screenshot
```

## Timings mesurés (baseline Full CI)

Run succès `33796983013` (~**4m57s** wall, runner `macos-26`) :

| Step | Durée |
|------|-------|
| Checkout + Xcode pin + SDK gate | ~10s |
| brew XcodeGen + generate | ~3s |
| **Unit tests** | **~3m32s** |
| Build Release unsigned | ~1m01s |
| Package + upload | ~3s |

Frein principal = **unit tests avant l’IPA**, pas l’archive. Les UI tests ajoutent ~1–2 min quand présents.

**Cible Fast QA** : ~**1.5–3 min** wall (sans unit/UI). Sous 3 min dépend aussi de la queue `macos-26`.

### Mesures Fast vs Full CI (runs réels)

| Run | Workflow | Job wall | Notes |
|-----|----------|----------|-------|
| Full baseline | `ios-native.yml` `33796983013` | ~4m57s | Unit ~3m32s + build ~1m01s |
| **Fast #1** | `ios-native-qa.yml` `33807323773` | **~1m30s** | SHA `fbd7d02` ; build ~1m13s |
| **Fast #2** | `ios-native-qa.yml` `33807597024` | **~1m15s** | Cache XcodeGen hit ; build ~1m05s |
| **Full #2** | `ios-native.yml` `33809232045` | **~10m28s** | Unit ~4m14s + UI ~4m44s + build ~58s |

**Verdict :** Fast QA ≈ **1.2–1.5 min** (cible 1.5–3 min **atteinte**). Full CI reste ~5 min avec unit tests.

## E2E réel (sept. 2026)

Run Fast QA `33807323773` → download SHA-bound → install sans `APPLE_ID` → **iLoader fallback (`INSTALL_HUMAN_REQUIRED`)** → launch + screenshot **PASS** (`artifacts/ios/deploy-smoke.png`).

| Étape | Résultat |
|-------|----------|
| Build Fast | YES (~1m30s) |
| Download + meta verify | YES |
| Install isideload | NO sans creds → iLoader HUMAN |
| Launch | YES |
| Screenshot | YES |

Pour zero-touch install : définir `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` (ou vault `ChatbotAppleID`).

## Commandes PC

```powershell
# Trigger Fast QA + watch + download (sans install)
npm.cmd run ios:fast-build

# Fast build + install + launch + smoke screenshot
npm.cmd run ios:deploy

# Campagne device (sans rebuild)
npm.cmd run ios:qa
```

## Artifact & metadata

- Artifact : `chatbot-ios-native-qa-unsigned`
- IPA : `ChatbotNative-unsigned.ipa`
- Meta : `qa-meta.json`

```json
{
  "git_sha": "<full sha>",
  "run_id": "<gha run id>",
  "build": "<CFBundleVersion>",
  "marketing": "3.0.0",
  "bundle_id": "fr.nicolazer.chatbot.native",
  "workflow": "qa"
}
```

`ios:deploy` **refuse** l’install si `git_sha` ≠ HEAD (ou SHA passé), ou si `bundle_id` ≠ `fr.nicolazer.chatbot.native`.

## Install

| Chemin | Outil | Codes sortie |
|--------|--------|--------------|
| **Primary** | `scripts/ios/tools/isideload-cli` (crate [isideload](https://crates.io/crates/isideload)) | `0` OK, `2` HUMAN_REQUIRED (2FA), `1` FAIL |
| **Fallback** | iLoader GUI (`C:\Program Files\iloader\iloader.exe`) | message `INSTALL_HUMAN_REQUIRED` |

Credentials (**jamais dans git**) :

- Env : `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` (ou `APPLE_PASSWORD`)
- Ou Windows Credential Manager target `ChatbotAppleID` (user = Apple ID, password = app-specific)

Signing GHA : **aucun** (`CODE_SIGNING_ALLOWED=NO`) — IPA unsigned ; le sideload free Apple ID signe sur le PC.

## MCP

Serveur `chatbot-ios-qa` :

- `ios_build_qa` — trigger + watch Fast QA
- `ios_download_artifact` — download lié au SHA
- `ios_install` — isideload / iLoader
- `ios_deploy` — compose fast-build + install + launch + screenshot

Conservés : `ios_screenshot`, `ios_hid_*`, `ios_launch`, `ios_autonomous`.

## Règle device-first

Phase UI Mobile 3.0 = **DONE** seulement après `ios:deploy` + screenshot + interaction + vision — pas après `xcodebuild` seul.

Voir aussi : [IOS-AUTONOMOUS-QA.md](./IOS-AUTONOMOUS-QA.md), [MOBILE-2.0-IMPLEMENTATION-PLAN.md](./MOBILE-2.0-IMPLEMENTATION-PLAN.md).
