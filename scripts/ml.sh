#!/usr/bin/env bash
# Arranca o para el machine learning de Immich (caras y búsqueda por contenido).
#
# POR QUÉ EXISTE ESTE SCRIPT
#   El mini PC tiene 7,9 GB de RAM y Windows por debajo. Immich funciona bien sin
#   machine learning, pero con él la memoria no llega en horario normal. La salida
#   es tenerlo apagado y encenderlo a ratos, con el equipo libre, hasta procesar el
#   atrasado. Una vez indexado el histórico, el gasto diario es pequeño.
#
# USO
#   bash scripts/ml.sh on      arranca el contenedor de ML
#   bash scripts/ml.sh off     lo para (no borra nada: los modelos quedan en caché)
#   bash scripts/ml.sh estado  muestra si está en marcha y cuánta RAM usa
#
# IMPORTANTE: además de esto, en la web de Immich hay que activar o desactivar
#   Administración → Ajustes → Machine Learning
# Si los ajustes están activos y el contenedor apagado, los trabajos fallan y se
# reintentan sin parar.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../immich" && pwd)"
cd "$DIR" || exit 1

case "${1:-}" in
  on)
    echo "Arrancando machine learning de Immich..."
    docker compose --profile ml up -d immich-machine-learning
    echo
    echo "Ahora, en la web: Administración → Ajustes → Machine Learning → activar."
    echo "Y en Administración → Trabajos, lanza 'Búsqueda inteligente' y"
    echo "'Reconocimiento facial' con concurrencia 1."
    echo
    echo "Vigila la memoria con:  docker stats --no-stream"
    ;;
  off)
    echo "Desactiva primero el ML en la web (Ajustes → Machine Learning),"
    echo "para que no queden trabajos reintentando contra un contenedor apagado."
    read -r -p "Hecho? (s/N) " r
    [ "$r" != "s" ] && [ "$r" != "S" ] && { echo "Cancelado."; exit 0; }
    docker compose stop immich-machine-learning
    echo "ML parado. Los modelos descargados siguen en caché para la próxima."
    ;;
  estado)
    if docker ps --format '{{.Names}}' | grep -q '^immich_machine_learning$'; then
      echo "ML ARRANCADO"
      docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}} ({{.MemPerc}})' immich_machine_learning
    else
      echo "ML parado"
    fi
    echo
    echo "Memoria libre en WSL:"
    free -h | awk '/^Mem:/{printf "  %s libres de %s\n", $7, $2}'
    ;;
  *)
    echo "Uso: bash scripts/ml.sh {on|off|estado}"
    exit 1
    ;;
esac
