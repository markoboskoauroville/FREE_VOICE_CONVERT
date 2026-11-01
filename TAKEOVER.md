# TAKEOVER: Free Voice Convert, where it stands (1.11.2026)

**v1 is live:** https://freevoiceconvert.pages.dev (download buttons: download/FreeVoiceConvert-1.dmg and
FreeVoiceConvert-1-Setup.exe, from release v1). Secrets in the repo: CLOUDFLARE_API_TOKEN (Marko pasted it),
CLOUDFLARE_ACCOUNT_ID (set from ~/Downloads/API/Cloudflare.api.txt; it is not a secret, never ask him for it).

**Proven on this Mac (1.11.2026):** setup.sh from nothing to `ready` (uv, Python 3.11.11, torch 2.5.1 on MPS, Seed-VC
51383efd, both models, 2.7 GB of models). Three HIR_98 Footage clips (1, 4, 7) with the EM_female_2 profile: SPEECH 88 s,
STUDIO 355 s for 22 s of sound; one by one and stitched mp4; video length kept; -16.5 LUFS each. Marko's Adobe pair
(Desktop ORIGINAL.wav / ORIGINAL-enhanced-v2.wav): profile "Studio profile"; listening files in
~/Desktop/Free Voice Convert test (0-compare: original, Adobe, ours KEEP, ours CONVERT). The Mac app opens, sees the
engine ready, lists the profiles (window capture checked).

**Not yet proven:** the Windows installer and app on a real Windows (built on GitHub only); the Mac .dmg from GitHub on
a clean Mac (ad-hoc signed, so "Open Anyway"); Marko's ears on the comparison.

**Next:** Marko listens to the comparison and the stitched clips and says what is missing against Adobe. Likely work:
a dereverb/denoise model before the conversion (the room of the source leaks into the content features), a room-tone bed
for the pauses, and making STUDIO faster (BigVGAN 44k on the CPU is the slow part on Macs).

## v2 and v3 (1.11.2026, later)

- **v2 lossless:** own sample rate / bit depth / channels out (24-bit for lossy sources), picture copied bit for bit,
  PCM in .mov (.mkv for mkv/webm/avi), lossless stitch when clips match. Proven with 44.1/16 stereo, 96/24 mono, mp3, mp4.
- **v3 window:** a workflow, ① ADD FILES, ② HOW TO EXPORT, ③ CONVERT; the round numbers are the buttons (lit and
  bigger on hover). The voice is asked once at the first CONVERT. Defaults: CONVERT, SPEECH, CLEAN. ✕ closes the window,
  OFF quits. Windows: Delete / Alt+arrows / right-click menu for the list. Live: FreeVoiceConvert-3.dmg / -3-Setup.exe.

## v4 and closing (1.11.2026, 05:20)

- **v4 window** (MANTRA_MANIFEST modules/workflow-interface.md, the default for every app now): ① ADD FILES | NEW TASK,
  ② ONE BY ONE | STITCHED | BOTH, ③ CONVERT → STOP → RESUME with the percentage; one labelled table (CONVERTED, TIME LEFT,
  ENDS AT, RUNNING, SPEED in fps | CPU, RAM FREE, GPU, VRAM FREE), hairlines, grey lines between parts, text grows with
  the width while the list shows more files, the window remembers its place and screen. No VU (removed at his word).
- **Engine:** each finished clip saved in `done/` (RESUME skips it; deleted when the job completes); downloads resume
  (curl -C -, .done markers, torch wheels by curl). Proven: the 22 HIR_98 clips → stitched_fvc.mov 2:50.8, PCM 24-bit.
- **Live:** https://freevoiceconvert.pages.dev (FreeVoiceConvert-4.dmg, FreeVoiceConvert-4-Setup.exe, the v4 window).
- **Damjan:** the message (Free Voice Convert + Voice to Text (Mantra), Croatian) was pasted unsent into WhatsApp
  "AI Videos"; Marko sends it. Damjan's gaming PC will be the first real Windows test of both apps.
- **Left:** Windows never run on a real PC; STUDIO quality is slow on Macs (BigVGAN 44 k on the CPU); a dereverb step if
  Marko hears the source room through.
