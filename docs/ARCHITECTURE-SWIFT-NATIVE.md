# Architecture study — React/Next (Web) + SwiftUI (iOS) clients

**Date :** 2026-09-03  
**Scope :** évaluation uniquement — **aucune réécriture Swift** dans ce document.  
**Repo audité :** `D:\Chatbot` (Next.js 15 App Router, SQLite/Drizzle, Worker Cloudflare, shell Capacitor iOS).  
**Plan d’exécution B0/B :** [`docs/IMPLEMENTATION-PLAN-B0-B.md`](./IMPLEMENTATION-PLAN-B0-B.md) (attente validation avant implémentation).

---

## 0. Résumé exécutif

Le backend actuel est **déjà largement client-agnostique** : ~34k LOC dans `src/lib/**`, ~52 routes HTTP sous `src/app/api/**`, orchestrateur chat SSE typé (`OrchestratorEvent`), auth JWT Cloudflare Access vérifiée serveur, Mail/Files/Memory via APIs + `pending_actions`.

Le client iOS actuel (Capacitor) **ne contient quasiment pas de logique** (~49 LOC Swift générées ; UI = React remote). Passer à SwiftUI signifie **réécrire toute l’UI iPhone**, pas le serveur.

**Verdict court :** techniquement viable et cohérent avec l’architecture “backend sur PC”, **mais prématuré** tant que Capacitor + Access + Gmail OAuth + perf démarrage ne sont pas stabilisés. Priorité : **contrats API + SSE gelés**, puis shell SwiftUI Chat uniquement.

---

## 1. Architecture actuelle

### 1.1 Structure

| Zone | Rôle | Ordre de grandeur |
|------|------|-------------------|
| `src/lib/**` | Métier (agent, mail, files, memory, auth, tools, db) | ~34k LOC, 271 fichiers |
| `src/components/**` | UI React | ~17k LOC |
| `src/app/**` | Pages + routes API | ~4.7k LOC |
| `workers/chatbot/**` | Edge proxy VPC, wake, offline | ~3k LOC |
| `ios/**` | Coquille Capacitor | négligeable |
| `www/**` | Fallback HTML Capacitor | minimal |
| `docs/**` | Runbooks déploiement / iOS / email E2E | — |

Pas de monorepo `apps/` aujourd’hui : **une app Next** qui sert à la fois UI Web et API.

### 1.2 Séparation frontend / backend

- **Bonne :** mutations dangereuses (send mail, trash, FS) → libs serveur + table `pending_actions` (`src/lib/actions/service.ts`).
- **Faible côté “contrat” :** pas d’OpenAPI ; types TypeScript consommés seulement par React ; validation Zod **par route** (ex. `src/app/api/chat/route.ts`).
- **UI grasse :** `ChatView.tsx` (~1.3k L) orchestre SSE, optimistic UI, regenerate — logique **présentationnelle** mais dense ; le métier durable reste dans `src/lib/agent/orchestrator.ts`.

### 1.3 Auth

```
Client → Cloudflare Access (edge)
      → JWT Cf-Access-Jwt-Assertion
      → src/middleware.ts (Edge) vérifie via JWKS (src/lib/auth/cloudflare-access.ts)
      → injecte x-user-id
      → routes API : withAuth(apiAuthGuard, …)
```

Dev local : `CF_ACCESS_ENABLED=false` → `x-user-id: local`.  
Health : Bearer `HEALTH_CHECK_TOKEN` bypass.

### 1.4 Chat SSE

- `POST /api/chat` → `ReadableStream` SSE (`data: {json}\n\n` + heartbeat `: ping` 15s).
- Client Web : `fetch` + `ReadableStream` (**pas** `EventSource`) — adapté à Swift `URLSession.bytes`.
- Union discriminée : `src/lib/agent/events.ts` (`token`, `done`, `error`, `sources`, `agent_*`, handoffs mail/files, etc.).

### 1.5 Données (SQLite / Drizzle)

Schéma unique : `src/lib/db/schema.ts` — conversations, messages, attachments, memories (+ FTS), oauth_accounts, email_drafts, pending_actions, file_roots / file_references / index, agent_runs, app_settings, …

