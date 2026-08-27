# FASE 6 - tarea programada que levanta WSL y el stack al encender el mini PC.
#
# EJECUTAR EN POWERSHELL COMO ADMINISTRADOR, en el mini PC:
#   powershell -ExecutionPolicy Bypass -File C:\claude\mediastack\wsl\06-arranque-automatico.ps1
#
# Idempotente: si la tarea "MediaStack" ya existe, la reemplaza.
#
# Esto es SOLO la pieza 3 de las tres que hacen falta. Las otras dos son manuales:
#   1. BIOS/UEFI -> Restore on AC Power Loss = Power On
#   2. Inicio de sesion automatico (netplwiz) NO hace falta con esta tarea, porque
#      corre como SYSTEM "tanto si el usuario inicio sesion como si no".

$ErrorActionPreference = 'Stop'

$distro = 'Ubuntu-24.04'
$script = '/home/jaime/mediastack/scripts/boot-mediastack.sh'
$tarea  = 'MediaStack'

# Comprobacion de elevacion: sin esto Register-ScheduledTask -User SYSTEM da acceso denegado.
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "ERROR: hay que ejecutar esto en un PowerShell ELEVADO." -ForegroundColor Red
  exit 1
}

# El argumento va sin comillas internas ni '$' a proposito: wsl.exe recibe solo
# una ruta. Toda la logica (log, sudo, espera a dockerd) esta dentro del .sh.
$argumento = "-d $distro -u root -- $script"

$accion = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wsl.exe' -Argument $argumento
$disparador = New-ScheduledTaskTrigger -AtStartup
$opciones = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

if (Get-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue) {
  Write-Host "La tarea '$tarea' ya existe: se reemplaza."
  Unregister-ScheduledTask -TaskName $tarea -Confirm:$false
}

Register-ScheduledTask -TaskName $tarea -Action $accion -Trigger $disparador `
  -Settings $opciones -RunLevel Highest -User 'SYSTEM' | Out-Null

Write-Host "Tarea '$tarea' registrada." -ForegroundColor Green
Get-ScheduledTask -TaskName $tarea | Format-List TaskName, State
(Get-ScheduledTask -TaskName $tarea).Actions | Format-List Execute, Arguments

Write-Host ""
Write-Host "Probarla SIN reiniciar:" -ForegroundColor Cyan
Write-Host "  Start-ScheduledTask -TaskName $tarea"
Write-Host "  wsl -d $distro -- tail -30 /var/log/mediastack-boot.log"
Write-Host ""
Write-Host "La prueba de verdad es un reinicio en frio (VERIFICACION 6 de PASOS.md)."
