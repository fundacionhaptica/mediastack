#!/usr/bin/env bash
# Volcado diario de la base de datos de Immich al NAS.
#
# POR QUÉ: las fotos están a salvo en el NAS, pero álbumes, caras, personas,
# fechas corregidas y usuarios viven SOLO en Postgres. Perder Postgres = perder
# todo el trabajo de organización aunque no se pierda ni una foto.
#
# Este script NO borra fotos ni toca la biblioteca. Solo escribe .sql.gz y
# rota los volcados antiguos DENTRO de su propia carpeta de backups.
#
# DESTINO: /volume1/Media/backup-immich en el NAS, o sea, una subcarpeta del mismo
# recurso compartido que usa Immich como UPLOAD_LOCATION. Decision de Jaime del
# 2026-08-27. Immich no borra carpetas que no conoce, asi que convive sin problema;
# la contrapartida es que volcado y biblioteca comparten carpeta compartida, y de
# eso responde el backup del propio NAS.
#
# Cron (dentro de WSL, alineado con la ventana de backup del NAS a la 1:00):
#   crontab -e
#   30 0 * * * /home/jaime/mediastack/scripts/backup-immich-db.sh >> /home/jaime/immich-backup.log 2>&1

set -euo pipefail

DESTINO="/mnt/nas/fotos/backup-immich"
RETENCION_DIAS=30
CONTENEDOR="immich_postgres"

mountpoint -q /mnt/nas/fotos || { echo "[$(date -Is)] ERROR: /mnt/nas/fotos no montado"; exit 1; }
mkdir -p "$DESTINO"

FICHERO="$DESTINO/immich-$(date +%Y%m%d-%H%M).sql.gz"

# --clean --if-exists deja el volcado listo para restaurar sobre una BBDD existente
docker exec -t "$CONTENEDOR" pg_dumpall --clean --if-exists --username=postgres \
  | gzip > "$FICHERO.parcial"

mv "$FICHERO.parcial" "$FICHERO"

TAM=$(du -h "$FICHERO" | cut -f1)
echo "[$(date -Is)] OK volcado $FICHERO ($TAM)"

# Rotación: solo ficheros immich-*.sql.gz de ESTA carpeta. Nada más.
find "$DESTINO" -maxdepth 1 -name 'immich-*.sql.gz' -type f -mtime +$RETENCION_DIAS -print -delete

# Restauración (manual, con el stack parado salvo la BBDD):
#   gunzip < immich-AAAAMMDD-HHMM.sql.gz | docker exec -i immich_postgres psql --username=postgres
