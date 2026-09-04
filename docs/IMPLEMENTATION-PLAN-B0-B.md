# Plan d’implémentation — Phases B0 & B

**Date :** 2026-09-03  
**Statut :** **B0 GO (device) + B GO (repo)** — Bearer app reporté à C ; SwiftUI non démarré.  
**Références :** `docs/ARCHITECTURE-SWIFT-NATIVE.md`, `docs/B0-B-STATUS.md`, `docs/B0-DEVICE-CHECKLIST.md`.  
**Hors scope immédiat :** SwiftUI, monorepo `apps/`, backend séparé, refonte UI, Bearer app (ADR seulement).

---

## 0. Objectif et périmètre

| Phase | Objectif | Produit livré |
|-------|----------|---------------|
| **B0** | Capacitor iPhone **stable** (Access, Chat/SSE, Mail OAuth, Files, démarrage) sans régression Web | Checklist P0 verte + runbook à jour |
| **B** | Contrats backend **figés et testés** pour futurs clients Web + Swift | `contracts/` + CI drift + handoffs IDs + erreurs unifiées + plan auth Swift (code auth minimal ou différé) |

Après validation de ce document, Cursor pourra exécuter les étapes **B0.x** puis **B.x** dans l’ordre §14.

---

## 1. PHASE B0 — Stabilisation Capacitor

### 1.1 Définition de sortie (« Capacitor stable »)

B0 est **terminé** seulement si **tous** les critères suivants sont vrais sur **iPhone réel** (IPA SideStore) **et** PC/Web :

| # | Critère | Preuve |
|---|---------|--------|
| 1 | Login Cloudflare Access **dans** la WKWebView (pas Chrome système) | Parcours Access → Google IdP → retour app |
| 2 | Session Access tient ; 401 UI géré (reload / message) | Forcer expiration / cookie manquant |
| 3 | Chat : envoyer, stream tokens, `done`, Markdown basique | Conversation réelle |
| 4 | SSE : stop generation (bouton) + abort background (`chatbot:app-background`) | `NativeShell` + `ChatView` |
| 5 | Regenerate / retry erreur réseau | Cas manuel |
| 6 | PJ upload + preview image | `/api/attachments/*` |
| 7 | Mail : démarrer OAuth Gmail **sans** `redirect_uri_mismatch` ; liste + thread | Settings + Mail |
| 8 | Files : roots, list, search, preview (texte/PDF si supporté) | Workspace Files |
| 9 | Démarrage iPhone **raisonnable** avec stack **production** (`start:fast` / `next start`), pas `next dev` | Cold open < ~15–20 s hors cold PC/tunnel (ordre de grandeur, pas SLA) |
| 10 | Aucun **P0** ouvert listé ci-dessous | §1.2 |
| 11 | Web/PC : régression smoke Chat + Settings | Même origin ou localhost |

**Non-objectifs B0 :** feature Swift, OpenAPI complet, Bearer app, redesign UI, push notifications.

### 1.2 Inventaire des problèmes (repo réel)

#### B0-P1 — Access / allowNavigation (régression Chrome)

| | |
|--|--|
| **Fichiers** | `capacitor.config.ts`, `ios/App/.../capacitor.config.json` (généré), `docs/IOS-CAPACITOR.md` |
| **Problème** | Si un hôte IdP manque dans `allowNavigation`, iOS ouvre Chrome et casse le cookie Access. Config actuelle inclut déjà Access + Google ; la doc dit encore « Google OAuth = À TESTER » et « allowNavigation limité au domaine Chatbot » — **désynchronisée** du code. |
| **Impact** | P0 historique (login impossible in-app). |
| **Solution** | (1) Checklist device Access→Google→app. (2) Aligner `docs/IOS-CAPACITOR.md` sur `capacitor.config.ts` + `openGmailOAuthStart`. (3) Registre des hôtes IdP documenté ; tout ajout = rebuild IPA. |
| **Dépendances** | Rebuild IPA via GHA si config change. |
| **Risque** | LOW si config inchangée ; MEDIUM si on retire un host trop tôt. |
| **Tests** | Device : login froid ; login après kill app ; login après 7j refresh SideStore. |
| **Critère de sortie** | 3 logins successifs in-app sans ouverture Chrome. |

#### B0-P2 — OAuth Gmail API (`redirect_uri` + navigation)

| | |
|--|--|
| **Fichiers** | `src/lib/native/open-external.ts` (`openGmailOAuthStart` → `location.assign`), `src/app/api/oauth/gmail/start/route.ts`, `callback/route.ts`, `src/components/settings/EmailOAuthPanel.tsx`, env `GOOGLE_OAUTH_REDIRECT_URI` |
| **Problème** | Le flux dépend d’une URI **exacte** enregistrée dans Google Cloud Console (`…/api/oauth/gmail/callback`). Échec fréquent : `redirect_uri_mismatch`. Doc Capacitor encore ambiguë (Browser vs même WebView). |
| **Impact** | Mail inutilisable sur iPhone / parfois Web. |
| **Solution** | (1) Vérifier console Google + `.env.local` alignés sur `PUBLIC_BASE_URL`. (2) Doc runbook : « Gmail API = same WKWebView ». (3) Smoke : connect → `/api/oauth/accounts` montre compte. (4) Ne **pas** repasser par `@capacitor/browser` pour ce flux. |
| **Dépendances** | Access stable (B0-P1) ; cookies Access présents. |
| **Risque** | LOW (config) / MEDIUM si callback casse session. |
| **Tests** | Connect + disconnect ; list messages après connect. |
| **Critère de sortie** | Connect Gmail iPhone + Web sans mismatch. |

#### B0-P3 — Démarrage lent (`next dev` vs production)

