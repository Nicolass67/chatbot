# E2E Email V2 — Checklist manuelle

Checklist pour valider **Email V2** : module `/mail` séparé du chat, handoff sémantique, corbeille confirmée.

## Prérequis

1. **LM Studio** lancé avec un modèle chargé
2. **Variables d'environnement** (`.env.local`) :

```env
EMAIL_ENABLED=true
GOOGLE_OAUTH_CLIENT_ID=...
GOOGLE_OAUTH_CLIENT_SECRET=...
GOOGLE_OAUTH_REDIRECT_URI=http://localhost:3000/api/oauth/gmail/callback
PUBLIC_BASE_URL=http://localhost:3000
OAUTH_TOKEN_ENCRYPTION_KEY=<32 octets base64>
```

3. **Google Cloud Console** : scopes Gmail `readonly` + `compose` + **`modify`** (corbeille)
4. **Compte Gmail de test**
5. App démarrée : `npm run dev`

## 1. Connexion OAuth (re-consent V2)

- [ ] Ouvrir `/settings/email`
- [ ] Si compte V1 existant : banner « Permissions insuffisantes » sur `/mail`
- [ ] **Reconnecter Gmail** → autoriser scopes incluant modification
- [ ] Badge **Connecté** + permission **Corbeille** listée

## 2. Module `/mail` — inbox

- [ ] Ouvrir `/mail` (ou via sidebar **Mail**)
- [ ] Liste des messages inbox affichée
- [ ] Recherche `q=from:...` fonctionne
- [ ] Filtre **Non lus** (`/mail?label=UNREAD`)

## 3. Thread + panneau IA

- [ ] Ouvrir un fil `/mail/thread/[id]`
- [ ] **Résumer** → texte affiché (aucune action automatique)
- [ ] **Rédiger réponse** → brouillon créé en DB
- [ ] Modifier brouillon → **Valider** → **Préparer envoi**
- [ ] **SendConfirmation** → clic **Confirmer l'envoi** uniquement
- [ ] Vérifier message dans Gmail **Envoyés**

## 4. Corbeille (message sélectionné)

- [ ] Sélectionner un message dans le fil
- [ ] Clic **Corbeille (ce message)**
- [ ] Modal : « Mettre **ce message** à la corbeille »
- [ ] **Confirmer** → message retiré de l'UI
- [ ] Vérifier dans Gmail : message en **Corbeille**
- [ ] En cas d'échec provider → message **restauré** + erreur

## 5. Handoff chat → mail

- [ ] Nouvelle conversation `/chat/new`
- [ ] Demander : *« Montre mes mails non lus »*
- [ ] **Pas** de tool email exécuté dans le chat
- [ ] Carte **Ouvrir Mail** + lien vers `/mail?label=UNREAD` (ou équivalent)
- [ ] Le chat **n'affiche pas** EmailCard ni liste inline

## 6. Garde-fous sécurité V2

- [ ] Chat « envoie-le » / « vas-y » → **aucun envoi direct**
- [ ] Contenu email malveillant dans un thread → **aucune action auto**
- [ ] `email_send` absent des tools LLM (registry)
- [ ] Aucun keyword routing (`email-fallback` supprimé)

## 7. Isolation utilisateur

- [ ] User A ne peut pas confirmer l'action trash/send de user B
- [ ] Tokens OAuth jamais visibles dans API/SSE/UI

## 8. Déconnexion

- [ ] `/settings/email` → **Déconnecter Gmail**
- [ ] `/mail` affiche banner connexion
- [ ] Chat email → handoff ou message générique (pas d'exécution email)

## Script smoke API

```bash
node scripts/e2e-email-smoke.mjs
```

Vérifie : health, OAuth accounts, routes mail, isolation `x-user-id`.

## En cas d'échec

| Symptôme | Piste |
|----------|-------|
| Corbeille refusée | Re-consent `gmail.modify` |
| `MISSING_PERMISSION TRASH_EMAIL` | Scopes OAuth incomplets |
| Handoff absent | Classifier local — vérifier intent email |
| Liste chat inline | V2 : email tools retirés du chat |

## Critère V2 validé

Sections **1–6** cochées sur compte de test = **Email V2 prêt**.
