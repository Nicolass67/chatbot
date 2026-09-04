# MOBILE — État actuel (photographie technique)

> **UPDATE 2026-09-03 (Mobile 3.0)** — La source de vérité produit iOS est désormais **SwiftUI native** (`apps/ios`, marketing **3.0.0**, build **22**, phases **P0–P20** côté dev). Capacitor est en **soft freeze** (fallback only). Voir [`MOBILE-3.0-CAPACITOR-EXIT.md`](MOBILE-3.0-CAPACITOR-EXIT.md), [`MOBILE-PARITY-MATRIX.md`](MOBILE-PARITY-MATRIX.md), [`MOBILE-3.0-DEVICE-QA.md`](MOBILE-3.0-DEVICE-QA.md). Le corps historique ci-dessous reste une photographie antérieure (versions 0.6 / Cap full-feature) — ne pas s’y fier pour le statut 3.0.

Document de référence : **ce qui existe réellement dans le repository aujourd’hui**.  
Date de photographie : **2026-09-03**.  
Aucune modification de code associée à ce document.

---

## 1. Executive Summary

Le projet contient **deux applications iOS distinctes**, coexistant dans le même monorepo, avec **deux bundle IDs** différents :

| App | Emplacement | Bundle ID | Version marketing (repo) | Nature |
|-----|-------------|-----------|--------------------------|--------|
| **Capacitor shell** | [`ios/`](ios/) + [`capacitor.config.ts`](capacitor.config.ts) | `fr.nicolazer.chatbot` | `1.0` (Xcode) | Coquille **WKWebView** → UI **100 % Web/React remote** |
| **SwiftUI native** | [`apps/ios/`](apps/ios/) | `fr.nicolazer.chatbot.native` | `0.6.0` / build `8` | App **SwiftUI** native + client HTTP/SSE natif |

Les deux pointent vers la même origin publique :

`https://your-worker.example.workers.dev`

puis Cloudflare Access / Worker / tunnel → Next.js (PC) → SQLite / LM Studio / Mail / Files.

**Conclusion factuelle :** l’app mobile n’est **plus uniquement** Capacitor/WebView. Une seconde app SwiftUI native (Phase C–F, marketing 0.6) existe, buildée en CI, avec chat/mail/files partiels. Capacitor reste le chemin **full-feature** (même UI que le web). SwiftUI est un **client parallèle** en maturation, **pas** un remplacement complet de Capacitor dans le code actuel.

---

## 2. Architecture actuelle

### 2.1 Schéma réel (deux clients)

```
┌─────────────────────────────────────────────────────────────────┐
│                         iPhone (device)                          │
├──────────────────────────────┬──────────────────────────────────┤
│ A) Capacitor App             │ B) Chatbot Native (SwiftUI)      │
│ bundle: fr.nicolazer.chatbot │ bundle: fr.nicolazer.chatbot.native│
│                              │                                  │
│ AppDelegate (UIKit)          │ @main ChatbotNativeApp (SwiftUI) │
│ + Capacitor Bridge           │ TabView Chat|Mail|Files|Settings │
│ + WKWebView                  │ APIClient + URLSession + SSE     │
│ + plugins App/Browser/       │ ASWebAuthenticationSession       │
│   Keyboard/StatusBar         │ Keychain (chs_…)                 │
│                              │ WKWebView (Mail HTML only)       │
│ Contenu UI = React remote    │ Contenu UI = SwiftUI native      │
└──────────────┬───────────────┴──────────────────┬───────────────┘
               │ HTTPS                            │ HTTPS
               │ cookies Access                   │ Bearer chs_ (+ Access bypass /api)
               ▼                                  ▼
        Cloudflare Access / Worker
               │
               ▼
        Next.js (PC Windows)
               │
     ┌─────────┼─────────┬──────────┐
     ▼         ▼         ▼          ▼
   Chat/SSE  Mail     Files     LM Studio / SQLite
```

### 2.2 Comment elles coexistent

- **Pas de partage de process** : deux IPA, deux installs possibles côte à côte.
- **Même backend** et contrats Client Surface ([`docs/CLIENT-API.md`](docs/CLIENT-API.md), [`contracts/`](contracts/)).
- **Auth différente** :
  - Capacitor : session **Cloudflare Access (cookies)** dans la WKWebView (comme Safari).
  - Native : **Access** uniquement pour mint session via `ASWebAuthenticationSession`, puis **Bearer `chs_`** en Keychain.
- Capacitor **n’embarque pas** le code SwiftUI de `apps/ios/`.
- SwiftUI **n’utilise pas** Capacitor, ni bridge JS, ni plugins Capacitor.

### 2.3 Technologies confirmées

| Techno | Présent ? | Où |
|--------|-----------|-----|
| Swift | Oui | `apps/ios/**/*.swift` (20 fichiers) + `ios/App/App/AppDelegate.swift` |
| SwiftUI | Oui | `apps/ios/ChatbotNative/**` (écrans + thème) |
| UIKit | Oui (ponctuel) | Capacitor `AppDelegate` ; native : `UIImage`, haptics, `ASPresentationAnchor`, `MailHtmlView` |
| Capacitor 7.x | Oui | `capacitor.config.ts`, `ios/`, deps npm `@capacitor/*` |
| WKWebView | Oui | Capacitor (UI complète) ; native (corps mail HTML seulement) |
| CocoaPods | Oui | `ios/App/Podfile` (Capacitor pods) |
| SPM / Package.swift | Non | Aucun `Package.swift` |
| Custom Capacitor plugin | Non | Aucun plugin custom dans le repo |
| Cordova plugins custom | Non | Uniquement `CapacitorCordova` transitif |