| | |
|--|--|
| **Fichiers** | `scripts/start-fast.mjs`, `scripts/start-production.mjs`, `src/app/layout.tsx` (`#app-boot`), `src/components/native/BootSplash.tsx`, plugin SplashScreen |
| **Problème** | Via tunnel, `next dev` Turbopack compile à la demande → noir ~1 min. La cible iPhone est **production** (`start:fast`). |
| **Impact** | Faux sentiment « app cassée » ; pas un bug Capacitor. |
| **Solution** | Runbook opérateur : iPhone tests = `npm.cmd run start:fast` (ou stack prod). Smoke cold start. Vérifier splash/loader encore présents. |
| **Dépendances** | Build Next OK ; port 3000 libre. |
| **Risque** | LOW. |
| **Tests** | Cold open iPhone après `start:fast` ; compare vs `dev` (doc seulement). |
| **Critère de sortie** | Runbook opérateur écrit + cold start prod acceptable. |

#### B0-P4 — Chat SSE / stop / background

| | |
|--|--|
| **Fichiers** | `src/app/api/chat/route.ts`, `src/components/chat/ChatView.tsx`, `src/components/native/NativeShell.tsx` |
| **Problème actuel (comportement réel)** | Client : `fetch` + `ReadableStream`, parse `data: {json}`. Stop = `AbortController`. Background Capacitor → `chatbot:app-background` → abort. Serveur sur abort : envoie `{ type: "error", message: "Requête annulée" }` puis ferme. Heartbeat `: ping` 15s. **Pas** de reprise de stream. |
| **Impact** | Stop OK ; background = interruption (acceptable B0). Risque UX : message « Erreur: Requête annulée » affiché comme erreur alors que c’est un abort volontaire. |
| **Solution B0** | (1) Device test stop + background. (2) Optionnel petit fix UX : distinguer abort client vs erreur (peut être B0.x ou B — voir B2). **Ne pas** implémenter resume streaming en B0. |
| **Dépendances** | Backend PC up ; Access OK. |
| **Risque** | LOW. |
| **Tests** | Stop mid-stream ; home button mid-stream ; retour foreground (pas de crash). |
| **Critère de sortie** | Stop propre ; background n’accroche pas l’UI (`isGenerating` false). |

#### B0-P5 — Auth session / 401 client

| | |
|--|--|
| **Fichiers** | `src/middleware.ts`, `src/lib/client/api-fetch.ts`, handlers toast `chatbot:auth-required` |
| **Problème** | Middleware 401 JSON **sans** `code` ; HTML pour `Accept: text/html`. `apiFetch` traite tout 401 comme session expirée. Comportement OK Web/Capacitor cookie ; **pas** prêt Swift (B6). |
| **Impact** | B0 : risque toast/reload en boucle si Access flap. |
| **Solution B0** | Smoke expiration ; s’assurer qu’un 401 ne casse pas l’état React de façon irrécupérable. Uniformisation `{ error, code: "AUTH_REQUIRED" }` → **phase B**, pas bloquant B0 si smoke OK. |
| **Risque** | LOW. |
| **Critère de sortie** | Après 401 forcé, utilisateur peut se reconnecter. |

#### B0-P6 — Mail / Files fonctionnels (smoke, pas refactor)

| | |
|--|--|
| **Fichiers** | `src/lib/mail/mail-client.ts`, `src/lib/email/email-client.ts`, `src/app/files/FilesWorkspace.tsx`, APIs `/api/mail/**`, `/api/files/**` |
| **Problème** | Pas de P0 code identifié hors OAuth ; risque = feature flags off (`Email désactivé` / `Files désactivé` → 503). |
| **Solution** | Vérifier settings/env ; smoke list/search/preview/confirm mutations si utilisées. |
| **Risque** | LOW. |
| **Critère de sortie** | Checklists Mail + Files iPhone + Web. |

#### B0-P7 — Safe area / clavier / bande noire

| | |
|--|--|
| **Fichiers** | `capacitor.config.ts` (`ios.contentInset: "never"`), CSS safe-area, `KeyboardResize.Body` |
| **Problème** | Historique bande noire home indicator — config actuelle vise correction. |
| **Solution** | Re-vérifier Chat input + Mail compose avec clavier. Si OK → documenter « résolu ». |
| **Risque** | LOW. |
| **Critère de sortie** | Pas de bande noire bloquante ; input visible avec clavier. |

#### B0-P8 — Dettes doc / opérateur

| | |
|--|--|
| **Fichiers** | `docs/IOS-CAPACITOR.md`, `docs/IOS-INSTALL.md`, éventuellement `docs/ARCHITECTURE-SWIFT-NATIVE.md` (lien vers ce plan) |
| **Problème** | Docs partiellement obsolètes vs code (OAuth, allowNavigation, JWT « à retester »). |
| **Solution** | Mise à jour doc **uniquement** (autorisée) pendant B0. |
| **Risque** | LOW. |

### 1.3 Matrice P0 / P1 / P2 (B0)

| ID | Priorité | Titre |
|----|----------|-------|
| B0-P1 | **P0** | Access in-WKWebView stable |
| B0-P2 | **P0** | Gmail OAuth redirect + same WebView |
| B0-P3 | **P0** (ops) | Stack prod pour tests iPhone |
| B0-P4 | **P0** | Chat SSE stop + background |
| B0-P5 | **P1** | 401 recovery UX |
| B0-P6 | **P0** | Smoke Mail/Files |
| B0-P7 | **P1** | Safe area / clavier |
| B0-P8 | **P2** | Docs alignées |

### 1.4 Ce qui est déjà en place (ne pas « réparer » sans preuve)

- JWT Access via JWKS : `src/lib/auth/cloudflare-access.ts`
- Abort SSE + heartbeat : `src/app/api/chat/route.ts`
- Background abort : `NativeShell` → `ChatView`
- Gmail OAuth same-WebView : `openGmailOAuthStart`
- PathGuard / pending actions : serveur
- IPA unsigned GHA : `.github/workflows/ios.yml`

---

## 2. PHASE B — API Contracts

### 2.1 ORCHESTRATOR EVENTS / SSE (priorité 1)

