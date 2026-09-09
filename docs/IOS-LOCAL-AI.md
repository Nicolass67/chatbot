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
- **Qwen3.5 2B Q4_K_M** (~1,18 Go / 1 270 808 032 octets) — `lmstudio-community/Qwen3.5-2B-GGUF` / `Qwen3.5-2B-Q4_K_M.gguf`
  - Architecture GGUF `qwen35` (hybride attention + SSM), `embedding_length` 2048, 24 couches, contexte 262 144 (runtime iPhone : `n_ctx` 2048)
  - Fichier **texte seul** (`general.type=model`) — la vision native Qwen3.5 n’est pas dans ce GGUF
  - **Ne pas remplacer** par le Q4_K_M bartowski (`Qwen_Qwen3.5-2B-Q4_K_M.gguf`, ~1,40 Go, couches MTP)
- **mmproj vision optionnel** (même dépôt LM Studio) : `mmproj-Qwen3.5-2B-BF16.gguf` (671 372 416 octets, ~640 Mo)
  - `clip.projector_type=qwen3vl_merger`, `projection_dim=2048` (compatible embedding texte)
  - Installation séparée : Réglages → Qwen3.5 2B → **Installer vision**
  - Chargé **à la demande** (image jointe) ; le GGUF texte n’est jamais écrasé
- Stockage : sandbox app `Library/Application Support/Models/`
- Jamais dans Git ni dans l’IPA par défaut
- Installation : Réglages → **IA locale** → Installer
- **Sideload / réinstall IPA** (`ios:install:usb`, isideload) : iOS recrée le conteneur de données de l’app → le GGUF **et** le mmproj sont **supprimés**. Ce n’est pas un App Group ni Documents partagé. Après chaque install IPA, il faut **ré-Installer** le modèle. L’état « Installé » est dérivé uniquement du fichier réel (exists + taille ±5 % + magic `GGUF`), jamais d’un flag UserDefaults.

## Runtime

- llama.cpp XCFramework tag **b10809** (`apps/ios/Vendor/LLAMA_XCFRAMEWORK_SOURCE.json`)
- Headers + binaire : `mtmd.h` / `mtmd-helper.h` et symboles `mtmd_init_from_file`, `mtmd_tokenize`, `mtmd_helper_eval_chunks` **présents**
- Fetch : `npm.cmd run ios:fetch-llama`
- Load : tentative **Metal + `n_gpu_layers`** via `LlamaInferenceConfig` (ExecutionProfile), **fallback CPU** automatique si le load Metal échoue
- Vision : Flash Attention **désactivée** sur le graphe CLIP ; `image_max_tokens=192` sur A15 / 6 Go
- Diagnostics : log `[local-ai:load]` / `[local-ai:vision]` / `[local-ai:llama] version=` + écran Réglages IA locale
- `n_ctx` / batch / threads : paramétrés par modèle (pas de gating features)

## Gemma 4 E2B (expérimental, sélection manuelle)

Candidat de comparaison **à côté** de Qwen3.5 2B. Jamais d’auto-remplacement, jamais de téléchargement automatique, jamais de bascule automatique.

| Bundle | Fichier | Taille | SHA256 |
|--------|---------|--------|--------|
| Texte | `gemma-4-E2B_q4_0-it.gguf` | 3 349 516 256 (~3,35 Go) | `fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634` |
| Vision | `gemma-4-E2B-it-mmproj.gguf` | 986 833 664 (~987 Mo) | `021059cce659fe7f9170d5599761d7bbaf644b798dab9503aca30dc43e6beb14` |

Source **officielle Google QAT Q4_0** : `google/gemma-4-E2B-it-qat-q4_0-gguf`. Pas bartowski.

Couples **séparés** (ne jamais mélanger les mmproj) :

- Qwen3.5 2B → `Qwen3.5-2B-Q4_K_M.gguf` + `mmproj-Qwen3.5-2B-BF16.gguf` (**inchangés**)
- Gemma 4 E2B → `gemma-4-E2B_q4_0-it.gguf` + `gemma-4-E2B-it-mmproj.gguf`

Après installation, Qwen reste le modèle actif. L’utilisateur doit appuyer sur **Utiliser Gemma 4 E2B**. Un seul GGUF texte en mémoire. Le mmproj n’est chargé que pour un tour image, puis libéré.

Profil iPhone 14 Plus (prudent, pas 128K) : `n_ctx` 1536, batch 192/96, timeout 240 s, thinking **off** par défaut.

**llama.cpp b10809 conservé** : le tag embarque déjà `LLM_ARCH_GEMMA4` et le projecteur `PROJECTOR_TYPE_GEMMA4V`. Une mise à jour risquerait la vision Qwen3.5 qui fonctionne.

Gemma 4 E4B : hors catalogue utilisateur, non téléchargeable (trop lourd pour 6 Go).

Comparer (Réglages → **Comparer**) : suite debug sur le modèle **déjà chargé**, sans auto-switch. Les mesures décident si Gemma justifie son coût mémoire ; cette doc ne déclare pas que Gemma est meilleur.

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
