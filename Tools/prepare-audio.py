"""Level active speech from the checked-in, reviewed voice references.

Normal use needs only ffmpeg. --reprocess-source also requires the source video
and DeepFilterNet, and rebuilds the denoised references first.
"""
import argparse
import array
import json
from pathlib import Path
import re
import statistics
import subprocess
import wave
from audio_gain import level_speech, measure, speech_stats

ROOT = Path(__file__).resolve().parents[1]
TMP = ROOT / 'tmp'
REFERENCE = ROOT / 'materials/voice-reference'
DENOISE = 'DeepFilterNet v0.5.6; compensated delay; maximum attenuation 35 dB; input headroom -6 dB; highpass 70 Hz'

def run(*args):
    subprocess.run(list(map(str, args)), check=True)

def rebuild_reference(cut, denoiser):
    name = f"{cut['id']:02d}.wav"
    duration = cut['end'] - cut['start']
    original = ROOT / 'materials/clips-original' / name
    original.parent.mkdir(exist_ok=True)
    source = ROOT / 'materials' / cut['sourceFile']
    ffmpeg = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y']
    run(*ffmpeg, '-i', source, '-ss', cut['start'], '-t', duration,
        '-vn', '-ar', 44100, '-ac', 1, '-c:a', 'pcm_s16le', original)
    context_start = max(0, cut['start'] - 1.5)
    before = cut['start'] - context_start
    model_input = TMP / f'context-{name}'
    clean_dir = TMP / 'deepfilter'
    clean_dir.mkdir(exist_ok=True)
    run(*ffmpeg, '-i', source, '-ss', context_start, '-t', duration + before + 1.5,
        '-vn', '-ac', 1, '-af', 'volume=0.5,highpass=f=70', '-ar', 48000,
        '-c:a', 'pcm_s16le', model_input)
    run(denoiser, '-D', '-a', 35, '-o', clean_dir, model_input)
    cleaned = clean_dir / model_input.name
    raw = TMP / f'raw-{name}'
    run(*ffmpeg, '-i', cleaned, '-ss', before, '-t', duration,
        '-ar', 44100, '-ac', 1, '-c:a', 'pcm_s16le', raw)
    with wave.open(str(raw)) as audio:
        samples = array.array('h', audio.readframes(audio.getnframes()))
    if not any(samples):
        raise ValueError(f"Silent clip: {cut['id']}")
    ramp = min(220, len(samples) // 2)
    for i in range(ramp):
        samples[i] = round(samples[i] * i / ramp)
        samples[-i-1] = round(samples[-i-1] * i / ramp)
    with wave.open(str(raw), 'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(44100)
        audio.writeframes(samples.tobytes())
    probe = subprocess.run(['ffmpeg', '-hide_banner', '-i', str(raw), '-af',
        'loudnorm=I=-20:TP=-1.5:LRA=7:print_format=json', '-f', 'null', '-'],
        capture_output=True, text=True, check=True)
    stats = json.loads(re.findall(r'\{[^{}]*"input_i"[^{}]*\}', probe.stderr, re.S)[-1])
    normalization = ('loudnorm=I=-20:TP=-1.5:LRA=7:linear=true'
        f":measured_I={stats['input_i']}:measured_TP={stats['input_tp']}"
        f":measured_LRA={stats['input_lra']}:measured_thresh={stats['input_thresh']}"
        f":offset={stats['target_offset']}")
    run(*ffmpeg, '-i', raw, '-af', normalization,
        '-ar', 44100, '-ac', 1, '-c:a', 'pcm_s16le', REFERENCE / name)
    for path in (raw, model_input, cleaned):
        path.unlink()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reprocess-source', action='store_true')
    parser.add_argument('--denoiser', type=Path,
                        help='Path to a DeepFilterNet executable; required with --reprocess-source')
    args = parser.parse_args()
    if args.reprocess_source and (not args.denoiser or not args.denoiser.is_file()):
        parser.error('--reprocess-source requires an existing --denoiser executable')
    TMP.mkdir(exist_ok=True)
    REFERENCE.mkdir(exist_ok=True)
    cuts = json.loads((ROOT / 'materials/cuts.json').read_text())
    order = [3, 1, 2, 5, 4, 6]
    if sorted(c['id'] for c in cuts) != sorted(order):
        raise ValueError('Unexpected clip IDs in cuts.json')
    cuts.sort(key=lambda c: order.index(c['id']))
    profile = json.loads((ROOT / 'materials/audio-profile.json').read_text())
    for cut in cuts:
        if args.reprocess_source or not (REFERENCE / f"{cut['id']:02d}.wav").exists():
            if not args.denoiser or not args.denoiser.is_file():
                parser.error('Missing reference audio requires an existing --denoiser executable and original source audio')
            rebuild_reference(cut, args.denoiser)
    reference_stats = [speech_stats(REFERENCE / f"{c['id']:02d}.wav",
        profile['frameMS'], profile['gateBelowPeakDB']) for c in cuts]
    baseline = statistics.median(s['activeRMSDBFS'] for s in reference_stats)
    target = baseline + profile['gainDB']
    catalog, sources, measurements = [], [], []
    for cut, reference in zip(cuts, reference_stats):
        name = f"{cut['id']:02d}.wav"
        stats = level_speech(REFERENCE / name, ROOT / 'Assets/Clips' / name, target, profile, TMP)
        if abs(stats['duration'] - reference['duration']) > 1 / 44100 or stats['clippedSamples']:
            raise ValueError(f'Timing or clipping verification failed: {name}')
        measurements.append({'id': cut['id'], 'label': cut['label'], **stats,
            'referenceActiveRMSDBFS': reference['activeRMSDBFS'],
            'referenceMedianActiveRMSDBFS': baseline, 'targetActiveRMSDBFS': target,
            'referenceGainDB': stats['activeRMSDBFS'] - reference['activeRMSDBFS'],
            'denoise': DENOISE})
        catalog.append({'id': cut['id'], 'label': cut['label'], 'file': name, 'duration': stats['duration']})
        sources.append({**cut, 'file': name, 'sourceStart': cut['start'],
                        'sourceEnd': cut['end'], 'duration': stats['duration']})
    (ROOT / 'Assets/clips.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    metadata = json.loads((ROOT / 'materials/sources.json').read_text())
    metadata.update(processing={**metadata.get('processing', {}), 'denoise': DENOISE,
        'leveling': 'Active speech RMS matching, pause exclusion, compression, oversampled transient peak protection',
        **profile, 'referenceMedianActiveRMSDBFS': baseline, 'targetActiveRMSDBFS': target}, audio=sources)
    (ROOT / 'materials/sources.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    (ROOT / 'verification/audio.json').write_text(json.dumps(measurements, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(measurements, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
