"""启动 xingli_music.exe 并捕获 stdout/stderr/退出码（排障用）。"""
import subprocess, time, sys

EXE = r"D:\Stellara\Music\xingli_music\build\windows\x64\runner\Release\xingli_music.exe"
out = open(r"C:\Users\Administrator\AppData\Local\Temp\xl_out.txt", "wb")
err = open(r"C:\Users\Administrator\AppData\Local\Temp\xl_err.txt", "wb")
try:
    p = subprocess.Popen([EXE], stdout=out, stderr=err, cwd=r"D:\Stellara\Music\xingli_music\build\windows\x64\runner\Release")
except Exception as e:
    print(f"启动失败: {e}")
    sys.exit(1)

alive_at = []
for i in range(12):
    time.sleep(1)
    code = p.poll()
    if code is not None:
        print(f"T={i+1}s: 进程退出 code={code}")
        break
    alive_at.append(i + 1)
    print(f"T={i+1}s: 存活 PID={p.pid}")
else:
    print("T=12s: 仍存活（未退出）")
    p.terminate()

out.close(); err.close()
o = open(r"C:\Users\Administrator\AppData\Local\Temp\xl_out.txt", "rb").read()
e = open(r"C:\Users\Administrator\AppData\Local\Temp\xl_err.txt", "rb").read()
print(f"--- stdout {len(o)}B ---")
print(o.decode("utf-8", "replace")[:2000])
print(f"--- stderr {len(e)}B ---")
print(e.decode("utf-8", "replace")[:3000])