Runtime : `better-sqlite3` + `src/lib/db/index.ts` — **Node-only**, reste sur le PC.

### 1.6 Domaines métier (fichiers pivots)

| Domaine | Serveur | UI React |
|---------|---------|----------|
| Chat | `src/lib/agent/*`, `src/lib/chat/*`, `src/app/api/chat`, `…/conversations/**` | `src/components/chat/*` |
| Mail | `src/lib/mail/*`, `src/lib/email/*`, `src/lib/integrations/email/gmail/*` | `src/components/mail/*`, `src/app/mail/*` |
| Files | `src/lib/files/*` (PathGuard, index, mutations) | `src/components/files/*` |
| Memory | `src/lib/memory/*`, `src/app/api/memories/**` | settings memory |
| Web search | `src/lib/tools/web-search/*` | toggles + `WebSearchActivity` |
| Native shell | — | `src/components/native/*` + Capacitor |

### 1.7 Capacitor aujourd’hui

- Stratégie A : `server.url` = origin publique ; contenu 100 % remote.
- `allowNavigation` : Access + Google IdP (login dans WKWebView).
- IPA unsigned → SideStore ; rebuild seulement si natif change.

---

## 2. Compatibilité client Swift

### 2.1 Réutilisable tel quel (serveur)

- Tout `src/lib/**` métier + SQLite + LM Studio + Gmail API + SearXNG + orchestrateur.
- Worker Cloudflare (proxy / wake) — indépendant du client.
- Routes API HTTP/JSON + SSE chat.
- Politique de confirmation (`pending_actions`).

### 2.2 À exposer / stabiliser comme contrats

| Besoin Swift | État actuel | Action |
|--------------|-------------|--------|
| Liste conversations | `GET /api/conversations` | Documenter schéma réponse |
| Messages | `GET /api/conversations/[id]/messages` | Idem + pagination éventuelle |
| Chat stream | `POST /api/chat` SSE | Versionner `OrchestratorEvent` |
| Mail list/thread | `/api/mail/**` | Contrats REST |
| Files list/search/content | `/api/files/**` | Binary streaming PDF/images |
| Settings / models | `/api/settings`, `/api/runtime/**`, `/api/lm-studio/**` | — |
| Auth identity | header `x-user-id` après Access | Session native Access (voir §6) |

### 2.3 À refactorer (client-agnostique)

1. **Extraire / publier** les types d’événements SSE et DTOs API hors “imports React”.
2. **Éliminer les handoffs URL-only** (`mail_handoff.url`, `files_handoff.url`) ou les compléter avec des **IDs structurés** (threadId, rootId) — Swift ne doit pas parser des routes Next.
3. **Uniformiser erreurs JSON** (`{ error, code }`) sur toutes les routes.
4. **Séparer** `src/lib/client/*` (fetch navigateur) du contrat serveur.
5. Optionnel : découper `src/app` (UI) vs package `api` si monorepo — **pas obligatoire** tant que les routes restent stables.

### 2.4 Dépendant React / browser (ne pas porter)

- Composants `src/components/**`, Markdown React, glass CSS, drawers.
- `apiFetch`, `openExternal`, Capacitor plugins, `visualViewport`, Web Share.
- Optimistic UI / cache messages côté client (`conversation-messages-cache`).

### 2.5 Dépendant Node (reste serveur)

- `better-sqlite3`, filesystem PathGuard Windows, LM Studio HTTP local, googleapis, indexation fichiers, chiffrement tokens OAuth, Worker wake Freebox.

---

## 3. Chat → SwiftUI

| Capacité | API actuelle | Swift | Gap |
|----------|--------------|-------|-----|
| Liste conversations | `GET /api/conversations` | `List` + NavigationStack | Faible |
| Messages | `GET …/messages` | LazyVStack | Faible |
| Streaming | SSE `token` / `done` / `error` | `URLSession` streaming | Moyen (parser SSE) |
| Stop | Abort request | `task.cancel()` | Faible |
| Regenerate / edit | body `regenerate`, `editMessageId` | Idem | Faible |
| Markdown / code | HTML côté React | AttributedString / lib Markdown | **HIGH** (qualité) |
| Sources | event `sources` | Cards + SafariView | Moyen |
| PJ | upload + ids dans POST chat | PhotosPicker / Files | Moyen |
| Auto-scroll / clavier | UIKit/SwiftUI | `ScrollViewReader` + keyboard safe area | Moyen |
| Background | abort SSE (Capacitor event) | `scenePhase` → cancel | Faible |
| Agent UI | events `agent_*` | Panels natifs | Moyen–High |
| Handoffs mail/files | URLs Next | **IDs** + navigation Swift | À refactor API |

