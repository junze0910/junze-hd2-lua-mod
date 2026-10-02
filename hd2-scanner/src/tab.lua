-- HD2 Scanner / tab —— 菜单探测（跟随 ESC）+ 页签落位（第 4 / 第 5）
-- 资源名: mods/junze/hd2_scanner/tab
local M = {}

function M.new(ctx)
    local P, log = ctx.P, ctx.log
    local U = ctx.platform
    local raw_read, rd_u32, rd_u64, mem_read, mem_write, hex8 = U.raw_read, U.rd_u32, U.rd_u64, U.mem_read, U.mem_write, U.hex8
    local s_u32, s_u64 = U.s_u32, U.s_u64
    local GAME, ffi = U.GAME, U.ffi
    local TAB = ctx.scan.TAB
    local ALLOW_5TH = (ctx.allow_5th == true)   -- 默认关闭：实测写第 5 槽位会崩（0xC0000026）
    local flush = ctx.flush or function() end   -- 认领前强制落盘，崩了也有日志
    -- 只在指定的 screen 上认为菜单开着（照 MDL：必须 InGame，否则会画到星图/军械库上）
    local SCREENS = ctx.menu_screens or {'InGame'}
    local WANT = {}
    for _, n in ipairs(SCREENS) do WANT[n] = true end

    -- ---------------------------------------------------------------------------
    -- 14. 菜单探测（决定：跟随 ESC 还是热键）
    -- ---------------------------------------------------------------------------
    -- 复用同一个表，避免每帧分配
    local PROBE = {open = false, index = 0, system = 0, name = nil}

    local function menu_probe()
        if not (GAME.ready and GAME.menu) then return nil end
        local b = raw_read(GAME.base + GAME.menu.global, 8)
        if not b then return nil end
        local sys = (b[4] + b[5]*256 + b[6]*65536 + b[7]*16777216) * 4294967296
                  + (b[0] + b[1]*256 + b[2]*65536 + b[3]*16777216)
        if sys < 0x10000 or sys >= 0x0000800000000000 then return nil end
        local h = raw_read(sys, 4)
        if not h then return nil end
        local cur = h[0] + h[1]*256 + h[2]*65536 + h[3]*16777216
        local f = raw_read(sys + GAME.menu.open, 2)
        if not f then return nil end
        PROBE.index  = cur
        PROBE.system = sys
        PROBE.name   = GAME.names and GAME.names[cur] or nil
        -- 照 MDL：必须「开着 + 名字在我们关心的 screen 列表里」。
        -- names 解不出来时 name 为 nil -> 判为没开（安全失败：宁可不显示）
        PROBE.open   = (f[0] ~= 0 and f[1] == 0 and PROBE.name ~= nil and WANT[PROBE.name] == true)
        return PROBE
    end

    local function tab_screen()
        if not (PROBE.system and PROBE.system > 0) then return nil end
        local screen = rd_u64(PROBE.system + 200)          -- TAB.SCREEN_SLOT = 200
        if not screen or screen < 0x10000 or screen % 8 ~= 0 then return nil end
        return screen
    end

    -- ---------------------------------------------------------------------------
    -- 18.5 页签落位（第 4 / 第 5；被占则退浮动面板）
    -- ---------------------------------------------------------------------------
    local OUR_LABEL = 0x4A5C3F21      -- 我们自己的页签 label 哈希（必须唯一，别撞 MDL 的 0x0227B3B0）
    local OUR_TEXT  = 'HD2 MENU'

    local PLACE = {state = 'idle', target = nil, ours = false}

    local function read_u32(addr)
        local raw4 = mem_read(addr, 4)
        if not raw4 then return nil end
        return s_u32(raw4, 0)
    end
    local function read_i32(addr)
        local v = read_u32(addr)
        if v and v >= 2147483648 then v = v - 4294967296 end
        return v
    end
    local function read_ptr(addr)
        local raw8 = mem_read(addr, 8)
        if not raw8 then return nil end
        local p = s_u64(raw8, 0)
        if p < 0x10000 or p >= 0x0000800000000000 then return nil end
        return p
    end

    local function claim_tab()
        local layout = GAME.tab
        if not layout then P.mode = 'float' return end
        if not layout.set_arg then
            PLACE.state = 'float'
            log('set_arg 不可用，退浮动面板')
            return
        end
        local screen = tab_screen()
        if not screen then return end

        local bar   = screen + layout.bar
        local count = read_i32(bar + layout.count)
        if not count then return end
        local labels = {}
        for i = 0, 4 do labels[i] = read_u32(bar + layout.labels + 4*i) end
        local panel = read_i32(screen + 8)          -- PANEL_INDEX = 8

        -- 自愈：已经在栏里
        if count >= 4 and labels[3] == OUR_LABEL then
            if PLACE.state ~= 'ours' then log('自愈：我们已经在第 4 个页签') end
            PLACE.state, PLACE.target, PLACE.ours = 'ours', 3, true
            return
        end
        if count >= 5 and labels[4] == OUR_LABEL then
            if PLACE.state ~= 'ours' then log('自愈：我们已经在第 5 个页签') end
            PLACE.state, PLACE.target, PLACE.ours = 'ours', 4, true
            return
        end

        -- MDL 会不会来抢第 4？（在场 ≠ 会抢：它自己也会退浮动面板）
        local mdl     = rawget(_G, 'MDL')
        local mdl_tab = mdl and mdl.native_tab
        local mdl_wants_4th = (mdl_tab ~= nil) and (mdl_tab.disabled == nil)

        local target
        if count == 3 then
            if mdl_wants_4th then
                if PLACE.state ~= 'yield' then
                    log('MDL 在场且 native_tab 活着 —— 让位，先走浮动面板等它占第 4')
                end
                PLACE.state = 'yield'
                return
            end
            target = 3
    elseif count == 4 then
        if not ALLOW_5TH then
            if PLACE.state ~= 'float' then
                log('第 4 页签已被占用 -> 浮动面板（第 5 页签默认关闭：实测会崩）')
            end
            PLACE.state = 'float'
            return
        end
        target = 4
    else
            if PLACE.state ~= 'float' then
                log(string.format('页签数 %d，第 5 已被 0x%X 占用 -> 浮动面板', count, labels[4] or 0))
            end
            PLACE.state = 'float'
            return
        end

        -- 认领前先强制落盘：万一这次写内存把游戏搞崩，日志也得留下（上次就是崩了才发现日志是空的）
    flush()
    log(string.format('claiming tab: count=%d target=%d bar=0x%X screen=0x%X',
        count, target, bar, screen))

    -- 认领三步
        local okf, fn_labels = pcall(ffi.cast, 'void (*)(void *, const uint32_t *, int32_t)',
                                     GAME.base + layout.set_labels)
        local okg, fn_arg = pcall(ffi.cast, 'void (*)(void *, uint32_t, const char *)',
                                  GAME.base + layout.set_arg)
        if not (okf and okg) then PLACE.state = 'float' log('cast 失败，退浮动面板') return end

        local anchors = PLACE.anchors
        if not anchors then anchors = {} PLACE.anchors = anchors end
        if not anchors[OUR_TEXT] then
            local b = ffi.new('char[?]', #OUR_TEXT + 1)
            ffi.copy(b, OUR_TEXT)
            anchors[OUR_TEXT] = b
        end

        local widget = bar + layout.text + TAB.STRIDE * target
        local ok1 = pcall(fn_arg, ffi.cast('void *', widget), TAB.TEXT_ARG, anchors[OUR_TEXT])
        local arr = ffi.new('uint32_t[8]')
        for i = 0, count-1 do arr[i] = labels[i] end
        arr[count] = OUR_LABEL
        local ok2 = pcall(fn_labels, ffi.cast('void *', bar), arr, count + 1)
        if not (ok1 and ok2) then
            PLACE.state = 'float'
            log('认领失败（set_arg/set_labels 抛错）-> 浮动面板')
            return
        end

        -- 标记按钮的 state / flag —— **照 MDL 的写法：写「当前选中」那个（index <= 3，必然在界内）**。
        -- 别写 target（新槽位）：第 5 槽位越界，实测把游戏搞崩（0xC0000026 STATUS_INVALID_DISPOSITION）。
        local cur = PROBE.index or 0
        mem_write(screen + layout.state + TAB.STRIDE * cur, '\3\0\0\0')
        mem_write(screen + layout.flag  + TAB.STRIDE * cur, '\0')

        -- 回读验证
        local count2 = read_i32(bar + layout.count)
        local lab2   = read_u32(bar + layout.labels + 4*target)
        if count2 == count + 1 and lab2 == OUR_LABEL then
            PLACE.state, PLACE.target, PLACE.ours = 'ours', target, true
            log(string.format('认领成功：第 %d 个页签（现在 %d 个，panel %s）',
                target + 1, count2, tostring(panel)))
            local raw = mem_read(bar + layout.count + 24, 32)
            if raw and ffi then
                local f = ffi.new('float[8]')
                ffi.copy(f, raw, 32)
                local vals = {}
                for i = 0, 7 do vals[#vals+1] = string.format('%.1f', f[i]) end
                log('bar layout: ' .. table.concat(vals, ' '))
            end
        else
            PLACE.state = 'float'
            log(string.format('认领回读不符（count %s，label 0x%s）-> 浮动面板',
                tostring(count2), lab2 and hex8(lab2) or 'nil'))
        end
    end


    return {
        probe  = menu_probe,
        screen = tab_screen,
        claim  = claim_tab,
        PROBE  = PROBE,
        PLACE  = PLACE,
        OUR_LABEL = OUR_LABEL,
        OUR_TEXT  = OUR_TEXT,
    }
end

return M
