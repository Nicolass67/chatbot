# Fiabilité — contrat opérationnel

## Ownership

| Surface | Owner | Notes |
|---------|--------|--------|
| Métier (PathGuard, OAuth, SQLite, orchestrateur) | Backend (`src/lib/**`, routes API) | Jamais dans un client |
| Chat / Mail / Files UX | iOS native (`apps/ios/ChatbotNative`) | Isolation UI : un onglet ne doit pas vider un autre |
| Contracts SSE / erreurs | `contracts/` + `src/lib/http/api-error.ts` | Codes stables ; clients ignorent les `type` inconnus |
| Matrice de panne | `src/lib/reliability/failure-modes.ts` | Source de vérité testée |

## Startup

1. Boot crée/migre SQLite ; indexes hot-path seulement si la table existe (`tableExists`).
2. `/api/health` :
   - **200** si Next + SQLite OK (`status: "ok"` ou `"degraded"`).
   - **503** uniquement si SQLite en panne (`ready: false`).
   - `aiReady` = LM Studio joignable **et** modèle chargé — informatif, ne force pas 503.
3. Scripts boot (`scripts/boot/lib/nextjs.mjs`) acceptent 200 (et 503 dégradé legacy si sqlite ok) ; envoient `Authorization: Bearer $HEALTH_CHECK_TOKEN` si défini.

## Shutdown / cancellation

- Client abort → `AbortError` / `ABORTED` ; pas de placeholder ; pas de `done`.
- iOS quitte/change de conversation → cancel stream + bump `sendGeneration`.
- Persist avant `done` ; échec persist = error SSE.

## Modèle d’erreur

- Corps uniforme : `{ error, code }` (`VALIDATION_ERROR`, `ABORTED`, `AUTH_REQUIRED`, …).
- SSE chat : `{ type: "error", message, code? }`.
- Domaines : network / timeout / auth / database / filesystem / ai / search / streaming / validation / cancellation.

## Retries

- Bornés (typ. ×3) avec backoff sur 502/503 tunnel uniquement.
- Pas de retry sur validation, auth, permission denied, JSON modèle invalide.
- Idempotence : double-submit iOS ignoré via `isSending` + génération.

## Isolation Chat / Mail / Files

- Mail : ne pas vider la liste avant un nouveau load.
- Logout : `TabMemoryCache.clearAll()`.
- Contexte Assistant stable par scope (general / mail / files).

## Matrice de panne (extraits)

| Panne | HTTP / effet | Recovery |
|-------|----------------|----------|
| SQLite down | health 503 | fail_fast |
| LM / modèle down | health 200 degraded | degrade |
| SearXNG down | chat sans web | degrade |
| Body chat invalide | 400 | fail_fast |
| Abort client | SSE `ABORTED` | cancel_clean |
| Persist fail | SSE error, pas de done | fail_fast |
| Stale / double send | ignoré | ignore_stale |

Voir `FAILURE_CONTRACTS` dans `src/lib/reliability/failure-modes.ts`.

## Tests

```bash
npx vitest run src/lib/lm-studio src/lib/agent/orchestrator-abort.test.ts src/app/api/health src/lib/health src/lib/reliability
```

## Limites

On ne garantit pas l’absence totale de bugs. On garantit que les classes de panne ci-dessus ont une stratégie explicite et des tests de non-régression sur les chemins critiques.
