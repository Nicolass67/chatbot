# Mobile 3.0 — Assistants Pass (travail)

Date : 2026-09-03  
Plan : assistants contextuels (Chat · Mail · Files)  
Build cible : 3.0.0 (**build 25** = P2–P4 Chat)

## Gel d’exécution

```
P0 + P1 + P1b  →  GATE Chat (descriptions OK, screenshots optionnels)  →  P2/P3/P4
Puis P5…P17
```

GATE Chat : poursuivi **sans screenshots** sur descriptions plan (2026-09-03).

## Audit screenshots gelé (IMG_2745–2750)

| Shot | Écran | Problèmes |
|------|--------|-----------|
| 2750 / 2745 | Mail inbox | Pas de FAB Assistant ; filtres capsules |
| 2749 | Files Documents | Un niveau OK ; pas de FAB ; nesting code fragile |
| 2746 | Mail corps | Contraste illisible ; dock 4 actions |
| 2747 | Résumé | Markdown brut (`##`) ; carte glass |
| 2748 | Brouillon | Pas Modifier/Envoyer ; FAB envelope ambigu |

## Checklist device (P1 / P1b)

- [ ] Nested folders Files + back + breadcrumb
- [x] Corps facture lisible (P1b — Fast Simulator fixtures + MailBodyReader)
- [x] Résumé Markdown rendu (`MailSummaryBlock` → `MarkdownMessageView`)
- [x] PJ listées (fixture Free)
- [x] Fallbacks HTML → plain (modes distincts + a11y)

## Phases

| Phase | Statut |
|-------|--------|
| P0 Doc | done |
| P1 Files nav | done (NavigationPath + cursor + breadcrumb) |
| P1b Mail readability | **code ready — DoD = Fast Simulator screenshots** (html/text/summary) |
| GATE | **levé** (descriptions) |
| P2 Keyboard | done (build 25) |
| P3 Thinking | done (build 25) |
| P4 Agent + Stop | done (build 25) |
| P5 Scope | done (DB + API + client) |
| P6–P7 Assistants | done (FAB + sheet in-place) |
| P8 Harden | baseline = P1b ; edge cases futurs |
| P9 Send | done (validate → propose → confirm) |
| P10–P17 | partiel (menus, FAB, IPA) |
