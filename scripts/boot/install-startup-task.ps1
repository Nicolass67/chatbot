#Requires -Version 5.1
<#
  Installe une tâche planifiée Windows (à la connexion utilisateur)
  pour le démarrage conditionnel Chatbot après WoL Worker.
#>

param(
  [switch]$WarmAutostart,
  [switch]$WarmLmStudio
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$LogDir = Join-Path $ProjectRoot 'data'
$LogFile = Join-Path $LogDir 'boot-conditional.log'
$ScriptPath = Join-Path $ProjectRoot 'scripts\boot\conditional-start.cmd'
$TaskName = 'ChatbotConditionalBoot'

if (-not (Test-Path (Join-Path $ProjectRoot 'deploy\boot\machine.env'))) {
  Write-Host 'ERREUR: deploy\boot\machine.env manquant.' -ForegroundColor Red
  exit 1
}

if (-not (Test-Path $ScriptPath)) {
  Write-Host "ERREUR: $ScriptPath introuvable." -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Host "Tâche   : $TaskName"
Write-Host "Script  : $ScriptPath"
Write-Host "Journal : $LogFile"

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute $ScriptPath -WorkingDirectory (Split-Path $ScriptPath -Parent)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$settings.ExecutionTimeLimit = 'PT2H'

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Description 'Démarrage conditionnel Chatbot après WoL Worker Cloudflare' `
  -RunLevel Limited | Out-Null

Write-Host 'OK — tâche installée (déclenchement à la connexion).' -ForegroundColor Green

if ($WarmAutostart -or $WarmLmStudio) {
  $warmArgs = @()
  if ($WarmLmStudio) { $warmArgs += '-LmStudio' }
  & (Join-Path $PSScriptRoot 'enable-warm-autostart.ps1') @warmArgs
} else {
  Write-Host ''
  Write-Host 'Option vitesse : .\install-startup-task.ps1 -WarmAutostart' -ForegroundColor DarkGray
  Write-Host '  (Docker au login — recommandé PC serveur WoL)' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Test à chaud : npm run boot:conditional:dry-run'
Write-Host ''
Write-Host 'PC déjà allumé (bouton « Démarrer les services ») :' -ForegroundColor DarkGray
Write-Host '  .\install-poll-task.ps1   ou   npm run boot:install-poll-task' -ForegroundColor DarkGray
