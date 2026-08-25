#!/usr/bin/env bash
# Arranque del stack completo. Se invoca desde la tarea programada de Windows
# (fase 6) y también sirve para arrancar a mano tras un mantenimiento.
#
# Idempotente: si ya está todo levantado, no hace daño.

set -uo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[$(date -Is)] arrancando media stack desde $BASE"

# Esperar a que el NAS esté accesible (tras un corte de luz el NAS puede tardar más)
for i in $(seq 1 30); do
  if mountpoint -q /mnt/nas/fotos; then break; fi
  echo "  esperando montajes del NAS... ($i/30)"
  sleep 10
done

for stack in immich navidrome jellyfin; do
  if [ -f "$BASE/$stack/docker-compose.yml" ]; then
    echo "--- $stack"
    (cd "$BASE/$stack" && docker compose up -d)
  fi
done

echo "[$(date -Is)] hecho. Verificación:  bash $BASE/scripts/verificar.sh"
