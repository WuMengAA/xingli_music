# ════════════════════════════════════════════════════════════════════════
# clOTA 发布到 GitHub Pages（gh-pages 分支静态分发源）
# ════════════════════════════════════════════════════════════════════════
# 用法：
#   $env:DSH_PAT = 'github_pat_...'          # 一次性注入，用完即删
#   powershell -ExecutionPolicy Bypass -File tools/publish_pages_ota.ps1 `
#       -Tag 0.26.8.31_beta_cl01 `
#       -Notes "clOTA：GitHub Pages 分发链路" `
#       [-ApkDir build/app/outputs/flutter-apk] `
#       [-WindowsZip path\to\xingli_music_windows_x64.zip] [-SkipBuild]
#
# 行为：
#   1. （可选）先构建 release APK（-SkipBuild 跳过；Windows 包需先自行打包好）
#   2. 收集平台资产（arm64-v8a / armeabi-v7a APK + 可选 windows x64 zip），
#      计算 size + sha256（客户端校验用，无需再放 .sha256 文件）
#   3. 拉取 gh-pages 现有 ota/manifest.json（保留历史版本/其它渠道），
#      合并更新当前渠道 latest + 新 tag 资产，版本列表按 (日期, cl) 倒序
#   4. 在独立临时 git 仓库（只含 ota/，不污染主仓库）提交并推送 gh-pages
#   5. 打印 Pages 验证 URL
#
# 推送认证：经 $env:DSH_PAT 单次注入（不回显、不写盘、不改 origin）。
# ════════════════════════════════════════════════════════════════════════
param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,

    [string]$Notes = '',

    [string]$RepoOwner = 'WuMengAA',
    [string]$RepoName = 'xingli_music',

    [string]$ApkDir = '',

    [string]$WindowsZip = '',

    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# ── 0. 前置检查 ─────────────────────────────────────────────────────────
$TagPattern = '^0\.\d+\.\d+\.\d+_(beta|alpha)_cl\d+(_hotfix\d+)?$'
if ($Tag -notmatch $TagPattern) {
    throw "Tag 不合法（需 0.YY.MM.DD_渠道_clNN[_hotfixN]）：$Tag"
}
$channel = $Matches[1]
$build = [int](($Tag -split '_cl')[1] -split '_')[0]
$hotfix = $null
if ($Tag -match '_hotfix(\d+)$') { $hotfix = [int]$Matches[1] }
# dateKey = 0.YY.MM.DD → YYMMDD 数字（与客户端 OtaTagInfo 同构：year*1e4+month*1e2+day）。
$verParts = ($Tag -split '_')[0] -split '\.'
$dateKey = ([int]$verParts[1]) * 10000 + ([int]$verParts[2]) * 100 + [int]$verParts[3]
Write-Step "发布 $Tag （渠道=$channel dateKey=$dateKey cl=$build hotfix=$hotfix）"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ApkDir) { $ApkDir = Join-Path $repoRoot 'build\app\outputs\flutter-apk' }

# ── 1. （可选）构建 release APK ────────────────────────────────────────
# 清理 flutter test 可能残留的 dev 插件 registrant（src/main 老位置，
# 否则 release 构建会编译含 integration_test 的陈旧注册器而失败）。
$staleRegistrant = Join-Path $repoRoot 'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
if (Test-Path $staleRegistrant) {
    Remove-Item $staleRegistrant -Force
    Write-Ok '已清理残留 dev 插件 registrant'
}
if (-not $SkipBuild) {
    Write-Step '构建 release APK（--release --split-per-abi）…'
    Push-Location $repoRoot
    try { flutter build apk --release --split-per-abi | Out-Host } 
    finally { Pop-Location }
    if (-not (Test-Path (Join-Path $ApkDir 'app-arm64-v8a-release.apk'))) {
        throw "构建产物缺失：$ApkDir\app-arm64-v8a-release.apk"
    }
    Write-Ok 'APK 构建完成'
}