#### Protocole actuel (exact)

**Transport**

- `POST /api/chat` (`src/app/api/chat/route.ts`)
- Body Zod : `conversationId`, `message`, `attachmentIds`, `regenerate?`, `editMessageId?`, `mode?`, `activeContext?`
- Réponse : `text/event-stream`
- Frames data : `data: ${JSON.stringify(OrchestratorEvent)}\n\n`
- Heartbeat : commentaire SSE `: ping\n\n` toutes les 15 s (ignorer côté client)
- Fin : fermeture du stream après orchestrateur (ou abort)
- Abort client : événement `{ type: "error", message: "Requête annulée" }` puis close

**Source de vérité types :** `src/lib/agent/events.ts` (`OrchestratorEvent`).

#### Catalogue des événements

| `type` | Payload (champs) | Obligatoire ? | Notes |
|--------|------------------|---------------|-------|
| `assistant_start` | `messageId` | Quasi — début message | Client React s’y accroche |
| `token` | `content` | Si génération | Répétable |
| `done` | `messageId` | Fin succès typique | |
| `error` | `message` (string only) | Erreur / abort | **Pas de `code` aujourd’hui** |
| `assistant_discard` | `messageId` | Optionnel | Regenerate / discard |
| `conversation_title` | `title` | Optionnel | |
| `runtime_status` | `status`, `message?` | Optionnel | |
| `route_decision` | `decision` | Optionnel / debug-ish | React log en non-prod |
| `memory_intent` | `decision` | Optionnel | |
| `memory_saved` | `messageId`, `memories` | Optionnel | |
| `context_snapshot` | `snapshot` | Optionnel | |
| `context_debug` | `trace` | Dev only | `CONTEXT_DEBUG` / development |
| `generation_usage` | `usage` | Optionnel | |
| `tool_start` | `tool`, `input` | Optionnel | `web_search` UX |
| `tool_done` | `tool`, `summary`, `sourceCount?` | Optionnel | |
| `sources` | `sources: SearchResult[]` | Optionnel | Citations web |
| `draft_preview` | `draft` | Optionnel | Email draft dans chat |
| `mail_handoff` | `url`, `intent`, `query?`, `threadId?`, `label?`, `reason` | Optionnel | **url = route Next** |
| `files_handoff` | `url`, `intent`, `query?`, `rootId?`, `reason` | Optionnel | **url = route Next** |
| `file_action_pending` | `actionId`, `confirmationToken`, `expiresAt`, `op`, `payload`, `notice?` | Optionnel | Confirmation Files |
| `agent_*` | plan / steps / actions / status / done / limit | Mode agent | Sous-protocole |

**Ordre typique (chat simple)** — observé côté client, non garanti formellement aujourd’hui :

1. éventuels `runtime_status` / `route_decision` / memory / context  
2. `assistant_start`  
3. `tool_*` / `sources` (si search)  
4. `token`*  
5. handoffs éventuels  
6. `done`  
7. close  

**Garanties à figer en B :**

- Tout frame `data:` = JSON objet avec `type: string` discriminé.
- Clients **doivent ignorer** `type` inconnus (forward compatible).
- Heartbeat ignoré.
- Au plus un message assistant « courant » par requête (via `assistant_start` / discard).
- Abort → préférer plus tard `error.code = "ABORTED"` (B2) plutôt que message libre seul.

#### Contrat versionné recommandé

**Ne pas** uniquement un fichier `chat-events.schema.json` orphelin.

Structure recommandée (après inspection — Zod déjà partout) :

```
contracts/
  VERSION                 # ex. 1
  README.md               # règles compat
  chat/
    orchestrator-events.zod.ts   # ou .ts réexportant depuis src — voir §5
    orchestrator-events.schema.json  # généré
    fixtures/
      happy-path.sse.txt
      web-search.sse.txt
      mail-handoff.sse.txt
      files-handoff.sse.txt
      abort.sse.txt
      agent-mode.sse.txt
      unknown-event.sse.txt
  ...
```

**Versioning événementiel :**

- Champ contrat `contracts/VERSION` (entier).
- Header réponse optionnel `X-Chat-Events-Version: 1` sur `/api/chat`.
- Règle : ajout de `type` ou champ **optionnel** = OK ; renommer/supprimer/changer sens = bump majeur + migration clients.

#### Fixtures

Chaque fixture = fichier texte SSE rejouable (parser partagé Node + plus tard Swift).  
Tests Vitest : parse → validate contre schema → snapshot ordre des `type`.

---

### 2.2 API ERRORS (priorité 2)

#### Formats actuels (inventaire réel)

| Zone | Format | Exemple |
|------|--------|---------|
| Middleware 401 | `{ error: string }` **sans code** | `src/middleware.ts` |
| Beaucoup de routes | `{ error: string }` | settings, conversations 404, files list… |
| Mail/AI/Files partiel | `{ error, code }` | `EMAIL_NOT_CONNECTED`, `INVALID_REQUEST`, `AI_ERROR`, `FORBIDDEN`, `TRASH_FAILED`, `SEND_FAILED` |
| Actions (`ActionError`) | codes riches | `NOT_FOUND`, `FORBIDDEN`, `EXPIRED`, `ALREADY_USED`, `HASH_MISMATCH`, `POLICY_DENIED`, `DRAFT_NOT_*`, `MESSAGE_NOT_FOUND`, `INVALID_STATE` |
| Files raisons | `FileAccessReasonCode` (axes) | `PATH_ESCAPE`, `ROOT_DENIED`, … — pas toujours exposés en JSON API |
| Attachments | parfois **texte brut** | `"Not found"` |
| SSE | `{ type: "error", message }` | pas de `code` |

#### Format commun proposé (adapté au repo)

```json
{
  "error": "Message humain (FR OK)",
  "code": "AUTH_REQUIRED"
}
```

Optionnels plus tard (pas obligatoires B) :

