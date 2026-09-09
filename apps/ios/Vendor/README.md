# Vendor — llama.cpp XCFramework

Le runtime LLM local (Metal) utilise **llama.cpp** via `llama.xcframework`.

## Installer (obligatoire avant build Xcode / Flash)

```bash
npm.cmd run ios:fetch-llama
```

Source épinglée : `LLAMA_XCFRAMEWORK_SOURCE.json` (tag nightly `b10809`).

## Règles

- **Ne jamais committer** `llama.xcframework` ni `*.gguf` (~86 Mo + ~1,28 Go).
- Headers : `llama.h`, **`mtmd.h`**, **`mtmd-helper.h`** (vision / mmproj) — tag `b10809`
- Le GGUF Qwen3.5 2B Q4_K_M, son mmproj, et le bundle expérimental Gemma 4 E2B se téléchargent **dans l’app** (Application Support / Models), pas dans Git.
- **Ne pas bumper** `b10809` : Qwen3.5 vision (mtmd) fonctionne ; Gemma 4 (`LLM_ARCH_GEMMA4` + `PROJECTOR_TYPE_GEMMA4V`) est déjà dans ce tag.
- Flash CI fetch automatiquement le XCFramework avant `xcodegen`.

## Doc produit

Voir `docs/IOS-LOCAL-AI.md`.
