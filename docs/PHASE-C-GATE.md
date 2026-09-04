# Phase C — Gate (SwiftUI shell)

**Prérequis :** B0 **GO** + B **GO**.

## Statut

| Item | État |
|------|------|
| Go utilisateur | **OK** 2026-09-03 |
| API app-session Bearer | **Done** |
| Shell SwiftUI `apps/ios` | **Done** (Chat list + SSE) |
| CI IPA native | **Done** — `ios-native.yml` |
| Capacitor parallèle | **Conservé** (`fr.nicolazer.chatbot`) |
| Bundle native | `fr.nicolazer.chatbot.native` |
| Access Bypass `/api` + Login start | **Done** 2026-09-03 |
| Push + CI IPA | **Done** — artifact `chatbot-ios-native-unsigned` |

## Ops Access (fait 2026-09-03)

| App Access | Path | Policy |
|------------|------|--------|
| Chatbot API Bypass | `…/api` | Bypass Everyone |
| Chatbot Native Login | `…/api/auth/app-session/start` | Allow account members (plus spécifique → Access pour mint Bearer) |
| chatbot - Cloudflare Workers | hostname | **inchangé** (UI / Capacitor) |

Script idempotent : `node scripts/cloudflare-access-api-bypass.mjs`

## Action device

1. Actions → **iOS Native IPA (unsigned)** → SideStore `ChatbotNative-unsigned.ipa`
2. Tester login Access → Chat

## Suite

- **D** : parity Chat (Markdown, PJ, agent UI…)
- **E** : Mail SwiftUI
- **F** : Files SwiftUI
- **G** : retrait Capacitor (seulement après D+E+F)
