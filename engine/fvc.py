#!/usr/bin/env python3
"""fvc.py: the Free Voice Convert engine. The Mac and the Windows app both run this; it never opens a window.

  fvc.py check                      are Python, Seed-VC and the models all here? (exit 1 if not)
  fvc.py fetch                      download every model (the installer runs this)
  fvc.py profile <audio> <name>     make a sound profile from a voice recording
  fvc.py profiles                   the profiles, as JSON
  fvc.py run <job.json>             convert, equalize, level, and export (one by one or stitched)

Every line meant for the app starts with '@' and is JSON: {"pct": 0..100, "msg": "...", "clip": i} or
{"done": true, "outputs": [...]} or {"error": "..."}. Anything else is a log line.

The data folder: macOS ~/Library/Application Support/FreeVoiceConvert, Windows %LOCALAPPDATA%\\FreeVoiceConvert
(FVC_HOME overrides). Inside: seed-vc/ (the code), models/ (the weights), profiles/, the Python environment.
"""
import json
import os
import re
import subprocess
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
VERSION = 1


def home():
    if os.environ.get("FVC_HOME"):
        return os.environ["FVC_HOME"]
    if sys.platform == "win32":
        return os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "FreeVoiceConvert")
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Application Support/FreeVoiceConvert")
    return os.path.expanduser("~/.local/share/FreeVoiceConvert")


HOME = home()
SEEDVC = os.path.join(HOME, "seed-vc")
MODELS = os.path.join(HOME, "models")
PROFILES = os.path.join(HOME, "profiles")
os.environ.setdefault("HF_HUB_CACHE", os.path.join(MODELS, "checkpoints", "hf_cache"))
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")  # BigVGAN has a conv too long for MPS: that op runs on the CPU

# what `fetch` must leave behind (relative to MODELS/checkpoints, matched loosely)
NEEDED = {
    "speech": ["DiT_seed_v2_uvit_whisper_small_wavenet_bigvgan_pruned.pth", "bigvgan_v2_22khz_80band_256x"],
    "studio": ["DiT_seed_v2_uvit_whisper_base_f0_44k_bigvgan_pruned_ft_ema_v2.pth", "bigvgan_v2_44khz_128band_512x",
               "rmvpe.pt"],
    "both": ["campplus_cn_common.bin", "whisper-small"],
}


def say(**kw):
    print("@" + json.dumps(kw), flush=True)


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def probe(path):
    """What the file holds, from ffmpeg's own banner: picture (size, fps, codec) and sound (rate, channels, depth)."""
    r = subprocess.run([ffmpeg(), "-hide_banner", "-i", path], capture_output=True, text=True, errors="replace")
    t = r.stderr
    dur = 0.0
    m = re.search(r"Duration: (\d+):(\d+):(\d+\.\d+)", t)
    if m:
        dur = int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3])
    vline = next((l for l in t.splitlines() if re.search(r"Stream #\S+.*Video:", l) and "attached pic" not in l), "")
    v = re.search(r"Video: (\w+).*?(\d{2,5})x(\d{2,5})", vline)
    f = re.search(r"(\d+(?:\.\d+)?) fps", vline) or re.search(r"(\d+(?:\.\d+)?) tbr", vline)
    aline = next((l for l in t.splitlines() if re.search(r"Stream #\S+.*Audio:", l)), "")
    a = re.search(r"Audio: (\w+)", aline)
    sr = re.search(r"(\d+) Hz", aline)
    ch = 2
    layouts = {"mono": 1, "stereo": 2, "2.1": 3, "3.0": 3, "quad": 4, "4.0": 4, "4.1": 5, "5.0": 5, "5.1": 6,
               "6.0": 6, "6.1": 7, "7.0": 7, "7.1": 8}
    lay = re.search(r"Hz, ([\w.]+)(?:\(\w+\))?,", aline)
    if lay and lay[1] in layouts:
        ch = layouts[lay[1]]
    elif re.search(r"(\d+) channels", aline):
        ch = int(re.search(r"(\d+) channels", aline)[1])
    # bit depth: pcm_s16le / s16 -> 16, s24 / "(24 bit)" -> 24, s32 -> 32, flt/f32 -> float; lossy codecs have none
    bits = None
    if re.search(r"\(24 bit\)|pcm_s24|s24", aline):
        bits = 24
    elif re.search(r"pcm_s16|\bs16p?\b", aline) and (a and (a[1].startswith("pcm") or a[1] in ("flac", "alac"))):
        bits = 16
    elif re.search(r"pcm_s32|\bs32p?\b", aline) and (a and (a[1].startswith("pcm") or a[1] in ("flac", "alac"))):
        bits = 32
    elif re.search(r"pcm_f32|pcm_f64", aline):
        bits = "float"
    return {"video": bool(v), "vcodec": v[1] if v else "", "w": int(v[2]) if v else 0, "h": int(v[3]) if v else 0,
            "fps": float(f[1]) if f else 30.0, "audio": bool(a), "acodec": a[1] if a else "", "dur": dur,
            "sr": int(sr[1]) if sr else 48000, "ch": max(1, min(ch, 8)), "bits": bits}


