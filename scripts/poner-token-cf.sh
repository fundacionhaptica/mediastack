#!/usr/bin/env bash
# Guarda el token de API de Cloudflare en caddy/.env sin que aparezca en pantalla
# ni en el historial del terminal.
#
#   wsl -d Ubuntu-24.04 -- /home/jaime/mediastack/scripts/poner-token-cf.sh
#
# El token sale de: Cloudflare -> My Profile -> API Tokens -> Create Token ->
# plantilla "Edit zone DNS", acotado a la zona ruizespana.com (Zone:DNS:Edit).

set -uo pipefail
ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/caddy/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: no existe $ENV_FILE"; exit 1; }

read -rsp "Pega el token de Cloudflare (no se vera nada al escribir): " TOKEN
echo

if [ -z "$TOKEN" ]; then echo "No has pegado nada. No se toca el fichero."; exit 1; fi

# Los tokens de Cloudflare son 40 caracteres de [A-Za-z0-9_-]. Un pegado a medias
# o con espacios se detecta aqui y no cuando Caddy no consiga el certificado.
if ! printf '%s' "$TOKEN" | grep -qE '^[A-Za-z0-9_-]{40}$'; then
  echo "AVISO: no parece un token de Cloudflare (40 caracteres alfanumericos)."
  echo "       Has pegado ${#TOKEN} caracteres."
  read -rp "Guardarlo igualmente? (s/N) " OK
  [ "${OK,,}" = "s" ] || { echo "Cancelado."; exit 1; }
fi

# Fichero temporal con permisos cerrados desde el principio: nunca hay una ventana
# en la que el token este en disco y sea legible por otros.
TMP=$(mktemp) && chmod 600 "$TMP"
grep -v '^CF_API_TOKEN=' "$ENV_FILE" > "$TMP"
printf 'CF_API_TOKEN=%s\n' "$TOKEN" >> "$TMP"
mv "$TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"
unset TOKEN

echo "Guardado en $ENV_FILE (permisos $(stat -c %a "$ENV_FILE"))."
echo "Comprobacion, sin enseñar el token:"
sed 's/^\(CF_API_TOKEN=\).*/\1<oculto, '"$(grep -c '^CF_API_TOKEN=.\+' "$ENV_FILE")"' definido>/' "$ENV_FILE"