```json
{
  "error": "...",
  "code": "VALIDATION_ERROR",
  "details": { "field": "conversationId" }
}
```

SSE aligné :

```json
{ "type": "error", "message": "...", "code": "ABORTED" }
```

(`message` conservé pour compat React actuelle ; `code` ajouté).

#### Catalogue de codes (cible B)

| Code | HTTP typique | Domaine |
|------|--------------|---------|
| `AUTH_REQUIRED` | 401 | Access / session |
| `FORBIDDEN` | 403 | Token confirm, PathGuard, user |
| `NOT_FOUND` | 404 | Ressource |
| `VALIDATION_ERROR` | 400 | Zod / input |
| `FEATURE_DISABLED` | 503 | Email/Files off |
| `EMAIL_NOT_CONNECTED` | 403 | OAuth manquant |
| `PROVIDER_ERROR` | 502/500 | Gmail / LM Studio |
| `AI_ERROR` | 500 | déjà utilisé |
| `RATE_LIMITED` | 429 | si introduit |
| `CONFLICT` / `INVALID_STATE` | 409 | actions |
| `EXPIRED` | 410/400 | confirmations |
| `ALREADY_USED` | 409 | confirmations |
| `POLICY_DENIED` | 403 | policy |
| `ABORTED` | — (SSE) | cancel client |
| `INTERNAL` | 500 | fallback |

**Mapper** les `ActionErrorCode` et `FileAccessReasonCode` vers ce catalogue (ou sous-namespace `FILES_PATH_ESCAPE` si on veut granularité — décision B2 : **préserver** codes actions existants quand déjà renvoyés ; combler les trous ailleurs).

#### Compatibilité

- Phase B : **ajouter** `code` partout sans retirer `error`.
- React : continuer à afficher `error` ; brancher progressivement sur `code`.
- Tests : helper `assertApiErrorShape(body)`.

---

### 2.3 HANDOFFS (priorité 3)

#### État réel

- Builder serveur : `src/lib/mail/handoff.ts`, `src/lib/files/handoff.ts` — **sanitisation** query/label/threadId/rootId déjà solide ; tests mail `handoff.test.ts`.
- Événements SSE portent **déjà** `threadId` / `rootId` / `query` / `intent` **et** `url` Next (`/mail?...`, `/files?...`).
- Bug contrat client : `ChatView` ne persiste que `{ url, intent, reason }` — **drop** `threadId` / `rootId` / `query` / `label`.
- UI : `MailHandoffCard` / `FilesHandoffCard` naviguent via `Link href={url}`.

#### Cible

Événements (et cartes) basés sur **référence métier** ; `url` devient **dérivé optionnel** pour Web only (ou généré côté client Web).

```ts
// mail_handoff (contrat v1+)
{
  type: "mail_handoff",
  intent: "read_thread" | "search" | "list" | ...,
  reason: string,
  threadId?: string,
  query?: string,
  label?: string,
  // deprecated optional:
  url?: string
}
```

```ts
// files_handoff
{
  type: "files_handoff",
  intent: ...,
  reason: string,
  rootId?: string,
  query?: string,
  fileId?: string, // si un jour pertinent
  url?: string // deprecated
}
```

#### Sécurité (déjà partiellement correcte — à documenter dans contrat)

| Règle | Implémentation actuelle / cible |
|-------|----------------------------------|
| Ne pas faire confiance au client | `activeContext` = hint ; `resolveActiveContext` re-résout + auth (`src/lib/context/active-context.ts`) |
| Sanitiser IDs handoff | Patterns Gmail / rootId dans builders |
| Autorisation thread/file | Au moment de l’**ouverture** API Mail/Files avec `userId` — le handoff n’accorde **aucun** droit |
| Isolation user | Roots / OAuth / conversations scopés `userId` |
| LLM ne forge pas l’URL | Commentaire déjà dans `files/handoff.ts` — conserver builders serveur |

#### Travail B

1. Étendre builders pour exposer payload structuré (url optionnelle / helper `toWebPath()`).
2. Mettre à jour `ChatView` + cards pour naviguer par IDs (`router.push` construit côté Web).
3. Fixtures SSE sans dépendance URL.
4. Tests handoff files (aujourd’hui surtout mail).

---

### 2.4 CLIENT API — sous-ensemble public

**Principe :** ne **pas** publier les ~53 routes comme « API publique ». Publier un **Client Surface** documenté ; le reste = internal/ops.

#### Surface client (Web + futur iOS) — basée sur usages réels

**Chat / conversations**

| Endpoint | Usage |
|----------|--------|
| `GET/POST /api/conversations` | Liste / create — `ConversationsProvider` |
| `GET/PATCH/DELETE /api/conversations/[id]` | Titre, delete, flags |
| `GET .../messages` | Historique |
| `GET .../context` | Usage contexte |
| `POST /api/chat` | SSE |
| `POST/DELETE /api/attachments/*` | PJ |
| `GET /api/attachments/[id]` | Preview binaire |

**Runtime / settings**

| Endpoint | Usage |
|----------|--------|
| `GET/PATCH /api/settings` | |
| `GET /api/runtime/status`, `web-status`, `model`, `reasoning-capabilities` | Chat chrome |
| `GET /api/lm-studio/models` | |
| `GET/POST/DELETE /api/memories*` | Chat + settings |

**Mail**

| Endpoint | Usage |
|----------|--------|
| `GET /api/oauth/accounts` | |
| `GET /api/oauth/gmail/start`, callback, disconnect | OAuth (callback browser) |
| `GET /api/mail/messages`, `threads/[id]`, message, read, attachment | `mail-client.ts` |
| `POST /api/mail/ai/*` | summarize, suggest-reply, chat |
| `POST /api/mail/actions/trash`, `.../confirm` | |
| `POST /api/email/actions/*`, drafts | `email-client.ts` |

**Files**

