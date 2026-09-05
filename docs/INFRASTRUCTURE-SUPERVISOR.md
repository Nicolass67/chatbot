# Infrastructure Supervisor

Processus Node **indépendant** de Next.js qui surveille et répare la stack locale avec un blast radius minimal.

## Services (IDs canoniques)

| id | Rôle | Critique |
|----|------|----------|
| `docker` | Moteur conteneurs | optional |
| `searxng` | Recherche Web (dépend de `docker`) | optional |
| `nextjs` | Chatbot / API | **required** |
| `lm_studio` | Assistant IA (readiness = modèle chargé) | optional |
| `cloudflared` | Tunnel / ingress (dépend de `nextjs`) | optional |

Contrats TypeScript : `src/lib/infrastructure/types.ts`  
(`ServiceStatusSnapshot`, `InfrastructureStatus`, plans de réparation).

## Lancer

```bash
npm run supervisor
# équivalent : node scripts/supervisor/index.mjs
```

Windows (tâche planifiée au logon) :

```bash
npm run supervisor:install-task
```

## API locale Supervisor (`127.0.0.1:3927`)

| Méthode | Chemin | Rôle |
|---------|--------|------|
| GET | `/health` | Liveness |
| GET | `/status` | Snapshot `InfrastructureStatus` |
| POST | `/repair` | Body optionnel `{ "serviceId" }` |

Fichiers sous `data/supervisor/` : `status.json`, `command.json`, `incidents.json`, `repair.lock`.

## API authentifiée (Next.js)

Auth : `withAuth` + `apiAuthGuard` (Bearer app `chs_` ou Cloudflare Access).

| Méthode | Chemin | Rôle |
|---------|--------|------|
| GET | `/api/infrastructure/status` | Supervisor HTTP → fallback fichier |
| GET | `/api/infrastructure/incidents` | Historique |
| POST | `/api/infrastructure/diagnose` | Plan minimal (sans exécution) |
| POST | `/api/infrastructure/repair` | Repair via Supervisor ou enqueue commande |
| GET | `/api/infrastructure/power` | État alimentation |
| POST | `/api/infrastructure/power/wake` | Wake (`CHATBOT_WAKE_URL`) |
| POST | `/api/infrastructure/power/shutdown` | Extinction hôte |
| POST | `/api/infrastructure/power/restart` | Redémarrage hôte |

## Réparation minimale

`buildMinimalRepairPlan` (`src/lib/infrastructure/repair-planner.ts`) :

- ne touche que les services réellement down (+ dépendances down)
- ordre topologique (ex. `docker` avant `searxng`)
- `crashLoop` → aucune action de restart (circuit ouvert)
- `lm_studio` process up + `readiness: not_ready` → `reload_model`, pas de full restart

## Power

`HostPowerController` (`src/lib/host/power-controller.ts`) implémente `PowerController` :

- `shutdown` → `scheduleHostPcShutdown`
- `restart` → `shutdown.exe /r` (Windows)
- `wake` → `CHATBOT_WAKE_URL` (optionnel)

## Tests

```bash
npx vitest run src/lib/infrastructure
```

Voir aussi `docs/RELIABILITY.md` — section *Application reliability vs Infrastructure supervision*.
