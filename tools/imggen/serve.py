# =============================================================================
# forge-imggen SERVICE + WEB PORTAL — Huginn on-demand image gen (calder-016)
# Long-lived HTTP service that holds NO CUDA context. Per generate request:
#   filelock (serialize) -> wait for GPU idle -> spawn worker.py SUBPROCESS ->
#   worker loads/gens/exits (context dies, VRAM -> ~baseline) -> save to gallery.
#
# Routes:
#   GET  /            -> the web portal (type prompt, see image, download)
#   POST /generate    -> {prompt, profile?, width?, height?, seed?} -> {artifacts:[{base64}], meta}
#   GET  /gallery     -> recent generations (JSON: file, meta, ts)
#   GET  /img/<name>  -> a saved PNG
#   GET  /health      -> {ok, gpu_used_mib, busy}
# Run: python serve.py   (0.0.0.0:8710)
# =============================================================================
import base64
import json
import os
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

from filelock import FileLock, Timeout

sys.path.insert(0, "/data/forge-imggen")
import imggen

HERE = "/data/forge-imggen"
GALLERY = HERE + "/gallery"
PORT = 8710
LOCK = FileLock(imggen.LOCK_PATH)
os.makedirs(GALLERY, exist_ok=True)


def run_job(spec):
    """Serialize + gate + spawn a one-shot worker. Returns (png_bytes, filename, meta)."""
    with LOCK.acquire(timeout=900):
        if not imggen.wait_for_gpu(max_wait=300):
            raise RuntimeError("GPU stayed busy (ollama/memory-engine) > 5 min")
        ts = int(time.time())
        prof = spec.get("profile", "concept")
        name = "%d_%s.png" % (ts, prof)
        out = "%s/%s" % (GALLERY, name)
        job = {"prompt": spec["prompt"], "profile": prof,
               "width": int(spec.get("width", 1024)), "height": int(spec.get("height", 1024)),
               "seed": int(spec.get("seed", 0)), "style": spec.get("style", True),
               "lora": (spec.get("lora") or None),
               "negative_prompt": (spec.get("negative_prompt") or None), "out": out}
        jf = "%s/.job_%d.json" % (HERE, ts)
        json.dump(job, open(jf, "w"))
        t0 = time.time()
        r = subprocess.run([sys.executable, "%s/worker.py" % HERE, jf],
                           capture_output=True, text=True, cwd=HERE, timeout=600)
        os.remove(jf)
        if r.returncode != 0 or not os.path.exists(out):
            raise RuntimeError("worker failed rc=%s: %s" % (r.returncode, (r.stderr or "")[-800:]))
        data = open(out, "rb").read()
        meta = {"gen_s": round(time.time() - t0, 1), "vram_after_mib": imggen.gpu_used_mib(),
                "profile": prof, "size": [job["width"], job["height"]], "prompt": spec["prompt"],
                "seed": job["seed"], "file": name, "ts": ts}
        json.dump(meta, open(out + ".json", "w"))
        return data, name, meta


def gallery_list(limit=40):
    items = []
    for f in sorted(os.listdir(GALLERY), reverse=True):
        if f.endswith(".png") and os.path.exists(GALLERY + "/" + f + ".json"):
            try:
                items.append(json.load(open(GALLERY + "/" + f + ".json")))
            except Exception:
                pass
        if len(items) >= limit:
            break
    return items


