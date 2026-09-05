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
$SystemNode = "C:\Program Files\nodejs\node.exe"
if (Test-Path -LiteralPath $SystemNode) {
  $NodePath = $SystemNode
} elseif ($NodeCmd) {
  $NodePath = $NodeCmd.Source
} else {
  throw "node introuvable dans le PATH. Installe Node.js puis réessaie."
}

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
  -Description "Chatbot Supervisor - docker searxng nextjs lm_studio cloudflared" `
  | Out-Null

Write-Host "Tâche '$TaskName' installée."
Write-Host "  Node : $NodePath"
Write-Host "  Script : $IndexPath"
Write-Host "  Cwd : $RepoRoot"
Write-Host "Démarre au logon ; redémarrage auto en cas d'échec (toutes les 1 min)."

# Non-interactif : SUPERVISOR_START=1 ou -StartNow → démarre immédiatement
$autoStart = ($env:SUPERVISOR_START -eq "1") -or ($args -contains "-StartNow")
if ($autoStart) {
  Start-ScheduledTask -TaskName $TaskName
  Write-Host "Tâche démarrée."
} elseif ([Environment]::UserInteractive -and -not $env:CI) {
  $start = Read-Host "Démarrer la tâche maintenant ? (o/N)"
  if ($start -match '^[oOyY]') {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Tâche démarrée."
  }
} else {
  Write-Host "Tâche enregistrée (pas démarrée). Utilise: Start-ScheduledTask -TaskName $TaskName"
}