def read_audio(path, info=None, clean=True):
    """The sound as it is: its own sample rate and channels, float32, shape (samples, channels). Nothing resampled."""
    import numpy as np
    info = info or probe(path)
    sr, ch = info["sr"], info["ch"]
    cmd = [ffmpeg(), "-v", "error", "-i", path, "-vn", "-map", "0:a:0"]
    if clean:  # rumble and steady noise away before the voice is read (the "Clear" we used in Resolve, gently)
        cmd += ["-af", "highpass=f=70,afftdn=nf=-25:tn=1"]
    cmd += ["-ac", str(ch), "-ar", str(sr), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy().reshape(-1, ch), sr


SUBTYPE = {16: "PCM_16", 24: "PCM_24", 32: "PCM_32", "float": "FLOAT"}
PCM = {16: "pcm_s16le", 24: "pcm_s24le", 32: "pcm_s32le", "float": "pcm_f32le"}


def write_wav(path, x, sr, bits=24):
    import soundfile as sf
    sf.write(path, x, sr, subtype=SUBTYPE.get(bits or 24, "PCM_24"))


# ------------------------------------------------------------------------------------------------ commands
def cmd_check():
    ok = True
    if not os.path.isfile(os.path.join(SEEDVC, "inference.py")):
        print("missing: seed-vc code in", SEEDVC)
        ok = False
    ck = os.path.join(MODELS, "checkpoints")
    found = []
    for root, dirs, files in os.walk(ck):
        found += files + dirs
    blob = "\n".join(found)
    for group, names in NEEDED.items():
        for n in names:
            if n not in blob:
                print(f"missing ({group}): {n}")
                ok = False
    try:
        import torch, transformers, librosa, pyloudnorm, imageio_ffmpeg  # noqa: F401
        dev = "cuda" if torch.cuda.is_available() else "mps" if torch.backends.mps.is_available() else "cpu"
        print(f"python {sys.version.split()[0]}, torch {torch.__version__} on {dev}, ffmpeg {ffmpeg()}")
    except Exception as e:  # noqa: BLE001
        print("missing python package:", e)
        ok = False
    print("ready" if ok else "not ready")
    say(ready=ok)
    return 0 if ok else 1


def cmd_fetch():
    """Load both models once: Seed-VC downloads everything it needs into MODELS."""
    from seedvc_runner import SeedVC
    for i, q in enumerate(["speech", "studio"]):
        say(pct=50 + i * 25, msg=f"downloading the {q} model")
        SeedVC(SEEDVC, MODELS, q, log=print)
    import imageio_ffmpeg  # its ffmpeg binary comes with the wheel
    say(pct=100, msg="all models here", done=True, outputs=[])
    return cmd_check()


def slug(s):
    return re.sub(r"[^A-Za-z0-9_-]+", "_", s).strip("_") or "voice"


def cmd_profile(audio, name):
    import dsp
    out = os.path.join(PROFILES, slug(name))
    say(pct=10, msg=f"reading {os.path.basename(audio)}")
    prof = dsp.make_profile(audio, out, name)
    say(pct=100, msg=f"profile {name} ready", done=True, outputs=[out], profile=prof["name"])
    return 0


def cmd_profiles():
    res = []
    if os.path.isdir(PROFILES):
        for d in sorted(os.listdir(PROFILES)):
            p = os.path.join(PROFILES, d, "profile.json")
            if os.path.isfile(p):
                j = json.load(open(p))
                res.append({"id": d, "name": j.get("name", d), "source": j.get("source", ""),
                            "dir": os.path.join(PROFILES, d)})
    print(json.dumps(res))
    return 0


def cmd_run(job_path):
    """job: {"clips": [paths], "profile": id-or-dir, "voice": "convert"|"keep", "quality": "speech"|"studio",
    "export": "individual"|"stitched"|"both", "outdir": path, "clean": true, "steps": 30, "lufs": -16}

    Lossless where it can be: every clip comes out at its own sample rate, bit depth (24-bit for lossy sources) and
    channel count; a video keeps its picture untouched and gets the sound as PCM (in .mov, or .mkv for mkv/webm/avi)."""
    import numpy as np
    import dsp
    job = json.load(open(job_path))
    clips = job["clips"]
    if not clips:
        raise SystemExit("no clips")
    pdir = job["profile"] if os.path.isdir(job["profile"]) else os.path.join(PROFILES, job["profile"])
    prof = json.load(open(os.path.join(pdir, "profile.json")))
    ref = os.path.join(pdir, "voice.wav")
    outdir = job.get("outdir") or os.path.join(os.path.dirname(clips[0]), "Free Voice Convert")
    os.makedirs(outdir, exist_ok=True)
    convert = job.get("voice", "convert") == "convert"
    export = job.get("export", "individual")
    lufs = float(job.get("lufs", prof.get("lufs", -16)))
    steps = int(job.get("steps", 30))
    n = len(clips)

    vc = None
    if convert:
        say(pct=1, msg="loading the voice model")
        from seedvc_runner import SeedVC
        vc = SeedVC(SEEDVC, MODELS, job.get("quality", "speech"), log=print)

    infos, audios, outputs = [], [], []
    t0 = time.time()
    pre = [probe(c) for c in clips]
    total_s = sum(p["dur"] for p in pre)  # the whole length: the counter and the estimate count in these seconds
    done_before = 0.0
    say(pct=2, msg=f"{n} files, {total_s:.1f} s of sound", total_s=round(total_s, 2), done_s=0)
    for i, clip in enumerate(clips):
        base = 2 + 90 * i / n
        span = 90 / n
        info = pre[i]
        if not info["audio"]:
            raise RuntimeError(f"{os.path.basename(clip)} has no sound")
        infos.append(info)
        name = os.path.splitext(os.path.basename(clip))[0]
        say(pct=round(base, 1), msg=f"{i + 1}/{n} {name}: reading ({info['sr']} Hz, {info['ch']} ch, "
                                    f"{info['bits'] or 'lossy'}{'' if info['bits'] in (None, 'float') else '-bit'})", clip=i)
        x, sr = read_audio(clip, info, clean=job.get("clean", True))
        if convert:
            def prog(f, i=i, base=base, span=span, name=name, d=info["dur"], b=done_before):
                say(pct=round(base + span * 0.8 * f, 1), msg=f"{i + 1}/{n} {name}: the voice", clip=i,
                    total_s=round(total_s, 2), done_s=round(b + 0.9 * f * d, 2))
            y, ysr = vc.convert(x.mean(axis=1), sr, ref, steps=steps, progress=prog)
            import librosa
            y = librosa.resample(y, orig_sr=ysr, target_sr=sr, res_type="soxr_vhq").astype(np.float32)
            y = y[: len(x)] if len(y) >= len(x) else np.pad(y, (0, len(x) - len(y)))  # frame by frame, same length
            y = np.repeat(y[:, None], x.shape[1], axis=1)  # the voice in every channel the file had
        else:
            y = x
        say(pct=round(base + span * 0.85, 1), msg=f"{i + 1}/{n} {name}: the sound profile", clip=i)
        y, _ = dsp.match_eq(y, sr, prof["ltas"])
        y = dsp.level(y, sr, lufs)
        audios.append(y)
        if export in ("individual", "both"):
            outputs.append(export_one(clip, info, y, sr, outdir, name))
        done_before += info["dur"]
        # the VU meters: 20 readings a second of the clip before (in) and after (out), in dBFS
        say(pct=round(base + span, 1), msg=f"{i + 1}/{n} {name}: done", clip=i, total_s=round(total_s, 2),
            done_s=round(done_before, 2), vu_in=envelope(x, sr), vu_out=envelope(y, sr))

    if export in ("stitched", "both"):
        say(pct=93, msg="stitching")
        outputs.append(stitch(clips, infos, audios, outdir))
    say(pct=100, msg=f"finished in {time.time() - t0:.0f} s", done=True, outputs=outputs)
    return 0


def envelope(x, sr, rate=20):
    import numpy as np
    m = np.abs(x).max(axis=1) if x.ndim == 2 else np.abs(x)
    hop = max(1, sr // rate)
    n = len(m) // hop
    if n == 0:
        return []
    peaks = m[: n * hop].reshape(n, hop).max(axis=1)
    return [round(float(v), 1) for v in 20 * np.log10(np.maximum(peaks, 1e-5))]


def video_out(clip):
    ext = os.path.splitext(clip)[1].lower()
    return ".mkv" if ext in (".mkv", ".webm", ".avi") else ".mov"


def export_one(clip, info, y, sr, outdir, name):
    bits = info["bits"] or 24
    wav = os.path.join(outdir, f"{name}_fvc.wav")
    write_wav(wav, y, sr, bits)
    if not info["video"]:
        return wav
    out = os.path.join(outdir, f"{name}_fvc{video_out(clip)}")
    # the picture copied bit for bit; the sound as PCM at the source's rate and depth
    subprocess.run([ffmpeg(), "-y", "-v", "error", "-i", clip, "-i", wav, "-map", "0:v:0", "-map", "1:a:0",
                    "-c:v", "copy", "-c:a", PCM.get(bits, "pcm_s24le"), "-shortest", out], check=True)
    os.remove(wav)
    return out


def fit(y, seconds, sr):
    import numpy as np
    n = int(round(seconds * sr))
    return y[:n] if len(y) >= n else np.pad(y, ((0, n - len(y)), (0, 0)))


def stitch(clips, infos, audios, outdir):
    """One file in the list's order, in the first clip's sound format (others resampled to it, soxr very high)."""
    import numpy as np
    import librosa
    sr, ch = infos[0]["sr"], max(i["ch"] for i in infos)
    bits = infos[0]["bits"] or 24
    same = []
    for a, i in zip(audios, infos):
        if i["sr"] != sr:
            a = librosa.resample(a.T, orig_sr=i["sr"], target_sr=sr, res_type="soxr_vhq").T.astype(np.float32)
        if a.shape[1] < ch:
            a = np.repeat(a[:, :1], ch, axis=1) if a.shape[1] == 1 else np.pad(a, ((0, 0), (0, ch - a.shape[1])))
        same.append(a)
    any_video = any(i["video"] for i in infos)
    if not any_video:
        fade = int(0.005 * sr)  # 5 ms at each joint so no click
        parts = []
        for y in same:
            y = y.copy()
            if len(y) > 2 * fade:
                y[:fade] *= np.linspace(0, 1, fade)[:, None]
                y[-fade:] *= np.linspace(1, 0, fade)[:, None]
            parts.append(y)
        out = os.path.join(outdir, "stitched_fvc.wav")
        write_wav(out, np.concatenate(parts), sr, bits)
        return out
    vids = [i for i in infos if i["video"]]
    first = vids[0]
    durs = [i["dur"] if i["dur"] > 0 else len(a) / sr for i, a in zip(infos, same)]
    wav = os.path.join(outdir, "stitched_fvc_audio.wav")
    write_wav(wav, np.concatenate([fit(a, d, sr) for a, d in zip(same, durs)]), sr, bits)
    ext = video_out(clips[0])
    out = os.path.join(outdir, "stitched_fvc" + ext)
    acodec = PCM.get(bits, "pcm_s24le")
    # lossless join when every clip is video with the same codec, size and frame rate: the picture is not touched
    if len(vids) == len(infos) and all((i["vcodec"], i["w"], i["h"], round(i["fps"], 2)) ==
                                       (first["vcodec"], first["w"], first["h"], round(first["fps"], 2)) for i in infos):
        lst = os.path.join(outdir, "stitched_fvc_list.txt")
        with open(lst, "w", encoding="utf-8") as f:
            for c in clips:
                f.write("file '" + os.path.abspath(c).replace("'", "'\\''") + "'\n")
        r = subprocess.run([ffmpeg(), "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-i", wav,
                            "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", acodec, "-shortest", out])
        os.remove(lst)
        if r.returncode == 0:
            os.remove(wav)
            return out
        print("lossless join failed; the picture is re-encoded")
    W, H, FPS = first["w"] - first["w"] % 2, first["h"] - first["h"] % 2, first["fps"]
    cmd, filt = [ffmpeg(), "-y", "-v", "error"], []
    for k, (clip, info, d) in enumerate(zip(clips, infos, durs)):
        if info["video"]:
            cmd += ["-i", clip]
        else:  # a sound without picture gets black picture of its length
            cmd += ["-f", "lavfi", "-t", f"{d:.3f}", "-i", f"color=c=black:s={W}x{H}:r={FPS}"]
        filt.append(f"[{k}:v]scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2,"
                    f"setsar=1,fps={FPS},format=yuv420p,trim=duration={d:.3f},setpts=PTS-STARTPTS[v{k}]")
    n = len(clips)
    filt.append("".join(f"[v{k}]" for k in range(n)) + f"concat=n={n}:v=1:a=0[v]")
    # clips that differ must be re-encoded: near-lossless H.264 (crf 12)
    cmd += ["-i", wav, "-filter_complex", ";".join(filt), "-map", "[v]", "-map", f"{n}:a",
            "-c:v", "libx264", "-crf", "12", "-preset", "slow", "-c:a", acodec, "-shortest", out]
    subprocess.run(cmd, check=True)
    os.remove(wav)
    return out


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    c = argv[0]
    try:
        if c == "check":
            return cmd_check()
        if c == "fetch":
            return cmd_fetch()
        if c == "profile":
            return cmd_profile(argv[1], argv[2] if len(argv) > 2 else os.path.splitext(os.path.basename(argv[1]))[0])
        if c == "profiles":
            return cmd_profiles()
        if c == "run":
            return cmd_run(argv[1])
        if c == "version":
            print(VERSION)
            return 0
        print("unknown command:", c)
        return 2
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        say(error=f"{type(e).__name__}: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
