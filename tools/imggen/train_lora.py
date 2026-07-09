#!/usr/bin/env python
# =============================================================================
# forge-imggen LoRA TRAINER — teach SDXL a specific person/subject on the 8GB
# RTX 2070. PRIVATE + LOCAL: training images + output LoRAs never leave Huginn,
# never go in the shared gallery, never get pushed to git.
#
# 8GB strategy (design panel calder-018): cache VAE latents + text embeddings
# ONCE (load encoders -> encode -> unload), then only the UNet + tiny LoRA is
# resident during training. 768px, gradient checkpointing, batch 1.
#
# Usage: python train_lora.py <images_dir> <trigger_name> [--steps N] [--rank R]
#   e.g. python train_lora.py /data/forge-imggen/train/tim tim --steps 1400
# Output: /data/forge-imggen/loras/<trigger_name>/pytorch_lora_weights.safetensors
#   Use in a prompt with the trigger token, e.g. "a photo of tim_person as a gunslinger".
# =============================================================================
import argparse
import gc
import glob
import os

os.environ.setdefault("HF_HOME", "/data/forge-imggen/hf")
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image

BASE = "stabilityai/stable-diffusion-xl-base-1.0"
LORA_ROOT = "/data/forge-imggen/loras"
DEV = "cuda"


def log(m):
    print(m, flush=True)


def gpu_mib():
    return torch.cuda.memory_allocated() // (1024 * 1024)


