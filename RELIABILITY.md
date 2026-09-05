# Reliability Rework

Contrat de fiabilité pour Chatbot (backend Next + iOS native).  
Détails opérationnels : [`docs/RELIABILITY.md`](docs/RELIABILITY.md).

## Principes

1. **Fail safe** — en cas de doute, ne pas écrire / ne pas exécuter.
2. **Recoverable** — toute erreur doit ramener (ou permettre de ramener) un état valide.
3. **No magic** — pas de sleep arbitraire, retry infini, ou force-reload pour masquer un bug.
4. **Isolation** — Chat ≠ Mail ≠ Files ; une panne optionnelle ne tue pas le process.
5. **Single source of truth** — une responsabilité = un owner.

## Startup

| Dépendance | Bloque le démarrage ? |
|------------|------------------------|
| SQLite | **Oui** → health 503 |
| LM Studio / modèle | Non → health 200 `degraded`, `aiReady: false` |
| SearXNG | Non → recherche dégradée |
| Mail OAuth / Files roots | Non → features off |

## Invariants testés

- Abort stream ≠ faux message assistant (`ABORTED`, pas de `done`).
- Persist assistant **avant** `done`.
- Health 200 si SQLite OK même si IA down.
- iOS : double-send ignoré ; génération SSE stale → `CancellationError`.
- Mail : pas de wipe liste avant refresh.
- Logout : purge `TabMemoryCache`.

## Tests locaux

```bash
npx vitest run src/lib/lm-studio src/lib/agent/orchestrator-abort.test.ts src/app/api/health src/lib/health src/lib/reliability
```

Pas de CI dans ce rework. Pas de déploiement.
