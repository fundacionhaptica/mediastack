#!/usr/bin/env bash
# FASE 3 — descubrir y probar los montajes del NAS ANTES de tocar /etc/fstab.
#
# Nada de esto escribe en /etc/fstab. Monta a mano, enseña lo que se ve y desmonta.
# Ejecutar como root:
#   wsl -d Ubuntu-24.04 -u root -- /home/jaime/mediastack/scripts/montar-nas.sh <subcomando>
#
# Subcomandos:
#   diagnostico          qué protocolos ofrece el NAS ahora mismo
#   listar-smb USUARIO   nombres reales de las carpetas compartidas (pide contraseña)
#   probar-nfs RUTA      monta 192.168.1.205:RUTA en /mnt/nas/prueba, lista y desmonta
#   probar-cifs SHARE USUARIO   igual, por SMB (pide contraseña)
#
# Ejemplos:
#   ... diagnostico
#   ... listar-smb jaime
#   ... probar-nfs /volume1/foto
#   ... probar-cifs foto jaime

set -uo pipefail

NAS="${NAS_IP:-192.168.1.205}"
PRUEBA=/mnt/nas/prueba

rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
verde() { printf '\033[32m%s\033[0m\n' "$*"; }

puerto() {
  timeout 3 bash -c "echo > /dev/tcp/$NAS/$1" 2>/dev/null \
    && verde "  $1/tcp abierto   ($2)" \
    || rojo  "  $1/tcp cerrado   ($2)"
}

limpiar() {
  mountpoint -q "$PRUEBA" && umount "$PRUEBA"
  rmdir "$PRUEBA" 2>/dev/null
  return 0
}
trap limpiar EXIT

case "${1:-}" in

  diagnostico)
    echo "== Puertos en $NAS =="
    puerto 111  "rpcbind, hace falta para NFSv3"
    puerto 2049 "NFS"
    puerto 445  "SMB/CIFS"
    echo
    echo "== showmount (exports NFS) =="
    timeout 10 showmount -e "$NAS" 2>&1 | sed 's/^/  /'
    echo
    echo "Si 2049 está cerrado: DSM -> Panel de control -> Servicios de archivos -> NFS"
    echo "  -> Habilitar, version maxima NFSv4.1. Ver PASOS.md fase 3."
    echo "Si solo hay 445: se puede tirar por CIFS (variante B de wsl/fstab.snippet)."
    ;;

  listar-smb)
    USUARIO="${2:?falta el usuario del NAS}"
    echo "Carpetas compartidas visibles para '$USUARIO' en $NAS:"
    smbclient -L "$NAS" -U "$USUARIO" 2>&1 | sed 's/^/  /'
    echo
    echo "Los nombres de esta lista son los que van en /etc/fstab (//IP/NOMBRE)."
    ;;

  probar-nfs)
    RUTA="${2:?falta la ruta export, p.ej. /volume1/foto}"
    mkdir -p "$PRUEBA"
    echo "Montando $NAS:$RUTA ..."
    if mount -t nfs -o vers=4.1,soft,timeo=150 "$NAS:$RUTA" "$PRUEBA"; then
      verde "montado. Contenido:"
      ls -la "$PRUEBA" | head -15
      echo; df -h "$PRUEBA" | tail -1
    else
      rojo "no monta. Ejecuta '$0 diagnostico' para ver si NFS esta encendido."
      exit 1
    fi
    ;;

  probar-cifs)
    SHARE="${2:?falta el nombre de la carpeta compartida}"
    USUARIO="${3:?falta el usuario del NAS}"
    mkdir -p "$PRUEBA"
    echo "Montando //$NAS/$SHARE como $USUARIO ..."
    read -rsp "Contrasena de $USUARIO en el NAS: " PW; echo
    if mount -t cifs "//$NAS/$SHARE" "$PRUEBA" \
         -o "username=$USUARIO,password=$PW,uid=1000,gid=1000,vers=3.1.1,file_mode=0664,dir_mode=0775"; then
      unset PW
      verde "montado. Contenido:"
      ls -la "$PRUEBA" | head -15
      echo; df -h "$PRUEBA" | tail -1
    else
      unset PW
      rojo "no monta. Revisa usuario, contrasena y que la carpeta exista (listar-smb)."
      exit 1
    fi
    ;;

  *)
    sed -n '2,25p' "$0"
    exit 1
    ;;
esac
