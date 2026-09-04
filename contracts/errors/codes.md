# API error codes

Voir `src/lib/http/api-error.ts` (source runtime) et `api-error.schema.json`.

| Code | HTTP typique |
|------|--------------|
| AUTH_REQUIRED | 401 |
| FORBIDDEN | 403 |
| NOT_FOUND | 404 |
| VALIDATION_ERROR | 400 |
| FEATURE_DISABLED | 503 |
| EMAIL_NOT_CONNECTED | 403 |
| PROVIDER_ERROR | 502 |
| AI_ERROR | 500 |
| RATE_LIMITED | 429 |
| INVALID_STATE | 409 |
| EXPIRED | 410 |
| ALREADY_USED | 409 |
| POLICY_DENIED | 403 |
| ABORTED | SSE only |
| INTERNAL | 500 |
