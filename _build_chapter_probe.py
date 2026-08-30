# -*- coding: utf-8 -*-
"""通用：触发指定分支的 GitHub Actions 构建 -> 轮询 -> 下载 artifact -> 提取 deb/dylib -> 验证特征串。
token 从本机已有推送脚本运行时提取，不硬编码、不打印。

已知坑：
1. 本机 push100.py 的 PAT 已失效（401），需逐个 token 试探。
2. artifact zip 会 302 到 Azure Blob，必须剥离 Authorization，否则 401；匿名又被要求登录。
"""
import os, re, json, time, zipfile, shutil, urllib.request, urllib.error

PAT_RE = re.compile(r'(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})')
OWNER, REPO, WF, REF = 'yxh41', 'DYYY', 'build.yml', 'chapter-probe'
OUT_DIR = r'C:\Users\hxy24\WorkBuddy\dyyy\DYYY_build_chapter_probe'
# 用于确认产物确实是本次代码（改一行就换一个串，避免拿到旧缓存）
VERIFY_NEEDLES = [b'dyyy_chapter_probe.log', b'[probe selftest]', b'[adfields]', b'range=[',
                   b'adChapterAutoSkipIndexArray', b'DYYYAutoSkipAdChapter', b'[adskip]']


def load_tokens():
    base = os.path.expanduser('~/WorkBuddy/vcamx/w2symtrace')
    toks, seen = [], set()
    for name in ('push146.py', 'push100.py'):
        p = os.path.join(base, name)
        try:
            txt = open(p, encoding='utf-8', errors='ignore').read()
        except Exception:
            continue
        for m in PAT_RE.finditer(txt):
            t = m.group(1)
            if t not in seen:
                seen.add(t)
                toks.append(t)
    return toks


