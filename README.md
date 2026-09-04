# Chatbot Local — LM Studio

Application web de chatbot IA **100 % locale** utilisant LM Studio comme moteur LLM, SQLite pour la persistance, et une recherche Web optionnelle.

## Architecture V1

```
Browser → Next.js → Agent → web_search() → SearXNG → moteurs configurés → SQLite (data/local.db)
                              ↓
                         LM Studio (LLM local)
```

Aucun service cloud obligatoire. La recherche Web passe par **SearXNG auto-hébergé** (agrégateur de moteurs) et reste **désactivable**. LM Studio, SearXNG et SQLite sont des services indépendants.

## Prérequis

- **Node.js** 20+ (testé avec 24.x)
- **npm** 11+
- **LM Studio** installé avec un modèle chargé
- **GPU** recommandé (ex. RTX 4080 Super) pour l'inférence

## Installation

```bash
npm install
cp .env.example .env.local
npm run db:push
```

### Démarrage recommandé (tout-en-un)

```bash
npm run start:local
```

Ce script :
1. Vérifie si SearXNG répond déjà sur `SEARXNG_URL`
2. Sinon, démarre automatiquement la stack Docker si Docker est disponible
3. Attend le health check JSON (`/search?q=test&format=json`)
4. Lance Next.js (`npm run dev`)

Ensuite, démarrez **LM Studio** (serveur local) pour l'inférence IA.

