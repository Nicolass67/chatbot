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
- Stockage : sandbox app `Library/Application Support/Models/Qwen3-1.7B-Q4_K_M.gguf`
- Jamais dans Git ni dans l’IPA par défaut
- Installation : Réglages → **IA locale** → Installer
- **Sideload / réinstall IPA** (`ios:install:usb`, isideload) : iOS recrée le conteneur de données de l’app → le GGUF est **supprimé**. Ce n’est pas un App Group ni Documents partagé. Après chaque install IPA, il faut **ré-Installer** le modèle. L’état « Installé » est dérivé uniquement du fichier réel (exists + taille ±5 % + magic `GGUF`), jamais d’un flag UserDefaults.

## Runtime

- llama.cpp XCFramework (Metal **compilé** dans le framework arm64 device)
- Fetch : `npm.cmd run ios:fetch-llama`
- Load : tentative **Metal + `n_gpu_layers`** via `LlamaInferenceConfig` (ExecutionProfile), **fallback CPU** automatique si le load Metal échoue
- Diagnostics : log `[local-ai:load]` + écran Réglages IA locale (backend effectif, ctx, batch, threads)
- `n_ctx` / batch / threads : paramétrés par modèle (pas de gating features)

## Modes d’exécution (Réglages)

- **Automatique** : PC si joignable ; local seulement si PC confirmé offline + modèle prêt
- **Toujours distant** : force SSE PC
- **Toujours local** : force Qwen on-device

Login : bouton **Continuer en mode local** si le modèle est installé (sans session `chs_`).

## Gmail direct

- Client ID iOS public via `GOOGLE_OAUTH_IOS_CLIENT_ID` (`Local.xcconfig` gitignored / variable Flash) — **pas de secret**
- Redirect : `com.googleusercontent.apps.<id>:/oauthredirect` (scheme Google iOS)
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
