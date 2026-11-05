# 发布检查清单

1. 更新 `build.sh`、`Windows/build.ps1`、`Windows/ChenzhenPet.csproj`、`Windows/app.manifest` 和应用菜单中的版本号，并更新 README、安装教程和 CHANGELOG。
2. 从干净检出目录按 `docs/building.md` 在 macOS 和 Windows 原生系统构建；运行自检与核心检查，并检查两端启动、交互、声音和设置保存。未执行的原生检查必须在 Release 中标明。
3. 检查 DMG 和 ZIP 内的程序、说明、`LICENSE`、`ASSETS_LICENSE.md`、`CREDITS.txt`、`licenses/` 与 `materials/sources.json`。核对安装包文件名和版本号。
4. 为 DMG 和 ZIP 生成 `SHA256SUMS-<version>.txt`，核对文件哈希、下载链接及安装教程中的版本号。
5. 检查仓库内容没有个人绝对路径、凭证、私有工具默认依赖或本机产物；发布新标签与 Release，并更新旧 Release 的新版入口。
