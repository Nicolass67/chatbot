# Mobile Visual QA — Checklist

**Version app cible :** 2.0.0+  
**Règle :** Functional ≠ Done. Cocher avant de merger une phase UI.

## Devices

- [ ] iPhone SE (petit)
- [ ] iPhone 15 / 16
- [ ] iPhone Pro Max
- [ ] Dynamic Island / notch safe areas OK

## États système

- [ ] Dynamic Type XXL — composer + bulles lisibles
- [ ] Reduce Motion — pas d’animations parasites
- [ ] Reduce Transparency — chrome opaque (pas de blur illisible)
- [ ] VoiceOver — labels Send / Stop / Attach / tabs / Souvenirs

## Écrans

### Login
- [ ] Branding clair, CTA ≥ 44pt, erreur SoftErrorBanner

### Chat list
- [ ] Skeleton / empty SoftEmptyState
- [ ] Swipe rename/delete

### Chat thread
- [ ] Composer glass, touch ≥ 44
- [ ] Options en sheet (pas chips surchargés)
- [ ] Streaming sans jank (texte brut pendant stream)
- [ ] Markdown code/tables après fin de stream
- [ ] Stop annule la génération
- [ ] Background interrompt le stream proprement
- [ ] Clavier ouvert — composer au-dessus

### Mail
- [ ] Empty / loading
- [ ] Swipe corbeille + confirm
- [ ] Thread HTML + AI + mailto

### Files
- [ ] PDF Quick Look
- [ ] Empty / error

### Souvenirs
- [ ] Liste / search / créer / oublier
- [ ] Langage humain (pas IDs SQL)

### Plus / Réglages
- [ ] Face ID toggle
- [ ] Expiry session visible

## Comparaison

Captures baseline recommandées : `apps/ios/VisualQA/` (manuelles ou future CI Diffable).
