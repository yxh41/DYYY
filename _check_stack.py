import re

ROOT = "C:/Users/hxy24/WorkBuddy/dyyy"

def read(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def expand(path, seen=None):
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
            out.append("\n//__INCLUDE__ " + m.group(1) + "\n")
            out.extend(expand(incpath, seen))
        else:
            out.append(ln + "\n")
    return out

src_lines = expand(ROOT + "/DYYY.xmi")
text = "".join(src_lines).split("\n")

# ----- Track block stack: openers and closers, skipping comments/strings -----
def scan(text_lines):
    in_block = False
    in_line = False
    in_str = False
    in_char = False
    escaped = False
    prev_char = ""
    stack = []          # list of (kind, lineno)
    results = []        # per line: (lineno, len(stack), raw)
    for i, line in enumerate(text_lines, 1):
        # process char-by-char for brace/comment/string state
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
                stack.append(("{", i))
            elif ch == "}":
                if stack and stack[-1][0] == "{":
                    stack.pop()
                else:
                    stack.append(("UNBALANCED_CLOSE", i))
            prev_char = ch
        if in_line:
            in_line = False
        # Now handle ObjC block keywords on this (comment/string-free-for-keyword) line.
        # Re-evaluate with comments/strings stripped for keyword detection.
        s = line
        s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
        s = re.sub(r'//[^\n]*', '', s)
        # crude string strip (enough for keyword checks)
        s = re.sub(r'"[^"]*"', '""', s)
        s = re.sub(r"'[^']*'", "''", s)
        stripped = s.strip()
        # openers
        m_impl = re.match(r'^@implementation\b', stripped)
        m_intf = re.match(r'^@interface\b', stripped)
        m_proto = re.match(r'^@protocol\b', stripped)
        m_end = re.match(r'^@end\b', stripped)
        if m_impl:
            stack.append(("@implementation", i))
        elif m_intf:
            stack.append(("@interface", i))
        elif m_proto:
            stack.append(("@protocol", i))
        elif m_end:
            if stack and stack[-1][0] in ("@implementation", "@interface", "@protocol"):
                stack.pop()
            else:
                stack.append(("UNBALANCED_END", i))
        results.append((i, len(stack), line.rstrip()))
    return results

res = scan(text)

# Group-nesting awareness: %group opens a logical container that PERMITS %hook inside it.
hook_re = re.compile(r'^\s*%(hook|group|subclass|ctor)\b')
open_kinds = ("{", "@implementation", "@interface", "@protocol")

print("=== Scan for %hook/%group/%subclass inside a non-group block (theos 'inside a block') ===")
group_depth = 0  # count of open %group
errors = []
for i, (ln, depth, raw) in enumerate(res):
    s2 = re.sub(r'/[*/].*?(\*/)?', '', raw)
    s2 = re.sub(r'"[^"]*"', '""', s2)
    stripped = s2.strip()
    mg = re.match(r'%(group|hook|subclass|ctor|end|new|property)\b', stripped)
    if not mg:
        continue
    directive = mg.group(1)
    if directive == "group":
        # entering a group: this group itself must be at top level (not inside brace/@impl)
        if depth != 0:
            errors.append((ln, "group opened while block stack depth=%d" % depth, raw))
        group_depth += 1
    elif directive in ("hook", "subclass"):
        # %hook/%subclass allowed only at top level OR inside a %group
        if depth != 0 and group_depth == 0:
            errors.append((ln, "hook/subclass inside block (stack depth=%d, group_depth=%d)" % (depth, group_depth), raw))
    elif directive == "end":
        # %end closes %group or %hook; if closing %group:
        if group_depth > 0:
            group_depth -= 1
    elif directive == "ctor":
        # %ctor { ... } is allowed at top level; if depth !=0 something is open
        if depth != 0:
            errors.append((ln, "ctor while block stack depth=%d" % depth, raw))

print("Errors found:", len(errors))
for ln, msg, raw in errors[:20]:
    print(f"  L{ln}: {msg}")
    print(f"      {raw.strip()[:80]}")

# Also report final stack (should be empty)
final_stack = res[-1][1] if res else -1
print("\nFinal block-stack size:", final_stack)

# If errors, show context around first error (last few stack entries)
if errors:
    first_ln = errors[0][0]
    # recompute stack up to first error to find what's open
    print(f"\n=== Context around first error L{first_ln} (last open blockers) ===")
    # rebuild stack precisely at that line using a focused scan
    stack_now = []
    for i, (ln, depth, raw) in enumerate(res):
        if ln > first_ln:
            break
        s2 = re.sub(r'/[*/].*?(\*/)?', '', raw)
        s2 = re.sub(r'"[^"]*"', '""', s2)
        s2 = re.sub(r"'[^']*'", "''", s2)
        st = s2.strip()
        if re.match(r'^@implementation\b', st):
            stack_now.append(("@implementation", ln))
        elif re.match(r'^@interface\b', st):
            stack_now.append(("@interface", ln))
        elif re.match(r'^@protocol\b', st):
            stack_now.append(("@protocol", ln))
        elif re.match(r'^@end\b', st):
            if stack_now and stack_now[-1][0] in ("@implementation","@interface","@protocol"):
                stack_now.pop()
        # braces already excluded from this focused view; rely on depth
    print("  Open ObjC-block stack at error line:", stack_now)
    print("  (brace depth at error = the 'depth' reported by full scan)")
