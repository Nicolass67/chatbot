# Déploiement IPA — USB vs Wi-Fi lockdown

## Verdict (environnement Windows actuel)

| Question | Réponse |
|----------|---------|
| Wi-Fi possible avec **notre** stack ? | **Oui, conditionnel** — via usbmux `ConnectionType: Network` (Apple Mobile Device Service), pas un protocole « magique » séparé |
| Install IPA complète (sign + install) par Wi-Fi ? | **Oui si** le device apparaît Network dans `pymobiledevice3 usbmux list` — isideload utilise le même provider usbmux |
| Que reste-t-il USB ? | **Bootstrap** : Trust + pairing + `wifi-connections on` (une fois). Fallback fiable si Wi-Fi absent |
| Pairing réutilisable ? | **Oui** — record local `%ProgramData%\Apple\Lockdown\<UDID>.plist` (ne jamais committer) |
| USB intact ? | **Oui** — défaut `--auto` préfère USB ; `--usb` force USB |

**Mesure live (session d’analyse)** : `usbmux list = []`, `remote browse wifi = []`, pairing présent pour `00008110-…`. Donc **Wi-Fi lockdown n’était pas actif / device non visible** au moment du test — pas d’install Wi-Fi possible sans l’étape d’activation USB.

## Architecture

```
CI Flash → IPA unsigned locale
        → isideload (Apple ID vault) signe + InstallationProxy
        → transport usbmux : USB  ou  Network (Wi-Fi lockdown)
```

- **isideload** reste obligatoire pour notre IPA **unsigned** (signature free-dev).
- **pymobiledevice3** sert au probe / `wifi-connections` / QA ; `apps install` seul ne signe pas.
- **iLoader** reste le fallback GUI (2FA / CLI absente).

## Prérequis Wi-Fi

1. PC + iPhone **même LAN** (pas réseau invité / isolation client).
2. **Apple Mobile Device Support** (iTunes) + service AMDS (port local usbmux `27015`).
3. Pairing USB déjà fait (Trust) — record Lockdown présent.
4. Une fois en USB :
   ```bat
   npm.cmd run ios:wifi-enable
   ```
   (= `pymobiledevice3 lockdown wifi-connections on`)
5. Débranche, iPhone **déverrouillé**, Wi-Fi allumé.
6. Vérifie :
   ```bat
   npm.cmd run ios:wifi-probe
   ```
   Attendu : `verdict.wifiReady: true` (entrée Network dans usbmux).

## Commandes

```bat
npm.cmd run ios:wifi-probe
npm.cmd run ios:wifi-enable
npm.cmd run ios:install:auto
npm.cmd run ios:install:usb
npm.cmd run ios:install:wifi
npm.cmd run ios:deploy -- --skip-build --wifi
```

Flags deploy/install : `--auto` (défaut) | `--usb` | `--wifi` | `--transport …`

## Limitations pratiques

| Situation | Effet |
|-----------|--------|
| iPhone verrouillé / écran éteint | Souvent invisible ou install refusée |
| Changement d’IP / autre SSID | Disparaît de usbmux jusqu’à rediscovery |
| Isolation AP / guest Wi-Fi | Pas de lockdown Network |
| Firewall bloquant Bonjour/mDNS | Discovery cassée (usbmux Network repose surtout sur AMDS après enable) |
| Pairing expiré / Untrust | Rebrancher USB + Trust |
| Transfert IPA | Plus lent et moins stable qu’USB ; USB reste recommandé pour smoke critiques |

## Performance (conceptuel)

- **USB** : découverte instantanée, transfert stable, meilleur défaut QA.
- **Wi-Fi** : OK pour itérer sans câble **après** bootstrap ; moins fiable (veille, AP, IP).

## Sécurité

Ne jamais committer : Apple password, 2FA, pairing plist, certificats isideload, tokens. Creds = env ou Credential Manager `ChatbotAppleID`.

## Décision produit

- **CAS C (implémenté)** : couche transport Wi-Fi via usbmux Network + probe/enable, sans casser USB.
- Install Wi-Fi **validée en code path** ; **preuve device** = quand `wifiReady` est true (à rejouer après `ios:wifi-enable`).
