#!/usr/bin/env bash
# Preparación de la VM Oracle Always Free como borde público de pelis./fotos-vpn.
# Ejecutar como root (sudo) en una Ubuntu 24.04 recién creada. Ver oracle-vps/README.md.
#
# Qué hace: Docker, Tailscale, y el firewall del propio sistema (ufw) — la "capa 2" que
# hace falta ADEMÁS del Security List de OCI (capa 1, se abre a mano en la consola).
# Qué NO hace: no levanta Caddy. Eso es aparte (README.md paso 3) porque necesita saber
# antes la IP de Tailscale del mini PC.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
	echo "Ejecutar como root (sudo ./setup.sh)" >&2
	exit 1
fi

echo "== Actualizando el sistema =="
apt-get update
apt-get -y upgrade

echo "== Docker =="
if ! command -v docker >/dev/null 2>&1; then
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
		>/etc/apt/sources.list.d/docker.list
	apt-get update
	apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	usermod -aG docker ubuntu || true
else
	echo "Docker ya instalado, se salta."
fi

echo "== fail2ban + unattended-upgrades =="
apt-get install -y fail2ban unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable --now fail2ban

echo "== Tailscale =="
if ! command -v tailscale >/dev/null 2>&1; then
	curl -fsSL https://tailscale.com/install.sh | sh
fi
if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
	tailscale up --authkey="${TAILSCALE_AUTHKEY}" --hostname=oracle-vps-ruizespana --ssh
else
	echo "TAILSCALE_AUTHKEY no está puesta: 'tailscale up' pendiente, hazlo a mano:"
	echo "  tailscale up --hostname=oracle-vps-ruizespana --ssh"
fi

echo "== Firewall del sistema (ufw) — capa 2, además del Security List de OCI =="
# La imagen de Ubuntu de OCI trae reglas de iptables que bloquean todo salvo el 22.
# ufw las sustituye: sin esto, abrir el Security List en la consola no sirve de nada.
apt-get install -y ufw
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "== Hecho =="
echo "Falta: comprobar 'tailscale status' (si no había authkey), y seguir con el paso 3"
echo "del README (copiar .env.example a .env con la IP de Tailscale del mini PC y"
echo "'docker compose up -d')."
