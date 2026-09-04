# Mobile 3.0 — Assistants Pass (travail)

Date : 2026-09-03 (maj 2026-09-04)  
Plan : assistants contextuels (Chat · Mail · Files)  
Build cible : 3.0.0 (**build 27** = P6–P13 lot local)

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

CI autorisée uniquement à un **jalon d’intégration** (un run large, plan intelligent).

### Plans Simulator

| Plan | Contenu |
|------|---------|
| `mail` | Readability + draft + Mail Assistant |
| `chat` | empty + keyboard + thinking + agent + handoffs |
| `files` | drill-in + nested + preview + Files Assistant |
| `assistants` | Mail/Files Assistant + history + draft + handoff + Files nav |
| `gate` | MVP + readability + assistants + draft + nested/preview + handoffs |
| `all` | gate + history isolation shots |

Orchestrateur : `IOS_SIM_TEST_PLAN=assistants npm.cmd run ios:sim`  
(opt-in : `IOS_SIM_DISPATCH=1`)

## Gel d’exécution

```
P0 + P1 + P1b  →  GATE Chat (DoD Simulator)  →  P2/P3/P4
Puis P5…P17
```

## Audit screenshots (référence Simulator)

| Shot | Écran | Statut |
|------|--------|--------|
| mail-inbox | Inbox + FAB sparkle | OK Simulator |
| mail-detail-html | HTML contraste forcé | OK |
| mail-detail-text | Plain lisible | OK |
| mail-summary | Caption unique « Résumé » | OK |
| files-root | Roots + FAB | OK |
| chat-empty | Composer Message | OK |
| chat-composer / keyboard | P2 | OK run 33832310215 |
| chat-thinking / agent | P3/P4 | **pas encore PNG** (échec assert antérieur) |
| mail-assistant / files-assistant / draft / preview / handoff | P6–P13 | **code local — DoD = prochain run gate/all** |

## Checklist device (P1 / P1b)

- [x] Nested folders Files + back (fixtures Projets + UITest)
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
| P2 Keyboard | code + PNG run 33832310215 |
| P3 Thinking | **PASS** run 33839932300 |
| P4 Agent + Stop | **PASS** run 33839932300 (`chat-agent.png`) |
| P5 Scope | done (DB + API + client) |
| P6 Mail Assistant | **PASS** |
| P7 Files Assistant | **PASS** (+ context Documents) |
| P8 Harden Mail | baseline P1b |
| P9 Draft edit/send | **PASS** |
| P10 Actions | **PASS** overflow / draft actions |
| P11 Files preview | **PASS** |
| P12 Histories | **PASS** |
| P13 Handoffs | **PASS** |
| P14–P16 | **PASS polish** — empty chat UITest, Settings Apparence, Mail a11y unread, HTML light-dark, Reduce Motion login |
| P17 Final QA | gate = `plan=smoke` ≤5 min ; `all` = opt-in long |

## Note Contracts CI

`contracts.yml` : tests **ciblés** (`src/lib/contracts`, `api-error`) — plus de `npm test` full.  
Désynchro `package-lock.json` : **lot séparé**, ne pas mélanger à Mobile.
