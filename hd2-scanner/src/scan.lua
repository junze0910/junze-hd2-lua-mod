-- HD2 Scanner / scan —— 签名扫描器 + PE + MENU / TAB / FONTS 三个解码器
-- 资源名: mods/junze/hd2_scanner/scan
local M = {}

function M.new(ctx)
    local U = ctx.platform
    local g_u32, g_i32, s_u32, s_u64, hex8 = U.g_u32, U.g_i32, U.s_u32, U.s_u64, U.hex8

    -- ---------------------------------------------------------------------------
    -- 5. 签名扫描器（get(o) 取 0 基 RVA 处的一字节）
    -- ---------------------------------------------------------------------------
    local function parse_sig(text)
        local p = {}
        for tok in text:gmatch('%S+') do
            p[#p+1] = (tok == '??') and -1 or tonumber(tok, 16)
        end
        return p
    end

    local function find_all(get, size, sig, limit)
        local pat = parse_sig(sig)
        local first, n = pat[1], #pat
        local hits = {}
        for i = 0, size - n do
            if get(i) == first then
                local ok = true
                for j = 2, n do
                    local want = pat[j]
                    if want >= 0 and get(i + j - 1) ~= want then ok = false break end
                end
                if ok then
                    hits[#hits + 1] = i
                    if limit and #hits >= limit then break end
                end
            end
        end
        return hits
    end

    local function matches(get, at, sig)
        local i = 0
        for tok in sig:gmatch('%S+') do
            if tok ~= '??' and get(at + i) ~= tonumber(tok, 16) then return false end
            i = i + 1
        end
        return true
    end

    -- ---------------------------------------------------------------------------
    -- 6. PE：找 .text（返回 text_start, text_size, image_size）
    -- ---------------------------------------------------------------------------
    local function text_section(get)
        local pe = g_u32(get, 0x3c)
        if pe <= 0 or pe > 4096 or get(pe) ~= 0x50 or get(pe+1) ~= 0x45 then
            return nil, 'PE header unavailable'
        end
        local nsec     = get(pe+6) + get(pe+7)*256
        local optsize  = get(pe+20) + get(pe+21)*256
        local image_sz = g_u32(get, pe + 24 + 56)
        for i = 0, nsec - 1 do
            local h = pe + 24 + optsize + 40*i
            local chars = g_u32(get, h + 36)
            if math.floor(chars / 0x20000000) % 2 == 1 then          -- IMAGE_SCN_MEM_EXECUTE
                return g_u32(get, h + 12), g_u32(get, h + 8), image_sz
            end
        end
        return nil, 'code section unavailable'
    end

    -- ---------------------------------------------------------------------------
    -- 7. MenuSystem（菜单当前停在哪个 screen）
    -- ---------------------------------------------------------------------------
    local MENU = {}
    MENU.SIG = '40 53 48 83 EC 20 48 8B 1D ?? ?? ?? ?? 8B 03 3B C2 75 ?? 80 BB ?? ?? 00 00 00 74 ?? '
            .. '44 8B C0 48 8D 15 ?? ?? ?? ?? 48 8D 05 ?? ?? ?? ?? 48 8D 0D ?? ?? ?? ?? 4E 8B 04 C0'

    function MENU.decode(get, at)
        local open = g_u32(get, at + 21)
        assert(open > 0 and open < 65536, 'implausible menu open offset')
        return {
            global = at + 13 + g_i32(get, at + 9),
            open   = open,
            hidden = open + 1,
            names  = at + 45 + g_i32(get, at + 41),
        }
    end

    function MENU.resolve(get, text_start, text_size)
        local function rel(i) return get(text_start + i) end
        local hits = find_all(rel, text_size, MENU.SIG, 2)
        -- find_all 的 i 是段内偏移，换算成 RVA
        assert(#hits == 1, 'MenuSystem signature matched ' .. #hits .. ' times')
        local at = text_start + hits[1]
        local layout = MENU.decode(function(i) return get(i) end, at)
        layout.at = at
        return layout
    end

    function MENU.read_names(readmem, base, layout)
        -- ⚠ layout.names 是 RVA，必须加 base！漏了会读到 0 个名字（2026-10-02 的真 bug）
        local names = {}
        for i = 0, 63 do
            local raw = readmem(base + layout.names + 8*i, 8)
            if not raw then break end
            local p = s_u64(raw, 0)
            -- ⚠ 这是**绝对地址**（模块内已重定位），不是 RVA！
            --   写成 p > 0x80000000 会把 0x7FF9xxxxxxxx 这种正常指针全否掉（2026-10-02 的真 bug）
            if p < 0x10000 or p >= 0x0000800000000000 then break end
            local txt = readmem(p, 48)      -- p 是绝对地址（指针值），不加 base
            if not txt then break end
            local z = txt:find('\0', 1, true)
            local nm = z and txt:sub(1, z-1) or txt
            if not nm:match('^[%w_]+$') then break end
            names[i] = nm
            if nm == 'Count' then break end
        end
        return names
    end

    -- ---------------------------------------------------------------------------
    -- 8. ESC 页签（set_labels 那一套）
    -- ---------------------------------------------------------------------------
    local TAB = {}
    TAB.SIG = '49 8D 9F ?? ?? ?? ?? BA ?? ?? 00 00 48 8B CB C6 83 ?? ?? ?? ?? 01 E8 ?? ?? ?? ?? '
           .. '41 B8 03 00 00 00 48 8D 15 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 48 8B D3 '
           .. '41 C7 87 ?? ?? ?? ?? 03 00 00 00 49 8D 4F 10 41 88 B7 ?? ?? ?? ??'
    TAB.SET_LABELS_PROLOGUE = '48 89 54 24 10 53 56 48 83 EC 68 0F 29 74 24 30 48 8B C2 48 89 7C 24 60 '
           .. '48 8B F1 4C 89 6C 24 50 4C 89 7C 24 40 41 BF 08 00 00 00 45 3B C7 45 8B EF 45 0F 4C E8 44 89 A9'
    TAB.LABEL_LOOP     = '8B 1C A8 48 8D 8F ?? ?? ?? ?? 8B D3 E8'
    TAB.SET_LABEL_HEAD = '48 83 EC 28 4C 8B D9 39 91 10 01 00 00'
    TAB.ARG_SIG = '40 53 48 83 EC 20 48 8B D9 48 81 C1 10 01 00 00 E8 ?? ?? ?? ?? 84 C0 74 ?? '
           .. '8B 93 B8 00 00 00 8B C2 83 C8 02 89 83 B8 00 00 00 3B C2 74'
    TAB.ARG_RECORD_HEAD = '48 89 5C 24 18 57 48 83 EC 40 44 0F B6 99 58 01 00 00'
    TAB.STRIDE      = 3400
    TAB.ARG_WINDOW  = 0x4000
    TAB.TEXT_LABEL  = 0x0227B3B0      -- MDL 自己的页签名（我们不要用）
    TAB.TEXT_ARG    = 0x57F3D153

    function TAB.decode(get, at)
        local layout = {
            bar          = g_u32(get, at + 3),
            labels_table = at + 40 + g_i32(get, at + 36),
            set_labels   = at + 48 + g_i32(get, at + 44),
            state        = g_u32(get, at + 54),
            flag         = g_u32(get, at + 69),
        }
        local fn = layout.set_labels
        assert(matches(get, fn, TAB.SET_LABELS_PROLOGUE), 'set-labels prologue changed')
        layout.count   = g_u32(get, fn + 0x38)
        assert(get(fn + 0x4A) == 0x81 and get(fn + 0x4B) == 0xC1, 'labels offset not found')
        layout.labels  = g_u32(get, fn + 0x4C)
        layout.current = layout.count + 4

        local first, stride
        for i = 0, 0x140 do
            if not first and get(fn+i) == 0x48 and get(fn+i+1) == 0x8D and get(fn+i+2) == 0xBE then
                first = g_u32(get, fn + i + 3)
            end
            if not stride and matches(get, fn + i, '48 81 C7 48 0D 00 00') then stride = TAB.STRIDE end
        end
        if not stride then
            for i = 0x140, 0x340 do
                if matches(get, fn + i, '48 81 C7 48 0D 00 00') then stride = TAB.STRIDE break end
            end
        end
        assert(first and stride == TAB.STRIDE, 'tab button layout changed')
        layout.first = first

        for i = 0, 0x1C0 do
            if matches(get, fn + i, TAB.LABEL_LOOP) then
                layout.text      = first + g_i32(get, fn + i + 6)
                layout.set_label = fn + i + 17 + g_i32(get, fn + i + 13)
                break
            end
        end
        assert(layout.text and layout.text > first - TAB.STRIDE and layout.text < first,
               'tab text widget not found')
        assert(matches(get, layout.set_label, TAB.SET_LABEL_HEAD), 'set_label changed')

        assert(layout.state - layout.bar - first == 2012, 'button state offset changed')
        assert(layout.flag - layout.state == 17,          'button flag offset changed')
        assert(layout.count - layout.labels == 128,       'tab arrays changed')
        return layout
    end

    function TAB.find_arg_setter(get, set_label, text_size)
        local hits = find_all(function(i) return get(set_label + i) end,
                              TAB.ARG_WINDOW, TAB.ARG_SIG, 8)
        local picked = {}
        for _, hit in ipairs(hits) do
            local at = set_label + hit
            local callee = at + 21 + g_i32(get, at + 17)
            if hit > 0 and matches(get, callee, TAB.ARG_RECORD_HEAD) then
                picked[#picked + 1] = at
            end
        end
        assert(#picked == 1, 'text argument setter matched ' .. #picked .. ' times')
        return picked[1]
    end

    function TAB.resolve(get, text_start, text_size)
        local function rel(i) return get(text_start + i) end
        local hits = find_all(rel, text_size, TAB.SIG, 2)
        assert(#hits == 1, 'ESC-menu tab signature matched ' .. #hits .. ' times')
        local at = text_start + hits[1]
        local layout = TAB.decode(get, at)
        layout.at = at
        layout.expected = {}
        for i = 0, 2 do layout.expected[i] = g_u32(get, layout.labels_table + 4*i) end
        local ok, setter = pcall(TAB.find_arg_setter, get, layout.set_label, text_size)
        if ok then layout.set_arg = setter else layout.arg_problem = tostring(setter) end
        return layout
    end

    -- ---------------------------------------------------------------------------
    -- 9. 字体（浮动面板画真字用）
    -- ---------------------------------------------------------------------------
    local FONTS = {}
    FONTS.SIG = '48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 48 89 7C 24 20 41 54 41 56 41 57 '
            .. '0F 57 C0 8B C1 0F 57 C9 4C 8D 25 ?? ?? ?? ?? 33 DB 0F 11 05 ?? ?? ?? ?? '
            .. '48 8D 3C C5 00 00 00 00 33 C0 4E 8B 94 27'

    function FONTS.decode(get, at)
        local function marker(o)
            return get(o) == 0x4B and get(o+1) == 0x89 and get(o+2) == 0x84 and get(o+3) == 0x21
        end
        assert(at + 0x29 + g_i32(get, at + 0x25) == 0, 'initializer does not address the image base')
        assert(marker(at + 0x25e) and marker(at + 0x268), 'font table stores not found')
        local font, atlas = g_u32(get, at + 0x262), g_u32(get, at + 0x26c)
        assert(atlas > font and atlas - font < 0x2000, 'unexpected font/atlas layout')
        local material_table = at + 0x32 + g_i32(get, at + 0x2e)
        return { font = font, atlas = atlas, material = material_table + 8 }
    end

    function FONTS.resolve(get, text_start, text_size)
        local function rel(i) return get(text_start + i) end
        local hits = find_all(rel, text_size, FONTS.SIG, 2)
        assert(#hits == 1, 'font initializer signature matched ' .. #hits .. ' times')
        local at = text_start + hits[1]
        local slots = FONTS.decode(get, at)
        slots.at = at
        return slots
    end

    local function idstring_hex(raw)
        if not raw or #raw ~= 8 then return nil end
        local v = string.format('%08x%08x', s_u32(raw, 4), s_u32(raw, 0))
        if v == '0000000000000000' then return nil end
        return v
    end

    function FONTS.read(readmem, base, slots)
        local font     = idstring_hex(readmem(base + slots.font, 8))
        local atlas    = idstring_hex(readmem(base + slots.atlas, 8))
        local ptr_raw  = readmem(base + slots.material, 8)
        if not (font and atlas and ptr_raw) then return nil, 'font/atlas/material slot unreadable' end
        local p = s_u64(ptr_raw, 0)
        if p < 0x10000 or p >= 0x0000800000000000 then return nil, 'material pointer implausible' end
        local material = idstring_hex(readmem(p + 24, 8))
        if not material then return nil, 'material name unreadable' end
        return { font = font, atlas = atlas, material = material }
    end


    return {
        parse_sig = parse_sig, find_all = find_all, matches = matches,
        text_section = text_section,
        MENU = MENU, TAB = TAB, FONTS = FONTS, idstring_hex = idstring_hex,
    }
end

return M
