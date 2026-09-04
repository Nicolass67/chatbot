# AGENTS.md — Chatbot (Web React + futur iOS SwiftUI)

## Architecture clients

| Client | Stack | Emplacement |
|--------|--------|-------------|
| Web / PC | Next.js + React | `src/app/**` (pages), `src/components/**` |
| iPhone Capacitor | Capacitor remote shell | `capacitor.config.ts`, `ios/` — UI = React remote |
| iPhone SwiftUI | Native Phase C | `apps/ios/` (bundle `fr.nicolazer.chatbot.native`) |
| Backend | Next API + `src/lib/**` + SQLite + LM Studio | PC uniquement |

Les clients consomment les **mêmes** contrats (`contracts/`) et la **Client Surface** (`docs/CLIENT-API.md`).

## Règles de modification

1. **Comportement / API / data** → analyser et mettre à jour si besoin :
   - backend (`src/lib`, `src/app/api`)
   - `contracts/` (+ fixtures / VERSION si breaking)
   - Web React
   - iOS SwiftUI **quand le client existera**
2. **UI pure Web** → React / CSS seulement.
3. **UI pure iOS** → Swift seulement (futur).
4. **Shell Capacitor natif** (`capacitor.config.ts`, plugins) → rebuild IPA ; pas pour une modif `src/` Next.
5. **Métier** reste serveur : PathGuard, OAuth tokens, orchestrateur, SQLite — jamais dans un client.
6. **Ne pas** contourner Cloudflare Access. `X-Client` n’est **jamais** une autorisation.
7. **Ne pas** stocker Apple ID / certificats / secrets OAuth dans GitHub Actions.

## Contrats

- Source publiée : `contracts/` (`VERSION`, schemas, fixtures SSE).
- Breaking change schema / event / error code retiré → bump `contracts/VERSION` + CI.
- SSE : ignorer les `type` inconnus (forward compatible).
- Handoffs : références métier (IDs) ; pas seulement des URLs Next.

## Checklist PR (agent)

```
[ ] contracts/VERSION bump si breaking
[ ] fixtures SSE / schemas à jour si chat events ou handoffs
[ ] Client Surface (docs/CLIENT-API.md) si nouvel endpoint public
[ ] Web React impacté ?
[ ] iOS Swift impacté ? (N/A tant que pas d’app native)
[ ] Capacitor rebuild nécessaire ? (native only)
[ ] X-Client non utilisé pour auth
[ ] Tests Vitest / contracts CI green
```

## Références

- Plan B0/B : `docs/IMPLEMENTATION-PLAN-B0-B.md`
- Statut B0/B : `docs/B0-B-STATUS.md` (**B0+B GO**)
- Gate phase C : `docs/PHASE-C-GATE.md` / shell : `apps/ios/README.md`
- Architecture Swift (étude) : `docs/ARCHITECTURE-SWIFT-NATIVE.md`
- Auth app (ADR, code reporté) : `docs/adr/001-app-session-bearer.md`
- iOS ops : `docs/IOS-CAPACITOR.md`, `docs/B0-DEVICE-CHECKLIST.md`
