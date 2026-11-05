# 可选素材处理

应用构建直接使用已提交的 `Assets/`。下列命令仅用于重新处理或核对素材，不是普通用户安装步骤。

## 音频校准

安装 Python 3 与 `ffmpeg` 后，在仓库根目录运行：

```sh
python3 -B Tools/prepare-audio.py
```

默认从已提交的 `materials/voice-reference/` 生成应用音频。重新从原视频处理时，另备 `materials/cuts.json` 指定的原视频音轨，并显式提供 DeepFilterNet 可执行程序：

```sh
python3 -B Tools/prepare-audio.py --reprocess-source --denoiser /path/to/deep-filter
```

缺少原音轨或降噪程序时，重新提取流程不能运行；正常构建不受影响。

## 本地转写复核

另行安装 Python 的 `torch`、`openai-whisper` 及 `ffmpeg`，自行准备 Whisper 模型权重，运行：

```sh
python3 Tools/transcribe.py path/to/audio.wav --model-file /path/to/model.pt
python3 Tools/audit-final-audio.py --model-file /path/to/model.pt
```

转写结果仅供人工复核，不会自动替换应用字幕。脚本不读取个人目录中的模型，也不调用云端转写服务。

## 动画素材

重新导出道具图格需要 Pillow：

```sh
python3 -B Tools/export-action-assets.py
```

来源与裁切范围见 `materials/sources.json` 和 `materials/cuts.json`；素材使用范围见 [素材许可说明](../ASSETS_LICENSE.md)。
