# 陈震桌宠

<img src="Assets/face.png" alt="陈震桌宠人物" width="220">

点击人物播放原声、拖动摆放，并用人物下方的按钮触发卡通投喂互动。应用在本地运行，启动和闲置时不会自动发声。支持 **Windows 10/11 x64** 和 **macOS 14+ Apple Silicon**。

## 下载与安装

从 [最新发布页面](https://github.com/aaba9152/chenzhen-desktop-pet/releases/latest) 下载对应系统的成品。使用成品不需要安装 SDK、Python 或语音模型。

| 系统 | 下载文件 | 安装步骤 |
| --- | --- | --- |
| Windows 10/11 x64 | `ChenzhenPet-Windows-x64-1.3.4.zip` | 解压 ZIP，双击 `ChenzhenPet.exe`。运行环境已包含在程序中。 |
| macOS 14+ Apple Silicon | `ChenzhenPet-1.3.4.dmg` | 打开 DMG，将“陈震桌宠”拖到“应用程序”，然后从“应用程序”启动。 |

[macOS 首次打开教程](docs/macos-install.md)说明系统拦截提示的处理方式。Windows 成品未使用商业代码签名证书；macOS 成品采用本地签名，未经过 Apple 公证。发布页面提供 `SHA256SUMS-1.3.4.txt` 用于核对下载文件。

## 使用

- 单击人物：依次循环播放六句原声。播放中再点会立即切换，不叠音。
- 拖动人物：改变位置；拖动右下角标记：调整大小。
- 点击人物旁箭头：展开台词清单，选择任意一句播放。
- 右键人物：选择台词或人像，调整音量、大小与位置，或退出。
- 点击或拖动下方四个按钮到人物区域：触发牛肉、咖啡、苏打水或浇咖啡互动。

大小、音量、位置和人像选择会自动保存。Windows 另有系统托盘入口，macOS 另有菜单栏入口。详细操作见 [Windows 使用说明](Windows/使用说明.txt)与 [macOS 使用说明](使用说明.txt)。

| 黄色长发 | 黑色长发 | 短发 |
| --- | --- | --- |
| <img src="Assets/Portraits/portrait-near.png" width="150" alt="黄色长发人像"> | <img src="Assets/Portraits/portrait-smile.png" width="150" alt="黑色长发人像"> | <img src="Assets/face.png" width="150" alt="短发人像"> |

## 从源码构建

见 [构建与检查](docs/building.md)。应用运行只需要随项目提供的资源；音频重新处理与转写是可选开发流程，见 [素材处理](docs/media-processing.md)。贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 验证状态

1.3.4 的 macOS 构建、自检、签名与 DMG 校验已通过；Windows 原生运行器已完成构建、核心逻辑及资源检查，记录见 [1.3.4 验证结果](verification/1.3.4-test.json)。此版本的两端实际桌面交互与扬声器输出尚未完成验证，历史记录不代替这些检查。

## 许可与素材

项目自有代码采用 [MIT License](LICENSE)。第三方许可和来源见 [CREDITS.txt](CREDITS.txt) 与 `licenses/`。人物照片及原声仅获准随本项目分发，不包含在代码的 MIT 许可中；使用边界见 [素材许可说明](ASSETS_LICENSE.md)。

完整版本历史见 [CHANGELOG.md](CHANGELOG.md)。
