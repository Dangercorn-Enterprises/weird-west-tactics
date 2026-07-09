# =============================================================================
# forge-imggen SERVICE — Huginn on-demand image gen (forge item calder-016)
# Long-lived HTTP endpoint that holds NO CUDA context. Per request:
#   filelock (serialize image jobs) -> wait for GPU idle (never evict ollama/
#   memory-engine) -> spawn worker.py SUBPROCESS -> worker loads/gens/exits
#   (context dies, VRAM -> ~1 MiB) -> return the PNG as base64.
#
# Contract mirrors the old NIM endpoint so callers swap only the URL:
#   POST /generate  {prompt, profile?, width?, height?, seed?, style?}
#     -> 200 {"artifacts":[{"base64": "<png>"}], "meta": {...}}
#   GET  /health    -> {"ok":true,"gpu_used_mib":N,"busy":bool}
# Run: python serve.py   (listens 0.0.0.0:8710)
# =============================================================================
import base64
import json
import os
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from filelock import FileLock, Timeout

sys.path.insert(0, "/data/forge-imggen")
import imggen

HERE = "/data/forge-imggen"
PORT = 8710
LOCK = FileLock(imggen.LOCK_PATH)


def run_job(spec):
    """Serialize + gate + spawn a one-shot worker subprocess. Returns png bytes."""
    with LOCK.acquire(timeout=600):          # only one image job on the box at a time
        if not imggen.wait_for_gpu(max_wait=300):
            raise RuntimeError("GPU stayed busy (ollama/memory-engine resident) > 5 min")
        ts = int(time.time() * 1000)
        job = {
            "prompt": spec["prompt"], "profile": spec.get("profile", "concept"),
            "width": int(spec.get("width", 1024)), "height": int(spec.get("height", 1024)),
            "seed": int(spec.get("seed", 0)), "style": spec.get("style", True),
            "out": "%s/job_%d.png" % (HERE, ts),
        }
        jf = "%s/job_%d.json" % (HERE, ts)
        json.dump(job, open(jf, "w"))
        t0 = time.time()
        r = subprocess.run(
            [sys.executable, "%s/worker.py" % HERE, jf],
            capture_output=True, text=True, cwd=HERE, timeout=600,
        )
        if r.returncode != 0 or not os.path.exists(job["out"]):
            raise RuntimeError("worker failed rc=%s: %s" % (r.returncode, (r.stderr or "")[-800:]))
        data = open(job["out"], "rb").read()
        # worker process has exited -> context freed. record the proof.
        residual = imggen.gpu_used_mib()
        os.remove(jf)
        return data, {"gen_s": round(time.time() - t0, 1), "vram_after_mib": residual,
                      "profile": job["profile"], "size": [job["width"], job["height"]]}


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.startswith("/health"):
            busy, m, u = imggen.gpu_busy()
            self._send(200, {"ok": True, "gpu_used_mib": m, "gpu_util": u, "busy": busy})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self.path.startswith("/generate"):
            self._send(404, {"error": "not found"}); return
        try:
            n = int(self.headers.get("Content-Length", 0))
            spec = json.loads(self.rfile.read(n) or "{}")
            if not spec.get("prompt"):
                self._send(400, {"error": "prompt required"}); return
            data, meta = run_job(spec)
            self._send(200, {"artifacts": [{"base64": base64.b64encode(data).decode()}], "meta": meta})
        except Timeout:
            self._send(503, {"error": "another image job holds the GPU lock"})
        except Exception as e:
            self._send(500, {"error": str(e)[:800]})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("forge-imggen serving on 0.0.0.0:%d (worker-per-job, VRAM-clean)" % PORT, flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
