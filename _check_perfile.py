import re

ROOT = "C:/Users/hxy24/WorkBuddy/dyyy"
FILES = [
    "DYYY.xmi", "DYYYDownload.xm", "DYYYPlayback.xm", "DYYYUI.xm",
    "DYYYFeed.xm", "DYYYInteraction.xm", "DYYYMisc.xm",
]

def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return text

for fname in FILES:
    with open(ROOT + "/" + fname, 'r', encoding='utf-8', errors='replace') as f:
        raw = f.read()
    clean = strip_comments(raw)
    # brace balance ignoring strings roughly
    depth = 0
    maxdepth = 0
    bad_lines = []
    for i, line in enumerate(clean.split("\n"), 1):
        for ch in line:
            if ch == '{':
                depth += 1
                maxdepth = max(maxdepth, depth)
            elif ch == '}':
                depth -= 1
        if depth < 0:
            bad_lines.append((i, depth))
    # logos directive counts
    hooks = len(re.findall(r'(?m)^\s*%hook\b', raw))
    ends  = len(re.findall(r'(?m)^\s*%end\b', raw))
    groups = len(re.findall(r'(?m)^\s*%group\b', raw))
    subs  = len(re.findall(r'(?m)^\s*%subclass\b', raw))
    ctors = len(re.findall(r'(?m)^\s*%ctor\b', raw))
    print("%-22s braces_end=%d maxdepth=%d  %%hook=%d %%end=%d %%group=%d %%subclass=%d %%ctor=%d"
          % (fname, depth, maxdepth, hooks, ends, groups, subs, ctors))
    if depth != 0:
        print("    -> UNBALANCED BRACES (final depth %d)" % depth)
    if (hooks + groups + subs + ctors) != ends:
        print("    -> DIRECTIVE MISMATCH: opens=%d closes=%d"
              % (hooks + groups + subs + ctors, ends))