PAGE = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Forge ImgGen — Dangercorn</title>
<style>
:root{--bg:#14100a;--panel:#1e1810;--ink:#efe6d6;--brass:#d4a843;--teal:#4ecdc4;--dim:#8a7c66;--line:#2c2417}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,Segoe UI,sans-serif}
header{display:flex;align-items:center;gap:12px;padding:14px 20px;border-bottom:1px solid var(--line);background:var(--panel)}
header h1{font-size:18px;margin:0;letter-spacing:.5px}header h1 b{color:var(--brass)}
#dot{width:10px;height:10px;border-radius:50%;background:var(--dim)}#hstat{font-size:12px;color:var(--dim);margin-left:auto}
main{max-width:1080px;margin:0 auto;padding:20px;display:grid;grid-template-columns:340px 1fr;gap:20px}
@media(max-width:820px){main{grid-template-columns:1fr}}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px}
label{display:block;font-size:12px;color:var(--dim);margin:10px 0 4px;text-transform:uppercase;letter-spacing:.5px}
textarea,select,input{width:100%;background:#0f0c07;border:1px solid var(--line);color:var(--ink);border-radius:7px;padding:9px;font:inherit}
textarea{min-height:88px;resize:vertical}
.row{display:flex;gap:8px}.row>*{flex:1}
button{cursor:pointer;border:0;border-radius:7px;padding:11px;font:inherit;font-weight:600}
#go{width:100%;margin-top:14px;background:var(--brass);color:#1a1206}#go:disabled{opacity:.5;cursor:wait}
.mini{background:#0f0c07;color:var(--teal);border:1px solid var(--line);flex:0 0 auto;padding:9px 11px}
#stage{min-height:300px;display:flex;align-items:center;justify-content:center;flex-direction:column;text-align:center;color:var(--dim)}
#stage img{max-width:100%;max-height:70vh;border-radius:8px;border:1px solid var(--line)}
#meta{font-size:12px;color:var(--dim);margin-top:10px;word-break:break-word}
#dl{background:var(--teal);color:#08201e;text-decoration:none;padding:9px 16px;border-radius:7px;font-weight:600;margin-top:12px;display:none}
.spin{width:34px;height:34px;border:3px solid var(--line);border-top-color:var(--brass);border-radius:50%;animation:s 1s linear infinite}
@keyframes s{to{transform:rotate(360deg)}}
h3{font-size:12px;color:var(--dim);text-transform:uppercase;letter-spacing:.5px;margin:24px 0 8px}
#gal{display:grid;grid-template-columns:repeat(auto-fill,minmax(84px,1fr));gap:6px}
#gal img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:6px;border:1px solid var(--line);cursor:pointer}
</style></head><body>
<header><span id=dot></span><h1><b>Forge</b> ImgGen <span style=color:var(--dim)>· Dangercorn / Huginn RTX 2070</span></h1><span id=hstat>checking…</span></header>
<main>
<div class=card>
  <label>Prompt</label><textarea id=prompt placeholder="a weathered sheriff on a saloon porch at dusk"></textarea>
  <label>Style profile</label>
  <select id=profile><option value=concept>Concept — painterly (30-step)</option><option value=pixel>Pixel — fast (Lightning 8-step)</option></select>
  <label>Subject LoRA <span style=text-transform:none>(trained people/subjects)</span></label>
  <select id=lora><option value="">none</option></select>
  <div class=row><div><label>Width</label><select id=w><option>768</option><option selected>1024</option><option>512</option></select></div>
  <div><label>Height</label><select id=h><option>768</option><option selected>1024</option><option>512</option></select></div></div>
  <label>Seed</label><div class=row><input id=seed type=number value=0><button class=mini id=rnd>🎲</button></div>
  <button id=go>Generate</button>
  <h3>Recent</h3><div id=gal></div>
</div>
<div class=card><div id=stage>Type a prompt and hit Generate.</div><a id=dl download>⬇ Download PNG</a></div>
</main>
<script>
const $=s=>document.querySelector(s);
// DOM-safe rendering: prompt text always via textContent / setAttribute, never innerHTML.
function metaText(m){return `${m.profile} · ${m.size?m.size.join('×'):''} · seed ${m.seed} · ${m.gen_s||'?'}s · VRAM after ${m.vram_after_mib}MiB`;}
function show(m){
  const st=$('#stage');st.textContent='';
  const img=document.createElement('img');img.src='/img/'+m.file;st.appendChild(img);
  const meta=document.createElement('div');meta.id='meta';
  meta.textContent=metaText(m);
  const pr=document.createElement('div');pr.textContent=m.prompt||'';pr.style.marginTop='4px';
  meta.appendChild(pr);st.appendChild(meta);
  const a=$('#dl');a.href='/img/'+m.file;a.download=m.file;a.style.display='inline-block';
}
function stageMsg(txt,err){const st=$('#stage');st.textContent='';
  const d=document.createElement('div');d.id='meta';d.textContent=txt;if(err)d.style.color='#c0392b';
  st.appendChild(d);$('#dl').style.display='none';return d;}
function stageSpin(){const st=$('#stage');st.textContent='';
  const s=document.createElement('div');s.className='spin';st.appendChild(s);
  const d=document.createElement('div');d.id='meta';d.textContent='generating… 0s';st.appendChild(d);$('#dl').style.display='none';}
async function health(){try{const h=await(await fetch('/health')).json();
  $('#dot').style.background=h.busy?'#d4a843':'#4ecdc4';
  $('#hstat').textContent=(h.busy?'GPU busy':'GPU idle')+' · '+h.gpu_used_mib+' MiB';}catch(e){$('#hstat').textContent='offline';}}
async function loadGal(){try{const g=await(await fetch('/gallery')).json();
  const gal=$('#gal');gal.textContent='';
  g.forEach(m=>{const img=document.createElement('img');img.src='/img/'+m.file;
    img.setAttribute('title',(m.prompt||'').slice(0,140));img.addEventListener('click',()=>show(m));gal.appendChild(img);});
 }catch(e){}}
async function gen(){const p=$('#prompt').value.trim();if(!p)return;
  const go=$('#go');go.disabled=true;go.textContent='Generating…';
  let t=0;stageSpin();const tick=setInterval(()=>{t++;const el=$('#meta');if(el)el.textContent='generating… '+t+'s';},1000);
  try{const r=await fetch('/generate',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({prompt:p,profile:$('#profile').value,lora:$('#lora').value,width:+$('#w').value,height:+$('#h').value,seed:+$('#seed').value})});
   const d=await r.json();clearInterval(tick);
   if(d.error){stageMsg(d.error,true);}else{show(d.meta);loadGal();}
  }catch(e){clearInterval(tick);stageMsg(''+e,true);}
  go.disabled=false;go.textContent='Generate';}
$('#go').addEventListener('click',gen);
$('#rnd').addEventListener('click',()=>{$('#seed').value=Math.floor(Math.random()*1e6);});
async function loadLoras(){try{const l=await(await fetch('/loras')).json();
  const sel=$('#lora');while(sel.options.length>1)sel.remove(1);
  l.forEach(n=>{const o=document.createElement('option');o.value=n;o.textContent=n;sel.appendChild(o);});}catch(e){}}
health();loadGal();loadLoras();setInterval(health,5000);
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj, ctype="application/json"):
        b = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/" or p == "/index.html":
            self._send(200, PAGE.encode(), "text/html; charset=utf-8")
        elif p == "/health":
            busy, m, u = imggen.gpu_busy()
            self._send(200, {"ok": True, "gpu_used_mib": m, "gpu_util": u, "busy": busy})
        elif p == "/gallery":
            self._send(200, gallery_list())
        elif p == "/loras":
            self._send(200, imggen.list_loras())
        elif p.startswith("/img/"):
            name = os.path.basename(unquote(p[5:]))
            fp = GALLERY + "/" + name
            if name.endswith(".png") and os.path.exists(fp):
                self._send(200, open(fp, "rb").read(), "image/png")
            else:
                self._send(404, {"error": "not found"})
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
            data, name, meta = run_job(spec)
            self._send(200, {"artifacts": [{"base64": base64.b64encode(data).decode()}], "meta": meta})
        except Timeout:
            self._send(503, {"error": "another image job holds the GPU lock — try again shortly"})
        except Exception as e:
            self._send(500, {"error": str(e)[:800]})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("forge-imggen + portal on 0.0.0.0:%d (worker-per-job, VRAM-clean)" % PORT, flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
