# E2E Email V1 — Checklist manuelle

Checklist pour valider le flux **Personal AI Assistant + Gmail** de bout en bout sur un compte de test.

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

3. **Google Cloud Console** : redirect URI autorisé, scopes Gmail (read + compose + send)
4. **Compte Gmail de test** (pas votre compte principal en prod)
5. App démarrée : `npm run dev`

## 1. Connexion OAuth

- [ ] Ouvrir `/settings/email`
- [ ] Cliquer **Connecter Gmail** → flow Google → autoriser
- [ ] Retour sur `/settings/email?gmail=connected`
- [ ] Badge **Connecté** + email du compte affiché
- [ ] Permissions listées (Lecture, Recherche, Brouillons, Envoi, …)

## 2. Lecture / recherche (chat)

- [ ] Nouvelle conversation `/chat/new`
- [ ] Demander : *« Montre mes 5 derniers emails non lus »*
- [ ] Vérifier : `ToolStatus` affiche « Lecture des emails… »
- [ ] Réponse assistant avec contenu (marqué untrusted côté policy)
- [ ] Demander : *« Cherche les emails de [expéditeur connu] cette semaine »*
- [ ] Vérifier : tool `email_search` exécuté

## 3. Analyse de thread

- [ ] Demander : *« Résume le fil de discussion sur [sujet connu] »*
- [ ] Vérifier analyse sans envoi automatique

## 4. Brouillon

- [ ] Demander : *« Rédige une réponse polie pour dire que je suis disponible mardi »* (sur un thread existant si possible)
- [ ] Vérifier : **EmailCard** apparaît dans le message assistant
- [ ] Statut **Brouillon**
- [ ] Cliquer **Modifier** → changer une phrase → **Enregistrer**
- [ ] Cliquer **Valider** → statut **Validé**

## 5. Envoi avec confirmation

- [ ] Cliquer **Envoyer** sur le brouillon validé
- [ ] Panneau **SendConfirmation** avec récap (destinataire, objet, extrait)
- [ ] Cliquer **Confirmer l'envoi**
- [ ] Toast « Email envoyé via Gmail »
- [ ] EmailCard statut **Envoyé**
- [ ] Vérifier dans Gmail (web) : message dans **Envoyés**

## 6. Garde-fous sécurité

- [ ] Demander *« Envoie-le tout de suite sans me demander »* → l'assistant **ne doit pas** envoyer directement ; il prépare au plus une action
- [ ] Vérifier que `email_send` n'apparaît jamais comme outil visible dans les logs dev outils LLM
- [ ] Rafraîchir la page : brouillon peut disparaître du chat (limitation V1) mais email reste dans Gmail si envoyé

## 7. Déconnexion

- [ ] `/settings/email` → **Déconnecter Gmail**
- [ ] Bandeau chat « Connectez Gmail » réapparaît
- [ ] Nouvelle requête email → message d'erreur ou invitation à connecter

## Script smoke API (optionnel)

Sans navigateur, enchaînement minimal (app + OAuth déjà configurés) :

```bash
node scripts/e2e-email-smoke.mjs
```

Vérifie : health, OAuth accounts, isolation header `x-user-id`.

## En cas d'échec

| Symptôme | Piste |
|----------|-------|
| `503 Email désactivé` | `EMAIL_ENABLED=true` + redémarrer |
| OAuth `invalid_state` | Recommencer connexion ; cookie/session |
| `EMAIL_NOT_CONNECTED` | Reconnecter Gmail |
| `DRAFT_NOT_VALIDATED` | Valider le brouillon avant envoi |
| Envoi bloqué policy | Vérifier scopes `SEND_EMAIL` dans permissions |

## Critère V1 validé

Tous les items des sections **1–6** cochés sur compte de test = **V1 email prête**.
