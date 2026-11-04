#!/usr/bin/env python3
"""
auto-albums — álbumes de Immich que se rellenan solos a partir de personas reconocidas.

Immich (v3.3) no tiene "álbumes automáticos por persona": sus Workflows saben añadir a un
álbum, pero no filtrar por cara. Este script lo suple con la API pública:

  1. Para cada álbum de config.json, busca todas las fotos/vídeos en los que sale
     cualquiera de sus personas (POST /api/search/metadata, filtro personIds.any).
  2. Añade al álbum lo que falte (PUT /api/albums/{id}/assets).
  3. En modo "espejo", quita del álbum lo que ya no corresponde
     (DELETE /api/albums/{id}/assets) — p. ej. tras corregir una cara mal asignada.
     Solo quita fotos de las que es dueño el usuario de la clave: la búsqueda por álbum
     devuelve las de todos los miembros, y las de otro usuario no son asunto suyo.
  4. Con "otras_cuentas", repite 1-3 con la clave de otro usuario con quien el álbum está
     compartido como editor, para que entren también SUS fotos (Immich solo deja añadir
     a un álbum fotos propias).

Sin dependencias: solo la biblioteca estándar de Python 3.10+.

Uso:
  python auto_albums.py              # bucle: sincroniza al arrancar y cada día a HORA
  python auto_albums.py --una-vez    # una pasada y sale
  python auto_albums.py --simular    # una pasada sin escribir nada en Immich

Variables de entorno:
  IMMICH_URL        p. ej. http://immich_server:2283
  IMMICH_API_KEY    clave de API del usuario dueño de las personas y de los álbumes
  IMMICH_API_KEY_*  claves de otras cuentas, con el nombre que diga "clave_env" en config.json
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
        self._yo: str | None = None

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
    def buscar(self, filtro: dict) -> dict[str, str]:
        """{id de asset: id del dueño} de todo lo que cumple el filtro (forma nueva de
        v3.2+, con cursor)."""
        ids: dict[str, str] = {}
        cursor = None
        while True:
            cuerpo = {"filter": filtro, "size": PAGINA, "withExif": False}
            if cursor:
                cuerpo["cursor"] = cursor
            r = self._peticion("POST", "/api/search/metadata", cuerpo)
            assets = (r or {}).get("assets") or {}
            for a in assets.get("items", []):
                ids[a["id"]] = a.get("ownerId", "")
            cursor = assets.get("nextCursor")
            if not cursor:
                return ids

    def assets_de_personas(self, personas: list[str], todas: bool) -> set[str]:
        clave = "all" if todas else "any"
        return set(self.buscar(
            {"personIds": {clave: personas}, "visibility": {"in": VISIBILIDADES}}
        ))

    def assets_del_album(self, album_id: str) -> dict[str, str]:
        """{asset: dueño} del álbum. OJO: Immich (v3.3.5) devuelve las fotos de TODOS los
        miembros del álbum, no solo las de la clave (comprobado el 2026-11-04)."""
        # Mismo filtro de visibilidad que en las personas, para comparar like con like.
        return self.buscar({"albumIds": {"any": [album_id]}, "visibility": {"in": VISIBILIDADES}})

    def yo(self) -> str:
        """Id del usuario de la clave (GET /api/users/me, permiso user.read)."""
        if self._yo is None:
            self._yo = self._peticion("GET", "/api/users/me")["id"]
        return self._yo

    # --- personas y álbumes ----------------------------------------------------
    def persona(self, persona_id: str) -> dict:
        return self._peticion("GET", f"/api/people/{persona_id}")

    def persona_o_nada(self, persona_id: str) -> dict | None:
        try:
            return self.persona(persona_id)
        except ErrorImmich as e:
            if "HTTP 400" in str(e) or "HTTP 404" in str(e):
                return None
            raise

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


def validar_personas(api: Immich, nombre: str, personas_cfg: list[dict]) -> tuple[list[str], list[str]]:
    """Ids y nombres de las personas que existen para esta clave, antes de tocar nada.
    Una persona obligatoria que no existe para la clave es un error (clave equivocada, id
    mal copiado). Una "opcional" se salta: sirve para poner los ids de las dos cuentas en
    las dos fuentes, porque con el grupo de reconocimiento compartido una foto nueva puede
    quedar bajo el id de la otra cuenta."""
    ids, nombres = [], []
    for p in personas_cfg:
        datos = api.persona_o_nada(p["id"]) if p.get("opcional") else api.persona(p["id"])
        if datos is None:
            continue
        real = (datos.get("name") or "").strip()
        if p.get("nombre") and real and real != p["nombre"].strip():
            log(f"  aviso: la persona {p['id']} se llama «{real}» en Immich, no «{p['nombre']}»")
        ids.append(p["id"])
        nombres.append(real or f"{p.get('nombre') or p['id']} (sin nombre en Immich)")
    if not ids:
        raise ErrorImmich(f"«{nombre}»: ninguna de sus personas existe para esta clave")
    return ids, nombres


def aplicar(api: Immich, album_id: str | None, modo: str, deseados: set[str], simular: bool) -> None:
    """Deja en el álbum lo que pide `deseados`. En espejo solo se quitan fotos cuyo dueño
    es el usuario de la clave: las que han puesto otros miembros no se tocan nunca."""
    actuales = api.assets_del_album(album_id) if album_id else {}
    faltan = sorted(deseados - set(actuales))
    propios: set[str] = set()
    if modo == "espejo" and actuales:
        yo = api.yo()  # antes de escribir nada: sin user.read, error y no se toca el álbum
        propios = {a for a, dueno in actuales.items() if dueno == yo}
    sobran = sorted(propios - deseados)
    log(f"  personas: {len(deseados)} · álbum: {len(actuales)}"
        f"{f' (propias: {len(propios)})' if modo == 'espejo' else ''} · "
        f"añadir: {len(faltan)} · quitar: {len(sobran)}")

    if sobran and len(sobran) / len(propios) > MAX_FRACCION_A_QUITAR:
        log(f"  FRENO: quitar {len(sobran)} de {len(propios)} supera el "
            f"{MAX_FRACCION_A_QUITAR:.0%}; no se quita nada en esta pasada. Revisar.")
        sobran = []

    if simular:
        log("  [simulación] no se escribe nada")
        return
    if faltan:
        hechos = api.anadir(album_id, faltan)
        log(f"  añadidos: {hechos}")
        if hechos < len(faltan):
            log(f"  aviso: {len(faltan) - hechos} no se pudieron añadir (¿fotos de otra cuenta?)")
    if sobran:
        log(f"  quitados: {api.quitar(album_id, sobran)}")


def comprobar_modo(nombre: str, modo: str) -> None:
    if modo not in ("anadir", "espejo"):
        raise ErrorImmich(f"«{nombre}»: modo «{modo}» no válido (anadir | espejo)")


def sincronizar_album(api: Immich, cfg: dict, estado: dict, simular: bool) -> bool:
    """Sincroniza el álbum con la clave principal y luego con cada una de "otras_cuentas".
    Devuelve False si falló alguna otra cuenta (la principal falla con excepción)."""
    nombre = cfg["nombre"]
    modo = cfg.get("modo", "anadir")
    comprobar_modo(nombre, modo)
    if not cfg.get("personas"):
        raise ErrorImmich(f"«{nombre}»: sin personas")
    if cfg.get("requiere_todas") and any(
            p.get("opcional") for p in cfg["personas"] + [x for o in cfg.get("otras_cuentas", [])
                                                         for x in o.get("personas", [])]):
        # Saltarse una persona cambiaría qué fotos cumplen "todas a la vez".
        raise ErrorImmich(f"«{nombre}»: \"opcional\" no vale con \"requiere_todas\"")

    personas, nombres = validar_personas(api, nombre, cfg["personas"])
    log(f"«{nombre}» [{modo}] ← {' + '.join(nombres)}"
        f"{' (todas juntas)' if cfg.get('requiere_todas') else ''}")

    deseados = api.assets_de_personas(personas, bool(cfg.get("requiere_todas")))
    if not deseados:
        # Una búsqueda vacía nunca debe vaciar un álbum: se para aquí.
        raise ErrorImmich(f"«{nombre}»: la búsqueda no devuelve nada; no se toca el álbum")

    album_id = resolver_album(api, nombre, estado, simular)
    aplicar(api, album_id, modo, deseados, simular)

    ok = True
    for otra in cfg.get("otras_cuentas", []):
        if otra.get("activo", True) is False:
            continue
        try:
            sincronizar_otra_cuenta(api.url, nombre, album_id, otra, bool(cfg.get("requiere_todas")), simular)
        except (ErrorImmich, KeyError) as e:
            ok = False
            log(f"ERROR en «{nombre}», cuenta «{otra.get('cuenta', '?')}»: {e}")
    return ok


def sincronizar_otra_cuenta(url: str, nombre: str, album_id: str | None, otra: dict,
                            todas: bool, simular: bool) -> None:
    """Añade al álbum (de la clave principal) las fotos de otra cuenta, con su propia clave.
    El álbum tiene que estar compartido con esa cuenta como editor. Por defecto en modo
    "anadir": nunca quita nada."""
    cuenta = otra["cuenta"]
    modo = otra.get("modo", "anadir")
    comprobar_modo(nombre, modo)
    clave = os.environ.get(otra["clave_env"], "").strip()
    if not clave:
        raise ErrorImmich(f"falta la variable {otra['clave_env']} en .env")
    if album_id is None:
        log(f"  [simulación] cuenta «{cuenta}»: el álbum aún no existe, se salta")
        return
    api = Immich(url, clave)
    if not api.album(album_id):
        raise ErrorImmich("esa cuenta no ve el álbum: compártelo con ella como editora")
    personas, nombres = validar_personas(api, f"{nombre}/{cuenta}", otra.get("personas", []))
    log(f"  cuenta «{cuenta}» [{modo}] ← {' + '.join(nombres)}")
    deseados = api.assets_de_personas(personas, todas)
    if not deseados and modo == "espejo":
        raise ErrorImmich("la búsqueda no devuelve nada; no se toca el álbum")
    aplicar(api, album_id, modo, deseados, simular)


def pasada(api: Immich, config: dict, ruta_estado: Path, simular: bool) -> bool:
    estado = leer_estado(ruta_estado)
    ok = True
    for cfg in config.get("albumes", []):
        if cfg.get("activo", True) is False:
            continue
        try:
            if not sincronizar_album(api, cfg, estado, simular):
                ok = False
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
