# Fiabilité — contrat opérationnel

## Ownership

| Surface | Owner | Notes |
|---------|--------|--------|
| Métier (PathGuard, OAuth, SQLite, orchestrateur) | Backend (`src/lib/**`, routes API) | Jamais dans un client |
| Chat / Mail / Files UX | iOS native (`apps/ios/ChatbotNative`) | Isolation UI : un onglet ne doit pas vider un autre |
| Contracts SSE / erreurs | `contracts/` + `src/lib/http/api-error.ts` | Codes stables ; clients ignorent les `type` inconnus |

## Startup

1. Boot crée/migre SQLite ; indexes hot-path seulement si la table existe (`tableExists`).
2. `/api/health` :
   - **200** si Next + SQLite OK (`status: "ok"` ou `"degraded"`).
   - **503** uniquement si SQLite en panne (`ready: false`).
   - `aiReady` = LM Studio joignable **et** modèle chargé — informatif, ne force pas 503.
3. Scripts boot (`scripts/boot/lib/nextjs.mjs`) acceptent 200 (et 503 dégradé legacy si sqlite ok) ; envoient `Authorization: Bearer $HEALTH_CHECK_TOKEN` si défini.

## Modèle d’erreur

- Corps uniforme : `{ error, code }` (`VALIDATION_ERROR`, `ABORTED`, `AUTH_REQUIRED`, …).
- SSE chat : `{ type: "error", message, code? }` — `ABORTED` / « Requête annulée » sur annulation.
- Annulation ≠ succès : pas de placeholder « Je n'ai pas pu générer… », pas de `done` après abort.
- Persistance assistant **avant** `done` ; échec persist → `error`, pas de `done`.

## Retries / annulation

- Client LM : `AbortError` → `onError` (jamais `onDone` vide).
- Orchestrateur : `signal.aborted` / AbortError → event `ABORTED`.
- iOS `ChatStreamingService` : génération obsolète → `CancellationError` (pas return silencieux).
- iOS Chat : `sendGeneration` ignore les SSE d’un envoi précédent ; cancel sur changement de conversation.
- Poll runtime status : un tick en vol saute le suivant (guard in-flight).

## Isolation Chat / Mail / Files

- Mail : ne pas vider la liste avant un nouveau load (garder l’ancien état jusqu’aux nouvelles données / erreur transitoire).
- Logout : `TabMemoryCache.clearAll()` (mail, files, chat).
- Cache onglets process-local uniquement — pas de secrets.

## Matrice de panne

| Panne | HTTP / effet | UI attendue |
|-------|----------------|-------------|
| SQLite down | health 503, `ready: false` | Process non utilisable |
| LM / modèle down | health 200 `degraded`, `aiReady: false` | Chat peut échouer avec erreur claire |
| Body chat invalide | 400 `VALIDATION_ERROR` | Pas de SSE |
| Abort client | SSE `error` `ABORTED` | Pas de faux message assistant |
| Persist message fail | SSE `error` (sauvegarde) | Pas de `done` trompeur |
| Tunnel 502/503 | iOS retry ×3 puis erreur | Message transient friendly |

## Tests

```bash
npx vitest run src/lib/lm-studio/client.test.ts src/lib/agent/orchestrator-abort.test.ts src/app/api/health/health.test.ts
```

Ou : `npx vitest run` pour la suite complète.
