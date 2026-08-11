"""反汇编崩溃函数 + 提取其引用的 .rdata 字符串，识别子系统。"""
import struct

from capstone import Cs, CS_ARCH_X86, CS_MODE_64

DLL = r"D:\Stellara\Music\xingli_music\build\windows\x64\runner\Release\flutter_windows.dll"
CRASH = 0x3A9FA
FUNC_START = CRASH - 0x400  # 往上找函数头（含 prologue）
FUNC_END = CRASH + 0x300


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
    try:
        end = data.index(b"\0", off)
        s = data[off:end].decode("utf-8", "ignore")
        return s if s.isprintable() and len(s) > 2 else None
    except Exception:
        return None


def main():
    with open(DLL, "rb") as fh:
        data = fh.read()
    # 段信息
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    sec = e_lfanew + 24 + opt_size
    sections = []
    for i in range(nsec):
        off = sec + i * 40
        name = data[off : off + 8].rstrip(b"\0").decode("ascii", "ignore")
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
        sections.append((name, vaddr, vsize, rawptr, rawsize))

    # 反汇编函数区间
    start_off = rva_to_off(data, FUNC_START)
    end_off = rva_to_off(data, FUNC_END)
    code = data[start_off:end_off]
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    print("=== 崩溃函数反汇编（含字符串引用标注）===")
    strings = []
    for ins in md.disasm(code, FUNC_START):
        mark = "  <== 崩溃点" if ins.address == CRASH else ""
        line = f"  0x{ins.address:X}: {ins.mnemonic:8s} {ins.op_str}{mark}"
        print(line)
        # lea reg, [rip+off] → 字符串
        if ins.mnemonic == "lea" and "[rip" in ins.op_str:
            try:
                disp = int(ins.op_str.split("[rip + 0x")[1].split("]")[0], 16)
                target = ins.address + ins.size + disp
                off = rva_to_off(data, target)
                if off:
                    s = read_cstr(data, off)
                    if s:
                        strings.append((ins.address, target, s))
                        print(f"        └→ 字符串 @0x{target:X}: {s!r}")
            except Exception:
                pass
    print()
    print("=== 引用的 .rdata 字符串 ===")
    for a, t, s in strings:
        print(f"  0x{a:X} → 0x{t:X}: {s!r}")


if __name__ == "__main__":
    main()
