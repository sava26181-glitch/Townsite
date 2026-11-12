"""Скачивает фотореалистичные CC0-ассеты с Poly Haven (без аккаунта):
текстуры асфальта/бетона/травы и 3D-модели (дерево, скамейка, урна).
Запускается в GitHub Actions перед сборкой. Ошибки не роняют сборку."""
import json, os, sys, urllib.request

UA = {"User-Agent": "EmpireCity-build/1.0"}
API = "https://api.polyhaven.com"


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def jget(url):
    return json.loads(get(url))


EXCLUDE = ("work", "cabinet", "robin", "bobbin", "kitchen", "table")


def pick(assets, words, prefer_cats=()):
    best, score = None, -1
    for aid, a in assets.items():
        if any(x in aid.lower() for x in EXCLUDE):
            continue
        cats = [c.lower() for c in a.get("categories", [])]
        name = aid.lower()
        if not any(w in name or w in cats for w in words):
            continue
        s = a.get("download_count", 0)
        if any(c in cats for c in prefer_cats):
            s *= 2
        if s > score:
            best, score = aid, s
    return best


def fetch_texture(slot, words):
    tex = jget(f"{API}/assets?t=textures")
    aid = pick(tex, words)
    if not aid:
        print("no texture for", slot); return
    files = jget(f"{API}/files/{aid}")
    os.makedirs("assets/tex", exist_ok=True)
    maps = {"diff": ["Diffuse", "diffuse", "diff"], "nor": ["nor_gl", "Normal"], "rough": ["Rough", "rough", "Roughness"]}
    for kind, keys in maps.items():
        for k in keys:
            try:
                url = files[k]["1k"]["jpg"]["url"]
            except Exception:
                continue
            data = get(url)
            open(f"assets/tex/{slot}_{kind}.jpgdata", "wb").write(data)
            print("ok", slot, kind, aid, len(data))
            break


def fetch_model(slot, words):
    models = jget(f"{API}/assets?t=models")
    aid = pick(models, words)
    if not aid:
        print("no model for", slot); return
    files = jget(f"{API}/files/{aid}")
    try:
        g = files["gltf"]["1k"]["gltf"]
    except Exception:
        print("no gltf for", aid); return
    out = f"assets/props/{slot}"
    os.makedirs(out, exist_ok=True)
    open(f"{out}/{slot}.gltf", "wb").write(get(g["url"]))
    for rel, inc in g.get("include", {}).items():
        p = os.path.join(out, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(get(inc["url"]))
    # переименованный gltf ссылается на те же относительные пути — ок
    print("ok model", slot, aid)


jobs = [
    (fetch_texture, "asphalt", ["asphalt"]),
    (fetch_texture, "concrete", ["concrete_floor", "concrete_pavement", "concrete"]),
    (fetch_texture, "grass", ["grass"]),
    (fetch_model, "bench", ["bench"]),
    (fetch_model, "bin", ["trash_can", "trashcan", "dustbin", "garbage_can"]),
]
for fn, slot, words in jobs:
    try:
        fn(slot, words)
    except Exception as e:
        print("skip", slot, e)
