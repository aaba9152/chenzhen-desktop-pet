"""Export the six equal sprite cells without changing their illustrated pixels."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
sheet = Image.open(root / 'materials/action-sprite-source.png').convert('RGBA')
assert sheet.size == (1536, 1024)
output = root / 'Assets/Actions'
output.mkdir(exist_ok=True)
for index, name in enumerate(('bowl', 'noodles', 'coffee', 'soda', 'splash', 'bubbles')):
    x, y = index % 3 * 512, index // 3 * 512
    sheet.crop((x, y, x + 512, y + 512)).save(output / (name + '.png'))

# The beef button was generated separately from the original six-cell sheet.
beef = Image.open(root / 'materials/beef-icon-source.png').convert('RGBA')
beef.resize((512, 512), Image.Resampling.LANCZOS).save(output / 'beef.png')