**Verdict SSE :** le protocole est **suffisamment propre** pour Swift **si** on fige un schéma versionné de `OrchestratorEvent` (OpenAPI ou JSON Schema) et on évite les handoffs “URL Next only”.

---

## 4. Mail

| Concern | Serveur (garder) | Swift (UI) |
|---------|------------------|------------|
| OAuth Gmail | Start/callback/token store | ASWebAuthenticationSession ou SafariView → callback HTTPS |
| Sessions Gmail | Tokens chiffrés SQLite | Aucun secret local |
| Threads / search / read | `/api/mail/**` | Listes / détail natifs |
| Drafts / validate / send | `/api/email/**` + confirm token | Sheets de confirmation UIKit-like |
| Trash confirm | pending_actions | Idem |
| PJ Gmail | `/attachment` | Quick Look |
| Règles sécurité | policy + audit log | Affichage erreurs `code` |
| Assistant mail | `/api/mail/ai/**` | Vue conversation secondaire |

**Ne pas** faire OAuth “natif Google SDK” si le serveur gère déjà le flow web — garder **un seul** redirect URI serveur.

---

## 5. Files

| Concern | Serveur | Swift |
|---------|---------|-------|
| PathGuard / roots / index | Obligatoire serveur (FS PC) | — |
| list / search / content | API | Navigation + preview |
| PDF / images | content API ou stream | `PDFKit` / `QuickLook` |
| Upload | multipart API | `fileImporter` |
| Mutations | propose → confirm | Alertes natives |
| Permissions | roots autorisées serveur | Ne jamais exposer chemins absolus PC à l’aveugle |

iPhone = **client distant** du FS Windows, pas un miroir offline du disque.

---

## 6. Authentification Swift native + Cloudflare Access

Le modèle Capacitor (cookies WKWebView partagés avec la WebView app) **ne se transpose pas** tel quel à une app URLSession.

### Options (recommandation)

| Option | Description | Fit |
|--------|-------------|-----|
| **A. ASWebAuthenticationSession / SFSafariViewController** pour Access login, puis extraction cookie/`CF_Authorization` | Proche du web | Fragile (cookies HttpOnly) |
| **B. Access Service Token** (Client ID/Secret) pour app “device” | Pas d’OTP user | Mauvais pour usage perso multi-user ; secrets sur device |
| **C. Couche session app** : après Access (WebAuth), échange contre **token app** (`/api/auth/session`) Bearer longue durée liée userId | Clean pour URLSession | **Recommandé** (petit endpoint à ajouter) |
| **D. Rester sur WebView login-only** puis injecter Authorization | Hybride | OK phase C |

**Recommandation :** Phase B/C — endpoint `POST /api/auth/exchange` (ou similaire) qui, avec JWT Access valide, émet un **refresh/access token app** stocké Keychain ; toutes les API Swift utilisent `Authorization: Bearer`. Web continue cookies Access.  
Deep links : `fr.nicolazer.chatbot://oauth/...` seulement si nécessaire pour OAuth Gmail ; Access team domain reste HTTPS.

Logout : révoquer token app + clear Keychain ; Access logout via URL team si besoin.

---

## 7. API contracts

**Aujourd’hui :** Zod local + types TS internes — **insuffisant** pour un 2ᵉ client.

### Recommandation pragmatique (sans monorepo artificiel)

1. Package léger **`packages/api-contracts`** (ou `contracts/`) :
   - JSON Schema / OpenAPI 3.1 généré ou maintenu pour :
     - `OrchestratorEvent`
     - Conversations / Messages DTOs
     - Mail / Files / pending_actions
   - `zod` sources de vérité → export OpenAPI (`zod-to-openapi` ou hand-written OpenAPI synced by CI).