---

## 3. Code Swift — inventaire fichier par fichier

### 3.1 Capacitor (`ios/`)

| Chemin | Rôle | Framework | Notes |
|--------|------|-----------|-------|
| [`ios/App/App/AppDelegate.swift`](ios/App/App/AppDelegate.swift) | Cycle de vie UIKit + deep links Capacitor | UIKit + Capacitor | Template Capacitor ; délègue `open url` / Universal Links à `ApplicationDelegateProxy` |
| Storyboards Launch/Main | Splash + host WebView | UIKit | Standard Capacitor |
| [`ios/App/App/Info.plist`](ios/App/App/Info.plist) | Bundle Capacitor | — | Display name `Chatbot` ; orientations portrait+paysage |
| [`ios/App/App/capacitor.config.json`](ios/App/App/capacitor.config.json) | Config syncée | — | Généré par `cap sync` depuis `capacitor.config.ts` |
| [`ios/App/Podfile`](ios/App/Podfile) | Pods | CocoaPods | iOS 14.0 ; Capacitor, App, Browser, Keyboard, StatusBar |
| [`ios/App/App.xcodeproj/`](ios/App/App.xcodeproj/) | Projet Xcode | — | Bundle `fr.nicolazer.chatbot`, deployment **14.0**, marketing **1.0** |

**Pas d’écrans SwiftUI dans `ios/`.** Pas de client HTTP métier Swift côté Capacitor.

### 3.2 Native SwiftUI (`apps/ios/ChatbotNative/`)

| Chemin | Lignes ~ | Rôle | SwiftUI / UIKit | Métier / réseau / état |
|--------|----------|------|-----------------|------------------------|
| [`ChatbotNativeApp.swift`](apps/ios/ChatbotNative/ChatbotNativeApp.swift) | 15 | `@main`, injecte session + nav | SwiftUI | `@StateObject` session, `@State` `AppNavigation` |
| [`Auth/AppSessionStore.swift`](apps/ios/ChatbotNative/Auth/AppSessionStore.swift) | 89 | Login / logout / token | UIKit + AuthenticationServices | `ASWebAuthenticationSession` → `chatbot-native://auth` ; `ObservableObject` |
| [`Auth/KeychainStore.swift`](apps/ios/ChatbotNative/Auth/KeychainStore.swift) | 43 | Persistance token | Security | Keychain generic password, `AfterFirstUnlockThisDeviceOnly` |
| [`API/APIClient.swift`](apps/ios/ChatbotNative/API/APIClient.swift) | 569 | Client HTTP + SSE + DTOs | Foundation + UIKit (images) | URLSession ; headers `Authorization`, `X-Client: ios`, `X-App-Version: 0.6.0` |
| [`API/ImagePipeline.swift`](apps/ios/ChatbotNative/API/ImagePipeline.swift) | 77 | Compress / downsample / cache | UIKit + ImageIO + **actor** | `ImageThumbCache` mémoire+disque |
| [`API/PickedImageData.swift`](apps/ios/ChatbotNative/API/PickedImageData.swift) | 17 | Transferable Photos | UniformTypeIdentifiers | Import image pour upload |
| [`Navigation/AppNavigation.swift`](apps/ios/ChatbotNative/Navigation/AppNavigation.swift) | 49 | Tabs + deep links Mail/Files | Observation iOS 17 | `@Observable` ; handoffs chat → tabs |
| [`Theme/AppTheme.swift`](apps/ios/ChatbotNative/Theme/AppTheme.swift) | 121 | Soft Graphite + ambient + glass | SwiftUI | Couleurs alignées globals.css |
| [`Theme/ModernUI.swift`](apps/ios/ChatbotNative/Theme/ModernUI.swift) | 138 | Empty states, haptics, context meter | SwiftUI + UIKit | `ContentUnavailableView`, `symbolEffect` |
| [`Theme/AppDates.swift`](apps/ios/ChatbotNative/Theme/AppDates.swift) | 14 | Dates relatives FR | Foundation | — |
| [`Views/RootView.swift`](apps/ios/ChatbotNative/Views/RootView.swift) | 99 | Login + TabView | SwiftUI | Gate auth |
| [`Views/ConversationListView.swift`](apps/ios/ChatbotNative/Views/ConversationListView.swift) | 177 | Liste / CRUD conversations | SwiftUI | API conversations |
| [`Views/ChatScreen.swift`](apps/ios/ChatbotNative/Views/ChatScreen.swift) | 1141 | Chat complet | SwiftUI + PhotosUI | SSE, agent UI, PJ, options modèle |
| [`Views/MessageBubble.swift`](apps/ios/ChatbotNative/Views/MessageBubble.swift) | 364 | Bulles + PJ + sources | SwiftUI + UIKit | Markdown `AttributedString` |
| [`Views/ComposerCapsule.swift`](apps/ios/ChatbotNative/Views/ComposerCapsule.swift) | 85 | Composer glass | SwiftUI + PhotosUI | — |
| [`Views/AgentActivityView.swift`](apps/ios/ChatbotNative/Views/AgentActivityView.swift) | 153 | Timeline agent / web | SwiftUI | État local SSE |
| [`Views/ChatExtras.swift`](apps/ios/ChatbotNative/Views/ChatExtras.swift) | 147 | Mail HTML, memory notice, file confirm | SwiftUI + **WebKit** | `WKWebView` pour HTML mail |
| [`Views/MailInboxView.swift`](apps/ios/ChatbotNative/Views/MailInboxView.swift) | 376 | Inbox + thread + AI | SwiftUI | Catégories, search, summarize/reply |
| [`Views/FilesBrowserView.swift`](apps/ios/ChatbotNative/Views/FilesBrowserView.swift) | 483 | Roots / browse / search / preview | SwiftUI | Filtres grille/liste |
| [`Views/SettingsView.swift`](apps/ios/ChatbotNative/Views/SettingsView.swift) | 139 | Session / web / OAuth / roots | SwiftUI | Lecture runtime + logout |
| [`Info.plist`](apps/ios/ChatbotNative/Info.plist) | — | URL scheme, photos, portrait | — | Scheme `chatbot-native` |
| [`project.yml`](apps/ios/project.yml) | — | XcodeGen | — | iOS **17.0**, unsigned CI |

