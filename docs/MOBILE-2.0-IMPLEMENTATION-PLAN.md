# MOBILE 3.0 — Native iOS 26 Rebuild Plan

> **Fichier unique** : ce document remplace le master plan Mobile 2.0.  
> **Statut :** **EXÉCUTION EN COURS** — feu vert utilisateur 2026-09-03. P0 Platform Reset + shell Chat-first / 3 tabs démarrés.  
> **Règle :** implémenter selon phases P0→… Device QA obligatoire.  
> **Date :** 2026-09-03  
> **Sources :** screenshots iPhone 2.0.0, `apps/ios/**`, CI, Apple docs / WWDC25 (Liquid Glass) **et WWDC26** (Foundation Models 241/242, Evaluations, LanguageModel, DynamicProfile, PCC, Vision tools), `docs/MOBILE-CURRENT-STATE.md`.

### Correction pass (2026-09-03b) — ce qui change vs draft précédent

1. **Xcode CI pinné** → `Xcode_26.6.app` (pas « latest 26.x » implicite).
2. **Audit WWDC26 / iOS 26 techno complet** ajouté (§11 bis) — pas seulement Liquid Glass WWDC25.
3. **Liquid Glass discipline renforcée** — anti-gimmick verre (§17).
4. **Tabs re-challengés** avec test fréquence d’usage (§14–15) — 3 tabs **confirmés**, pas dogmatiques.
5. **Identité assistant** définie (§18 bis) — native Apple-like ≠ clone Apple générique.
6. **Abstraction `LanguageModel` long terme** documentée (§43) — sans implémenter maintenant.
7. **Evaluations framework** intégré qualité agent (§57, phases).
8. **Gate SDK** : vérifier APIs dans le SDK piné avant P0 code.

---

## 1. Executive Summary

Mobile 2.0 a livré un client SwiftUI **fonctionnel** (`fr.nicolazer.chatbot.native`, marketing **2.0.0**, build 12) et a gelé Capacitor en fallback. Les captures iPhone prouvent que ce n’est **pas** un produit iOS 26 exceptionnel : c’est un prototype SwiftUI sombre, list-centric, saturé de pills/cartes, avec une IA chat dont la racine est une liste d’historique, un onglet « Plus » fourre-tout, un header chat surchargé, un Mail compressé, et un Files encore trop proche d’un listing technique.

**Mobile 3.0** change d’objectif :

| Avant (2.0) | Après (3.0) |
|-------------|-------------|
| Rendre le native « plus joli / plus complet » | **Reconstruire** l’expérience iPhone comme si elle devait naître en 2026 |
| iOS 18 + Xcode 16, Liquid Glass « plus tard » | **Baseline iOS 26.0 + SDK du Xcode 26.6 piné** |
| Préserver Soft Graphite / Graphite Depth / tabs 2.0 | Tout est **contestable** : nav, tabs, DS, composer, Chat root |
| Polir `ChatScreen` monolithe | **Redesign Chat-first** + architecture feature-oriented |
| Parité Web → SwiftUI | **Capacités Web + expression native iOS 26** |

**Cible en une phrase :**

> L’assistant personnel le plus crédible possible sur iPhone — conçu pour iOS 26, pas adapté depuis un dashboard web.

---

## 2. Why the Previous Direction Was Wrong

1. **Optimisation locale sur une mauvaise IA.** Chat = liste de conversations. L’action primaire d’un assistant est **parler**, pas parcourir un historique.
2. **Design System avant product truth.** Tokens Graphite Depth + capsules partout ont produit une identité « AI dark app générique », pas une app Apple-native.
3. **Liquid Glass traité comme polish futur.** Apple documente Liquid Glass comme **couche fonctionnelle** (controls/nav), pas comme gloss. En buildant avec Xcode 16 / iOS 18, le produit **ne peut pas** devenir iOS 26 même sur device moderne.
4. **« Plus » = décharge.** Memory + Settings + About dans un 4ᵉ tab sans métier clair.
5. **Options Chat = panneau settings.** Un sheet monolithe pour Mode / Web / Modèle viole la disclosure progressive.
6. **Header chat = telemetry UI.** READY + tokens + titre + sliders = cockpit technique, pas conversation.
7. **ChatScreen ~1214 lignes.** Preuve d’architecture présentationnelle non bornée.
8. **Compat iOS 17/18 sacrée sans raison produit.** Le produit est personnel (SideStore), la cible device est contrôlée ; la compat legacy a **bridé** la plateforme.
9. **Visual QA trop faible.** « Compile + IPA + un test » ≠ « crédible à côté des apps Apple ».
10. **Mobile 2.0 a réussi un jalon d’existence.** Il a échoué comme **direction esthétique et informationnelle finale**.

---

## 3. Current Product Audit

### Inventaire technique réel (2026-09-03)

| Élément | État réel |
|---------|-----------|
| Bundle | `fr.nicolazer.chatbot.native` |
| Marketing / build | `2.0.0` / `12` |
| `deploymentTarget` | **iOS 18.0** (`apps/ios/project.yml`) |
| `IPHONEOS_DEPLOYMENT_TARGET` | 18.0 |
| `xcodeVersion` (XcodeGen) | **16.0** |
| `SWIFT_VERSION` | **5.0** |
| CI | `macos-15`, sélection **Xcode 16.x**, XcodeGen, tests + IPA unsigned |
| Packages SPM | **aucun** |
| Observation | Mixte : `AppNavigation` `@Observable` ; `AppSessionStore` encore `ObservableObject` |
| Concurrency | `async/await`, `ChatStreamingService`, cancel HTTP ; pas encore un pipeline AsyncSequence unifié côté UI |
| Availability | Quasi absent (cible 18) ; commentaire Liquid Glass « quand SDK 26 dispo » |
| Orientation | Portrait only |
| Color scheme | `.preferredColorScheme(.dark)` forcé |
| Tabs | Chat \| Mail \| Files \| Plus |
| Chat root | `ConversationListView` → `ChatScreen` |
| Fichiers clés | `ChatScreen` 1214 L, `APIClient` 613 L, `FilesBrowser` 499 L, `MailInbox` 451 L |
| Capacitor | Workflow `ios.yml` en `workflow_dispatch` only (gel opérationnel) |

### Ce qui fonctionne déjà (à préserver comme capacité, pas comme UI)

- Auth Cloudflare Access → ASWebAuthenticationSession → bearer Keychain
- Face ID lock optionnel
- SSE chat + abort HTTP via session dédiée
- Markdown partiel, Agent strip, sources sheet, share
- Mail list/search/labels, trash propose+confirm, mailto reply
- Files roots/list/folder NavigationLink, preview image/text/PDF Quick Look (partiel)
- Memories CRUD basique
- Tests unitaires `ChatSSEParser`
- Pipeline IPA SideStore

### Ce qui est structurellement faux

- Racine Chat = historique
- Tab Plus
- Composer + rangée de pills + sheet Options
- Header telemetry
- Surface visuelle = rounded rect + pills
- Absence volontaire de SDK iOS 26
- Monolithe Chat
- Settings / Memory sans produit
- Light mode / Dynamic Type / Reduce Transparency non traités comme architecture

---

## 4. Screenshot-by-Screenshot UX Audit

Légende complexité : S = small, M = medium, L = large. Priorité : P0/P1/P2.

### 4.1 Liste Chat (racine actuelle)

| | |
|--|--|
| **Comportement** | Large title « Chat », bouton compose, rows titre + date + chevron |
| **Structure** | `List` plate, séparateurs fins, AmbientBackground |
| **Problèmes** | L’entrée produit n’est pas « parler » ; 2 taps minimum pour composer ; rows génériques ; aucune section Aujourd’hui/Hier ; pas de search visible ; pas d’état actif premium |
| **IA / Nav** | Historique = root = erreur produit |
| **Reco** | Chat root = **nouvelle conversation vide + composer focus** ; historique = surface secondaire |
| **Complexité / Priorité** | L / **P0** |

### 4.2 Chat actif + composer + pills

