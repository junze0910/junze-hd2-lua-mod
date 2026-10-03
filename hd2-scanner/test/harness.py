"""公共测试夹具：起一个真 LuaJIT(lupa)，把资源名 preload 到 src/ 下的文件。"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC  = os.path.join(ROOT, "src")
# ⚠ 夹具路径必须是**纯 ASCII**：Lua 的 io.open 按 ANSI 解路径，
# 含中文（%TEMP% 里的用户名）会静默失败 —— 见设计定稿 13.6 坑 #2。
WORK = os.path.join(os.environ.get("SystemDrive", "C:") + "\\", "lua_sandbox_hd2_scanner")

for cand in (r"F:\JS\pylibs", os.path.expandvars(r"%USERPROFILE%\pylibs")):
    if os.path.isdir(os.path.join(cand, "lupa")) and cand not in sys.path:
        sys.path.insert(0, cand)
from lupa.luajit21 import LuaRuntime

    # ⚠ 2026-10-04：ui / registry 已退役（见 src/ui.lua 顶部横幅）。
    #   这里**故意不 preload**，测试才等于发布包；要复活浮窗面板请连 build.py 一起加回来。
ENTRY = "mods/junze/hd2_scanner"
FILES = {
    ENTRY:                              "hd2_scanner.lua",
    "mods/junze/hd2_scanner/platform":   "platform.lua",
    "mods/junze/hd2_scanner/scan":       "scan.lua",
    "mods/junze/hd2_scanner/tab":        "tab.lua",
    "mods/junze/hd2_scanner/kernel":     "kernel.lua",
    "mods/junze/hd2_scanner/memscan":    "memscan.lua",
    "mods/junze/hd2_scanner/aob":        "aob.lua",
}


def src(name):
    return open(os.path.join(SRC, FILES[name]), "rb").read().decode("utf-8")


def source_of(fname):
    return open(os.path.join(SRC, fname), "rb").read().decode("utf-8")


def new_lua():
    """返回一个已 preload 好全部资源的 LuaRuntime（入口还没执行）。"""
    os.makedirs(os.path.join(WORK, "Logs"), exist_ok=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    pre = []
    for res, fn in FILES.items():
        pre.append("package.preload[%r] = function() return assert(loadfile(%r))() end"
                   % (res, os.path.join(SRC, fn).replace("\\", "/")))
    lua.execute("\n".join(pre))
    lua.execute("CowboyBingusModLoader = { version=16, api=1, modules={}, "
                "log_directory=[=[%s/Logs]=] }" % WORK.replace("\\", "/"))
    return lua


def boot(lua):
    """执行入口，返回 P 的访问前缀字符串。"""
    lua.execute(source_of("hd2_scanner.lua"))
    return "rawget(_G,%r)" % ENTRY