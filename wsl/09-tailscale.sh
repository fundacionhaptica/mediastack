#!/usr/bin/env bash
# FASE 9 (pieza 1) — Tailscale DENTRO de Ubuntu/WSL, no en Windows.
#
# Por qué dentro y no en Windows: si tailscaled corre en Windows, la IP del tailnet
# es de Windows y los contenedores están en WSL. El tráfico del tailnet llega a la IP
# de Windows, no a localhost, así que el reenvío automático de WSL2 no sirve y haría
# falta 'netsh portproxy' — una pieza más que se rompe sola en cada actualización de
# WSL. Dentro de Ubuntu, Caddy y los contenedores comparten la misma red y ya está.
#
# Prerrequisitos, ya comprobados en este equipo el 2026-08-27:
#   /dev/net/tun existe, ip_forward=1, systemd 'running'.
# Contrapartida: WSL tiene que estar arrancada — que es justo lo que garantiza la
# tarea programada de la fase 6.
#
# Ejecutar como root:
#   wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/wsl/09-tailscale.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: esto va como root."
  echo "  wsl -d Ubuntu-24.04 -u root -- $0"
  exit 1
fi

echo "== Comprobando prerrequisitos =="
[ -c /dev/net/tun ] || { echo "ERROR: falta /dev/net/tun"; exit 1; }
[ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ] || echo "AVISO: ip_forward=0 (solo importa si vas a usar subnet router)"
systemctl is-system-running --quiet 2>/dev/null || echo "AVISO: systemd no dice 'running'; sigue, pero revisa /etc/wsl.conf"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "== Instalando Tailscale =="
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "Tailscale ya está instalado: $(tailscale version | head -1)"
fi

systemctl enable --now tailscaled

echo
echo "== Autenticación =="
echo "El siguiente comando imprime una URL. Ábrela en el navegador e inicia sesión."
echo "'--ssh' queda fuera a propósito: no hace falta y amplía superficie."
echo
echo "  tailscale up --hostname=minipc-jrh"
echo
echo "Y cuando termine, la IP que va en los registros DNS de Cloudflare:"
echo
echo "  tailscale ip -4"
echo
echo "Esa IP (100.x.y.z) es la que se pone en caddy/.env como TS_IP y en los"
echo "registros «solo DNS» (nube GRIS) de la zona ruizespana.com."