| | |
|--|--|
| **Comportement** | Header READY + tokens + titre tronqué + sliders ; message user bulle ; assistant texte + barre ; rangée Chat/Web/Model/Brain ; composer attach/options/send |
| **Problèmes** | Header cockpit ; pills permanentes ; concurrence visuelle composer vs tools ; titre tronqué ; stop rouge carré dissonant ; identité assistant faible |
| **Reco** | Header minimal ; tools en disclosure ; composer signature Liquid Glass ; tokens en debug/advanced |
| **Complexité / Priorité** | L / **P0** |

### 4.3 Empty / near-empty chat + menu pièce jointe

| | |
|--|--|
| **Comportement** | Message assistant long + menu Fichier/Photo ; pills modèle ; clavier AZERTY |
| **Problèmes** | Empty state = pas un empty state ; suggestions absentes ; menu OK mais chrome non iOS 26 |
| **Reco** | Empty intentionnel : identité calme + 3–5 suggestions + composer dominant |
| **Complexité / Priorité** | M / **P0** |

### 4.4 Sheet « Options chat »

| | |
|--|--|
| **Comportement** | Mode Chat/Agent, toggle Web, liste modèles interminable, OK |
| **Problèmes** | Panneau settings pour 1 changement ; modèles techniques bruts ; pas de progressive disclosure ; anti-pattern |
| **Reco** | **Supprimer** ce sheet monolithe ; pickers contextualisés (menu modèle, toggle Web, mode dans menu) |
| **Complexité / Priorité** | M / **P0** |

### 4.5 Mail list

| | |
|--|--|
| **Comportement** | Search, Boîte/Non lus, pills catégories, rows sender/subject/snippet |
| **Problèmes** | Densité excessive ; pills catégories ; hiérarchie visuelle faible ; snippets compressés ; look « admin panel » |
| **Reco** | Rows Mail-app grade : SENDER / SUBJECT / SNIPPET / TIME / unread / attach ; filtres en toolbar/menu ; swipe actions |
| **Complexité / Priorité** | L / **P1** |

### 4.6 Mail detail (loading + sparse card)

| | |
|--|--|
| **Comportement** | Spinner plein écran puis card GitHub + vide ; toolbar reply/trash |
| **Problèmes** | Empty spatial ; loading non skeleton ; détail non document ; actions basiques OK mais pauvre |
| **Reco** | Layout lecture mail (from/to/date/body) ; skeleton ; AI summarize contextual ; attachments |
| **Complexité / Priorité** | M / **P1** |

### 4.7 Files / Documents

| | |
|--|--|
| **Comportement** | List/grid toggle, pills filtres, folders system icons, back « Files » |
| **Problèmes** | Look Finder-lite générique ; pills filtres ; métadonnées pauvres ; pas de breadcrumb riche ; mutations (upload/rename/move) absentes côté UX |
| **Reco** | Browser natif : navigation dossiers fiable, preview one-tap, context menus, mutations P0/P1 |
| **Complexité / Priorité** | L / **P0 fonctionnel / P1 visuel** |

### 4.8 Plus hub

| | |
|--|--|
| **Comportement** | Sections Mémoire / Compte / À propos en cartes arrondies |
| **Problèmes** | Tab sans métier ; dead space ; Memory cachée ; Settings non Settings.app-like |
| **Reco** | **Supprimer le tab Plus** ; Settings via account/toolbar ; Memory produit dédié (sous Chat ou Settings) |
| **Complexité / Priorité** | M / **P0 IA** |

### Synthèse audit captures

Les screenshots ne sont pas une référence visuelle. Ce sont des **symptômes** : List/Form + pills + telemetry + mauvaise racine Chat + chrome non système iOS 26.

---

## 5. Product Vision

Un assistant personnel **local-first** (PC + LM Studio + Next API) dont le client iPhone est :

1. **Chat-first** — ouvrir l’app = pouvoir parler immédiatement.
2. **Contextuel** — Mail et Files sont des surfaces d’action assistée, pas des clones Gmail/Files.app exacts, mais **crédibles** comme apps natives.
3. **Digne de confiance** — Memory et session expliqués, destructifs confirmés.
4. **Plateforme iOS 26** — TabView/toolbar/sheets/glass système ; custom glass seulement où Apple le recommande.
5. **Rapide et calme** — motion utile, pas décoratif.

Non-objectifs 3.0 :

- Cloner le Web pixel-perfect
- Remplacer le backend LLM par Foundation Models
- Widgets / Live Activities / Siri comme blockers du DoD core
- Support iOS &lt; 26
- Framework DIY / DI container / coordinators géants

---

## 6. Core UX Principles

1. **Primary action first** — chaque surface expose l’action principale en &lt; 1 seconde.
2. **Content over chrome** — le verre sert le contenu, jamais l’inverse (Apple HIG Liquid Glass).
3. **Progressive disclosure** — cacher l’avancé jusqu’au besoin.
4. **Anti-pill** — capsule exception, pas langage.
5. **One job per screen region**.
6. **Native patterns first** — Tab, NavigationStack, sheet detents, Menu, contextMenu, swipeActions, searchable, ShareLink, Quick Look.
7. **Fewer taps to talk**.
8. **Trust for memory & auth**.
9. **Accessibility is design**.
10. **Device QA or it didn’t happen**.

---

## 7. Platform Strategy

| Décision | Choix |
|----------|-------|
| Client principal | SwiftUI Native `apps/ios` |
| Capacitor | Maintenance-only → freeze fort → retrait code après DoD 3.0 |
| Backend | Next API + contracts inchangés comme source de vérité fonctionnelle |
| Auth | Access + ASWebAuth + Keychain (conserver) |
| Device | iPhone (portrait) ; iPad layout-ready via NavigationSplitView **phase ultérieure** |
| Distribution | SideStore unsigned IPA continue ; App Store signing hors scope DoD |
| CI | **Migrer** `ios-native.yml` → `runs-on: macos-26` + **pin** `/Applications/Xcode_26.6.app` |

---

## 8. iOS 26 Target Decision

### Décision

**OUI — `IPHONEOS_DEPLOYMENT_TARGET = 26.0` devient le baseline natif.**

### Pourquoi

1. Liquid Glass, tab bar minimize, glassEffect, Foundation Models, et l’expression visuelle iOS 26 **exigent** SDK 26 et ont leur pleine valeur sur OS 26.
2. Le produit est un assistant **personnel** ; la flotte device est connue (iPhone de l’utilisateur).
3. Continuer iOS 18 force des `#available`, des fallbacks Material, et **reproduit** l’échec 2.0 (« design moderne cripplé »).
4. GitHub Actions expose **`macos-26`** avec **Xcode 26.6** (default image) et SDK iOS 26.5 — la CI n’est plus un bloqueur structurel.
5. Rebuild avec le **SDK piné** → composants système adoptent Liquid Glass automatiquement (Apple *Adopting Liquid Glass*).

### Raison valable de NE PAS le faire (à documenter si elle apparaît)

- L’iPhone de test n’est **pas** sur iOS 26 → alors bloquer l’implémentation UI glass jusqu’à upgrade device, **sans** redescendre le target « par confort code ». Alternative temporaire : target 26 mais tester sur sim iOS 26 uniquement.

### Availability strategy

- **Pas de dual-target 18/26.**
- Code écrit pour APIs iOS 26.
- Fallbacks accessibilité système (Reduce Transparency / Reduce Motion) via comportements Apple, pas via re-implémentation iOS 18.

---

## 9. Xcode / Swift / SDK Strategy

| Couche | Cible Mobile 3.0 |
|--------|------------------|
| Minimum deployment | **iOS 26.0** |
| SDK | Celui livré par le Xcode **piné** (Xcode 26.6 → iOS 26.5 SDK / `iphoneos26.5` sur runners actuels) |
| Xcode (CI) | **PIN : `/Applications/Xcode_26.6.app`** — **jamais** « latest » non piné |
| Runner CI | **`macos-26`** (ne plus utiliser `macos-15` + Xcode 16) |
| Swift | Language mode **Swift 6** ; toolchain Xcode 26.6 (compilateur Swift 6.3.x) |
| Concurrency | Structured concurrency, `async/await`, `AsyncSequence` SSE, `@MainActor`, `Sendable` |
| Observation | **`@Observable` partout** ; migrer `AppSessionStore` hors `ObservableObject` |
| XcodeGen | Conserver ; bump `deploymentTarget: "26.0"`, `xcodeVersion`, settings |
| SPM | Apple frameworks d’abord ; packages tiers seulement si ROI clair |

