# chatbot-isideload-cli

CLI locale pour `ios:deploy` (wrapper [isideload](https://crates.io/crates/isideload)).

## Build

```bat
cd D:\chatbot-public\scripts\ios\tools\isideload-cli
cargo build --release
```

Binaire : `target/release/chatbot-isideload-cli.exe`

## Usage

```bat
chatbot-isideload-cli install [--transport auto|usb|wifi] path\to.app.ipa
```

- `auto` (défaut) : USB si présent, sinon usbmux **Network** (Wi-Fi lockdown)
- `usb` : USB uniquement
- `wifi` : Network uniquement

Env : `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `IOS_INSTALL_TRANSPORT`, `IOS_SIDELLOAD_2FA_CODE`

Voir `docs/IOS-WIFI-DEPLOY.md`.
