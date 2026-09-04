# Mobile 2.0 — Vision Lock (Phase 0)

**Date :** 2026-09-03  
**Statut :** VERROUILLÉ pour exécution  
**Plan canonique :** Cursor `mobile_2.0_plan_02fcd761.plan.md` (+ miroir `docs/MOBILE-2.0-IMPLEMENTATION-PLAN.md`)

## Décisions figées

| Sujet | Choix |
|-------|--------|
| Client iOS principal | SwiftUI Native (`fr.nicolazer.chatbot.native`) |
| Capacitor | Fallback → freeze après DoD |
| Direction artistique | **Graphite Depth** (ADN Soft Graphite, expression reconstruite) |
| Navigation | **Chat \| Mail \| Files \| More** (Memory = Souvenirs dans More) |
| Liquid Glass | Chrome only ; iOS 26 progressif quand SDK dispo ; fallback Material |
| Min iOS | **18.0** |
| Ordre | Vision → DS → Shell → Chat UI → architecture → SSE → … |
| Premium graphique | P0 dès le début (pas polish final) |

## Impression cible (5 s)

Fond profond calme · chrome verre subtil · typo précise · login produit · message assistant éditorial.

## Anti-objectifs

Clone Web pixel · Liquid Glass partout · 5 tabs plats · ChatGPT clone · Soft Graphite sacré.

## Jobs-to-be-done

1. Continuer un chat avec streaming fiable  
2. Triager / répondre mail  
3. Trouver / prévisualiser / agir fichiers  
4. Comprendre / gérer souvenirs  
5. Contrôler modèle / session  

## Next

Phase 1 — Design System code (`AppTheme` / `ChromeGlass` / états).