2. **Génération Swift :** `swift-openapi-generator` ou OpenAPI Generator → `APIClient` + models.
3. **Validation serveur :** garder Zod aligné sur le même schéma (test CI “contracts drift”).
4. **Versioning :** header `X-API-Version: 1` ou préfixe `/api/v1/` **avant** Swift GA ; jusqu’alors figer les breaking changes.
5. **Compat :** règle “additive only” sur events SSE (nouveaux `type` ignorés par clients old).

---

## 8. Architecture de code recommandée

### Option retenue (évolution minimale)

```
Chatbot/                          # repo actuel
  src/                            # Next = Web UI + API (inchangé structurellement au début)
  contracts/                      # NOUVEAU : openapi.yaml + schemas SSE
  apps/ios/                       # NOUVEAU : Xcode SwiftUI (remplace progressivement ios/ Capacitor)
  workers/chatbot/
  docs/
  .github/workflows/
    ios.yml                       # xcodebuild unsigned IPA (Swift target)
  AGENTS.md                       # règles dual-client
```

### Ce qu’on évite

- Turborepo / pnpm workspace **tant que** un seul serveur Next suffit.
- Partage de composants UI cross-platform (React Native, etc.).
- Dupliquer SQLite sur iPhone.

### Quand un vrai monorepo `apps/web` + `apps/api` devient utile

Si l’API doit évoluer **indépendamment** du bundle Web (équipes / releases séparées). Aujourd’hui : **surdimensionné**.

---

## 9. Synchronisation Web / iOS (Cursor)

### Problème

Cursor “oublie” le 2ᵉ client si le contexte est mono-React.

### Mécanismes recommandés

1. **`AGENTS.md` à la racine** (obligatoire) avec matrice :

   | Changement | Web | iOS | API |
   |------------|-----|-----|-----|
   | Comportement chat / SSE | Adapter `ChatView` | Adapter Chat VM | Si contrat change → `contracts/` + les deux |
   | Visuel only | React CSS | SwiftUI | Non |
   | Natif iOS only (Share Sheet, QL) | Non (ou fallback web) | Oui | Non |

2. **Règle Cursor** `.cursor/rules/dual-client.mdc` :  
   “Toute modif sous `src/app/api/**` ou `src/lib/agent/events.ts` doit lister l’impact iOS et mettre à jour `contracts/`.”

3. **Issues / PR template** : cases à cocher Web / iOS / Contracts / Tests.

4. **Feature flags serveur** (`app_settings`) pour activer des capacités seulement si le client annonce `X-Client: ios/1.x`.

5. **Pas de pixel-parity** : documenter “parity fonctionnelle” vs “parity visuelle”.

---

## 10. Design system

| Partageable | Comment |
|-------------|---------|
| Tokens couleur / spacing / radius | JSON ou Style Dictionary → CSS variables + Asset Swift (génération) |
| Sémantique (accent, danger, surface) | Noms communs |
| Typographie conceptuelle (title, body, mono) | Mapping SF Pro ↔ Geist — **pas** les mêmes fonts obligatoires |

| Non partagé | |
|-------------|--|
| Composants | React ≠ SwiftUI |
| Navigation | AppRouter ≠ NavigationStack |
| Glass / blur web | Material SwiftUI |

Objectif : **même langage produit**, pas le même toolkit.

---

## 11. Tests

| Couche | Aujourd’hui | Cible dual-client |
|--------|-------------|-------------------|
| Unit `src/lib` | Vitest colocalisé | Garder + étendre contracts |
| Worker | Vitest | Garder |
| React UI | quasi absent | RTL ciblé (SSE parser) |
| Swift | — | XCTest parsers SSE + API mocks |
| Contrats | — | CI : OpenAPI validate + golden SSE fixtures |
| Intégration | scripts smoke email | Smoke `/api/chat` SSE avec token test |
| E2E device | manuel SideStore | Checklist + éventuel XCUITest plus tard |

**Anti-régression Web-only :** job CI “contract + SSE fixture” **blocking** ; job Swift compile sur `macos-14` (déjà le runner IPA).