| Endpoint | Usage |
|----------|--------|
| `GET/POST/DELETE /api/files/roots` | |
| `GET /api/files/list`, `search`, `content` | |
| `POST /api/files/index`, `upload`, `propose`, `actions` | |
| `POST /api/files/ai/chat` | |

#### Internal / ne pas traiter comme contrat client iOS V1

| Endpoint | Raison |
|----------|--------|
| `GET /api/health` | Ops / Worker / Bearer `HEALTH_CHECK_TOKEN` |
| `POST/GET /api/perf/audit` | Dev profiler UI |
| `GET /api/conversations/[id]/export` | Download navigateur (Sidebar) — optionnel plus tard |
| `GET /api/runtime/capabilities` | Peu/pas consommé UI principale — vérifier avant d’inclure |
| `GET /api/lm-studio/health` | Ops |
| `GET/POST /api/memories/import|export` | Settings avancés — P2 |

**Pas de renommage massif** des paths en B (casse Capacitor/Web). Renommer seulement si collision ; préférer **aliases** documentés.

---

### 2.5 TYPES / CONTRACTS — choix pour CE repo

| Option | Verdict |
|--------|---------|
| TypeScript seul dans `src/lib` | Insuffisant pour Swift / drift CI |
| JSON Schema only | Duplique Zod déjà présent |
| OpenAPI complet 53 routes | Trop lourd pour B |
| **Zod source → JSON Schema généré + OpenAPI partiel (Client Surface)** | **Retenu** |
| Génération Swift immédiate | **Différer** à phase C (ouvrir la porte via schemas) |

**Règle anti-duplication :**

1. Définir / réexporterer types dans `contracts/**` **ou** `src/lib/contracts/**` réexportés.
2. Préférence pragmatique pour ce repo **sans monorepo** :

```
contracts/           # artefacts versionnés + fixtures (source de vérité publiée)
src/lib/contracts/   # adapters Zod + re-exports utilisés par routes (optionnel)
```

Éviter de casser les imports existants : en B1, **extraire** `OrchestratorEvent` vers module contrat et faire `events.ts` réexporterer (compat).

Validation runtime : Zod sur routes déjà (ex. chat) — étendre progressivement helpers `jsonError`.

---

### 2.6 AUTHENTIFICATION — plan seulement (pas d’implémentation forcée en B0)

#### Système actuel (exact)

```
Edge CF Access (cookie / JWT assertion)
  → middleware authentifie Cf-Access-Jwt-Assertion (JWKS)
  → x-user-id
  → withAuth sur routes sensibles
Dev : CF_ACCESS_ENABLED=false → user "local"
Health : Bearer HEALTH_CHECK_TOKEN (exception étroite)
```

Client Capacitor = **même modèle cookie navigateur** que le Web.

#### Comparaison options Swift

| Option | Faisable | Sécurisé | Compatible | Nécessaire pour Swift | Peut attendre |
|--------|----------|----------|------------|----------------------|---------------|
| **A. Access + cookie** seul | Fragile hors WKWebView | Oui si Access edge | URLSession cookies possibles mais UX login mauvaise | Non fiable | — |
| **B. Access + session applicative** | Oui | Oui si session liée à identité Access vérifiée | Oui | Recommandé | Après B0 |
| **C. Access + Bearer app** | Oui | Oui si émis **après** preuve Access, TTL court, revoke | Excellent URLSession | **Cible** | Plan en B ; code peut être **fin de B** ou **début C** |
| **D. Autre (API keys user)** | Oui | Risque si mal fait | — | Non | Non recommandé |

**Retenu : C (avec contrainte Access).**

Exigences non négociables :

1. Cloudflare Access **reste** devant l’origine (Worker) — pas de contournement.
2. Le Bearer app **n’ouvre pas** l’API sans qu’Access edge soit satisfait **ou** sans un flux d’échange explicitement boré (ex. endpoint `POST /api/auth/app-session` appelé **depuis** un contexte déjà Access-authentifié, qui émet un token app stocké Keychain).
3. `HEALTH_CHECK_TOKEN` **ne** devient **pas** le token utilisateur.
4. `X-Client` **jamais** autorisation.

**Décision reportée à validation :** implémenter le code Bearer en **B7** (fin de B) vs **C0** (shell Swift). Ce plan **prépare** le contrat auth (`contracts/auth/`) dans tous les cas ; le code Bearer n’est **pas** requis pour clôturer B0.

---

### 2.7 OBSERVABILITÉ

Instrumenter (headers / logs structurés existants `src/lib/observability/*`) :

| Champ | Où | Authz ? |
|-------|-----|---------|
| `X-Client: web \| capacitor \| ios` | Request | **Non** — telemetry only |
| `X-App-Version` | Request | Non |
| `X-API-Version` / `X-Chat-Events-Version` | Request/Response | Non |
| latency, status, route | logs serveur | — |
| SSE disconnect / abort | logs chat | — |
| auth failure reason class | logs (sans token) | — |

Réutiliser `redact` / `sse-sanitize` — ne pas logger confirmation tokens / OAuth.

---

### 2.8 VERSIONING (minimal)

**Recommandation pour ce projet :**

1. **Ne pas** migrer tout vers `/api/v1` maintenant (casse clients, coût HIGH).
2. `contracts/VERSION` + header `X-API-Version: 1`.
3. Compat ascendante : champs nouveaux optionnels ; suppression = bump + période de dual-read.
4. Endpoint `GET /api/runtime/capabilities` (ou nouveau `GET /api/meta/client-api`) exposant `{ apiVersion, chatEventsVersion, features: {...} }` pour que Swift sache quoi activer.

---

### 2.9 CI CONTRACTS

Aujourd’hui : **pas** de workflow CI tests app (seulement `.github/workflows/ios.yml` IPA).

À ajouter (phase B) — workflow ex. `.github/workflows/contracts.yml` :

