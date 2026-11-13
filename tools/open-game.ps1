# 用 Godot 編輯器打開遊戲專案
# 用法：powershell -ExecutionPolicy Bypass -File tools/open-game.ps1
$root = Split-Path -Parent $PSScriptRoot
$projDir = Join-Path $root "game"

if (-not (Test-Path (Join-Path $projDir "project.godot"))) {
    Write-Error "搵唔到 $projDir\project.godot"
    exit 1
}

$exe = Get-ChildItem -Path $root -Depth 1 -Filter "Godot_v*mono_win64.exe" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch "console" } |
    Select-Object -First 1

if (-not $exe) {
    Write-Error "搵唔到 Godot 引擎（預期喺 $root\Godot_v4.7.2-stable_mono_win64\）。請自行下載 Godot 4.7 mono 並解壓喺 repo 根目錄。"
    exit 1
}

Write-Host "引擎：$($exe.FullName)"
Write-Host "專案：$projDir"
Start-Process -FilePath $exe.FullName -ArgumentList "--path", $projDir, "--editor"
