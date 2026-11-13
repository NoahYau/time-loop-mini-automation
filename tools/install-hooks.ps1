# 安裝 git hooks（pre-push 守門員）
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $PSScriptRoot "hooks\pre-push"
$dstDir = Join-Path $root ".git\hooks"
$dst = Join-Path $dstDir "pre-push"

if (-not (Test-Path $dstDir)) {
	New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
}
Copy-Item $src $dst -Force
Write-Host "已安裝：$dst"
Write-Host "測試：git checkout main && git commit --allow-empty -m test && git push（應該被擋）"
