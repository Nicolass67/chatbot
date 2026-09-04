# Chatbot Native (SwiftUI) — Mobile 3.0

Bundle ID : `fr.nicolazer.chatbot.native`  
**Marketing : 3.0.0** (build 14) · **iOS 26.0+** · Xcode **26.6** (CI pin) · Swift 6

Client iOS **principal**. Capacitor (`fr.nicolazer.chatbot`) = fallback gelé (`workflow_dispatch` only).

## Build IPA

GitHub Actions → **iOS Native IPA (unsigned)** → artifact `chatbot-ios-native-unsigned`  
Runner : `macos-26` · pin `/Applications/Xcode_26.6.app`  
CI lance unit tests + gate SDK.

## Auth

ASWebAuthenticationSession → `chs_` Keychain (+ userId / expiresAt) · Face ID optionnel

## Navigation (Mobile 3.0)

**Chat | Mail | Files** (3 tabs)  
- Chat ouvre une **nouvelle conversation** (historique = switcher)  
- Réglages / Mémoire = sheet (plus de tab « Plus »)

## Docs

- Master plan : [`docs/MOBILE-2.0-IMPLEMENTATION-PLAN.md`](../../docs/MOBILE-2.0-IMPLEMENTATION-PLAN.md) (Mobile 3.0)
- État : [`docs/MOBILE-CURRENT-STATE.md`](../../docs/MOBILE-CURRENT-STATE.md)
- Parité : [`docs/MOBILE-PARITY-MATRIX.md`](../../docs/MOBILE-PARITY-MATRIX.md)
- Visual QA : [`docs/MOBILE-VISUAL-QA.md`](../../docs/MOBILE-VISUAL-QA.md)
- **Autonomous QA (Cursor ↔ iPhone)** : [`docs/IOS-AUTONOMOUS-QA.md`](../../docs/IOS-AUTONOMOUS-QA.md)

## QA rapide (Windows + iPhone USB)

```powershell
pip install -r requirements-ios-qa.txt
npm.cmd run ios:mount
npm.cmd run ios:launch
npm.cmd run ios:screenshot
node scripts/ios/qa.mjs qa --device --label smoke
```

Voir la matrice PHYSICAL vs SIMULATOR dans `docs/IOS-AUTONOMOUS-QA.md`.
