# Smart File Organizer (iPhone)

## Objectif

Réorganiser un dossier Files **sans suppression** : inventaire → proposition (IA ou heuristique) → validation utilisateur → exécution (mkdir + move) → historique d’annulation.

## Architecture

```
SmartOrganizerSheet
  └─ SmartFileOrganizerEngine (@Observable, MainActor)
        ├─ OrganizationInventoryService   (listFiles récursif, max 2500 / profondeur 8)
        ├─ ProtectedStructureDetector     (+ OrganizationProtectionStore)
        ├─ OrganizationAIPlanner          → POST api/files/organize/plan
        ├─ OrganizationHeuristicPlanner   (repli métadonnées)
        ├─ OrganizationPlanValidator      (chemins, collisions, protections)
        └─ OrganizationHistoryStore       (UserDefaults, 20 manifests)
```

Modèles canoniques : `OrganizationModels.swift`, `OrganizationPathUtils.swift`, `OrganizationPlanValidator.swift`, `ProtectedStructureDetector.swift`.

## Flux

1. **Inventaire** via `APIClient.listFiles` (pagination curseur).
2. **Protections** auto (node_modules, bundles, densités techniques) + manuelles (« Protéger ce dossier » / « Toujours protéger »).
3. **Plan IA** (`src/lib/files/organize-plan.ts`) ; si 503 / JSON invalide → **heuristique** (Factures, Contrats, Images, Voyages, A classer).
4. **Validation stricte** : pas de traversal, hors root, collision, doublon, contradiction, source protégée. Seul `operation == move`.
5. **Approbation** UI : bouton explicite « Valider et réorganiser ». Fichiers `needsReview` exclus de l’auto-exécution.
6. **Exécution** : `proposeCreateDirectory` + `confirm`, puis `proposeMoveFile` + `confirm`. Manifest rollback destination→source. Annulation entre moves → `partiallyCompleted`.

## Entrées UI

- Menu dossier Files → **Réorganiser**
- Context menu dossier → protéger
- Assistant Files → **Réorganiser ce dossier** (`onRequestOrganize` / `Notification.Name.smartOrganizerRequest`)

## Backend

- `POST /api/files/organize/plan` — auth `withAuth` + `apiAuthGuard`, feature Files.
- Corps : `{ rootId, rootRelativePath, items, protectedPaths, instruction? }`
- Réponse : `{ summary, proposedDirectories, moves[{source,destination,confidence,reason}], warnings }`
- Échec modèle → **503** (`AI_ERROR`) pour bascule iOS heuristique.

## Garanties

- Jamais de delete dans ce flux.
- Pas d’exécution sans validation utilisateur.
- Structures protégées intouchables.
- Confiance auto : `OrganizationConfidence.autoExecuteMinimum` (0.72).
