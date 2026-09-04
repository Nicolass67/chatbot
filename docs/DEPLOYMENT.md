# Déploiement PC Windows + Cloudflare Tunnel

Architecture cible :

```
Internet (4G/5G)
      ↓ HTTPS
Cloudflare Edge (certificat, DDoS, Access)
      ↓ tunnel sortant chiffré (aucun port entrant sur Freebox)
cloudflared (PC Windows)
      ↓ localhost uniquement
Next.js :3000
      ├── SQLite (data/local.db)
      ├── fichiers (data/attachments/)
      ├── mémoire / agent / recherche
      ├── SearXNG (localhost:8080) — non exposé
      └── LM Studio (localhost:1234) — non exposé
```

## Choix d'architecture Cloudflare (vérifié doc 2026)

| Option | SSE `/api/chat` | Production | Coût |
|--------|-----------------|------------|------|
| **Quick Tunnel** (`trycloudflare.com`) | ❌ Non supporté | Non | Gratuit |
| **Tunnel nommé** (dashboard Zero Trust) | ✅ Oui | **Oui — choix requis** | Gratuit |
| **Cloudflare Access** (auth) | ✅ Compatible | Recommandé | Gratuit ≤ 50 users |

Le Chatbot utilise du **SSE streaming** avec heartbeat 15 s et headers `text/event-stream` + `X-Accel-Buffering: no` — compatible tunnel nommé, **incompatible Quick Tunnel**.

**Aucun port forwarding** sur la Freebox : `cloudflared` ouvre une connexion **sortante** vers Cloudflare.

## Prérequis

### Sur le PC Windows

1. **Node.js 20+** et dépendances (`npm install`)
2. **LM Studio** serveur local port `1234` (si chat IA local)
3. **SearXNG** Docker port `8080` (si recherche web activée) : `npm run searxng:start`
4. **cloudflared** installé :
   ```powershell
   winget install Cloudflare.cloudflared
   ```

### Compte Cloudflare (gratuit)

