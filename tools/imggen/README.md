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
