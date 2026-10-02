"""打包 HD2 Scanner —— 多资源 archive，**只有入口**带 `-- HD2-Addon:` 声明。

为什么不能直接用 tools/build_addon.py 的 --extra：那条路径会给每个 extra 也补上声明头，
而 loader 的 discovery 只看「声明名 == 资源名哈希」（discover.lua:91），
于是每个模块都会变成**独立 addon**——在 MDL/Arsenal 里显示成 6 个 mod。

用法:
    python build.py                      # → hd2-mod/build/HD2-Scanner-vX.Y.Z.zip
    python build.py --release            # 额外拷进 junze-hd2-lua-mod/dist/ 并打印 SHA256
    python build.py --output X.zip       # 指定输出
    python build.py --verify X.zip       # 只校验已打好的包
"""
import argparse, hashlib, json, os, re, shutil, sys, time, uuid, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
for cand in (os.path.join(HERE, "..", "..", "..", "hd2-lua-mod-skill", "tools"),
             r"F:\JS\10-projects\hd2\hd2-lua-mod-skill\tools"):
    cand = os.path.abspath(cand)
    if os.path.isfile(os.path.join(cand, "hd2_archive.py")):
        sys.path.insert(0, cand)
        break
else:
    raise SystemExit("找不到 hd2_archive.py")
import hd2_archive as A

ENTRY = "mods/junze/hd2_scanner"
# 资源名 -> 源文件（相对 src/）。这些**不带**声明头。
MODULES = {
    "mods/junze/hd2_scanner/platform": "platform.lua",
    "mods/junze/hd2_scanner/registry": "registry.lua",
    "mods/junze/hd2_scanner/kernel":   "kernel.lua",
    "mods/junze/hd2_scanner/scan":     "scan.lua",
    "mods/junze/hd2_scanner/tab":      "tab.lua",
    "mods/junze/hd2_scanner/memscan":  "memscan.lua",
}
DISPLAY = "HD2 Scanner"

# 工作构建区 / 发布区 / 废案（沿用仓库既有约定，见 SKILL.md §10）
BUILD_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "build"))   # hd2-mod/build
DIST_DIR  = os.path.normpath(os.path.join(HERE, "..", "dist"))          # junze-hd2-lua-mod/dist
DEP_DIR   = os.path.join(BUILD_DIR, "_deprecated")


def version_from_source():
    """版本号只在入口源码里写一次，build.py 跟着它走，避免两边漂移。"""
    text = open(os.path.join(HERE, "src", "hd2_scanner.lua"), encoding="utf-8").read()
    m = re.search(r"^\s*version\s*=\s*'([0-9][^']*)'", text, re.M)
    if not m:
        raise SystemExit("入口源码里找不到 version = '...'")
    return m.group(1)


def guid_for(path):
    if os.path.isfile(path):
        v = open(path).read().strip()
        if v:
            return v
    v = str(uuid.uuid4())
    open(path, "w").write(v + "\n")
    print("生成并记住 GUID:", v)
    return v


def read_src(name):
    p = os.path.join(HERE, "src", name)
    b = open(p, "rb").read()
    if b.startswith(b"\xef\xbb\xbf"):
        b = b[3:]
    assert not b.startswith(b"\x1b"), "%s: 不能是字节码" % name
    assert b"\0" not in b, "%s: 含 NUL" % name
    b.decode("utf-8")
    return b


def archive_existing(out):
    """绝不覆盖已有产物：同名文件存在就先移进 _deprecated/（原因留给人补）。

    2026-10-02 就因为直接覆盖，把那份「第 5 页签会崩」的证据弄丢了。
    """
    if not os.path.exists(out):
        return None
    os.makedirs(DEP_DIR, exist_ok=True)
    base = os.path.basename(out)
    if base.lower().endswith(".zip"):
        base = base[:-4]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dst = os.path.join(DEP_DIR, "%s_被同名重建覆盖_%s.zip" % (base, stamp))
    n = 1
    while os.path.exists(dst):                      # 同一秒内连打两次也不能互相覆盖
        n += 1
        dst = os.path.join(DEP_DIR, "%s_被同名重建覆盖_%s_%d.zip" % (base, stamp, n))
    shutil.move(out, dst)
    return dst


