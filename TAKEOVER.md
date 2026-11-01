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