---

## 12. Performance : Capacitor vs SwiftUI

| Domaine | Gain SwiftUI attendu |
|---------|----------------------|
| Startup (après login) | **Élevé** — plus de boot React/hydratation remote |
| Scroll liste messages | **Élevé** |
| Clavier / safe area | **Moyen–élevé** |
| Markdown riche | **Variable** (dépend de la lib) |
| Latence réseau / LM Studio | **Négligeable** (identique) |
| SSE time-to-first-token | **Négligeable** |
| Access login | **Neutre / pire** si mal conçu |

Capacitor reste acceptable pour valider produit ; SwiftUI paye surtout **UX fluidité** et intégration système.

---

## 13. Offline / background / notifications

| Capacité | Pertinent ? | Note |
|----------|-------------|------|
| Push | Optionnel plus tard | APNs + serveur push sur PC — complexité HIGH ; pas V1 |
| Background fetch | Faible valeur | Backend PC doit être réveillé (déjà wake Worker) |
| Reprise SSE | Moyen | Re-fetch messages + éventuel resume id (API à concevoir) |
| Cache local messages | Moyen | Keychain/DB locale lecture seule |
| Stockage fichiers PC | Non | Reste serveur |

Ne **jamais** déplacer SQLite/LM Studio sur l’iPhone.

---

## 14. Distribution (Windows + GHA + SideStore + iLoader)

### Chaîne actuelle

GitHub Actions `macos-14` → `xcodebuild` unsigned → artifact IPA → iLoader install initiale / SideStore resign ~7j → Apple ID gratuit.

### Capacitor → SwiftUI : qu’est-ce qui change ?

| Élément | Change ? |
|---------|----------|
| Runner macOS GHA | Non |
| IPA unsigned | Non — même packaging `Payload/App.app` |
| SideStore signature | Non — SideStore signe **n’importe quelle IPA** unsigned (bundle id + entitlements raisonnables) |
| iLoader import IPA | Non — indépendant Capacitor |
| Secrets Apple dans GHA | Toujours **non** (reste SideStore local) |
| Entitlements | Possiblement plus (Keychain, Associated Domains, Push) — à garder minimal pour sideload gratuit |
| Bundle ID | Garder `fr.nicolazer.chatbot` pour continuité SideStore |

**Verdict H :** le workflow **iLoader → SideStore reste valide et essentiellement identique** pour une app SwiftUI native. Capacitor n’est pas un prérequis de SideStore.

Contrainte : entitlements “push” / App Groups / iCloud peuvent compliquer le sideload gratuit — les éviter en V1 native.

---

## 15. Estimation complexité

| Élément | Complexité |
|---------|------------|
| Petit refactor backend (erreurs, handoffs IDs) | **MEDIUM** |
| Contrats OpenAPI + CI drift | **MEDIUM** |
| Shell SwiftUI (auth session + navigation) | **HIGH** |
| Chat natif (SSE + Markdown + PJ) | **HIGH** |
| Mail natif | **HIGH** |
| Files natif | **HIGH** |
| Settings / runtime | **MEDIUM** |
| Auth Access → token app | **HIGH** |
| Tests contracts + SSE fixtures | **MEDIUM** |
| CI IPA Swift | **MEDIUM** (déjà macos) |
| Migration progressive + dual maintain | **VERY HIGH** (coût continu) |

---

## 16. Stratégie de migration (critique de ta proposition)

Ta séquence A→G est **globalement bonne**, avec correctifs :

### Recommandée

| Phase | Contenu | Critère de sortie |
|-------|---------|-------------------|
| **A** | Capacitor actuel | Chat + Access + Gmail stables, perf prod OK |
| **B0** | Stabilisation produit (bugs, OAuth redirect, démarrage) | Pas de P0 ouverts |
| **B** | `contracts/` + versioning SSE + handoffs structurés + (idéal) token app auth | CI contracts green |
| **C** | App SwiftUI **minimale** : login + WebView **ou** Chat-only API | Proof distribution IPA native |
| **D** | Chat SwiftUI complet (parity fonctionnelle) | Capacitor encore fallback |
| **E** | Mail | |
| **F** | Files | |
| **G** | Retrait Capacitor | Seulement si D+E+F OK 2+ semaines |