1. `npm test` (Vitest) — déjà ~76 tests unitaires  
2. Validation JSON Schema (ajv) des schemas générés  
3. Replay fixtures SSE → conforme  
4. `assertApiErrorShape` sur fixtures erreurs  
5. Job « breaking change » : compare schemas vs baseline `contracts/baseline/` (diff semver)  
6. Plus tard : génération Swift + compile — **hors B**

Le job doit **échouer** si un schema breaking est modifié sans bump `VERSION`.

---

### 2.10 STRUCTURE DE FICHIERS RECOMMANDÉE

Après inspection : **pas** de monorepo artificiel ; garder Next monolith + dossier `contracts/` à la racine.

```
contracts/
  VERSION
  README.md
  meta/
    client-api.openapi.yaml      # surface seulement (généré ou maintenu mince)
  chat/
    orchestrator-events.schema.json
    fixtures/*.sse.txt
  errors/
    api-error.schema.json
    codes.md
  handoffs/
    mail-handoff.schema.json
    files-handoff.schema.json
  auth/
    app-session.schema.json      # contrat futur — même si code plus tard
  design-tokens/
    tokens.json                  # couleurs/spacing conceptuels (B léger)
docs/
  IMPLEMENTATION-PLAN-B0-B.md    # ce fichier
  ARCHITECTURE-SWIFT-NATIVE.md
  CLIENT-API.md                  # à créer en B : surface endpoints
AGENTS.md                        # dual-client
.cursor/rules/dual-client.mdc
.cursor/rules/contracts.mdc      # optionnel
src/lib/agent/events.ts          # réexport depuis contrat
```

**Pas** `/apps/web` tant que Swift n’existe pas.

---

## 3. CURSOR / DUAL CLIENT

### 3.1 Livrables B (fichiers)

**`AGENTS.md`** (racine) — points clés :

- Clients : Web React (`src/components`, `src/app` pages) + futur iOS SwiftUI (`apps/ios` quand créé) + shell Capacitor temporaire.
- Backend unique : `src/lib`, `src/app/api`.
- Toute feature touchant comportement → analyser **API + Web + (iOS si présent)**.
- UI-only Web → React only ; UI-only iOS → Swift only.
- Interdits : métier dans Swift ; secrets Apple dans git/GHA ; bypass Access.

**`.cursor/rules/dual-client.mdc`** (`alwaysApply` ou glob `contracts/**`, `src/app/api/**`, `src/lib/agent/**`) :

- Si modification `OrchestratorEvent` / routes Client Surface → mettre à jour `contracts/` + tests + checklist PR.
- Matrice obligatoire dans la réponse agent quand feature cross-cutting.

**Checklist PR (dans AGENTS.md)** :

```
[ ] contracts/VERSION bump si breaking
[ ] fixtures SSE à jour
[ ] Web React impacté ? 
[ ] iOS Swift impacté ? (N/A tant que pas d’app)
[ ] Capacitor rebuild nécessaire ? (native only)
[ ] X-Client non utilisé pour auth
```

### 3.2 Matrice Web / iOS / API (vivante)

