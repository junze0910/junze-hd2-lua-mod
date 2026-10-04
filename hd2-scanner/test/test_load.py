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
    check("模块清单 = 发布包（ui/registry 已退役）",
          mods == "aob,kernel,memscan,platform,scan,tab", mods)
    # ---- HD2Menu 页面体系已退役（2026-10-04）----
    # 渲染宿主 ui.lua 早就不在发布包里 -> 页面永远显示不出来。消费者一律走 ModOptionsMenu。
    check("HD2Menu 不再导出", ev("rawget(_G,'HD2Menu') == nil"))
    check("HD2MenuQueue 不再导出", ev("rawget(_G,'HD2MenuQueue') == nil"))
    check("页面状态字段已删（pages/page/cursor/revision）",
          ev("(function() local p = rawget(_G,'mods/junze/hd2_scanner') "
             "return p.pages == nil and p.page == nil and p.cursor == nil and p.revision == nil end)()") is True)
    check("ctx.rows 不再提供（面板退役）", ev("rawget(_G,'mods/junze/hd2_scanner').rows == nil"))
    # 消费者就算还按老办法注册，也只是挂到自己的 HD2MenuQueue 里，不影响 Scanner
    lua2 = harness.new_lua()
    lua2.execute("HD2MenuQueue = { { id='q', attach=function(api) api.register{ id='q', title='Q' } end } }")
    P2 = harness.boot(lua2)
    check("旧消费者挂队列也不炸（Scanner 不再消费它）",
          lua2.eval("rawget(_G,'HD2Menu') == nil") and lua2.eval("type(rawget(_G,'HD2MenuQueue'))") == "table")

    # 跑 200 帧（无 game.dll / 无 stingray，应优雅降级不报错）
    lua.execute("for i=1,200 do update(0.016) end")
    check("200 帧无错", ev(P + ".errs or 0") == 0)
    check("降级到热键", ev(P + ".trigger") == "hotkey")
    check("update/shutdown 已挂钩", ev("type(update)") == "function" and ev("type(shutdown)") == "function")
    lua.execute("shutdown()")
    check("shutdown 不抛", True)

    # ---- draw=on：ui 已退役，必须**优雅降级**（这是浮窗面板退役后要守的那条路）----
    open(cfg, "w").write("draw=on\nclaim=on\nprobe=on\nallow_5th=off\n")
    lua3 = harness.new_lua()
    P3 = harness.boot(lua3)
    lua3.execute("for i=1,200 do update(0.016) end")
    mods_after = lua3.eval("(function() local t={} for k in pairs(rawget(_G,'mods/junze/hd2_scanner').modules) do t[#t+1]=k end table.sort(t) return table.concat(t,',') end)()")
    check("draw=on 也不会加载 ui（已退役）", "ui" not in mods_after.split(","), mods_after)
    check("draw=on 后 200 帧无错", lua3.eval("rawget(_G,'mods/junze/hd2_scanner').errs or 0") == 0)
    check("cfg 被真正读到（draw=on 生效）",
          lua3.eval("rawget(_G,'mods/junze/hd2_scanner').cfg.draw") is True)
    # 面板那条分支只在「菜单开着」时才走：沙箱里没有 MenuSystem，走热键路 -> 把 visible 打开
    lua3.execute("rawget(_G,'mods/junze/hd2_scanner').visible = true")
    lua3.execute("for i=1,3 do update(0.016) end")
    check("draw=on 且面板该显示时：降级为 ui unavailable（不报错）",
          lua3.eval("rawget(_G,'mods/junze/hd2_scanner').status") == "ui unavailable",
          lua3.eval("rawget(_G,'mods/junze/hd2_scanner').status"))
    check("降级后仍然 0 错误", lua3.eval("rawget(_G,'mods/junze/hd2_scanner').errs or 0") == 0)
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

    # ---- Scanner 自己的 MOM 面板（4 行：扫描状态 / 解析战备表 / 全内存扫描 / 初始化）----
    # HD2Menu 退役后，这是 Scanner 唯一的界面入口；MOM 没有只读状态行，
    # 所以「状态」挂在 label（≤64 字符）与 description（≤400 字符）两个函数上，
    # 行本身做成动作（点一下 = 立刻扫一轮，然后自动弹回）。
    luaM = harness.new_lua()
    luaM.execute(r"""
_G.ModOptionsMenu = (function()
  local M = { api = 1, opts = {}, changes = {}, sets = {}, values = {} }
  function M.register_option(id, spec) M.opts[id] = spec return true end
  function M.on_change(id, fn) M.changes[id] = fn end
  function M.set(id, v) M.values[id] = v M.sets[#M.sets + 1] = id .. '=' .. tostring(v) end
  function M.get(id) return M.values[id] end
  return M
end)()
""")
    harness.boot(luaM)
    luaM.execute("for i=1,10 do update(0.016) end")
    ids = luaM.eval("(function() local t={} for k in pairs(ModOptionsMenu.opts) do t[#t+1]=k end table.sort(t) return table.concat(t,',') end)()")
    check("MOM: 注册了 4 行（状态/AOB/全内存扫描/初始化）",
          ids == "hd2_scanner.aob,hd2_scanner.full,hd2_scanner.reset,hd2_scanner.status", ids)
    check("MOM: mom_group = 'A HD2 MOD COLLECTION'",
          luaM.eval("rawget(_G,'HD2Scanner').mom_group") == "A HD2 MOD COLLECTION",
          luaM.eval("tostring(rawget(_G,'HD2Scanner').mom_group)"))
    check("MOM: 没有 probe/draw/claim 行（④~⑧ 待定，不进）",
          luaM.eval("ModOptionsMenu.opts['hd2_scanner.probe'] == nil "
                    "and ModOptionsMenu.opts['hd2_scanner.draw'] == nil "
                    "and ModOptionsMenu.opts['hd2_scanner.claim'] == nil") is True)
    r1 = luaM.eval("(function() local s = ModOptionsMenu.opts['hd2_scanner.status'].label() "
                   "return tostring(type(s)) .. '|' .. tostring(#s) .. '|' .. tostring(s:find('扫描状态', 1, true) ~= nil) end)()").split("|")
    check("MOM: 状态 label 是函数 / ≤64 字符 / 有摘要", r1[0] == "string" and int(r1[1]) <= 64 and r1[2] == "true", r1)
    r2 = luaM.eval("(function() local s = ModOptionsMenu.opts['hd2_scanner.status'].description() "
                   "return tostring(type(s)) .. '|' .. tostring(#s) .. '|' .. tostring(s:find(string.char(10), 1, true) ~= nil) end)()").split("|")
    check("MOM: 状态 description 是多行 / ≤400 字符", r2[0] == "string" and int(r2[1]) <= 400 and r2[2] == "true", r2)
    check("MOM: 所有 label/description 调用都不抛",
          luaM.eval("(function() for _, o in pairs(ModOptionsMenu.opts) do pcall(o.label) "
                    "if o.description then pcall(o.description) end end return true end)()") is True)

    # ① 状态行：点一下 = 立刻扫一轮，并自动弹回
    luaM.execute("ModOptionsMenu.changes['hd2_scanner.status'](true)")
    check("MOM: 状态行点击置内核 urgent",
          luaM.eval("rawget(_G,'HD2Scanner').status().urgent") is True)
    check("MOM: 状态行点完弹回 false",
          "hd2_scanner.status=false" in luaM.eval("table.concat(ModOptionsMenu.sets, ',')"))
    # ② AOB 行
    luaM.execute("ModOptionsMenu.changes['hd2_scanner.aob'](true)")
    check("MOM: AOB 行触发了 strat_table_request（无 game.dll -> failed）",
          luaM.eval("rawget(_G,'HD2Scanner').strat_table_status().state") == "failed",
          luaM.eval("rawget(_G,'HD2Scanner').strat_table_status().state"))
    check("MOM: AOB 行弹回 false",
          "hd2_scanner.aob=false" in luaM.eval("table.concat(ModOptionsMenu.sets, ',')"))
    # ③ 全内存扫描（兜底）行：置 urgent + 触发 AOB，并弹回
    luaM.execute("rawget(_G,'HD2Scanner').urgent = false")
    luaM.execute("ModOptionsMenu.changes['hd2_scanner.full'](true)")
    check("MOM: 全内存扫描行置内核 urgent",
          luaM.eval("rawget(_G,'HD2Scanner').status().urgent") is True)
    check("MOM: 全内存扫描行弹回 false",
          "hd2_scanner.full=false" in luaM.eval("table.concat(ModOptionsMenu.sets, ',')"))
    # ④ 初始化行：跑掉注册的重置回调，并弹回
    luaM.execute("rawget(_G,'HD2Scanner').register_reset('probe_mod', "
                 "function() _G.__RESET_RAN = true end)")
    check("MOM: register_reset 非函数/空名 -> false",
          luaM.eval("(function() local ok = rawget(_G,'HD2Scanner').register_reset('', function() end) "
                    "return ok end)()") is False)
    check("MOM: reset_names 列出已注册的 mod",
          luaM.eval("table.concat(rawget(_G,'HD2Scanner').reset_names(), ',')") == "probe_mod")
    # ---- 跨 mod 集成：假成员 mod 用 Scanner 的 API 并入同一组 ----
    luaM.execute(r"""
local S = rawget(_G, 'HD2Scanner')
local MOM = rawget(_G, 'ModOptionsMenu')
assert(type(S.mom_group) == 'string' and S.mom_group ~= '', 'mom_group 未导出')
MOM.register_option('fake.a', { type = 'toggle', label = '假成员 A', mod = S.mom_group, default = false })
MOM.register_option('fake.b', { type = 'toggle', label = '假成员 B', mod = S.mom_group, default = false })
S.register_reset('假成员', function() _G.__FAKE_RESET = (_G.__FAKE_RESET or 0) + 1 end)
S.register_reset('第二成员', function() _G.__FAKE_RESET2 = true end)
S.register_full_scan('假成员', function() _G.__FAKE_SCAN = (_G.__FAKE_SCAN or 0) + 1 end)
""")
    check("跨 mod: 所有行共用同一个分组名",
          luaM.eval("(function() local t={} for k,o in pairs(ModOptionsMenu.opts) do t[#t+1]=o.mod end "
                    "for i=2,#t do if t[i]~=t[1] then return false end end return t[1] end)()")
          == "A HD2 MOD COLLECTION")
    check("跨 mod: 一行都不缺（4 + 假成员 2）",
          luaM.eval("(function() local n=0 for _ in pairs(ModOptionsMenu.opts) do n=n+1 end return n end)()") == 6)
    check("跨 mod: reset_names 列出两个成员",
          luaM.eval("table.concat(rawget(_G,'HD2Scanner').reset_names(), ',')") == "probe_mod,假成员,第二成员",
          luaM.eval("table.concat(rawget(_G,'HD2Scanner').reset_names(), ',')"))
    check("跨 mod: full_scan_names 列出成员",
          luaM.eval("table.concat(rawget(_G,'HD2Scanner').full_scan_names(), ',')") == "假成员")
    luaM.execute("rawget(_G,'HD2Scanner').run_full_scans()")
    check("跨 mod: 全内存扫描跑到了成员回调",
          luaM.eval("_G.__FAKE_SCAN") == 1)
    luaM.execute("ModOptionsMenu.changes['hd2_scanner.reset'](true)")
    check("跨 mod: 全局初始化跑到全部成员回调",
          luaM.eval("_G.__FAKE_RESET") == 1 and luaM.eval("_G.__FAKE_RESET2") is True)
    check("MOM: 初始化行跑了注册的回调", luaM.eval("_G.__RESET_RAN") is True)
    check("MOM: 初始化行弹回 false",
          "hd2_scanner.reset=false" in luaM.eval("table.concat(ModOptionsMenu.sets, ',')"))

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
    check("内核页已随 HD2Menu 退役（不再注册页面）",
          lua5.eval("rawget(_G,'mods/junze/hd2_scanner').pages == nil") is True)

    # ---- AOB 战备表定位：合成映像（不需要游戏）----
    # 把「lea r15 → AOB pair → 指针数组 → 记录」整条链摆在一块自留内存里，
    # 验证 aob.lua 的解链、唯一性判据、槽位探针和记录读取。
    lua6 = harness.new_lua()
    harness.boot(lua6)
    lua6.execute(r"""
local ffi = require('ffi')
local IMG = 0x4000
local buf = ffi.new('uint8_t[?]', IMG)          -- 必须留着引用，别让 GC 收走
local base = tonumber(ffi.cast('uintptr_t', buf))
local function poke(off, s)
  for i = 1, #s do buf[off + i - 1] = s:byte(i) end
end
local function put32(off, v)
  if v < 0 then v = v + 4294967296 end
  poke(off, string.char(v % 256, math.floor(v / 256) % 256,
                        math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256))
end
local function put64(off, v)
  put32(off, v % 4294967296)
  put32(off + 4, math.floor(v / 4294967296))
end
local R15   = base + 0x1000
local TABLE = base + 0x2000
local REC   = base + 0x2800
-- ① lea r15,[rip+disp32]
poke(0x100, string.char(0x4C, 0x8D, 0x3D))
put32(0x103, R15 - (base + 0x100 + 7))
-- ② AOB pair：consumer = base+0x800
poke(0x800, string.char(0x49, 0x8B, 0x84, 0xC7))
put32(0x804, TABLE - R15)                        -- disp32 = table_base - r15
poke(0x808, string.char(0x44, 0x8B, 0x80, 0xC8, 0x00, 0x00, 0x00,
                        0x8B, 0xC2, 0x45, 0x85, 0xC0))
-- ③ 指针数组：只有 id=3 有记录
put64(0x2000 + 3 * 8, REC)
-- ④ 记录：package@0xA8 / icon@0xB0 / additional@0xC8
_T = { base = base, table_base = TABLE, rec = REC,
       pkg =  string.char(0x66, 0xAF, 0x88, 0x47, 0x29, 0x9A, 0x74, 0x22),
       icon = string.char(0x17, 0x0E, 0xE8, 0xA6, 0x60, 0xCA, 0x6E, 0x39) }
poke(0x2800 + 0x00, string.char(3, 0, 0, 0))
put32(0x2800 + 0x50, 2)                          -- use
poke(0x2800 + 0xA8, _T.pkg)
poke(0x2800 + 0xB0, _T.icon)
HD2_AOB_TEST = { sections = { { base = base, size = IMG } } }
""")
    check("AOB: 初始 idle", lua6.eval("HD2Scanner.strat_table_status().state") == "idle")
    check("AOB: request 接受", lua6.eval("HD2Scanner.strat_table_request()") is True)
    lua6.execute("for i=1,5 do update(0.016) end")
    res = lua6.eval(r"""(function()
      local S, out = HD2Scanner, {}
      local st, rec = S.strat_table_status(), S.strat_rec(3, 0xD0)
      out[#out+1] = tostring(st.state)
      out[#out+1] = st.reason and tostring(st.reason) or '-'
      out[#out+1] = tostring(st.base == _T.table_base)
      out[#out+1] = tostring(S.strat_table_base() == _T.table_base)
      out[#out+1] = tostring(S.strat_slot(3) == _T.rec)
      out[#out+1] = tostring(rec ~= nil and #rec == 0xD0)
      out[#out+1] = tostring(rec ~= nil and rec:sub(0xA9, 0xB0) == _T.pkg)
      out[#out+1] = tostring(rec ~= nil and rec:sub(0xB1, 0xB8) == _T.icon)
      out[#out+1] = tostring(rec ~= nil and rec:sub(0xC5, 0xC8) == '\0\0\0\0')
      out[#out+1] = tostring(rec ~= nil and rec:sub(0xCD, 0xD0) == '\0\0\0\0')
      out[#out+1] = tostring(S.strat_slot(200) == nil)
      out[#out+1] = tostring(st.slots_ok)
      return table.concat(out, '|')
    end)()""").split("|")
    check("AOB: 解出 ok", res[0] == "ok", res)
    check("AOB: table_base 正确", res[2] == "true", res)
    check("AOB: strat_table_base() 一致", res[3] == "true", res)
    check("AOB: slot_ptr(3) 正确", res[4] == "true", res)
    check("AOB: 记录读得到 0xD0 字节", res[5] == "true", res)
    check("AOB: package 在 +0xA8", res[6] == "true", res)
    check("AOB: icon 在 +0xB0", res[7] == "true", res)
    check("AOB: depends_on(+0xC4)=0", res[8] == "true", res)
    check("AOB: max_in_loadout(+0xCC)=0", res[9] == "true", res)
    check("AOB: 空槽位返回 nil", res[10] == "true", res)
    check("AOB: 槽位探针 >=1", int(res[11]) >= 1, res)

    # ---- AOB 安全网：命中不唯一必须放弃（不许猜）----
    lua7 = harness.new_lua()
    harness.boot(lua7)
    lua7.execute(r"""
local ffi = require('ffi')
local buf = ffi.new('uint8_t[?]', 0x4000)
local base = tonumber(ffi.cast('uintptr_t', buf))
local function poke(off, s) for i = 1, #s do buf[off + i - 1] = s:byte(i) end end
local pair = string.char(0x49, 0x8B, 0x84, 0xC7) .. '\0\0\0\0' ..
             string.char(0x44, 0x8B, 0x80, 0xC8, 0x00, 0x00, 0x00, 0x8B, 0xC2, 0x45, 0x85, 0xC0)
poke(0x100, pair)          -- 同一段里两处命中
poke(0x900, pair)
HD2_AOB_TEST = { sections = { { base = base, size = 0x4000 } } }
""")
    lua7.execute("HD2Scanner.strat_table_request()")
    lua7.execute("for i=1,5 do update(0.016) end")
    st7 = lua7.eval("HD2Scanner.strat_table_status().state")
    why7 = lua7.eval("tostring(HD2Scanner.strat_table_status().reason)")
    check("AOB: 命中不唯一 -> failed", st7 == "failed", (st7, why7))
    check("AOB: 不唯一的原因写明", "唯一" in why7, why7)
    check("AOB: 失败后 strat_rec 返回 nil", lua7.eval("HD2Scanner.strat_rec(3) == nil") is True)

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