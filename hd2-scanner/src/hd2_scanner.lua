-- HD2-Addon: mods/junze/hd2_scanner
-- ===========================================================================
--  HD2 Scanner —— ESC 菜单宿主（设计见 docs/MENU-PANEL-设计定稿.md）
--
--  职责：页面宿主（ESC 第 4 / 第 5 页签，被占则自绘浮动面板）+ _G.HD2Menu 注册接口。
--        本体零内容 —— 本文件不认识任何业务 mod。
--
--  红线：只写 UI 结构（labels/state/flag），绝不写游戏数据表。
--
--  ⚠ 本文件只是**入口 + 编排**；真正的逻辑在同一个 archive 的另外 5 个资源里：
--       mods/junze/hd2_scanner/platform   平台层（ffi/kernel32/内存/日志）
--       mods/junze/hd2_scanner/scan       签名扫描 + MENU/TAB/FONTS 解码器
--       mods/junze/hd2_scanner/ui         user32 输入 + stingray 渲染
--       mods/junze/hd2_scanner/tab        菜单探测 + 页签落位
--       mods/junze/hd2_scanner/registry   插件注册表 / _G.HD2Menu
--     这些资源**不带** `-- HD2-Addon:` 声明，所以 loader 不会把它们当独立 addon。
-- ===========================================================================

local MOD = 'mods/junze/hd2_scanner'
if rawget(_G, MOD) then return end

local P = {
    version  = '0.7.0',
    api      = 1,
    status   = 'starting',
    mode     = 'float',      -- 'float' | 'tab'
    trigger  = nil,          -- 'menu'（跟随 ESC）| 'hotkey'
    pages    = {},
    by_id    = {},
    revision = 0,
    cursor   = 1,
    visible  = false,
    hotkey   = 0x78,         -- VK_F9
    page     = 'root',
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
    ui       = 'mods/junze/hd2_scanner/ui',
    tab      = 'mods/junze/hd2_scanner/tab',
    registry = 'mods/junze/hd2_scanner/registry',
    kernel   = 'mods/junze/hd2_scanner/kernel',
    memscan  = 'mods/junze/hd2_scanner/memscan',
}

local ctx = { P = P, loader = loader, mdl = mdl, RES = RES }

local function load_module(key)
    local name = RES[key]
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
local MENU, TAB, FONTS = S.MENU, S.TAB, S.FONTS
local text_section = S.text_section
local GAME, game_open, mem_read, hex8 = U.GAME, U.game_open, U.mem_read, U.hex8

