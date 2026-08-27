#!/usr/bin/env bash
# FASE 6 — punto de entrada del arranque automatico. Lo invoca la tarea programada
# de Windows como root, SIN argumentos, para no depender del parseo de comillas de
# wsl.exe ni de PowerShell (ver "Trampas ya pagadas" en HANDOFF.md).
#
#   wsl.exe -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/boot-mediastack.sh
#
# Se encarga del log y de bajar a 'jaime'; la logica de arranque vive en
# arrancar-stack.sh, que tambien se puede lanzar a mano.

set -uo pipefail

USUARIO=jaime
LOG=/var/log/mediastack-boot.log

exec >>"$LOG" 2>&1

echo "=================================================================="
echo "[$(date -Is)] arranque automatico (uid=$(id -u))"

# Docker dentro de WSL tarda unos segundos en estar listo tras el boot de systemd.
for i in $(seq 1 30); do
  docker info >/dev/null 2>&1 && break
  echo "  esperando a dockerd... ($i/30)"
  sleep 5
done

exec sudo -u "$USUARIO" "/home/$USUARIO/mediastack/scripts/arrancar-stack.sh"
