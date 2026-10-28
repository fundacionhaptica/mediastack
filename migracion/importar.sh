#!/bin/sh
# Sube a Immich, en la cuenta de cada usuario, lo descargado en _migracion.
#
#   ./importar.sh <usuario> <takeout|icloud> [--dry-run] [más opciones de immich-go]
#   usuarios: jaime | maria-espana | maria-herrero | maria-jesus
#
# Empezar SIEMPRE con --dry-run. Lanzar de noche (regla 9: el disco manda).
# Takeout: los ZIP van tal cual en _migracion/takeout/<usuario>/ (no descomprimir).
#
# --include-partner=false: si no, el Takeout de Jaime arrastraría las fotos que
# María le comparte como pareja en Google y saldrían duplicadas en su cuenta.
# --pause-immich-jobs=false: pausar trabajos exige clave de administrador.
set -eu
cd "$(dirname "$0")"
[ $# -ge 2 ] || { sed -n 3,5p "$0"; exit 1; }
set -a; . ./.env; set +a
U=$1; ORIGEN=$2; shift 2
VAR=IMMICH_KEY_$(echo "$U" | tr 'a-z-' 'A-Z_')
eval "KEY=\${$VAR:-}"
[ -n "$KEY" ] || { echo "Falta $VAR en .env"; exit 1; }
COMUN="--server=http://immich_server:2283 --api-key=$KEY --pause-immich-jobs=false --no-ui --log-file=/logs/$U-$ORIGEN.log"
case "$ORIGEN" in
  takeout) CMD="immich-go upload from-google-photos $COMUN --include-partner=false $* /takeout/$U/*.zip" ;;
  icloud)  CMD="immich-go upload from-folder $COMUN $* /icloud/$U" ;;
  *) echo "Origen: takeout o icloud"; exit 1 ;;
esac
exec docker compose run --rm -T immich-go sh -c "$CMD"