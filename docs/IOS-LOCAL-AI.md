# IA locale iPhone (Qwen3 + Gmail direct)

Runtime LLM **séparé** du pipeline PC / LM Studio. Aucune bascule automatique du modèle distant.

## Capacités

| Surface | PC online | PC offline + modèle installé |
|---------|-----------|------------------------------|
| Chat | Distant (SSE) | Local Qwen3 1.7B (Metal) |
| Mail | API PC OAuth | Gmail API directe (OAuth iOS + Keychain) |
| Files | FS Windows | Message « nécessite le PC » |
| Web V4 | Pipeline PC | Indisponible (pas de SearXNG local) |

## Modèle

- **Qwen3 1.7B Q4_K_M** (~1,28 Go) — Hugging Face `second-state/Qwen3-1.7B-GGUF` (le dépôt officiel `Qwen/Qwen3-1.7B-GGUF` ne publie plus que Q8_0)
- Stockage : Application Support `/Models/Qwen3-1.7B-Q4_K_M.gguf`
- Jamais dans Git ni dans l’IPA par défaut
- Installation : Réglages → **IA locale** → Installer

## Runtime

- llama.cpp XCFramework (Metal, arm64 device)
- Fetch : `npm.cmd run ios:fetch-llama`
- `n_ctx = 4096` — budgets prompts locaux réduits

## Modes d’exécution (Réglages)

- **Automatique** : PC si joignable ; local seulement si PC confirmé offline + modèle prêt
- **Toujours distant** : force SSE PC
- **Toujours local** : force Qwen on-device

Login : bouton **Continuer en mode local** si le modèle est installé (sans session `chs_`).

## Gmail direct

- Client ID iOS public dans `GOOGLE_OAUTH_IOS_CLIENT_ID` (Local.xcconfig / Flash vars) — **pas de secret**
- Redirect : `chatbot-native://oauth/gmail`
- PKCE + Keychain (`gmail-*`)
- Envoi mail : confirmation UI obligatoire (`confirmSend`)

## Build Flash

1. CI fetch XCFramework
2. IPA légère (sans GGUF)
3. Sur device : télécharger le modèle depuis l’app

## Tests manuels (après deploy)

1. Installer Qwen3 → Tester le modèle
2. Mode local → « Bonjour, présente-toi en une phrase »
3. PC éteint → Chat local
4. Connecter Gmail direct → recherche / résumé
5. Proposition de réponse → **Refuser** → aucun envoi
6. Files → « nécessite la connexion au PC »
7. PC rallumé → mode distant intact
