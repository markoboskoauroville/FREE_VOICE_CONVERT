"""seedvc_runner.py: Seed-VC (Plachtaa/seed-vc, GPL-3.0) loaded once, converting many clips.

The conversion loop is Seed-VC's own inference.py main(), kept as close to the original as possible and turned into a
function that returns the samples instead of writing a file. Two models:

  speech  : DiT_seed_v2_uvit_whisper_small_wavenet_bigvgan_pruned (22.05 kHz, the speech model, no pitch tracking)
  studio  : DiT_seed_v2_uvit_whisper_base_f0_44k (44.1 kHz, pitch-tracked; the speaker's melody is kept and moved to
            the profile voice's median pitch with auto_f0_adjust)

Everything Seed-VC downloads lands in <models>/checkpoints (its own relative paths, resolved against the models folder,
because this module chdirs there before importing it).
"""
import os
import sys
import time
from types import SimpleNamespace

import numpy as np


class SeedVC:
    def __init__(self, seedvc_dir, models_dir, quality="speech", log=print):
        os.makedirs(models_dir, exist_ok=True)
        os.chdir(models_dir)  # Seed-VC's './checkpoints' paths now resolve inside the models folder
        os.environ["HF_HUB_CACHE"] = os.path.join(models_dir, "checkpoints", "hf_cache")
        if seedvc_dir not in sys.path:
            sys.path.insert(0, seedvc_dir)
        import torch  # noqa: F401
        import inference as inf  # Seed-VC's inference.py

        self.inf = inf
        self.torch = inf.torch
        self.device = inf.device
        self.quality = quality
        self.f0 = quality == "studio"
        fp16 = self.device.type == "cuda"
        args = SimpleNamespace(f0_condition=self.f0, checkpoint=None, config=None, fp16=fp16)
        t = time.time()
        log(f"loading the {quality} model on {self.device.type}")
        (self.model, self.semantic_fn, self.f0_fn, self.vocoder_fn, self.campplus, self.mel_fn,
         self.mel_args) = inf.load_models(args)
        self.sr = self.mel_args["sampling_rate"]
        log(f"model ready in {time.time() - t:.1f} s ({self.sr} Hz)")
        self._ref_key = None

    # --- the reference voice (the profile), prepared once per profile ---
    def _prepare_ref(self, ref_path):
        if self._ref_key == ref_path:
            return
        import librosa
        torch, inf = self.torch, self.inf
        sr = self.sr
        ref = librosa.load(ref_path, sr=sr)[0]
        ref = torch.tensor(ref[: sr * 25]).unsqueeze(0).float().to(self.device)
        ref16 = inf.torchaudio.functional.resample(ref, sr, 16000)
        S_ori = self.semantic_fn(ref16)
        mel2 = self.mel_fn(ref.float())
        feat2 = inf.torchaudio.compliance.kaldi.fbank(ref16, num_mel_bins=80, dither=0, sample_frequency=16000)
        feat2 = feat2 - feat2.mean(dim=0, keepdim=True)
        style2 = self.campplus(feat2.unsqueeze(0))
        F0_ori = None
        if self.f0:
            F0_ori = torch.from_numpy(self.f0_fn(ref16[0], thred=0.03)).to(self.device)[None]
        target2_lengths = torch.LongTensor([mel2.size(2)]).to(mel2.device)
        prompt_condition, *_ = self.model.length_regulator(S_ori, ylens=target2_lengths, n_quantizers=3, f0=F0_ori)
        self.ref = SimpleNamespace(mel2=mel2, style2=style2, F0_ori=F0_ori, prompt=prompt_condition)
        self._ref_key = ref_path

    # --- one clip: samples in (any rate, mono float32), samples out at self.sr ---
    def convert(self, wave, wave_sr, ref_path, steps=30, cfg_rate=0.7, progress=None):
        import librosa
        torch, inf = self.torch, self.inf
        self._prepare_ref(ref_path)
        sr = self.sr
        hop = 256 if not self.f0 else 512
        max_context_window = sr // hop * 30
        overlap_frame_len = 16
        overlap_wave_len = overlap_frame_len * hop
        if wave_sr != sr:
            wave = librosa.resample(wave, orig_sr=wave_sr, target_sr=sr)
        src = torch.tensor(wave).unsqueeze(0).float().to(self.device)
        w16 = inf.torchaudio.functional.resample(src, sr, 16000)

        if w16.size(-1) <= 16000 * 30:
            S_alt = self.semantic_fn(w16)
        else:  # Seed-VC's 30 s windows with 5 s overlap
            ov = 5
            parts, buffer, done = [], None, 0
            while done < w16.size(-1):
                if buffer is None:
                    chunk = w16[:, done:done + 16000 * 30]
                else:
                    chunk = torch.cat([buffer, w16[:, done:done + 16000 * (30 - ov)]], dim=-1)
                S = self.semantic_fn(chunk)
                parts.append(S if done == 0 else S[:, 50 * ov:])
                buffer = chunk[:, -16000 * ov:]
                done += 30 * 16000 if done == 0 else chunk.size(-1) - 16000 * ov
            S_alt = torch.cat(parts, dim=1)

        mel = self.mel_fn(src.float())
        target_lengths = torch.LongTensor([mel.size(2)]).to(mel.device)  # length kept: frame by frame

        shifted_f0 = None
        if self.f0:
            F0_alt = torch.from_numpy(self.f0_fn(w16[0], thred=0.03)).to(self.device)[None]
            F0_ori = self.ref.F0_ori
            log_alt = torch.log(F0_alt + 1e-5)
            shifted = log_alt.clone()
            v_alt, v_ori = F0_alt[F0_alt > 1], F0_ori[F0_ori > 1]
            if len(v_alt) and len(v_ori):  # auto_f0_adjust: the speaker's melody at the profile voice's pitch
                shifted[F0_alt > 1] = (log_alt[F0_alt > 1] - torch.median(torch.log(v_alt + 1e-5))
                                       + torch.median(torch.log(v_ori + 1e-5)))
            shifted_f0 = torch.exp(shifted)

        cond, *_ = self.model.length_regulator(S_alt, ylens=target_lengths, n_quantizers=3, f0=shifted_f0)
        mel2, style2, prompt = self.ref.mel2, self.ref.style2, self.ref.prompt
        max_source_window = max_context_window - mel2.size(2)
        processed, chunks, previous = 0, [], None
        total = cond.size(1)
        use_fp16 = self.device.type == "cuda"
        while processed < total:
            chunk_cond = cond[:, processed:processed + max_source_window]
            last = processed + max_source_window >= total
            cat = torch.cat([prompt, chunk_cond], dim=1)
            with torch.autocast(device_type=self.device.type, dtype=torch.float16 if use_fp16 else torch.float32,
                                enabled=use_fp16):
                vc = self.model.cfm.inference(cat, torch.LongTensor([cat.size(1)]).to(mel2.device), mel2, style2,
                                              None, steps, inference_cfg_rate=cfg_rate)
                vc = vc[:, :, mel2.size(-1):]
            w = self.vocoder_fn(vc.float()).squeeze()[None, :]
            if processed == 0:
                if last:
                    chunks.append(w[0].cpu().numpy())
                    break
                chunks.append(w[0, :-overlap_wave_len].cpu().numpy())
                previous = w[0, -overlap_wave_len:]
                processed += vc.size(2) - overlap_frame_len
            elif last:
                chunks.append(inf.crossfade(previous.cpu().numpy(), w[0].cpu().numpy(), overlap_wave_len))
                break
            else:
                chunks.append(inf.crossfade(previous.cpu().numpy(), w[0, :-overlap_wave_len].cpu().numpy(),
                                            overlap_wave_len))
                previous = w[0, -overlap_wave_len:]
                processed += vc.size(2) - overlap_frame_len
            if progress:
                progress(min(processed / total, 1.0))
        out = np.concatenate(chunks).astype(np.float32)
        if progress:
            progress(1.0)
        return out, sr
