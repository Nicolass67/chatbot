# iOS Autonomous Deploy Pipeline (Flash → Wi‑Fi RSD)

Boucle **sans intervention** pour l’app native :

```
code → commit → push → Flash IPA → download → sign local →
RemotePairing → Trusted Tunnel → RSD → install → launch
```

USB reste un **fallback** (`ios:deploy:usb`). Pas de screenshots. Pas de Simulator / Contracts / Full CI.

## Commandes

| Script | Rôle |
|--------|------|
| `npm.cmd run ios:ipa:flash` | Déclenche Flash IPA, attend, télécharge l’artifact |
| `npm.cmd run ios:deploy:wifi` | Flash + sign + install Wi‑Fi RSD + launch |
| `npm.cmd run ios:deploy:usb` | Flash + isideload USB (historique) |
| `npm.cmd run ios:deploy:auto` | Wi‑Fi d’abord, USB si échec |
| `npm.cmd run ios:deploy` | Alias de `deploy:auto` |
| `npm.cmd run ios:deploy:venv` | Crée/vérifie `scripts/ios/.deploy-venv` (Python ≥3.13, pymobiledevice3==11.3.1) |
| `npm.cmd run ios:install:wifi` | Install seule (IPA locale déjà téléchargée) |

## Transport Wi‑Fi (validé)

1. RemotePairing (record `~/.pymobiledevice3/remote_<UDID>.plist`)
2. Trusted Tunnel **userspace** (Python **3.13+**, TLS‑PSK natif)
3. RSD
4. AFC + `installation_proxy` shims
5. Launch CoreDevice `AppService`

**Ne pas** utiliser Python 3.12 + `sslpsk_pmd3` (échec `NO_CIPHERS_AVAILABLE`).

**Ne pas** dépendre de usbmux Network lockdown pour l’install IPA (CAS E).

## Signature

- Credentials : Windows Credential Manager cible `ChatbotAppleID` (ou env `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD`).
- Jamais dans Git / logs / GHA / `.env` versionné.
- 2FA : one-shot `IOS_SIDELLOAD_2FA_CODE` si Apple le demande ; jamais persisté.
- CLI : `chatbot-isideload-cli sign --out <dir> <ipa>` (sans USB).

## Prérequis locaux

1. Pairing RemotePairing déjà fait une fois (USB) :  
   `pymobiledevice3 lockdown remotepairing --pair`
2. Python 3.13+ installé → `npm.cmd run ios:deploy:venv`
3. `gh` authentifié pour le repo public
4. isideload CLI build :  
   `cargo build --release` dans `scripts/ios/tools/isideload-cli`

## États progressifs

```
[1/8] Waiting for GitHub Flash IPA build
[2/8] IPA downloaded
[3/8] Signature ready
[4/8] Finding iPhone
[5/8] Trusted Tunnel / install transport
[6/8] Installing
[7/8] Launching
[8/8] Deployment successful
```

## Récupération d’erreurs

| Échec | Action |
|-------|--------|
| Flash IPA | Diagnostiquer le workflow ; ne pas re-télécharger une IPA invalide |
| Sign / 2FA | Session Apple / `IOS_SIDELLOAD_2FA_CODE` one-shot |
| Tunnel / RSD | Retries ; iPhone déverrouillé, même Wi‑Fi ; pas de rebuild |
| Install | Réutiliser la même IPA signée ; reconnecter tunnel |
| Launch | Install peut être OK sans launch ; `npm.cmd run ios:launch` |

## Futur (non implémenté ici)

- Wake-on-LAN PC
- Accès VPN domicile → PC → iPhone Wi‑Fi

Le design n’impose pas localhost-only pour le tunnel device (RemotePairing/Bonjour LAN).