def load_images(d, res):
    paths = []
    for ext in ("*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.PNG"):
        paths += glob.glob(os.path.join(d, ext))
    if not paths:
        raise SystemExit("no images in %s" % d)
    imgs = []
    for p in sorted(paths):
        im = Image.open(p).convert("RGB")
        # center-crop square, resize to res
        w, h = im.size
        s = min(w, h)
        im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((res, res), Image.LANCZOS)
        arr = np.asarray(im, dtype=np.float32) / 127.5 - 1.0  # [-1,1]
        imgs.append(torch.from_numpy(arr).permute(2, 0, 1))
    log("  loaded %d training images" % len(imgs))
    return torch.stack(imgs)  # (N,3,res,res)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images_dir")
    ap.add_argument("trigger")
    ap.add_argument("--steps", type=int, default=1400)
    ap.add_argument("--rank", type=int, default=16)
    ap.add_argument("--res", type=int, default=768)
    ap.add_argument("--lr", type=float, default=1e-4)
    a = ap.parse_args()
    prompt = "a photo of %s person" % a.trigger
    outdir = os.path.join(LORA_ROOT, a.trigger)
    os.makedirs(outdir, exist_ok=True)
    torch.cuda.set_per_process_memory_fraction(0.92)

    pixels = load_images(a.images_dir, a.res)  # CPU

    # ---- 1. cache VAE latents, then unload VAE -------------------------------
    from diffusers import AutoencoderKL
    log("[1/4] encoding latents (VAE)...")
    vae = AutoencoderKL.from_pretrained("madebyollin/sdxl-vae-fp16-fix", torch_dtype=torch.float16).to(DEV)
    lat = []
    with torch.no_grad():
        for i in range(pixels.shape[0]):
            x = pixels[i:i + 1].to(DEV, torch.float16)
            l = vae.encode(x).latent_dist.sample() * vae.config.scaling_factor
            lat.append(l.cpu())
    latents = torch.cat(lat)  # (N,4,res/8,res/8) on CPU
    del vae, lat
    gc.collect(); torch.cuda.empty_cache()

    # ---- 2. cache text embeddings, then unload text encoders -----------------
    from transformers import CLIPTextModel, CLIPTextModelWithProjection, CLIPTokenizer
    log("[2/4] encoding prompt embeddings (text encoders)...")
    tok1 = CLIPTokenizer.from_pretrained(BASE, subfolder="tokenizer")
    tok2 = CLIPTokenizer.from_pretrained(BASE, subfolder="tokenizer_2")
    te1 = CLIPTextModel.from_pretrained(BASE, subfolder="text_encoder", torch_dtype=torch.float16).to(DEV)
    te2 = CLIPTextModelWithProjection.from_pretrained(BASE, subfolder="text_encoder_2", torch_dtype=torch.float16).to(DEV)
    with torch.no_grad():
        ids1 = tok1(prompt, padding="max_length", max_length=77, truncation=True, return_tensors="pt").input_ids.to(DEV)
        ids2 = tok2(prompt, padding="max_length", max_length=77, truncation=True, return_tensors="pt").input_ids.to(DEV)
        o1 = te1(ids1, output_hidden_states=True)
        o2 = te2(ids2, output_hidden_states=True)
        pe = torch.cat([o1.hidden_states[-2], o2.hidden_states[-2]], dim=-1).cpu()  # (1,77,2048)
        pooled = o2.text_embeds.cpu()  # (1,1280)
    del te1, te2, o1, o2
    gc.collect(); torch.cuda.empty_cache()

    # ---- 3. UNet + LoRA ------------------------------------------------------
    from diffusers import DDPMScheduler, UNet2DConditionModel
    log("[3/4] loading UNet + attaching LoRA (rank %d)..." % a.rank)
    unet = UNet2DConditionModel.from_pretrained(BASE, subfolder="unet", torch_dtype=torch.float16).to(DEV)
    unet.requires_grad_(False)
    unet.enable_gradient_checkpointing()
    from peft import LoraConfig
    lc = LoraConfig(r=a.rank, lora_alpha=a.rank, init_lora_weights="gaussian",
                    target_modules=["to_k", "to_q", "to_v", "to_out.0"])
    unet.add_adapter(lc)
    # LoRA params -> fp32 for stable optimization
    lora_params = [p for p in unet.parameters() if p.requires_grad]
    for p in lora_params:
        p.data = p.data.float()
    log("  trainable LoRA params: %.2fM | UNet resident: %d MiB" %
        (sum(p.numel() for p in lora_params) / 1e6, gpu_mib()))
    sched = DDPMScheduler.from_pretrained(BASE, subfolder="scheduler")
    opt = torch.optim.AdamW(lora_params, lr=a.lr)
    scaler = torch.cuda.amp.GradScaler()

    res = a.res
    add_time = torch.tensor([[res, res, 0, 0, res, res]], device=DEV, dtype=torch.float16)
    pe_d = pe.to(DEV, torch.float16)
    pooled_d = pooled.to(DEV, torch.float16)
    N = latents.shape[0]

    # ---- 4. train ------------------------------------------------------------
    log("[4/4] training %d steps..." % a.steps)
    unet.train()
    g = torch.Generator(device=DEV).manual_seed(0)
    for step in range(a.steps):
        i = int(torch.randint(0, N, (1,), generator=g, device=DEV).item())
        lat_i = latents[i:i + 1].to(DEV, torch.float16)
        noise = torch.randn(lat_i.shape, device=DEV, dtype=torch.float16, generator=g)
        t = torch.randint(0, sched.config.num_train_timesteps, (1,), device=DEV, generator=g).long()
        noisy = sched.add_noise(lat_i, noise, t)
        with torch.autocast("cuda", dtype=torch.float16):
            pred = unet(noisy, t, encoder_hidden_states=pe_d,
                        added_cond_kwargs={"text_embeds": pooled_d, "time_ids": add_time}).sample
            loss = F.mse_loss(pred.float(), noise.float())
        scaler.scale(loss).backward()
        scaler.step(opt); scaler.update(); opt.zero_grad(set_to_none=True)
        if step % 100 == 0 or step == a.steps - 1:
            log("  step %4d/%d  loss %.4f  vram %d MiB" % (step, a.steps, loss.item(), gpu_mib()))

    # ---- save LoRA (diffusers format, loadable by pipe.load_lora_weights) ----
    from diffusers import StableDiffusionXLPipeline
    from diffusers.utils import convert_state_dict_to_diffusers
    from peft.utils import get_peft_model_state_dict
    unet_lora = convert_state_dict_to_diffusers(get_peft_model_state_dict(unet))
    StableDiffusionXLPipeline.save_lora_weights(save_directory=outdir, unet_lora_layers=unet_lora, safe_serialization=True)
    log("SAVED LoRA -> %s (trigger token: '%s person')" % (outdir, a.trigger))


if __name__ == "__main__":
    main()
