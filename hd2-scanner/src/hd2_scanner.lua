-- HD2-Addon: mods/junze/hd2_scanner
-- ===========================================================================
--  HD2 Scanner —— 数据表定位/广播 + 通用全量扫描 + AOB 战备表（前置服务 mod）
--
--  对外只暴露 `_G.HD2Scanner`；消费者自己负责校验与写入。
--
--  ⚠ 界面：自绘面板 / `_G.HD2Menu` 页面体系 **2026-10-04 已退役**
--     （渲染宿主 ui.lua 早已不在发布包里，页面永远显示不出来）。
--     消费者一律注册 `_G.ModOptionsMenu`（原生 MODS 页），不要再注册 HD2Menu。
--     本 mod 自己的状态/动作注册在下面 §4.6。
--
--  红线：本文件不写游戏数据表；全包唯一会写游戏内存的是 tab.lua 的页签认领。
--
--  ⚠ 本文件只是**入口 + 编排**；真正的逻辑在同一个 archive 的另外 6 个资源里：
--       mods/junze/hd2_scanner/platform   平台层（ffi/kernel32/内存/日志）
--       mods/junze/hd2_scanner/scan       签名扫描 + MENU/TAB/FONTS 解码器
--       mods/junze/hd2_scanner/tab        菜单探测 + 页签落位
--       mods/junze/hd2_scanner/kernel     数据表定位 + 广播（只读）
--       mods/junze/hd2_scanner/memscan    通用全量内存扫描服务
--       mods/junze/hd2_scanner/aob        game.dll AOB 定位（战备记录指针数组）
--     这些资源**不带** `-- HD2-Addon:` 声明，所以 loader 不会把它们当独立 addon。
-- ===========================================================================

local MOD = 'mods/junze/hd2_scanner'
if rawget(_G, MOD) then return end

local P = {
    version  = '0.8.0',
    api      = 1,
    status   = 'starting',
    mode     = 'float',      -- 'float' | 'tab'
    trigger  = nil,          -- 'menu'（跟随 ESC）| 'hotkey'
    visible  = false,        -- 自绘面板（退役中，见 §4.6 的 MOM 面板）
    hotkey   = 0x78,         -- VK_F9
}
rawset(_G, MOD, P)

-- ---------------------------------------------------------------------------
-- 1. 前置：BSL 或 MDL 任一在场
-- ---------------------------------------------------------------------------
local loader = rawget(_G, 'CowboyBingusModLoader')
local mdl    = rawget(_G, 'MDL')
if not loader and not mdl then
    P.status = 'dormant: no loader'
    return P
end

-- ---------------------------------------------------------------------------
-- 2. 装载同 archive 的模块资源
-- ---------------------------------------------------------------------------
local RES = {
    platform = 'mods/junze/hd2_scanner/platform',
    scan     = 'mods/junze/hd2_scanner/scan',
    tab      = 'mods/junze/hd2_scanner/tab',
    kernel   = 'mods/junze/hd2_scanner/kernel',
    memscan  = 'mods/junze/hd2_scanner/memscan',
    aob      = 'mods/junze/hd2_scanner/aob',
}
local RES_N = 0
for _ in pairs(RES) do RES_N = RES_N + 1 end


local ctx = { P = P, loader = loader, mdl = mdl, RES = RES }

local function load_module(key)
    local name = RES[key]
    if not name then return nil, key .. ': 已退役（不在 RES 里）' end   -- 例：ui（2026-10-04）
    local ok, mod = pcall(require, name)
    if ok and type(mod) == 'table' and type(mod.new) == 'function' then return mod end
    return nil, name .. ': ' .. tostring(mod)
end

local U
do
    local m, e = load_module('platform')
    if not m then P.status = 'failed: ' .. e return P end
    local ok, val = pcall(m.new, ctx)
    if not ok then P.status = 'failed: platform.new: ' .. tostring(val) return P end
    U = val
end
ctx.platform = U
ctx.log = U.log                       -- 其余模块都从 ctx.log 取日志
local log, log_flush = U.log, U.log_flush
log(string.format('hd2_scanner %s starting; host=%s base=%s',
    P.version, loader and 'BSL' or 'MDL', tostring(U.BASE)))

