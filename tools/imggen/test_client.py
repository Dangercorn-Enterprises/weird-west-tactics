import json
import urllib.request

BASE = "http://localhost:8710"


def health():
    return json.load(urllib.request.urlopen(BASE + "/health", timeout=15))


def gen(spec):
    req = urllib.request.Request(
        BASE + "/generate", data=json.dumps(spec).encode(),
        headers={"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=600))
    b = d.get("artifacts", [{}])[0].get("base64", "")
    return d.get("meta"), len(b)


print("health before:", health())
m1, n1 = gen({"prompt": "a dusty saloon at golden hour", "profile": "concept", "width": 768, "height": 768, "seed": 3})
print("job1 concept:", m1, "| png b64 len", n1)
hb = health()
print("health BETWEEN jobs:", hb)
m2, n2 = gen({"prompt": "a coiled rattlesnake", "profile": "pixel", "width": 1024, "height": 1024, "seed": 5})
print("job2 pixel:", m2, "| png b64 len", n2)
print("health after:", health())

# verdict: worker-exit VRAM residual (meta.vram_after_mib) should be ~memory-engine
# baseline (a few hundred MiB), NOT +548 image context accumulating.
print("\nVRAM after job1:", m1.get("vram_after_mib"), "MiB | after job2:", m2.get("vram_after_mib"), "MiB")
print("VERDICT:", "CLEAN (no image-context accumulation)" if m1.get("vram_after_mib") < 700 and m2.get("vram_after_mib") < 700 else "LEAK")
