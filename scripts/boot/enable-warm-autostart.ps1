#Requires -Version 5.1
<#
  Prechauffage optionnel au login Windows (PC serveur WoL).
  - Docker Desktop : raccourci dossier Demarrage
  - LM Studio serveur : tache planifiee lms server start (optionnel)

  Usage :
    .\enable-warm-autostart.ps1
    .\enable-warm-autostart.ps1 -LmStudio
    .\enable-warm-autostart.ps1 -Disable
#>

param(
  [switch]$LmStudio,
  [switch]$Disable
)

$ErrorActionPreference = 'Stop'

$DockerPaths = @(
  (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe')
)
$pf86 = ${env:ProgramFiles(x86)}
if ($pf86) {
  $DockerPaths += Join-Path $pf86 'Docker\Docker\Docker Desktop.exe'
}

$StartupFolder = [Environment]::GetFolderPath('Startup')
$DockerShortcut = Join-Path $StartupFolder 'Chatbot-Docker Desktop.lnk'
$LmTaskName = 'ChatbotWarmLmStudio'

function Find-DockerDesktop {
  foreach ($path in $DockerPaths) {
    if (Test-Path $path) { return $path }
  }
  return $null
}

function Remove-WarmAutostart {
  if (Test-Path $DockerShortcut) {
    Remove-Item $DockerShortcut -Force
    Write-Host "Retire : $DockerShortcut" -ForegroundColor Yellow
  }

  $lmTask = Get-ScheduledTask -TaskName $LmTaskName -ErrorAction SilentlyContinue
  if ($lmTask) {
    Unregister-ScheduledTask -TaskName $LmTaskName -Confirm:$false
    Write-Host "Tache retiree : $LmTaskName" -ForegroundColor Yellow
  }
}

if ($Disable) {
  Remove-WarmAutostart
  Write-Host 'OK - prechauffage login desactive.' -ForegroundColor Green
  exit 0
}

$dockerExe = Find-DockerDesktop
if ($dockerExe) {
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($DockerShortcut)
  $shortcut.TargetPath = $dockerExe
  $shortcut.WorkingDirectory = Split-Path $dockerExe -Parent
  $shortcut.WindowStyle = 7
  $shortcut.Description = 'Chatbot WoL - Docker Desktop au login'
  $shortcut.Save()
  Write-Host "OK - Docker au login : $DockerShortcut" -ForegroundColor Green
} else {
  Write-Host 'Docker Desktop introuvable - raccourci non cree.' -ForegroundColor Yellow
}

if ($LmStudio) {
  $lms = Get-Command lms -ErrorAction SilentlyContinue
  if (-not $lms) {
    Write-Host 'CLI lms introuvable - ajoutez LM Studio CLI au PATH.' -ForegroundColor Yellow
  } else {
    $existing = Get-ScheduledTask -TaskName $LmTaskName -ErrorAction SilentlyContinue
    if ($existing) {
      Unregister-ScheduledTask -TaskName $LmTaskName -Confirm:$false
    }

    $action = New-ScheduledTaskAction -Execute 'lms' -Argument 'server start'
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $settings.ExecutionTimeLimit = 'PT5M'

    Register-ScheduledTask `
      -TaskName $LmTaskName `
      -Action $action `
      -Trigger $trigger `
      -Settings $settings `
      -Description 'Chatbot WoL - serveur LM Studio au login' `
      -RunLevel Limited | Out-Null

    Write-Host "OK - LM Studio serveur au login : tache $LmTaskName" -ForegroundColor Green
  }
}

Write-Host ''
Write-Host 'Desactiver : .\enable-warm-autostart.ps1 -Disable' -ForegroundColor DarkGray
