"""Cross-check the six packaged clips with a user-supplied local Whisper model."""
import array
import argparse
import json
from pathlib import Path
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', default=str(ROOT / 'tmp/audio-review'))
parser.add_argument('--model-file', type=Path, required=True,
                    help='Path to installed Whisper model weights')
args = parser.parse_args()
if not args.model_file.expanduser().is_file():
    parser.error('--model-file must point to an installed Whisper model')
WORK = Path(args.output).resolve()
WORK.mkdir(exist_ok=True)
catalog = json.loads((ROOT / 'Assets/clips.json').read_text())
combined = array.array('h', [0] * 16000)
index = []
for clip in catalog:
    pcm = subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error',
        '-i', str(ROOT / 'Assets/Clips' / clip['file']), '-ar', '16000', '-ac', '1',
        '-f', 's16le', '-'], capture_output=True, check=True).stdout
    samples = array.array('h', pcm)
    start = len(combined) / 16000
    combined.extend(samples)
    index.append({'id': clip['id'], 'expected': clip['label'], 'start': start,
                  'end': len(combined) / 16000})
    combined.extend([0] * 48000)
wav = WORK / 'final-six-audit.wav'
with wave.open(str(wav), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(16000)
    output.writeframes(combined.tobytes())
(WORK / 'final-six-index.json').write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n')
transcript = WORK / 'final-six-transcript.json'
subprocess.run([sys.executable, str(ROOT / 'Tools/transcribe.py'), str(wav),
                '--model-file', str(args.model_file.expanduser()),
                '--output', str(transcript)], check=True)
result = json.loads(transcript.read_text())
result['clip_intervals'] = index
transcript.write_text(
    json.dumps(result, ensure_ascii=False, indent=2) + '\n')