### 3.3 Capacités natives déjà présentes (SwiftUI)

Confirmé dans le code :

- Interface SwiftUI réelle (tabs, listes, chat, mail, files, settings)
- Navigation native (`NavigationStack`, `TabView`, `@Observable` handoffs)
- Client HTTP natif (`APIClient` / `URLSession`)
- Client SSE natif (`URLSession.shared.bytes` + parse `data: `)
- Conversations CRUD natif
- Auth native (ASWebAuthenticationSession + Keychain Bearer)
- Pièces jointes images (PhotosPicker + upload multipart + thumbs serveur `?w=`)
- Documents via `fileImporter` (chat)
- Fichiers : list/search/preview (sous-ensemble API)
- Mail : liste/thread/AI summarize & suggest-reply ; HTML via WKWebView
- Clavier : comportement SwiftUI standard (pas de plugin Keyboard natif custom)
- **Pas** de push / notifications locales métier
- **Pas** de bridge JavaScript ↔ Swift
- **Pas** de plugins Capacitor custom
- **Pas** de Capacitor dans l’app native

---

## 4. Architecture UI mobile — tableau fonction → techno

Légende : **C** = Capacitor (WebView React), **N** = Native SwiftUI, **S** = Serveur/backend.

| Fonction | Implémentation actuelle | Techno | Native ou Web | Fichier(s) clés |
|----------|-------------------------|--------|---------------|-----------------|
| Lancement Capacitor | Storyboard + splash plugin + redirect remote | Capacitor/UIKit | Shell natif → Web | `AppDelegate`, SplashScreen config, `www/index.html` fallback |
| Lancement Native | SwiftUI `WindowGroup` | SwiftUI | Native | `ChatbotNativeApp.swift` |
| Splash | Capacitor SplashScreen ; Native UILaunchScreen vide | Cap / iOS | Mixte | `capacitor.config.ts` ; `Info.plist` native |
| Login Access (Cap) | Cookies Access dans WKWebView | Web | Web | Accès edge CF |
| Login Access (Native) | ASWebAuthenticationSession → Bearer | AuthServices | Native | `AppSessionStore.swift`, `/api/auth/app-session/start` |
| Navigation Cap | React router / layout web | React | Web | `src/app/**`, sidebar web |
| Navigation Native | TabView 4 onglets | SwiftUI | Native | `RootView.swift` |
| Sidebar Cap | Composant web | React | Web | composants sidebar |
| Liste conversations | Cap: web ; N: `ConversationListView` | React / SwiftUI | Les deux | `ConversationListView.swift` |
| Création conversation | Cap: web ; N: API POST | React / Swift | Les deux | `APIClient.createConversation` |
| Chat UI | Cap: `ChatView` ; N: `ChatScreen` | React / SwiftUI | Les deux (parité inégale) | `ChatView.tsx`, `ChatScreen.swift` |
| Messages | Cap: MessageList riche ; N: `MessageBubble` | React / SwiftUI | Les deux | — |
| Markdown | Cap: react-markdown+KaTeX ; N: `AttributedString` `.full` | React / Swift | Cap plus riche | `MessageBubble.swift` |
| Code / tables / math | Cap: oui ; N: limité AttributedString | — | Cap | — |
| Streaming SSE | Cap: fetch stream ; N: `bytes.lines` | JS / Swift | Les deux | `APIClient.sendChat`, `ChatView` |
| Stop | Cap: AbortController ; N: `Task.cancel` (lecture) | — | Les deux (N partiel) | Voir §8 |
| Régénération / edit | Cap: oui ; N: oui | — | Les deux | `ChatSendOptions` |
| PJ images | Cap: web ; N: PhotosPicker + compress | — | Les deux | `ImagePipeline`, upload API |
| PJ documents | Cap: web ; N: fileImporter | — | Les deux | `ChatScreen` |
| Lightbox | Cap: oui ; N: `ImageLightboxView` zoom | — | Les deux | `ChatScreen` |
| Mail | Cap: UI web complète ; N: inbox/thread/AI | React / SwiftUI | Cap plus complet | `MailInboxView.swift` |
| Files | Cap: UI web complète ; N: browse/search/preview | React / SwiftUI | Cap plus complet | `FilesBrowserView.swift` |
| Web Search toggle | Cap: toolbar ; N: chip + settings | — | Les deux | — |
| Agent timeline | Cap: AgentStatusBar… ; N: `AgentActivityView` | — | Les deux (N simplifié) | — |
| Sources | Cap: SourceCitations ; N: chips expand | — | Les deux | — |
| Mémoire CRUD UI | Cap: UI web ; N: notice SSE seulement | — | Cap | Pas d’API memories dans `APIClient` |
| Settings | Cap: pages web ; N: subset | — | Cap plus riche | `SettingsView.swift` |
| Profil | Cap: via Access/user ; N: `userId` affiché | — | Minimal N | — |
| Erreurs / loading | Cap: toasts + SessionGuards ; N: textes + ProgressView | — | Les deux | — |
| Notifications push | — | — | **Absent** | — |
| Deep links Cap | Capacitor URL open | Cap | Shell | `AppDelegate` |
| Deep links Native | `chatbot-native://auth` | iOS | Native | Info.plist + ASWebAuth |
| OAuth Gmail | Cap: same-WebView `openGmailOAuthStart` ; N: lecture comptes seulement | — | Cap pour connect | `open-external.ts` |
| Clavier Cap | Plugin Keyboard resize body | Cap plugin | Native plugin | `NativeShell.tsx` |
| Clavier Native | SwiftUI | — | Native | — |
| Safe areas Cap | CSS `env(safe-area-*)` + contentInset never | Web+config | Mixte | `capacitor.config.ts` |
| Safe areas Native | SwiftUI system | — | Native | — |
| Dark mode | Forcé dark Soft Graphite | — | Les deux | `preferredColorScheme(.dark)` |
| Orientation Cap | Portrait + paysage | Info.plist | — | Capacitor Info.plist |
| Orientation Native | Portrait only | Info.plist | — | Native Info.plist |
| Gestes | Cap: web ; N: swipe rename/delete, pinch lightbox | — | Mixte | — |
| Sheets / modals | Cap: web ; N: options composer, lightbox | — | Les deux | — |

