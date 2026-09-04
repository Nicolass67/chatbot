# iOS Autonomous QA — boucle Cursor ↔ iPhone

Infrastructure pour que Cursor **build → déploie → observe → (interagit) → screenshot → analyse → corrige** avec le moins d’intervention humaine possible.

## Verdict architecture (sept. 2026)

**Environnement réel de ce projet :** PC Windows + iPhone USB (Apple ID gratuit / iLoader) + build iOS via GitHub Actions `macos-26` / Xcode 26.6. **Pas de Mac local.**

| Niveau | Cible | Outil | Rôle |
|--------|--------|--------|------|
| **0 — Fast QA** | IPA unsigned rapide | `ios-native-qa.yml` + `ios:deploy` | Build sans unit/UI (~cible 1.5–3 min) → download SHA-bound → install → launch → screenshot |
| **1 — rapide** | Simulator (CI) | `xcodebuild` + **XCUITest** (`ChatbotNativeUITests`) via **Full CI** `ios-native.yml` | Tap / swipe / type / a11y / screenshots en artifact |
| **2 — référence** | **iPhone physique** | **pymobiledevice3** + `scripts/ios/qa.mjs` + MCP | Launch + **screenshot réel** + HID iOS 27+ + deep links |

Détails timings / flux deploy : [IOS-FAST-CI.md](./IOS-FAST-CI.md).

### Solution retenue

1. **pymobiledevice3** (host Windows) pour USB, DDI, launch DVT, screenshots DVT, HID (iOS 27+) — **prouvé** sur iPhone iOS 27.
2. **Fast QA GHA** (`ios-native-qa.yml`) pour IPA sans tests lourds ; **Full CI** (`ios-native.yml`) garde unit + UI.
3. **Install** : primary `isideload` CLI (credentials hors git) ; fallback **iLoader GUI** si 2FA / CLI absente.
4. **XCUITest** + accessibility IDs pour automation Simulator / CI.
5. **Deep links** `chatbot-native://qa/...` pour naviguer sans HID quand besoin.
6. **MCP local** `chatbot-ios-qa` (`ios_deploy`, screenshot, HID, …).

### Alternatives écartées

| Candidat | Pourquoi écarté / limité |
|----------|---------------------------|
| **LetsView / mirroring seul** | Observation sans API agent ; pas d’automation. |
| **XcodeBuildMCP / Device Hub** | Excellent **sur Mac** ; UI automation Simulator. Ici : pas de Mac local → inutilisable au quotidien. |
| **Appium + WDA** | Contrôle physique possible mais WDA à signer/installer (Mac + profils) — incompatible SideStore unsigned sans friction. |
| **libimobiledevice `idevicescreenshot`** | Cassé iOS 17+ ; remplacé par pymobiledevice3. |
| **HID `universal-hid-service`** | Tap/swipe/type **exigent iOS 27+** — testé : erreur `Remote control requires iOS 27.0 or later` sur iOS 26.6.1. |

## Matrice de capacités (honnête)

### PHYSICAL DEVICE (iPhone USB)

| Capacité | Statut |
|----------|--------|
| Deploy (build IPA) | YES — Fast QA `ios:fast-build` / Full CI |
| Install | YES via `isideload` si creds ; sinon PARTIAL — iLoader GUI (`INSTALL_HUMAN_REQUIRED`) |
| Launch | YES (`dvt launch` + bundle resigné `*.TEAM`) |
| Screenshot | YES |
| UI tree | NO (sans WDA) |
| Tap / Swipe / Type | YES sur **iOS 27+** (validé) — NO / `BLOCKED_BY_OS` sur iOS 26 |
| Deep-link nav | YES (après unlock) |
| Face ID | MANUAL |

### SIMULATOR (GHA / Mac)

| Capacité | Statut |
|----------|--------|
| Deploy / Launch / Screenshot | YES |
| UI tree / Tap / Swipe / Type | YES (XCUITest) |
| Full control | YES |

**Règle :** `SIMULATOR VERIFIED` ≠ `PHYSICAL DEVICE VERIFIED`.

