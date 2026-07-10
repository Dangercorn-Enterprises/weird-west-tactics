# forge-imggen WORKER — one job per PROCESS so the CUDA context (the ~548 MiB
# that empty_cache can't free) dies on exit and VRAM returns to true baseline.
# Invoked by serve.py as: python worker.py <job.json>
# job.json: {"prompt","profile","width","height","seed","out",
#            "init"?, "strength"?}   (init = path to an uploaded photo -> img2img)
import json
import sys

sys.path.insert(0, "/data/forge-imggen")
import imggen


def main(job_path):
    job = json.load(open(job_path))
    init = None
    if job.get("init"):
        from PIL import Image
        init = Image.open(job["init"])
    pipe = imggen.load(job.get("profile", "concept"), lora=job.get("lora"),
                       mode="img2img" if init is not None else "txt2img")
    img = imggen.generate(
        pipe, job["prompt"], profile=job.get("profile", "concept"),
        width=int(job.get("width", 1024)), height=int(job.get("height", 1024)),
        seed=int(job.get("seed", 0)), style=job.get("style", True),
        negative_prompt=job.get("negative_prompt"),
        init_image=init, strength=float(job.get("strength", 0.6)),
    )
    img.save(job["out"])
    # process exit (below) frees the CUDA context -> VRAM back to ~1 MiB
    print("WORKER_OK %s %s" % (job["out"], img.size))


if __name__ == "__main__":
    main(sys.argv[1])