Ouvrir [http://localhost:3000](http://localhost:3000)

L'interface affiche deux statuts distincts :
- **IA** — connexion LM Studio
- **Web** — SearXNG (health check backend)

### Démarrage classique (sans bootstrap SearXNG)

```bash
npm run dev
```

Utile pour le debug Next.js sans toucher à Docker.

### Commandes SearXNG

```bash
npm run searxng:status   # Health check + état Docker
npm run searxng:start    # Démarrer SearXNG (échoue si indisponible)
npm run searxng:stop     # Arrêter la stack Docker
```

## Configuration LM Studio

1. Ouvrir LM Studio
2. Charger un modèle compatible chat / tool calling
3. Démarrer le **serveur local** (Developer → Local Server)
4. Vérifier que l'API écoute sur `http://localhost:1234`

## Configuration `.env.local`

| Variable | Description | Défaut |
|----------|-------------|--------|
| `LM_STUDIO_BASE_URL` | URL API OpenAI-compatible | `http://localhost:1234/v1` |
| `LM_STUDIO_API_KEY` | Clé factice pour le SDK | `lm-studio` |
| `DATABASE_URL` | Chemin SQLite | `./data/local.db` |
| `RUNTIME_MODE` | `local` (V1) ou `remote` (V2) | `local` |
| `WEB_SEARCH_ENABLED` | Activer recherche Web | `true` |
| `WEB_SEARCH_PROVIDER` | `searxng`, `auto`, `brave`, `duckduckgo` | `searxng` |
| `SEARXNG_URL` | URL instance SearXNG locale | `http://localhost:8080` |
| `WEB_SEARCH_TIMEOUT_MS` | Timeout recherche (ms) | `10000` |
| `BRAVE_SEARCH_API_KEY` | Secours optionnel (mode `auto`) | — |

## Recherche Web avec SearXNG

SearXNG est un **agrégateur** : le chatbot appelle SearXNG, qui interroge les moteurs configurés dans votre instance (Google, Bing, etc.). Le nombre et la disponibilité des moteurs dépendent de **votre** configuration SearXNG — ce n'est pas un accès illimité garanti à tous les moteurs.

Objectif : éviter une dépendance à une API commerciale pour la couche recherche du chatbot.

### Démarrer SearXNG manuellement (Docker)

Si vous préférez gérer Docker vous-même :

```bash
docker compose -f docker-compose.searxng.yml up -d
# ou
npm run searxng:start
```

Vérifier :

```bash
curl "http://localhost:8080/search?q=test&format=json"
# ou
npm run searxng:status
```

Configuration minimale dans `docker/searxng/core-config/settings.yml` (format JSON activé).

Les logs `duckduckgo: engine timeout` ou moteurs `Suspended` dans le conteneur SearXNG indiquent que **certains** moteurs agrégés sont bloqués depuis Docker — ce n'est pas fatal si d'autres répondent.

La config `docker/searxng/core-config/settings.yml` active **duckduckgo**, **qwant**, **wikipedia**, **mwmbl** et désactive les scrapers souvent bloqués (google cse, startpage, brave). **Redémarrez SearXNG** après toute modification :

```bash
npm run searxng:stop
npm run searxng:start
```

Vérification :

```powershell
Invoke-RestMethod "http://localhost:8080/search?q=test&format=json" | Select-Object query, @{n='count';e={$_.results.Count}}
```

### Docker Desktop (Windows)

Pour éviter de lancer Docker manuellement à chaque session :
1. Ouvrir **Docker Desktop**
2. **Settings → General → Start Docker Desktop when you log in**

Le script `npm run start:local` détectera Docker automatiquement et démarrera SearXNG si nécessaire. L'application **ne modifie jamais** les paramètres Windows/Docker Desktop.

Si Docker n'est pas disponible, le chatbot démarre quand même — le statut **Web** affichera « SearXNG indisponible » et seules les fonctions nécessitant le Web seront limitées.

### Modes provider

| Mode | Comportement |
|------|--------------|
| `searxng` (défaut) | SearXNG uniquement |
| `auto` | SearXNG → Brave si `BRAVE_SEARCH_API_KEY` est défini |
| `brave` | Brave Search API (clé requise) |
| `duckduckgo` | Legacy, souvent bloqué en requête serveur |

En cas d'échec SearXNG sur une demande nécessitant des données actuelles, l'Agent **ne fabrique pas** de recommandation basée sur ses connaissances internes.

## Base de données

SQLite dans `data/local.db`. **Backup : copier le dossier `data/`** (fichier `.db` + éventuels fichiers WAL).

```bash
npm run db:push      # Appliquer le schéma
npm run db:studio    # Interface Drizzle Studio
```

## Utilisation

- **Chat** : conversations, streaming, Markdown, code highlighting
- **Recherche Web** : le modèle peut appeler `web_search` (sources affichées)
- **Mémoriser** : bouton cerveau sur vos messages
- **Paramètres** : modèle, temperature, system prompt, mémoire, web
- **Export** : conversations (MD/JSON), mémoire (JSON)

## Confidentialité

| Composant | Localisation |
|-----------|-------------|
| Conversations | SQLite local |
| Mémoire | SQLite local |
| LM Studio | localhost |
| Recherche Web | SearXNG local → moteurs configurés (si activée) |

Désactivez la recherche Web dans Paramètres pour une confidentialité maximale.

## Sécurité Git

Ce dépôt ne doit **jamais** contenir de données privées :

- `.env.local` — configuration locale (utilisez `.env.example` comme modèle)
- `data/` — base SQLite, conversations, mémoires, pièces jointes
- Aucune clé API, token ou mot de passe réel

Copiez `.env.example` vers `.env.local` après le clone. Initialisez la base avec `npm run db:push`.

## Dépannage LM Studio

| Problème | Solution |
|----------|----------|
| « LM Studio inaccessible » | Vérifier que le serveur local est démarré |
| Port incorrect | Ajuster `LM_STUDIO_BASE_URL` dans `.env.local` |
| Modèle non listé | Charger un modèle dans LM Studio puis rafraîchir Paramètres |
| Tool calling échoue | Utiliser un modèle supportant les function tools |

## Dépannage Windows / PowerShell

Si PowerShell affiche *« l'exécution de scripts est désactivée »* en lançant `npm run …`, c'est la politique d'exécution qui bloque `npm.ps1`. **Solutions (au choix) :**

```powershell
# Option 1 — lanceur .cmd (recommandé, sans changer la politique)
.\start-local.cmd

# Option 2 — node directement
node scripts/start-local.mjs

# Option 3 — npm via le wrapper .cmd
npm.cmd run start:local

# Option 4 — assouplir la politique pour votre utilisateur (une fois)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Les scripts `start:local` et `searxng:*` appellent `node` directement dans `package.json` ; seul l'invocation de `npm` depuis PowerShell peut poser problème.

## V1 vs V2 (évolution future)

**V1 (actuel)** : tout sur votre PC, `npm run start:local` (recommandé) ou `npm run dev`.

**V2 (préparé)** : UI hébergée sur Internet → connexion sécurisée → Local Agent sur PC → LM Studio.

Types préparés : `LocalAIRuntime`, `AuthGuard`, `QueuedRequest`, `PowerController`, `IdleManager`.

La V2 permettra :
- Accès depuis iPhone / n'importe où
- Réveil du PC (Wake-on-LAN, si matériel compatible)
- File d'attente des requêtes pendant le démarrage
- Arrêt automatique après inactivité (configurable)

> Wake-on-LAN dépend de la carte mère, BIOS/UEFI, Windows et du réseau — pas de garantie automatique.

## Stack

- Next.js 15.5.24 · React 19 · TypeScript · Tailwind CSS 4
- Drizzle ORM · better-sqlite3 · Zod

## Scripts

```bash
npm run start:local   # Bootstrap SearXNG + Next.js (recommandé)
npm run dev           # Next.js seul (debug)
npm run searxng:start # Démarrer SearXNG via Docker
npm run searxng:stop  # Arrêter SearXNG
npm run searxng:status # Health check SearXNG
npm run build         # Build production
npm run start         # Serveur production
npm run lint          # ESLint
npm test              # Tests unitaires
```