### Règle de pin CI (obligatoire)

```yaml
runs-on: macos-26
# Select Xcode — PIN explicite, mise à jour délibérée seulement
sudo xcode-select -s /Applications/Xcode_26.6.app
xcodebuild -version   # assert Xcode 26.6
```

- **Interdit :** boucler sur `Xcode_26.*.app` « le plus récent trouvé ».
- **Autorisé :** bump manuel `26.6` → `26.7` (ou image runner) dans un commit dédié + note changelog CI après validation device.
- **Raison :** une mise à jour silencieuse de Xcode ne doit pas casser l’IPA SideStore / les tests.

### Gate SDK avant P0 code

Avant d’écrire du Swift 3.0, une checklist CI/local doit confirmer la présence (compile smoke ou `xcrun` / docs SDK piné) de :

- `glassEffect` / Tab minimize APIs
- `FoundationModels` (`LanguageModel`, `SystemLanguageModel`, `LanguageModelSession`)
- `Evaluations` (si utilisé en test target)
- App Intents `IndexedEntity` path

Si une API citée dans §11 bis **n’existe pas** dans le SDK 26.6 piné (ex. API documentée seulement en preview iOS 27), elle est **DEFER** explicitement — pas d’assumption mémoire.

---

## 10. Current Technology Audit

| Domaine | Aujourd’hui | Verdict 3.0 |
|---------|-------------|-------------|
| SwiftUI Views monolithes | ChatScreen 1.2k L | Rebuild feature modules |
| Theme | AppTheme + ChromeGlass fake | Remplacer par DS iOS 26 (système d’abord) |
| Navigation | TabView 4 tabs + stacks | Revoir IA (voir §14–16) |
| Networking | URLSession + APIClient God-object | Découper clients par feature ; garder patterns auth |
| SSE | ChatStreamingService OK direction | Monter en AsyncSequence + state machine UI |
| Markdown | Custom Attributed-ish | Renderer message first-class |
| Quick Look | Présent PDF | Généraliser previews |
| Auth | Solide | Garder |
| Tests | Parser only | Étendre domain + streaming state |
| Cap | Gel soft | Freeze produit + exit criteria |

---

## 11. Modern Apple Technology Audit (WWDC25 baseline)

Sources WWDC25 / design système : *Adopting Liquid Glass*, WWDC25 « Build a SwiftUI app with the new design », TabView `tabBarMinimizeBehavior` / `tabViewBottomAccessory`, `glassEffect` / `GlassEffectContainer`, App Intents + Spotlight IndexedEntity.

### SwiftUI / Concurrency

NavigationStack, Tab API moderne (`Tab`), sheets/detents, scroll edge effects, Observation, structured concurrency, task cancellation — **ADOPT**.

### Liquid Glass (WWDC25 — toujours valide)

Système d’abord (tab/toolbar/sheet). Custom `glassEffect` pour composer / FABs seulement. **ADOPT avec discipline** (voir §17 — anti-gimmick).

### Tab bar iOS 26

`tabBarMinimizeBehavior(.onScrollDown)` Mail/Files — **ADOPT**. `tabViewBottomAccessory` — **EVALUATE**.

### Documents / Media

Quick Look, ShareLink, PhotosPicker, fileImporter, Transferable — **ADOPT**. Camera — **EVALUATE**.

### System

App Intents + Shortcuts — **ADOPT P15**. Spotlight — **ADOPT P15**. Widgets — **EVALUATE**. Live Activities — **DEFER**.

---

## 11 bis. WWDC26 / iOS 26+ Technology Audit (obligatoire avant P0)

> **Règle :** avant P0 code, traiter cet audit comme source — **pas seulement** Liquid Glass WWDC25.  
> Objectif : technologies Apple **disponibles en 2026**, pas « mettre du verre ».

Sources : WWDC26 **241** (*What’s new in Foundation Models*), **242** (*Build agentic app experiences*), docs `FoundationModels`, Evaluations, Private Cloud Compute, Vision tools, App Intents WWDC26.

### A. Foundation Models — stack 2026

| API / concept | Rôle | Décision Chatbot |
|---------------|------|------------------|
| `LanguageModel` (protocol) | Abstraction multi-backend | **ADOPT architecturalement** (frontière future) — **pas** brancher PCC/tiers au DoD core |
| `SystemLanguageModel` | On-device Apple Intelligence | **EVALUATE** assists (titre, résumé court, classify) |
| `PrivateCloudComputeLanguageModel` | Raisoning + contexte large | **EVALUATE / DEFER** — **ne remplace pas** LM Studio PC |
| `LanguageModelSession` | Session + transcript | **EVALUATE** sous-tâches on-device |
| `DynamicProfile` | Swap model/instructions/tools dans une session | **EVALUATE** agents locaux ; inspiration context engineering |
| Tool calling modes | allowed / disallowed / required | **EVALUATE** si FM local |
| Vision system tools | `OCRTool`, `BarcodeReaderTool` | **EVALUATE** (si présents dans SDK piné) |
| Spotlight local RAG tool | RAG on-device | **EVALUATE** avec index conversations/files |
| Foundation Models Instrument | Debug latency/cache | **ADOPT tooling** quand FM utilisé |
| **Evaluations framework** | Datasets, trajectoires outils, métriques agent | **ADOPT qualité** (voir §57) |
| Custom/partner LLM via `LanguageModel` | Autres providers | **DEFER** — équivalent produit = Next + LM Studio |
| Remplacer le chat principal par FM | — | **REJECT** |

### B. Abstraction modèle long terme (ne pas coder maintenant)

```
AssistantModelRuntime (concept)
      │
      ├── Primary: Local PC / LM Studio via Next `/api/chat` (SSE)  ← DoD core
      ├── Assist: SystemLanguageModel (on-device)                 ← EVALUATE
      ├── Assist: PrivateCloudComputeLanguageModel               ← EVALUATE later
      └── Future: other LanguageModel providers                  ← DEFER
```

- Chat utilisateur principal = backend local.
- Assists (titre, résumé mail offline, OCR, classify mémoire) = FM possible.
- Éviter de couler l’UI dans un seul transport pour ne pas bloquer un adaptateur `LanguageModel` plus tard.

### C. Plateforme au-delà du glass

- Observation, Swift 6, Tab minimize, system lists — **ADOPT**.
- Icon Composer / icône layered — **EVALUATE** identité (§18 bis).
- App Intents schemas / semantic Spotlight — **ADOPT P15**.

### D. Refus explicites

- « iOS 26 = glass partout »
- « Apple Intelligence = cerveau principal »
- DynamicProfile / PCC / Evaluations **dans l’UI** avant excellence Chat/Files/Mail
- APIs preview iOS 27 absentes du SDK **26.6** piné

### E. Gate « APIs réellement dans le SDK piné » (ouvre P0)

| Symbole | Attendu Xcode 26.6 | Action si absent |
|---------|--------------------|------------------|
| `glassEffect` | oui | bloquer P4/P5 |
| `tabBarMinimizeBehavior` | oui | bloquer P5 |
| `LanguageModel` / `SystemLanguageModel` | oui (iOS 26+) | DEFER assists |
| `DynamicProfile` | vérifier | EVALUATE ou DEFER |
| `PrivateCloudComputeLanguageModel` | vérifier | DEFER |
| `OCRTool` | vérifier | DEFER |
| `Evaluations` | vérifier | datasets maison si absent |

---

## 12. Adopt / Evaluate / Defer / Reject Matrix

