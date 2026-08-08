import re

ROOT = "C:/Users/hxy24/WorkBuddy/dyyy"

def read(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def expand_line(path, seen=None):
    if seen is None:
        seen = set()
    if path in seen:
        return []
    seen.add(path)
    out = []
    for ln in read(path).split("\n"):
        m = re.match(r'\s*#include\s+"([^"]+)"', ln)
        if m:
            incpath = ROOT + "/" + m.group(1)
            out.extend(expand_line(incpath, seen))
        else:
            out.append(ln)
    return out

lines = expand_line(ROOT + "/DYYY.xmi")
text = "\n".join(lines)
with open(ROOT + "/DYYY.xm", "w", encoding="utf-8", newline="") as f:
    f.write(text)
print("Wrote DYYY.xm, total lines:", len(lines))
# sanity: no #include left
left = [i+1 for i,l in enumerate(lines) if re.match(r'\s*#include\b', l)]
print("Remaining #include lines in DYYY.xm:", left)
