' Lance poll-boot-request.mjs sans fenêtre console (tâche planifiée Windows).
Option Explicit

Dim fso, shell, scriptDir, projectRoot, logFile, nodeScript, cmd

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("Wscript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
projectRoot = fso.GetParentFolderName(fso.GetParentFolderName(scriptDir))
logFile = projectRoot & "\data\boot-poll.log"
nodeScript = scriptDir & "\poll-boot-request.mjs"

If Not fso.FolderExists(projectRoot & "\data") Then
  fso.CreateFolder projectRoot & "\data"
End If

cmd = "cmd /c cd /d """ & projectRoot & """ && node """ & nodeScript & """ >> """ & logFile & """ 2>&1"
shell.Run cmd, 0, True