| Technologie | Décision | Raison |
|-------------|----------|--------|
| iOS 26 deployment | **ADOPT** | Baseline produit |
| Xcode **26.6** pin CI | **ADOPT** | Builds reproductibles |
| SDK iOS 26 (via 26.6) | **ADOPT** | Glass + APIs |
| Swift 6 language mode | **ADOPT** | Concurrency |
| `@Observable` | **ADOPT** | State moderne |
| AsyncSequence SSE | **ADOPT** | Streaming |
| Liquid Glass system bars | **ADOPT** | Native |
| `glassEffect` composer only | **ADOPT** | Signature |
| Glass sur messages / rows / canvas | **REJECT** | Anti-gimmick |
| `GlassEffectContainer` | **EVALUATE** | Morph attach/send |
| `tabBarMinimizeBehavior` | **ADOPT** | Contenu d’abord |
| `tabViewBottomAccessory` | **EVALUATE** | Composer |
| NavigationSplitView iPad | **DEFER** | Après iPhone |
| Quick Look / ShareLink / PhotosPicker | **ADOPT** | |
| App Intents + Spotlight | **ADOPT P15** | |
| WidgetKit | **EVALUATE** | |
| Live Activities / Dynamic Island | **DEFER** | |
| `SystemLanguageModel` assists | **EVALUATE** | Complément |
| `LanguageModel` boundary (arch) | **ADOPT boundary** | Évolutivité |
| `DynamicProfile` | **EVALUATE** | |
| PCC LanguageModel | **EVALUATE/DEFER** | Pas chat principal |
| Vision OCRTool | **EVALUATE** si SDK | |
| **Evaluations framework** | **ADOPT qualité** | Trajectoires agent |
| FM Instrument | **ADOPT tooling** | |
| Remplacer backend LM Studio | **REJECT** | Cœur produit |
| Fake glass / glass everywhere | **REJECT** | |
| Tab Memory / tab Plus | **REJECT** | Fréquence |
| Options sheet / Chat list root | **REJECT** | |
| Protocol forests / DI framework | **REJECT** | |
| Capacitor feature forever | **REJECT** | |

---

## 13. Information Architecture

### Entités utilisateur

- **Conversation** (chat)
- **Message** (+ attachments, sources, agent events)
- **Mail thread / message**
- **File / Folder**
- **Memory**
- **Session / Settings**
- **Model / Tools config** (Web, Agent, reasoning)

### Hiérarchie proposée

```
App
├── Chat (primary)
│   ├── Active conversation (default = new empty)
│   ├── Conversation switcher (secondary)
│   ├── Composer + contextual tools
│   └── Message canvas
├── Mail
│   ├── Inbox / filters
│   └── Thread detail (+ Ask Assistant)
├── Files
│   ├── Browser
│   └── Preview (+ Ask Assistant)
└── Settings (non-tab)
    ├── Account / session / Face ID
    ├── Assistant defaults
    ├── Memory
    ├── Appearance / Privacy
    └── About
```

---

## 14. Navigation Options

### Test fréquence d’usage (re-challenge tabs)

Critère Apple : un tab = destination **principale et persistante** utilisée régulièrement.

| Destination | Fréquence attendue (cet assistant) | Mérite un tab ? |
|-------------|------------------------------------|-----------------|
| Chat | Quotidienne / primaire | **Oui** |
| Mail | Fréquente (pilier produit déjà) | **Oui** |
| Files | Fréquente (disques / docs / PJ) | **Oui** |
| Memory | Occasionnelle / confiance | **Non** → Settings + entrée Chat |
| Settings | Rare | **Non** → toolbar compte |
| Search global | Utile mais pas quotidien autonome | **Non** (searchable in-surfaces + Spotlight later) |

Conclusion du test : **3 tabs restent la meilleure réponse** pour *ce* produit — pas parce que Cursor l’a dit, mais parce que Chat/Mail/Files sont trois métiers quotidiens distincts. Memory/Settings échouent le test de fréquence.

**Risque à surveiller en Device QA :** si Files est rarement ouvert en usage réel, envisager Files sous Chat handoff + More — **seulement** avec données d’usage, pas par goût. Jusqu’à preuve contraire → Files reste tab.

### Option A — 4 tabs : Chat | Mail | Files | Settings

- Settings nommé correctement (mieux que « Plus »)
- 4 destinations diluent la tab bar iOS 26
- **Verdict :** interim acceptable, **pas** cible 3.0

### Option B — 3 tabs : Chat | Mail | Files + Settings via compte

- Aligné sur le test fréquence
- Settings découvrable via icône compte persistante
- **Verdict : RECOMMANDÉ (confirmé après re-challenge)**

### Option C — Chat hub + Search + More

- Sous-découvre Mail/Files
- **Rejeté** pour ce produit

### Option D — Sidebar always (iPad-first)

- **DEFER** après excellence iPhone

---

## 15. Final Navigation Recommendation

**Confirmé : Option B — 3 tabs Chat | Mail | Files.**

Non dogmatique : révisable après Device QA usage (§14).

- **Chat** → default **nouvelle conversation vide** + composer ready
- **Historique** → switcher secondaire (leading)
- **Settings** → icône compte (non-tab)
- **Memory** → Settings + lien Chat
- **Plus : DELETE**

---

## 16. Tab Bar Strategy

1. `TabView` / `Tab` **système** (glass automatique SDK 26.6).
2. **Interdit** : custom opaque / capsules sur la tab bar.
3. `tabBarMinimizeBehavior(.onScrollDown)` Mail & Files.
4. Chat : minimize soft/off pour ne pas lutter avec le composer.
5. `tabViewBottomAccessory` — **EVALUATE** seulement si gain réel.
6. Labels : Chat, Mail, Files.
7. SF Symbols système.

---

## 17. Liquid Glass Strategy

Apple : Liquid Glass = matériau **dynamique fonctionnel** (controls/nav), déjà sur composants SwiftUI standards quand on build avec le bon SDK. `glassEffect` = custom **quand ça apporte vraiment quelque chose**.

### Anti-gimmick (critique)

Ne **pas** remplacer « trop de pills » par « trop de verre ».

| Surface | Traitement |
|---------|------------|
| Tab bar | **Native Liquid Glass** |
| Navigation bar / toolbar | **Native** (pas AmbientBackground sous la bar) |
| Sheets / menus / popovers | **Native** |
| Composer | **Custom `glassEffect`** signature + interactive |
| FABs / scroll-to-bottom | Glass **compact** |
| Message bodies / markdown | **NO glass** |
| Mail / Files rows | **NO glass** |
| Full-screen canvas / empty chat | **NO glass** plein écran |
| Settings list | System List |
| Loading overlays | Material système si besoin |

**Règle :** si retirer le glass n’enlève pas une fonction de chrome → ce n’était pas du chrome.  
**Règle 2 :** un seul custom glass hero (composer) > dix surfaces glass décoratives.

---

## 18. Visual Language

Nom de travail : **Depth Native** (remplace Soft Graphite / Graphite Depth comme dogmes).

Principes :

- Dark **et** Light (light n’est plus « post-DoD optionnel » — architecture dès DS, même si dark shippe en premier).
- Accent **calme** (bleu système ou accent produit unique) — **pas** purple AI.
- Typographie **SF** (pas rounded display gadget partout).
- Profondeur via **matériaux système + hiérarchie type**, pas gradients décoratifs.
- Séparateurs rares ; grouping par spacing.
- Corner radii : suivre concentricité iOS 26 (contrôles), pas radiusXl partout.
- Motion : springs courte, matched geometry pour switcher/composer.

Soft Graphite web peut rester ADN **backend/web** ; iOS n’est plus tenu de le mimer.

---


## 18 bis. Assistant Identity (personnalité produit)

Cible :

> Une app qui **semble conçue par Apple**, mais qui **n’est clairement pas** une app Apple.

Risque à éviter : Mail + Files + Messages + Settings génériques avec un LLM dedans.

### Identité

| Dimension | Direction |
|-----------|-----------|
| Nom / présence | « Chatbot » / assistant personnel local — calme, compétent, proche |
| Ton | Français clair, direct, sans corporate AI fluff ; humour rare et sec |
| Visuel | Depth Native + **une** signature (composer glass + accent produit) — pas mascotte géante |
| Empty chat | Identité **discrète** (symbole + courte présence) ≠ hero marketing |
| Pensée / streaming | Feedback de présence : activité agent collapsible, « Recherche… », pas cockpit READY |
| Agent | Timeline outils sobre ; sentiment de collaboration, pas de terminal |
| Web | Indicateur éphémère + sources soignées |
| Mémoire | Confiance et transparence (« ce que je retiens ») |
| Cross-feature | « Ask Assistant » depuis Mail/Files = même personnalité, même composer language |
| Micro-interactions | Haptics send/stop ; morph send↔stop ; symbol effects **rares** ; matched geometry switcher |
| Icône app | EVALUATE Icon Composer layered — reconnaissable Home Screen |