---

## 5. Flux de données — Chat

### 5.1 Capacitor (WebView)

```
iPhone Capacitor WKWebView
  → React ChatView (src/components/chat/ChatView.tsx)
  → fetch/SSE vers /api/chat (cookies Access)
  → Cloudflare → Next chat route
  → orchestrator / agent / LM Studio
  → events SSE (token, sources, handoffs, …)
  → state React messages
```

- Background : `NativeShell` écoute `appStateChange` → event `chatbot:app-background` → `ChatView` appelle `abortRef.current?.abort()` (**confirmé** dans le code).
- Offline : `SessionGuards` + events `chatbot:auth-required` / `chatbot:network-error`.

### 5.2 Native SwiftUI

```
ChatScreen.send()
  → APIClient.sendChat(conversationId, message, options)
  → URLRequest POST /api/chat
       Authorization: Bearer chs_…
       X-Client: ios
       X-App-Version: 0.6.0
  → URLSession.shared.bytes
  → pour chaque ligne "data: {json}" → handleSSE(type, obj)
  → streamingText / agentActivity / sources / handoffs / file_action_pending
  → fin → loadMessages() + context snapshot
```

Fichiers : [`ChatScreen.swift`](apps/ios/ChatbotNative/Views/ChatScreen.swift), [`APIClient.sendChat`](apps/ios/ChatbotNative/API/APIClient.swift).

**Stop :** `sendTask?.cancel()` + `Task.checkCancellation()` dans la boucle SSE.  
**Non confirmé dans le code native :** envoi d’un signal d’abort HTTP dédié au serveur (contrairement au AbortController web) ; l’annulation est côté client (arrêt de lecture). Comportement serveur exact non vérifié ici.

**Background / kill / réseau :** aucune logique `scenePhase` / `appState` native dédiée au chat n’a été trouvée dans `apps/ios`. Comportement = défaut URLSession / OS (**déduit**, non instrumenté).

---

## 6. Authentification

### 6.1 Capacitor

1. Première ouverture → WKWebView charge `server.url` (origin publique).
2. Edge Cloudflare Access : sans cookie → login Access (hôtes dans `allowNavigation`, y compris Google IdP).
3. Cookie Access maintenu dans la WebView.
4. Appels API = cookies session Access (pas de Bearer app Capacitor dans le code client web typique).
5. OAuth Gmail API : `window.location.assign("/api/oauth/gmail/start")` **dans la même WebView** (`openGmailOAuthStart`) — **confirmé**.
6. Externes hors allowNavigation : `@capacitor/browser`.

### 6.2 Native SwiftUI

1. Écran `LoginView` → `session.login()`.
2. `ASWebAuthenticationSession` ouvre  
   `https://…/api/auth/app-session/start?redirect_uri=chatbot-native://auth`
