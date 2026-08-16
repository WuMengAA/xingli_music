#!/usr/bin/env python3
# cl78 兜底修复（沿用 cl77 思路）：删除 Actions 自动上传的资产，
# 重传本地「已验证 cl78 构建」以保证 OTA SHA-256 一致。
#
# ⚠️ 关键坑：本地 release/app-release.apk 是「陈旧的 cl77 构建」
#   （sha 2e5043cf…，与 cl77 记录一致），绝对不能直接上传！
#   必须用 cl78 构建：星璃音乐_0.26.08.16_alpha_cl78.apk（sha 3a5763b4…）。
#   上传时以 asset name "app-release.apk" 抛出即可（OTA 只认这个名字）。
import json, re, os, hashlib, urllib.request, urllib.error, urllib.parse, sys

CRED = r"C:/Users/Administrator/.git-credentials"
line = open(CRED, encoding="utf-8").read().strip().splitlines()[0]
TOK = re.search(r'WuMengAA:([^@]+)@', line).group(1)
API = "https://api.github.com/repos/WuMengAA/xingli_music"
UP  = "https://uploads.github.com/repos/WuMengAA/xingli_music"
TAG = "cl78"
RELEASE_DIR = r"D:/Stellara/Music/xingli_music/release"
# cl78 本地验证构建（非陈旧的 app-release.apk / cl77）
SRC_APK = os.path.join(RELEASE_DIR, "星璃音乐_0.26.08.16_alpha_cl78.apk")
APK_SHA = "3a5763b4ed2bcf8d787a8c72f624243e4f6709879f9a5945b7dfac2c23239b42"

def req(method, url, data=None, ctype=None, timeout=600):
    h = {"Authorization": "token " + TOK, "Accept": "application/vnd.github+json"}
    if ctype: h["Content-Type"] = ctype
    body = json.dumps(data).encode() if isinstance(data, (dict, list)) else data
    r = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]

def log(*a):
    print(*a, flush=True)

# ── 本地构建自检（防把 cl77 当 cl78 发出去）──
if not os.path.exists(SRC_APK):
    log("ERROR: cl78 本地构建缺失:", SRC_APK); sys.exit(2)
h = hashlib.sha256()
with open(SRC_APK, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
local_sha = h.hexdigest()
if local_sha != APK_SHA:
    log("ERROR: 本地 cl78 apk sha 不匹配", local_sha, "!=", APK_SHA); sys.exit(3)
log("本地 cl78 构建校验通过:", local_sha)

s, b = req("GET", f"{API}/releases?per_page=30")
rels = json.loads(b)
target = next((r for r in rels if r.get("tag_name") == TAG), None)
if not target:
    log("NO RELEASE — creating")
    s, b = req("POST", f"{API}/releases", data={
        "tag_name": TAG, "name": "星璃音乐 cl78",
        "body": "## 星璃音乐 cl78\n本地验证构建发布。\n\n> 应用内「设置 → 关于 → 版本更新」可自动检测本 Release 并 OTA 更新。",
        "draft": False, "prerelease": False})
    target = json.loads(b)
rid = target["id"]
log("release id:", rid, "assets before:", [(a["name"], a["size"]) for a in target.get("assets", [])])

# 删除坏/旧资产
for a in target.get("assets", []):
    if a["name"] in ("app-release.apk", "app-release.apk.sha256"):
        st, _ = req("DELETE", f"{API}/releases/assets/{a['id']}")
        log("delete", a["name"], st)

sha = os.path.join(RELEASE_DIR, "app-release.apk.sha256")
with open(sha, "w", encoding="utf-8") as f:
    f.write(f"{APK_SHA}  app-release.apk\n")

def upload(local, name, ctype):
    with open(local, "rb") as f:
        data = f.read()
    url = f"{UP}/releases/{rid}/assets?name={urllib.parse.quote(name)}"
    st, b = req("POST", url, data=data, ctype=ctype)
    log("upload", name, st, len(data), "resp", b[:80])

upload(sha, "app-release.apk.sha256", "text/plain")
upload(SRC_APK, "app-release.apk", "application/vnd.android.package-archive")

s, b = req("GET", f"{API}/releases/{rid}")
final = json.loads(b)
log("FINAL assets:", [(a["name"], a["size"]) for a in final.get("assets", [])])
log("DONE")
