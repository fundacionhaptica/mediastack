#!/usr/bin/env bash
# Arranque del stack completo. Se invoca desde la tarea programada de Windows
# (fase 6) y también sirve para arrancar a mano tras un mantenimiento.
#
# Idempotente: si ya está todo levantado, no hace daño.

set -uo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[$(date -Is)] arrancando media stack desde $BASE"

# Esperar a que el NAS esté accesible (tras un corte de luz el NAS puede tardar más).
#
# OJO: aquí había 'mountpoint -q', y no vale. Con x-systemd.automount el punto de montaje
# existe SIEMPRE, esté vivo el NFS o no, así que la espera daba por bueno el primer intento
# y seguía de largo. Eso es lo que el 2026-09-03 dejó immich_server, navidrome y jellyfin en
# estado 'created': se crearon contra montajes muertos. Hay que probar que la carpeta se
# pueda ABRIR de verdad.
NAS_OK=0
for i in $(seq 1 30); do
  if timeout 25 ls -A /mnt/nas/fotos >/dev/null 2>&1; then NAS_OK=1; break; fi
  echo "  esperando montajes del NAS... ($i/30)"
  sleep 10
done

# Si el NAS no responde, NO se arranca. Levantar Immich contra un montaje muerto no es
# medio arranque: crea contenedores rotos que luego hay que limpiar a mano, y en el peor
# caso mete a Immich en el bucle de reinicio de los marcadores .immich (HANDOFF.md).
# Mejor no arrancar y que se vea en el log, que arrancar mal y que parezca que va.
if [ "$NAS_OK" -ne 1 ]; then
  echo "[$(date -Is)] ABORTADO: /mnt/nas/fotos no se puede leer tras 5 minutos." >&2
  echo "  El NAS no responde o el montaje NFS está colgado. Comprobar, y arrancar a mano:" >&2
  echo "    bash $BASE/scripts/verificar.sh" >&2
  echo "    bash $BASE/scripts/arrancar-stack.sh" >&2
  exit 1
fi

for stack in immich navidrome jellyfin; do
  if [ -f "$BASE/$stack/docker-compose.yml" ]; then
    echo "--- $stack"
    (cd "$BASE/$stack" && docker compose up -d)
  fi
done

echo "[$(date -Is)] hecho. Verificación:  bash $BASE/scripts/verificar.sh"