3. L’utilisateur passe Access dans la session auth.
4. Middleware / route start exige `x-user-id` Access, mint session SQLite `chs_…` ([`app-session.ts`](src/lib/auth/app-session.ts), TTL défaut **7 jours**).
5. Redirect `chatbot-native://auth?token=chs_…&userId=…&expiresAt=…`
6. Token stocké Keychain ; requêtes API = `Authorization: Bearer`.
7. Edge : Bearer app session **bypass** middleware Access pour atteindre Node ([`middleware.ts`](src/middleware.ts) + apps Access path `/api` Bypass — documenté ; config CF hors repo).
8. Logout : `DELETE /api/auth/app-session` + clear Keychain.
9. 401 → `APIClientError.unauthorized` → plusieurs écrans appellent `session.logout()`.

**Refresh token :** non présent — un seul Bearer jusqu’expiration/révocation.  
**Cookies dans l’app native UI :** non utilisés pour l’API après mint.

---

## 7. Backend / API utilisée par le mobile

### 7.1 Abstraction

```
Mobile Native → APIClient (Swift) → HTTPS endpoints Next
Mobile Capacitor → fetch React (api-fetch / hooks) → mêmes endpoints
```

Pas de SDK partagé TypeScript↔Swift. Contrats documentés dans `docs/CLIENT-API.md` + `contracts/`.

### 7.2 Endpoints appelés par le client **Swift** (`APIClient`)

| Méthode | Route | Usage native |
|---------|-------|--------------|
| GET/POST/PATCH/DELETE | `/api/conversations` (+ `[id]`) | Liste, create, rename, delete, mode, reasoning |
| GET | `/api/conversations/[id]/messages` | Historique |
| GET | `/api/conversations/[id]/context` | Compteur contexte |
| POST | `/api/chat` | SSE chat |
| POST/GET/DELETE | `/api/attachments/upload`, `/api/attachments/[id]` | PJ (+ `?w=` thumbs) |
| GET/PATCH | `/api/settings` | webSearchEnabled |
| GET | `/api/lm-studio/models` | Liste modèles |
| POST/GET | `/api/runtime/model`, reasoning-capabilities, status | Modèle / runtime |
| GET | `/api/mail/messages`, `/api/mail/threads/[id]` | Mail |
| POST | `/api/mail/messages/[id]/read` | Lu |
| POST | `/api/mail/ai/summarize`, `suggest-reply` | AI mail |
| GET | `/api/oauth/accounts` | Affichage comptes |
| GET | `/api/files/roots`, `list`, `search`, `content` | Files |
| POST | `/api/files/actions` | Confirm/cancel mutation |
| GET | `/api/auth/app-session/start` | Via ASWebAuth (navigateur) |
| DELETE | `/api/auth/app-session` | Logout |

### 7.3 Utilisé par Capacitor/Web et **pas** (ou peu) par Swift

Exemples confirmés absents de `APIClient` Swift :  
`/api/memories`, mail AI chat panel complet, email drafts/send confirm UX, files propose/upload/index UI, export conversation, nombreuses actions mail trash/confirm, etc.  
Le Web consomme l’ensemble Client Surface + routes legacy éventuelles.

### 7.4 Streaming

Seul `/api/chat` est consommé en SSE par le native. Autres AI mail = JSON POST.

---

## 8. Stockage local

| Quoi | Où | App | Sécurité / durée |
|------|-----|-----|------------------|
| Bearer `chs_` | Keychain (`fr.nicolazer.chatbot.native` / `app-session-token`) | Native | `AccessibleAfterFirstUnlockThisDeviceOnly` ; survit relaunch ; purge à logout / réinstall |
| userId (mémoire process) | `@Published` AppSessionStore | Native | Pas Keychain (reçu au callback ; perdu si non re-login — **confirmé** : seul token rechargé au launch) |
| Thumbs images | Caches/`att-thumbs/*.jpg` | Native | Cache disque ; non sensible auth |
| NSCache images | Mémoire process | Native | Éphémère |
| Cookies Access | WKWebView store | Capacitor | Session navigateur WebView |
| localStorage / etc. | WebView | Capacitor | Comme web app remote |
| Conversations / messages | **Serveur SQLite only** | Les deux | Pas de cache offline conversations native |
| SwiftData / Core Data / SQLite local | — | — | **Absent** |
| UserDefaults métier | — | — | **Non trouvé** |
| Capacitor Preferences | — | — | **Non trouvé** dans code app |

Après réinstallation native : Keychain peut parfois persister selon OS/réglages ; en pratique l’app repart sur login si token absent. **Non testé ici sur device.**

---

## 9. Capacitor — responsabilité exacte

**Réponse : B — uniquement un shell (remote WebView), avec plugins de confort.**

Preuves :

1. [`capacitor.config.ts`](capacitor.config.ts) : `server.url` = origin publique ; commentaire « contenu applicatif 100 % remote ».
2. [`www/index.html`](www/index.html) : fallback boot/offline qui redirige vers l’origin ; pas l’UI produit.
3. [`AppDelegate.swift`](ios/App/App/AppDelegate.swift) : template Capacitor sans UI métier.
4. UI produit = React embarqué **à distance** (même codebase web).
5. Plugins : App, Browser, Keyboard, StatusBar (+ SplashScreen déclaré en TS ; `packageClassList` sync liste App/Browser/Keyboard/StatusBar).
6. JS natif helpers : [`NativeShell.tsx`](src/components/native/NativeShell.tsx), [`is-native-app.ts`](src/lib/native/is-native-app.ts), [`open-external.ts`](src/lib/native/open-external.ts).