### Règles

1. Native patterns Apple **oui** ; personnalité produit **obligatoire**.
2. Pas de logo chatbot plein écran.
3. La signature visuelle principale = **composer + rendu messages**, pas des badges.
4. L’assistant a une voix cohérente Mail ↔ Chat ↔ Files.

---
## 19. Design System

Livrables DS 3.0 (après IA/UX, avant polish massif) :

1. Semantic colors (light/dark)
2. Type ramp (Large Title → Caption2) + markdown styles
3. Spacing 4-pt
4. Control sizes (min 44)
5. Surface roles (canvas, chrome, elevated, danger)
6. Glass roles (system vs custom composer)
7. Motion tokens + Reduce Motion alts
8. Iconography SF Symbols only
9. Components : `ConversationSwitcher`, `Composer`, `AssistantMessage`, `UserMessage`, `MailRow`, `FileRow`, `EmptyChat`, `SoftError` → renommés sans « Soft » kitsch

**Interdit DS :** SoftCard wrapping everything ; CapsuleButton default ; fake blur views.

---

## 20. Anti-Pill Rules

Une capsule est autorisée seulement si elle communique :

- un **segmented control** système,
- un **tag** discret (ex. Unread count),
- un **compact control** flottant unique,
- un **status** temporaire (recording, offline) — pas permanent READY.

**Interdit :**

- transformer Mode/Web/Model/Reasoning en rangée de pills permanentes,
- capsules sur chaque metadata de liste,
- capsules décoratives dans Settings,
- « Agent » badge capsule si un indicateur inline suffit.

Hiérarchie = typo + spacing + position + material.

---

## 21. Chat UX

### Objectif

Ouvrir Chat = **conversation prête**, clavier prêt, friction minimale.

### Règles

1. Default landing = **New conversation** (draft local jusqu’au premier send si besoin API).
2. Reprendre une conversation = action secondaire explicite.
3. Streaming cancel = stop UI + HTTP abort (déjà directionnellement correct).
4. Handoffs Mail/Files depuis citations = conserver via `AppNavigation`.
5. Pas de dashboard de features dans le canvas.

---

## 22. Empty Chat

Composition cible (hero budget strict) :

1. Présence assistant discrète (symbole + nom) — **pas** hero marketing, **pas** absence totale d’identité (§18 bis)
2. Une ligne d’accueil calme (ton produit)
3. 3–5 **suggestions** (texte / rows — **non** pills chrome)
4. Composer dominant (signature)
5. Historique leading ; compte/Settings trailing

Pas de : stats, token gauges, model dump, multi-cards, mascotte.

---

## 23. Conversation Navigation

Surface : **Conversation Switcher** (sheet/detent large ou push).

Capabilities obligatoires :

- New
- Search
- Sections (Épinglés / Aujourd’hui / Hier / Semaine / Plus ancien)
- Rename / Delete / Pin
- Swipe actions + context menus
- Selection mode multi-delete
- Active checkmark
- Empty / loading / error
- Transition morph vers conversation

Visuel : **pas** title/date/divider brut — preview snippet, relative time, optional mode indicator discret.

---

## 24. Composer

**Composant signature.**

Hiérarchie :

1. **CONTENT** — TextField multiline dynamique
2. **PRIMARY ACTION** — Send / Stop morph (glass interactive)
3. **SECONDARY** — Attach (menu) ; overflow menu (Web, Mode, Model, Reasoning)

Comportements :

- Keyboard-aware, height 1…N lines cap
- Attachment previews inline
- Disabled/sending/error states clairs
- Haptics send/stop
- Accessibilité VoiceOver labels complets
- Liquid Glass chrome ; **pas** 7 pills

Remplace : `ComposerCapsule` + tool pills + Options sheet.

---

## 25. Message Renderer

Système `MessageKit`-like maison :

- User : bulle opaque
- Assistant : document canvas (pas bulle web) avec typo lecture
- Markdown : headings, lists, code+highlight, tables scrollables horizontalement, quotes, links
- Citations / sources : chips tappable → sheet
- Images / attachments : native previews
- Agent activity : collapsible timeline, pas strip permanent bruyant
- Streaming : plain/fast path puis promote structured
- Actions : Copy, Share, Regenerate, Edit (user) en context menu / barre au focus — **pas** icônes permanentes sous chaque message

---

## 26. Streaming

### Exigences

- Incremental render sans stutter
- Moins d’invalidations : buffer + throttle UI (ex. 30–60 fps max updates)
- Cancel → `URLSession.invalidateAndCancel` + Task cancel
- Race : generationId / token monotique
- Background : pause UI ; préciser politique partial persist
- Retry soft error banner
- Scroll : stick-to-bottom si user near bottom ; sinon FAB
- Architecture : `ChatSession` actor/orchestrator + `AsyncThrowingStream` d’événements typés (plus de `[String: Any]` au bord UI)

### Non-but

« async wrapper autour de callbacks UIKit-era ».

---

## 27. Agent UX

- Mode Agent = choix dans overflow, indicateur discret dans header ou sous composer pendant run
- Timeline outils collapsible
- Erreurs outil compréhensibles
- Pas de cockpit permanent

---

## 28. Web Search UX

- Toggle dans overflow / menu
- Pendant run : indicateur « Recherche… » dans agent/activity
- Sources finales via citations UI (voir §29)
- Pas de pill Web permanente

---

## 29. Sources / Citations UX

- Inline markers sobres
- Tap → sheet liste sources (title, domain, open Safari / in-app)
- Share source link
- Accessible labels

---

## 30. Attachments

- PhotosPicker + fileImporter
- Preview thumb avant send
- Types : image, pdf, text/doc
- Erreurs upload claires
- « Ask about this file » depuis Files → new chat prefill attachment

---

## 31. Mail UX

### List row hierarchy (obligatoire)

```
SENDER                     TIME
SUBJECT
SNIPPET (2 lines max)
[attach glyph] [label discreet]
```

+ unread leading mark  
+ generous spacing  
+ swipe : Trash / Read / Archive(si API)  
+ context menu  
+ search  
+ filters in toolbar menu (pas pill circus)

### Detail

Header from/subject/date ; body lisible ; attachments ; actions Reply / Ask Assistant / Trash.

### Gaps fonctionnels (parity)

- Native Gmail OAuth connect
- Send via drafts API (réduire mailto)
Priorité P1 après Chat/Files P0.

---

## 32. Files UX

Objectif : **vrai browser**, pas inventory dump.

- Roots clairs
- Sort / list-grid
- Search
- Context menus
- Upload / create folder / rename / move / delete (P0/P1)
- Share
- Ask Assistant

---

## 33. Files Navigation

```
Files root → Folder → Subfolder → …
Back + optional breadcrumb menu
Deep link path restore
```

Tap folder **doit** entrer (déjà partiellement codé — QA device à valider/fixer).  
État path = source of truth observable.

---

## 34. Files Preview

| Type | Comportement |
|------|--------------|
| PDF | Quick Look |
| Image | Zoomable preview |
| Video | AVPlayer / QL |
| Text | Reader + share |
| Office/unknown | File info + Share + Open In |
| Loading | Skeleton, pas spinner centré nu |
| Error | Retry |

Toolbar : Share, Ask Assistant, Reveal in folder.

---

## 35. Memory UX

Produit de **confiance**, pas page settings.

- Liste searchable
- Catégories si backend le permet
- Explanation « pourquoi c’est retenu »
- Edit / Delete / Forget with confirm
- Privacy copy
- Empty state éducatif
- Entrée depuis Settings + lien Chat

---

## 36. Settings / Account

`List` / `Form` système groupé :

- Compte & session (logout, Face ID)
- Assistant defaults (model, web, agent)
- Mémoire
- Apparence (theme follow system)
- Confidentialité
- À propos / version / diagnostics avancés (tokens debug ici)

Pas de cartes custom empilées type Plus.

---

## 37. Authentication

Conserver flux Access. Améliorer :

- Login premium calme (system materials)
- Error states
- Session expiry handling (P1)
- Face ID respect Reduce Motion
- Ne jamais utiliser `X-Client` comme auth

---

## 38. System Integration

Phases tardives après excellence in-app.

