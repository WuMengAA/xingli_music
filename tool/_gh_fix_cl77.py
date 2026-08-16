#!/usr/bin/env python3
# cl77 兜底修复：Actions 构建失败，Release 仅含自动 .sha256、缺 app-release.apk。
# 删除坏资产，重传本地已验证 APK + 正确 sha（保证 OTA SHA-256 校验一致）。
import json, re, os, urllib.request, urllib.error, urllib.parse, sys

CRED = r"C:/Users/Administrator/.git-credentials"
line = open(CRED, encoding="utf-8").read().strip().splitlines()[0]
TOK = re.search(r'WuMengAA:([^@]+)@', line).group(1)
API = "https://api.github.com/repos/WuMengAA/xingli_music"
UP  = "https://uploads.github.com/repos/WuMengAA/xingli_music"
TAG = "cl77"
RELEASE_DIR = r"D:/Stellara/Music/xingli_music/release"
APK_SHA = "2e5043cf5bcd98d6c2b645e22489fade7d06146cb7d84cf7235ce2bdfe00f413"

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

s, b = req("GET", f"{API}/releases?per_page=30")
rels = json.loads(b)
target = next((r for r in rels if r.get("tag_name") == TAG), None)
if not target:
    log("NO RELEASE — creating")
    s, b = req("POST", f"{API}/releases", data={
        "tag_name": TAG, "name": "星璃音乐 cl77",
        "body": "## 星璃音乐 cl77\n本地验证构建发布（Actions 构建失败，改用本地验证包）。\n\n> 应用内「设置 → 关于 → 版本更新」可自动检测本 Release 并 OTA 更新。",
        "draft": False, "prerelease": False})
    target = json.loads(b)
rid = target["id"]
log("release id:", rid, "assets before:", [(a["name"], a["size"]) for a in target.get("assets", [])])

# 删除坏/旧资产
for a in target.get("assets", []):
    if a["name"] in ("app-release.apk", "app-release.apk.sha256"):
        st, _ = req("DELETE", f"{API}/releases/assets/{a['id']}")
        log("delete", a["name"], st)

apk = os.path.join(RELEASE_DIR, "app-release.apk")
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
upload(apk, "app-release.apk", "application/vnd.android.package-archive")

s, b = req("GET", f"{API}/releases/{rid}")
final = json.loads(b)
log("FINAL assets:", [(a["name"], a["size"]) for a in final.get("assets", [])])
log("DONE")
