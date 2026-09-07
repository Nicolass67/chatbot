# AGENTS.md — Chatbot (iPhone native first)

## Arbre unique (obligatoire)

| Chemin | Statut |
|--------|--------|
| **`D:\chatbot-public`** | **Seul dépôt actif** (code, SQLite `data/`, boot WoL, Worker local, tâches Windows) |
| `D:\Chatbot` / `D:\Chatbot.CONDEMNED` | **Condamné** — ne plus lancer, ne plus modifier, ne plus y pointer de tâche |

Les tâches `ChatbotConditionalBoot` / `ChatbotBootPoll` et le Supervisor doivent toujours cibler `D:\chatbot-public`. Secrets boot : `deploy/boot/machine.env` (gitignored) dans **ce** dépôt seulement.

## Produit prioritaire

| Client | Stack | Emplacement | Priorité |
|--------|--------|-------------|----------|
| **iPhone SwiftUI** | Native | `apps/ios/ChatbotNative/` (`fr.nicolazer.chatbot.native`) | **Principale** |
| Backend | Next API + `src/lib/**` + SQLite + LM Studio | PC (`D:\chatbot-public`) | Dépendance technique |
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
[ ] Fin de tâche feature iPhone : commit → push → npm.cmd run ios:deploy:wifi
      (Flash IPA → download → sign local → Trusted Tunnel RSD → install → launch)
[ ] USB fallback seulement si Wi-Fi échoue : ios:deploy:usb / ios:deploy:auto
[ ] Pas de Simulator / Contracts / Full CI / screenshots sans demande explicite
[ ] Aucun secret Apple / 2FA / pairing dans git ou logs
```

## Install iPhone — scripts obligatoires (ne pas inventer)

Toujours les **mêmes** commandes npm (jamais des one-shot Python / scans LAN bricolés à la place) :

| But | Commande |
|-----|----------|
| Déployer (build Flash + install Wi‑Fi) | `npm.cmd run ios:deploy:wifi` |
| Install seule (IPA déjà là) | `npm.cmd run ios:install:wifi` |
| Fallback câble | `npm.cmd run ios:deploy:usb` / `ios:install:usb` |

**Dual-NIC (PC Ethernet + Wi‑Fi)** : le téléphone est sur le **LAN Wi‑Fi**, souvent un autre `/24` que l’Ethernet. Ne **pas** conclure « RemotePairing mort » après un scan Ethernet seul. S’assurer que le Wi‑Fi PC est **connecté** au même SSID que l’iPhone ; `wifi_rsd_deploy.py` scanne tous les `/24` locaux (Wi‑Fi d’abord).

## Pipeline autonome (défaut)

Voir `docs/IOS-AUTONOMOUS-DEPLOY.md`.

Ne pas demander confirmation pour : commit, push, Flash IPA, download IPA, install Wi‑Fi, launch, retry deploy.
Ne rebuild pas GHA si seule l’étape install/tunnel échoue — réutiliser l’IPA.

## Références

- Plan mobile : `docs/MOBILE-2.0-IMPLEMENTATION-PLAN.md`
- État mobile : `docs/MOBILE-CURRENT-STATE.md`
- Shell iOS : `apps/ios/README.md`
- Architecture Swift : `docs/ARCHITECTURE-SWIFT-NATIVE.md`
- Auth app : `docs/adr/001-app-session-bearer.md`
- QA autonome : `docs/IOS-AUTONOMOUS-QA.md`
- Deploy autonome : `docs/IOS-AUTONOMOUS-DEPLOY.md`
