"""Pruebas de auto_albums.py contra un Immich simulado (sin red, solo stdlib).

    python -m unittest test_auto_albums.py -v
"""
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory

import auto_albums as aa

P1, P2 = "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"


class Falso:
    """Estado del Immich simulado."""
    def __init__(self):
        self.personas = {P1: "Padre", P2: "Madre"}
        # asset -> personas que salen
        self.assets = {f"a{i}": set() for i in range(2500)}
        for i in range(0, 1200):
            self.assets[f"a{i}"].add(P1)
        for i in range(1000, 2100):
            self.assets[f"a{i}"].add(P2)
        self.albumes = {}   # id -> {"albumName", "assets": set()}
        self.peticiones = []


def manejador(f: Falso):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _resp(self, code, obj):
            b = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def _cuerpo(self):
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n)) if n else None

        def _todo(self, metodo):
            f.peticiones.append((metodo, self.path))
            if self.headers.get("x-api-key") != "k":
                return self._resp(401, {"message": "Invalid API key"})
            c = self._cuerpo()
            p = self.path
            if metodo == "GET" and p.startswith("/api/people/"):
                pid = p.rsplit("/", 1)[1]
                return self._resp(200, {"id": pid, "name": f.personas[pid]}) if pid in f.personas \
                    else self._resp(400, {"message": "Not found"})
            if metodo == "GET" and p == "/api/albums":
                return self._resp(200, [{"id": k, "albumName": v["albumName"]} for k, v in f.albumes.items()])
            if metodo == "GET" and p.startswith("/api/albums/"):
                aid = p.rsplit("/", 1)[1]
                return self._resp(200, {"id": aid}) if aid in f.albumes else self._resp(400, {"message": "x"})
            if metodo == "POST" and p == "/api/albums":
                aid = f"album{len(f.albumes) + 1}"
                f.albumes[aid] = {"albumName": c["albumName"], "assets": set()}
                return self._resp(201, {"id": aid})
            if metodo == "POST" and p == "/api/search/metadata":
                assert "page" not in c and "personIds" not in c, "forma antigua"
                filt = c["filter"]
                assert filt.get("visibility") == {"in": ["timeline", "archive"]}
                if "personIds" in filt:
                    pf = filt["personIds"]
                    if "any" in pf:
                        ids = [a for a, ps in f.assets.items() if ps & set(pf["any"])]
                    else:
                        ids = [a for a, ps in f.assets.items() if set(pf["all"]) <= ps]
                else:
                    ids = sorted(f.albumes[filt["albumIds"]["any"][0]]["assets"])
                ids = sorted(ids)
                ini = int(c.get("cursor") or 0)
                trozo = ids[ini:ini + c["size"]]
                sig = str(ini + c["size"]) if ini + c["size"] < len(ids) else None
                return self._resp(200, {"albums": {}, "assets": {
                    "items": [{"id": i} for i in trozo], "count": len(trozo), "nextCursor": sig}})
            if p.startswith("/api/albums/") and p.endswith("/assets"):
                aid = p.split("/")[3]
                assert len(c["ids"]) <= aa.LOTE
                al = f.albumes[aid]["assets"]
                res = []
                for i in c["ids"]:
                    if metodo == "PUT":
                        res.append({"id": i, "success": i not in al})
                        al.add(i)
                    else:
                        res.append({"id": i, "success": i in al})
                        al.discard(i)
                return self._resp(200, res)
            return self._resp(404, {"message": "ruta no simulada"})

        def do_GET(self): self._todo("GET")
        def do_POST(self): self._todo("POST")
        def do_PUT(self): self._todo("PUT")
        def do_DELETE(self): self._todo("DELETE")
    return H


class Pruebas(unittest.TestCase):
    def setUp(self):
        self.f = Falso()
        self.srv = HTTPServer(("127.0.0.1", 0), manejador(self.f))
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.api = aa.Immich(f"http://127.0.0.1:{self.srv.server_port}", "k")
        self.tmp = TemporaryDirectory()
        self.estado = Path(self.tmp.name) / "estado.json"
        self.cfg = {"albumes": [{"nombre": "Papá y Mamá", "modo": "espejo", "personas": [
            {"id": P1, "nombre": "Padre"}, {"id": P2, "nombre": "Madre"}]}]}

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()
        self.tmp.cleanup()

    def album(self):
        (aid,) = self.f.albumes
        return self.f.albumes[aid]["assets"]

    def test_crea_y_rellena_con_paginacion(self):
        self.assertTrue(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(len(self.album()), 2100)  # a0..a2099 (cualquiera de los dos)
        self.assertEqual(json.loads(self.estado.read_text())["albumes"]["Papá y Mamá"], "album1")

    def test_segunda_pasada_no_escribe(self):
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.f.peticiones.clear()
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertFalse([p for p in self.f.peticiones if p[0] in ("PUT", "DELETE", "POST")
                          and "search" not in p[1]])

    def test_espejo_quita_cara_corregida_y_lo_manual(self):
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.f.assets["a5"].discard(P1)       # cara corregida
        self.album().add("a2400")             # añadida a mano
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertNotIn("a5", self.album())
        self.assertNotIn("a2400", self.album())
        self.assertEqual(len(self.album()), 2099)

    def test_modo_anadir_no_quita(self):
        self.cfg["albumes"][0]["modo"] = "anadir"
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.album().add("a2400")
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertIn("a2400", self.album())

    def test_requiere_todas(self):
        self.cfg["albumes"][0]["requiere_todas"] = True
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertEqual(len(self.album()), 200)  # a1000..a1199

    def test_busqueda_vacia_no_vacia_el_album(self):
        aa.pasada(self.api, self.cfg, self.estado, False)
        for ps in self.f.assets.values():
            ps.clear()
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(len(self.album()), 2100)

    def test_freno_si_hay_que_quitar_mas_de_la_mitad(self):
        aa.pasada(self.api, self.cfg, self.estado, False)
        for i in range(0, 1500):
            self.f.assets[f"a{i}"].clear()
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertEqual(len(self.album()), 2100)

    def test_renombrado_en_immich_no_duplica(self):
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.f.albumes["album1"]["albumName"] = "Otro nombre"
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertEqual(len(self.f.albumes), 1)

    def test_simular_no_escribe(self):
        self.assertTrue(aa.pasada(self.api, self.cfg, self.estado, True))
        self.assertEqual(self.f.albumes, {})
        self.assertFalse(self.estado.exists())

    def test_clave_mala_falla_sin_tocar(self):
        mala = aa.Immich(self.api.url, "mala")
        self.assertFalse(aa.pasada(mala, self.cfg, self.estado, False))
        self.assertEqual(self.f.albumes, {})

    def test_persona_inexistente(self):
        self.cfg["albumes"][0]["personas"][0]["id"] = "33333333-3333-4333-8333-333333333333"
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(self.f.albumes, {})

    def test_dos_albumes_mismo_nombre(self):
        self.f.albumes = {"x": {"albumName": "Papá y Mamá", "assets": set()},
                          "y": {"albumName": "Papá y Mamá", "assets": set()}}
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))


if __name__ == "__main__":
    unittest.main()
