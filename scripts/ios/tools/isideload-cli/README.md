# chatbot-isideload-cli

CLI locale pour `ios:deploy` (wrapper [isideload](https://crates.io/crates/isideload)).

## Build

```powershell
cd D:\Chatbot\scripts\ios\tools\isideload-cli
cargo build --release
```

Binaire : `target/release/chatbot-isideload-cli.exe`

## Credentials (hors git)

```powershell
$env:APPLE_ID = "you@example.com"
$env:APPLE_APP_SPECIFIC_PASSWORD = "xxxx-xxxx-xxxx-xxxx"
```

Ou Windows Credential Manager target `ChatbotAppleID`.

## Exit codes

| Code | Sens |
|------|------|
| 0 | Install OK |
| 2 | HUMAN_REQUIRED (2FA) → fallback iLoader |
| 1 | FAIL |
