# AGENTS.md — Chatbot (iPhone native first)

## Produit prioritaire

| Client | Stack | Emplacement | Priorité |
|--------|--------|-------------|----------|
| **iPhone SwiftUI** | Native | `apps/ios/ChatbotNative/` (`fr.nicolazer.chatbot.native`) | **Principale** |
| Backend | Next API + `src/lib/**` + SQLite + LM Studio | PC | Dépendance technique |
| Web / PC | Next.js + React | `src/app/**`, `src/components/**` | Hors scope UX |
| Capacitor | Remote shell | `capacitor.config.ts`, `ios/` | Gelé / hors cible |

Les clients consomment les **mêmes** contrats (`contracts/`) et la **Client Surface** (`docs/CLIENT-API.md`).

## Règles de modification

1. **UX / UI / navigation / Chat / Mail / Files / Assistant** → **uniquement** `apps/ios/ChatbotNative/` (Swift).
2. **Bug iPhone** → diagnostiquer d’abord Swift (`APIClient`, stores, vues, navigation). TypeScript seulement si l’endpoint backend est réellement en cause.
3. **Backend** → plus petite modif possible si l’API manque de données pour le natif ; **ne pas** retoucher l’UI desktop.
4. **Métier** reste serveur : PathGuard, OAuth tokens, orchestrateur, SQLite — jamais dans un client.
5. **Ne pas** contourner Cloudflare Access. `X-Client` n’est **jamais** une autorisation.
6. **Ne pas** stocker Apple ID / certificats / secrets OAuth dans GitHub Actions.

## Contrats

- Source publiée : `contracts/` (`VERSION`, schemas, fixtures SSE).
- Breaking change schema / event / error code retiré → bump `contracts/VERSION`.
- SSE : ignorer les `type` inconnus (forward compatible).
- Handoffs : références métier (IDs) ; pas seulement des URLs Next.

## Checklist agent (iOS)

```
[ ] Changement dans apps/ios/ChatbotNative/ (ou backend minimal si nécessaire)
[ ] Pas de modif UX/UI Web / Capacitor sans nécessité démontrée
[ ] contracts/VERSION bump si breaking API
[ ] X-Client non utilisé pour auth
[ ] Fin de tâche : commit → push → npm.cmd run ios:ipa:flash uniquement
[ ] Pas de Simulator / Contracts / Full CI sans demande explicite
```

## Références

- Plan mobile : `docs/MOBILE-2.0-IMPLEMENTATION-PLAN.md`
- État mobile : `docs/MOBILE-CURRENT-STATE.md`
- Shell iOS : `apps/ios/README.md`
- Architecture Swift : `docs/ARCHITECTURE-SWIFT-NATIVE.md`
- Auth app : `docs/adr/001-app-session-bearer.md`
- QA autonome : `docs/IOS-AUTONOMOUS-QA.md`
