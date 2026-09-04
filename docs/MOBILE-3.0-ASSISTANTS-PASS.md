# Mobile 3.0 — Assistants Pass (travail)

Date : 2026-09-03 (maj 2026-09-04)  
Plan : assistants contextuels (Chat · Mail · Files)  
Build cible : 3.0.0 (**build 25** = P2–P4 Chat)

## Boucle Fast Simulator (règle — CI = EXCEPTION)

**Par défaut : NE PAS lancer de CI.**

Boucle principale :

```
CODE → tests locaux (privacy, contracts ciblés) → inspection screenshots existants
→ gros lot → commit → push → continuer
```

`npm.cmd run ios:sim` **ne dispatch plus** sauf :

```
IOS_SIM_DISPATCH=1 IOS_SIM_TEST_PLAN=gate npm.cmd run ios:sim
```

CI autorisée uniquement si validation Simulator / workflow / lot final / IPA autrement impossible.

### Plans Simulator

| Plan | Contenu |
|------|---------|
| `mail` | MailReadability uniquement |
| `chat` | empty + keyboard + thinking + agent |
| `files` | drill-in + nested + back |
| `gate` | MVP chat/mail roots + mail readability + chat gate |
| `all` | gate + FilesNavigation |

Orchestrateur : `IOS_SIM_TEST_PLAN=mail npm.cmd run ios:sim`

Optimisations CI : `build-for-testing` / `test-without-building`, cache DerivedData app-only, xcresult **failure-only**, screenshots required par plan, suites découpées.

## Gel d’exécution

```
P0 + P1 + P1b  →  GATE Chat (DoD Simulator)  →  P2/P3/P4
Puis P5…P17
```

## Audit screenshots (référence Simulator + gel device)

| Shot | Écran | Statut |
|------|--------|--------|
| mail-inbox | Inbox + FAB sparkle | OK Simulator |
| mail-detail-html | HTML contraste forcé | OK (fix WebView blank) |
| mail-detail-text | Plain lisible | OK |
| mail-summary | Caption unique « Résumé » | fix double heading |
| files-root | Roots + FAB | OK |
| chat-empty | Composer Message | OK visuel ; a11y glass flaky → query Message |

## Checklist device (P1 / P1b)

- [x] Nested folders Files + back (fixtures Projets + UITest FilesNavigation)
- [x] Corps facture lisible
- [x] Résumé Markdown (sans double titre)
- [x] PJ listées (fixture Free)
- [x] Fallbacks HTML → plain
- [x] DoD Simulator P1b — run 33829223957

## Phases

| Phase | Statut |
|-------|--------|
| P0 Doc | done |
| P1 Files nav | done + nested UITest |
| P1b Mail readability | **PASS Simulator** |
| GATE | descriptions OK ; Chat Gate via MVP découpé |
| P2 Keyboard | code done ; DoD PNG via plan `chat` |
| P3 Thinking | fixtures SSE + UITest |
| P4 Agent + Stop | fixtures SSE + UITest |
| P5 Scope | done (DB + API + client) |
| P6–P7 Assistants | done (FAB + sheet) |
| P8 Harden | baseline P1b |
| P9 Send | done + UITest `MailDraftUITests` (Modifier/Envoyer stubs) |
| P10–P17 | partiel |

## Note Contracts CI

`contracts.yml` : tests **ciblés** (`src/lib/contracts`, `api-error`) — plus de `npm test` full.  
Désynchro `package-lock.json` : **lot séparé**, ne pas mélanger à Mobile.
