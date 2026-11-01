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
7. **Never install over a running job** (1.11.2026): build.sh replaces the app in /Applications; doing it twice during
   Marko's 22-clip run lost the whole job (empty output folder). Build with `CI=1` (no install) while a job runs.
8. **Helper runs must not own the job** (1.11.2026): `run()` set `proc`/`busy` for every process, so a `check` that
   ended mid-job set busy = false and dropped the job's handle: the window showed RESUME while the engine went on and
   STOP could not reach it. Only the job sets them now (`job:` flag), and STOP forces SIGKILL after 2 s.
9. **Each converted clip is saved whole** (`done/<key>.wav`, written as .part then renamed), keyed by path, size,
   mtime, profile and settings: STOP → RESUME skips finished clips (proven: RESUME went straight to 7/22, 27 %).
10. **The interface rules of the day** are in MANTRA_MANIFEST modules/workflow-interface.md (the default for every app).
11. **Download buttons carry no version** (1.11.2026, MANTRA_MANIFEST modules/download-always-latest.md). The page
   linked FreeVoiceConvert-__VERSION__.dmg with the version from mac/App.swift, so a push that raised the number but had
   not yet released showed a version whose files did not exist. Now the buttons are fixed names, site.yml copies the
   newest release's .dmg/.exe to them and takes the version from that release's tag (files and number from one source),
   and it fails red instead of deploying a page without both files or with a file over Pages' 25 MB. Cloudflare Pages
   `_redirects` accepts a splat in the middle of a name (`/download/FreeVoiceConvert-*-Setup.exe`): verified 301 live.
