$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$version = '1.3.4'
dotnet publish Windows/ChenzhenPet.csproj -c Release -r win-x64 --self-contained true -o build/windows-x64 --disable-build-servers
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
dotnet run --project Windows/Tests/CoreTests.csproj -c Release -- "$PWD" "$PWD/Windows/bin/Release/net10.0-windows/win-x64/ChenzhenPet.dll"
if ($LASTEXITCODE -ne 0) { throw 'Windows core tests failed' }
$stage = "tmp/windows-package-$version"
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item build/windows-x64/ChenzhenPet.exe "$stage/ChenzhenPet.exe"
Get-ChildItem Windows/*.txt | Copy-Item -Destination $stage
Copy-Item CREDITS.txt, LICENSE, ASSETS_LICENSE.md, CHANGELOG.md -Destination $stage
Copy-Item materials/sources.json "$stage/素材来源.json"
Copy-Item licenses -Destination $stage -Recurse
New-Item -ItemType Directory -Path dist -Force | Out-Null
Compress-Archive -Path "$stage/*" -DestinationPath "dist/ChenzhenPet-Windows-x64-$version.zip" -Force
Get-FileHash "dist/ChenzhenPet-Windows-x64-$version.zip" -Algorithm SHA256
Remove-Item $stage -Recurse -Force
