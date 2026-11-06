# 从源码构建与检查

在仓库根目录执行命令。构建脚本按仓库位置定位运行资源，支持包含空格的目录。音频处理步骤见 [素材处理](media-processing.md)。

## Windows 10/11 x64

安装 [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)，在 PowerShell 中运行：

```powershell
.\Windows\build.ps1
```

脚本编译自带运行环境的单文件 EXE，运行核心及嵌入资源检查，在 `dist/` 生成 ZIP。直接编译可用：

```powershell
dotnet publish Windows/ChenzhenPet.csproj -c Release -r win-x64 --self-contained true -o build/windows-x64
```

Windows 代码也启用了跨平台目标编译，但在其他系统上编译通过不等于 Windows 原生界面与音频验证。

## macOS 14+ Apple Silicon

安装 Xcode Command Line Tools，在终端运行：

```sh
./build.sh --package
```

脚本编译原生应用、运行内置自检、对应用本地签名，并在 `dist/` 生成 DMG。只需构建应用时运行 `./build.sh`。macOS 应用未经过 Apple 公证，首次打开方式见 [安装教程](macos-install.md)。

## 核心检查

在有 .NET 10 SDK 的系统上可运行 Windows 核心检查：

```sh
dotnet run --project Windows/Tests/CoreTests.csproj -c Release -- .
```

历史检查结果保存在 `verification/`。它们记录当时的检查范围；修改后应重新运行相应检查。发布流程见 [发布清单](release-checklist.md)。