local S
do
    local m, e = load_module('scan')
    if not m then P.status = 'failed: ' .. e log(P.status) return P end
    local ok, val = pcall(m.new, ctx)
    if not ok then P.status = 'failed: scan.new: ' .. tostring(val) log(P.status) return P end
    S = val
end
ctx.scan = S

local MS
do
    local m, e = load_module('memscan')
    if m then
        local ok, val = pcall(m.new, ctx)
        if ok and val then MS = val ctx.memscan = MS end
    else
        log('memscan unavailable: ' .. tostring(e))
    end
end

local AOB
do
    local m, e = load_module('aob')
    if m then
        local ok, val = pcall(m.new, ctx)
        if ok and val then AOB = val ctx.aob = AOB else log('aob.new 失败: ' .. tostring(val)) end
    else
        log('aob unavailable: ' .. tostring(e))
    end
end
local MENU, TAB, FONTS = S.MENU, S.TAB, S.FONTS
local text_section = S.text_section
local GAME, game_open, mem_read, hex8 = U.GAME, U.game_open, U.mem_read, U.hex8

-- 面板/开关的配置落盘（读在下面 §3.5，写在这里）
-- ⚠⚠ local 必须声明在【所有用它的函数之前】（Lua 的词法作用域是位置性的）：
--   2026-10-02 实机踩到过 —— 忘了前置声明，下面所有 CFG 引用会静默变成全局 nil。
local CFG, CFG_FILE

local function cfg_save()
    pcall(function()
        local f = io.open(CFG_FILE, 'w')
        if not f then return end
        f:write('# HD2 Scanner - 改完 1 秒内热生效，不用重编译\n')
        f:write('# 由面板/MOM 选项写回；手工编辑同样有效\n')
        f:write('draw='        .. (CFG.draw        and 'on' or 'off') .. '\n')
        f:write('claim='       .. (CFG.claim       and 'on' or 'off') .. '\n')
        f:write('probe='       .. (CFG.probe       and 'on' or 'off') .. '\n')
        f:write('allow_5th='   .. (CFG.allow_5th   and 'on' or 'off') .. '\n')
        f:write(string.format('hotkey=0x%X\n', CFG.hotkey))
        f:close()
    end)
end

-- ---------------------------------------------------------------------------
-- 3.5 热配置（每次 ~1 秒重读，不用重编译就能二分定位崩溃）
--     %LOCALAPPDATA%\CowboyBingus\Helldivers2\HD2Scanner.cfg
-- ---------------------------------------------------------------------------
CFG_FILE = U.BASE .. '/HD2Scanner.cfg'
CFG = { draw = false, claim = false, probe = true, allow_5th = false, hotkey = 0x78 }
--           默认关浮窗（用户要求移除浮动面板）
local CFG_AT = -10

local function cfg_write_default()
    pcall(function()
        local f = io.open(CFG_FILE, 'w')
        if not f then return end
        f:write('# HD2 Scanner - 改完 1 秒内热生效，不用重编译\n')
        f:write('# 面板是浮动窗，开 ESC 时出现；标题栏可以拖着走，位置记在 HD2Scanner.pos\n')
        f:write('draw=off       # 浮动面板已移除；保留键只为兼容旧 cfg\n')
        f:write('claim=off      # 要不要抢 ESC 页签（默认关，只整浮窗）\n')
        f:write('probe=on       # 每帧还要不要读 MenuSystem\n')
        f:write('allow_5th=off  # 允许占第 5 页签（实测会崩，别开）\n')
        f:write('hotkey=0x78    # 0x78 = F9，仅在探不到 MenuSystem 时用\n')
        f:close()
    end)
end

