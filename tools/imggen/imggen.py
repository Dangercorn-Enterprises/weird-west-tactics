# =============================================================================
# forge-imggen — Huginn on-demand image-gen service CORE (load -> gen -> unload)
# Backbone: SDXL 1.0 base fp16 (Open RAIL++-M, commercial-clean), native fp16 on
# the RTX 2070 (Turing) so NO bf16 emulation + NO quant kernels. Two LoRA
# profiles: "pixel" (SDXL-Lightning 8-step, fast sprites) / "concept" (30-step,
# painterly). Design panel spec: forge item calder-016.
#
# Lifecycle contract: every job load()s, generate()s, teardown()s so VRAM
# returns to ~baseline for the memory-engine / ollama. Arbitration: a filelock
# serializes image jobs + a pynvml idle-gate refuses to load while another GPU
# user is resident.
# =============================================================================
import gc
import os

os.environ.setdefault("HF_HOME", "/data/forge-imggen/hf")
os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "0")
import torch

BASE = "stabilityai/stable-diffusion-xl-base-1.0"
VAE_FIX = "madebyollin/sdxl-vae-fp16-fix"
LIGHTNING_REPO = "ByteDance/SDXL-Lightning"
LIGHTNING_CKPT = "sdxl_lightning_8step_lora.safetensors"
LOCK_PATH = "/data/forge-imggen/gpu.lock"
BASELINE_MIB = 300  # teardown must return under this

# The real Dustfall style descriptors (from tools/gen_assets.py)
STYLE_PIXEL = ("16-bit SNES pixel art, crisp chunky pixels, dark warm ink outlines, "
               "weird west aesthetic, warm umber ochre and brass palette with teal accents")
STYLE_PAINT = ("painterly concept art, weird western americana, warm dusk light, "
               "deep umber shadows, brass and teal accents, moody, high detail")


# ---- GPU arbitration -------------------------------------------------------
def _nvml_handle():
    import pynvml
    pynvml.nvmlInit()
    return pynvml, pynvml.nvmlDeviceGetHandleByIndex(0)


def gpu_used_mib():
    pynvml, h = _nvml_handle()
    return pynvml.nvmlDeviceGetMemoryInfo(h).used // (1024 * 1024)


def gpu_busy(mem_thresh=1536, util_thresh=20):
    """True if another GPU user (ollama/memory-engine) is resident. Baseline ~1 MiB."""
    pynvml, h = _nvml_handle()
    m = pynvml.nvmlDeviceGetMemoryInfo(h).used // (1024 * 1024)
    u = pynvml.nvmlDeviceGetUtilizationRates(h).gpu
    return (m > mem_thresh or u > util_thresh), m, u


def wait_for_gpu(max_wait=300, poll=5):
    """Back off (never force-evict) until the card is idle. Returns True if free."""
    import time
    waited = 0
    while waited < max_wait:
        busy, m, u = gpu_busy()
        if not busy:
            return True
        time.sleep(poll)
        waited += poll
    return False


# private trained LoRAs (family / house-model / product subjects) live here;
# gitignored + never in the shared gallery.
LORA_ROOT = "/data/forge-imggen/loras"


def list_loras():
    if not os.path.isdir(LORA_ROOT):
        return []
    return sorted(d for d in os.listdir(LORA_ROOT)
                  if os.path.exists(os.path.join(LORA_ROOT, d, "pytorch_lora_weights.safetensors")))


# ---- load / generate / teardown -------------------------------------------
def load(profile="concept", lora=None):
    from diffusers import AutoencoderKL, DiffusionPipeline, EulerDiscreteScheduler
    torch.cuda.set_per_process_memory_fraction(0.90)
    # fp16-fix VAE avoids the known SDXL fp16 black/NaN decode
    vae = AutoencoderKL.from_pretrained(VAE_FIX, torch_dtype=torch.float16)
    pipe = DiffusionPipeline.from_pretrained(
        BASE, vae=vae, torch_dtype=torch.float16, variant="fp16", use_safetensors=True,
    )
    # Turing path: torch SDPA only. Do NOT enable xformers / flash-attn.
    # Load adapters BEFORE cpu-offload so their hooks register cleanly.
    active = []
    if profile == "pixel":
        from huggingface_hub import hf_hub_download
        pipe.load_lora_weights(hf_hub_download(LIGHTNING_REPO, LIGHTNING_CKPT), adapter_name="lightning")
        active.append("lightning")
        pipe.scheduler = EulerDiscreteScheduler.from_config(
            pipe.scheduler.config, timestep_spacing="trailing")
    if lora:
        d = os.path.join(LORA_ROOT, os.path.basename(lora))
        if os.path.isdir(d):
            pipe.load_lora_weights(d, adapter_name="subject")
            active.append("subject")
    if active:
        pipe.set_adapters(active, adapter_weights=[1.0] * len(active))
    pipe.enable_model_cpu_offload()   # text encoders encode then evict; UNet resident
    pipe.enable_vae_tiling()          # 1024 safety margin
    return pipe


def generate(pipe, prompt, profile="concept", width=1024, height=1024, seed=0,
             style=True, lora=None, negative_prompt=None):
    styled = f"{prompt}, {STYLE_PIXEL if profile == 'pixel' else STYLE_PAINT}" if style else prompt
    steps, gs = (8, 0.0) if profile == "pixel" else (30, 6.0)
    g = torch.Generator(device="cuda").manual_seed(int(seed))
    kw = dict(prompt=styled, num_inference_steps=steps, guidance_scale=gs, generator=g)
    # negative_prompt only takes effect with classifier-free guidance (gs > 1);
    # the SDXL-Lightning "pixel" profile runs at gs=0.0 and ignores it (and some
    # diffusers builds error if it's passed there), so gate on gs.
    if negative_prompt and gs > 1:
        kw["negative_prompt"] = negative_prompt
    try:
        return pipe(width=width, height=height, **kw).images[0]
    except torch.cuda.OutOfMemoryError:
        torch.cuda.empty_cache()
        print("  [OOM at %dx%d -> retry 768x768]" % (width, height))
        return pipe(width=768, height=768, **kw).images[0]


def teardown(pipe):
    """Strip accelerate offload hooks (they pin GPU refs), free, verify baseline."""
    try:
        pipe.remove_all_hooks()
    except Exception:
        pass
    del pipe
    gc.collect()
    torch.cuda.empty_cache()
    torch.cuda.ipc_collect()
    torch.cuda.reset_peak_memory_stats()
    used = gpu_used_mib()
    return used