## Prérequis

### Une fois

1. iPhone USB + **Trust this computer**
2. **Developer Mode** ON (Réglages → Confidentialité → Mode développeur) — souvent déjà OK si SideStore / Xcode paired
3. Python 3.12+ : `pip install -r requirements-ios-qa.txt`
4. `gh` authentifié
5. Cursor : MCP `.cursor/mcp.json` (serveur `chatbot-ios-qa`) — recharger Cursor après ajout
6. (Optionnel Mac) XcodeBuildMCP pour boucle Simulator interactive

### À chaque session

1. iPhone **déverrouillé** (sinon screenshot noir / Face ID)
2. Câble USB stable
3. `npm.cmd run ios:mount` si screenshot/launch échoue (DDI)

## Commandes

```powershell
# Validation PC (sans device)
npm.cmd run ios:validate-pc

# Matrice / versions
npm.cmd run ios:capabilities
node scripts/ios/qa.mjs versions
node scripts/ios/qa.mjs device-info

# Device
npm.cmd run ios:mount
node scripts/ios/qa.mjs media-support
npm.cmd run ios:launch
node scripts/ios/qa.mjs screenshot mail-root
node scripts/ios/qa.mjs tap 32768 32768
node scripts/ios/qa.mjs swipe 32768 5000 32768 60000
node scripts/ios/qa.mjs type "hello"

# Deep links QA (auth requise, pas de bypass)
node scripts/ios/qa.mjs open qa/mail
node scripts/ios/qa.mjs open qa/mail/detail
node scripts/ios/qa.mjs open qa/files/documents
node scripts/ios/qa.mjs open qa/assistant/mail
node scripts/ios/qa.mjs open qa/composer

# Campagne autonome PHYSICAL DEVICE
npm.cmd run ios:autonomous
# ou
node scripts/ios/qa.mjs autonomous --label smoke27

# Fast QA → IPA → install → launch → screenshot (PHYSICAL DEVICE)
npm.cmd run ios:fast-build
npm.cmd run ios:deploy

# Full CI (unit + UI + IPA) + ancien prep iLoader seul
npm.cmd run ios:build
npm.cmd run ios:deploy-prep
```

### Flux deploy recommandé

1. `npm.cmd run ios:deploy` — déclenche `ios-native-qa.yml` sur le SHA courant, attend, télécharge, vérifie `qa-meta.json`, installe (`isideload` ou iLoader), lance, screenshot smoke.
2. Si exit `INSTALL_HUMAN_REQUIRED` : compléter dans iLoader (Apple ID), puis `npm.cmd run ios:launch` + `npm.cmd run ios:screenshot`.
3. Campagne produit : `npm.cmd run ios:qa` / `ios:autonomous` (sans rebuild).


### Smoke iOS 27 (après « L'iPhone est à jour »)

```powershell
node scripts/ios/qa.mjs device-info
node scripts/ios/qa.mjs mount
node scripts/ios/qa.mjs media-support
node scripts/ios/qa.mjs screenshot post-update
node scripts/ios/qa.mjs tap 32768 32768
node scripts/ios/qa.mjs swipe 32768 5000 32768 60000
node scripts/ios/qa.mjs type "qa"
node scripts/ios/qa.mjs launch
```

Puis lire `artifacts/ios/latest.png` et remplir PHYSICAL DEVICE CONTROL YES/NO.

Artifacts :

```
artifacts/ios/latest.png
artifacts/ios/latest-<label>.png
artifacts/ios/<timestamp>_<label>.png
artifacts/ios/qa-report-*.json
```

## Deep links QA

Schéma `chatbot-native` :

| URL | Effet |
|-----|--------|
| `chatbot-native://qa/tab/chat` | Tab Chat |
| `chatbot-native://qa/tab/mail` | Tab Mail |
| `chatbot-native://qa/tab/files` | Tab Files |
| `chatbot-native://qa/assistant/mail` | Sheet Mail Assistant |
| `chatbot-native://qa/assistant/files` | Sheet Files Assistant |
| `chatbot-native://qa/chat/new` | Nouvelle conversation |
| `chatbot-native://qa/settings` | Settings |

