"""装载 + 插件注册表回归（不需要游戏、不需要 stingray）。"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness

CHECKS = []


def check(name, cond, extra=""):
    CHECKS.append((name, bool(cond), extra))
    print("  [%s] %s%s" % ("OK" if cond else "FAIL", name, ("  " + str(extra)) if extra and not cond else ""))


def main():
    cfg = os.path.join(harness.WORK, "HD2Scanner.cfg")
    if os.path.exists(cfg): os.remove(cfg)        # 每次从干净状态开始
    lua = harness.new_lua()
    P = harness.boot(lua)
    ev = lua.eval

    check("入口 status=ready", ev(P + ".status") == "ready")
    mods = ev("(function() local t={} for k in pairs(rawget(_G,'mods/junze/hd2_scanner').modules) do t[#t+1]=k end table.sort(t) return table.concat(t,',') end)()")
    check("默认不加载 ui（draw=off，连 require 都不做）",
          mods == "api,kernel,memscan,platform,registry,scan,tab", mods)
    check("_G.HD2Menu 已注册", ev("rawget(_G,'HD2Menu') ~= nil and rawget(_G,'HD2Menu').api == 1"))
    check("初始 2 页（面板 + 扫描内核各自注册）", ev("rawget(_G,'HD2Menu').page_count()") == 2)

    lua.execute("HD2Menu.register{ id='b', title='B', order=20 }")
    lua.execute("HD2Menu.register{ id='a', title='A', order=10 }")
    check("注册后 4 个", ev("rawget(_G,'HD2Menu').page_count()") == 4)
    check("按 order 排序", ev("(function() local t={} for _,p in ipairs(rawget(_G,'mods/junze/hd2_scanner').pages) do t[#t+1]=p.id end return table.concat(t,',') end)()") == "hd2_scanner,scanner_kernel,a,b")

    lua.execute("HD2Menu.register{ id='bad', api=99 }")
    check("api 不匹配被拒", ev("rawget(_G,'HD2Menu').page_count()") == 4)

    lua.execute("HD2Menu.register{ id='a', title='A again' }")
    check("重复注册幂等", ev("rawget(_G,'HD2Menu').page_count()") == 4)

    n, title = lua.eval("(function() local r,t = rawget(_G,'mods/junze/hd2_scanner').rows() return tostring(#r)..'|'..tostring(t) end)()" ).split("|")
    n = int(n)
    check("rows() 可用", n == 4 and title == "HD2 MENU", "%r %r" % (n, title))

    lua.execute("HD2Menu.unregister('a')")
    check("反注册", ev("rawget(_G,'HD2Menu').page_count()") == 3)

    # pending 队列：面板加载前就注册的插件
    lua2 = harness.new_lua()
    lua2.execute("HD2MenuQueue = { { id='q', attach=function(api) api.register{ id='q', title='Q' } end } }")
    P2 = harness.boot(lua2)
    check("pending 队列已回灌", lua2.eval("rawget(_G,'HD2Menu').page_count()") == 3 and lua2.eval("rawget(_G,'HD2MenuQueue') == nil"))

    # 跑 200 帧（无 game.dll / 无 stingray，应优雅降级不报错）
    lua.execute("for i=1,200 do update(0.016) end")
    check("200 帧无错", ev(P + ".errs or 0") == 0)
    check("降级到热键", ev(P + ".trigger") == "hotkey")
    check("update/shutdown 已挂钩", ev("type(update)") == "function" and ev("type(shutdown)") == "function")
    lua.execute("shutdown()")
    check("shutdown 不抛", True)

    # ---- draw=on 时才惰性加载 ui ----
    open(cfg, "w").write("draw=on\nclaim=on\nprobe=on\nallow_5th=off\n")
    lua3 = harness.new_lua()
    P3 = harness.boot(lua3)
    mods_before = lua3.eval("(function() local t={} for k in pairs(rawget(_G,'mods/junze/hd2_scanner').modules) do t[#t+1]=k end table.sort(t) return table.concat(t,',') end)()")
    check("draw=on 前 ui 仍未加载", "ui" not in mods_before.split(","), mods_before)
    lua3.execute("for i=1,200 do update(0.016) end")
    mods_after = lua3.eval("(function() local t={} for k in pairs(rawget(_G,'mods/junze/hd2_scanner').modules) do t[#t+1]=k end table.sort(t) return table.concat(t,',') end)()")
    check("draw=on 后 ui 惰性加载", "ui" in mods_after.split(","), mods_after)
    check("draw=on 后 200 帧无错", lua3.eval("rawget(_G,'mods/junze/hd2_scanner').errs or 0") == 0)
    check("cfg 被真正读到（draw=on 生效）",
          lua3.eval("rawget(_G,'mods/junze/hd2_scanner').cfg.draw") is True)
    # 回归守卫：日志必须真的落到盘上（中文路径会静默失败）
    logf = os.path.join(harness.WORK, "Logs", "HD2Scanner.log")
    check("日志真的落盘了", os.path.exists(logf) and os.path.getsize(logf) > 100,
          "size=%s" % (os.path.getsize(logf) if os.path.exists(logf) else 'missing'))
    os.remove(cfg)

    # ---- cfg 行尾带注释也必须能解析 ----
    # ★ 默认生成的 cfg 每行都带注释；只测 "draw=on\n" 的话，
    #   `[^#]*` 那个 bug 完全测不出来（2026-10-02 就这么漏过去的）
    open(cfg, "w").write("draw=on   # 行尾注释\nclaim=off  # 再来一个\n")
    lua4 = harness.new_lua()
    harness.boot(lua4)
    check("cfg 带行尾注释：draw 读到 true",
          lua4.eval("rawget(_G,'mods/junze/hd2_scanner').cfg.draw") is True)
    check("cfg 带行尾注释：claim 读到 false",
          lua4.eval("rawget(_G,'mods/junze/hd2_scanner').cfg.claim") is False)
    check("cfg 带行尾注释：probe 保持默认 true",
          lua4.eval("rawget(_G,'mods/junze/hd2_scanner').cfg.probe") is True)
    os.remove(cfg)

    # ---- 扫描内核（阶段 1）对外接口 ----
    lua5 = harness.new_lua()
    P5 = harness.boot(lua5)
    check("_G.HD2Scanner 已导出", lua5.eval("type(rawget(_G,'HD2Scanner'))") == "table")
    check("内核 version=1", lua5.eval("rawget(_G,'HD2Scanner').version") == 1)
    check("memscan scan_request 已导出", lua5.eval("type(rawget(_G,'HD2Scanner').scan_request)") == "function")
    badreq = lua5.eval("(function() local ok,why = rawget(_G,'HD2Scanner').scan_request({id='', patterns={}}) return tostring(ok)..'|'..tostring(why) end)()")
    check("memscan 拒绝非法请求", badreq.startswith("false|"), badreq)
    lua5.execute("K_H = HD2Scanner.request(0xFB8D88A3, 'WeaponMagazineComponentData')")
    check("request 返回 handle", lua5.eval("type(K_H.declare_need)") == "function")
    snap = lua5.eval("(function() local s = HD2Scanner.poll(0xFB8D88A3) return tostring(#s.entries)..'|'..tostring(s.generation) end)()")
    check("poll 空表时不报错", snap == "0|0", snap)
    lua5.execute("K_H.declare_need()")
    check("declare_need 置 urgent", lua5.eval("rawget(_G,'HD2Scanner').status().urgent") is True)
    pc = lua5.eval("(function() local c=0 for _,p in ipairs(rawget(_G,'mods/junze/hd2_scanner').pages) do if p.id=='scanner_kernel' then c=c+1 end end return c end)()")
    check("内核页在注册表里", pc == 1, pc)

    # ---- 源码卫生：几何/命中区字段必须「画」和「读」是**同一个宿主表** ----
    # 2026-10-02 吃过这个亏：panel_draw 写 G.zones，panel_input 读 P.zones，
    # 而 P.zones 从未被赋值 -> hit 恒为 nil -> 悬停不亮、点击永不触发。
    # 这类「单边笔误」的行为没法离线夹具化（输入走 user32），但宿主表不一致一眼可查。
    ui_src = harness.source_of("ui.lua")
    stray = []
    for field in ("zones", "header", "frame"):
        hosts = sorted(set(re.findall(r"\b([A-Za-z_]\w*)\.%s\b" % field, ui_src)))
        if len(hosts) != 1:
            stray.append("%s on %s" % (field, hosts))
    check("几何字段只有一个宿主表", not stray, stray)

    # ---- 源码卫生：面板必须是「上 → 下」布局 ----
    # Stingray 的 screen gui 是 **y 轴向上**的（原点左下），而人读界面是从上往下。
    # panel_draw 里靠 fy(d) = ytop - d 把「从可视顶端往下 d」镜像回 gui 的 y。
    # 2026-10-02 之前这段整段按 y 向下写，于是整个面板上下镜像：标题跑最底、
    # hint 跑最顶、行序整个倒过来（「‹ 返回」顶在最上面）。
    mirror_bad = []
    if "rect(x, fy(head), w, head, 980, hdr)" not in ui_src:
        mirror_bad.append("标题栏没走 fy()")
    if "local ry = fy(head + vi*rowh)" not in ui_src:
        mirror_bad.append("行序没走 fy()")
    if "y + h - foot" in ui_src:
        mirror_bad.append("残留旧写法 y + h - foot")
    check("面板布局是镜像修正后的（上→下）", not mirror_bad, mirror_bad)

    # ---- 源码卫生：local 必须声明在所有用它的函数之前 ----
    # Lua 的词法作用域是【位置性】的：函数里引用的局部变量必须在函数【之前】声明，
    # 否则解析成全局 nil。2026-10-02 实机踩到：cfg_save / build_page_rows 用了 CFG，
    # 而 `local CFG` 在后面 -> 每次面板渲染页面都抛 attempt to index global 'CFG'。
    sc = harness.source_of("hd2_scanner.lua")
    bad_local = []
    for name in ("CFG", "CFG_FILE"):
        decl = None
        for i, l in enumerate(sc.split("\n"), 1):
            code = re.sub(r"--.*$", "", l)
            m = re.match(r"\s*local\s+([^=]*)", code)      # 只看 = 之前那段
            if decl is None and m and re.search(r"\b%s\b" % name, m.group(1)):
                decl = i                                  # 支持 "local CFG, CFG_FILE"
                break
            if re.search(r"\b%s\b" % name, code):
                bad_local.append("%s: L%d 被引用，但声明在 L%d 之后" % (name, i, decl or -1))
                break
    check("local 声明在第一处引用之前", not bad_local, bad_local)

    # ---- 源码卫生：键位铁律——绝不允许绑 ESC 菜单会吃的键 ----
    # 我们只能 GetAsyncKeyState「偷看」，吃不到事件，游戏会收到同一个键。
    # Enter / Backspace / Esc 会被游戏菜单吃掉（退菜单 / 点到「退出游戏」）。
    FORBIDDEN = ("VK.enter", "VK.esc", "VK.back", "0x0D", "0x0d", "0x1B", "0x1b", "0x08")
    banned = []
    for fn in ("ui.lua", "hd2_scanner.lua"):
        for m in re.finditer(r"key_edge\(\s*'([^']*)'\s*,\s*([^)]+?)\s*\)", harness.source_of(fn)):
            if m.group(2).strip() in FORBIDDEN:
                banned.append("%s: %s -> %s" % (fn, m.group(1), m.group(2).strip()))
    check("没有绑 ESC 菜单会吃的键", not banned, banned)

    bad = [c for c in CHECKS if not c[1]]
    print("\nLOAD SUITE: %s (%d/%d)" % ("OK" if not bad else "FAIL", len(CHECKS) - len(bad), len(CHECKS)))
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())