Priorité d’intégration :

1. App Intents core
2. Spotlight entities
3. Widget New Chat (evaluate)
4. Foundation Models assists
5. Live Activities only if proven

---

## 39. App Intents

Adopt :

- `NewChatIntent`
- `OpenConversationIntent`
- `SearchConversationsIntent`
- `SearchFilesIntent` (si perf OK)
- `SummarizeMailIntent` (si Foundation Models ou backend)

Schema domains quand pertinents (WWDC26 App Schemas) — phase P15.

---

## 40. Spotlight

Indexer :

- Conversations (title, snippet) via `IndexedEntity`
- Files metadata (name, path) avec prudence volume
- Memories (opt-in privacy)

Pas indexer corps mail complets sans review privacy.

---

## 41. Widgets

**EVALUATE** widget « Nouveau chat » + éventuellement dernière conversation.  
Ship seulement si New Chat from Home Screen apporte un gain quotidien mesurable.

---

## 42. Live Activities

**DEFER.** Candidate : agent run &gt; N minutes. Sinon bruit.

---

## 43. Foundation Models / On-device AI

**Complément**, jamais remplacement LM Studio / Next chat.

### Rôle immédiat (DoD)

Chat principal = SSE backend. FM = assists optionnels.

Use cases **EVALUATE** :

- Titre auto conversation on-device
- Résumé court mail offline
- Classification / tagging memories
- Suggestions empty state
- OCR image via Vision tools **si** dans SDK piné

Toujours vérifier `availability` + fallback no-op/serveur.

### Rôle architectural (ne pas coder au P0–P7)

Réserver une frontière `AssistantModelRuntime` / adapters pour :

```
LanguageModel-shaped boundary
      │
      ├── Local PC / LM Studio (via Next SSE)  ← primary
      ├── SystemLanguageModel                  ← assist
      ├── PrivateCloudComputeLanguageModel     ← assist later
      └── future providers                     ← defer
```

But : ne pas rendre impossible une évolution où certaines briques (pas le chat principal) parlent `LanguageModel` / `DynamicProfile`.  
**Interdit :** réécrire le chat streaming serveur en session FM pour le DoD Mobile 3.0.

### DynamicProfile / tool calling

Inspiration pour context engineering & agents **serveur** ; usage FM local = EVALUATE après Chat excellence. Mesurer avec **Evaluations** (§57).

---
## 44. Vision / OCR

**EVALUATE** si présent dans le SDK **26.6** piné (`OCRTool` / Vision system tools WWDC26) : extraire texte image avant send.  
Sinon DEFER — pas de pipeline Vision custom lourd au P0.  
BarcodeReaderTool : faible priorité produit.

---

## 45. Accessibility

Dès architecture :

- Dynamic Type sur chat/mail/files
- VoiceOver labels/hints/values
- Hit targets ≥ 44
- Reduce Motion
- Reduce Transparency (glass → opaque system behavior)
- Contrast
- Pas d’info couleur seule (unread)

Gate QA VoiceOver sur Chat + Composer + Switcher.

---

## 46. Performance

Budgets :

- Cold start ressenti &lt; 1s jusqu’à UI interactive (auth cache)
- Scroll 60 fps listes
- Streaming sans jank
- ChatScreen &lt; ~250 L par fichier ; VMs focalisées
- Images : pipeline existant à conserver/améliorer
- Instruments : Time Profiler + Swift Concurrency sur chat send

---

## 47. Animation / Motion

Utiliser pour : nav switcher, new chat, composer expand, keyboard, message insert, sheet present, tab selection, attach insert.

Respect Reduce Motion → fades.

Pas de : parallax kitsch, glow pulses permanents (login pulse 2.0 = à supprimer ou très rare).

---

## 48. Error / Loading / Empty States

Chaque feature définit :

- Skeleton / redacted
- Empty intentionnel
- Soft error + retry
- Offline copy

Interdit : `ProgressView` centré nu comme seul design.

---

## 49. Web vs Native Parity

| Concept | Règle |
|---------|-------|
| Functional parity | Capacités importantes Web présentes ou explicitement différées |
| Data/behavior parity | Contracts SSE / auth / IDs identiques |
| Native expression | UI iOS 26 — **jamais** copie layout Web |

Matrice à réécrire post-IA (remplace `MOBILE-PARITY-MATRIX` mindset « translate UI »).

---

## 50. Capacitor Strategy

| Phase | Capacitor |
|-------|-----------|
| Maintenant | Déjà `workflow_dispatch` only — **freeze features** confirmé |
| Pendant 3.0 | Aucune feature Cap nouvelle ; hotfixes sécurité only |
| Native Primary gate | Chat 3.0 + Files preview nav + Mail list usable + Auth |
| Freeze final | Quand DoD §67 vert sur device |
| Delete code Cap | Après freeze final + période overlap courte (optionnelle) |

Capacitor **ne contraint jamais** l’architecture Native.

---

## 51. Architecture

Feature-oriented :

```
App/
  ChatbotNativeApp.swift
Core/          # session, logging, utilities
DesignSystem/
Networking/    # URLClient, SSE, endpoints
Authentication/
Chat/
Conversations/
Mail/
Files/
Memory/
Settings/
Shared/        # handoffs, deep links
SystemIntegration/  # intents, spotlight, widgets
```

Séparer : domain models, networking, orchestration (`ChatSession`), presentation, reusable UI.

---

## 52. Feature Boundaries

- Chat ne connaît pas l’implémentation Mail ; handoff via navigation IDs
- APIClient God-object → clients `ChatAPI`, `MailAPI`, `FilesAPI`, `MemoryAPI`
- DesignSystem n’importe aucune feature
- SystemIntegration dépend de domain, pas de View monolithes

---

## 53. Data Flow

```
View → @Observable Store/VM → UseCase/Orchestrator → API/SSE → DTO → Domain → Store → View
```

SSE :

```
ChatStreamingService.events: AsyncThrowingStream<ChatEvent, Error>
→ ChatSession.reduce
→ messages projection
```

---

## 54. Concurrency Strategy

- UI : `@MainActor`
- Network : async URLSession
- Parsers : Sendable pure functions
- Orchestrators : actors ou MainActor stores fins
- Cancellation : Task ids + generation counters
- Swift 6 : corriger warnings comme erreurs progressivement

---

## 55. Networking / SSE Strategy

- Garder abort HTTP (critique backend `request.signal`)
- Typer events (enum) vs `[String: Any]`
- Heartbeats ignored
- Unknown event types ignored (forward compatible contracts)
- Auth 401 → session invalidate UX

---

## 56. Security

- Keychain tokens
- Pas de secrets dans IPA (CI grep conserve)
- ATS strict
- Confirm destructifs Mail/Files/Memory
- Memory privacy copy
- X-Client jamais autorisation
- Pas contourner Cloudflare Access

---

## 57. Testing

### Classique

- Unit : SSE parser, reducers ChatSession, date sections, markdown AST
- Snapshot (EVALUATE) message renderer
- XCUITest smoke : login shell, new chat, switcher, file preview (P18+)
- Contracts CI serveur inchangé

### AI / Agent Evaluation Framework (qualité — pas feature UI)

Apple **Evaluations** (WWDC26, intégré Foundation Models) : datasets, trajectoires d’outils, métriques, impact des changements de prompts/context.

**ADOPT comme discipline qualité P1/P2** (framework SDK pour assists FM ; pour le routing agent **serveur**, eval sets équivalents).

Scénarios minimum :

1. Demande X → bon outil
2. Mail ouvert + « résume » → bon handoff
3. PDF joint → bon traitement
4. Réseau coupé mid-stream → récupération propre
5. Cancel → **aucun état zombie** (UI + HTTP)
6. Agent vs Chat → frontières respectées
7. Web on/off → pas d’appel search fantôme

Si `Evaluations` absent du SDK 26.6 piné → datasets JSON + harness maison, **même intention**.

Outils liés : Foundation Models Instrument (si FM), Time Profiler (streaming UI).

---
## 58. Visual QA

Processus obligatoire :

DESIGN → IMPLEMENT → BUILD → DEVICE → SCREENSHOT → CRITIQUE → FIX → SCREENSHOT → VALIDATE

