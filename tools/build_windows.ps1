$ErrorActionPreference = 'Continue'
$root  = "D:\Stellara\Music\xingli_music"
$rel   = "D:\Stellara\Music\release"
$log   = "$root\build_windows.log"
$cmake = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
$env:ANDROID_HOME = "D:\Android\Sdk"
$env:Path = "$cmake;" + $env:Path
"=== windows build start $(Get-Date) ===" | Tee-Object -FilePath $log -Append
Set-Location $root
$fl = "D:\flutter\bin\flutter.bat"

# parse AppVersion（2026-08-17 渠道化：channel 替代 stage；Windows 产物名在
# cl 后加 _pc，如 0.26.8.17_alpha_cl01_pc。用 Get-Content -Raw -Encoding UTF8
# 读取（ReadAllText 在该上下文偶发空），脚本文件本身须 UTF-8 with BOM，
# 否则 PS5.1 按 ANSI 解析中文字面量（星璃音乐 → 乱码）。）
$txt      = Get-Content "$root\lib\core\app_version.dart" -Raw -Encoding UTF8
$year     = [regex]::Match($txt,'static const int year = (\d+)').Groups[1].Value
$month    = [regex]::Match($txt,'static const int month = (\d+)').Groups[1].Value
$day      = [regex]::Match($txt,'static const int day = (\d+)').Groups[1].Value
$channel  = [regex]::Match($txt,'static const UpdateChannel channel = UpdateChannel\.(\w+)').Groups[1].Value
$build    = [regex]::Match($txt,'static const int buildCount = (\d+)').Groups[1].Value
$codename = [regex]::Match($txt,"static const String codename = '([^']+)'").Groups[1].Value
$buildPad = $build.PadLeft(2, '0')
$name     = "星璃音乐_0.$year.$month.$day" + "_" + $channel + "_cl" + $buildPad + "_pc_" + $codename
"version name = $name" | Tee-Object -FilePath $log -Append
"cmake = $((Get-Command cmake -ErrorAction SilentlyContinue).Source)" | Tee-Object -FilePath $log -Append

& $fl build windows --release 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath $log -Append

$exe = "$root\build\windows\x64\runner\Release\xingli_music.exe"
if (Test-Path $exe) {
  $dst = "$rel\${name}_win"
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  Copy-Item "$root\build\windows\x64\runner\Release" $dst -Recurse
  "=== DONE -> $dst ===" | Tee-Object -FilePath $log -Append
  Get-ChildItem $dst | Select-Object Name, @{N='KB';E={[math]::Round($_.Length/1KB)}} | Out-File -FilePath $log -Append
} else {
  "=== BUILD FAILED: xingli_music.exe not found ===" | Tee-Object -FilePath $log -Append
}
"=== windows build end $(Get-Date) ===" | Tee-Object -FilePath $log -Append