| Domaine | API | Web | iOS (futur) | Capacitor |
|---------|-----|-----|-------------|-----------|
| Chat SSE | oui | `ChatView` | à venir | remote UI |
| Mail | oui | mail/* | à venir | remote |
| Files | oui | files/* | à venir | remote |
| Auth Access | edge+middleware | cookies | session/Bearer | cookies |
| Handoffs | events | cards | deep links natifs | Link Next |

---

## 4. DESIGN SYSTEM (minimal B)

Uniquement `contracts/design-tokens/tokens.json` :

- couleurs sémantiques (`bg`, `fg`, `accent`, `danger`, `success`)
- spacing scale
- radius
- typographie **conceptuelle** (family roles : ui / mono / display — pas de fichiers de police partagés obligatoires)
- états : `idle | loading | error | disabled`

**Pas** de composants partagés React/Swift.  
Web continue Tailwind ; Swift plus tard mappe les tokens.

---

## 5. TEST MATRIX

| Domaine | Backend unit (existe) | Contract (à créer) | Web | iOS device | Integration |
|---------|----------------------|--------------------|-----|------------|-------------|
| Chat orchestrator | partiel (`loop`, etc.) | fixtures SSE | manuel + peu de tests UI | B0 device | POST /api/chat |
| SSE parse | `sse-sanitize` | **oui** | `ChatView` manuel | B0 | |
| Errors | actions tests | **schema** | `apiFetch` test | | |
| Handoffs | mail tests | **schemas + files tests** | cards | | |
| Auth Access | `cloudflare-access.test`, `request-auth` | auth schema futur | 401 toast | B0 login | |
| Mail API | nombreux | OpenAPI slice | mail-client | B0 OAuth | |
| Files / PathGuard | `path-guard.test` | errors mapping | FilesWorkspace | B0 smoke | |
| Attachments | validate/extract | | ChatInput | B0 | |
| Memory | intent tests | | settings | P2 | |
| Web search | nombreux | tool events fixtures | activity UI | | |
| Capacitor shell | `open-external.test` | — | — | **device** | |
| CI contracts | — | **workflow** | | | |

Légende B0 : device obligatoire pour P0.  
B : contract tests en CI obligatoire.

---

## 6. ORDRE D’IMPLÉMENTATION DÉTAILLÉ

### B0 — Stabilisation

#### B0.1 — Alignement doc opérateur + stack prod

| | |
|--|--|
| **Objectif** | Tests iPhone toujours contre prod build |
| **Fichiers** | `docs/IOS-CAPACITOR.md`, `docs/IOS-INSTALL.md`, éventuellement README ops |
| **Mods** | Doc only : `start:fast`, allowNavigation réel, Gmail same-WebView |
| **Tests** | N/A |
| **Dépendances** | — |
| **Sortie** | Doc cohérente avec `capacitor.config.ts` + `open-external.ts` |

#### B0.2 — Smoke Access iPhone (P0)

| | |
|--|--|
| **Objectif** | Login Access in-app stable |
| **Fichiers** | Config Capacitor **seulement si** échec device |
| **Mods** | Aucune si OK ; sinon ajuster `allowNavigation` + rebuild IPA |
| **Tests** | Device checklist §1.1 #1–2 |
| **Sortie** | 3 logins OK |

#### B0.3 — Smoke Chat SSE (P0)

| | |
|--|--|
| **Objectif** | Stream, stop, background |
| **Fichiers** | Peut-être petit UX abort dans `ChatView` / `chat/route.ts` si « Erreur annulée » gênante |
| **Tests** | Device + Web |
| **Sortie** | Critères §1.1 #3–5 |

#### B0.4 — Gmail OAuth (P0)

| | |
|--|--|
| **Objectif** | Connect sans mismatch |
| **Fichiers** | Env / console Google ; UI settings si message d’aide insuffisant |
| **Sortie** | Compte visible via `/api/oauth/accounts` ; list mail |

#### B0.5 — Files + Mail smoke (P0)

| | |
|--|--|
| **Objectif** | Parcours critiques |
| **Sortie** | Checklist signée (doc ou issue) |

#### B0.6 — Perf démarrage (P0 ops)

| | |
|--|--|
| **Objectif** | Cold start prod acceptable |
| **Fichiers** | Ops only sauf bug splash |
| **Sortie** | §1.1 #9 |

#### B0.7 — Clôture B0

| | |
|--|--|
| **Objectif** | Aucun P0 ouvert ; note « B0 done » dans ce doc ou changelog |
| **Sortie** | Go / No-Go pour démarrer B |

---

### B — Contrats

#### B1 — Scaffolder `contracts/` + VERSION + README

| | |
|--|--|
| **Objectif** | Emplacement + règles compat |
| **Fichiers** | `contracts/**` |
| **Complexité** | LOW |
| **Sortie** | Dossier versionné ; pas encore enforcement CI |

#### B2 — Figer `OrchestratorEvent` + schemas + fixtures SSE

| | |
|--|--|
| **Objectif** | Contrat chat events v1 |
| **Fichiers** | `src/lib/agent/events.ts`, `contracts/chat/**`, tests Vitest, éventuellement `X-Chat-Events-Version` sur `chat/route.ts` |
| **Mods** | Extraire/réexporterer types ; générer JSON Schema ; fixtures ; ignorer unknown types documenté ; ajouter `code` optionnel sur error SSE |
| **Risque** | MEDIUM (toucher chat) |
| **Sortie** | Tests fixtures green ; React inchangé fonctionnellement |

#### B3 — Erreurs API uniformes `{ error, code }`

| | |
|--|--|
| **Objectif** | Helper `apiError()` + migration progressive routes Client Surface |
| **Fichiers** | Nouveau helper `src/lib/http/api-error.ts` (nom à confirmer), `middleware.ts`, routes mail/files/chat/conversations… |
| **Mods** | Ajouter codes ; **ne pas** casser clients (champ `error` reste) |
| **Risque** | MEDIUM |
| **Sortie** | Surface client : 100 % avec `code` ; internal P2 |

#### B4 — Handoffs structurés (IDs first)

| | |
|--|--|
| **Objectif** | Clients naviguent sans parser routes Next |
| **Fichiers** | `mail/handoff.ts`, `files/handoff.ts`, `events.ts`, `orchestrator.ts`, `ChatView.tsx`, cards, tests |
| **Mods** | `url` deprecated/optional ; React construit paths ; schemas handoffs |
| **Risque** | MEDIUM |
| **Sortie** | Fixtures sans url obligatoire ; Web OK |

#### B5 — Document Client Surface + OpenAPI mince

| | |
|--|--|
| **Objectif** | `docs/CLIENT-API.md` + `contracts/meta/client-api.openapi.yaml` |
| **Fichiers** | docs + contracts ; **pas** rewrite routes |
| **Complexité** | MEDIUM |
| **Sortie** | Liste endpoints « public client » figée |

#### B6 — Meta capabilities + version headers

| | |
|--|--|
| **Objectif** | `GET /api/meta/client-api` ou étendre capabilities |
| **Fichiers** | nouvelle route mince + observability headers documentés |
| **Risque** | LOW |
| **Sortie** | Clients peuvent lire versions |

#### B7 — Auth contrat (+ optionnellement session Bearer)

| | |
|--|--|
| **Objectif** | Spec `contracts/auth/` ; **décision go/no-go code** |
| **Fichiers** | contracts ; si go : `src/app/api/auth/**`, storage session DB, middleware accept Bearer **en plus** de JWT Access selon design validé |
| **Risque** | HIGH si code — sinon LOW (spec only) |
| **Sortie min** | Spec revue |
| **Sortie max** | Token app émis après Access, TTL, revoke — **sans** bypass edge Access |

#### B8 — AGENTS.md + dual-client rules + tokens

| | |
|--|--|
| **Objectif** | Cursor dual-client ready |
| **Fichiers** | `AGENTS.md`, `.cursor/rules/dual-client.mdc`, `contracts/design-tokens/tokens.json` |
| **Risque** | LOW |
| **Sortie** | Rules actives |

#### B9 — CI contracts

| | |
|--|--|
| **Objectif** | Bloquer drift |
| **Fichiers** | `.github/workflows/contracts.yml`, scripts generate/check |
| **Risque** | LOW–MEDIUM |
| **Sortie** | PR breaking schema → CI red |

#### B10 — Clôture B

| | |
|--|--|
| **Objectif** | Critères §18 |
| **Sortie** | Autorisation phase C |

---

## 7. ESTIMATIONS

| Chantier | Complexité | Fichiers (ordre) | Risque régression |
|----------|------------|------------------|-------------------|
| B0 doc/ops | LOW | 2–4 | LOW |
| B0 device smokes | LOW–MEDIUM | 0–3 | LOW |
| B0 fix Access/OAuth si besoin | MEDIUM | 1–5 + IPA | MEDIUM |
| B1 scaffold contracts | LOW | 5–10 | LOW |
| B2 SSE contrat + fixtures | **HIGH** | 8–20 | **MEDIUM–HIGH** |
| B3 erreurs API | **MEDIUM–HIGH** | 20–40 | MEDIUM |
| B4 handoffs | MEDIUM | 8–15 | MEDIUM |
| B5 OpenAPI mince | MEDIUM | 3–8 | LOW |
| B6 meta/version | LOW | 3–6 | LOW |
| B7 auth spec | MEDIUM | 2–5 | LOW |
| B7 auth code (si go) | **HIGH** | 10–25 | **HIGH** |
| B8 Cursor rules | LOW | 3–5 | LOW |
| B9 CI | MEDIUM | 3–8 | LOW |
| Design tokens | LOW | 1–2 | LOW |

Pas d’estimation horaires fiable (device Apple + GHA + config Google hors repo).

---

## 8. CE QU’IL NE FAUT PAS FAIRE

- Réécrire Swift / créer `apps/ios` pendant B0/B (sauf dossier vide explicitement refusé — **attendre C**).
- Créer un backend séparé ou dupliquer SQLite sur iPhone.
- Transformer les ~53 routes en « API publique » massive.
- Partager composants UI React/Swift.
- Stocker Apple ID / certificats / secrets Gmail dans GitHub Actions.
- Mettre la logique métier (PathGuard, OAuth tokens, orchestrateur) dans le client.
- Contourner Cloudflare Access (désactiver edge, bearer magique global).
- Introduire monorepo Turborepo/Nx sans besoin.
- `/api/v1` rewrite global.
- Resume SSE + offline-first iPhone en B.
- Remplacer Capacitor avant parity Chat native.
- Faire de `X-Client` un mécanisme d’autorisation.
- Réutiliser `HEALTH_CHECK_TOKEN` comme session utilisateur.

---

## 9. MIGRATION FUTURE (après B)

| Phase | Contenu | Prérequis issus de B0/B |
|-------|---------|-------------------------|
| **C** | Shell SwiftUI : login Access→session, navigation, maybe WebView fallback | B terminé ; **décision Bearer tranchée** |
| **D** | Chat SwiftUI (SSE fixtures = mêmes streams) | B2 + B3 + B4 |
| **E** | Mail SwiftUI | Client Surface mail + OAuth natif planifié |
| **F** | Files SwiftUI | IDs handoff + content API |
| **G** | Retrait Capacitor | D+E+F stables |

### Décisions **avant C**

1. Format session / Bearer (B7).  
2. Version events figée (B2).  
3. Handoffs IDs (B4).  
4. Bundle ID inchangé `fr.nicolazer.chatbot`.  
5. Origin publique inchangée.

### Peut attendre après C

- OpenAPI exhaustif  
- Génération Swift automatique  
- Design system riche  
- Push / background transfer  
- Parity Mail/Files  

---

## 10. VERDICT

### Plan recommandé

Exécuter **B0.1 → B0.7** (smokes + doc ; code minimal), puis **B1 → B9** (contrats), avec **B7 code Bearer optionnel** reportable en C0 si on veut réduire le risque.

### Priorités

| Priorité | Items |
|----------|-------|
| **P0 maintenant** | B0 Access, Gmail OAuth, Chat SSE smoke, stack prod, Mail/Files smoke |
| **P1 ensuite** | B2 SSE contracts, B3 errors, B4 handoffs, B9 CI, AGENTS dual-client |
| **P2** | OpenAPI mince polish, design tokens, auth Bearer code, meta capabilities |

### Absolument maintenant (dès validation)

- B0 smokes device + doc ops  
- Ne pas démarrer Swift  

### Peut attendre

- Bearer app code  
- SwiftUI  
- Monorepo  
- `/api/v1`  

### Surtout ne pas faire maintenant

Voir §8.

### B0 terminé si

Tous les critères §1.1 + aucun P0 §1.3 ouvert.

### B terminé si

1. `contracts/VERSION` ≥ 1 publié  
2. Fixtures SSE + schema events validés en CI  
3. Client Surface documentée  
4. Erreurs surface avec `code`  
5. Handoffs IDs first (Web adapté)  
6. `AGENTS.md` + dual-client rule  
7. Spec auth Swift revue (code Bearer : done **ou** explicitement reporté à C avec ADR)  
8. CI contracts bloque breaking change  

### Autorisation de commencer SwiftUI (phase C) si

- B0 terminé  
- B terminé (ci-dessus)  
- Décision auth C tranchée  
- Capacitor encore maintenu en parallèle  
- IPA unsigned workflow inchangé (SideStore)  

---

## 11. Zones d’incertitude (pas de fiction)

Signalées explicitement — à trancher pendant l’implémentation, pas inventées ici :

1. **Fréquence exacte / ordre garanti** de tous les events hors happy-path : le type union est clair ; l’ordre formel n’est **pas** spécifié dans le code — B2 doit le documenter empiriquement via fixtures capturées.  
2. **`draft_preview`** : émis serveur ; consommation UI Chat peu visible dans le switch `ChatView` (pas de `case "draft_preview"`) — Clarifier si event mort côté UI ou géré ailleurs avant de le marquer « required client ».  
3. **Couverture exacte** de `GET /api/runtime/capabilities` par l’UI : à vérifier avant inclusion Client Surface.  
4. **État réel device** Access/Gmail « OK » vs « encore flaky » : la doc dit encore à retester ; ce plan exige smoke **mesuré** en B0.2/B0.4.  
5. **Implémenter Bearer en B vs C** : laissé en décision explicite à la validation utilisateur.

---

## 12. Prochaine étape

**Attente validation humaine de ce plan.**  
Après « OK pour B0 » / « OK pour B0+B », exécuter dans l’ordre §6 sans élargir le scope.
