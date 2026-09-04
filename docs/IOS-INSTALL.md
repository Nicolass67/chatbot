# Guide utilisateur — obtenir et installer l’IPA (0 €)

## Prérequis

- Compte **GitHub** (repo privé OK)
- **Apple ID gratuit** (pas de Developer payant)
- iPhone iOS 15+
- PC Windows + câble USB
- Backend joignable : `https://your-worker.example.workers.dev` (ou ton origin local)

## A. Build IPA (GitHub Actions)

1. Pousse le projet sur GitHub (si ce n’est pas déjà fait).
2. Onglet **Actions** → workflow **iOS IPA (unsigned)** → **Run workflow**.
3. Attends la fin du job macOS.
4. Télécharge l’artifact **`chatbot-ios-unsigned`** → extrais `Chatbot-unsigned.ipa`.

Ce workflow :
- ne demande **aucun** secret Apple ;
- produit une IPA **non signée** pour SideStore ;
- se déclenche aussi sur push touchant `ios/`, `capacitor.config.ts`, `www/`, etc.  
  **Pas** sur une simple modif `src/` Next.js.

Vérification locale (Windows) avant push :

```powershell
npm.cmd run cap:verify
```

## B. SideStore (Windows → iPhone)

1. Installe [SideStore](https://sidestore.io/) (via iLoader / doc officielle).
2. Connecte l’iPhone en USB, suis l’installation initiale SideStore.
3. Dans SideStore : installe `Chatbot-unsigned.ipa` avec ton **Apple ID gratuit**.  
   Astuce Windows : `npm.cmd run ios:deploy-prep` télécharge l’artifact et ouvre iloader.
4. Sur le PC : lance la stack **production** (`npm.cmd run start:fast`), pas `next dev`.
5. Ouvre l’app **Chatbot** sur l’iPhone.
6. Login **Cloudflare Access** (IdP Google) **dans** l’app — si Chrome s’ouvre, `allowNavigation` est incomplet → rebuild IPA.
7. Teste chat SSE ; pour Mail : Settings → Gmail (même WebView ; redirect URI exacte dans Google Console).
8. Checklist complète : [`B0-DEVICE-CHECKLIST.md`](B0-DEVICE-CHECKLIST.md).

Refresh signature ~**7 jours** (SideStore) — **sans** recompiler l’IPA tant que tu ne changes pas le shell natif.

## C. Mises à jour

| Tu changes… | Action |
|-------------|--------|
| UI / API / orchestrateur / CSS (fichiers `src/`) | Restart Next sur le PC — **pas** de nouvelle IPA |
| `capacitor.config.ts`, plugins, `ios/`, `Info.plist` | Nouveau run Actions → nouvelle IPA → SideStore |

## D. Si l’app affiche « Backend injoignable »

- PC allumé, Next + Worker/tunnel OK
- Tester l’URL dans Safari iPhone d’abord
- Bouton **Réessayer** sur l’écran fallback