local function cfg_load()
    local f = io.open(CFG_FILE, 'r')
    if not f then cfg_write_default() return end
    local text = f:read('*a') f:close()
    for line in text:gmatch('[^\r\n]+') do
        line = line:gsub('#.*$', '')          -- ★ 先砍掉行尾注释！
        -- 默认生成的 cfg 每行都带注释；不先砍注释的话，[^#]* 后面接 %s*$ 永远匹配不上，
        -- 整行会被静默丢弃（2026-10-02 的 bug：draw=true 一直读成 false）
        local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
        if k and v and v ~= '' then
            if k == 'hotkey' then
                CFG.hotkey = tonumber(v) or CFG.hotkey
            else
                CFG[k] = (v == 'on' or v == 'yes' or v == 'true')
            end
        end
    end
end

cfg_load()
P.cfg = CFG
local _cfg_tick = 0
local function cfg_tick()
    _cfg_tick = _cfg_tick + 1
    if _cfg_tick >= 60 then _cfg_tick = 0 cfg_load() end
end

ctx.flush     = U.log_flush
ctx.cfg       = CFG
-- ⚠ 必须在这里同步：tab.lua 的 M.new(ctx) 紧接着就会把它读走（2026-10-04 修：
--   以前这里写死 false + 注释「由 cfg 覆盖」，但全文件再没人覆盖过 -> allow_5th 永远无效）
ctx.allow_5th = CFG.allow_5th == true

-- ui 是**可选**模块：draw=off 时连 require 都不做 —— 连 ffi.load('user32') 都不会碰。
local UI = nil
local UI_tried = false

local function ensure_ui()
    if UI then return UI end
    if UI_tried then return nil end
    UI_tried = true
    local m, e = load_module('ui')
    if not m then log('ui unavailable: ' .. tostring(e)) return nil end
    local ok, val = pcall(m.new, ctx)
    if not ok then log('ui.new failed: ' .. tostring(val)) return nil end
    UI = val
    ctx.ui = UI
    if P.modules then P.modules.ui = UI end    -- P.modules 是加载时建的，这里要补上
    log('ui module loaded (draw=on)')
    return UI
end
local TB
do
    local m, e = load_module('tab')
    if not m then P.status = 'failed: ' .. e log(P.status) return P end
    local ok, val = pcall(m.new, ctx)
    if not ok then P.status = 'failed: tab.new: ' .. tostring(val) log(P.status) return P end
    TB = val
end
ctx.tab = TB

-- ---------------------------------------------------------------------------
-- 4.2 扫描内核（阶段 1：只读、偏移直读 + 广播；设计见 SCANNER-设计定稿 §4/§5）
-- ---------------------------------------------------------------------------
local K
do
    local m, e = load_module('kernel')
    if not m then
        log('kernel 未装载: ' .. tostring(e))
    else
        local ok, val = pcall(m.new, ctx)
        if not ok then
            log('kernel.new 失败: ' .. tostring(val))
        else
            K = val
            if MS then
                K.scan_request = function(req) return MS.request(req) end
                K.scan_cancel  = function(id)  return MS.cancel(id) end
                K.scan_status  = function(id)  return MS.status(id) end
            end
            if AOB then
                -- ★ AOB 战备表定位：game.dll 里解出记录指针数组，按 ID 直取（见 aob.lua）
                K.strat_table_request = function() return AOB.request() end
                K.strat_table_status  = function() return AOB.status() end
                K.strat_table_base    = function() return AOB.base() end
                K.strat_slot          = function(id) return AOB.slot(id) end
                K.strat_rec           = function(id, n) return AOB.rec(id, n) end
            end
            rawset(_G, 'HD2Scanner', K)      -- ★ 对外接口：其它 mod 从这里拿地址
            log('_G.HD2Scanner 已导出')
        end
    end
end


-- ---------------------------------------------------------------------------
-- 4.6 ModOptionsMenu（原生 MODS 页）—— 只注册 3 行：状态 / AOB / 诊断
--
--   ⚠ MOM 只支持 toggle / choice / slider，**没有只读状态行**；但它的 label 与
--     description 可以是**函数**，每次打开 ESC 菜单时重算（mod_options_menu API v2，
--     见其 translation.refresh）。状态就挂在这两个函数上 —— 所以「状态行」同时
--     也是个动作（点一下 = 立刻扫一轮），不然 MOM 里没有纯展示位。
--   ⚠ 注册后不能注销、不能改 kind；id 必须稳定，函数必须自己兜异常
--     （MOM 侧会 pcall，但返回 nil/超长只会退回旧文本，注册期还会直接失败）。
--   ⚠ 这里注册的就是 HD2Menu 那套页面的替代品（2026-10-04 退役，见文件头）。
-- ---------------------------------------------------------------------------
local MOM = { registered = false, prefix = 'hd2_scanner.' }
local MOM_NAME = 'HD2 Scanner（前置）'

local function mom_tables()
    local n = 0
    if K and K.published then
        for _ in pairs(K.published()) do n = n + 1 end
    end
    return n
end

local function mom_aob_line()
    if not AOB then return '战备表  AOB 模块未装载' end
    local st = AOB.status()
    if st.state == 'ok' then
        return string.format('战备表  AOB ok · base 0x%X · 槽位 %d/%d · %.0f ms',
            st.base or 0, st.slots_ok or 0, st.slots or 0, st.ms or 0)
    elseif st.state == 'scanning' then
        return string.format('战备表  AOB 解析中 %.1f / %.1f MB',
            (st.scanned or 0) / 1048576, (st.total or 0) / 1048576)
    end
    return '战备表  AOB ' .. tostring(st.state)
        .. (st.reason and (' · ' .. tostring(st.reason)) or '')
end

-- MOM 的 description（≤400 字符）：整块状态，开菜单时重算
local function mom_status_text()
    local ok, txt = pcall(function()
        local out = {}
        local ks = K and K.status and K.status() or nil
        if ks then
            out[#out+1] = string.format('内核  %s · 第 %d 轮 · 表 %d 张 · 上轮 %.0f ms / 墙上 %.1f s',
                tostring(ks.state), ks.rounds or 0, mom_tables(), ks.ms or 0, (ks.wall or 0) / 1000)
            out[#out+1] = string.format('探针  区段 %d · 读 %d 次 · 分 %d 帧 · 掉过 %d 份 · 周期 %d s',
                ks.regions or 0, ks.reads or 0, ks.shard_frames or 0, ks.lost or 0, ks.interval or 0)
        else
            out[#out+1] = '内核  未装载（缺 ffi/kernel32？）'
        end
        out[#out+1] = mom_aob_line()
        local chk = P.selfcheck
        out[#out+1] = chk and string.format('自检  %d/%d %s', chk.ok, chk.total,
                (chk.ok == chk.total) and '与 MDL 基准逐位一致' or '有差异，见日志')
            or '自检  尚未运行（进过一局才会跑）'
        local sc = P.scan
        out[#out+1] = string.format('环境  %s / API %d · Scanner v%s · %s',
            loader and 'BSL' or (mdl and 'MDL' or '无宿主'), P.api, P.version,
            sc and string.format('game.dll .text %.1f MB', sc.text_size / 1048576) or 'game.dll 未解析')
        out[#out+1] = string.format('界面  菜单探针 %s · 页签 %s · 自绘浮窗 %s',
            CFG.probe ~= false and '开' or '关',
            CFG.claim and '已开（需重开游戏）' or '关',
            CFG.draw and '开' or '关')
        return table.concat(out, '\n')
    end)
    if not ok or type(txt) ~= 'string' or txt == '' then return '状态读不出来，见 HD2Scanner.log' end
    if #txt > 390 then txt = txt:sub(1, 390) end      -- MOM 上限 400，留余量
    return txt
end

-- MOM 的 label（≤64 字符）：一行摘要
local function mom_status_label()
    local ok, txt = pcall(function()
        local ks = K and K.status and K.status() or nil
        return string.format('扫描状态：%s · 表 %d 张 · %s',
            ks and tostring(ks.state) or '未装载', mom_tables(),
            (AOB and AOB.base and AOB.base()) and 'AOB ok' or 'AOB --')
    end)
    if not ok or type(txt) ~= 'string' or txt == '' then return '扫描状态（读取失败）' end
    if #txt > 60 then txt = txt:sub(1, 60) end
    return txt
end

local function mom_aob_text()
    local ok, txt = pcall(function()
        return mom_aob_line() .. '\n\n点一下 = 立刻重新解析（game.dll 代码段，分帧后台跑，约十几帧）。\n'
            .. '失败了会显示原因（AOB 不唯一 / 锚点找不到 / 表不可读），同时写进 HD2Scanner.log。'
    end)
    if not ok or type(txt) ~= 'string' or txt == '' then return 'AOB 状态读不出来' end
    if #txt > 390 then txt = txt:sub(1, 390) end
    return txt
end

local function register_mod_options()
    if MOM.registered then return end
    local mom = rawget(_G, 'ModOptionsMenu')
    if type(mom) ~= 'table' or mom.api ~= 1 or type(mom.register_option) ~= 'function' then return end
    MOM.registered, MOM.api = true, mom

    local function add(id, spec)
        local ok, why = mom.register_option(id, spec)
        if not ok then log('MOM: 注册 ' .. id .. ' 失败: ' .. tostring(why)) end
        return ok
    end
    local function on_change(id, fn)
        if type(mom.on_change) ~= 'function' then return end
        local ok, why = pcall(mom.on_change, id, fn)
        if not ok then log('MOM: on_change ' .. id .. ' 失败: ' .. tostring(why)) end
    end
    -- 动作型 toggle：点完立刻弹回 false（MOM 的 set 不触发 on_change，安全）
    local function unpress(id)
        if type(mom.set) == 'function' then pcall(mom.set, id, false) end
    end

    -- ① 状态（点一下 = 立刻扫一轮）
    local status_id = MOM.prefix .. 'status'
    add(status_id, { type = 'toggle', mod = MOM_NAME, default = false,
        label = mom_status_label, description = mom_status_text })
    on_change(status_id, function(v)
        if not v then return end
        local ok = pcall(function() if K and K.declare_need then K.declare_need() end end)
        unpress(status_id)
        log('MOM: 立刻扫一轮' .. (ok and '' or '（失败）'))
    end)

    -- ② 解析战备表（AOB）
    local aob_id = MOM.prefix .. 'aob'
    add(aob_id, { type = 'toggle', mod = MOM_NAME, default = false,
        label = '解析战备表（AOB）', description = mom_aob_text })
    on_change(aob_id, function(v)
        if not v then return end
        if AOB then
            local ok2, r1, r2 = pcall(AOB.request)
            log(string.format('MOM: 解析战备表 -> %s %s %s', tostring(r1), tostring(r2),
                ok2 and '' or '（异常）'))
        else
            log('MOM: 解析战备表 -> AOB 模块未装载')
        end
        unpress(aob_id)
    end)

    -- ③ 写诊断到日志
    local diag_id = MOM.prefix .. 'diag'
    add(diag_id, { type = 'toggle', mod = MOM_NAME, default = false,
        label = '写诊断到日志',
        description = '把上面那段状态整块写进 HD2Scanner.log（排查用，点完自动弹回）。' })
    on_change(diag_id, function(v)
        if not v then return end
        local ok2, txt = pcall(mom_status_text)
        log('MOM 诊断：' .. tostring(txt):gsub('\n', ' | '))
        log_flush(true)
        unpress(diag_id)
    end)

    log('MOM: 已注册 3 行（扫描状态 / 解析战备表 / 写诊断）')
end

-- ---------------------------------------------------------------------------
-- 4. 进程内自检：和 MDL 的成功基准逐项比对
-- ---------------------------------------------------------------------------
-- 期望值取自 %LOCALAPPDATA%\MDL\Helldivers2\Logs\MDL.log，
-- MDL 1.4.2 在**本机同一个游戏构建**上跑成功时解出的数字。
local REFERENCE = {
    { 'menu.global',     0x347CE38 },
    { 'menu.open',       2185      },
    { 'tab.bar',         1248      },
    { 'tab.count',       57448     },
    { 'tab.labels',      57320     },
    { 'tab.text',        8296      },
    { 'tab.set_labels',  0x17AAC50 },
    { 'tab.set_arg',     0x143C950 },
    { 'font.font',       0x3772268 },
    { 'font.atlas',      0x3772EE8 },
    { 'font.material',   0x37C5478 },
}

local function selfcheck(actual)
    local okn, tot = 0, 0
    for _, row in ipairs(REFERENCE) do
        tot = tot + 1
        local got, want = actual[row[1]], row[2]
        local hit = (got == want)
        if hit then okn = okn + 1 end
        log(string.format('selfcheck: %-16s %-12s 期望 %-12s  %s',
            row[1], got and ('0x' .. hex8(got)) or 'nil', '0x' .. hex8(want),
            hit and 'OK' or 'MISMATCH'))
    end
    log(string.format('selfcheck: %d/%d %s', okn, tot,
        okn == tot and 'OK —— 解码器与 MDL 逐位一致' or '有差异，见上'))
    return okn, tot
end

-- ---------------------------------------------------------------------------
-- 5. 首次解析 + 自检
-- ---------------------------------------------------------------------------
local resolve_done = false

local function resolve_once()
    if resolve_done then return end
    resolve_done = true
    local t0 = os.clock()
    if not game_open() then
        log('native unavailable: ' .. tostring(GAME.why) .. ' -> 浮动面板 + 热键')
        P.trigger = P.trigger or 'hotkey'
        return
    end
    local text_start, text_size, why = text_section(GAME.get)
    if not text_start then
        log('native unavailable: ' .. tostring(why) .. ' -> 浮动面板 + 热键')
        P.trigger = P.trigger or 'hotkey'
        return
    end
    GAME.text = { start = text_start, size = text_size }
    log(string.format('.text: RVA 0x%X size 0x%X (%.1f MB)',
        text_start, text_size, text_size / 1048576))

    local r = {}
    local mok, mval = pcall(MENU.resolve, GAME.get, text_start, text_size)
    if mok then
        GAME.menu  = mval
        GAME.names = MENU.read_names(function(a, n) return mem_read(a, n) end, GAME.base, mval)
        r['menu.global'], r['menu.open'] = mval.global, mval.open
        local total, few = 0, {}
        for i = 0, 8 do if GAME.names[i] then few[#few+1] = GAME.names[i] end end
        for _ in pairs(GAME.names) do total = total + 1 end
        log(string.format('menu: global 0x%X open %d names %d 个', mval.global, mval.open, total))
        log('menu names[0..8]: ' .. table.concat(few, ' '))
        if total < 3 then
            log('!! names 解不出来 —— 探测会永远判为「菜单没开」（安全失败：宁可不显示）')
        end
    else
        log('menu resolve failed: ' .. tostring(mval))
    end

    local tok, tval = pcall(TAB.resolve, GAME.get, text_start, text_size)
    if tok then
        GAME.tab = tval
        r['tab.bar'], r['tab.count'], r['tab.labels'], r['tab.text'] =
            tval.bar, tval.count, tval.labels, tval.text
        r['tab.set_labels'], r['tab.set_arg'] = tval.set_labels, tval.set_arg
        log(string.format('tab: bar +%d count +%d labels +%d text +%d set_labels +0x%X set_arg %s',
            tval.bar, tval.count, tval.labels, tval.text, tval.set_labels,
            tval.set_arg and ('+0x' .. hex8(tval.set_arg)) or ('NIL (' .. tostring(tval.arg_problem) .. ')')))
        log(string.format('tab labels: 0x%X 0x%X 0x%X stride %d',
            tval.expected[0], tval.expected[1], tval.expected[2], TAB.STRIDE))
    else
        log('tab resolve failed: ' .. tostring(tval))
    end

    local fok, fval = pcall(FONTS.resolve, GAME.get, text_start, text_size)
    if fok then
        GAME.slots = fval
        -- ★ REFERENCE 要的是**槽位 RVA**（MDL 日志里 +0x3772268 那种），不是读出来的哈希！
        --   之前喂错值 → 自检永远 3 条 MISMATCH（2026-10-02 修正）
        r['font.font'], r['font.atlas'], r['font.material'] = fval.font, fval.atlas, fval.material
        log(string.format('font slots: font +0x%X atlas +0x%X material +0x%X',
            fval.font, fval.atlas, fval.material))
        local hashes, fwhy = FONTS.read(function(a, n) return mem_read(a, n) end, GAME.base, fval)
        if hashes then
            log('font hashes: ' .. hashes.font .. ' / ' .. hashes.atlas .. ' / ' .. hashes.material)
        else
            log('font hashes 暂不可读（开机太早，ui 会在用时重试）: ' .. tostring(fwhy))
        end
    else
        log('font resolve failed: ' .. tostring(fval))
    end

    local okn, tot = selfcheck(r)
    P.selfcheck = { ok = okn, total = tot }
    P.scan = {
        text_rva  = text_start, text_size = text_size,
        ms        = (os.clock() - t0) * 1000,
        menu = mok, tab = tok, font = fok,
        arg  = tok and tval.set_arg ~= nil or false,
    }
    log_flush(true)          -- 自检结果立刻落盘，别等 300 帧
    P.trigger = GAME.menu and 'menu' or 'hotkey'
    P.mode    = GAME.tab and 'tab' or 'float'
    log(string.format('resolve done in %.0f ms; trigger=%s mode=%s',
        (os.clock() - t0) * 1000, P.trigger, P.mode))
end

-- ---------------------------------------------------------------------------
-- 6. 帧循环
-- ---------------------------------------------------------------------------
local frames, seen = 0, 0
local last_menu_name, last_open, drew_once = nil, nil, false

local function frame()
    frames = frames + 1
    if not resolve_done then resolve_once() end
    cfg_tick()

    -- ★ 扫描内核：每帧 tick。到点或 urgent 时**当帧同步**跑探针（落实定稿 §7.2）
    --   注意位置：写在"菜单开没开"判断**之前** —— 菜单关着也要保持探针节奏
    if K then pcall(K.frame) end
    if MS then pcall(MS.frame) end
    if AOB then pcall(AOB.frame) end
    pcall(register_mod_options)     -- MOM 面板：注册一次（幂等）

    local open = false
    if CFG.probe == false then
        open = false
    elseif P.trigger == 'menu' then
        local st = TB.probe()
        open = (st ~= nil and st.open == true)
        local nm = st and (st.name or ('screen#' .. tostring(st.index)))
        if nm ~= last_menu_name then
            last_menu_name = nm
            log('menu screen: ' .. tostring(nm))
        end
    else
        if CFG.draw ~= false then
            local UIm = ensure_ui()
            if UIm and UIm.key_edge('hot', P.hotkey) then P.visible = not P.visible end
        end
        open = P.visible
    end
    if open ~= last_open then
        last_open = open
        log('menu ' .. (open and 'OPEN' or 'CLOSED') .. '  (draw=' .. tostring(CFG.draw)
            .. ' claim=' .. tostring(CFG.claim) .. ' allow_5th=' .. tostring(CFG.allow_5th) .. ')')
    end

    if not open then
        seen = 0
        if UI and UI.shown() then UI.destroy() end
        P.status = 'idle'
        if frames % 300 == 0 then log_flush() end
        return
    end
    seen = seen + 1
    P.status = 'visible'

    -- 懒③：菜单打开的第 1 帧只看不动（给 MDL 先手）；第 2 帧才认领页签
    if seen == 2 and P.mode == 'tab' and CFG.claim ~= false then pcall(TB.claim) end

    -- 浮动面板完全可选：draw=off 时到此为止，ui 模块根本没加载
    if CFG.draw == false then
        P.status = 'observing (draw=off)'
        if frames % 300 == 0 then log_flush() end
        return
    end
    local UIm = ensure_ui()
    if not UIm then
        P.status = 'ui unavailable'
        if frames % 300 == 0 then log_flush() end
        return
    end

    local ok, why = UIm.draw()
    if ok then
        P.draw_count = (P.draw_count or 0) + 1
        if not drew_once then
            drew_once = true
            log('float panel drawn (第一次)')
        end
        UIm.poll()
    elseif why == 'no world yet' or why == 'stingray missing' then
        P.status = 'waiting: ' .. tostring(why)
    else
        log('panel disabled: ' .. tostring(why))
        P.visible, P.status = false, 'disabled: ' .. tostring(why)
    end
    if frames % 300 == 0 then log_flush() end
end

-- ---------------------------------------------------------------------------
-- 7. 钩子
-- ---------------------------------------------------------------------------
local prev_update = update
update = function(...)
    local a, b, c = prev_update and prev_update(...)
    local ok, err = pcall(frame)
    if not ok then
        P.errs = (P.errs or 0) + 1
        if P.errs <= 5 then log('frame error: ' .. tostring(err)) end
    end
    return a, b, c
end

local prev_shutdown = shutdown
shutdown = function(...)
    if UI then pcall(UI.destroy) end
    log_flush(true)
    if prev_shutdown then return prev_shutdown(...) end
end

P.status = 'ready'
P.modules = { platform = U, scan = S, ui = UI, tab = TB, kernel = K, memscan = MS, aob = AOB }
log(string.format('ready: resources=%d', RES_N))

return P
