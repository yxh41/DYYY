import re, sys

ROOT = "C:/Users/hxy24/WorkBuddy/dyyy"

def read(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

# Recursively inline #include "file" (textual, in order, matching theos .xmi behavior)
def expand(path, depth=0, seen=None):
    if seen is None:
        seen = set()
    abs = path
    if abs in seen:
        return []
    seen.add(abs)
    lines = read(abs).split("\n")
    out = []
    for ln in lines:
        m = re.match(r'\s*#include\s+"([^"]+)"', ln)
        if m:
            inc = m.group(1)
            # resolve relative to ROOT (all includes are bare filenames)
            incpath = ROOT + "/" + inc
            out.append("\n//__INCLUDE__ " + inc + "\n")
            out.extend(expand(incpath, depth + 1, seen))
        else:
            out.append(ln + "\n")
    return out

src_lines = expand(ROOT + "/DYYY.xmi")

# ---- Careful scanner: count only real C/ObjC braces, skipping comments/strings/chars ----
def scan(text):
    in_block = False
    in_line = False
    in_str = False
    in_char = False
    escaped = False
    depth = 0
    per_line_depth = []  # depth AFTER processing each line
    for ch in text:
        if in_block:
            if ch == "*" and not escaped:
                # lookahead handled below
                pass
            if ch == "/" and prev_char == "*":
                in_block = False
            prev_char = ch
            continue
        if in_line:
            if ch == "\n":
                in_line = False
            continue
        if in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_str = False
            continue
        if in_char:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "'":
                in_char = False
            continue
        # not in any special state
        if ch == "/":
            # possible start of comment; peek next handled by prev_char logic
            pass
        if ch == "/" and prev_char == "/":
            in_line = True
        elif ch == "*" and prev_char == "/":
            in_block = True
        elif ch == '"':
            in_str = True
        elif ch == "'":
            in_char = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        prev_char = ch
    return depth

# We need per-line; redo with line splitting but preserve state across lines for block/str.
def scan_lines(text_lines):
    in_block = False
    in_line = False
    in_str = False
    in_char = False
    escaped = False
    prev_char = ""
    depth = 0
    results = []  # (lineno, depth_after_line, raw_line)
    for i, line in enumerate(text_lines, 1):
        for ch in line:
            if in_block:
                if ch == "*":
                    pass
                elif ch == "/" and prev_char == "*":
                    in_block = False
                prev_char = ch
                continue
            if in_line:
                # rest of line is comment
                break
            if in_str:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    in_str = False
                prev_char = ch
                continue
            if in_char:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == "'":
                    in_char = False
                prev_char = ch
                continue
            # normal
            if ch == "/" and prev_char == "/":
                in_line = True
                prev_char = ch
                continue
            if ch == "*" and prev_char == "/":
                in_block = True
                prev_char = ch
                continue
            if ch == '"':
                in_str = True
            elif ch == "'":
                in_char = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            prev_char = ch
        # end of line: line comment resets naturally (in_line stays True until break above)
        if in_line:
            in_line = False
        results.append((i, depth, line.rstrip()))
    return results

full = "".join(src_lines)
res = scan_lines(src_lines)

# Find Logos top-level directives and report depth
hook_re = re.compile(r'^\s*%(hook|group|subclass|ctor)\b')
print("=== Brace depth at Logos top-level directives (depth!=0 => inside a block) ===")
errors = []
for ln, depth, raw in res:
    if hook_re.match(raw):
        flag = "  <-- INSIDE BLOCK!" if depth != 0 else ""
        print(f"L{ln:6d}  depth={depth:3d}  {raw.strip()[:70]}{flag}")
        if depth != 0:
            errors.append(ln)

print(f"\n=== Final brace depth (must be 0): {res[-1][1] if res else 'n/a'} ===")

if errors:
    first = errors[0]
    print(f"\n=== First 'inside block' directive at L{first}. Showing context (depth track) ===")
    # show lines around where depth became nonzero before this
    # find earliest line where, after it, depth is already >0 and stays
    print("Context before first error (lineno : depth : first 60 chars):")
    for ln, depth, raw in res:
        if ln >= first - 25 and ln <= first:
            marker = " <<<" if ln == first else ""
            print(f"  L{ln:6d} d={depth:3d}  {raw[:60]}{marker}")
else:
    print("No Logos directive found inside a block. The error must come from elsewhere.")
