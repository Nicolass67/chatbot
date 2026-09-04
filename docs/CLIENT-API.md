# Client Surface API

Surface HTTP destinée aux clients **Web React** et **futur SwiftUI**.  
Ce n’est **pas** l’inventaire exhaustif des ~53 routes du monolithe.

**Versions :** `GET /api/meta/client-api` → `apiVersion`, `chatEventsVersion`, `contractsVersion`.  
Headers réponse chat SSE : `X-API-Version`, `X-Chat-Events-Version`.

Erreurs publiques : `{ "error": string, "code": ApiErrorCode }` — voir `contracts/errors/`.

---

## Inclus (public client)

### Meta / Auth app
| Method | Path |
|--------|------|
| GET | `/api/meta/client-api` |
| GET | `/api/auth/app-session/start` |
| POST | `/api/auth/app-session` |
| DELETE | `/api/auth/app-session` |

### Chat / conversations
| Method | Path |
|--------|------|
| GET, POST | `/api/conversations` — GET `?scope=general\|mail\|files` ; POST `{ scope?, contextKey?, contextLabel?, title? }` |
| GET, PATCH, DELETE | `/api/conversations/[id]` |
| GET | `/api/conversations/[id]/messages` |
| GET | `/api/conversations/[id]/context` |
| POST | `/api/chat` (SSE) — body optionnel `activeContext: { fileId?, mailThreadId?, rootId?, label? }` |
| GET, DELETE | `/api/attachments/[id]` (`?w=` / `?thumb=1` → miniature JPEG) |

### Runtime / settings / memory
| Method | Path |
|--------|------|
| GET, PATCH | `/api/settings` |
| GET | `/api/runtime/status` |
| GET | `/api/runtime/web-status` |
| POST | `/api/runtime/model` |
| GET | `/api/runtime/reasoning-capabilities` |
| GET | `/api/lm-studio/models` |
| GET, POST | `/api/memories` |
| DELETE | `/api/memories/[id]` |

### Mail / OAuth / email actions
| Method | Path |
|--------|------|
| GET | `/api/oauth/accounts` |
| GET | `/api/oauth/gmail/start` |
| GET | `/api/oauth/gmail/callback` |
| POST | `/api/oauth/gmail/disconnect` |
| GET | `/api/mail/messages` |
| GET | `/api/mail/messages/[id]` |
| GET | `/api/mail/messages/[id]/attachment` |
| POST | `/api/mail/messages/[id]/read` |
| GET | `/api/mail/threads/[id]` |
| POST | `/api/mail/ai/summarize` |
| POST | `/api/mail/ai/suggest-reply` |
| POST | `/api/mail/ai/chat` |
| POST | `/api/mail/actions/trash` |
| POST | `/api/mail/actions/[id]/confirm` |
| POST | `/api/email/actions/send` |
| GET | `/api/email/actions/pending` |
| GET | `/api/email/actions/[id]` |
| POST | `/api/email/actions/[id]/confirm` |
| POST | `/api/email/actions/[id]/cancel` |
| GET, PATCH | `/api/email/drafts/[id]` |
| POST | `/api/email/drafts/[id]/validate` |

### Files
| Method | Path |
|--------|------|
| GET, POST, PATCH, DELETE | `/api/files/roots` |
| GET | `/api/files/list` |
| GET | `/api/files/search` |
| GET | `/api/files/content` |
| POST | `/api/files/index` |
| POST | `/api/files/upload` |
| POST | `/api/files/propose` |
| POST | `/api/files/actions` |
| POST | `/api/files/ai/chat` |

---

## Exclus / internal (ne pas traiter comme contrat iOS V1)

| Path | Raison |
|------|--------|
| `/api/health` | Ops / Worker (`HEALTH_CHECK_TOKEN`) |
| `/api/perf/audit` | Profiler dev |
| `/api/lm-studio/health` | Ops |
| `/api/conversations/[id]/export` | Download navigateur (P2) |
| `/api/memories/import\|export` | Settings avancés (P2) |
| `/api/runtime/capabilities` | Legacy / à confirmer avant inclusion |

---

## Auth

- Web / Capacitor : Cloudflare Access (JWT assertion) → middleware → `x-user-id`.
- iOS SwiftUI : Access (ASWebAuthenticationSession) → `GET /api/auth/app-session/start` → Bearer `chs_…` (Keychain).
- Edge : Bypass Access recommandé sur `/api/*` pour Bearer ; UI HTML reste protégée.
- ADR : `docs/adr/001-app-session-bearer.md`
