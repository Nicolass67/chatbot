# ADR 001 — Session Bearer applicative (Swift)

**Statut :** Accepted / **Implemented (Phase C)**  
**Date :** 2026-09-03

## Contexte

- Web + Capacitor : cookies Cloudflare Access + JWT assertion.
- Client SwiftUI : `URLSession` + Bearer app (`chs_…`) en Keychain.

## Décision (implémentée)

1. Access **reste** obligatoire pour **obtenir** une session (`GET /api/auth/app-session/start` derrière Access).
2. `POST /api/auth/app-session` crée aussi une session si déjà authentifié.
3. Token opaque `chs_` + hash SHA-256 en table `app_sessions`, TTL 7 j, révocable.
4. Middleware / `authenticateRequest` : Access JWT **ou** Bearer app (pas le `HEALTH_CHECK_TOKEN`).
5. `X-Client` = télémétrie uniquement.

## Edge Cloudflare

Pour que le Bearer atteigne Next sans cookie Access : **Bypass Access sur `/api/*`** (UI HTML reste protégée). Voir `apps/ios/README.md`.

## Non-goals

- Désactiver Access pour le login.
- Réutiliser `HEALTH_CHECK_TOKEN` comme session user.