**Pas D « progressivement remplacé » dans le code Capacitor** : Capacitor n’est pas modifié pour déléguer à SwiftUI. La migration est une **deuxième app** parallèle (`apps/ios`), pas un remplacement in-place du shell.

Versions npm (package.json) : `@capacitor/core` ^7.6.9, `ios` ^7.6.9, app/browser/keyboard/splash-screen/status-bar 7.x.

Podfile platform : **iOS 14.0**.

---

## 10. Build / CI / distribution

### 10.1 Capacitor IPA

- Workflow : [`.github/workflows/ios.yml`](.github/workflows/ios.yml)
- Runner : `macos-14`
- Triggers : `workflow_dispatch` + push paths `ios/**`, `capacitor.config.ts`, `www/**`, package lock, workflow
- Étapes : npm install → `cap:verify` → `cap sync ios` → `pod install` → `xcodebuild` **unsigned** → zip IPA → artifact `chatbot-ios-unsigned`
- **Pas** de certificats Apple / provisioning dans CI
- Mac local : **non requis** pour builder (GHA) ; requis seulement pour Xcode local optionnel
- SideStore / iloader : documenté ([`docs/IOS-CAPACITOR.md`](docs/IOS-CAPACITOR.md))

### 10.2 Native SwiftUI IPA

- Workflow : [`.github/workflows/ios-native.yml`](.github/workflows/ios-native.yml)
- Runner : `macos-15` + Xcode 16.x
- Triggers : `workflow_dispatch` + push `apps/ios/**`
- Étapes : brew xcodegen → `xcodegen generate` → `xcodebuild` unsigned → artifact `chatbot-ios-native-unsigned`
- Signing : `CODE_SIGNING_ALLOWED=NO` ; `DEVELOPMENT_TEAM` vide
- Scan anti-secrets dans le bundle avant zip

### 10.3 Rebuild quand ?

| Changement | Rebuild Cap | Rebuild Native |
|------------|-------------|----------------|
| React / Next / API / CSS | Non (remote) | Non |
| `capacitor.config` / plugins / ios/ | Oui | Non |
| `apps/ios` Swift | Non | Oui |

Pas d’entitlements custom trouvés (pas de fichiers `.entitlements`).

---

## 11. Compatibilité iPhone (d’après le code)

| Sujet | Capacitor | Native |
|-------|-----------|--------|
| Safe area | CSS + `contentInset: never` | SwiftUI system |
| Dynamic Island | Via safe-area CSS web | System |
| Clavier | Plugin resize body | SwiftUI |
| Scroll chat | Web overflow | `scrollPosition` iOS 17 |
| Touch targets | Design system web (`touch-min`) | `AppTheme.touchMin` 44 |
| Orientation | Portrait+paysage | Portrait only |
| Status bar | Plugin DARK | Dark scheme |
| Background SSE | Abort explicite | **Pas de handler** trouvé |
| Photos | Web file input | PhotosPicker + usage string |
| Caméra directe | Non V1 (doc Cap) | Non |
| Push | Non | Non |
| Partage système | Non native dédié | Non |
| Offline | Bannière SessionGuards + www offline | Erreurs réseau API seulement |

Risques probables (déduits du code) : Cap dépend du PC/tunnel allumé ; native dépend Access bypass `/api` + Bearer ; Markdown/math native inférieur ; Stop native ≠ abort serveur garanti.

---

## 12. Fonctionnalités mobiles — classification

### Fonctionne réellement (code + chemins complets)

**Capacitor :** chat full web, mail, files, mémoire UI web, agents, web search, PJ, Access, Gmail OAuth same-WebView, settings web, abort SSE background.

**Native :** login Bearer, conversations CRUD, chat SSE (tokens, status, agent basique, sources, handoffs, file_action confirm, memory notice), PJ images/docs, mail liste/thread/AI summarize+suggest, files roots/list/search/preview, settings subset, runtime pill, context meter, Soft Graphite UI.

### Partiellement implémenté (Native surtout)

- Agent (pas toute la richesse web panels)
- Markdown / code / KaTeX
- Mail (pas trash/confirm/draft send panel/FAB assistant)
- Files (pas propose/upload/index/mutations UI complètes)
- Stop SSE (cancel Task only)
- Handoffs (navigue tab ; deep link thread/query best-effort)
- Sources attachées au streaming / last message meta (pas historique serveur sources)

### Présent dans le code mais non « produit » standalone

- `www/index.html` offline fallback (seulement si remote échoue)
- `MailHtmlView` WKWebView (sous-composant)

### Préparé / documenté mais hors app native

- XCTest parsers (mentionnés dans docs archi, **pas** de targets test dans `apps/ios`)
- Gate Phase C docs vs feature set 0.6 déjà au-delà du shell minimal

### Non présent (mobile)

- Push notifications
- Widget / Siri / App Intents
- Offline conversations
- Face ID
- Custom Cap plugins
- SPM packages
- XCUITest
- Mémoire CRUD native
- Multi-compte switcher riche

---

## 13. Tests existants liés au mobile

