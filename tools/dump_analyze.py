"""解析 WER minidump：异常信息 + 崩溃线程调用栈（模块+偏移）。"""
import struct
import sys

from minidump.minidumpfile import MinidumpFile


def module_for(md, addr: int):
    for m in md.modules.modules:
        base = m.baseaddress
        if base <= addr < base + m.size:
            return m, addr - base
    return None, addr


def build_memory_map(md):
    """{start_addr: bytes}，覆盖 memory_segments 与 64 位段。"""
    segs = {}
    for s in getattr(md, "memory_segments", None) or []:
        try:
            data = s.to_bytes()
            segs[s.start_address] = data
        except Exception:
            pass
    seg64 = getattr(md, "memory_segments_64", None)
    if seg64 is not None:
        for s in getattr(seg64, "memory_descriptors", []) or []:
            try:
                data = s.to_bytes()
                segs[s.start_address] = data
            except Exception:
                pass
    return segs


def read_va(mem, addr: int, size: int):
    for base, data in mem.items():
        if base <= addr < base + len(data):
            off = addr - base
            if off + size <= len(data):
                return data[off : off + size]
    return None


def main(path: str):
    md = MinidumpFile.parse(path)
    mem = build_memory_map(md)
    print("=" * 62)
    print("异常信息")
    print("=" * 62)
    tid = None
    rip = 0
    rsp = 0
    code = 0
    ctx_bytes = None  # 异常时刻线程上下文（x64 CONTEXT）
    if md.exception is not None:
        for rec in md.exception.exception_records:
            er = rec.ExceptionRecord
            raw_code = getattr(er, "ExceptionCode_raw", None) or er.ExceptionCode
            code = int(raw_code, 0) if isinstance(raw_code, str) else int(raw_code)
            addr = getattr(er, "ExceptionAddress", 0)
            addr = int(addr, 0) if isinstance(addr, str) else int(addr or 0)
            info = er.ExceptionInformation
            print(f"异常代码: 0x{code:08X}  {code}")
            print(f"崩溃地址: 0x{addr:016X}")
            if info:
                v0 = int(info[0], 0) if isinstance(info[0], str) else int(info[0])
                print(f"参数0(读/写地址): 0x{v0:016X}")
                if len(info) > 1:
                    v1 = int(info[1], 0) if isinstance(info[1], str) else int(info[1])
                    print(f"参数1(访问地址): 0x{v1:016X}")
            tid = rec.ThreadId
            # ThreadContext: MINIDUMP_LOCATION_DESCRIPTOR（DataSize/Rva）
            tc = rec.ThreadContext
            if tc is not None and getattr(tc, "Rva", None) is not None:
                with open(path, "rb") as fh:
                    fh.seek(tc.Rva)
                    ctx_bytes = fh.read(tc.DataSize)
        if ctx_bytes is not None and len(ctx_bytes) >= 0x100:
            # x64 CONTEXT: Rip@0xF8, Rsp@0x98
            rip = struct.unpack("<Q", ctx_bytes[0xF8 : 0x100])[0]
            rsp = struct.unpack("<Q", ctx_bytes[0x98 : 0xA0])[0]
        print(f"崩溃线程: TID={tid}  异常RIP=0x{rip:016X}  RSP=0x{rsp:016X}")
        m0, off0 = module_for(md, rip)
        print(f"  → 崩溃点: {m0.name.split(chr(92))[-1] if m0 else '?'}+0x{off0:X}")
    else:
        print("无异常流")

    print()
    print("=" * 62)
    print("崩溃线程调用栈（栈扫描，模块+偏移）")
    print("=" * 62)
    for t in md.threads.threads:
        if t.ThreadId != tid:
            continue
        if rip == 0:
            c = t.ContextObject
            rip = getattr(c, "Rip", 0) or 0
            rsp = getattr(c, "Rsp", 0) or 0
        m, off = module_for(md, rip)
        print(f"  [帧0/崩溃点] 0x{rip:016X}  "
              f"{m.name.split(chr(92))[-1] if m else '?'}+0x{off:X}")

        # 栈扫描：RSP 起 8KB，收集落在模块代码段内的返回值
        frames = []
        for i in range(0, 8192, 8):
            raw = read_va(mem, rsp + i, 8)
            if raw is None:
                break
            (val,) = struct.unpack("<Q", raw)
            m2, off2 = module_for(md, val)
            if m2 is None:
                continue
            # 粗判代码段（跳过 PE 头/数据区）
            if 0x1000 <= off2 < m2.size - 0x1000:
                frames.append((i, val, m2, off2))
        seen = set()
        for i, val, m2, off2 in frames:
            key = (m2.name, off2 >> 12)
            if key in seen:
                continue
            seen.add(key)
            print(f"  [栈+0x{i:04X}] 0x{val:016X}  "
                  f"{m2.name.split(chr(92))[-1]}+0x{off2:X}")
        break

    print()
    print("=" * 62)
    print("全部线程（RIP 定位，找第二现场）")
    print("=" * 62)
    for t in md.threads.threads[:24]:
        try:
            c = t.ContextObject
            r = getattr(c, "Rip", 0) or 0
            m, off = module_for(md, r)
            name = m.name.split("\\")[-1] if m else "?"
            print(f"  TID={t.ThreadId:<8} {name}+0x{off:X}")
        except Exception:
            pass


if __name__ == "__main__":
    main(sys.argv[1])
