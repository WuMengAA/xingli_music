"""一次性辅助脚本：移除因取色改为 context.appColors/appText 而失效的 const。

思路：读取 flutter analyze 报出的 invalid_constant / non_constant_* 位置，
从该位置向前回溯，找到覆盖它的最近一个 `const` 关键字并删除。
"""
import re
import subprocess
import sys

ERR = re.compile(
    r"-\s(lib\\[^\s:]+):(\d+):(\d+)\s-\s"
    r"(invalid_constant|non_constant_list_element|non_constant_map_value|"
    r"const_constructor_param_type_mismatch|"
    r"const_eval_method_invocation|non_constant_default_value)"
)

# 在 Dart 里，`const` 后面跟的是构造调用/字面量。回溯时匹配这些起始形态。
CONST_TOKEN = re.compile(r"\bconst\b")


def analyze():
    out = subprocess.run(
        ["flutter", "analyze", "lib"], capture_output=True, text=True, shell=True
    ).stdout
    hits = []
    for line in out.splitlines():
        m = ERR.search(line)
        if m:
            hits.append((m.group(1).replace("\\", "/"), int(m.group(2)), int(m.group(3))))
    return hits


def offset_of(text, line, col):
    lines = text.split("\n")
    return sum(len(x) + 1 for x in lines[: line - 1]) + (col - 1)


def matching_close(text, open_idx):
    """给定 '(' 或 '[' 或 '{' 的下标，返回配对闭合符下标。"""
    pairs = {"(": ")", "[": "]", "{": "}"}
    opener = text[open_idx]
    closer = pairs[opener]
    depth = 0
    i = open_idx
    while i < len(text):
        ch = text[i]
        if ch in "\"'":
            quote = ch
            i += 1
            while i < len(text) and text[i] != quote:
                if text[i] == "\\":
                    i += 1
                i += 1
        elif ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def const_covers(text, const_idx, target_idx):
    """判断 const_idx 处的 const 表达式是否覆盖 target_idx。"""
    j = const_idx + 5
    while j < len(text) and text[j] in " \t\n":
        j += 1
    # 找到该 const 表达式的第一个分组符
    k = j
    while k < len(text) and text[k] not in "([{;,":
        k += 1
    if k >= len(text) or text[k] not in "([{":
        return False
    close = matching_close(text, k)
    return close != -1 and const_idx < target_idx < close


def fix_file(path, positions):
    with open(path, encoding="utf-8") as f:
        text = f.read()

    # 从后往前处理，避免下标漂移
    targets = sorted({offset_of(text, ln, col) for ln, col in positions}, reverse=True)
    removed = 0
    for tgt in targets:
        # 回溯找覆盖该位置的最近 const
        best = None
        for m in CONST_TOKEN.finditer(text, 0, tgt):
            if const_covers(text, m.start(), tgt):
                best = m
        if best is None:
            continue
        s, e = best.start(), best.end()
        while e < len(text) and text[e] == " ":
            e += 1
        text = text[:s] + text[e:]
        removed += 1

    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    return removed


def main():
    for rnd in range(1, 9):
        hits = analyze()
        if not hits:
            print(f"第 {rnd} 轮：无 const 相关错误，收工")
            return 0
        by_file = {}
        for path, ln, col in hits:
            by_file.setdefault(path, []).append((ln, col))
        total = 0
        for path, pos in by_file.items():
            n = fix_file(path, pos)
            total += n
            print(f"  {path}: 移除 {n} 处 const")
        print(f"第 {rnd} 轮：命中 {len(hits)}，移除 {total}")
        if total == 0:
            print("无法自动处理，剩余需手工修：", hits[:20])
            return 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
