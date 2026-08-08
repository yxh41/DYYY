import re

ROOT = "C:/Users/hxy24/WorkBuddy/dyyy"

def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return text

def resolve(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    out = []
    for ln in lines:
        m = re.match(r'\s*#include\s+"([^"]+)"', ln)
        if m:
            inc = m.group(1)
            out.append("\n//__INCLUDE__%s\n" % inc)
            out.extend(resolve(ROOT + "/" + inc))
        else:
            out.append(ln)
    return out

all_lines = resolve(ROOT + "/DYYY.xmi")
clean = strip_comments("".join(all_lines))

depth = 0
reported = []
for i, line in enumerate(clean.split("\n"), 1):
    for ch in line:
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
    stripped = line.strip()
    if re.match(r'%(hook|group|subclass|ctor|new)\b', stripped):
        reported.append((i, depth, stripped[:60]))

bad = [r for r in reported if r[1] != 0]
print("=== Brace depth at each Logos directive (depth != 0 => inside a block) ===")
for r in reported:
    flag = "  <-- INSIDE BLOCK!" if r[1] != 0 else ""
    print("line %6d  depth=%3d  %s%s" % (r[0], r[1], r[2], flag))
print("\n=== Final brace depth (should be 0):", depth, "===")
if bad:
    print("\nFIRST directive inside a block: line %d depth %d %s" % (bad[0][0], bad[0][1], bad[0][2]))
