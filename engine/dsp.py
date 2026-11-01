"""dsp.py: the sound profile and the equalizer, without any model.

A profile is what makes every clip sound the same:
  - the voice reference (the clip Seed-VC copies the voice from: a clean, ideally studio-enhanced recording),
  - its long-term average spectrum (LTAS) over voiced frames, in 1/6-octave bands from 50 Hz to 18 kHz,
  - its loudness target (LUFS).
Every converted clip is measured the same way, the difference becomes a smooth linear-phase EQ curve (limited to
+-12 dB), then the clip is levelled to the profile's loudness and its peaks held under -1 dBFS.
"""
import json

import numpy as np
import soundfile as sf
from scipy import signal

SR = 48000
BANDS = np.geomspace(50, 18000, 52)  # 1/6-octave-ish centres


def voiced_frames(x, sr, frame=2048, hop=1024, gate_db=-35):
    """Frames that hold the voice: louder than (loudest - |gate|) dB."""
    if len(x) < frame:
        x = np.pad(x, (0, frame - len(x)))
    n = 1 + (len(x) - frame) // hop
    idx = np.arange(frame)[None, :] + hop * np.arange(n)[:, None]
    fr = x[idx] * np.hanning(frame)[None, :]
    rms = 20 * np.log10(np.sqrt((fr ** 2).mean(axis=1)) + 1e-9)
    keep = rms > rms.max() + gate_db
    return fr[keep] if keep.any() else fr


def mono(x):
    return x.mean(axis=1) if x.ndim == 2 else x


def ltas(x, sr):
    """Long-term average spectrum in dB at BANDS (voiced frames only), of the channels mixed."""
    fr = voiced_frames(mono(x), sr)
    spec = (np.abs(np.fft.rfft(fr, axis=1)) ** 2).mean(axis=0)
    freqs = np.fft.rfftfreq(fr.shape[1], 1 / sr)
    out = []
    for c in BANDS:
        lo, hi = c / 2 ** (1 / 12), c * 2 ** (1 / 12)
        m = (freqs >= lo) & (freqs < hi)
        out.append(10 * np.log10(spec[m].mean() + 1e-12) if m.any() else -120.0)
    out = np.array(out)
    return out - out[(BANDS > 300) & (BANDS < 3000)].mean()  # level-free shape


def loudness(x, sr):
    import pyloudnorm as pyln
    if len(x) < sr // 2:
        x = np.pad(x, ((0, sr // 2 - len(x)),) + (((0, 0),) if x.ndim == 2 else ()))
    if x.ndim == 2 and x.shape[1] > 5:  # BS.1770 weights only up to 5 channels here: measure the mix
        x = x.mean(axis=1)
    return float(pyln.Meter(sr).integrated_loudness(x))


def match_eq(x, sr, target_ltas, max_db=12.0, smooth=3):
    """EQ x so its LTAS follows target_ltas. Linear phase, delay removed."""
    cur = ltas(x, sr)
    diff = np.clip(np.asarray(target_ltas) - cur, -max_db, max_db)
    if smooth > 1:
        k = np.ones(smooth) / smooth
        diff = np.convolve(np.pad(diff, smooth // 2, mode="edge"), k, mode="valid")[: len(BANDS)]
    # above the reference's useful range (e.g. a 22 kHz model has nothing over 11 kHz) do not boost hiss
    nyq = sr / 2
    f = np.concatenate([[0], BANDS[BANDS < nyq * 0.98], [nyq]]) / nyq
    g = np.concatenate([[diff[0]], diff[BANDS < nyq * 0.98], [min(diff[-1], 0)]])
    gains = 10 ** (g / 20)
    ntap = 2047 if sr <= 50000 else 4095  # the same resolution in Hz at 88.2/96 kHz
    taps = signal.firwin2(ntap, f, gains)
    h = ntap // 2
    if x.ndim == 2:  # the same curve on every channel: the stereo picture is kept
        y = np.stack([signal.fftconvolve(x[:, c], taps, mode="full")[h:h + len(x)] for c in range(x.shape[1])], axis=1)
    else:
        y = signal.fftconvolve(x, taps, mode="full")[h:h + len(x)]
    return y.astype(np.float32), diff


def limit(x, ceiling_db=-1.0, sr=SR):
    """A gentle look-ahead peak limiter (5 ms attack, 80 ms release)."""
    c = 10 ** (ceiling_db / 20)
    peak = np.abs(x).max(axis=1) if x.ndim == 2 else np.abs(x)  # one gain for all channels
    if peak.max() <= c:
        return x
    from scipy.ndimage import minimum_filter1d
    need = np.minimum(1.0, c / np.maximum(peak, 1e-9))
    la = int(0.005 * sr)
    g = minimum_filter1d(need, size=2 * la + 1)  # the gain is already down when the peak arrives
    # release: the gain climbs back over ~80 ms (a running max of the decaying envelope, done per 1 ms block)
    blk = max(1, sr // 1000)
    nb = -(-len(g) // blk)
    gb = np.pad(g, (0, nb * blk - len(g)), constant_values=1.0).reshape(nb, blk).min(axis=1)
    a = np.exp(-blk / (0.08 * sr))
    env = np.empty(nb)
    cur = 1.0
    for i, v in enumerate(gb):
        cur = v if v < cur else a * cur + (1 - a) * v
        env[i] = cur
    env = np.minimum(np.repeat(env, blk)[: len(g)], g)
    return (x * (env[:, None] if x.ndim == 2 else env)).astype(np.float32)


def level(x, sr, lufs=-16.0, ceiling_db=-1.0):
    now = loudness(x, sr)
    if np.isfinite(now):
        x = x * 10 ** ((lufs - now) / 20)
    return limit(x.astype(np.float32), ceiling_db, sr)


def make_profile(ref_path, out_dir, name, lufs=-16.0):
    """Store a profile: the reference voice (48 kHz mono, at most 25 s of its loudest speech) + its LTAS."""
    import os
    import librosa
    x, _ = librosa.load(ref_path, sr=SR, mono=True)
    if len(x) > SR * 25:  # keep the 25 s window with the most voice
        win, best, best_e = SR * 25, 0, -1
        for s in range(0, len(x) - win, SR):
            e = float((x[s:s + win] ** 2).sum())
            if e > best_e:
                best, best_e = s, e
        x = x[best:best + win]
    os.makedirs(out_dir, exist_ok=True)
    voice = os.path.join(out_dir, "voice.wav")
    sf.write(voice, x / (np.abs(x).max() + 1e-9) * 0.9, SR, subtype="PCM_24")
    prof = {"name": name, "source": os.path.basename(ref_path), "lufs": lufs,
            "bands": BANDS.round(1).tolist(), "ltas": ltas(x, SR).round(2).tolist(), "version": 1}
    with open(os.path.join(out_dir, "profile.json"), "w") as f:
        json.dump(prof, f, indent=1)
    return prof
