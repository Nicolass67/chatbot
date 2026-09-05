# Infrastructure Supervisor

Processus Node **indépendant** de Next.js qui surveille et répare la stack locale avec un blast radius minimal.

Frontière avec la fiabilité applicative : [`docs/RELIABILITY.md`](./RELIABILITY.md).

## Architecture

```
Windows (tâche planifiée / logon)
  └── scripts/supervisor/index.mjs   ← daemon autonome (pas d’import src/)
        ├── probes process / health / readiness
        ├── repair lock + crash-loop circuit
        ├── data/supervisor/*.json
        └── HTTP 127.0.0.1:3927
              ▲
Next.js (quand up) ── /api/infrastructure/* (auth) ──► iPhone SwiftUI
```

Next.js **ne** se supervise **pas** lui-même. S’il tombe, le Supervisor le redémarre.

## Services détectés (audit repo)

| id | Rôle | Critique | Dépendances |
|----|------|----------|-------------|
| `docker` | Docker Desktop / daemon | optional | — |
| `searxng` | Recherche Web (compose) | optional | `docker` |
| `nextjs` | Chatbot / API | **required** | — (SQLite in-process) |
| `lm_studio` | Assistant IA | optional | — |
| `cloudflared` | Tunnel / ingress | optional | `nextjs` |

Sources d’audit : `scripts/boot/*`, `docker-compose`, `package.json`, health LM/SearXNG/Next.

SQLite n’est **pas** un service OS séparé : il vit avec Next.

## Dependency graph

```
docker ──► searxng
nextjs ──► cloudflared
lm_studio (parallèle, indépendant)
```

Démarrage : parallélisme sûr entre branches indépendantes ; ordre topologique pour les arêtes.

## Process / Health / Readiness

Chaque service expose trois axes :

| Axe | Signifie |
|-----|----------|
| `process` | Processus / conteneur présent |
| `health` | Endpoint / probe OK |
| `readiness` | Capacité métier (ex. modèle LM chargé) |

Exemple LM Studio : `process=running`, `health=healthy`, `readiness=loading` → **pas** « Assistant prêt ».

États globaux : `healthy` | `degraded` | `recovering` | `offline` | `error`.

## Startup sequence

1. Windows démarre → tâche Supervisor
2. Tick : probe tous les services
3. Services required absents → start minimal
4. Attente health puis readiness
5. Snapshot `data/supervisor/status.json` + API locale

## Auto-repair (minimum blast radius)

Pipeline : discover → diagnose → plan minimal → execute → verify.

Règles (`src/lib/infrastructure/repair-planner.ts` + exécuteur Supervisor) :

- ne redémarre **que** les services down (+ dépendances down)
- `searxng` down, reste OK → SearXNG seul
- `docker` + `searxng` down → Docker puis SearXNG
- tunnel down, Next OK → tunnel seul
- `crashLoop` → **aucune** action restart (circuit ouvert)
- LLM **jamais** décideur opérationnel

Après réparation, le plan liste `untouchedServiceIds`.

## Crash-loop

Fenêtre + `maxRestarts` + backoff exponentiel → `SERVICE_UNSTABLE` / `crashLoop: true`.
Notification iOS ; bouton « Réparer » / réessai manuel uniquement.

## Power

`HostPowerController` (`src/lib/host/power-controller.ts`) :

| Action | Mécanisme |
|--------|-----------|
| wake | `CHATBOT_WAKE_URL` (Worker existant) — pas de secret en code |
| shutdown | `scheduleHostPcShutdown` |
| restart | `shutdown.exe /r` (Windows) |

Reboot PC = dernier recours (jamais premier réflexe du repair planner).

## API locale Supervisor (`127.0.0.1:3927`)

| Méthode | Chemin | Rôle |
|---------|--------|------|
| GET | `/health` | Liveness |
| GET | `/status` | Snapshot |
| POST | `/repair` | Body optionnel `{ "serviceId" }` |

Fichiers : `status.json`, `command.json`, `incidents.json`, `repair.lock`.

## API authentifiée (Next.js)

Auth : `withAuth` + `apiAuthGuard` (Bearer `chs_` ou Cloudflare Access).  
Pas de `POST /api/exec` ni commandes shell arbitraires.

| Méthode | Chemin |
|---------|--------|
| GET | `/api/infrastructure/status` |
| GET | `/api/infrastructure/incidents` |
| POST | `/api/infrastructure/diagnose` |
| POST | `/api/infrastructure/repair` |
| GET/POST | `/api/infrastructure/power` (+ `/wake` `/shutdown` `/restart`) |

## iOS

- Settings → **État du système** (`SystemStatusView`) — détails techniques ici seulement
- `InfrastructureStore` + bannières contextuelles Chat / Mail / Files
- Pas de dashboard permanent ; pas de jaune structurel

## Security

Opérations power / repair authentifiées, actions typées, audit incidents sans secrets ni contenu utilisateur.

## Failure modes

Voir `src/lib/reliability/failure-modes.ts` (domaine `infrastructure` : `docker_down`, `nextjs_down`, `tunnel_down`, `pc_offline`, `crash_loop`, `supervisor_unreachable`).

## Tests

```bash
npx vitest run src/lib/infrastructure
npx vitest run src/lib/reliability
npx tsc --noEmit
```

## Lancer

```bash
npm run supervisor
npm run supervisor:install-task   # Windows Scheduled Task au logon
```

## Troubleshooting

| Symptôme | Piste |
|----------|--------|
| Status stale | Supervisor down → installer la tâche ; lire `data/supervisor/status.json` |
| Repair no-op | `repair.lock` ou crash-loop |
| Wake échoue | `CHATBOT_WAKE_URL` / Worker Access |
| Faux « IA prête » | Vérifier `readiness` LM, pas seulement process |
