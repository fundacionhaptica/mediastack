#!/usr/bin/env python3
"""
auto-albums — álbumes de Immich que se rellenan solos a partir de personas reconocidas.

Immich (v3.3) no tiene "álbumes automáticos por persona": sus Workflows aún no filtran por
cara ni añaden a álbumes. Este script lo suple con la API pública:

  1. Para cada álbum de config.json, busca todas las fotos/vídeos en los que sale
     cualquiera de sus personas (POST /api/search/metadata, filtro personIds.any).
  2. Añade al álbum lo que falte (PUT /api/albums/{id}/assets).
  3. En modo "espejo", quita del álbum lo que ya no corresponde
     (DELETE /api/albums/{id}/assets) — p. ej. tras corregir una cara mal asignada.

Sin dependencias: solo la biblioteca estándar de Python 3.10+.

Uso:
  python auto_albums.py              # bucle: sincroniza al arrancar y cada día a HORA
  python auto_albums.py --una-vez    # una pasada y sale
  python auto_albums.py --simular    # una pasada sin escribir nada en Immich

Variables de entorno:
  IMMICH_URL        p. ej. http://immich_server:2283
  IMMICH_API_KEY    clave de API del usuario dueño de las personas y de los álbumes
  CONFIG            ruta de config.json        (por defecto /config/config.json)
  ESTADO            ruta del fichero de estado  (por defecto /estado/estado.json)
  HORA              hora diaria HH:MM, local    (por defecto la de config.json, o 04:00)
  EJECUTAR_AL_ARRANCAR  1/0                     (por defecto 1)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

VISIBILIDADES = ["timeline", "archive"]  # nunca "locked" (carpeta bloqueada) ni "hidden"
LOTE = 500                               # ids por petición de añadir/quitar
PAGINA = 1000                            # máximo que admite la búsqueda
MAX_FRACCION_A_QUITAR = 0.5              # freno de seguridad del modo espejo


def log(msg: str) -> None:
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


class ErrorImmich(Exception):
    pass


class Immich:
    def __init__(self, url: str, clave: str):
        self.url = url.rstrip("/")
        self.clave = clave

    def _peticion(self, metodo: str, ruta: str, cuerpo=None):
        datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
        req = urllib.request.Request(
            self.url + ruta,
            data=datos,
            method=metodo,
            headers={
                "x-api-key": self.clave,
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                texto = r.read().decode()
                return json.loads(texto) if texto else None
        except urllib.error.HTTPError as e:
            detalle = e.read().decode(errors="replace")[:300]
            raise ErrorImmich(f"{metodo} {ruta} → HTTP {e.code}: {detalle}") from None
        except urllib.error.URLError as e:
            raise ErrorImmich(f"{metodo} {ruta} → sin conexión: {e.reason}") from None

    # --- búsquedas -------------------------------------------------------------
    def buscar_ids(self, filtro: dict) -> set[str]:
        """Todos los ids de asset que cumplen el filtro (forma nueva de v3.2+, con cursor)."""
        ids: set[str] = set()
        cursor = None
        while True:
            cuerpo = {"filter": filtro, "size": PAGINA, "withExif": False}
            if cursor:
                cuerpo["cursor"] = cursor
            r = self._peticion("POST", "/api/search/metadata", cuerpo)
            assets = (r or {}).get("assets") or {}
            for a in assets.get("items", []):
                ids.add(a["id"])
            cursor = assets.get("nextCursor")
            if not cursor:
                return ids

    def assets_de_personas(self, personas: list[str], todas: bool) -> set[str]:
        clave = "all" if todas else "any"
        return self.buscar_ids(
            {"personIds": {clave: personas}, "visibility": {"in": VISIBILIDADES}}
        )

    def assets_del_album(self, album_id: str) -> set[str]:
        # Mismo filtro de visibilidad que en las personas, para comparar like con like.
        return self.buscar_ids({"albumIds": {"any": [album_id]}, "visibility": {"in": VISIBILIDADES}})

    # --- personas y álbumes ----------------------------------------------------
    def persona(self, persona_id: str) -> dict:
        return self._peticion("GET", f"/api/people/{persona_id}")

    def album(self, album_id: str) -> dict | None:
        try:
            return self._peticion("GET", f"/api/albums/{album_id}")
        except ErrorImmich as e:
            if "HTTP 400" in str(e) or "HTTP 404" in str(e):
                return None
            raise

    def albumes(self) -> list[dict]:
        return self._peticion("GET", "/api/albums") or []

    def crear_album(self, nombre: str) -> dict:
        return self._peticion("POST", "/api/albums", {"albumName": nombre})

    def anadir(self, album_id: str, ids: list[str]) -> int:
        hechos = 0
        for i in range(0, len(ids), LOTE):
            r = self._peticion("PUT", f"/api/albums/{album_id}/assets", {"ids": ids[i:i + LOTE]})
            hechos += sum(1 for x in (r or []) if x.get("success"))
        return hechos

    def quitar(self, album_id: str, ids: list[str]) -> int:
        hechos = 0
        for i in range(0, len(ids), LOTE):
            r = self._peticion("DELETE", f"/api/albums/{album_id}/assets", {"ids": ids[i:i + LOTE]})
            hechos += sum(1 for x in (r or []) if x.get("success"))
        return hechos


# --- estado: nombre de álbum en config → id real en Immich ----------------------
def leer_estado(ruta: Path) -> dict:
    try:
        return json.loads(ruta.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def guardar_estado(ruta: Path, estado: dict) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    tmp = ruta.with_suffix(".tmp")
    tmp.write_text(json.dumps(estado, indent=2, ensure_ascii=False))
    os.replace(tmp, ruta)


def resolver_album(api: Immich, nombre: str, estado: dict, simular: bool) -> str | None:
    """Id del álbum: el recordado en el estado, si sigue existiendo; si no, por nombre;
    si no existe, se crea. Recordar el id evita duplicar el álbum si se renombra en Immich."""
    recordado = estado.get("albumes", {}).get(nombre)
    if recordado and api.album(recordado):
        return recordado
    coinciden = [a for a in api.albumes() if a.get("albumName") == nombre]
    if len(coinciden) > 1:
        raise ErrorImmich(f"hay {len(coinciden)} álbumes llamados «{nombre}»: deja solo uno")
    if coinciden:
        album_id = coinciden[0]["id"]
    elif simular:
        log(f"  [simulación] se crearía el álbum «{nombre}»")
        return None
    else:
        album_id = api.crear_album(nombre)["id"]
        log(f"  álbum «{nombre}» creado ({album_id})")
    estado.setdefault("albumes", {})[nombre] = album_id
    return album_id


def sincronizar_album(api: Immich, cfg: dict, estado: dict, simular: bool) -> None:
    nombre = cfg["nombre"]
    modo = cfg.get("modo", "anadir")
    if modo not in ("anadir", "espejo"):
        raise ErrorImmich(f"«{nombre}»: modo «{modo}» no válido (anadir | espejo)")
    personas = [p["id"] for p in cfg["personas"]]
    if not personas:
        raise ErrorImmich(f"«{nombre}»: sin personas")

    # Validar personas (y que la clave es del usuario correcto) antes de tocar nada.
    nombres = []
    for p in cfg["personas"]:
        real = api.persona(p["id"]).get("name") or "(sin nombre)"
        if p.get("nombre") and real.strip() != p["nombre"].strip():
            log(f"  aviso: la persona {p['id']} se llama «{real}» en Immich, no «{p['nombre']}»")
        nombres.append(real.strip())
    log(f"«{nombre}» [{modo}] ← {' + '.join(nombres)}"
        f"{' (todas juntas)' if cfg.get('requiere_todas') else ''}")

    deseados = api.assets_de_personas(personas, bool(cfg.get("requiere_todas")))
    if not deseados:
        # Una búsqueda vacía nunca debe vaciar un álbum: se para aquí.
        raise ErrorImmich(f"«{nombre}»: la búsqueda no devuelve nada; no se toca el álbum")

    album_id = resolver_album(api, nombre, estado, simular)
    actuales = api.assets_del_album(album_id) if album_id else set()
    faltan = sorted(deseados - actuales)
    sobran = sorted(actuales - deseados) if modo == "espejo" else []
    log(f"  personas: {len(deseados)} · álbum: {len(actuales)} · "
        f"añadir: {len(faltan)} · quitar: {len(sobran)}")

    if sobran and actuales and len(sobran) / len(actuales) > MAX_FRACCION_A_QUITAR:
        log(f"  FRENO: quitar {len(sobran)} de {len(actuales)} supera el "
            f"{MAX_FRACCION_A_QUITAR:.0%}; no se quita nada en esta pasada. Revisar.")
        sobran = []

    if simular:
        log("  [simulación] no se escribe nada")
        return
    if faltan:
        log(f"  añadidos: {api.anadir(album_id, faltan)}")
    if sobran:
        log(f"  quitados: {api.quitar(album_id, sobran)}")


def pasada(api: Immich, config: dict, ruta_estado: Path, simular: bool) -> bool:
    estado = leer_estado(ruta_estado)
    ok = True
    for cfg in config.get("albumes", []):
        if cfg.get("activo", True) is False:
            continue
        try:
            sincronizar_album(api, cfg, estado, simular)
        except (ErrorImmich, KeyError) as e:
            ok = False
            log(f"ERROR en «{cfg.get('nombre', '?')}»: {e}")
    if not simular:
        estado["ultima_pasada"] = datetime.now().isoformat(timespec="seconds")
        estado["ultima_pasada_ok"] = ok
        guardar_estado(ruta_estado, estado)
    log(f"pasada terminada: {'OK' if ok else 'CON ERRORES'}")
    return ok


def segundos_hasta(hora: str) -> float:
    hh, mm = (int(x) for x in hora.split(":"))
    ahora = datetime.now()
    objetivo = ahora.replace(hour=hh, minute=mm, second=0, microsecond=0)
    if objetivo <= ahora:
        objetivo += timedelta(days=1)
    return (objetivo - ahora).total_seconds()


def main() -> int:
    ap = argparse.ArgumentParser(description="Álbumes automáticos por persona para Immich")
    ap.add_argument("--una-vez", action="store_true", help="una pasada y salir")
    ap.add_argument("--simular", action="store_true", help="no escribir nada (implica --una-vez)")
    args = ap.parse_args()

    url = os.environ.get("IMMICH_URL", "http://immich_server:2283")
    clave = os.environ.get("IMMICH_API_KEY", "").strip()
    if not clave:
        log("ERROR: falta IMMICH_API_KEY")
        return 2
    config = json.loads(Path(os.environ.get("CONFIG", "/config/config.json")).read_text())
    ruta_estado = Path(os.environ.get("ESTADO", "/estado/estado.json"))
    hora = os.environ.get("HORA") or config.get("hora", "04:00")
    api = Immich(url, clave)

    if args.simular or args.una_vez:
        return 0 if pasada(api, config, ruta_estado, args.simular) else 1

    log(f"auto-albums en marcha: {len(config.get('albumes', []))} álbum(es), cada día a las {hora}")
    if os.environ.get("EJECUTAR_AL_ARRANCAR", "1") == "1":
        pasada(api, config, ruta_estado, False)
    while True:
        espera = segundos_hasta(hora)
        log(f"próxima pasada en {espera / 3600:.1f} h")
        time.sleep(espera)
        try:
            # Se relee la config en cada pasada: cambiarla no exige reiniciar.
            config = json.loads(Path(os.environ.get("CONFIG", "/config/config.json")).read_text())
            pasada(api, config, ruta_estado, False)
        except Exception as e:  # el bucle no debe morir por un fallo puntual
            log(f"ERROR inesperado: {e!r}")


if __name__ == "__main__":
    sys.exit(main())
