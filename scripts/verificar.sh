#!/usr/bin/env bash
# Verificación del media stack. Solo LEE: no arranca, no para, no borra nada.
#   bash ~/mediastack/scripts/verificar.sh
# Salida 0 = todo OK. Salida 1 = hay al menos un FALLO.

set -uo pipefail

FALLOS=0
ok()    { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
fallo() { printf '  \033[31mFALLO\033[0m %s\n' "$1"; FALLOS=$((FALLOS+1)); }
aviso() { printf '  \033[33mAVISO\033[0m %s\n' "$1"; }
titulo(){ printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

titulo "Entorno WSL"
grep -qi microsoft /proc/version && ok "corriendo dentro de WSL2" || aviso "no parece WSL (¿Linux nativo?)"
if [ -d /run/systemd/system ]; then ok "systemd activo"; else fallo "systemd NO activo → revisar /etc/wsl.conf y 'wsl --shutdown'"; fi
printf '  INFO  RAM total en WSL: %s\n' "$(free -h | awk '/^Mem:/{print $2}')"
printf '  INFO  RAM libre:        %s\n' "$(free -h | awk '/^Mem:/{print $7}')"

titulo "Docker"
if docker info >/dev/null 2>&1; then
  ok "dockerd responde ($(docker --version | cut -d, -f1))"
else
  fallo "dockerd no responde → sudo systemctl status docker"
fi
docker compose version >/dev/null 2>&1 && ok "plugin 'docker compose' presente" \
  || fallo "falta el plugin compose (docker-compose v1 NO sirve para Immich)"

titulo "Montajes del NAS"
# OJO con lo que prueba cada cosa (aprendido a base de perder 17 horas, 2026-09-03):
#   - 'mountpoint -q' NO prueba que el NFS responda. Con x-systemd.automount el punto de
#     montaje existe siempre, esté vivo el NAS o no.
#   - El 'find' de abajo tampoco vale por sí solo: con 'timeout' y '2>/dev/null', un montaje
#     colgado devuelve exactamente lo mismo que una carpeta vacía —nada— y salía como AVISO.
#     Un NFS muerto tarda ~17 s y da 'No such device'; eso es un FALLO, no un aviso.
# Por eso se prueba primero que la carpeta se pueda ABRIR, y se separa el error del vacío.
for m in /mnt/nas/fotos /mnt/nas/fotos-historico /mnt/nas/musica /mnt/nas/video; do
  if ! mountpoint -q "$m"; then
    fallo "$m NO está montado"
    continue
  fi
  err=$(timeout 25 ls -A "$m" 2>&1 >/dev/null); rc=$?
  if [ "$rc" -eq 124 ]; then
    fallo "$m no contesta en 25 s → el montaje NFS está colgado"
  elif [ "$rc" -ne 0 ]; then
    fallo "$m montado pero ilegible: ${err:-error $rc}"
  else
    n=$(timeout 20 find "$m" -maxdepth 4 -type f 2>/dev/null | head -1)
    if [ -n "$n" ]; then ok "$m montado y con contenido legible"
    else aviso "$m se abre bien, pero no tiene ficheros en 4 niveles"; fi
  fi
done

titulo "Reglas de almacenamiento (esto es lo que rompe instalaciones)"
DBDIR=$(grep -h '^DB_DATA_LOCATION=' ~/mediastack/immich/.env 2>/dev/null | cut -d= -f2-)
if [ -z "${DBDIR:-}" ]; then
  aviso "no encuentro DB_DATA_LOCATION en immich/.env"
else
  case "$DBDIR" in
    /mnt/*) fallo "Postgres apunta a $DBDIR — es un montaje de red o de Windows. PROHIBIDO" ;;
    *)      ok "Postgres en ruta local: $DBDIR"
            df -h "$DBDIR" 2>/dev/null | tail -1 | awk '{printf "  INFO  libre en ese disco: %s de %s\n",$4,$2}' ;;
  esac
fi
for d in /var/lib/mediastack/navidrome/data /var/lib/mediastack/jellyfin/config; do
  [ -d "$d" ] && ok "$d es local" || aviso "$d no existe todavía"
done

titulo "Contenedores"
# immich_machine_learning NO esta en la lista a proposito: en este equipo va
# apagado por defecto y se arranca a demanda con scripts/ml.sh (ver PLAN.md §3).
esperados="immich_server immich_postgres immich_redis navidrome jellyfin"
for c in $esperados; do
  # Ojo: cuando el contenedor no existe, 'docker inspect' falla pero deja un salto de
  # linea en la salida. Sin el tr, "$estado" seria "\nausente" y no casaria con nada.
  estado=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null | tr -d '\r\n')
  salud=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$c" 2>/dev/null | tr -d '\r\n')
  [ -z "$estado" ] && estado="ausente"
  [ -z "$salud" ]  && salud="-"
  case "$estado" in
    running) [ "$salud" = "unhealthy" ] && fallo "$c running pero unhealthy" || ok "$c running (salud: $salud)" ;;
    ausente) aviso "$c no existe todavía" ;;
    *)       fallo "$c en estado '$estado'" ;;
  esac
done

titulo "Puertos HTTP"
comprueba_http() {
  # Sin '|| echo 000': cuando curl falla ya imprime "000" por el -w, y el echo
  # anadia otro, dejando el codigo en "000000".
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$2" 2>/dev/null | tr -d '\r\n')
  [ -z "$code" ] && code=000
  case "$code" in
    200|30[12]|401|403) ok "$1 responde HTTP $code en $2" ;;
    000) fallo "$1 no responde en $2" ;;
    *)   aviso "$1 responde HTTP $code en $2" ;;
  esac
}
comprueba_http "Immich"    "http://localhost:2283/api/server/ping"
comprueba_http "Navidrome" "http://localhost:4533/ping"
comprueba_http "Jellyfin"  "http://localhost:8096/health"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^immich_machine_learning$'; then
  aviso "immich_machine_learning ESTA ARRANCADO - recuerda pararlo con: bash scripts/ml.sh off"
else
  ok "immich_machine_learning parado (lo esperado en este equipo)"
fi

titulo "Consumo de memoria por contenedor"
docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}} ({{.MemPerc}})' 2>/dev/null || aviso "docker stats no disponible"

printf '\n'
if [ "$FALLOS" -eq 0 ]; then
  printf '\033[32mVERIFICACIÓN OK — 0 fallos\033[0m\n'; exit 0
else
  printf '\033[31mVERIFICACIÓN CON %s FALLO(S)\033[0m — no avances de fase hasta resolverlos\n' "$FALLOS"; exit 1
fi
