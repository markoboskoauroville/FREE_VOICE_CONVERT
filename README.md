# Free Voice Convert (Free Voice Convert Equalizer)

Marko, 1.11.2026: *"Its purpose is exactly to make AI videos sound good, so it does automatically everything we are
doing in DaVinci. You just pick the voice, and it outputs the voice so that all the clips sound the same, even if I am
in different spaces and different environments."* The full request is in `momentaryupdates.md`.

**Website:** https://freevoiceconvert.pages.dev · **GitHub:** markoboskoauroville/FREE_VOICE_CONVERT (private) ·
**License:** GPL-3.0 (Seed-VC is GPL-3.0) · **Version:** the one number in `mac/App.swift` (whole numbers).

## What it does

One window, two choices and a list: **SOURCE VOICE** (the voice and the room every clip should have) and the clips
(audio or video, in order). Every clip goes through:

1. **Clean**: high-pass 70 Hz and a gentle steady-noise reduction (ffmpeg `afftdn`), the "Clear" we used in Resolve.
2. **Voice** (CONVERT): Seed-VC, zero-shot speech-to-speech, turns the speech into the profile's voice. The output has
   the same number of frames as the input, so no transcription or re-timing is needed: the lips still fit.
   SPEECH = the 22.05 kHz speech model; STUDIO = the 44.1 kHz pitch-tracked model (the speaker's melody kept, moved to
   the profile voice's median pitch). KEEP skips this step: the speaker stays, only the sound is matched.
3. **Profile**: the clip's long-term average spectrum (voiced frames, 1/6-octave bands) is compared to the profile's;
   the difference becomes a smooth linear-phase EQ (limited to ±12 dB). This is the "acoustic quality profile":
   a reference enhanced by Adobe Podcast gives every clip that microphone and that room.
4. **Level**: −16 LUFS integrated, a look-ahead limiter at −1 dBFS.
5. **Export**: ONE BY ONE (`<name>_fvc.wav`, or the video with the new sound, picture copied), STITCHED (one file in
   the list's order; video scaled/padded to the first clip's size and frame rate, sound-only clips get black picture),
   or BOTH. Into a `Free Voice Convert` folder next to the first clip.

## The parts

```
engine/fvc.py            the engine (check, fetch, profile, profiles, run <job.json>); '@' JSON lines = progress
engine/seedvc_runner.py  Seed-VC loaded once, many clips converted (its inference.py main() as a function)
engine/dsp.py            profile, LTAS, match EQ, loudness, limiter (no model)
engine/setup.sh / .ps1   the installation: uv -> Python 3.11 -> torch 2.5.1 -> packages -> Seed-VC (pinned) -> models
engine/PINS              the pinned versions (Seed-VC commit, uv, Python, torch)
mac/                     Free Voice Convert Equalizer (Mantra).app, SwiftUI, swiftc (build.sh, tools/make_dmg.sh)
windows/                 FreeVoiceConvert.exe, WinForms on .NET Framework 4.8 (in every Windows 10/11), installer.iss
site/public/             the website (donation bowl, download + visit counters, Speechify keys, SEO)
.github/workflows/       build.yml (dmg + Setup.exe -> release v<N>), site.yml (release files + page -> Cloudflare)
```

The data folder (Python, Seed-VC, models, profiles): macOS `~/Library/Application Support/FreeVoiceConvert`,
Windows `%LOCALAPPDATA%\FreeVoiceConvert`. About 3 GB after the installation.

## Models (downloaded during the installation)

| Model | From | Use |
|---|---|---|
| DiT_seed_v2_uvit_whisper_small_wavenet_bigvgan_pruned | Plachta/Seed-VC | SPEECH conversion |
| DiT_seed_v2_uvit_whisper_base_f0_44k_bigvgan_pruned_ft_ema_v2 | Plachta/Seed-VC | STUDIO conversion |
| bigvgan_v2_22khz_80band_256x, bigvgan_v2_44khz_128band_512x | nvidia | vocoders |
| whisper-small (encoder) | openai | speech content |
| campplus_cn_common | funasr/campplus | speaker style |
| rmvpe | lj1995/VoiceConversionWebUI | pitch (STUDIO) |

Chosen from the research of 31.10.2026 (ElevateMedia production/damjan/research/voice_alternatives.md): Seed-VC is
zero-shot (no training, a 10–30 s reference) and beat OpenVoice and CosyVoice on similarity in its own evaluation.

## Building

- Mac: `mac/build.sh` (signed "Mantra Apps" and installed in /Applications on Marko's Mac; ad-hoc on GitHub), then
  `mac/tools/make_dmg.sh`.
- Windows: `dotnet build windows/FreeVoiceConvert.csproj -c Release`, then `ISCC /DAppVersion=N windows/installer.iss`.
- GitHub does both at every push to mac/, windows/, engine/ (`Build apps`), makes release `v<N>`, and `Site` deploys
  the page with those files. Secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