| Test | Type | Ce qu’il couvre | CI | Device |
|------|------|-----------------|----|--------|
| [`src/lib/auth/app-session.test.ts`](src/lib/auth/app-session.test.ts) | Vitest | mint/resolve/redirect allowlist `chatbot-native://auth` | Oui (tests node) | Non |
| [`scripts/verify-capacitor.mjs`](scripts/verify-capacitor.mjs) | Script | Cohérence config Cap / allowNavigation | Workflow ios.yml | Non |
| [`src/lib/native/open-external.test.ts`](src/lib/native/open-external.test.ts) | Vitest | URLs externes / résolution | Oui | Non |
| [`src/lib/native/is-native-app`](src/lib/native/is-native-app.ts) | — | Pas de test dédié trouvé | — | — |
| XCTest / XCUITest apps/ios | — | **Absent** du repo | Non | — |
| Checklist manuelle | Docs | [`docs/B0-DEVICE-CHECKLIST.md`](docs/B0-DEVICE-CHECKLIST.md), IOS-CAPACITOR | Manuel | iPhone réel |

**Non testé automatiquement :** UI SwiftUI, SSE native, Keychain, PhotosPicker, SideStore install, Access bypass bout-en-bout, parité Cap vs Native.

---

## 14. Qualité du code mobile

### Bonnes décisions (confirmées)

- Séparation nette Cap shell vs Native app (bundle IDs distincts)
- Remote UI Cap → rebuild rare
- Auth Bearer hashée serveur (`chs_` + SHA-256)
- CI unsigned sans secrets Apple
- Client API centralisé Swift
- Soft Graphite tokens partagés conceptuellement avec le web
- Thumbs serveur `?w=` pour perf tunnel
- Observation iOS 17 / scrollPosition / actor cache images

### Faiblesses / dette

- `ChatScreen.swift` très gros (~1141 lignes) — état + réseau + UI mélangés
- Parité native ≪ web sur Mail/Files/Markdown/mémoire
- Pas de couche ViewModel testable isolée
- Cancel SSE native incomplet vs web
- Pas de tests UI native
- Deux stacks à maintenir (coût produit)
- `userId` non persisté Keychain (seulement token)
- Capacitor `www/index.html` health check peut diverger du comportement Access (401 health)

---

## 15. UX/UI mobile actuelle

### Capacitor

- Identique au web Soft Graphite, adapté mobile CSS
- Avantage : feature-complete
- Limites WebView : clavier/scroll/focus parfois « web » ; dépend de `NativeShell` + CSS safe-area
- Impression : app web enveloppée (shell stable documenté)

### Native SwiftUI 0.6

- Vraie app iOS : TabView, listes, composer glass, ambient, haptics, ContentUnavailableView
- Hiérarchie Soft Graphite volontaire (assistant sans bulle fill, user bubble asymétrique)
- Encore en rattrapage feature → sensation « produit en construction » sur Mail/Files/Markdown
- Cohérence iOS 17 APIs moderne
- Accessibilité : labels partiels ; pas d’audit VoiceOver trouvé

---

## 16. Performance (d’après architecture)

| Zone | Observation code |
|------|------------------|
| Launch Cap | Splash + charge remote + Access + hydratation React — dominant réseau/PC |
| Launch Native | Léger (pas de WebView UI) puis login ou liste API |
| Premier token | Dominé LM Studio + tunnel (commun) |
| Streaming Cap | JS + React re-render |
| Streaming Native | Append string + SwiftUI ; scrollPosition |
| Longues conv | Pas de virtualisation custom native au-delà LazyVStack |
| PJ | Compress client + thumb serveur — bon pour tunnel |
| Batterie WebView | Cap garde WebView permanente |
| Cache | Thumbs disque native ; pas de cache messages |

Bottleneck principal probable : **backend/tunnel/modèle**, pas le shell iOS lui-même.

---

## 17. Sécurité

| Item | Niveau | Détail |
|------|--------|--------|
| Bearer en Keychain device-only | — | Bonne pratique |
| Token préfixe `chs_` hash serveur | — | Pas de stockage raw serveur |
| Cap cookies Access dans WebView | MOYEN | Surface WebView classique ; allowNavigation large (Google) nécessaire Access |
| Deep link token dans URL callback | ÉLEVÉ (théorique) | `chatbot-native://auth?token=` visible un instant (ASWebAuth pattern) |
| X-Client jamais auth | — | Confirmé AGENTS.md / code |
| IPA unsigned SideStore | MOYEN | Distribution sideload ; pas d’App Store review |
| Logs token | FAIBLE | CI refuse `chs_` dans binaire |
| ATS | — | `NSAllowsArbitraryLoads: false` native |
| JS injection Cap | MOYEN | Surface WebView + contenu mail/web |
| PathGuard / files | — | Serveur ; client native ne contourne pas |
| Absence Face ID sur token | FAIBLE | Token after first unlock |

CRITIQUE bloquant non identifié dans le code mobile seul ; la sécurité repose sur Access + PathGuard serveur.

---

## 18. Dépendances et versions

| Élément | Version / valeur |
|---------|------------------|
| Swift (project.yml) | 5.0 |
| iOS deployment Native | **17.0** |
| iOS deployment Capacitor | **14.0** |
| Xcode CI Native | 16.x sur macos-15 |
| Xcode CI Cap | macos-14 (Xcode image défaut runner) |
| Capacitor core/ios | ^7.6.9 |
| Plugins Cap | app 7.1.2, browser 7.0.5, keyboard 7.0.6, splash 7.0.5, status-bar 7.0.6 |
| SPM | Aucun |
| Native marketing | 0.6.0 (8) |
| Cap marketing | 1.0 |

