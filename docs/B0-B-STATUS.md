# État d’implémentation B0 / B (repo)

**Mis à jour :** 2026-09-03

| Phase | État repo | État device iPhone |
|-------|-----------|-------------------|
| B0.1 docs ops | **Done** | N/A |
| B0.2–B0.7 smokes | Checklists | **GO** — `docs/B0-DEVICE-CHECKLIST.md` (2026-09-03) |
| B1 contracts scaffold | **Done** | N/A |
| B2 SSE + fixtures | **Done** | OK (app rapide + session) |
| B3 API errors | **Done** (surface majeure) | N/A |
| B4 handoffs IDs-first | **Done** | N/A |
| B5 Client Surface | **Done** — `docs/CLIENT-API.md` | N/A |
| B6 meta/version | **Done** — `GET /api/meta/client-api` | N/A |
| B7 auth Bearer | **Spec/ADR only** — `docs/adr/001-app-session-bearer.md` | N/A |
| B8 dual-client Cursor | **Done** — `AGENTS.md` + rule | N/A |
| B9 CI contracts | **Done** — `.github/workflows/contracts.yml` | N/A |

**B0 :** **GO** (device 2026-09-03).  
**B :** **GO** côté repo.  
**C :** **En cours / shell livré** — `apps/ios` + Bearer ; Bypass Access `/api/*` à configurer ; IPA via `ios-native.yml`.  
**SwiftUI :** shell Chat minimal (pas Mail/Files). Capacitor conservé.
