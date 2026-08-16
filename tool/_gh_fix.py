import json, re, os, shutil, urllib.request, urllib.error, urllib.parse

CRED = r"C:/Users/Administrator/.git-credentials"
line = open(CRED, encoding="utf-8").read().strip().splitlines()[0]
TOK = re.search(r'WuMengAA:([^@]+)@', line).group(1)
API = "https://api.github.com/repos/WuMengAA/xingli_music"
UP = "https://uploads.github.com/repos/WuMengAA/xingli_music"

def req(method, url, data=None, headers=None, ctype=None):
    h = {"Authorization": "token " + TOK, "Accept": "application/vnd.github+json"}
    if headers: h.update(headers)
    if ctype: h["Content-Type"] = ctype
    body = json.dumps(data).encode() if isinstance(data, (dict, list)) else data
    r = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=600) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]

RELEASE_DIR = r"D:/Stellara/Music/xingli_music/release"
H6 = "星璃音乐_0.26.8.15_alpha_cl76_hotfix6.apk"
H6_SHA = "f18034fb4d43eb5679e5095d666266136075e32c6205d99ddd7feab37c261e27"

s, rels = req("GET", API + "/releases?per_page=20")
rels = json.loads(rels)
target = next((r for r in rels if r.get("tag_name") == "cl76_hotfix6"), None)
rid = target["id"]
print("release id:", rid, "current assets:", [(a["name"], a["size"]) for a in target.get("assets", [])])

# delete apk + sha256 (keep patch)
for a in target.get("assets", []):
    if a["name"] in ("app-release.apk", "app-release.apk.sha256"):
        st, _ = req("DELETE", API + f"/releases/assets/{a['id']}")
        print(f"delete {a['name']}: {st}")

# re-upload my verified local build
apk_src = os.path.join(RELEASE_DIR, H6)
apk_tmp = os.path.join(RELEASE_DIR, "app-release.apk")
sha_tmp = os.path.join(RELEASE_DIR, "app-release.apk.sha256")
shutil.copy(apk_src, apk_tmp)
with open(sha_tmp, "w", encoding="utf-8") as f:
    f.write(H6_SHA + "  app-release.apk\n")

def upload(local, name, ctype):
    with open(local, "rb") as f:
        data = f.read()
    url = f"{UP}/releases/{rid}/assets?name={urllib.parse.quote(name)}"
    st, b = req("POST", url, data=data, ctype=ctype)
    print(f"upload {name}: {st} ({len(data)} bytes)  resp={b[:80]}")

upload(sha_tmp, "app-release.apk.sha256", "text/plain")
upload(apk_tmp, "app-release.apk", "application/vnd.android.package-archive")

for t in (apk_tmp, sha_tmp):
    try: os.remove(t)
    except OSError: pass
print("DONE")
