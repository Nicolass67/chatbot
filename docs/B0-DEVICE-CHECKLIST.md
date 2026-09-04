# B0 — Checklist validation iPhone (obligatoire)

Les items ci-dessous **ne sont pas validés** tant qu’ils n’ont pas été cochés sur un **iPhone réel** (IPA SideStore).  
Les smokes PC/Web sont complémentaires, pas substituts.

**Prérequis ops :** `npm.cmd run start:fast` (ou stack prod équivalente) + tunnel/Worker up.

**Validation device :** 2026-09-03 (utilisateur) — Access session persistante, perf OK, Gmail connecté in-app.

## Access (B0.2) — P0

- [x] Login Cloudflare Access **dans** l’app (pas Chrome système)
- [x] IdP Google Access reste in-app
- [x] Retour UI Chatbot après OTP
- [x] Relancer l’app : session encore valide (ou reconnect propre)
- [x] 3 logins successifs sans ouverture Chrome

## Chat SSE (B0.3) — P0

- [x] Envoyer un message → tokens stream
- [x] Stop generation → UI idle (pas bloqué)
- [x] Home / background mid-stream → génération stoppée, UI récupérable
- [x] Regenerate OK
- [x] Erreur réseau → message clair + retry possible

## Gmail OAuth (B0.4) — P0

- [x] Settings → connecter Gmail **sans** `redirect_uri_mismatch`
- [x] URI console = `…/api/oauth/gmail/callback` exacte
- [x] Compte visible après connect
- [x] Liste messages / ouvrir un thread

## Mail + Files smoke (B0.5) — P0

- [x] Mail : recherche ou inbox
- [x] Files : roots visibles, list, search, preview texte ou PDF

## Démarrage (B0.6) — P0 ops

- [x] Cold open avec stack **prod** : pas ~1 min de noir « Turbopack »
- [x] Splash / loader disparaît → UI utilisable

## Clavier / safe area (B0.7) — P1

- [x] Pas de bande noire bloquante home indicator
- [x] Champ chat visible avec clavier ouvert

## Clôture B0

B0 = **GO** seulement si tous les P0 ci-dessus sont cochés sur iPhone.  
Date / testeur : **2026-09-03 / nicolazer — GO**
