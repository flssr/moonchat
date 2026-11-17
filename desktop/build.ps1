# 构建 Windows 客户端（MondChat.exe）。需要 Flutter SDK 与 Visual Studio 2022
# 的「使用 C++ 的桌面开发」工作负载；没有这些的机器用 CI 的 desktop job 产物。
#
# 用法：
#   .\desktop\build.ps1
#   .\desktop\build.ps1 -ApiBase http://127.0.0.1:8080
param(
    [string]$ApiBase = 'https://api.mondchat.com'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# frontend/app 是共享包，资源必须复制进桌面包内（见 pubspec.yaml 的 assets）。
$assets = Join-Path $PSScriptRoot 'assets'
Remove-Item -Recurse -Force $assets -ErrorAction SilentlyContinue
Copy-Item -Recurse (Join-Path $repo 'frontend\app\assets') $assets

Push-Location $PSScriptRoot
try {
    flutter build windows --release --dart-define=MONDCHAT_API_BASE=$ApiBase
} finally {
    Pop-Location
}

Write-Host "产物：$(Join-Path $PSScriptRoot 'build\windows\x64\runner\Release\MondChat.exe')"
