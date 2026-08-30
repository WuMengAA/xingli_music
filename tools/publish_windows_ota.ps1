# ═══════════════════════════════════════════════════════════════════════
# 发布 Windows 电脑版 OTA 更新包（cl77）
# ═══════════════════════════════════════════════════════════════════════
# 产物：
#   - xingli_music_windows_x64.zip        —— Release 目录平铺打包（exe + dll + data/）
#   - xingli_music_windows_x64.zip.sha256 —— SHA-256 校验文件
# 应用侧约定（lib/services/ota_service.dart）：
#   otaWindowsAssetName() = 'xingli_music_windows_x64.zip'
#   otaWindowsShaAssetName() = '<上面>.sha256'
# 命名固定、不随 tag 变；安装链路解压该 zip 到 staging 后延迟替换 exe。
#
# 用法：
#   .\tools\publish_windows_ota.ps1
#   （完成后把两个文件按指引传到 GitHub Release 同 tag 资产下）
# ═══════════════════════════════════════════════════════════════════════
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

# ── 1) 构建 Windows Release ──
Write-Host '==> flutter build windows --release' -ForegroundColor Cyan
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Windows 构建失败' }

$ReleaseDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $ReleaseDir)) {
  throw "Release 目录不存在：$ReleaseDir"
}

$AssetBase = 'xingli_music_windows_x64'
$ZipPath   = Join-Path $RepoRoot "$AssetBase.zip"
$ShaPath   = "$ZipPath.sha256"

# ── 2) 平铺打包（zip 内直接是 exe/dll/data，无顶层目录）──
# tar -a 让 bsdtar 按 .zip 扩展名选 zip 压缩器（Windows 10+ 自带）。
Write-Host "==> 打包 $AssetBase.zip（平铺）" -ForegroundColor Cyan
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Push-Location $ReleaseDir
try {
  & tar -a -c -f $ZipPath .
  if ($LASTEXITCODE -ne 0) { throw 'tar 打包失败' }
} finally {
  Pop-Location
}

# ── 3) 生成 SHA-256 ──
Write-Host '==> 生成 .sha256' -ForegroundColor Cyan
$Hash = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash.ToLowerInvariant()
"$Hash  $AssetBase.zip" | Set-Content -Encoding ascii -NoNewline $ShaPath

Write-Host '' -ForegroundColor Cyan
Write-Host '✅ 已生成：' -ForegroundColor Green
Write-Host "   $ZipPath  ($([math]::Round((Get-Item $ZipPath).Length / 1MB, 1)) MB)"
Write-Host "   $ShaPath"
Write-Host ''
Write-Host '==> 上传（任选其一，tag 用当前版本，如 0.26.8.29_beta_cl02）：' -ForegroundColor Yellow
Write-Host '  gh release upload <TAG> xingli_music_windows_x64.zip xingli_music_windows_x64.zip.sha256'
Write-Host '  或 GitHub Web 打开 Releases → Edit → 附件上传两个文件'