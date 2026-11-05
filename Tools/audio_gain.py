"""Level active speech, excluding pauses, with compression and peak protection."""
import array
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile
import wave

def measure(path):
    result = subprocess.run(['ffmpeg', '-hide_banner', '-i', str(path), '-af',
        'loudnorm=I=-14:TP=-1.5:LRA=7:print_format=json', '-f', 'null', '-'],
        capture_output=True, text=True, check=True)
    return json.loads(re.findall(r'\{[^{}]*"input_i"[^{}]*\}', result.stderr, re.S)[-1])

def speech_stats(path, frame_ms=20, gate_below_peak_db=20, active_frames=None):
    with wave.open(str(path)) as audio:
        if audio.getnchannels() != 1 or audio.getsampwidth() != 2:
            raise ValueError('Expected mono 16-bit PCM WAV')
        rate = audio.getframerate()
        samples = array.array('h', audio.readframes(audio.getnframes()))
    width = round(rate * frame_ms / 1000)
    frames = [(sum(x*x for x in samples[i:i+width]), len(samples[i:i+width]))
              for i in range(0, len(samples), width)]
    max_power = max(total / count for total, count in frames)
    if max_power == 0:
        raise ValueError('Silent audio')
    gate = max_power * 10 ** (-gate_below_peak_db / 10)
    # Freeze the reference's speech mask during gain adjustment. Re-detecting
    # after compression can turn quiet tails into speech and destabilize the meter.
    if active_frames is None:
        active_frames = [i for i, (total, count) in enumerate(frames) if total / count >= gate]
    active = [frames[i] for i in active_frames]
    active_count = sum(count for _, count in active)
    active_power = sum(total for total, _ in active) / active_count
    rms = sum(x*x for x in samples) / len(samples)
    return {'activeRMSDBFS': 10 * math.log10(active_power / 32768**2),
            'activeFrames': active_frames,
            'rmsDBFS': 10 * math.log10(rms / 32768**2),
            'activeFraction': active_count / len(samples),
            'duration': len(samples) / rate,
            'peak': max(abs(x) for x in samples) / 32768,
            'clippedSamples': sum(abs(x) >= 32767 for x in samples)}

def level_speech(source, destination, target_dbfs, profile, work_dir):
    source, destination = Path(source), Path(destination)
    if source.resolve() == destination.resolve():
        raise ValueError('Source and destination must differ')
    with tempfile.TemporaryDirectory(prefix='speech-level-', dir=work_dir) as folder:
        reference = speech_stats(source, profile['frameMS'], profile['gateBelowPeakDB'])
        mask = reference['activeFrames']
        compressed = Path(folder) / 'compressed.wav'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
            '-i', str(source), '-af', profile['compressor'], '-ac', '1', '-ar', '44100',
            '-c:a', 'pcm_s16le', str(compressed)], check=True)
        stats = speech_stats(compressed, profile['frameMS'], profile['gateBelowPeakDB'], mask)
        gain = 10 ** ((target_dbfs - stats['activeRMSDBFS']) / 20)
        ceiling = 10 ** (profile['truePeakCeilingDBTP'] / 20)
        for attempt in range(16):
            filters = (f'aresample=192000,volume={gain},'
                       f'alimiter=limit={ceiling}:attack=5:release=30:level=false:latency=true,'
                       'aresample=44100')
            subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                '-i', str(compressed), '-af', filters, '-ac', '1', '-c:a', 'pcm_s16le',
                str(destination)], check=True)
            actual = speech_stats(destination, profile['frameMS'], profile['gateBelowPeakDB'], mask)
            error = target_dbfs - actual['activeRMSDBFS']
            if abs(error) <= 0.10:
                loudness = measure(destination)
                if float(loudness['input_tp']) > profile['truePeakCeilingDBTP'] + 0.15:
                    raise ValueError('Output true peak exceeds protection ceiling')
                return {**actual, 'gainAfterCompressionDB': 20 * math.log10(gain),
                        'matchingIterations': attempt + 1, 'integratedLUFS': float(loudness['input_i']),
                        'truePeakDBTP': float(loudness['input_tp'])}
            gain *= 10 ** (error / 20)
    raise ValueError(f"Cannot reach speech level for {source.name}: target={target_dbfs:.3f}, actual={actual['activeRMSDBFS']:.3f}")

if __name__ == '__main__':
    import sys
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python3 Tools/audio_gain.py WAV')
    print(json.dumps({**speech_stats(sys.argv[1]), **measure(sys.argv[1])}, indent=2))
