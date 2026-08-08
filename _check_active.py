import re

ROOT = "C:/Users/hxy24/WorkBuddy/dyyy"

def read(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

# Recursively inline #include "file" (textual, in order, matching theos .xmi behavior)
def expand(path, seen=None):
    if seen is None:
        seen = set()
    if path in seen:
        return []
    seen.add(path)
    lines = read(path).split("\n")
    out = []
    for ln in lines:
        m = re.match(r'\s*#include\s+"([^"]+)"', ln)
        if m:
            inc = m.group(1)
            incpath = ROOT + "/" + inc
            out.append("\n//__INCLUDE__ " + inc + "\n")
            out.extend(expand(incpath, seen))
        else:
            out.append(ln + "\n")
    return out

src_lines = expand(ROOT + "/DYYY.xmi")
full_text = "".join(src_lines).split("\n")

# ---- Evaluate C preprocessor conditionals, keep only ACTIVE lines ----
# We DO NOT evaluate defined() macros deeply; treat #if / #ifdef / #ifndef by a simple
# model: #if 0 => inactive, #if 1 => active, #ifdef X => unknown(assume active to be safe
# for non-zero), #ifndef X => assume active. This catches the classic `#if 0 {...}` trap.
def is_active_stack(stack):
    return all(stack)

active_lines = []
cond_stack = []  # each entry: True if this level is active
for raw in full_text:
    s = raw.strip()
    m_if = re.match(r'^#\s*if\s+(.*)$', s)
    m_ifdef = re.match(r'^#\s*ifdef\s+(\w+)', s)
    m_ifndef = re.match(r'^#\s*ifndef\s+(\w+)', s)
    m_elif = re.match(r'^#\s*elif\b', s)
    m_else = re.match(r'^#\s*else\b', s)
    m_endif = re.match(r'^#\s*endif\b', s)
    if m_if or m_ifdef or m_ifndef:
        cond = False
        if m_if:
            expr = m_if.group(1).strip()
            if expr == "0":
                cond = False
            elif expr == "1":
                cond = True
            else:
                # unknown expression -> assume ACTIVE (conservative: keep it)
                cond = True
        elif m_ifdef or m_ifndef:
            # we don't know if macro defined -> assume ACTIVE
            cond = True
        parent = cond_stack[-1] if cond_stack else True
        cond_stack.append(cond and parent)
        active_lines.append(raw)  # keep the directive line itself (harmless)
        continue
    if m_elif or m_else:
        # flip: this level becomes active if parent active and (previous inactive)
        parent = cond_stack[-2] if len(cond_stack) >= 2 else True
        # For #else: active if parent and previous was inactive
        # We approximate: #else/#elif makes this branch active (parent active)
        cond_stack[-1] = parent  # simplest: treat else/elif as active branch
        active_lines.append(raw)
        continue
    if m_endif:
        if cond_stack:
            cond_stack.pop()
        active_lines.append(raw)
        continue
    if is_active_stack(cond_stack):
        active_lines.append(raw)

active_text = "\n".join(active_lines)

# ---- Now count braces in ACTIVE text only, skipping comments/strings/chars ----
def scan_lines(text_lines):
    in_block = False
    in_line = False
    in_str = False
    in_char = False
    escaped = False
    prev_char = ""
    depth = 0
    results = []
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
        if in_line:
            in_line = False
        results.append((i, depth, line.rstrip()))
    return results

res = scan_lines(active_text.split("\n"))

hook_re = re.compile(r'^\s*%(hook|group|subclass|ctor)\b')
print("=== ACTIVE-REGION brace depth at Logos top-level directives ===")
errors = []
for ln, depth, raw in res:
    if hook_re.match(raw):
        flag = "  <-- INSIDE BLOCK!" if depth != 0 else ""
        print(f"L{ln:6d}  depth={depth:3d}  {raw.strip()[:70]}{flag}")
        if depth != 0:
            errors.append(ln)

print(f"\n=== Final active brace depth: {res[-1][1] if res else 'n/a'} ===")

if errors:
    first = errors[0]
    print(f"\n=== First 'inside block' at L{first}. Find where depth first went nonzero ===")
    # trace backwards to find the stray open brace
    for ln, depth, raw in res:
        if ln >= first - 30 and ln <= first:
            marker = " <<<" if ln == first else ""
            print(f"  L{ln:6d} d={depth:3d}  {raw[:60]}{marker}")
else:
    print("No directive inside a block in ACTIVE regions either.")
