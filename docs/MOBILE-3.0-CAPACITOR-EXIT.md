# Mobile 3.0 — Capacitor Freeze / Exit (P20)

## Statut

| Niveau | État |
|--------|------|
| Soft freeze features | **DONE** — `.github/workflows/ios.yml` = `workflow_dispatch` only |
| Native primary | **DONE** — `apps/ios` + `ios-native.yml` (Xcode 26.6 pin) |
| Hard freeze formel DoD §67.12 | **THIS DOC** |
| Delete physique Cap (`ios/`, deps) | **POST-DoD** — seulement après overlap SideStore stable |

## Règles freeze

1. **Aucune nouvelle feature** dans Capacitor / `ios/` Cap shell.
2. Hotfixes sécu uniquement sur Cap, documentés.
3. Produit iOS = **ChatbotNative** (`fr.nicolazer.chatbot.native`).
4. Docs Cap marquées FALLBACK ONLY (`docs/IOS-CAPACITOR.md`).

## Exit criteria (avant delete Cap)

- [ ] DoD Mobile 3.0 §67 points 1–12 satisfaits (dont QA device)
- [ ] ≥ 2 semaines usage SideStore sans regress Cap-only critique
- [ ] Owner confirme : native couvre Chat / Mail / Files / Settings / Memory
- [ ] Backup IPA + tag git `mobile-3.0-final`

## Plan delete (après exit)

À exécuter dans un commit dédié **après** feu vert humain :

1. Retirer workflow Cap ou le laisser `workflow_dispatch` archivé
2. Supprimer / archiver `ios/` Cap, `capacitor.config.ts`, plugins `@capacitor/*` si plus utilisés
3. Nettoyer scripts `cap:*` du `package.json`
4. Mettre à jour README → native only

**Ne pas supprimer** tant que SideStore native n’a pas prouvé le remplacement.