Obsolescence : deployment Cap 14 vs Native 17 — **acceptable** (deux apps). Pas de dépendance Swift tierce à risque identifiée.

---

## 19. Ce que nous avons déjà réellement accompli côté mobile

1. **Shell Capacitor remote stable** buildable en CI, installable SideStore, UI = app web complète derrière Access.
2. **Plugins** Keyboard / StatusBar / Browser / App / Splash + helpers React `NativeShell` / `SessionGuards` / OAuth same-WebView.
3. **Seconde app SwiftUI native** complète au niveau structure (auth Bearer, 4 tabs, chat SSE, mail, files, settings).
4. **Auth app-session** serveur + tests Vitest + redirect scheme.
5. **Pipeline IPA unsigned** séparé pour Cap et Native.
6. **Thumbs PJ serveur** + cache images native.
7. **Design Soft Graphite** porté en SwiftUI (tokens, ambient, glass composer).
8. **Handoffs** chat → navigation tabs native.
9. **Documentation ops** IOS-CAPACITOR + apps/ios README.

---

## 20. Manques (gaps réels)

### P0 — bloque l’utilisation (selon contexte)

- Backend PC / tunnel / Access mal configurés → **les deux apps inutilisables**
- Native : Access app Bypass `/api` ou Allow `/start` absents → login/API cassés
- Native iOS &lt; 17 → IPA 0.6 non installable

### P1 — important

- Parité Native ≪ Capacitor (Mail/Files/Markdown/mémoire/agents)
- Stop/abort SSE native incomplet
- Pas de gestion background native pour streams
- Pas de tests UI/device automatisés native
- Deux apps à expliquer à l’utilisateur (quelle installer ?)

### P2 — amélioration importante

- Persistance userId / refresh session UX
- Sources/historique par message côté serveur
- Offline / retry robuste native
- Réduction taille `ChatScreen`
- Alignement orientation / polish Cap clavier edge cases

### P3 — polish

- Symbol animations, empty states partout
- PDF preview natif
- Haptics généralisés
- Accessibilité VoiceOver

### Future / optionnel

- Remplacement Capacitor par Swift only
- Push, widgets, App Intents
- App Store signing
- XCUITest

---

## 21. Architecture diagram (synthèse)

```
┌──────────────────────────┐     ┌──────────────────────────────┐
│ Capacitor                │     │ Chatbot Native (SwiftUI)     │
│ fr.nicolazer.chatbot     │     │ fr.nicolazer.chatbot.native  │
│                          │     │                              │
│ UIKit AppDelegate        │     │ SwiftUI App + TabView        │
│ Capacitor → WKWebView    │     │ URLSession APIClient         │
│ React UI (remote)        │     │ SSE chat natif               │
│ Cookies CF Access        │     │ Bearer chs_ (Keychain)       │
│ Plugins Kbd/Status/Brw   │     │ ASWebAuth + WKWebView mail   │
└────────────┬─────────────┘     └───────────────┬──────────────┘
             │                                   │
             └────────────────┬──────────────────┘
                              ▼
                 your-worker.example.workers.dev
                              │
                    Cloudflare Access + Worker
                              ▼
                         Next.js (PC)
                    Chat │ Mail │ Files │ Auth
                              ▼
              SQLite · LM Studio · Gmail · Disk roots
```

---

## 22. Conclusion

Aujourd’hui le « mobile » du projet est un **système dual** :

1. **Capacitor** = produit iPhone **feature-complete** via WebView remote (cœur UX actuel pour la parité web).
2. **SwiftUI native 0.6** = vrai client natif en construction avancée (auth, chat, mail, files), **sans** Capacitor, destiné à la parité progressive.

Ce n’est **pas** « encore une simple app Capacitor » exclusive, et ce n’est **pas** non plus « déjà une app SwiftUI qui remplace tout ». Les deux coexistent, buildés séparément, partageant le backend.

---

## FACTS VS ASSUMPTIONS

### Confirmé par le code

- Deux bundle IDs, deux arbres (`ios/` vs `apps/ios/`)
- Capacitor remote `server.url` + allowNavigation
- AppDelegate Capacitor sans UI métier
- 20 fichiers Swift métier sous `apps/ios/ChatbotNative`
- APIClient endpoints listés, SSE `bytes.lines`
- Keychain token, ASWebAuthenticationSession, scheme `chatbot-native`
- Workflows GHA unsigned séparés
- iOS 17 native / iOS 14 Cap
- Abort SSE background **uniquement** côté React/Capacitor
- WKWebView dans native limité à `MailHtmlView`
- Pas de Package.swift, pas de XCTest apps/ios, pas de push
- Tests Vitest app-session + verify-capacitor

### Déduit du code (non observé runtime device dans cet audit)

- Comportement exact URLSession si app background pendant SSE native
- Persistance Keychain après réinstall
- Qualité perçue UX sur chaque iPhone
- Config Cloudflare Access réelle (apps Bypass) — scripts/docs présents, compte CF non relu ici
- Latences réelles tunnel / LM Studio

### Non vérifié

- Installation SideStore réelle de l’IPA 0.6 sur un appareil de cet audit
- Contenu exact des artifacts CI du jour (hors inspection workflows)
- Entitlements Apple Developer (absents du repo — cohérent unsigned)
- Couverture VoiceOver / perf Instruments

---

*Fin du document `docs/MOBILE-CURRENT-STATE.md`.*
