# Mobile Parity Matrix — 3.0.0

Dernière mise à jour : 2026-09-03 · Native build **22** · Bundle `fr.nicolazer.chatbot.native`

Légende : ✅ native OK · 🟡 partiel · ❌ absent · N/A

| Surface | Web | Native 3.0 | Notes |
|---------|-----|------------|-------|
| Chat new conversation | ✅ | ✅ | Chat-first root |
| Historique / switcher | ✅ | ✅ | Sheet sectionnée |
| Streaming SSE + stop | ✅ | ✅ | Actor + generation guard |
| Attach image/fichier | ✅ | ✅ | |
| Mode chat/agent + modèle | ✅ | ✅ | Sheet options + Settings |
| Web search | ✅ | ✅ | |
| Files browse / preview | ✅ | ✅ | |
| Files mkdir / rename / upload | ✅ | ✅ | propose→confirm ; pas delete API |
| Mail list / detail | ✅ | ✅ | |
| Mail trash | ✅ | ✅ | |
| Mail OAuth connect | ✅ | 🟡 | Safari start URL JSON ; refresh manuel |
| Mail send drafts | ✅ | 🟡 | mailto / suggest-reply |
| Memory CRUD | ✅ | ✅ | |
| Settings / Face ID | ✅ | ✅ | |
| App Intents | N/A | 🟡 | NewChatIntent |
| Widgets / Live Activities | N/A | ❌ | Déférés plan |
| Capacitor shell | fallback | Soft freeze | Voir `MOBILE-3.0-CAPACITOR-EXIT.md` |

## Anti-patterns retirés

- Tab Plus
- Chat list as root
- Tool pills permanentes
- Options Menu qui ferme à chaque tap
