#!/bin/bash
# Verificación del media stack en el NAS. Solo LEE: no arranca, no para, no borra nada.
#   bash /volume1/docker/mediastack/scripts/verificar-nas.sh
# Salida 0 = todo OK. Salida 1 = hay al menos un FALLO.
#
# Pensado para correr desde el contenedor nas-mcp (root, con /volume1/docker montado
# y el socket de Docker). Las carpetas compartidas (/volume1/photo...) NO están montadas
# ahí, así que se comprueban desde dentro de los propios contenedores.

set -uo pipefail
NAS=192.168.1.205
REPO=/volume1/docker/mediastack
DATA=/volume1/docker/mediastack-data

FALLOS=0
ok()    { printf '  OK     %s\n' "$1"; }
fallo() { printf '  FALLO  %s\n' "$1"; FALLOS=$((FALLOS+1)); }
aviso() { printf '  AVISO  %s\n' "$1"; }
titulo(){ printf '\n== %s ==\n' "$1"; }

titulo "Máquina"
awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "  INFO   RAM %.1f GiB, libre %.1f GiB\n",t/1048576,a/1048576}' /proc/meminfo
read -r _ u1 n1 s1 i1 w1 _ < /proc/stat; sleep 3; read -r _ u2 n2 s2 i2 w2 _ < /proc/stat
tot=$(( (u2-u1)+(n2-n1)+(s2-s1)+(i2-i1)+(w2-w1) )); [ "$tot" -gt 0 ] || tot=1
io=$(( 100*(w2-w1)/tot ))
if [ "$io" -ge 40 ]; then aviso "iowait ${io}% — disco saturado, no lanzar nada pesado"
else ok "iowait ${io}%"; fi

titulo "Docker"
if timeout 20 docker info >/dev/null 2>&1; then ok "dockerd responde"; else fallo "dockerd no responde en 20 s"; fi
docker network inspect mediastack-net >/dev/null 2>&1 && ok "red mediastack-net existe" \
  || fallo "falta la red: docker network create --subnet 10.100.5.0/24 mediastack-net"

titulo "Contenedores"
for c in immich_server immich_postgres immich_redis navidrome jellyfin; do
  st=$(docker inspect "$c" --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}} r={{.RestartCount}} oom={{.State.OOMKilled}}' 2>/dev/null)
  case "$st" in
    "") fallo "$c no existe" ;;
    running\ healthy*|running\ \ *) ok "$c: $st" ;;
    running\ starting*) aviso "$c: $st (arrancando)" ;;
    *) fallo "$c: $st" ;;
  esac
done
if docker inspect immich_machine_learning >/dev/null 2>&1; then
  printf '  INFO   ML de Immich: %s\n' "$(docker inspect immich_machine_learning --format '{{.State.Status}}')"
else
  printf '  INFO   ML de Immich: no creado (apagado a propósito hasta acabar las miniaturas)\n'
fi

titulo "Servicios por HTTP"
chk(){ c=$(timeout 10 curl -s -o /dev/null -w '%{http_code}' "$2" 2>/dev/null); c=${c:-000}
  case "$c" in 2*|3*) ok "$1 → $c";; *) fallo "$1 → $c ($2)";; esac; }
chk Immich    "http://$NAS:2283/api/server/ping"
chk Navidrome "http://$NAS:4533/ping"
chk Jellyfin  "http://$NAS:8096/health"

titulo "Bibliotecas legibles desde dentro"
docker exec immich_server sh -c 'ls /fotos-historico >/dev/null' 2>/dev/null && ok "Immich lee /fotos-historico" || fallo "Immich NO lee /fotos-historico"
docker exec navidrome sh -c 'ls /music >/dev/null' 2>/dev/null && ok "Navidrome lee /music" || fallo "Navidrome NO lee /music"
docker exec jellyfin sh -c 'ls /media >/dev/null' 2>/dev/null && ok "Jellyfin lee /media" || fallo "Jellyfin NO lee /media"
docker exec jellyfin sh -c 'test -r /dev/dri/renderD128 && test -w /dev/dri/renderD128' 2>/dev/null \
  && ok "Jellyfin puede usar la GPU (renderD128)" || aviso "Jellyfin no puede abrir /dev/dri/renderD128 → convertirá por CPU"

titulo "Reglas de almacenamiento"
DBDIR=$(grep -h '^DB_DATA_LOCATION=' "$REPO/immich/.env" 2>/dev/null | cut -d= -f2-)
case "$DBDIR" in
  "") fallo "no encuentro DB_DATA_LOCATION en immich/.env" ;;
  "$REPO"*) fallo "Postgres dentro del repo ($DBDIR) — PROHIBIDO, regla 5" ;;
  "$DATA"/*) ok "Postgres en $DBDIR" ;;
  *) aviso "Postgres en $DBDIR, fuera de $DATA" ;;
esac
git -C "$REPO" ls-files --error-unmatch immich/.env >/dev/null 2>&1 && fallo ".env versionado en git" || ok ".env fuera de git"
[ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] && ok "clon del repo limpio" || aviso "clon del repo con cambios sin commitear"

echo
if [ "$FALLOS" -eq 0 ]; then echo "Resultado: 0 fallos"; exit 0; else echo "Resultado: $FALLOS fallo(s)"; exit 1; fi