# ── 2. 收集资产 ─────────────────────────────────────────────────────────
$android = [ordered]@{}
$apkArm64 = Join-Path $ApkDir 'app-arm64-v8a-release.apk'
$apkArm32 = Join-Path $ApkDir 'app-armeabi-v7a-release.apk'
foreach ($pair in @(
        @('arm64-v8a',   $apkArm64),
        @('armeabi-v7a', $apkArm32)
    )) {
    if (Test-Path $pair[1]) {
        $fi = Get-Item $pair[1]
        $hash = (Get-FileHash -Algorithm SHA256 -Path $pair[1]).Hash.ToLowerInvariant()
        $android[$pair[0]] = @{
            name   = $pair[1].Split('\')[-1]
            size   = $fi.Length
            sha256 = $hash
        }
        Write-Ok ("{0}  {1:N1} MB  sha256={2}" -f $pair[1].Split('\')[-1], ($fi.Length / 1MB), $hash.Substring(0, 12) + '…')
    }
}
if ($android.Count -eq 0) { throw '没有任何 APK 资产（检查 -ApkDir）' }

$windows = $null
if ($WindowsZip) {
    if (-not (Test-Path $WindowsZip)) { throw "WindowsZip 不存在：$WindowsZip" }
    $fi = Get-Item $WindowsZip
    $hash = (Get-FileHash -Algorithm SHA256 -Path $WindowsZip).Hash.ToLowerInvariant()
    $windows = [ordered]@{
        x64 = @{
            name   = 'xingli_music_windows_x64.zip'
            size   = $fi.Length
            sha256 = $hash
        }
    }
    if ($fi.Length -gt 100MB) {
        Write-Warn 'Windows zip 超过 GitHub Pages 单文件 100MB 上限，将被 Pages 拒绝；'
        Write-Warn '请改用 Releases 发布 Windows 包（tools/publish_windows_ota.ps1）。'
    }
    Write-Ok ("xingli_music_windows_x64.zip  {0:N1} MB" -f ($fi.Length / 1MB))
}

# ── 3. 合并旧 manifest（保留历史版本与其它渠道）────────────────────────
$rawOldUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/gh-pages/ota/manifest.json"
$oldChannels = [ordered]@{}
$oldAssets = [ordered]@{}
$oldVersions = New-Object System.Collections.Generic.List[string]
$oldBody = $null
try {
    $oldBody = (Invoke-WebRequest -Uri $rawOldUrl -UseBasicParsing -TimeoutSec 15).Content
} catch {
    Write-Warn 'raw.githubusercontent 拉取失败，改用 GitHub API 兜底…'
}
if (-not $oldBody) {
    try {
        $apiHeaders = @{ 'User-Agent' = 'xingli-ota' }
        if ($env:DSH_PAT) { $apiHeaders['Authorization'] = "Bearer $($env:DSH_PAT)" }
        $r = Invoke-RestMethod -Uri (
            "https://api.github.com/repos/$RepoOwner/$RepoName/contents/ota/manifest.json?ref=gh-pages"
        ) -Headers $apiHeaders -TimeoutSec 25
        if ($r.content) {
            $oldBody = [System.Text.Encoding]::UTF8.GetString(
                [System.Convert]::FromBase64String($r.content))
        }
    } catch {
        Write-Warn "API 兜底也失败：$($_.Exception.Message)"
    }
}
if ($oldBody) {
    $old = $oldBody | ConvertFrom-Json
    Write-Ok '拉取到 gh-pages 现有 manifest，将合并历史'
    if ($old.channels) {
        foreach ($p in $old.channels.PSObject.Properties) {
            # 兼容旧版平铺（channels.<ch> 直接为 latest 对象）→ 统一嵌套 { latest = ... }。
            $v = $p.Value
            if ($null -eq $v.latest) { $v = @{ latest = $v } }
            $oldChannels[$p.Name] = $v
        }
    }
    if ($old.assets) {
        foreach ($p in $old.assets.PSObject.Properties) { $oldAssets[$p.Name] = $p.Value }
    }
    if ($old.versions) { foreach ($v in $old.versions) { $oldVersions.Add([string]$v) } }
} else {
    Write-Ok 'gh-pages 尚未发布过 manifest（或拉取失败），从零开始'
}

# 本 tag 资产。
$tagAssets = [ordered]@{ android = $android }
if ($windows) { $tagAssets['windows'] = $windows }
$oldAssets[$Tag] = $tagAssets

# 版本列表去重 + (日期, cl) 倒序。
if (-not $oldVersions.Contains($Tag)) { $oldVersions.Insert(0, $Tag) }
function Get-Rank($t) {
    $v = ($t -split '_')[0] -split '\.'
    $dk = ([int]$v[1]) * 10000 + ([int]$v[2]) * 100 + [int]$v[3]
    $cl = 0; if ($t -match '_cl(\d+)') { $cl = [int]$Matches[1] }
    return $dk * 10000 + $cl
}
$versions = @($oldVersions | Sort-Object -Descending { Get-Rank $_ } | Select-Object -Unique)

# 渠道 latest：本渠道用新 tag，其它渠道保留旧值。
$latest = [ordered]@{
    tag      = $Tag
    dateKey  = $dateKey
    build    = $build
    hotfix   = $hotfix
    notes    = $Notes
}
$oldChannels[$channel] = @{ latest = $latest }

$nowIso = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
$manifest = [ordered]@{
    schema    = 1
    source    = 'github-pages'
    updatedAt = $nowIso
    channels  = $oldChannels
    assets    = $oldAssets
    versions  = $versions
}

# ── 4. 组装临时仓库（只含 ota/，独立 git 仓库推 gh-pages）──────────────
$tmp = Join-Path $env:TEMP ("pages_ota_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'ota') | Out-Null
$otaDir = Join-Path $tmp 'ota'

$manifestJson = $manifest | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText(
    (Join-Path $otaDir 'manifest.json'), $manifestJson, $utf8NoBom)

$tagDir = Join-Path $otaDir $Tag
New-Item -ItemType Directory -Force -Path $tagDir | Out-Null
foreach ($abiName in @('arm64-v8a', 'armeabi-v7a')) {
    if ($android.Contains($abiName)) {
        Copy-Item (Join-Path $ApkDir $android[$abiName].name) $tagDir -Force
    }
}
if ($windows) {
    Copy-Item $WindowsZip (Join-Path $tagDir 'xingli_music_windows_x64.zip') -Force
}
Write-Step "组装完成：$otaDir（$($versions.Count) 个版本记录）"

# ── 5. 推送 gh-pages ────────────────────────────────────────────────────
$pat = $env:DSH_PAT
if (-not $pat) { throw '缺少推送凭据：请先 $env:DSH_PAT = ''github_pat_...''（用完 Remove-Item Env:DSH_PAT）' }
$pushUrl = "https://x-access-token:$pat@github.com/$RepoOwner/$RepoName.git"

# 优先 clone 远端 gh-pages（保留历史后快进推送）；分支不存在（首次）则建孤儿仓库。
$gitDir = Join-Path $env:TEMP ("pages_ota_git_" + [guid]::NewGuid().ToString('N'))
git clone -q --depth 50 --branch gh-pages $pushUrl $gitDir
if ($LASTEXITCODE -eq 0) {
    Remove-Item (Join-Path $gitDir 'ota') -Recurse -Force -ErrorAction SilentlyContinue
} else {
    git init -q $gitDir
}
git -C $gitDir config user.name 'xingli-bot'
git -C $gitDir config user.email 'xingli-bot@users.noreply.github.com'
Copy-Item -Recurse -Force $otaDir (Join-Path $gitDir 'ota')
git -C $gitDir add -A
git -C $gitDir commit -q -m "ota(pages): publish $Tag"
git -C $gitDir push -q $pushUrl HEAD:refs/heads/gh-pages
if ($LASTEXITCODE -ne 0) { throw "推送 gh-pages 失败（exit=$LASTEXITCODE）" }
Write-Ok "已推送 gh-pages：$Tag"

Remove-Item -Recurse -Force $tmp
Remove-Item -Recurse -Force $gitDir -ErrorAction SilentlyContinue
Remove-Item Env:DSH_PAT -ErrorAction SilentlyContinue

# ── 6. 验证 ─────────────────────────────────────────────────────────────
$pagesBase = "https://$($RepoOwner.ToLowerInvariant()).github.io/$RepoName"
$manifestUrl = "$pagesBase/ota/manifest.json"
$apkUrl = "$pagesBase/ota/$Tag/$($android['arm64-v8a'].name)"
Write-Ok '验证 URL（GitHub Pages 构建需 1~2 分钟生效）:'
Write-Ok "  manifest: $manifestUrl"
Write-Ok "  apk     : $apkUrl"
Write-Host ''
Write-Host '完成。检查方式：' -ForegroundColor Cyan
Write-Host "  1. Invoke-WebRequest $manifestUrl | Select -Expand Content" -ForegroundColor Gray
Write-Host '  2. 若 Pages 未开启：仓库 Settings → Pages → Source: Deploy from a branch → gh-pages / (root)' -ForegroundColor Gray