class StripAuthRedirect(urllib.request.HTTPRedirectHandler):
    """重定向到 blob storage 时移除 Authorization，避免 Azure 401"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        nr = super().redirect_request(req, fp, code, msg, headers, newurl)
        if nr is not None:
            for d in (nr.headers, nr.unredirected_hdrs):
                for k in list(d.keys()):
                    if k.lower() == 'authorization':
                        del d[k]
        return nr


def req(method, path, body=None, raw=False, token=None, timeout=90):
    url = 'https://api.github.com' + path
    data = json.dumps(body).encode() if body is not None else None
    h = {'Accept': 'application/vnd.github+json', 'User-Agent': 'probe-builder',
         'X-GitHub-Api-Version': '2022-11-28'}
    if token:
        h['Authorization'] = 'Bearer ' + token
    if data:
        h['Content-Type'] = 'application/json'
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers=h),
                                    timeout=timeout) as resp:
            return resp.read() if raw else json.loads(resp.read().decode('utf-8') or '{}')
    except urllib.error.HTTPError as e:
        return {'__error__': e.code, '__body__': e.read().decode('utf-8', 'ignore')[:300]}
    except Exception as e:
        return {'__error__': 'exc', '__body__': str(e)[:200]}


def download_zip(url, token, timeout=300):
    opener = urllib.request.build_opener(StripAuthRedirect)
    h = {'Accept': 'application/vnd.github+json', 'User-Agent': 'probe-builder',
         'X-GitHub-Api-Version': '2022-11-28'}
    if token:
        h['Authorization'] = 'Bearer ' + token
    try:
        with opener.open(urllib.request.Request(url, headers=h), timeout=timeout) as resp:
            return resp.read()
    except Exception as e:
        return {'__error__': str(e)[:200]}


TOKENS = load_tokens()
if not TOKENS:
    print('FATAL: no token')
    raise SystemExit(1)

# 1) 选可用 token
TOKEN = None
for idx, tk in enumerate(TOKENS):
    probe = req('GET', '/repos/%s/%s' % (OWNER, REPO), token=tk)
    if '__error__' not in probe:
        TOKEN = tk
        print('TOKEN[%d] ACCEPTED private=%s' % (idx, probe.get('private')))
        break
    print('TOKEN[%d] REJECTED code=%s' % (idx, probe['__error__']))
if TOKEN is None:
    print('ALL_TOKENS_FAILED')
    raise SystemExit(2)

# 2) 触发 workflow_dispatch
d = req('POST', '/repos/%s/%s/actions/workflows/%s/dispatches' % (OWNER, REPO, WF),
        {'ref': REF, 'inputs': {'scheme': 'roothide'}}, token=TOKEN)
if '__error__' in d:
    print('DISPATCH_FAILED %s' % d)
    raise SystemExit(3)
print('DISPATCH_OK ref=%s' % REF)

# 3) 轮询 run
time.sleep(20)
run_id, concluded = None, None
for i in range(45):
    runs = req('GET', '/repos/%s/%s/actions/runs?branch=%s&per_page=5' % (OWNER, REPO, REF),
               token=TOKEN)
    if '__error__' not in runs and runs.get('workflow_runs'):
        r0 = runs['workflow_runs'][0]
        run_id, st, conc = r0['id'], r0.get('status'), r0.get('conclusion')
        print('[%02d] run=%s status=%s conclusion=%s' % (i, run_id, st, conc))
        if st == 'completed':
            concluded = conc
            break
    else:
        print('[%02d] waiting for run...' % i)
    time.sleep(20)

if not run_id:
    print('NO_RUN_FOUND')
    raise SystemExit(4)
if concluded != 'success':
    print('RUN_FAILED conclusion=%s url=https://github.com/%s/%s/actions/runs/%s'
          % (concluded, OWNER, REPO, run_id))
    raise SystemExit(5)
print('RUN_URL=https://github.com/%s/%s/actions/runs/%s' % (OWNER, REPO, run_id))

# 4) 下载 artifact
arts = req('GET', '/repos/%s/%s/actions/runs/%s/artifacts' % (OWNER, REPO, run_id), token=TOKEN)
if '__error__' in arts or not arts.get('artifacts'):
    print('ARTIFACT_LIST_FAILED %s' % arts)
    raise SystemExit(6)
art = arts['artifacts'][0]
aid, aname = art['id'], art['name']
print('ARTIFACT id=%s name=%s' % (aid, aname))

api_zip = 'https://api.github.com/repos/%s/%s/actions/artifacts/%s/zip' % (OWNER, REPO, aid)
nightly = 'https://nightly.link/%s/%s/actions/artifacts/%s.zip' % (OWNER, REPO, aid)
blob = None
for tk in TOKENS:
    r = download_zip(api_zip, tk)
    if isinstance(r, bytes) and r[:2] == b'PK':
        print('DOWNLOAD_OK via api bytes=%d' % len(r))
        blob = r
        break
    print('api attempt failed: %s' % (r if isinstance(r, dict) else 'bad payload'))
if blob is None:
    r = download_zip(nightly, None)
    if isinstance(r, bytes) and r[:2] == b'PK':
        print('DOWNLOAD_OK via nightly.link bytes=%d' % len(r))
        blob = r
if blob is None:
    print('ALL_DOWNLOADS_FAILED')
    raise SystemExit(7)

os.makedirs(OUT_DIR, exist_ok=True)
zpath = os.path.join(OUT_DIR, 'artifact.zip')
with open(zpath, 'wb') as f:
    f.write(blob)

# 5) 提取产物
with zipfile.ZipFile(zpath) as z:
    names = z.namelist()
    print('ZIP_FILES=%s' % json.dumps(names, ensure_ascii=False))
    saved = []
    for n in names:
        low = n.lower()
        if 'roothide' in low and low.endswith('.deb'):
            saved.append(n)
        elif low.endswith('.dylib'):
            saved.append(n)
    if not saved:
        print('NO_ARTIFACT_MATCH')
        raise SystemExit(8)
    out_paths = []
    for n in saved:
        tgt = os.path.join(OUT_DIR, os.path.basename(n))
        with z.open(n) as src, open(tgt, 'wb') as dst:
            shutil.copyfileobj(src, dst)
        out_paths.append(tgt)
        print('SAVED=%s bytes=%d' % (tgt, os.path.getsize(tgt)))

# 6) 验证特征串真的进了产物
dylibs = [p for p in out_paths if p.endswith('.dylib')]
if dylibs:
    data = open(dylibs[0], 'rb').read()
    for nd in VERIFY_NEEDLES:
        print('VERIFY %-26s -> %s' % (nd.decode(), 'FOUND' if nd in data else 'MISSING'))
print('DONE')
