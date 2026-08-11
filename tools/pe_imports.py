"""解析 flutter_windows.dll 的 PE 导入表：RVA → 导入函数名。

用于识别崩溃点 0x3A9FA 附近 `call [rip + 0xfa4483]` 间接调用目标。
"""
import struct

DLL = r"D:\Stellara\Music\xingli_music\build\windows\x64\runner\Release\flutter_windows.dll"
TARGET_RVA = 0x3A9E7 + 7 + 0xFA4483  # call 指令 rip 相对目标


def rva_to_off(data, rva):
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    sec = e_lfanew + 24 + opt_size
    for i in range(nsec):
        off = sec + i * 40
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
        if vaddr <= rva < vaddr + max(vsize, rawsize):
            return rawptr + (rva - vaddr)
    return None


def read_cstr(data, off):
    end = data.index(b"\0", off)
    try:
        return data[off:end].decode("utf-8")
    except Exception:
        return data[off:end].hex()


def main():
    with open(DLL, "rb") as fh:
        data = fh.read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    opt = e_lfanew + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + 112 if magic == 0x20B else opt + 96  # PE32+
    imp_rva = struct.unpack_from("<I", data, dd + 8)[0]
    imp_size = struct.unpack_from("<I", data, dd + 12)[0]
    imp_off = rva_to_off(data, imp_rva)
    print(f"导入表 RVA=0x{imp_rva:X} 大小={imp_size} 目标调用 RVA=0x{TARGET_RVA:X}")
    found = []
    i = 0
    while True:
        desc = imp_off + i * 20
        ofs = struct.unpack_from("<I", data, desc + 4)[0]  # OriginalFirstThunk
        fts = struct.unpack_from("<I", data, desc + 12)[0]  # FirstThunk
        dll_name_rva = struct.unpack_from("<I", data, desc)[0]
        if dll_name_rva == 0:
            break
        dll_name = read_cstr(data, rva_to_off(data, dll_name_rva))
        # 遍历 thunk
        idx = 0
        while True:
            thunk_rva = ofs if ofs else fts
            thunk_off = rva_to_off(data, thunk_rva)
            if thunk_off is None:
                break
            entry = struct.unpack_from("<Q", data, thunk_off + idx * 8)[0]
            if entry == 0:
                break
            func_iat_rva = fts + idx * 8
            if ofs:
                if entry & 0x8000000000000000:
                    name = f"ordinal_{entry & 0xFFFF}"
                else:
                    name = read_cstr(data, rva_to_off(data, entry))
            else:
                name = f"rva_{entry:X}"
            # 记录 IAT 槽地址 → 函数名（调用目标是 IAT 槽！）
            found.append((func_iat_rva, dll_name, name))
            idx += 1
        i += 1
    print(f"共 {len(found)} 个导入")
    # TARGET 是最接近的 IAT 槽（call 间接调用实际跳 IAT 槽）
    best = None
    for rva, dll, name in found:
        if abs(rva - TARGET_RVA) < 0x2000:
            if best is None or abs(rva - TARGET_RVA) < abs(best[0] - TARGET_RVA):
                best = (rva, dll, name)
    if best:
        print(f"\n★ 目标 0x{TARGET_RVA:X} 最近 IAT 槽: {best[1]}!{best[2]} (槽 0x{best[0]:X}, 差 {abs(best[0]-TARGET_RVA):X})")
    else:
        print("\n目标不在导入表附近——可能是引擎内部函数指针")
        # 列出 IAT 槽地址区间帮助判断
        if found:
            rvas = sorted(r for r, _, _ in found)
            print(f"IAT 槽范围: 0x{rvas[0]:X} ~ 0x{rvas[-1]:X}")


if __name__ == "__main__":
    main()