### Critiques

- **Ne pas** démarrer Swift avant B0+B : sinon double dette.
- **C avant D** avec un “thin client” évite 3 mois de Swift invisible.
- Mail/Files en parallèle = explosion ; **strictement séquentiel**.
- Garder Capacitor jusqu’à parity Chat **réelle** (pas “hello world”).

---

## 17. Risques

1. **Divergence Web/iOS** sans AGENTS.md / contracts CI.  
2. **SSE breaking** (nouveau champ obligatoire) → iOS crash parse.  
3. **Auth cookies** mal portés → 401 silencieux.  
4. **OAuth Gmail** redirect / Access isolation.  
5. **Duplication UI** coût maintenance ×2.  
6. **Pas de Mac local** → debug Swift seulement via GHA + device (lent).  
7. **Entitlements** sideload gratuit limités.  
8. **Markdown** qualité inférieure au web un temps.  
9. **Handoffs URL** Next-specific.  
10. **Tests** sous-investis côté UI aujourd’hui.

---

## 18. Verdict final

### A. Viable techniquement ? **8/10**

Backend déjà orienté API ; SSE typé ; FS/Mail correctement serveur.

### B. Pertinent pour CE projet ? **6/10**

Pertinent pour UX iPhone long terme ; **moins** tant que le produit bouge encore vite et que Capacitor vient d’arriver.

### C. Code backend conservable ?

Environ **70–85 %** de `src/lib` + routes API + Worker + schema — **sans réécriture**.

### D. UI à réécrire ?

**~100 % de l’UI iPhone** (tout `src/components` + pages utilisées sur mobile). Web React **conservé**.

### E. 5 refactors AVANT Swift

1. **Figer / publier `OrchestratorEvent` + fixtures SSE** (`contracts/`).  
2. **Handoffs mail/files par IDs** (plus seulement `url`).  
3. **Erreur API uniforme `{ error, code }`**.  
4. **Session token app** pour clients non-cookie (préparer Swift).  
5. **Stabiliser Access + Gmail OAuth + démarrage prod** sur Capacitor (dette actuelle).

### F. Architecture finale

- **Web :** Next.js React (UI) + mêmes API.  
- **iOS :** SwiftUI app séparée (`apps/ios`) parlant HTTP/SSE.  
- **Backend :** Next `src/lib` + SQLite sur PC + Worker.  
- **Contracts :** OpenAPI/JSON Schema versionnés.  
- **Pas** de backend sur téléphone.

### G. Cursor dual-client

`AGENTS.md` + rule `.cursor/rules/dual-client.mdc` + PR checklist + contracts CI + header `X-Client`.

### H. iLoader / SideStore pour IPA Swift ?

**Oui, identique** en pratique (unsigned IPA → SideStore). Capacitor n’est pas requis.

### I. Commencer la migration maintenant ?

**Non — attendre.**  
Ordre : stabiliser Capacitor (A/B0) → contracts (B) → alors seulement shell Swift (C).  
Commencer Swift UI maintenant **double** le coût alors que le shell Capacitor et l’auth viennent d’être débloqués.

---

## Annexes — fichiers de référence

- Auth : `src/middleware.ts`, `src/lib/auth/cloudflare-access.ts`, `src/lib/auth/api-auth.ts`  
- Chat SSE : `src/app/api/chat/route.ts`, `src/lib/agent/events.ts`, `src/lib/agent/orchestrator.ts`, `src/components/chat/ChatView.tsx`  
- DB : `src/lib/db/schema.ts`, `src/lib/db/index.ts`  
- Mail : `src/lib/mail/service.ts`, `src/lib/email/**`, `src/app/api/mail/**`, `src/app/api/email/**`, `src/app/api/oauth/**`  
- Files : `src/lib/files/path-guard.ts`, `src/app/api/files/**`  
- Capacitor : `capacitor.config.ts`, `docs/IOS-CAPACITOR.md`, `.github/workflows/ios.yml`  
- Worker : `workers/chatbot/src/index.ts`
