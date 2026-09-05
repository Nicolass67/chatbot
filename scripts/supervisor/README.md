# Chatbot Supervisor

Processus Node **indépendant** de Next.js. Surveille et répare au minimum :

| id | Probe |
|----|--------|
| `docker` | `docker info` |
| `searxng` | `http://127.0.0.1:8080/` |
| `nextjs` | `http://127.0.0.1:3000/api/health` |
| `lm_studio` | `http://127.0.0.1:1234/v1/models` |
| `cloudflared` | `sc.exe query Cloudflared` |

Dépendances : `searxng` → `docker`, `cloudflared` → `nextjs`.

## Lancer

```bash
node scripts/supervisor/index.mjs
```

Tick toutes les **12 s**. Fichiers sous `data/supervisor/` :

- `status.json` — état courant
- `command.json` — commande one-shot (`repair` | `repair_service` | `diagnose`)
- `incidents.json` — historique
- `repair.lock` — réparation en cours

## API locale (`127.0.0.1:3927`)

- `GET /health`
- `GET /status`
- `POST /repair` — body optionnel `{ "serviceId": "nextjs" }`

Auto-réparation si `failStreak >= 2`. Circuit breaker : 4–5 redémarrages / 15 min → `crashLoop`, pas de repair.

## Windows — tâche planifiée

```powershell
powershell -ExecutionPolicy Bypass -File scripts/supervisor/install-windows-task.ps1
```

Crée **ChatbotSupervisor** (au logon, restart on failure).
