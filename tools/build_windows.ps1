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

# parse AppVersion (mirror build_release.sh)
$txt      = Get-Content "$root\lib\core\app_version.dart" -Raw
$year     = [regex]::Match($txt,'static const int year = (\d+)').Groups[1].Value
$month    = [regex]::Match($txt,'static const int month = (\d+)').Groups[1].Value
$day      = [regex]::Match($txt,'static const int day = (\d+)').Groups[1].Value
$stage    = [regex]::Match($txt,'static const AppStage stage = AppStage\.(\w+)').Groups[1].Value
$build    = [regex]::Match($txt,'static const int buildCount = (\d+)').Groups[1].Value
$codename = [regex]::Match($txt,"static const String codename = '([^']+)'").Groups[1].Value
$name     = "星璃音乐_0." + $year + "." + $month + "." + $day + "_" + $stage + "_cl" + $build + "_" + $codename
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
