#Requires -Version 5.1
<#
.SYNOPSIS
  Installe la tâche planifiée Windows « ChatbotSupervisor ».

.DESCRIPTION
  Démarre le superviseur au logon de l'utilisateur courant et le relance
  en cas d'échec. Exécute : node scripts/supervisor/index.mjs
#>

$ErrorActionPreference = "Stop"

$TaskName = "ChatbotSupervisor"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$IndexPath = Join-Path $RepoRoot "scripts\supervisor\index.mjs"

$NodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $NodeCmd) {
  throw "node introuvable dans le PATH. Installe Node.js puis réessaie."
}
$NodePath = $NodeCmd.Source

if (-not (Test-Path -LiteralPath $IndexPath)) {
  throw "Fichier introuvable: $IndexPath"
}

$Action = New-ScheduledTaskAction `
  -Execute $NodePath `
  -Argument "`"$IndexPath`"" `
  -WorkingDirectory $RepoRoot

$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$Settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit (New-TimeSpan -Days 0) `
  -MultipleInstances IgnoreNew

$Principal = New-ScheduledTaskPrincipal `
  -UserId $env:USERNAME `
  -LogonType Interactive `
  -RunLevel Limited

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $Action `
  -Trigger $Trigger `
  -Settings $Settings `
  -Principal $Principal `
  -Description "Chatbot Supervisor — surveille docker/searxng/nextjs/lm_studio/cloudflared" `
  | Out-Null

Write-Host "Tâche '$TaskName' installée."
Write-Host "  Node : $NodePath"
Write-Host "  Script : $IndexPath"
Write-Host "  Cwd : $RepoRoot"
Write-Host "Démarre au logon ; redémarrage auto en cas d'échec (toutes les 1 min)."

$start = Read-Host "Démarrer la tâche maintenant ? (o/N)"
if ($start -match '^[oOyY]') {
  Start-ScheduledTask -TaskName $TaskName
  Write-Host "Tâche démarrée."
}
