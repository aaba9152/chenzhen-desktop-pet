"""Transcribe an audio file with a user-supplied local Whisper model."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('audio', type=Path)
parser.add_argument('--model', choices=['base', 'small'], default='base')
parser.add_argument('--first-seconds', type=float)
parser.add_argument('--model-file', type=Path, required=True, help='Path to installed Whisper model weights')
parser.add_argument('--output', type=Path, help='Output JSON path; defaults beside the input audio')
args = parser.parse_args()
model_file = args.model_file.expanduser()
if not model_file.is_file():
    parser.error(f'Model weights not found: {model_file}; use --model-file to select an installed model')
import torch
import whisper
torch.set_num_threads(6)
model = whisper.load_model(str(model_file), device='cpu')
audio = whisper.load_audio(str(args.audio))
if args.first_seconds:
    audio = audio[:round(args.first_seconds * 16000)]
result = model.transcribe(audio, language='zh', fp16=False, word_timestamps=True, verbose=False, temperature=0, condition_on_previous_text=False)
output = args.output or args.audio.with_suffix('.transcript.json' if args.model == 'base' else '.small.transcript.json')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
for segment in result['segments']:
    print(f"{segment['start']:.2f}-{segment['end']:.2f} {segment['text']}", flush=True)
print(output, flush=True)
