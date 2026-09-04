# Contracts (Client Surface)

Version : voir `VERSION` (entier).

## Règles de compatibilité

1. **Ajout** de champ optionnel ou de `type` d’événement SSE → OK sans bump (clients ignorent l’inconnu).
2. **Suppression / renommage / changement de sens** → bump `VERSION` + mise à jour fixtures + note dans PR.
3. Corps d’erreur API public : toujours `{ "error": string, "code": ApiErrorCode }`.
4. Handoffs : références métier (`intent`, ids) ; `url` Web = optionnel / déprécié.
5. `X-Client` / `X-App-Version` = télémétrie uniquement — **jamais** autorisation.

## Contenu

| Chemin | Rôle |
|--------|------|
| `chat/` | Événements SSE + fixtures |
| `errors/` | Schema erreur API + codes |
| `handoffs/` | Schemas mail/files handoff |
| `auth/` | Spec session app (ADR — code reporté) |
| `design-tokens/` | Tokens conceptuels |
| `baseline/` | Snapshots pour CI anti-drift |

Génération / check : `node scripts/contracts-check.mjs`
