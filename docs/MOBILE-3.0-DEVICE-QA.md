# Mobile 3.0 — Device Visual QA Checklist

Remplace la checklist B0 pour la validation SideStore / iPhone.

## Prérequis

- IPA native build **≥ 22** (`fr.nicolazer.chatbot.native`)
- iPhone sur **iOS 26** (cible déploiement)
- Backend PC joignable + Cloudflare Access / session Bearer OK

## Checkpoints (§58 plan)

Pour chaque écran : passer / fail + capture optionnelle.

| # | Checkpoint | Pass? |
|---|------------|-------|
| 1 | Cold launch &lt; ~3 s après unlock Face ID | |
| 2 | Chat ouvre **nouvelle conversation** vide + composer focusable | |
| 3 | Switcher : sections Aujourd’hui/Hier, search, rename/delete | |
| 4 | Composer glass lisible ; Options sheet reste ouverte | |
| 5 | Attach image + fichier OK | |
| 6 | Streaming fluide ; Stop annule ; pas de décalage post-stream | |
| 7 | Fermer clavier accessible (pas collé) | |
| 8 | Files : drill-in dossier, preview image/PDF/texte, Share | |
| 9 | Files : mkdir + import + rename (propose→confirm) | |
| 10 | Mail rows lisibles ; detail HTML ; actions hors tab bar | |
| 11 | Mail : Connecter Gmail ; swipe Lu ; trash | |
| 12 | Chat contextuel Mail/Files persiste à la réouverture | |
| 13 | Settings : modèle, web, Face ID, Gmail, version build | |
| 14 | Memory : search, edit, forget, privacy copy | |
| 15 | 3 tabs only (pas Plus) ; Settings via avatar | |
| 16 | VoiceOver : composer send/stop + switcher row | |
| 17 | Dynamic Type : Mail rows / composer restent lisibles | |
| 18 | Reduce Transparency : composer opaque OK | |
| 19 | Feel crédible vs apps Apple (anti-pill) | |
| 20 | Aucun crash sur cancel stream / background | |

## Procédure

1. Installer IPA SideStore
2. Parcourir la grille ci-dessus
3. Noter fails avec build number + iOS version
4. Corriger → nouveau build → re-run fails seulement

**DoD §67.10** : cette grille ≥ 95 % vert sur device réel.
