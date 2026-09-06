#Requires -Version 5.1
<#
.SYNOPSIS
  Installe/met a jour la tache planifiee Windows "ChatbotSupervisor".
  Au logon: lance run-forever.cmd qui relance le supervisor s'il crash.

  Ne desenregistre JAMAIS avant d'avoir reussi a creer la nouvelle definition
  (evite de perdre la tache si Register echoue / Access Denied).
#>
param(
  [string]$TaskName = "ChatbotSupervisor",
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  # Par défaut: PAS de démarrage au login (boot conditionnel Worker uniquement).
  # Le Supervisor est lancé par scripts/boot après un wake/start-services app.
  [switch]$AtLogOn,
  [switch]$StartupShortcut
)

$ErrorActionPreference = "Stop"
$wrapper = Join-Path $RepoRoot "scripts\supervisor\run-forever.cmd"
$entry = Join-Path $RepoRoot "scripts\supervisor\index.mjs"

if (-not (Test-Path -LiteralPath $wrapper)) {
  throw "Wrapper introuvable: $wrapper"
}
if (-not (Test-Path -LiteralPath $entry)) {
  throw "Entrypoint introuvable: $entry"
}

$action = New-ScheduledTaskAction `
  -Execute "cmd.exe" `
  -Argument ("/c `"{0}`"" -f $wrapper) `
  -WorkingDirectory $RepoRoot

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
  -UserId $env:USERNAME `
  -LogonType Interactive `
  -RunLevel Limited

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if (-not $AtLogOn) {
  if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "OK: tache '$TaskName' retiree (pas de demarrage au login)."
  } else {
    Write-Host "OK: pas de tache AtLogOn (boot conditionnel)."
  }
} else {
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  if ($existing) {
    Set-ScheduledTask `
      -TaskName $TaskName `
      -Action $action `
      -Trigger $trigger `
      -Settings $settings `
      -Principal $principal | Out-Null
    Write-Host "OK: tache '$TaskName' mise a jour (Set-ScheduledTask)."
  } else {
    try {
      Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Chatbot local supervisor (API :3927) - forever loop + restart on failure" | Out-Null
      Write-Host "OK: tache '$TaskName' creee."
    } catch {
      Write-Host "ERREUR: impossible de creer la tache (droits insuffisants ?)."
      Write-Host $_.Exception.Message
      throw
    }
  }
  Write-Host "  Trigger : AtLogOn"
}

Write-Host "  Wrapper : $wrapper"
Write-Host "  Entry   : $entry"
Write-Host "Note: le Supervisor demarre via boot conditionnel (wake/start-services), pas au login."
