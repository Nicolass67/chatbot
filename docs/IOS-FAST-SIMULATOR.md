# Fast Simulator QA (LEVEL 1)

Boucle rapide **Simulator** via GitHub Actions (`macos-26` + Xcode 26.6).  
Le vrai iPhone reste le gate final : `npm.cmd run ios:deploy -- --direct-install`.

## Commande

```powershell
npm.cmd run ios:sim
```

Flux :

1. Push du SHA courant si besoin  
2. Dispatch `ios-native-simulator.yml`  
3. Boot Simulator + `xcodebuild test` (`ChatbotNativeUI`)  
4. PNG écrits sous `artifacts/simulator/` sur le runner  
5. Download → `artifacts/ios-simulator/<sha>/` + `artifacts/ios-simulator/latest/`

Screenshots obligatoires MVP : `chat-empty.png`, `mail-inbox.png`, `files-root.png`.

## Mode déterministe

Activé uniquement par `-UITesting` / `CHATBOT_UI_TESTING=1` :

- session locale factice (`uitest-local-session`) — **jamais** de vrai token  
- fixtures Mail / Files / Chat via `APIClient` (pas de mock server)  
- SSE chat stubbée pour les smoke send

Production inchangée.

## Physical (inchangé)

```powershell
npm.cmd run ios:deploy -- --direct-install
```
