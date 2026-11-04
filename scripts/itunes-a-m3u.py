#!/usr/bin/env python3
"""
itunes-a-m3u.py — Convierte las playlists de una biblioteca de iTunes exportada
(Archivo → Biblioteca → Exportar biblioteca…, fichero .xml) en ficheros .m3u que
Navidrome importa solo.

Uso (en el NAS; /volume1/music montado en /music, datos de Navidrome en /nd):

    docker run --rm --user 1026:100 --group-add 101 \
      -v /volume1/music:/music \
      -v /volume1/docker/mediastack-data/navidrome:/nd:ro \
      -v /volume1/docker/mediastack/scripts:/s:ro \
      python:3.12-alpine python /s/itunes-a-m3u.py \
        /music/iTunes/Biblioteca.xml /music/Playlists [--dry-run]

Cómo encuentra cada canción:
  1. Si la pista tiene fichero local (clave Location), traduce la ruta de Windows
     (…/iTunes Media/…) a /music/iTunes/… y, si no está, busca por la cola de la ruta.
  2. Si no lo tiene (pistas de Apple Music / iCloud, "Track Type" = Remote), la busca
     por artista + título en la base de datos de Navidrome (se lee una COPIA, nunca la
     original). Se normaliza: minúsculas, sin tildes, sin "(…)", "[…]", "feat." ni
     número de pista delante.
  Lo que no encuentra va a <salida>/_faltan.txt, por lista.

Notas:
  - Salta listas de sistema (Biblioteca, Música, Podcasts…) y carpetas. Las listas
    inteligentes se exportan como foto fija.
  - Escribe rutas RELATIVAS al .m3u. Reescribe sus .m3u en cada ejecución; no borra
    ningún otro fichero. Las listas sin ninguna canción encontrada no se crean.
  - Navidrome importa los .m3u en su escaneo (programado a las 04:00, o "Escanear").
"""
import os
import plistlib
import re
import shutil
import sqlite3
import sys
import tempfile
import unicodedata
from urllib.parse import unquote, urlparse

SISTEMA = ("Master", "Distinguished Kind", "Folder", "Movies", "TV Shows",
           "Podcasts", "Audiobooks", "Music", "Purchased Music")
RAIZ = "/music"
DB_NAVIDROME = "/nd/navidrome.db"


def nfc(s):
    return unicodedata.normalize("NFC", s)


def clave(s):
    """Normaliza un artista o título para comparar."""
    s = unicodedata.normalize("NFKD", (s or "").lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"\(.*?\)|\[.*?\]|feat\..*|^\d+\s+", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def nombre_fichero(nombre):
    limpio = re.sub(r'[\\/:*?"<>|]', "_", nombre).strip().rstrip(".")
    return limpio or "sin_nombre"


def indice_navidrome():
    """{(artista, título) normalizados: ruta absoluta} a partir de una copia de la BD."""
    if not os.path.exists(DB_NAVIDROME):
        return {}
    tmp = os.path.join(tempfile.mkdtemp(), "n.db")
    shutil.copy(DB_NAVIDROME, tmp)
    idx = {}
    con = sqlite3.connect(tmp)
    for titulo, artista, ruta in con.execute("select title, artist, path from media_file"):
        abs_ = ruta if ruta.startswith("/") else os.path.join(RAIZ, ruta)
        idx.setdefault((clave(artista), clave(titulo)), abs_)
    con.close()
    return idx


def indice_por_cola(raiz):
    idx = {}
    for d, _, fs in os.walk(raiz):
        if "@eaDir" in d or "#recycle" in d:
            continue
        for f in fs:
            p = os.path.join(d, f)
            partes = nfc(p).lower().split(os.sep)
            for n in (3, 2):
                idx.setdefault(tuple(partes[-n:]), p)
    return idx


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 2:
        sys.exit(__doc__)
    xml, salida = args

    with open(xml, "rb") as fh:
        lib = plistlib.load(fh)
    pistas = lib.get("Tracks", {})
    nav = indice_navidrome()
    cola = None

    def resolver(t):
        nonlocal cola
        loc = t.get("Location")
        if loc:
            ruta_win = nfc(unquote(urlparse(loc).path))
            m = re.search(r"/iTunes( Media)?/(.*)$", ruta_win, re.I)
            if m:
                cand = os.path.join(RAIZ, "iTunes", m.group(2))
                if os.path.exists(cand):
                    return cand
            if cola is None:
                cola = indice_por_cola(RAIZ)
            partes = ruta_win.lower().split("/")
            for n in (3, 2):
                if tuple(partes[-n:]) in cola:
                    return cola[tuple(partes[-n:])]
        return nav.get((clave(t.get("Artist")), clave(t.get("Name"))))

    if not dry:
        os.makedirs(salida, exist_ok=True)

    escritas = resueltas = total = 0
    faltan = []
    for pl in lib.get("Playlists", []):
        if any(pl.get(k) for k in SISTEMA):
            continue
        nombre = pl.get("Name", "sin nombre").strip()
        items = [pistas.get(str(i.get("Track ID"))) for i in pl.get("Playlist Items", [])]
        items = [t for t in items if t]
        if not items:
            continue
        lineas, falta_aqui = [], []
        for t in items:
            p = resolver(t)
            if p:
                lineas.append(os.path.relpath(p, salida))
            else:
                falta_aqui.append(f"{t.get('Artist', '?')} - {t.get('Name', '?')}")
        total += len(items)
        resueltas += len(lineas)
        print(f"  {len(lineas):4d}/{len(items):4d}  {nombre}")
        if falta_aqui:
            faltan.append((nombre, falta_aqui))
        if lineas and not dry:
            escritas += 1
            with open(os.path.join(salida, nombre_fichero(nombre) + ".m3u"), "w", encoding="utf-8") as fh:
                fh.write("#EXTM3U\n#PLAYLIST:" + nombre + "\n" + "\n".join(lineas) + "\n")

    if faltan and not dry:
        with open(os.path.join(salida, "_faltan.txt"), "w", encoding="utf-8") as fh:
            fh.write("Canciones de las playlists de iTunes que no están en el NAS\n\n")
            for nombre, lista in faltan:
                fh.write(f"== {nombre} ({len(lista)})\n" + "\n".join(lista) + "\n\n")

    print(f"\nListas escritas: {escritas}  canciones encontradas: {resueltas} de {total}"
          f"  {'(prueba en seco: no se ha escrito nada)' if dry else ''}")


if __name__ == "__main__":
    main()
