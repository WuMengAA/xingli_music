"""反汇编崩溃点：读磁盘上的 flutter_windows.dll，反汇编 0x3A9FA 附近指令。"""
import struct
import sys

from capstone import Cs, CS_ARCH_X86, CS_MODE_64

DLL = r"D:\Stellara\Music\xingli_music\build\windows\x64\runner\Release\flutter_windows.dll"
OFFSET = 0x3A9FA  # 崩溃偏移


def rva_to_offset(data: bytes) -> int:
    """PE 文件 RVA → 文件偏移（找 .text 段）。"""
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[e_lfanew : e_lfanew + 4] == b"PE\0\0", "not PE"
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    opt = e_lfanew + 24
    # 段表
    sec = opt + opt_size
    for i in range(nsec):
        off = sec + i * 40
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
        if vaddr <= OFFSET < vaddr + max(vsize, rawsize):
            return rawptr + (OFFSET - vaddr)
    raise ValueError("offset not in any section")


def main():
    with open(DLL, "rb") as fh:
        data = fh.read()
    fo = rva_to_offset(data)
    print(f"RVA 0x{OFFSET:X} → 文件偏移 0x{fo:X}")
    # 反汇编前后各 32 字节
    start = fo - 32
    code = data[start : fo + 64]
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = False
    print("=== 崩溃点前后指令 ===")
    for ins in md.disasm(code, OFFSET - 32):
        mark = "  <== 崩溃点" if ins.address == OFFSET else ""
        print(f"  0x{ins.address:X}: {ins.mnemonic:8s} {ins.op_str}{mark}")


if __name__ == "__main__":
    main()
