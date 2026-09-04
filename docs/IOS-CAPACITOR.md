# iOS Capacitor — runbook (shell remote stable)

> **FALLBACK ONLY — Mobile 3.0**  
> Aucune nouvelle feature Capacitor. Produit iPhone = app native `fr.nicolazer.chatbot.native`.  
> Freeze / exit : [`MOBILE-3.0-CAPACITOR-EXIT.md`](MOBILE-3.0-CAPACITOR-EXIT.md).  
> Workflow Cap : `workflow_dispatch` uniquement.

Architecture verrouillée :

```
iPhone (Capacitor / WKWebView)
  → HTTPS même hostname public (server.url)
  → Cloudflare Access
  → Worker VPC / Tunnel
    → Next.js (PC Windows)
    → SQLite / Files / Gmail / SearXNG / LM Studio
```

Règles non négociables :

- `server.url` = origin principale ; contenu applicatif **100 % remote**.
- Bundle iOS = coquille stable uniquement.
- `allowNavigation` = domaine Chatbot **+** hôtes Cloudflare Access **+** IdP Google (sinon iOS ouvre Chrome et casse la session).
- Externes hors allowNavigation → `@capacitor/browser`.
- **OAuth Gmail API** = navigation **dans la même WKWebView** (`openGmailOAuthStart` → `location.assign`), pas Browser externe.
- Pas de Face ID / Push / Siri / Camera en V1.
- Ne jamais désactiver Cloudflare Access (edge) pour « faire marcher » iOS.

## Opérateur — stack pour tests iPhone

Les tests iPhone doivent viser une stack **production**, pas `next dev` :

```powershell
# Windows — build + next start (USERPROFILE isolé si besoin)
npm.cmd run start:fast
```

`next dev` (Turbopack) via tunnel = cold compile → écran noir ~1 min : **faux positif** « app cassée ».

Préparer l’IPA pour iloader (sans secrets Apple) :

```powershell
npm.cmd run ios:deploy-prep
```

## allowNavigation (référence code)

Source : `capacitor.config.ts` — tout ajout/retrait = **rebuild IPA**.

| Hôte | Rôle |
|------|------|
| `your-worker.example.workers.dev` (ou host de `capacitor.local.json`) | App |
| `*.cloudflareaccess.com` + team + `oauth-callbacks` | Access |
| `dash.cloudflare.com` | IdP Cloudflare |
| `accounts.google.com`, `accounts.youtube.com`, `google.com`, `www.google.com` | IdP Google (Access) |

## Mises à jour

| Changement | Rebuild iOS ? |
|------------|---------------|
| Next.js / React / CSS / API / orchestrateur / SQLite / prompts | **Non** |
| Capacitor / plugin / Info.plist / appId / `server.url` / assets natifs / `allowNavigation` | **Oui** (GHA → IPA → SideStore) |

---

## URL (placeholder public)

```
ORIGIN_CAPACITOR=https://your-worker.example.workers.dev
```

Override local (gitignored) : `capacitor.local.json` → `publicOrigin` / `accessTeamHost`.

Aligner :

- `.env.local` → `PUBLIC_BASE_URL`
- `.env.local` → `GOOGLE_OAUTH_REDIRECT_URI` = `https://your-worker.example.workers.dev/api/oauth/gmail/callback` (ou ton origin réel en local)
- Google Cloud Console → Authorized redirect URIs = **exactement** cette URI
- `deploy/cloudflared/tunnel.env` → `PUBLIC_CHATBOT_URL`

Access team (placeholder) : `your-team.cloudflareaccess.com`
`CF_ACCESS_ENABLED=true` + `CF_ACCESS_AUD` / `CF_ACCESS_TEAM_DOMAIN`  
`HEALTH_CHECK_TOKEN` : Next + Worker (health VPC) — **pas** une session utilisateur.

## État technique (2026-09-03)

| Prérequis | État | Détail |
|-----------|------|--------|
| Next.js local (prod) | OK | `start:fast` |
| CF Access edge | OK | sans cookie → login Access |
| Origin JWT verify | OK | JWKS (`keys`) |
| Worker health VPC | OK | Bearer health |
| `allowNavigation` Access+Google | OK | **Validé iPhone** 2026-09-03 |
| Gmail OAuth same-WebView | OK | **Validé iPhone** 2026-09-03 (+ console Google) |
| Mac local | Non | build via GitHub Actions macOS |
| Apple Developer payant | Non | SideStore + Apple ID gratuit |

## Workflow IPA 0 €

```
Windows (Cursor / Next)
  → git push (changement natif seulement)
  → GitHub Actions macOS → IPA unsigned
  → iloader Import IPA / SideStore + Apple ID gratuit
  → App HTTPS remote → Access → Next sur PC
```

Voir aussi : [`IOS-INSTALL.md`](IOS-INSTALL.md), checklist B0 : [`B0-DEVICE-CHECKLIST.md`](B0-DEVICE-CHECKLIST.md).

Vérif config : `npm.cmd run cap:verify`
