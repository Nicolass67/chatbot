# Vendor — llama.cpp XCFramework

Le runtime LLM local (Metal) utilise **llama.cpp** via `llama.xcframework`.

## Installer (obligatoire avant build Xcode / Flash)

```bash
npm.cmd run ios:fetch-llama
```

Source épinglée : `LLAMA_XCFRAMEWORK_SOURCE.json` (tag nightly `b10809`).

## Règles

- **Ne jamais committer** `llama.xcframework` ni `*.gguf` (~86 Mo + ~1,28 Go).
- Le GGUF Qwen3 1.7B Q4_K_M se télécharge **dans l’app** (Application Support / Models), pas dans Git.
- Flash CI fetch automatiquement le XCFramework avant `xcodegen`.

## Doc produit

Voir `docs/IOS-LOCAL-AI.md`.
