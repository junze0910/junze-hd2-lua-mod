-- ⚠⚠ 已退役（2026-10-04）：本模块**不打包、不加载**。
--   原因：自绘面板 + `_G.HD2Menu` 页面体系整体退役 —— 消费者一律注册 `_G.ModOptionsMenu`。
--   保留源码只为 ④⑤（浮动面板/页签认领）将来可能的改动；恢复需三步：
--     ① build.py 的 MODULES 加回 ui；② hd2_scanner.lua 的 RES 加回 ui 并把 ctx.rows 那套接回来；
--     ③ 面板要显示的内容改成不认识 registry 的形态（本文件只依赖 ctx.rows / ctx.rows_key）。
--   注：现在直接加载本文件会报错（ctx.rows 已不存在），这是预期的。
-- HD2 Scanner / ui —— user32 输入 + stingray 渲染 + 字体装配 + 行绘制
-- 资源名: mods/junze/hd2_scanner/ui
-- 只通过 ctx.rows() / ctx.rows_key() 拿内容，不认识 registry（①a）
local M = {}

function M.new(ctx)
    local P, log = ctx.P, ctx.log
    local U = ctx.platform
    local ffi, mem_read, hex8 = U.ffi, U.mem_read, U.hex8
    local GAME = U.GAME
    local FONTS = ctx.scan.FONTS
    local rows_provider, rows_key = ctx.rows, ctx.rows_key

    -- ---------------------------------------------------------------------------
    -- 12. 输入（user32 采样）
    -- ---------------------------------------------------------------------------
    local u32, input_ok = nil, false
    if ffi then
        pcall(function()
            ffi.cdef[[
                void *GetForegroundWindow(void);
                int GetCursorPos(int32_t *pt);
                int ScreenToClient(void *win, int32_t *pt);
                int GetClientRect(void *win, int32_t *rc);
                int16_t GetAsyncKeyState(int key);
            ]]
            u32 = ffi.load('user32')
            input_ok = true
        end)
    end
    local s_pt = input_ok and ffi.new('int32_t[2]') or nil
    local s_rc = input_ok and ffi.new('int32_t[4]') or nil
    local VK = {up=0x26, down=0x28, left=0x25, right=0x27, enter=0x0D, esc=0x1B, back=0x08}

    local keys = {}
    local function key_down(vk)
        if not input_ok then return false end
        local k = tonumber(u32.GetAsyncKeyState(vk))
        return k ~= nil and k < 0
    end
    local function key_edge(name, vk)
        local down = key_down(vk)
        local edge = down and not keys[name]
        keys[name] = down
        return edge
    end

    -- 滚轮：走游戏自己的输入系统（user32 轮询拿不到滚轮）
    -- ⚠ sr() 在 §13 才定义，这里必须直接惰性取 _G.stingray
    local ids = {}
    local function engine_mouse()
        local s = rawget(_G, 'stingray')
        if type(s) == 'table' and type(s.Mouse) == 'table' then return s.Mouse end
        return nil
    end
    local function axis(name)
        local Mo = engine_mouse()
        if not Mo then return nil end
        local k = 'a:' .. name
        if ids[k] == nil then
            local ok, id = pcall(Mo.axis_id, name)
            ids[k] = (ok and id) or false
        end
        local id = ids[k]
        if not id then return nil end
        local ok, v = pcall(Mo.axis, id)
        return ok and v or nil
    end
    local function wheel()
        local v = axis('wheel')
        return (type(v) == 'number') and v or 0
    end

    local function cursor_gui(rw, rh)
        if not (input_ok and u32) then return nil end
        local win = u32.GetForegroundWindow()
        if win == nil then return nil end
        if u32.GetCursorPos(s_pt) == 0 then return nil end
        if u32.ScreenToClient(win, s_pt) == 0 then return nil end
        if u32.GetClientRect(win, s_rc) == 0 then return nil end
        local w, h = s_rc[2]-s_rc[0], s_rc[3]-s_rc[1]
        if not (w > 0 and h > 0) then return nil end
        return s_pt[0]*rw/w, (h - s_pt[1])*rh/h
    end

    -- ---------------------------------------------------------------------------
    -- 13. 渲染（stingray screen gui；有字体就画真字，没有就只画框）
    -- ---------------------------------------------------------------------------
    local G = {gui=nil, world=nil, failed=false, zones={}, text=false,
               pos=nil, drag={on=false, dx=0, dy=0}, header=nil}

    -- 拖曳后的位置记在文件里，下次进来还在原地
    local POS_FILE = U.BASE .. '/HD2Scanner.pos'
    local function load_pos()
        pcall(function()
            local f = io.open(POS_FILE, 'r')
            if not f then return end
            local t = f:read('*a') f:close()
            local sx, sy = t:match('(%-?%d+)%s+(%-?%d+)')
            if sx and sy then G.pos = { x = tonumber(sx), y = tonumber(sy) } end
        end)
    end
    local function save_pos()
        pcall(function()
            if not G.pos then return end
            local f = io.open(POS_FILE, 'w')
            if not f then return end
            f:write(string.format('%d %d\n', G.pos.x, G.pos.y))
            f:close()
        end)
    end
    load_pos()
    local FONT = {ready=false, failed=false}
    local scale, row_h = 1, 26

    local function sr() return rawget(_G, 'stingray') end

    local function panel_world()
        local s = sr()
        if type(s) ~= 'table' or type(s.Application) ~= 'table' then return nil end
        local okm, main = pcall(s.Application.main_world)
        local okw, worlds = pcall(s.Application.worlds)
        if not okw or type(worlds) ~= 'table' then return nil end
        for _, w in ipairs(worlds) do
            if not (okm and w == main) then return w end
        end
        return nil
    end

    local function panel_destroy()
        local s = sr()
        if G.gui and G.world and s then pcall(s.World.destroy_gui, G.world, G.gui) end
        G.gui, G.world, G.colors, G.draw_sig = nil, nil, nil, nil
        FONT.ready, FONT.ink, FONT.font_id, FONT.material_id = false, nil, nil, nil  -- 材质绑在旧 gui 上
        FONT.next_try, FONT.warned = 0, false                                       -- 立刻允许重试
    end

    local function rect(x, y, w, h, z, col)
        local s = sr()
        if not (s and G.gui and col) then return end
        pcall(s.Gui.rect, G.gui, s.Vector3(x, y, z or 980), s.Vector2(w, h), col)
    end

    local function font_setup()
        if FONT.ready or FONT.failed or not GAME.ready then return end
        local s = sr()
        if type(s) ~= 'table' or type(s.IdString64) ~= 'table' then FONT.failed = true return end
        -- ★ 字体子系统在开机那一刻可能还没初始化好（MDL 也是延后到真要用时才读）。
        --   所以读失败**不设 failed**，每 2 秒重试一次，直到成功。
        local now = os.clock()
        if now < (FONT.next_try or 0) then return end
        FONT.next_try = now + 2
        local readmem = function(a, n) return mem_read(a, n) end
        local ok, hashes = pcall(FONTS.read, readmem, GAME.base, GAME.slots)
        if not ok or not hashes then
            FONT.last_why = tostring(hashes)
            if not FONT.warned then
                FONT.warned = true
                log('font: 还没就绪，稍后重试（' .. FONT.last_why .. '）')
            end
            return
        end
        local okm, ink = pcall(s.Gui.material, G.gui, s.IdString64.from_hex(hashes.material))
        if not okm or ink == nil then
            FONT.last_why = 'material unavailable'
            return                              -- 也重试
        end
        pcall(function()
            local function slot(h) return s.IdString64.from_hex(h .. '00000000') end
            for _, h in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'}) do
                s.Material.set_scalar(ink, slot(h), 0)
            end
            s.Material.set_vector2(ink, slot('e13777ce'), s.Vector2(1, -1))
            s.Material.set_vector4(ink, slot('7701209e'), s.Color(0, 0, 0, 0))
            s.Material.set_texture(ink, slot('88bac99b'), s.IdString64.from_hex(hashes.atlas))
        end)
        FONT.font_id, FONT.material_id, FONT.ink = s.IdString64.from_hex(hashes.font),
                                                    s.IdString64.from_hex(hashes.material), ink
        FONT.ready = true
        -- ⚠ 只打一次：面板每 60 帧重建会重置 FONT.ready 并重取材质，
        --   每次都打日志会把 400 行缓冲刷爆（2026-10-02 实测刷了 392 行，
        --   把 selfcheck / kernel 广播全挤没了）
        if not FONT.logged then
            FONT.logged = true
            log('font ready: ' .. hashes.font .. ' / ' .. hashes.atlas .. ' / ' .. hashes.material)
        end
    end

    local function text(txt, x, y, size, col, z)
        if not FONT.ready then return end
        local s = sr()
        pcall(s.Gui.text, G.gui, txt, FONT.font_id, size, FONT.material_id,
              s.Vector3(x, y, z or 902), col or s.Color(220, 228, 214, 255))
    end

    local function measure(txt, size)
        if not FONT.ready then return #txt * size * 0.5 end
        local s = sr()
        local ok, lo, hi = pcall(s.Gui.text_extents, G.gui, txt, FONT.font_id, size)
        if not (ok and lo and hi) then return #txt * size * 0.5 end
        return s.Vector2.x(hi) - s.Vector2.x(lo)
    end
    -- ---------------------------------------------------------------------------
    -- 15. 浮动面板绘制
    -- ---------------------------------------------------------------------------
    local function row_label(row)
        if type(row.label) == 'string' then return row.label end
        return tostring(row.label or '?')
    end

    local function panel_colors()
        if G.colors then return G.colors end
        local s = sr()
        if type(s) ~= 'table' then return nil end
        local c = {}
        pcall(function()
            c.bg  = s.Color(12, 16, 14, 235)
            c.hdr = s.Color(34, 42, 36, 255)
            -- ⚠ 选中/悬停/闪光这三个是**行底色**，行上的说明文字用的是 dim(150,162,148)。
            --   原来 sel=(92,112,74) 跟 dim 只差约 1.5 倍亮度 -> 说明文字糊在底色里看不清。
            --   2026-10-02 实机反馈后整体压暗约 40%，保持 sel > hover、flash 最亮的层次。
            c.sel   = s.Color(55, 67, 45, 255)      -- 选中
            c.hover = s.Color(33, 41, 34, 255)      -- 悬停：比选中暗
            c.flash = s.Color(100, 124, 76, 255)    -- 点击闪光：最亮，但不盖住字
            c.txt = s.Color(216, 224, 208, 255)
            c.dim = s.Color(150, 162, 148, 255)
            c.ok    = s.Color(150, 210, 140, 255)
            c.warn  = s.Color(226, 196, 110, 255)
            c.bad   = s.Color(226, 122, 110, 255)
        end)
        if not (c.bg and c.hdr and c.sel and c.hover and c.flash and c.txt and c.dim
                and c.ok and c.warn and c.bad) then
            return nil
        end
        c.TONE = {text = c.txt, dim = c.dim, ok = c.ok, warn = c.warn, bad = c.bad}
        G.colors = c
        return c
    end

    -- F1：行内容缓存（默认 1 秒重算一次，绕开"每帧调 status()"）
    local RC = {rev = -1, page = nil, at = -1, rows = nil, title = nil}
    local function cached_rows(now)
        if RC.rows and RC.rev == P.revision and RC.page == P.page and (now - RC.at) < 1.0 then
            return RC.rows, RC.title
        end
        local rows, title = rows_provider()
        RC.rev, RC.page, RC.at, RC.rows, RC.title = P.revision, P.page, now, rows, title
        return rows, title
    end

    local function panel_draw()
        local s = sr()
        if type(s) ~= 'table' or type(s.Gui) ~= 'table' or type(s.World) ~= 'table' then
            return false, 'stingray missing'
        end
        if not G.gui then
            local w = panel_world()
            if not w then return false, 'no world yet' end
            local okg, gui = pcall(s.World.create_screen_gui, w, 'scale', 1, 1)
            if not okg or gui == nil then return false, 'create_screen_gui failed' end
            G.gui, G.world = gui, w
        end
        local okr, rw, rh = pcall(s.Gui.resolution)
        if not okr or type(rw) ~= 'number' or rw < 640 or type(rh) ~= 'number' or rh < 480 then
            return false, 'resolution'
        end

        font_setup()

        scale = math.min(rw / 1920, rh / 1080)
        local now = os.clock()
        local rows, title = cached_rows(now)
        local n     = #rows
        local w     = math.floor(720 * scale)
        local head  = math.floor(44 * scale)
        local foot  = math.floor(28 * scale)
        local rowh  = math.floor(row_h * scale)
        local h     = head + n * rowh + foot
        -- 位置：优先用拖曳后记住的，否则居中；一律钳在屏幕内
        if not G.pos then
            G.pos = { x = math.floor((rw - w) / 2), y = math.floor((rh - h) / 2) }
        end
        local x = math.max(0, math.min(G.pos.x, math.max(0, rw - w)))
        local y = math.max(0, math.min(G.pos.y, math.max(0, rh - h)))
        G.pos.x, G.pos.y = x, y
        G.header = { x = x, y = y, w = w, h = head }     -- 标题栏 = 拖曳把手

        local C = panel_colors()
        if not C then return false, 'Color ctor' end
        local bg, hdr, sel, col_txt, col_dim, TONE = C.bg, C.hdr, C.sel, C.txt, C.dim, C.TONE
        local hover, flash = C.hover, C.flash

        -- F4：内容签名没变且未满 60 帧 → 不重画（Stingray screen gui 是保留式的）
    local sig = table.concat({rows_key(), tostring(P.cursor), tostring(n), tostring(FONT.ready),
                              tostring(x), tostring(y), tostring(G.drag.on),
                              tostring(P.hover or 0),
                              tostring(G.flash and G.flash.index or 0),
                              tostring(G.flash and (os.clock() < G.flash.t) and 1 or 0)}, '|')
        if G.gui and sig == G.draw_sig then
            G.unchanged = G.unchanged + 1
            if G.unchanged < 60 then return true end
        end
        G.unchanged, G.draw_sig = 0, sig

        -- ★ 关键：Stingray 的 screen gui 是**保留式**的（「60 帧不重画还能显示」就是靠这个）。
        --   往同一个 gui 上反复 rect 只会只增不减，几十秒就把绘制列表撑爆 -> 0xC0000026。
        --   MDL 每次重画都先 self.clear() 再 create_screen_gui，我们必须一样。
        do
            local target = panel_world()
            if not target then return false, 'no world yet' end
            panel_destroy()                                   -- 清 G.gui / G.world / G.colors / FONT
            local okg, gui = pcall(s.World.create_screen_gui, target, 'scale', 1, 1)
            if not okg or gui == nil then return false, 'create_screen_gui failed' end
            G.gui, G.world = gui, target
        end
        local C2 = panel_colors()
        if not C2 then return false, 'Color ctor' end
        bg, hdr, sel, col_txt, col_dim, TONE = C2.bg, C2.hdr, C2.sel, C2.txt, C2.dim, C2.TONE
        font_setup()

        -- ★ 可视窗口：行数超过一屏时只画一段，滚轮翻页（鼠标优先，不吃键盘）
        --   先算完再画 —— 下面三个底框要用最终的 y/h（原来底框画在算之前，一滚动高度就错）
        if P.scroll == nil then P.scroll = 0 end
        if P.scroll < 0 then P.scroll = 0 end
        local maxr = math.max(1, math.floor((rh * 0.78 - head - foot) / rowh))
        local visn = math.min(maxr, n)
        local first = math.min(P.scroll + 1, math.max(1, n - visn + 1))
        P.scroll = first - 1
        G.frame = { x = x, y = y, w = w, h = head + visn*rowh + foot, maxoff = math.max(0, n - visn) }
        h = G.frame.h
        y = math.floor(math.max(0, math.min(G.pos.y or y, rh - h)))
        G.frame.y, G.pos.y = y, y

        -- ★ Stingray 的 screen gui 是 **y 轴向上** 的（原点在左下），而人读界面是从上往下。
        --   所以这里把「从可视顶端往下量 d 处」镜像回 gui 的 y：fy(d) = ytop - d。
        --   面板的包围盒 [y, y+h] 没变，只重排内部 —— 鼠标那套（cursor_gui 的 ScreenToClient
        --   翻转 / 拖曳 / 钳位 / zones 命中）**一行都不用动**，因为它本来就在同一个 y 向上的
        --   空间里，绘制和命中因此一直自洽（能点，只是看着是倒的）。
        --   ⚠ 2026-10-02 之前这段整段是按 y 向下写的，于是整个面板上下镜像：
        --      标题跑到最底、hint 跑到最顶、行序整个倒过来（「‹ 返回」顶在最上面）。
        local ytop = y + h
        local function fy(d) return ytop - d end

        rect(x, y, w, h, 979, bg)                     -- 底板
        rect(x, fy(head), w, head, 980, hdr)          -- 标题栏 = 可视顶端
        rect(x, y, w, foot, 980, hdr)                 -- 底栏   = 可视底端
        G.zones = {}
        G.header = { x = x, y = fy(head), w = w, h = head }

        local now = os.clock()
        for vi = 1, visn do
            local i  = first + vi - 1
            local row = rows[i]
            local ry = fy(head + vi*rowh)          -- 该行矩形在 gui 坐标里的底边
            -- 优先级：点击闪光 > 上次点击 > 鼠标悬停
            local bcol = ((G.flash and G.flash.index == i and now < G.flash.t) and flash)
                      or (i == P.cursor and sel)
                      or (i == P.hover and hover)
            if bcol then rect(x + 4, ry, w - 8, rowh - 2, 981, bcol) end
            local col = TONE[row.tone or 'text'] or col_txt
            text(row_label(row), x + 14, ry + rowh*0.28, 18, col, 902)
            if row.value ~= nil and tostring(row.value) ~= '' then
                text(tostring(row.value), x + w*0.52, ry + rowh*0.28, 18, col, 902)
            end
            if row.note ~= nil then
                text(tostring(row.note), x + w*0.74, ry + rowh*0.30, 15, col_dim, 902)
            end
            G.zones[i] = {x = x + 4, y = ry, w = w - 8, h = rowh - 2, action = 'row', index = i}
            if G.zones[i] then G.zones[i].label = row_label(row) end
        end
        text(title, x + 14, fy(head) + head*0.28, 20, col_txt, 902)
        local hint
        if n > visn then
            hint = string.format('鼠标点击操作 · 滚轮翻页  [%d-%d / %d]', first, first + visn - 1, n)
        else
            hint = '鼠标悬停选择 · 点击进入/执行 · Esc 关闭菜单'
        end
        text(hint, x + 14, y + foot*0.22, 15, col_dim, 902)

        P.rows, P.title = rows, title
        return true
    end

    -- ---------------------------------------------------------------------------
    -- 16. 输入处理
    -- ---------------------------------------------------------------------------
    -- ★ 纯鼠标：面板不绑任何键盘键。
    --   原因：我们只是"额外读一遍按键"，**没有能力把事件吃掉** ——
    --   游戏自己的 ESC 菜单照样收到同一个键（Backspace 会一路退到关菜单，
    --   Enter 有机会点到左边的「退出游戏」）。所以面板一律只认鼠标。
    local function activate(index)
        local row = (P.rows or {})[index or P.cursor]
        if not row then return end
        if row.open and row._page then
            P.page, P.cursor = row._page.id, 1
        elseif row.action == 'back' then
            P.page, P.cursor = 'root', 1
        elseif type(row.on_click) == 'function' then
            pcall(row.on_click, row)          -- ★ 通用点击回调（action / toggle / choice / 下拉选项都用它）
        end
    end

    local function panel_input(rw, rh)
        local gx, gy = cursor_gui(rw, rh)
        local lmb  = key_down(0x01)
        local edge = key_edge('click', 0x01)

        -- ===== 拖曳：只在**标题栏**按下才开始，不抢行的点击 =====
        if edge and gx and G.header and G.pos then
            local hz = G.header
            if gx >= hz.x and gx <= hz.x + hz.w and gy >= hz.y and gy <= hz.y + hz.h then
                G.drag.on = true
                G.drag.dx, G.drag.dy = gx - G.pos.x, gy - G.pos.y
            end
        end
        if G.drag.on then
            if lmb and gx then
                G.pos.x, G.pos.y = gx - G.drag.dx, gy - G.drag.dy
                if rw and rh then      -- 拖到屏幕外也留一点边
                    G.pos.x = math.max(0, math.min(G.pos.x, rw - 120))
                    G.pos.y = math.max(0, math.min(G.pos.y, rh - 40))
                end
            else
                G.drag.on = false
                save_pos()
            end
            return                          -- 拖曳期间不处理行点击
        end

        -- 滚轮翻页（光标在面板内才响应）
        local wv = wheel()
        if wv ~= 0 and gx and gy and G.frame then
            local f = G.frame
            if gx >= f.x and gx <= f.x + f.w and gy >= f.y and gy <= f.y + f.h then
                P.scroll = math.max(0, math.min((P.scroll or 0) - (wv > 0 and 3 or -3), f.maxoff))
            end
        end

        -- 悬停高亮：只动 P.hover，**不动 P.cursor**
        local hit = nil
        if gx and G.zones then
            for _, z in ipairs(G.zones) do
                if gx >= z.x and gx <= z.x + z.w and gy >= z.y and gy <= z.y + z.h then
                    hit = z.index
                    break
                end
            end
        end
        P.hover = hit

        if hit and edge then
            G.flash = { index = hit, t = os.clock() + 0.20 }    -- 点击闪光 200ms
            activate(hit)
            P.cursor = hit
        end
    end


    local function resolution()
        local s = sr()
        if type(s) ~= 'table' then return nil end
        local ok, w, h = pcall(s.Gui.resolution)
        if ok and type(w) == 'number' then return w, h end
        return nil
    end

    return {
        draw    = panel_draw,
        poll    = function()
            local rw, rh = resolution()
            if rw then panel_input(rw, rh) end
        end,
        destroy = panel_destroy,
        shown   = function() return G.gui ~= nil end,
        key_edge = key_edge,
        resolution = resolution,
        row_label = row_label,
        pos = function() return G.pos end,
        dragging = function() return G.drag.on end,
        VK = VK,
        FONT = FONT,
    }
end

return M
