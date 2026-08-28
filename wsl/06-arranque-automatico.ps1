# FASE 6 - tarea programada que levanta WSL y el stack al encender el mini PC.
#
# EJECUTAR EN POWERSHELL COMO ADMINISTRADOR, en el mini PC:
#   powershell -ExecutionPolicy Bypass -File C:\claude\mediastack\wsl\06-arranque-automatico.ps1
#
# Idempotente: si la tarea "MediaStack" ya existe, la reemplaza.
#
# ---------------------------------------------------------------------------
# POR QUE NO CORRE COMO SYSTEM (esto es lo que rompe el recipe "de manual")
# ---------------------------------------------------------------------------
# Las distribuciones de WSL se registran POR USUARIO de Windows, en
# HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss. Comprobado en este equipo
# el 2026-08-28: Ubuntu-24.04 esta bajo el perfil de 'Admin', y la rama Lxss de
# S-1-5-18 (SYSTEM) esta VACIA.
#
# Una tarea que corriera como SYSTEM lanzaria wsl.exe y no encontraria ninguna
# distribucion: fallaria en cada arranque, y ademas en silencio, porque nadie
# esta delante para verlo.
#
# Por eso corre como el usuario dueno de la distro, con LogonType S4U: se ejecuta
# aunque no haya nadie con la sesion iniciada y NO hay que guardar la contrasena
# en ningun sitio. La contrapartida de S4U es que la tarea no tiene credenciales
# de red de Windows, cosa que aqui da igual: los montajes del NAS los hace el
# propio Linux dentro de WSL, no el token de Windows.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$distro  = 'Ubuntu-24.04'
$script  = '/home/jaime/mediastack/scripts/boot-mediastack.sh'
$tarea   = 'MediaStack'
$usuario = "$env:COMPUTERNAME\$env:USERNAME"   # el usuario que ejecuta esto

# Comprobacion de elevacion: sin esto Register-ScheduledTask da acceso denegado.
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "ERROR: hay que ejecutar esto en un PowerShell ELEVADO." -ForegroundColor Red
  exit 1
}

# Comprobacion de que la distro es de ESTE usuario. Si no, la tarea no funcionaria.
$lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
$distros = @()
if (Test-Path $lxss) {
  $distros = Get-ChildItem $lxss | ForEach-Object { (Get-ItemProperty $_.PSPath).DistributionName }
}
if ($distros -notcontains $distro) {
  Write-Host "ERROR: '$distro' no esta registrada para el usuario $usuario." -ForegroundColor Red
  Write-Host "Distros de este usuario: $($distros -join ', ')" -ForegroundColor Yellow
  Write-Host "Ejecuta este script desde la sesion del usuario dueno de la distro." -ForegroundColor Yellow
  exit 1
}

# El argumento va sin comillas internas ni '$' a proposito: wsl.exe recibe solo
# una ruta. Toda la logica (log, espera a dockerd, sudo) esta dentro del .sh.
$argumento = "-d $distro -u root -- $script"

$accion = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wsl.exe' -Argument $argumento

# 30 s de margen tras el arranque: da tiempo a que la red este lista antes de que
# Linux empiece a buscar el NAS.
$disparador = New-ScheduledTaskTrigger -AtStartup
$disparador.Delay = 'PT30S'

$principal = New-ScheduledTaskPrincipal -UserId $usuario -LogonType S4U -RunLevel Highest

$opciones = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

if (Get-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue) {
  Write-Host "La tarea '$tarea' ya existe: se reemplaza."
  Unregister-ScheduledTask -TaskName $tarea -Confirm:$false
}

Register-ScheduledTask -TaskName $tarea -Action $accion -Trigger $disparador `
  -Principal $principal -Settings $opciones | Out-Null

Write-Host "Tarea '$tarea' registrada para $usuario (S4U)." -ForegroundColor Green
Get-ScheduledTask -TaskName $tarea | Format-List TaskName, State
(Get-ScheduledTask -TaskName $tarea).Actions | Format-List Execute, Arguments

Write-Host ""
Write-Host "Probarla SIN reiniciar:" -ForegroundColor Cyan
Write-Host "  Start-ScheduledTask -TaskName $tarea"
Write-Host "  Get-ScheduledTaskInfo -TaskName $tarea | Format-List LastRunTime, LastTaskResult"
Write-Host "  wsl -d $distro -- tail -40 /var/log/mediastack-boot.log"
Write-Host ""
Write-Host "LastTaskResult 0 = bien. 267011 = aun corriendo." -ForegroundColor Cyan
Write-Host "Si S4U diera problemas, la alternativa es -LogonType Password, que pide"
Write-Host "la contrasena de $usuario y la guarda en el Programador de tareas."
Write-Host ""
Write-Host "La prueba de verdad es un reinicio en frio (VERIFICACION 6 de PASOS.md)."
