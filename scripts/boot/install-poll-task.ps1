#Requires -Version 5.1
<#
  Installe une tâche planifiée Windows (toutes les 2 minutes, utilisateur connecté)
  pour détecter une demande POST /start-services quand le PC est déjà allumé.
#>

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$LogDir = Join-Path $ProjectRoot 'data'
$LogFile = Join-Path $LogDir 'boot-poll.log'
$ScriptPath = Join-Path $ProjectRoot 'scripts\boot\poll-boot-request-hidden.vbs'
$TaskName = 'ChatbotBootPoll'

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
Write-Host "Fréquence : toutes les 1 minute (session utilisateur, sans fenêtre)"

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
  -Execute 'wscript.exe' `
  -Argument "//B `"$ScriptPath`"" `
  -WorkingDirectory $ProjectRoot
$startTime = (Get-Date).AddMinutes(1)
$trigger = New-ScheduledTaskTrigger -Once -At $startTime -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
$settings.ExecutionTimeLimit = 'PT15M'

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Description 'Détecte POST /start-services Worker et lance la stack Chatbot (PC déjà allumé)' `
  -RunLevel Limited | Out-Null

Write-Host 'OK — tâche installée (sonde toutes les 1 min).' -ForegroundColor Green
Write-Host ''
Write-Host 'Test manuel : npm run boot:poll'
