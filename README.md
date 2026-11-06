# 陈震桌宠

<img src="Assets/face.png" alt="陈震桌宠人物" width="220">

陈震桌宠是一款在桌面上播放六句原声的单人物应用。点击人物听台词，拖动摆放，或用下方的卡通按钮投喂。播放时会显示字幕和轻微弹动；启动和闲置时保持安静。支持 **Windows 10/11 x64** 和 **macOS 14+ Apple Silicon**。

## 下载与安装

当前发布版本为 **1.3.4**。从 [发布页面](https://github.com/aaba9152/chenzhen-desktop-pet/releases/tag/v1.3.4) 下载对应系统的成品。

| 系统 | 下载 | 安装 |
| --- | --- | --- |
| Windows 10/11 x64 | [Windows ZIP](https://github.com/aaba9152/chenzhen-desktop-pet/releases/download/v1.3.4/ChenzhenPet-Windows-x64-1.3.4.zip) | 解压后双击 `ChenzhenPet.exe`。运行环境已包含在程序中。 |
| macOS 14+ Apple Silicon | [macOS DMG](https://github.com/aaba9152/chenzhen-desktop-pet/releases/download/v1.3.4/ChenzhenPet-1.3.4.dmg) | 打开 DMG，将“陈震桌宠”拖到“应用程序”，再从“应用程序”启动。 |

[macOS 首次打开教程](docs/macos-install.md)包含系统提示的图文步骤。安装包的 SHA-256 见 [校验清单](https://github.com/aaba9152/chenzhen-desktop-pet/releases/download/v1.3.4/SHA256SUMS-1.3.4.txt)。Windows 程序没有商业代码签名证书；macOS 应用采用本地签名，尚未经过 Apple 公证。

## 操作

- **单击人物**：按下文顺序循环播放六句原声。播放中再次点击会立即切换到下一句。
- **拖动人物**：移动桌宠，不触发台词。拖动右下角的斜线标记可调整大小。
- **台词清单**：点击人物旁的箭头展开，点选任意一句播放；再次点击箭头收起。
- **右键菜单**：挑选台词、更换人像、调整音量或人物大小、移回屏幕右下角，以及退出桌宠。
- **投喂按钮**：点击人物下方的按钮，或将按钮拖到人物区域后松开，播放对应动画与回应。拖到人物区域外会返回按钮。

默认人物宽度为 260、音量为 50%，位置在屏幕右下角。大小、音量、位置和人像选择会自动保存。Windows 可从系统托盘打开菜单，macOS 可从菜单栏打开菜单。完整操作见 [Windows 使用说明](Windows/使用说明.txt)和 [macOS 使用说明](使用说明.txt)。

### 三种人像

右键人物，在“更换人像”中选择：

| 黄色长发 | 黑色长发 | 短发 |
| --- | --- | --- |
| <img src="Assets/Portraits/portrait-near.png" width="150" alt="黄色长发人像"> | <img src="Assets/Portraits/portrait-smile.png" width="150" alt="黑色长发人像"> | <img src="Assets/face.png" width="150" alt="短发人像"> |

### 四种卡通互动

| 动作 | 预览 |
| --- | --- |
| 吃牛肉 | <img src="docs/previews/noodles.gif" width="180" alt="吃牛肉动画"> |
| 喝咖啡 | <img src="docs/previews/coffee.gif" width="180" alt="喝咖啡动画"> |
| 喝苏打水 | <img src="docs/previews/soda.gif" width="180" alt="喝苏打水动画"> |
| 咖啡浇头 | <img src="docs/previews/pour.gif" width="180" alt="咖啡浇头动画"> |

吃牛肉通常回应“牛肉面不要面”，咖啡浇头回应“这你受得了吗”。刚播放“冰的苏打水”后，苏打水回应“谢谢你啊”，咖啡和牛肉回应“其实不用”；其他情况下，咖啡和苏打水从“谢谢你啊”“这你受得了吗”中选择回应。点击人物或开始新的投喂会切换当前互动。

### 六句原声

1. 这你受得了吗
2. 牛肉面不要面
3. 谢谢你啊
4. 冰的美式
5. 其实不用
6. 冰的苏打水

两平台共用人像、音频和字幕素材。素材来源、台词与截取时间见 [素材清单](materials/sources.json)。

## 设置与排查

如果没有声音，先检查应用菜单中的音量、系统输出设备和系统音量。Windows 的设置保存在 `%LOCALAPPDATA%\ChenzhenPet\settings.json`；启动或播放错误会记录在同目录的 `error.log`。Windows 托盘图标可能位于“显示隐藏图标”菜单中。

退出时可使用人物右键菜单；Windows 也可用系统托盘，macOS 也可用菜单栏。更新前先退出正在运行的桌宠。

## 从源码构建

构建步骤与检查命令见 [构建说明](docs/building.md)。可选的音频处理、转写复核和道具导出见 [素材处理](docs/media-processing.md)。欢迎参考 [贡献指南](CONTRIBUTING.md) 提交改进。

| 路径 | 内容 |
| --- | --- |
| `Sources/`、`build.sh` | macOS 应用和构建脚本 |
| `Windows/` | Windows WPF 应用、构建脚本及核心检查 |
| `Assets/` | 人像、原声、字幕和互动道具 |
| `materials/` | 素材来源、裁切范围、参考音频与处理参数 |
| `Tools/` | 可选的素材处理工具 |
| `verification/` | 构建与功能检查记录 |
| `licenses/`、`CREDITS.txt` | 第三方许可和素材署名 |

四种互动的时长、道具图层和关键帧由 [`Assets/actions.json`](Assets/actions.json) 定义，两平台读取同一份动作数据。参考音频位于 `materials/voice-reference/`；音量校准参数见 [`materials/audio-profile.json`](materials/audio-profile.json)，测量结果见 [校准记录](verification/level-match-1.0.3.json)。

## 验证状态

1.3.4 已完成 macOS 构建、自检、签名和 DMG 校验；Windows 已在原生运行器上完成构建、核心逻辑、嵌入资源检查和 ZIP 打包，详见 [验证记录](verification/1.3.4-test.json)。两平台的桌面交互和扬声器输出仍待实机检查。

## 许可与素材

项目自有代码采用 [MIT License](LICENSE)。第三方许可和来源见 [CREDITS.txt](CREDITS.txt) 与 `licenses/`。人物照片和原声获准随本项目分发，使用范围见 [素材许可说明](ASSETS_LICENSE.md)。版本变化见 [CHANGELOG.md](CHANGELOG.md)。
