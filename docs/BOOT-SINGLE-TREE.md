# Boot PC (WoL + démarrage services) — arbre unique

## Emplacement

Tout tourne depuis **`D:\chatbot-public`** uniquement.

| Élément | Chemin |
|---------|--------|
| Config machine | `deploy/boot/machine.env` |
| Boot conditionnel (après WoL) | tâche `ChatbotConditionalBoot` → `scripts/boot/conditional-start.cmd` |
| Poll start-services (PC déjà allumé) | tâche `ChatbotBootPoll` → `scripts/boot/poll-boot-request-hidden.vbs` |
| Stack | `scripts/boot/orchestrator.mjs` (Docker, LM Studio, Next, SearXNG, Supervisor) |

`D:\Chatbot` est **condamné** (voir `D:\Chatbot.CONDEMNED\CONDEMNED.md` si renommé).

## Réinstaller les tâches

```powershell
cd D:\chatbot-public
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\boot\install-startup-task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\boot\install-poll-task.ps1
```

Vérifier :

```powershell
Get-ScheduledTask -TaskName ChatbotConditionalBoot,ChatbotBootPoll |
  ForEach-Object { $_.Actions.Execute; $_.Actions.Arguments; $_.Actions.WorkingDirectory }
```

Les chemins doivent contenir `D:\chatbot-public`, jamais `D:\Chatbot`.

## Tests

```powershell
cd D:\chatbot-public
npm.cmd run boot:conditional:dry-run
npm.cmd run boot:poll
```

Wake app → Worker Freebox WoL → au login Windows, ConditionalBoot consomme la demande et démarre la stack.  
PC déjà allumé → BootPoll (1 min) exécute `start-services`.