def build(output):
    version = version_from_source()
    entry_src = read_src("hd2_scanner.lua")
    marker = ("-- HD2-Addon: " + ENTRY + "\n").encode()
    if entry_src.startswith(b"-- HD2-Addon:"):
        line, sep, rest = entry_src.partition(b"\n")
        if not sep or line.rstrip(b"\r") != marker[:-1]:
            raise SystemExit("入口声明与资源名不符: %r（应为 %r）" % (line, marker[:-1]))
        entry_src = rest

    resources = {ENTRY: A.envelope(marker + entry_src)}
    for res, fn in sorted(MODULES.items()):
        body = read_src(fn)
        if b"-- HD2-Addon:" in body[:256]:
            raise SystemExit("%s: 模块资源不能带声明头" % fn)
        resources[res] = A.envelope(body)
    archive = A.make_archive(resources)

    guid = guid_for(os.path.join(HERE, "guid.txt"))
    desc = ("Background scanner/registry for other mods. The self-drawn floating panel "
            "was removed; user settings belong in ModOptionsMenu. Requires Bingus Shared Loader v15+ / API 1, or MDL.")
    manifest = {
        "Version": 1, "Guid": guid, "Name": DISPLAY, "Description": desc,
        "Options": [{"Name": DISPLAY, "Description": desc, "Include": ["Addon"]}],
    }
    files = {
        "manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(),
        "Addon/" + A.ARCHIVE_NAME: archive,
        "Addon/" + A.ARCHIVE_NAME + ".stream": b"",
        "Addon/" + A.ARCHIVE_NAME + ".gpu_resources": b"",
    }

    out = os.path.abspath(output)
    os.makedirs(os.path.dirname(out), exist_ok=True)

    tmp = out + ".tmp"
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for path, content in sorted(files.items()):
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, content)

    if os.path.exists(out):
        def sha(p):
            return hashlib.sha256(open(p, "rb").read()).hexdigest()
        if sha(tmp) == sha(out):
            os.remove(tmp)                       # 逐字节相同：什么都没丢，不必归档
            print("内容与已有产物逐字节一致，跳过归档")
            return out, archive, version
        moved = archive_existing(out)
        print("旧产物已归档:", moved)
    os.replace(tmp, out)
    return out, archive, version


def retire_older(new_out, version):
    """build/ 只留当前版本：把同前缀的旧版本移进 _deprecated\。

    版本号一跳，旧包就不再同名，archive_existing() 抓不到它 —— 这里补上。
    """
    keep = os.path.basename(new_out)
    prefix = keep.rsplit("-v", 1)[0] + "-v"
    moved = []
    if not os.path.isdir(BUILD_DIR):
        return moved
    for fn in sorted(os.listdir(BUILD_DIR)):
        if not (fn.startswith(prefix) and fn.endswith(".zip")) or fn == keep:
            continue
        src_path = os.path.join(BUILD_DIR, fn)
        dst = os.path.join(DEP_DIR, "%s_被v%s取代.zip" % (fn[:-4], version))
        n = 1
        while os.path.exists(dst):
            n += 1
            dst = os.path.join(DEP_DIR, "%s_被v%s取代_%d.zip" % (fn[:-4], version, n))
        os.makedirs(DEP_DIR, exist_ok=True)
        shutil.move(src_path, dst)
        moved.append(dst)
    return moved


def verify(path_or_archive, is_zip=True):
    """回读校验：确认**只有入口**带声明头，且每个资源的声明名跟自己的哈希对得上。"""
    if is_zip:
        with zipfile.ZipFile(path_or_archive) as z:
            data = z.read("Addon/" + A.ARCHIVE_NAME)
    else:
        data = path_or_archive
    a = A.parse(data)
    print("archive %d 资源 / %d 字节" % (a["count"], a["size"]))
    declared, ok = [], True
    for e in a["entries"]:
        nm = None
        head = e["body"][:256].decode("utf-8", "replace")
        if head.startswith("-- HD2-Addon:"):
            nm = head.split("\n", 1)[0][len("-- HD2-Addon:"):].strip()
        print("  hash=0x%016X  %7d B  %s" % (e["name"], e["body_len"], nm or "(模块, 无声明)"))
        if nm:
            declared.append(nm)
    if declared != [ENTRY]:
        print("  !! 声明入口应当只有 %r，实际 %r" % (ENTRY, declared)); ok = False
    else:
        print("  OK: 只有入口声明，%d 个模块资源不会被 loader 当独立 addon" % len(MODULES))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", help="默认: hd2-mod/build/")
    ap.add_argument("--release", action="store_true",
                    help="打完后额外拷进 junze-hd2-lua-mod/dist/（随 git 分发），并打印 SHA256")
    ap.add_argument("--verify", metavar="ZIP")
    a = ap.parse_args()

    if a.verify:
        raise SystemExit(0 if verify(a.verify) else 1)

    version = version_from_source()
    name = "HD2-Scanner-v%s.zip" % version
    out = a.output or os.path.join(BUILD_DIR, name)
    out, archive, version = build(out)
    for old in retire_older(out, version):
        print("旧版本已归档:", old)
    print("Built %s (%d 字节)" % (out, os.path.getsize(out)))
    print()
    if not verify(out):
        raise SystemExit(1)

    if a.release:
        os.makedirs(DIST_DIR, exist_ok=True)
        dst = os.path.join(DIST_DIR, name)
        shutil.copyfile(out, dst)
        print()
        print("release ->", dst)
        print("SHA256  :", hashlib.sha256(open(dst, "rb").read()).hexdigest().upper())


if __name__ == "__main__":
    main()