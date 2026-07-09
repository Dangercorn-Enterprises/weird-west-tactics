# forge-imggen — local fleet image generation (SDXL, Huginn RTX 2070)

Replaces the NVIDIA NIM flux endpoint with a self-hosted, commercial-clean image
generator. Chosen via a 5-approach design panel (forge item calder-016).

- **Model:** SDXL 1.0 base, native fp16 (Open RAIL++-M — commercial-safe, unlike
  flux.1-dev which is non-commercial). fp16-fix VAE. Runs native-fp16 on Turing
  (no bf16 tax, no quant kernels).
- **Profiles:** `concept` (30-step painterly) · `pixel` (SDXL-Lightning 8-step +
  the Dustfall pixel post-process downstream). Real STYLE_PIXEL/STYLE_PAINT strings.
- **Lifecycle:** ONE subprocess per job so the CUDA context dies on exit and VRAM
  returns to true baseline (~1 MiB image-context) between jobs — proven.
- **Arbitration:** filelock serializes image jobs; a pynvml idle-gate refuses to
  load while ollama/memory-engine are resident (never force-evicts). Coexists.

## Deploy (Huginn 10.2.0.11)
Code + venv live at `/data/forge-imggen/`; runs as `systemctl --user forge-imggen`
(enabled, linger). Weights cache in `/data/forge-imggen/hf`.

## API (mirrors the old NIM shape)
- `POST http://10.2.0.11:8710/generate` `{prompt, profile?, width?, height?, seed?, style?}`
  -> `{"artifacts":[{"base64":"<png>"}], "meta":{...}}`
- `GET  http://10.2.0.11:8710/health`

## Consumers
`tools/gen_assets.py::gen()` calls this first (env `IMGGEN_URL`), NIM as fallback.

## Web portal + fleet command (no code needed)
- **Portal:** open **http://10.2.0.11:8710/** in any browser on the LAN — type a
  prompt, pick profile/size, Generate; image shows inline with a Download button
  and a persistent gallery of past runs. (Served by serve.py; images in
  `/data/forge-imggen/gallery/`.)
- **Fleet command:** `imagegen "prompt" [concept|pixel] [w] [h]` on any node
  (`~/.local/bin/imagegen`, deployed fleet-wide) — generates on Huginn's GPU,
  prints the view URL.
- **Follow-up (not built):** an MCP tool so Hermes agents can generate on request
  in chat ("hey Tiki, make me a picture of X") — Hermes supports `mcp`/`tools`.

## LoRA training (private, local) — teach it a person or subject
- **Train:** put ~15-30 photos of one subject in `/data/forge-imggen/train/<name>/` on
  Huginn, then `python train_lora.py <dir> <name> --steps 1400`. Produces
  `/data/forge-imggen/loras/<name>/` (~1h on the 2070, peak <6GB). Verified: SDXL
  LoRA trains in 8GB via cached latents/embeds (only the UNet resident, 768px,
  gradient checkpointing).
- **Use:** the trained subject appears in the portal's **Subject LoRA** dropdown;
  pick it and generate (trigger token = "<name> person"). `imggen.load(profile, lora=)`.
- **PRIVACY (enforced):** training images + LoRAs stay on Huginn `/data`, are NOT in
  this repo, NOT in the shared gallery, NOT pushed anywhere. Family faces never
  leave the house. `.gitignore` guards against accidental commits.
- **Next:** a face-clustering ingest so a bulk photo dump (Google Takeout) auto-sorts
  into per-person training sets (you just name the clusters) — commercial-clean
  dlib/face_recognition, no Google API (face groups aren't API-exposed).