1. Compte [Cloudflare](https://dash.cloudflare.com) + **Zero Trust** activé (plan Free)
2. **Un nom de domaine** ajouté à Cloudflare (plan DNS Free suffit)
   - Pas besoin d'acheter un domaine **si vous en possédez déjà un**
   - Exemple d'URL : `https://chatbot.votre-domaine.fr`
   - Sans domaine dans Cloudflare, impossible d'obtenir une URL HTTPS stable pour un tunnel nommé

## Variables d'environnement

Copiez `.env.example` vers `.env.local`. **Ne commettez jamais `.env.local`.**

| Variable | Dev local | Production (tunnel) |
|----------|-----------|---------------------|
| `LM_STUDIO_BASE_URL` | `http://localhost:1234/v1` | idem |
| `LM_STUDIO_API_KEY` | `lm-studio` | idem |
| `DATABASE_URL` | `./data/local.db` | idem |
| `RUNTIME_MODE` | `local` | `local` |
| `CF_ACCESS_ENABLED` | `false` | **`true`** |
| `CF_ACCESS_TEAM_DOMAIN` | vide | ex. `votre-equipe.cloudflareaccess.com` |
| `CF_ACCESS_AUD` | vide | Audience tag Access |
| `HEALTH_CHECK_TOKEN` | vide | Token fort (WoL futur uniquement) |

L'**Audience tag (AUD)** : Zero Trust → Access → Applications → votre app → Application Audience (AUD) Tag.

### Secrets tunnel (hors `.env.local` Next.js)

Copiez `deploy/cloudflared/tunnel.env.example` → `deploy/cloudflared/tunnel.env` (gitignored) :

```env
CLOUDFLARE_TUNNEL_TOKEN=eyJ...
PUBLIC_CHATBOT_URL=https://chatbot.votre-domaine.fr
```

## Configuration Cloudflare (une fois)

### 1. Créer le tunnel nommé

1. [Cloudflare Zero Trust](https://one.dash.cloudflare.com) → **Networks** → **Tunnels**
2. **Create a tunnel** → nom : `chatbot`
3. **Install connector** → copier le **token** dans `deploy/cloudflared/tunnel.env`
4. **Public Hostname** :
   - Subdomain : `chatbot` (ou autre)
   - Domain : votre domaine
   - Service : `http://localhost:3000`
5. Enregistrer — Cloudflare crée le CNAME DNS automatiquement

### 2. Cloudflare Access (authentification)

1. Zero Trust → **Access** → **Applications** → **Add an application**
2. Type : **Self-hosted**
3. Application domain : `chatbot.votre-domaine.fr` (même hostname que le tunnel)
4. Identity provider : **One-time PIN** (email) pour usage personnel
5. Policy : **Allow** — votre email
6. Copier l'**AUD tag** → `CF_ACCESS_AUD` dans `.env.local`
7. Team domain (ex. `xxx.cloudflareaccess.com`) → `CF_ACCESS_TEAM_DOMAIN`

### 3. Activer l'auth côté Next.js

Dans `.env.local` :

```env
CF_ACCESS_ENABLED=true
CF_ACCESS_TEAM_DOMAIN=votre-equipe.cloudflareaccess.com
CF_ACCESS_AUD=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Redémarrer Next.js après modification.

## Démarrage production

Terminal 1 — Next.js :

```powershell
cd D:\Chatbot
npm run build
npm run start:prod
```

Terminal 2 — Tunnel :

```powershell
npm run tunnel:run
```

Services requis sur le PC :

1. LM Studio (`:1234`)
2. SearXNG (`npm run searxng:start`) si web search activée
3. Next.js (`npm run start:prod`, port 3000)
4. cloudflared (`npm run tunnel:run`)

## Vérification

```powershell
npm run deploy:verify
```

- `local-health` : `GET http://127.0.0.1:3000/api/health`
- `local-sse` : vérifie `Content-Type: text/event-stream` sur `POST /api/chat`
- `public-health` : si `PUBLIC_CHATBOT_URL` est défini

Test manuel téléphone (4G) : ouvrir `https://chatbot.votre-domaine.fr` → page Access → chat.

## Routes protégées

Quand `CF_ACCESS_ENABLED=true`, le middleware exige un JWT Cloudflare Access (`Cf-Access-Jwt-Assertion`) pour `/`, `/chat/*`, `/settings/*`, `/api/*`.

Exception : `GET /api/health` avec `Authorization: Bearer <HEALTH_CHECK_TOKEN>` (automation WoL futur).

## Sécurité

1. **Cloudflare Access** = auth utilisateur (OTP email, SSO)
2. **JWT vérifié côté origin** — requête sans JWT valide → `401`
3. **LM Studio / SearXNG / SQLite** restent sur localhost
4. **Secrets** : `.env.local`, `deploy/cloudflared/tunnel.env` — jamais dans Git
5. **Pas de WoL / app_token Freebox** dans Cloudflare pour cette étape

## Dépannage SSE

- Ne pas utiliser Quick Tunnel (`cloudflared tunnel --url ...`)
- Vérifier tunnel **nommé** avec hostname public
- Headers SSE déjà configurés dans `src/app/api/chat/route.ts`
- Heartbeat 15 s maintient la connexion active

## Wake-on-LAN (Worker → Freebox)

Le Worker envoie le WoL via l'API HTTPS distante de la Freebox (`POST /wake`).

### Démarrage conditionnel après WoL Worker

Quand le PC est éteint, le Worker crée une **demande de démarrage temporaire** (KV Cloudflare, TTL 5 min) **avant** d'envoyer le WoL.

Au démarrage Windows (tâche planifiée à la connexion), un script vérifie `GET /boot-request` sur le Worker.  
S'il n'y a **pas** de demande valide → **aucun** service Chatbot n'est lancé (démarrage manuel du PC).

| Composant | Rôle |
|-----------|------|
| `POST /wake` | Crée la demande KV + WoL Freebox |
| `POST /start-services` | Crée la demande KV **sans** WoL (PC déjà allumé, démarrage simple) |
| `POST /restart-services` | Crée une demande **restart** — arrêt propre puis relance |
| `GET /boot-request` | Le PC demande s'il doit démarrer (auth machine) |
| `POST /boot-request` | Consomme la demande (une seule fois) |
| `scripts/boot/conditional-start.mjs` | Orchestration Windows |
| Tâche `ChatbotConditionalBoot` | Déclenchement à la connexion |
| Tâche `ChatbotBootPoll` | Sonde toutes les 2 min si PC déjà allumé (`POST /start-services`) |

**Page offline Worker** (quand Next.js est down) : **Allumer le PC** (`POST /wake`) et **Relancer les services** (`POST /restart-services` — arrêt puis relance, modèle LM Studio déchargé puis rechargé).

**Optimisations boot (implémentées) :**

- Dès qu'une demande `pending` est détectée : **préchauffage immédiat** (pendant l'appel Worker)
- **Parallèle** : Docker + LM Studio + chargement modèle + Next.js
- **SearXNG lazy** : démarre en arrière-plan dès que Docker est prêt — le chat est utilisable avant la recherche web
- Chargement modèle via **`lms load -y`** quand le CLI est disponible
- Worker + cloudflared interrogés en parallèle après le réseau

**Préchauffage Windows au login (optionnel, PC serveur) :**

```powershell
# Docker Desktop au démarrage de session (~30-60 s gagnées au WoL)
npm run boot:enable-warm-autostart

# Ou avec réinstallation de la tâche boot :
.\scripts\boot\install-startup-task.ps1 -WarmAutostart

# LM Studio serveur au login aussi (consomme RAM/GPU au repos) :
.\scripts\boot\install-startup-task.ps1 -WarmAutostart -WarmLmStudio

# Désactiver :
powershell -File scripts\boot\enable-warm-autostart.ps1 -Disable
```

**Accélérer le démarrage Windows (~45 s) :**

| Action | Gain typique | Note |
|--------|--------------|------|
| **Connexion automatique** Windows | 10–30 s | La tâche `ChatbotConditionalBoot` ne tourne qu'**à la connexion**, pas au POST. Sans auto-login, WoL réveille le PC mais Chatbot attend que tu te connectes. |
| Désactiver apps au démarrage | 5–15 s | Paramètres → Applications → Démarrage |
| BIOS **Fast Boot** / boot NVMe | variable | Désactiver POST logo, priorité disque NVMe |
| Docker Desktop « Démarrer à la connexion » | 0 s* | Si déjà prêt, le script skip le lancement (* consomme RAM au repos) |
| LM Studio via `lms server start` au login | 0 s* | Idem — API déjà up = skip instantané |

> **WoL + Fast Startup :** le « démarrage rapide » Windows (hybrid shutdown) peut parfois compliquer le WoL. Si le réveil réseau échoue après un arrêt « normal », tester un arrêt complet (`shutdown /s /t 0`) ou désactiver le démarrage rapide dans les options d'alimentation.

**Secrets (hors Git) :**

1. Worker : `npx wrangler secret put BOOT_MACHINE_TOKEN` (dans `workers/chatbot/`)
2. PC : copier `deploy/boot/machine.env.example` → `deploy/boot/machine.env` avec le **même** token

**Installation tâche Windows :**

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
d:\Chatbot\scripts\boot\install-startup-task.ps1

# PC déjà allumé — détecter POST /start-services depuis le téléphone :
d:\Chatbot\scripts\boot\install-poll-task.ps1
# ou : npm run boot:install-poll-task
```

**Test sans éteindre le PC :**

```powershell
# 1. Créer une demande (navigateur, session Access) :
#    - PC éteint → bouton « Allumer le PC » (POST /wake)
#    - PC allumé, services down ou cassés → bouton « Relancer les services » (POST /restart-services)
# 2. Vérifier sans démarrer les services :
npm run boot:conditional:dry-run
# 3. Démarrage réel de la stack :
npm run boot:conditional
# 4. Sonde manuelle (PC allumé) :
npm run boot:poll
```

Journal boot connexion : `data/boot-conditional.log`  
Journal sonde PC allumé : `data/boot-poll.log`

### Cause de l'erreur « Réponse Freebox illisible » / HTTP 526

Le domaine par défaut `*.fbxos.fr` (ex. `xxxx.fbxos.fr:443`) utilise un certificat signé par la **CA privée Freebox**. Les Workers Cloudflare refusent cette chaîne TLS (équivalent navigateur sans certificat racine Freebox → **error 526**).

`wrangler cert upload certificate-authority` ne corrige **pas** ce cas : il sert à Hyperdrive/mTLS, pas aux `fetch()` sortants du Worker.

### Correctif recommandé : domaine `*.freeboxos.fr` (Let's Encrypt)

1. Freebox OS → **Paramètres de la Freebox** → **Nom de domaine**
2. Réserver un sous-domaine `votre-nom.freeboxos.fr` et activer le certificat **Let's Encrypt**
3. Attendre la validation Free (jusqu'à 24 h)
4. Noter le **port HTTPS API** (souvent visible dans la gestion des accès distants)
5. Mettre à jour le Worker (`workers/chatbot/wrangler.jsonc`) :
   - `FREEBOX_API_DOMAIN` → `votre-nom.freeboxos.fr`
   - `FREEBOX_HTTPS_PORT` → port HTTPS configuré (souvent `443`)
6. Redéployer : `cd workers/chatbot && npm run deploy`
7. Vérifier sans rallumer le PC : `GET /freebox-probe` doit retourner `ok: true` et `hasChallenge: true`

### Alternative (si vous avez un domaine dans Cloudflare)

Custom Origin Trust Store (zone + Advanced Certificate Manager) + flag `cots_on_external_fetch` + upload des CA racines Freebox. Nécessite **au moins une zone** sur le compte Cloudflare. Moins simple que `freeboxos.fr`.

### Prérequis Freebox (app API)

- Permission **`settings`** pour l'application API (WoL)
- **`wol`** activé dans la config connexion Freebox
- Secret Worker `FREEBOX_APP_TOKEN` configuré (`wrangler secret put FREEBOX_APP_TOKEN`)
