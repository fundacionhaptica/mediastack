"""Pruebas de auto_albums.py contra un Immich simulado (sin red, solo stdlib).

    python -m unittest test_auto_albums.py -v
"""
import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory

import auto_albums as aa

P1, P2 = "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"
P3 = "33333333-3333-4333-8333-333333333333"      # persona de la segunda cuenta
CLAVES = {"k": "u1", "k2": "u2"}                 # clave de API -> usuario


class Falso:
    """Estado del Immich simulado."""
    def __init__(self):
        # persona -> (dueño, nombre). En Immich el id de persona es por usuario.
        self.personas = {P1: ("u1", "Padre"), P2: ("u1", "Madre"), P3: ("u2", "")}
        # asset -> personas que salen; dueño de cada asset
        self.assets = {f"a{i}": set() for i in range(2500)}
        self.dueno = {a: "u1" for a in self.assets}
        for i in range(0, 1200):
            self.assets[f"a{i}"].add(P1)
        for i in range(1000, 2100):
            self.assets[f"a{i}"].add(P2)
        for i in range(300):                       # fotos de la segunda cuenta
            self.assets[f"b{i}"] = {P3} if i < 250 else set()
            self.dueno[f"b{i}"] = "u2"
        self.albumes = {}   # id -> {"albumName", "assets": set(), "usuarios": set()}
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
            yo = CLAVES.get(self.headers.get("x-api-key"))
            if not yo:
                return self._resp(401, {"message": "Invalid API key"})
            c = self._cuerpo()
            p = self.path

            def ve(aid):
                al = f.albumes.get(aid)
                return al is not None and yo in al["usuarios"]

            if metodo == "GET" and p == "/api/users/me":
                return self._resp(200, {"id": yo})
            if metodo == "GET" and p.startswith("/api/people/"):
                pid = p.rsplit("/", 1)[1]
                if pid in f.personas and f.personas[pid][0] == yo:
                    return self._resp(200, {"id": pid, "name": f.personas[pid][1]})
                return self._resp(400, {"message": "Not found"})
            if metodo == "GET" and p == "/api/albums":
                return self._resp(200, [{"id": k, "albumName": v["albumName"]}
                                        for k, v in f.albumes.items() if yo in v["usuarios"]])
            if metodo == "GET" and p.startswith("/api/albums/"):
                aid = p.rsplit("/", 1)[1]
                return self._resp(200, {"id": aid}) if ve(aid) else self._resp(400, {"message": "x"})
            if metodo == "POST" and p == "/api/albums":
                aid = f"album{len(f.albumes) + 1}"
                f.albumes[aid] = {"albumName": c["albumName"], "assets": set(), "usuarios": {yo}, "dueno": yo}
                return self._resp(201, {"id": aid})
            if metodo == "POST" and p == "/api/search/metadata":
                assert "page" not in c and "personIds" not in c, "forma antigua"
                filt = c["filter"]
                assert filt.get("visibility") == {"in": ["timeline", "archive"]}
                # Como Immich v3.3.5 (comprobado en el NAS el 2026-11-04): por persona,
                # solo assets propios; dentro de un álbum, los de TODOS sus miembros.
                if "personIds" in filt:
                    pf = filt["personIds"]
                    if "any" in pf:
                        ids = [a for a, ps in f.assets.items() if ps & set(pf["any"])]
                    else:
                        ids = [a for a, ps in f.assets.items() if set(pf["all"]) <= ps]
                    ids = [a for a in ids if f.dueno[a] == yo]
                else:
                    aid = filt["albumIds"]["any"][0]
                    if not ve(aid):
                        return self._resp(400, {"message": "Not found or no album.read access"})
                    ids = f.albumes[aid]["assets"]
                ids = sorted(ids)
                ini = int(c.get("cursor") or 0)
                trozo = ids[ini:ini + c["size"]]
                sig = str(ini + c["size"]) if ini + c["size"] < len(ids) else None
                return self._resp(200, {"albums": {}, "assets": {
                    "items": [{"id": i, "ownerId": f.dueno[i]} for i in trozo],
                    "count": len(trozo), "nextCursor": sig}})
            if p.startswith("/api/albums/") and p.endswith("/assets"):
                aid = p.split("/")[3]
                assert len(c["ids"]) <= aa.LOTE
                if not ve(aid):
                    return self._resp(400, {"message": "Not found or no access"})
                al = f.albumes[aid]["assets"]
                es_dueno = f.albumes[aid]["dueno"] == yo
                res = []
                for i in c["ids"]:
                    if metodo == "PUT":
                        # Solo se añaden fotos propias (permiso AssetShare).
                        okk = i not in al and f.dueno.get(i) == yo
                        res.append({"id": i, "success": okk})
                        if okk:
                            al.add(i)
                    else:
                        okk = i in al and (es_dueno or f.dueno.get(i) == yo)
                        res.append({"id": i, "success": okk})
                        if okk:
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
        self.f.albumes = {"x": {"albumName": "Papá y Mamá", "assets": set(), "usuarios": {"u1"}, "dueno": "u1"},
                          "y": {"albumName": "Papá y Mamá", "assets": set(), "usuarios": {"u1"}, "dueno": "u1"}}
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))

    # --- otras cuentas (fotos de otro usuario en el mismo álbum) -------------------
    def con_otra_cuenta(self, **extra):
        os.environ["IMMICH_API_KEY_OTRA"] = "k2"
        self.addCleanup(os.environ.pop, "IMMICH_API_KEY_OTRA", None)
        otra = {"cuenta": "Otra", "clave_env": "IMMICH_API_KEY_OTRA",
                "personas": [{"id": P3, "nombre": "Nieto"}, {"id": P1, "opcional": True}]}
        otra.update(extra)
        self.cfg["albumes"][0]["otras_cuentas"] = [otra]

    def compartir(self):
        (aid,) = self.f.albumes
        self.f.albumes[aid]["usuarios"].add("u2")

    def test_otra_cuenta_anade_sus_fotos(self):
        self.con_otra_cuenta()
        aa.pasada(self.api, self.cfg, self.estado, False)  # crea el álbum (sin compartir aún)
        self.compartir()
        self.assertTrue(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(len(self.album()), 2100 + 250)
        self.assertIn("b0", self.album())

    def test_espejo_principal_no_quita_fotos_de_otra_cuenta(self):
        self.con_otra_cuenta()
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.compartir()
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.album().add("b299")              # añadida a mano por la otra cuenta
        self.cfg["albumes"][0]["otras_cuentas"][0]["activo"] = False
        self.assertTrue(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(len(self.album()), 2100 + 251)  # espejo de u1 ve lo de u2 pero no lo quita

    def test_freno_cuenta_solo_las_propias(self):
        # 2100 propias + 2000 ajenas: quitar 1500 propias supera la mitad de las propias
        # aunque no la del álbum entero, y el freno tiene que saltar.
        self.con_otra_cuenta()
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.compartir()
        for i in range(2000):
            self.f.dueno[f"c{i}"] = "u2"
            self.f.assets[f"c{i}"] = set()
            self.album().add(f"c{i}")
        for i in range(0, 1500):
            self.f.assets[f"a{i}"].clear()
        self.cfg["albumes"][0]["otras_cuentas"][0]["activo"] = False
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertEqual(len(self.album()), 2100 + 2000)

    def test_espejo_sin_user_read_no_toca(self):
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.album().add("a2400")
        self.api.yo = lambda: (_ for _ in ()).throw(aa.ErrorImmich("GET /api/users/me → HTTP 403"))
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertIn("a2400", self.album())

    def test_otra_cuenta_en_modo_anadir_no_quita(self):
        self.con_otra_cuenta()
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.compartir()
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.f.assets["b0"].clear()           # cara corregida en la otra cuenta
        aa.pasada(self.api, self.cfg, self.estado, False)
        self.assertIn("b0", self.album())

    def test_otra_cuenta_sin_acceso_al_album_falla_sin_tocar(self):
        self.con_otra_cuenta()
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(len(self.album()), 2100)  # lo de la cuenta principal sí se hace
        self.assertNotIn("b0", self.album())

    def test_otra_cuenta_sin_clave_no_impide_la_principal(self):
        self.con_otra_cuenta(clave_env="IMMICH_API_KEY_NO_EXISTE")
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(len(self.album()), 2100)

    def test_otra_cuenta_inactiva_se_salta(self):
        self.con_otra_cuenta(activo=False, clave_env="IMMICH_API_KEY_NO_EXISTE")
        self.assertTrue(aa.pasada(self.api, self.cfg, self.estado, False))

    def test_persona_opcional_inexistente_se_salta(self):
        self.cfg["albumes"][0]["personas"].append({"id": P3, "opcional": True})
        self.assertTrue(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(len(self.album()), 2100)

    def test_solo_opcionales_inexistentes_es_error(self):
        self.cfg["albumes"][0]["personas"] = [{"id": P3, "opcional": True}]
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(self.f.albumes, {})

    def test_opcional_con_requiere_todas_es_error(self):
        self.cfg["albumes"][0]["requiere_todas"] = True
        self.cfg["albumes"][0]["personas"].append({"id": P3, "opcional": True})
        self.assertFalse(aa.pasada(self.api, self.cfg, self.estado, False))
        self.assertEqual(self.f.albumes, {})


if __name__ == "__main__":
    unittest.main()