-- ---------------------------------------------------------------------------
-- 3. 页面内容（①a：ui 不认识 registry，只调 ctx.rows()）
-- ---------------------------------------------------------------------------
local function build_root_rows()
    local rows = {}
    if #P.pages == 0 then
        rows[#rows+1] = { label = '(还没有 mod 注册页面)', tone = 'dim', selectable = false }
    end
    for _, page in ipairs(P.pages) do
        local st
        if type(page.status) == 'function' then
            local ok, v = pcall(page.status)
            if ok and type(v) == 'table' then st = v end
        end
        rows[#rows+1] = {
            label = page.title,
            value = st and st.text or (page.build and '>' or ''),
            tone  = st and st.tone or (page.build and 'text' or 'dim'),
            note  = st and st.note or nil,
            open  = page.build ~= nil,
            _page = page,
        }
    end
    return rows, 'HD2 MENU'
end

-- ---------------------------------------------------------------------------
-- 3.4 行规范化：把插件的「可调项」变成能看懂能点的行
--      kind='action'  点击执行 on_click
--      kind='toggle'  点击取反（需要 get/set）
--      kind='choice'  点击展开下拉，选一个就设上（需要 choices/get/set）
-- ---------------------------------------------------------------------------
local EXPAND = { page = nil, index = nil }      -- 哪个下拉展开了

local function normalize_rows(page, rows)
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == 'table' then
            local kind = row.kind
            -- 取当前值
            if (kind == 'choice' or kind == 'toggle') and type(row.get) == 'function' then
                local ok, v = pcall(row.get)
                row.value = ok and tostring(v) or '?'
            end
            local open = (EXPAND.page == page.id and EXPAND.index == i)

            if kind == 'choice' then
                row.note = open and '▴ 收起' or '▾ 展开'
                if type(row.on_click) ~= 'function' then
                    row.on_click = function()
                        if open then EXPAND.page, EXPAND.index = nil, nil
                        else EXPAND.page, EXPAND.index = page.id, i end
                    end
                end
            elseif kind == 'toggle' then
                row.note = '点击切换'
                if type(row.on_click) ~= 'function' then
                    row.on_click = function()
                        local ok, v = pcall(row.get)
                        if ok and type(row.set) == 'function' then pcall(row.set, not v) end
                    end
                end
            elseif kind == 'action' and type(row.on_click) == 'function' then
                row.note = row.note or '▸'
            end

            out[#out + 1] = row

            -- 展开的选项：插在它下面
            if kind == 'choice' and open then
                local cur = row.value
                for _, c in ipairs(row.choices or {}) do
                    local cs = tostring(c)
                    out[#out + 1] = {
                        label = '      ' .. cs .. ((cs == cur) and '   ✓' or ''),
                        value = '',
                        tone  = (cs == cur) and 'ok' or 'dim',
                        on_click = function()
                            if type(row.set) == 'function' then pcall(row.set, c) end
                            EXPAND.page, EXPAND.index = nil, nil
                        end,
                    }
                end
            end
        end
    end
    return out
end

-- 面板自己的配置落盘（面板也是"插件"，自己的配置自己存）
-- ⚠⚠ local 必须声明在【所有用它的函数之前】（Lua 的词法作用域是位置性的，不是文本顺序）。
--   2026-10-02 实机踩到：cfg_save(L192) 和 build_page_rows(L208) 都用了 CFG，
--   而 local CFG 原本在 L237 —— 于是那两处的 CFG 解析成【全局 nil】。
--   症状：每次面板渲染页面都抛 `attempt to index global 'CFG'`，页面画不出来。
--   所以这里先把两个 local 前置声明，具体赋值留在下面原来的位置。
local CFG, CFG_FILE

local function cfg_save()
    pcall(function()
        local f = io.open(CFG_FILE, 'w')
        if not f then return end
        f:write('# HD2 Scanner - 改完 1 秒内热生效\n')
        f:write('draw='        .. (CFG.draw        and 'on' or 'off') .. '\n')
        f:write('claim='       .. (CFG.claim       and 'on' or 'off') .. '\n')
        f:write('probe='       .. (CFG.probe       and 'on' or 'off') .. '\n')
        f:write('allow_5th='   .. (CFG.allow_5th   and 'on' or 'off') .. '\n')
        f:write(string.format('hotkey=0x%X\n', CFG.hotkey))
        f:write('detail=' .. tostring(CFG.detail or 2) .. '\n')
        f:close()
    end)
end

local function build_page_rows(page)
    if type(page.build) == 'function' then
        local pctx = {
            id    = page.id,
            log   = function(s) log('[' .. page.id .. '] ' .. tostring(s)) end,
            cheap = true,
            detail = CFG.detail or 2,   -- ★ 插件靠这个决定自己那一页显示到第几档
        }
        local ok, rows = pcall(page.build, pctx)
        if ok and type(rows) == 'table' then
            page.fails = 0
            -- 子页统一在最后加一行可点的「返回」（键盘的 Backspace 会和游戏菜单冲突）
            rows[#rows + 1] = { label = '‹ 返回', action = 'back', tone = 'dim' }
            return normalize_rows(page, rows), page.title
        end
        page.fails = (page.fails or 0) + 1
        if page.fails == 1 then log('plugin build failed: ' .. page.id .. ': ' .. tostring(rows)) end
        if page.fails >= 20 then page.disabled = 'build keeps failing' end
        return { { label = '(build failed: ' .. tostring(rows) .. ')', tone = 'bad' } }, page.title
    end
    return { { label = '(这一页没有内容)', tone = 'dim' } }, page.title
end

local function current_rows()
    if P.page == 'root' then return build_root_rows() end
    local page = P.by_id[P.page]
    if not page or page.disabled then P.page = 'root' return build_root_rows() end
    return build_page_rows(page)
end

-- ---------------------------------------------------------------------------
-- 3.5 热配置（每次 ~1 秒重读，不用重编译就能二分定位崩溃）
--     %LOCALAPPDATA%\CowboyBingus\Helldivers2\HD2Scanner.cfg
-- ---------------------------------------------------------------------------
CFG_FILE = U.BASE .. '/HD2Scanner.cfg'
CFG = { draw = false, claim = false, probe = true, allow_5th = false, hotkey = 0x78,
              detail = 2 }      -- 面板详情档位：1 简 / 2 标准 / 3 诊断（插件通过 pctx.detail 拿到）
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
        f:write('detail=2       # 详情档位 1/2/3：1 只看状态+动作，2 加关键信息，3 全部内部细节\n')
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
            elseif k == 'detail' then
                local d = tonumber(v)                       -- ⚠ 数字型，不能走下面那个布尔分支
                if d and d >= 1 and d <= 3 then CFG.detail = d end
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
ctx.flush     = U.log_flush
ctx.allow_5th = false      -- 由 cfg 覆盖，见下面
ctx.rows     = current_rows
ctx.rows_key = function() return tostring(P.revision) .. '|' .. tostring(P.page) end
P.rows, P.rows_key = ctx.rows, ctx.rows_key       -- 便于实机时手动调用/排查

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
local RG
do
    local m, e = load_module('registry')
    if not m then P.status = 'failed: ' .. e log(P.status) return P end
    local ok, val = pcall(m.new, ctx)
    if not ok then P.status = 'failed: registry.new: ' .. tostring(val) log(P.status) return P end
    RG = val
end
ctx.registry = RG
local _G_HD2Menu = RG.api

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
            rawset(_G, 'HD2Scanner', K)      -- ★ 对外接口：其它 mod 从这里拿地址
            log('_G.HD2Scanner 已导出')
        end
    end
end

-- ---------------------------------------------------------------------------
-- 4.5 面板把自己也注册成一个插件 —— 它的"扫描状态"就在这一页
-- ---------------------------------------------------------------------------
local function yn(b) return b and 'OK' or '失败' end

RG.api.register{
    id    = 'hd2_scanner',
    title = 'HD2 Scanner',
    order = 0,                       -- 排最前
    status = function()
        local sc = P.selfcheck
        local ok = sc and sc.ok == sc.total
        return { text = ok and '正常' or '有差异',
                 tone = ok and 'ok' or 'warn',
                 note = 'v' .. P.version }
    end,
    build = function()
        local rows = {}
        local function add(label, value, tone, note)
            rows[#rows+1] = { label = label, value = value, tone = tone or 'text', note = note }
        end
        local function hdr(txt) rows[#rows+1] = { label = txt, tone = 'dim', selectable = false } end

        hdr('── 本体 ──')
        add('版本', P.version, 'text')
        add('宿主', loader and 'Bingus Shared Loader' or (mdl and 'MDL' or '无'),
            loader and 'text' or 'warn')
        add('状态', tostring(P.status), P.errs and P.errs > 0 and 'warn' or 'ok')
        add('错误计数', tostring(P.errs or 0), (P.errs or 0) > 0 and 'bad' or 'dim')

        hdr('── 扫描（game.dll 签名）──')
        local sc = P.scan
        if sc then
            add('代码段', string.format('%.1f MB @ 0x%X', sc.text_size / 1048576, sc.text_rva), 'dim')
            add('解析耗时', string.format('%.0f ms', sc.ms), sc.ms < 500 and 'ok' or 'warn')
            add('MenuSystem',   yn(sc.menu), sc.menu and 'ok' or 'bad')
            add('ESC 页签',     yn(sc.tab),  sc.tab  and 'ok' or 'bad')
            add('字体初始化器', yn(sc.font), sc.font and 'ok' or 'bad')
        else
            add('（还没扫描）', '', 'dim')
        end
        local chk = P.selfcheck
        if chk then
            local okp = chk.ok == chk.total
            add('自检比对', string.format('%d/%d', chk.ok, chk.total), okp and 'ok' or 'bad',
                okp and '与 MDL 基准逐位一致' or '见 HD2Scanner.log')
        end

        hdr('── 界面 ──')
        add('浮动面板', CFG.draw and '开' or '关', CFG.draw and 'ok' or 'dim')
        add('认领页签', CFG.claim and '开' or '关（只整浮窗）', 'dim')
        add('菜单探针', CFG.probe and '开' or '关', 'dim')
        add('探测方式', tostring(P.trigger), 'dim', P.trigger == 'menu' and '跟随 ESC' or '热键')
        if UI and UI.pos then
            local pos = UI.pos()
            if pos then add('面板位置', string.format('%d, %d', pos.x, pos.y), 'dim',
                            UI.dragging and UI.dragging() and '拖曳中' or '拖标题栏可移动') end
        end
        add('当前页 / 行', tostring(P.page) .. ' / ' .. tostring(P.cursor), 'dim')
        add('绘制次数', tostring(P.draw_count or 0), 'dim')
        add('插件数', tostring(#P.pages), 'text')

        -- ↓↓↓ 示范：面板自己的设置，全部点着改
        hdr('── 面板设置（点着改）──')
        rows[#rows+1] = { label='浮动面板', kind='toggle',
            get=function() return CFG.draw end,
            set=function(v) CFG.draw = v cfg_save() log('cfg: draw=' .. tostring(v)) end }
        rows[#rows+1] = { label='认领 ESC 页签', kind='toggle',
            get=function() return CFG.claim end,
            set=function(v) CFG.claim = v cfg_save() log('cfg: claim=' .. tostring(v)) end,
            note='（要重开游戏才生效）' }
        rows[#rows+1] = { label='菜单探针', kind='toggle',
            get=function() return CFG.probe end,
            set=function(v) CFG.probe = v cfg_save() log('cfg: probe=' .. tostring(v)) end }
        rows[#rows+1] = { label='允许占第 5 页签', kind='choice', choices={'off','on'},
            get=function() return CFG.allow_5th and 'on' or 'off' end,
            set=function(v) CFG.allow_5th = (v == 'on') cfg_save()
                log('cfg: allow_5th=' .. tostring(v) .. '（要重开游戏才生效）') end }
        local HK_CHOICES = {'0x78 (F9)','0x77 (F8)','0x76 (F7)','0x75 (F6)'}
        rows[#rows+1] = { label='热键（探不到 MenuSystem 时）', kind='choice',
            choices=HK_CHOICES,
            get=function()
                -- ⚠ 必须返回 choices 里的**原样字符串**：下拉靠 row.value 跟 choices 精确比
                --   来标「✓ 当前」，返回 '0x78' 而 choices 是 '0x78 (F9)' 就永远标不出来。
                local want = string.format('0x%X', CFG.hotkey)
                for _, c in ipairs(HK_CHOICES) do
                    if c:sub(1, #want) == want then return c end
                end
                return want
            end,
            set=function(v) local n = tonumber(v:match('0x%x+'))
                if n then CFG.hotkey = n cfg_save() log('cfg: hotkey=' .. v) end end }
        local DETAIL_CHOICES = {'1 简','2 标准','3 诊断'}
        rows[#rows+1] = { label='详情档位', kind='choice',
            choices=DETAIL_CHOICES,
            get=function() return DETAIL_CHOICES[CFG.detail or 2] end,
            set=function(v) local n = tonumber(v:match('^%d'))
                if n and n >= 1 and n <= 3 then CFG.detail = n cfg_save() log('cfg: detail=' .. n) end end,
            note='各页显示多少内部细节' }
        return rows
    end,
    api = P.api,
}
log('自注册为插件（自带扫描状态页）')

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
P.modules = { platform = U, scan = S, ui = UI, tab = TB, registry = RG, kernel = K, memscan = MS, api = _G_HD2Menu }
log(string.format('ready: plugins=%d; resources=%d', #P.pages, 6))

return P