Bundle SideStore réel : `fr.nicolazer.chatbot.native.<TEAMID>` (détecté auto).

## Accessibility IDs

Convention dans `apps/ios/ChatbotNative/Accessibility/A11yID.swift` :

- `chat.*` — composer, send, stop, keyboard.dismiss, thinking, agent, history
- `mail.*` / `files.*` — root, assistant, settings
- `assistant.*` — sheet, close, history, context
- `navigation.tab.*`

## UI tests

Target `ChatbotNativeUITests` :

- `ChatSmokeUITests` — launch, keyboard dismiss, send
- `MailAssistantUITests` — sheet in-place (pas Chat général)
- `FilesNavigationUITests` — drill-in / back
- `HistoryIsolationUITests` — isolation general/mail/files

Lancement CI : workflow `ios-native.yml` (Simulator). Flag `-UITesting` désactive le gate Face ID.

## MCP Cursor

Fichier : `.cursor/mcp.json` → serveur `chatbot-ios-qa`.

Outils utiles :

- `ios_deploy` / `ios_build_qa` / `ios_download_artifact` / `ios_install` — Fast QA zero-touch
- `capture_ios_screen` / `ios_screenshot` / `ios_launch` / `ios_devices` / `ios_autonomous`
- `open_ios_deeplink`
- `tap_ios` / `swipe_ios` / `type_ios` → iOS 27+ ; `BLOCKED_BY_OS` sur iOS 26

Après capture, l’agent doit **lire** `artifacts/ios/latest.png` (outil Read / vision).

Voir [IOS-FAST-CI.md](./IOS-FAST-CI.md).

## Phrase magique pour l’agent

> **Teste P6 sur l’iPhone.**

Procédure attendue :

1. `ios_deploy` (Fast QA build + install + launch + screenshot) — ou `ios_status` / `ios_mount` si IPA déjà à jour
2. Si `INSTALL_HUMAN_REQUIRED` : iLoader puis `ios_launch` + `ios_screenshot`
3. `open_ios_deeplink("qa/tab/chat")` ou navigation manuelle si besoin
4. `ios_screenshot("p6-chat")`
5. Lire `artifacts/ios/latest.png` et juger (composer, keyboard dismiss, spacing)
6. Corriger le code Swift si FAIL
7. Relancer `ios_deploy` → déclarer **PHYSICAL DEVICE VERIFIED** seulement avec screenshot analysé

## Troubleshooting

| Symptôme | Action |
|----------|--------|
| `Python introuvable` | Utiliser le chemin Python312 dans MCP / `PYTHON_IOS_QA` |
| Screenshot échoue | `ios:mount` ; Developer Mode ; Trust USB |
| Launch `fr.nicolazer.chatbot.native` fail | Normal — utiliser le bundle resigné SideStore (auto) |
| Écran Face ID / noir | Déverrouiller iPhone ; ou désactiver Face ID app pour QA |
| Tap HID error iOS 27 | Attendu sur 26.x — deep links + XCUITest |
| WDA status fail | Normal sans WebDriverAgent installé |
| IPA Cap vs Native | `ios-deploy-prep` pointe native (`chatbot-ios-native-unsigned`) |

## Mac futur (optionnel)

Si un Mac Xcode 26+ arrive :

1. Installer [XcodeBuildMCP](https://www.xcodebuildmcp.com/)
2. Activer workflows `simulator` + `ui-automation` + `device`
3. Garder pymobiledevice3 Windows pour screenshots rapides USB depuis le PC Cursor
4. Device Hub (Xcode) = contrôle interactif Mac↔device, pas un remplacement CLI agent

## Fichiers clés

- `scripts/ios/qa.mjs` — CLI unique
- `scripts/ios/mcp_server.py` — MCP
- `docs/IOS-AUTONOMOUS-QA.md` — ce doc
- `apps/ios/ChatbotNativeUITests/` — UI tests
- `requirements-ios-qa.txt` — deps Python
