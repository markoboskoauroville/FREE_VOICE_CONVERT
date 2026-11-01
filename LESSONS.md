# LESSONS: Free Voice Convert

1. **Seed-VC must run under `torch.no_grad()`** (1.11.2026). Its main() is decorated; a wrapper that calls the model
   parts without it dies in BigVGAN with "Inference tensors cannot be saved for backward".
2. **BigVGAN does not fit MPS** (1.11.2026): "Output channels > 65536 not supported at the MPS device", and
   PYTORCH_ENABLE_MPS_FALLBACK does not catch it (it is a raised error, not a missing op). The vocoder runs on the CPU
   on Macs; the DiT stays on MPS.
3. **MPS has no float64**: RMVPE pitch comes back as float64 numpy; `.float()` before `.to(device)`.
4. **imageio-ffmpeg 0.5.1 has no arm64 Mac binary** and silently returns "ffmpeg" from the PATH, which works on a
   developer's Mac and fails on a user's. 0.6.0 brings ffmpeg 7.1 for arm64. Test with PATH=/usr/bin:/bin.
5. **The "Mantra Apps" identity is not "valid"** for `security find-identity -v` (self-signed); look without -v.
6. **A new Cloudflare Pages project must be created before `pages deploy`** in CI (non-interactive wrangler will not
   create it); `wrangler pages project create ... || true` before the deploy step.
