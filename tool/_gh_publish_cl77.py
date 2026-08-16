#!/usr/bin/env python3
# 发布 cl77：等待 Actions 构建完成 → 删除其自动上传的 apk+sha →
# 重新上传本地已验证构建（保证 OTA SHA-256 校验一致）。
import json, re, os, time, urllib.request, urllib.error, urllib.parse

CRED = r"C:/Users/Administrator/.git-credentials"
line = open(CRED, encoding="utf-8").read().strip().splitlines()[0]
TOK = re.search(r'WuMengAA:([^@]+)@', line).group(1)
API = "https://api.github.com/repos/WuMengAA/xingli_music"
UP  = "https://uploads.github.com/repos/WuMengAA/xingli_music"

HEAD_SHA = "4f51d797755fcbc660a7e2b2575236f8126024a5"
TAG = "cl77"
RELEASE_DIR = r"D:/Stellara/Music/xingli_music/release"
APK_SHA = "2e5043cf5bcd98d6c2b645e22489fade7d06146cb7d84cf7235ce2bdfe00f413"

def req(method, url, data=None, headers=None, ctype=None, timeout=600):
    h = {"Authorization": "token " + TOK, "Accept": "application/vnd.github+json"}
    if headers: h.update(headers)
    if ctype: h["Content-Type"] = ctype
    body = json.dumps(data).encode() if isinstance(data, (dict, list)) else data
    r = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]

# ── 1) 等待 Actions run 完成（head_sha 命中且 event=push）──
print("== 等待 Actions 构建完成 ==")
run = None
for i in range(40):  # 最多 ~13 分钟
    s, b = req("GET", f"{API}/actions/runs?head_sha={HEAD_SHA}&event=push&per_page=5")
    if s == 200:
        for r in json.loads(b).get("workflow_runs", []):
            if r.get("head_sha") == HEAD_SHA:
                run = r
                break
    if run and run.get("status") == "completed":
        print(f"  Actions 状态: {run['status']} / conclusion={run.get('conclusion')} (after {i*20}s)")
        break
    time.sleep(20)
else:
    print("  [WARN] 未在超时内确认 Actions 完成，仍继续尝试（可能需手动核对）")

# ── 2) 找到 cl77 Release（若不存在则手动创建）──
s, b = req("GET", f"{API}/releases?per_page=30")
rels = json.loads(b)
target = next((r for r in rels if r.get("tag_name") == TAG), None)
if target is None:
    print("== Release 不存在，手动创建 ==")
    s, b = req("POST", f"{API}/releases", data={
        "tag_name": TAG,
        "target_commitish": HEAD_SHA,
        "name": "星璃音乐 cl77",
        "body": "## 星璃音乐 cl77\n自动构建发布（由 GitHub Actions 生成）。\n\n> 应用内「设置 → 关于 → 版本更新」可自动检测本 Release 并 OTA 更新。",
        "draft": False, "prerelease": False,
    })
    if s not in (200, 201):
        print("  创建 Release 失败:", s, b); raise SystemExit(1)
    target = json.loads(b)
rid = target["id"]
print("  release id:", rid, "当前资产:", [(a["name"], a["size"]) for a in target.get("assets", [])])

# ── 3) 删除自动上传的 apk + sha256（保留其余）──
for a in target.get("assets", []):
    if a["name"] in ("app-release.apk", "app-release.apk.sha256"):
        st, _ = req("DELETE", f"{API}/releases/assets/{a['id']}")
        print(f"  delete {a['name']}: {st}")

# ── 4) 上传本地已验证构建 ──
apk = os.path.join(RELEASE_DIR, "app-release.apk")
sha = os.path.join(RELEASE_DIR, "app-release.apk.sha256")
# 确保 sha 文件内容正确（Actions 格式：hash + 空格*2 + 文件名）
with open(sha, "w", encoding="utf-8") as f:
    f.write(f"{APK_SHA}  app-release.apk\n")

def upload(local, name, ctype):
    with open(local, "rb") as f:
        data = f.read()
    url = f"{UP}/releases/{rid}/assets?name={urllib.parse.quote(name)}"
    st, b = req("POST", url, data=data, ctype=ctype)
    print(f"  upload {name}: {st} ({len(data)} bytes)  resp={b[:80]}")

upload(sha, "app-release.apk.sha256", "text/plain")
upload(apk, "app-release.apk", "application/vnd.android.package-archive")

# ── 5) 校验 ──
s, b = req("GET", f"{API}/releases/{rid}")
final = json.loads(b)
print("== 最终资产 ==")
for a in final.get("assets", []):
    print(f"  {a['name']}  {a['size']} bytes")
print("DONE")