Checkpoints : launch, auth, empty chat, streaming, composer, attachments, switcher, mail list/detail, files root/folder/preview, memory, settings, sheets, menus, tab bar, keyboard, dark/light, Dynamic Type, Reduce Transparency.

---

## 59. Device QA

Device réel (SideStore IPA) est **gate**. Simulateur insuffisant pour glass/haptics/keyboard feel.

Checklist B0 device à remplacer par checklist Mobile 3.0 (à créer en phase P18 docs).

---

## 60. Implementation Phases

Ajustées au repo réel (pas copie aveugle) :

| Phase | Nom | Focus |
|-------|-----|-------|
| **P0** | Platform Reset | iOS 26.0 ; CI `macos-26` + **pin Xcode 26.6** ; gate APIs SDK (§11 bis E) ; Swift 6 ; inventaire delete/keep |
| **P1** | IA + Identity Lock | Nav 3 tabs confirmée ; chat-first ; **identité assistant** (§18 bis) ; fiche Evaluations initiale ; design decisions |
| **P2** | UX Rebuild Specs | Wireflows Chat/Mail/Files/Memory/Settings ; scénarios eval agent listés |
| **P3** | Visual Direction | Depth Native, anti-pill, light/dark |
| **P4** | iOS 26 Design System | Tokens + composants chrome système |
| **P5** | Navigation Shell | TabView 3 tabs, Settings non-tab, minimize behavior |
| **P6** | Chat Core | New conversation root, header minimal, session state |
| **P7** | Composer | Signature glass, overflow tools |
| **P8** | Message Renderer | Markdown first-class |
| **P9** | Streaming | AsyncSequence + cancel races |
| **P10** | Conversation Switcher | Search/sections/swipe |
| **P11** | Files Rebuild | Nav + preview + mutations |
| **P12** | Mail Rebuild | Rows + detail + actions |
| **P13** | Memory | Trust UX |
| **P14** | Settings / Account | System list |
| **P15** | System Integration | Intents + Spotlight (+ widget eval) |
| **P16** | Accessibility | Dynamic Type / VO / Reduce* |
| **P17** | Performance | Instruments gates |
| **P18** | Visual + Device QA | Screenshot loops |
| **P19** | Parity | Functional matrix update |
| **P20** | Capacitor Freeze/Exit | Freeze final + plan delete |

**Priorité d’exécution réelle :** P0 → P1 → P5/P6/P7 (visible win) → P9 → P11 (gap fonctionnel) → P8/P10 → P12 → reste.

---

## 61. Priority Matrix

| Item | Priority |
|------|----------|
| iOS 26 platform reset | P0 |
| Chat opens to new conversation | P0 |
| Composer rebuild | P0 |
| Kill Options sheet / pills row | P0 |
| Header declutter | P0 |
| Files tap folder/file preview reliable | P0 |
| Remove Plus tab | P0 |
| Streaming architecture | P0/P1 |
| Mail row hierarchy | P1 |
| Message renderer excellence | P1 |
| Conversation switcher | P1 |
| Files mutations | P1 |
| Memory trust UX | P1 |
| Mail OAuth/send | P1 |
| App Intents / Spotlight | P2 |
| Widgets / FM / OCR | P2 |
| Live Activities | P3 |
| Delete Capacitor code | P3 post-DoD |

---

## 62. Dependency Graph

```
P0 Platform
 └─ P1 IA Lock
     └─ P3 Visual + P4 DS
         └─ P5 Shell ─┬─ P6 Chat Core ─ P7 Composer ─ P9 Streaming ─ P8 Renderer
                      │                 └─ P10 Switcher
                      ├─ P11 Files
                      ├─ P12 Mail
                      └─ P14 Settings ─ P13 Memory
 → P16 A11y + P17 Perf + P18 QA
 → P15 System
 → P19 Parity → P20 Capacitor
```

---

## 63. Risk Register

1. Device utilisateur pas encore iOS 26 → bloque validation glass
2. Scope ambition → dérive timeline (mitigation : gates P0–P7 d’abord)
3. ChatSession rewrite casse SSE abort
4. Files mutations API incomplets côté backend
5. Mail send/OAuth complexité
6. Swift 6 concurrency migration cost
7. Overuse glass → illisible (suivre Apple)
8. Reintroduire pills par habitude
9. Monolithe Chat revient
10. Capacitor zombie distracte
11. Foundation Models unavailable regions/devices
12. SideStore signing quirks after SDK bump
13. Xcode « latest » non piné → regressions CI silencieuses
14. Identité assistant oubliée → app Apple-générique
15. Glass overuse (nouveau gimmick)

---

## 64. Technical Debt

| Debt | Action |
|------|--------|
| ChatScreen 1214 L | Delete/rebuild modular |
| APIClient 613 L | Split |
| ObservableObject session | Migrate `@Observable` |
| ChromeGlass fake | Replace with system/glassEffect |
| Options chat sheet | Delete |
| Tool pills | Delete |
| Plus tab | Delete |
| preferredColorScheme dark only | Revisit |
| `[String: Any]` SSE edge | Typed events |
| SWIFT_VERSION 5.0 pin | Raise |
| CI Xcode 16 | Raise to 26 |

---

## 65. Delete / Keep / Rebuild Matrix

| Asset | Décision |
|-------|----------|
| Auth Keychain + ASWebAuth | **KEEP** |
| ChatStreamingService abort model | **KEEP / EXTEND** |
| QuickLookSupport | **KEEP / EXTEND** |
| AppNavigation handoffs | **KEEP / REFACTOR** |
| ConversationListView as root | **DELETE role** → rebuild as Switcher |
| ChatScreen monolith | **REBUILD** |
| ComposerCapsule | **REBUILD** |
| Options sheet | **DELETE** |
| MoreHub / Plus tab | **DELETE** |
| AppTheme Graphite Depth dogme | **REPLACE** |
| ModernUI Soft* naming | **REBUILD** |
| MailInboxView | **REBUILD UX** (keep API calls) |
| FilesBrowserView | **REBUILD UX + complete mutations** |
| MemoryListView | **REBUILD product** |
| SettingsView | **REBUILD system list** |
| MarkdownMessageView | **REBUILD** |
| Capacitor app | **FREEZE → later DELETE** |
| Contracts / backend | **KEEP** |

---

## 66. Premium Quality Bar

Un écran n’est done que si :

1. Hiérarchie évidente
2. Action primaire évidente
3. UI inutile retirée
4. Feel native iOS 26
5. Glass approprié (ou absence justifiée)
6. Spacing / typo excellents
7. Motion cohérente
8. Keyboard OK
9. Dynamic Type OK
10. VoiceOver OK
11. Feel rapide
12. Crédible à côté d’apps Apple
13. Screenshot device validé
14. Pas de pills non justifiées

---

## 67. Definition of Done (Mobile 3.0)

**Minimum bar « Mobile 3.0 done » :**

1. Build iOS 26 / Xcode 26 CI green + IPA SideStore
2. Chat ouvre sur empty new conversation + composer focus
3. Switcher historique first-class
4. Composer signature sans pill circus / sans Options sheet
5. Streaming cancel fiable + rendu fluide
6. Files : folder drill-in + preview types clés + share
7. Mail : rows lisibles + detail + actions essentielles
8. Settings remplace Plus ; Memory trust basics
9. Tab bar système glass + 3 tabs
10. Visual QA device passée sur checkpoints §58
11. A11y gate Chat/Composer
12. Capacitor gelé formellement (doc + workflow)

Hors DoD : Widgets, Live Activities, FM complets, iPad split, App Store signing, delete physique Cap.

---

## 68. Top 20 Transformations

1. **Chat root : conversation list → empty new conversation**  
   WHY : parler est l’action primaire.

2. **Deployment iOS 18 / Xcode 16 → iOS 26 / Xcode 26**  
   WHY : sans ça, le produit ne peut pas être iOS 26.

3. **Tab Plus → Settings non-tab**  
   WHY : Plus n’est pas une destination métier.

4. **4 tabs → 3 tabs Chat | Mail | Files**  
   WHY : charge cognitive et focus.

5. **Header READY+tokens → header minimal conversation**  
   WHY : telemetry ≠ UX chat.

6. **Options chat sheet → contextual menus/pickers**  
   WHY : disclosure progressive.

7. **Tool pills row → overflow composer**  
   WHY : anti-pill + calme.

8. **ComposerCapsule stack → signature Liquid Glass composer**  
   WHY : composant le plus important.

9. **Fake ChromeGlass / Ambient under bars → system Liquid Glass chrome**  
   WHY : Apple : remove custom bar backgrounds.

10. **ChatScreen monolithe → feature modules + ChatSession**  
    WHY : maintenabilité + perf.

11. **SSE dict events → typed AsyncSequence pipeline**  
    WHY : courses et clarté.

12. **Conversation list rows plates → switcher sections/search/snippets**  
    WHY : historique first-class secondaire.

13. **Mail dense pills → Mail-grade rows**  
    WHY : parse immédiat sender/subject/snippet/time.

14. **Files inventory → real browser + preview contract**  
    WHY : tap folder/file doit marcher comme un produit fichiers.

15. **Memory buried in Plus → trust product surface**  
    WHY : mémoire = relation utilisateur, pas settings dump.

16. **Graphite Depth dogma → Depth Native / system-first visuals**  
    WHY : identité iOS, pas clone web.

17. **Dark-only forced → system appearance architecture**  
    WHY : citoyen iOS.

18. **Markdown “good enough” → reading-grade message system**  
    WHY : l’assistant se lit, pas seulement s’affiche.

19. **Capacitor soft freeze → hard freeze + exit criteria**  
    WHY : un seul produit iOS.

20. **Code-then-screenshot → Design Review Gate + Device Visual QA loop**  
    WHY : empêcher de re-livrer un prototype.

---

## 69. Success Metrics

- Time-to-first-keystroke Chat &lt; 1 s after unlock
- Taps to send first message from cold Chat tab ≤ 1 (focus) / ≤ 2
- Zero permanent tool pills on Chat
- Files folder→preview success rate ~100% on QA set
- Mail row comprehension test (user finds unread+subject in &lt; 1 s)
- Crash-free streaming cancel on device
- Visual QA checklist ≥ 95% green
- VoiceOver critical path completable
- Subjective : « does this feel like an Apple-quality app? » pass with external reviewer

---

## 70. Final Architecture Decision

- Feature-oriented SwiftUI app
- `@Observable` + Swift Concurrency
- Typed SSE stream
- System navigation/chrome first
- No DI framework
- Native primary ; Capacitor non-blocking

---

## 71. Final Product Decision

- Chat-first assistant
- Mail & Files as peer pillars
- Memory & Settings secondary
- Backend LLM remains source of intelligence
- On-device Apple intelligence complementary only
- iOS 26 baseline, no legacy drag

---

## 72. Final Recommendation

**Arrêter Mobile 2.0 comme direction.** Traiter 2.0.0 comme **baseline d’existence** et preuve des erreurs.

**Statut après passe 2026-09-03b :** plan prêt pour **validation humaine finale**.  
Ensuite seulement : **STOP PLAN → CODE**, en commençant par **P0** (pin Xcode 26.6 + gate SDK) → **P1** (identité + nav) → shell + Chat/Composer → Files → Mail → polish.

Ne pas « rendre l’app actuelle jolie ».  
Construire l’app qui aurait dû exister — **Apple-native, pas Apple-générique**.

---

## Critical Final Questions — Explicit Answers

1. **iOS 26 minimum ?** → **OUI.**
2. **Swift/Xcode/SDK ?** → **CI pin Xcode 26.6** (`/Applications/Xcode_26.6.app`), runner `macos-26`, deployment **iOS 26.0**, SDK du Xcode piné, Swift 6 language mode. Bumps Xcode = commits délibérés.
3. **Chat ouvre nouvelle conversation ?** → **OUI (default).**
4. **Où vit l’historique ?** → **Switcher secondaire (leading → searchable sheet).**
5. **Tab bar remains ?** → **OUI, système iOS 26 (pas custom fake).**
6. **Combien de tabs ?** → **3 (Chat, Mail, Files)** — confirmé par test fréquence (§14) ; révisable si Device QA prouve Files peu utilisé.
7. **Plus existe ?** → **NON.**
8. **Mail top-level ?** → **OUI.**
9. **Files top-level ?** → **OUI** (sous réserve usage réel).
10. **Primary nav architecture ?** → **3-tab + Settings non-tab + Chat-first root.**
11. **Composer ?** → **Glass signature, content+send primary, tools in overflow.**
12. **Liquid Glass où ?** → **Bars, sheets, menus, composer, small FABs.**
13. **Liquid Glass où PAS ?** → **Message bodies, mail/file rows, full-screen canvases.** Anti-gimmick : pas « trop de verre ».
14. **Remplace Options sheet ?** → **Menus/popovers/detents contextual per control.**
15. **Files nav ?** → **Hierarchical NavigationStack + breadcrumb menu.**
16. **Tap file ?** → **Native preview (QL/image/text/video/info+share).**
17. **Mail row hierarchy ?** → **Sender / Subject / Snippet / Time + unread/attach.**
18. **Memory becomes ?** → **Trust product under Settings (+ Chat entry), editable/searchable.**
19. **Delete ?** → **Plus, Options sheet, pills row, Chat-list-as-root role, fake ChromeGlass dogma.**
20. **Rebuild from zero ?** → **Chat shell, Composer, Message renderer, Switcher, Mail UX, Files UX, Settings, DS.**
21. **Adopt Apple tech ?** → **Liquid Glass system (discipline), Tab minimize, Observation, AsyncSequence, QL/ShareLink, App Intents, Spotlight ; FM assists + Evaluations qualité ; LanguageModel boundary arch-only.**
22. **Deliberately NOT adopt (now) ?** → **Live Activities/DI default ; FM/PCC as primary brain ; glass everywhere ; Cap features ; DynamicProfile in user-chat DoD ; unpinned Xcode latest.**
23. **When freeze Capacitor ?** → **Hard freeze now for features ; final freeze at DoD §67 ; delete after overlap.**
24. **Min bar done ?** → **§67.**
25. **Obviously non-native ?** → **Pills everywhere, Web layout clone, custom opaque tab bar, telemetry header, Plus dump, spinner-only, glass décoratif partout, app Apple-générique sans identité.**
26. **Genuinely premium ?** → **Chat-first + identité assistant ; chrome glass système sans gimmick ; composer signature ; Mail/Files crédibles ; motion device-validée.**
27. **10 biggest risks ?** → **§63 (1–10) + Xcode unpinned + identité oubliée.**
28. **10 biggest opportunities ?** →  
    (1) Chat-first reboot  
    (2) iOS 26 glass authenticity (pas gimmick)  
    (3) Composer iconique  
    (4) Kill Plus  
    (5) Files réel  
    (6) Mail lisible  
    (7) Typed streaming  
    (8) App Intents  
    (9) Assists FM + Evaluations agent  
    (10) Personnalité « conçu comme Apple, pas une app Apple »

---

## Design Review Gate (process)

Avant chaque feature majeure P5–P14 :

```
CURRENT → PROBLEMS → OPTIONS → RECOMMENDATION → WHY
→ REJECTED ALTERNATIVES → IMPLEMENTATION STRATEGY → VISUAL QA CRITERIA
```

Aucune feature Chat/Composer/Files/Mail sans cette fiche.

---

## References

- Apple — *Adopting Liquid Glass*
- WWDC25 — *Build a SwiftUI app with the new design*
- WWDC26 — *What’s new in the Foundation Models framework* (241)
- WWDC26 — *Build agentic app experiences with the Foundation Models framework* (242)
- Apple — Foundation Models (`LanguageModel`, `SystemLanguageModel`, `DynamicProfile`, PCC)
- Apple — Evaluations framework (agent quality)
- Apple — App Intents / `IndexedEntity` / Spotlight
- GitHub Actions — `macos-26` + **Xcode 26.6** pin
- Repo — `apps/ios/project.yml`, `ChatbotNative/**`, `ios-native.yml`
- Prior art — IPA 2.0.0 screenshots (diagnostic only)

---

**FIN DU MASTER PLAN MOBILE 3.0 (passe correction 2026-09-03b) — DOCUMENT UNIQUE. AUCUNE IMPLÉMENTATION. EN ATTENTE DU FEU VERT CODE.**
