-- HD2 Scanner / aob —— game.dll AOB pair 定位：战备记录指针数组
-- 资源名: mods/junze/hd2_scanner/aob   （不带 -- HD2-Addon 头，不被 loader 单独发现）
--
-- 来源：StratagemCooldown 2.1.5（明文 Lua；逆向笔记见 hd2-mod/NEXT.md 第四节）。
--
-- 为什么：StratagemSettings 在内存里**不是** LDLD 块，旧办法只能全内存搜 package 值
--   （要扫几 GB、几秒）。这里改成在 game.dll 代码段里找一对固定指令，直接解出
--   「战备记录指针数组」的基址，之后按 ID 索引直取记录 —— 解析一次，随时可读。
--
--   49 8B 84 C7 ?? ?? ?? ??   mov rax,[r15+rax*8+disp32]     ← 唯一命中点 consumer
--   44 8B 80 C8 00 00 00      mov r8d,[rax+0xC8]
--   8B C2 45 85 C0            mov eax,edx / test r8d,r8d
--
-- 链：① 代码段里找上面这对字节，要求**唯一**命中（多命中 = 放弃，不猜）
--     ② disp = i32 @ consumer+4
--     ③ 往 consumer 前 0x1000 字节倒找 `4C 8D 3D`（lea r15,[rip+disp32]），
--        且要求它指向映像首 1MB（全局变量区）
--     ④ table_base = r15_base + disp
--     ⑤ slot_ptr(id) = u64 @ table_base + id*8 ，记录 = read(slot_ptr(id), n)
--
-- 红线：本文件**只读**。全程 ReadProcessMemory，坏地址返回 nil，不写任何游戏内存。
--       任何一步不成立就置 failed 并给出原因 —— 消费者据此回退旧的全内存搜。
--
-- 测试钩子：_G.HD2_AOB_TEST = { sections = { {base=..., size=...} } } 时跳过 PE 解析，
--   直接拿它当代码段（离线测试用合成映像；见 test/test_load.py）。
local M = {}

function M.new(ctx)
    local log = ctx.log
    local U = ctx.platform
    local ffi = U.ffi
    if not (ffi and U.GAME and U.game_open and U.mem_read) then return nil end
    local mem_read = U.mem_read
    local s_u32, s_u64, hex8 = U.s_u32, U.s_u64, U.hex8

    -- ---------------------------------------------------------------- 常量
    local MIN_PTR, MAX_PTR = 0x10000, 0x00007FFFFFFFFFFF
    local function sane_ptr(v)
        if type(v) ~= 'number' then return false end
        if v < MIN_PTR or v > MAX_PTR then return false end
        return v == math.floor(v)
    end
    local function i32_of(s, o)
        local v = s_u32(s, o)
        if v >= 2147483648 then v = v - 4294967296 end
        return v
    end

    -- 期望签名（StratagemCooldown 2.1.5 locate_table）
    local SIG_TEXT = '49 8B 84 C7 ?? ?? ?? ?? 44 8B 80 C8 00 00 00 8B C2 45 85 C0'
    local S1       = string.char(0x49, 0x8B, 0x84, 0xC7)
    local S2       = string.char(0x44, 0x8B, 0x80, 0xC8, 0x00, 0x00, 0x00,
                                 0x8B, 0xC2, 0x45, 0x85, 0xC0)
    local LEA_R15  = string.char(0x4C, 0x8D, 0x3D)
    local DISP_AT  = 4                      -- disp32 紧跟 S1：consumer+4
    local ANCHOR_WIN, ANCHOR_NEAR = 0x1000, 0x100000

    local SLOT_MAX = 255                    -- 指针数组上界（与参考实现一致）
    local REC_READ = 0xD0                   -- 覆盖 use(0x50) / package(0xA8) / icon(0xB0) / additional(0xC8)
    local CHUNK    = 1024 * 1024
    local OVERLAP  = 0x40
    local BUDGET   = 2 * 1024 * 1024        -- 每帧字节预算：33 MB 代码段 ≈ 17 帧

    local O = {
        state = 'idle', reason = nil,
        base = nil, r15 = nil, consumer = nil, disp = nil, image_base = nil,
        scanned = 0, total = 0, sections = 0, frames = 0, ms = 0, t0 = 0,
        slots = 0, slots_ok = 0, at = nil, hits = {},
    }

    -- ---------------------------------------------------------------- ① PE 代码段
    -- 直接读映像头（模块一定是 mapped 的）。返回 { {base, size}, ... }。
    local function pe_code_sections(image_base)
        local dos = mem_read(image_base, 0x1000)
        if not dos or dos:sub(1, 2) ~= 'MZ' then return nil, 'bad DOS header' end
        local peoff = s_u32(dos, 0x3C)
        if peoff <= 0 or peoff > 0x1000 then return nil, 'bad e_lfanew' end
        local hdr = mem_read(image_base + peoff, 0x1000)
        if not hdr or hdr:sub(1, 4) ~= 'PE\0\0' then return nil, 'bad PE header' end
        local nsec    = hdr:byte(7) + hdr:byte(8) * 256
        local optsize = hdr:byte(21) + hdr:byte(22) * 256
        local out = {}
        for i = 0, nsec - 1 do
            local o = 24 + optsize + 40 * i
            if o + 40 > #hdr then break end
            local vsize = s_u32(hdr, o + 8)
            local vaddr = s_u32(hdr, o + 12)
            local chars = s_u32(hdr, o + 36)
            if vsize > 0 and math.floor(chars / 0x20000000) % 2 == 1 then   -- IMAGE_SCN_MEM_EXECUTE
                out[#out + 1] = { base = image_base + vaddr, size = vsize }
            end
        end
        if #out == 0 then return nil, 'no executable section' end
        return out
    end

    local function code_sections()
        local test = rawget(_G, 'HD2_AOB_TEST')
        if type(test) == 'table' and type(test.sections) == 'table' then
            return test.sections, test.base or (test.sections[1] and test.sections[1].base)
        end
        if not U.game_open() then return nil, nil, 'game.dll not loaded' end
        local secs, why = pe_code_sections(U.GAME.base)
        if not secs then return nil, nil, why end
        return secs, U.GAME.base
    end

    -- ---------------------------------------------------------------- ② 开始一轮
    local function start()
        O.hits, O.scanned, O.frames, O.ms = {}, 0, 0, 0
        O.base, O.r15, O.consumer, O.disp = nil, nil, nil, nil
        O.slots, O.slots_ok = 0, 0
        O.reason, O.at = nil, nil
        local secs, image_base, why = code_sections()
        if not secs then
            O.state, O.reason = 'failed', tostring(why)
            log('aob: 失败：' .. O.reason)
            return false, O.reason
        end
        O.queue = secs
        O.image_base = image_base or secs[1].base
        O.sections = #secs
        O.total = 0
        for i = 1, #secs do
            O.total = O.total + (tonumber(secs[i].size) or 0)
        end
        O.qi, O.off, O.carry = 1, 0, ''
        O.t0 = os.clock()
        O.state = 'scanning'
        log(string.format('aob: 开始扫代码段 %d 段 / %.1f MB  sig=%s',
            #secs, O.total / 1048576, SIG_TEXT))
        return true
    end

    -- ---------------------------------------------------------------- ③ 解析（扫完后的纯计算）
    local function i32_at(addr)
        local b = mem_read(addr, 4)
        if not b then return nil end
        return i32_of(b, 0)
    end

    local function resolve()
        local hits = O.hits
        O.ms = (os.clock() - O.t0) * 1000
        if #hits ~= 1 then
            O.state  = 'failed'
            O.reason = string.format('AOB 命中 %d 个（要求唯一）', #hits)
            log('aob: 失败：' .. O.reason)
            return
        end
        local consumer = hits[1]
        O.consumer = consumer
        local disp = i32_at(consumer + DISP_AT)
        if not disp then
            O.state, O.reason = 'failed', 'disp32 读不出来'
            log('aob: 失败：' .. O.reason)
            return
        end
        O.disp = disp
        -- 往前倒找 lea r15,[rip+disp32]（从 consumer 往回，取最近的一处）
        local back_from = math.max(O.image_base, consumer - ANCHOR_WIN)
        local back = mem_read(back_from, consumer - back_from)
        local r15_base
        if back then
            for i = #back - 6, 1, -1 do
                if back:sub(i, i + 2) == LEA_R15 then
                    local ds    = i32_of(back, i + 2)
                    local at    = back_from + i - 1
                    local target = at + 7 + ds
                    if target >= O.image_base and target < O.image_base + ANCHOR_NEAR then
                        r15_base = target
                        break
                    end
                end
            end
        end
        if not r15_base then
            O.state, O.reason = 'failed', 'lea r15 锚点没找到'
            log('aob: 失败：' .. O.reason)
            return
        end
        O.r15 = r15_base
        local base = r15_base + disp
        if not sane_ptr(base) then
            O.state, O.reason = 'failed', 'table_base 不在合理地址范围'
            log(string.format('aob: 失败：%s（base=0x%X）', O.reason, base))
            return
        end
        -- 结构探针：前 256 个槽位里至少要有可读指针，否则说明解出来的不是指针数组
        local raw = mem_read(base, (SLOT_MAX + 1) * 8)
        if not raw then
            O.state, O.reason = 'failed', 'table_base 不可读'
            log('aob: 失败：' .. O.reason)
            return
        end
        local okn = 0
        for id = 0, SLOT_MAX do
            if sane_ptr(s_u64(raw, id * 8)) then okn = okn + 1 end
        end
        O.slots, O.slots_ok = SLOT_MAX + 1, okn
        if okn == 0 then
            O.state, O.reason = 'failed', '槽位指针全不可读（结构校验不过）'
            log('aob: 失败：' .. O.reason)
            return
        end
        O.base  = base
        O.state = 'ok'
        O.at    = os.clock()
        log(string.format(
            'aob: 战备表已定位 base=0x%X  consumer=0x%X  r15=0x%X  disp=0x%X  槽位 %d/%d 可读  %.0f ms',
            base, consumer, r15_base, disp, okn, SLOT_MAX + 1, O.ms))
    end

    -- ---------------------------------------------------------------- ④ 分帧推进
    local function step()
        local budget = BUDGET
        O.frames = O.frames + 1
        while budget > 0 and O.qi <= #O.queue do
            local sec = O.queue[O.qi]
            if O.off >= sec.size then
                O.qi, O.off, O.carry = O.qi + 1, 0, ''
            else
                local n    = math.min(CHUNK, sec.size - O.off)
                local data = mem_read(sec.base + O.off, n)
                if data then
                    local w  = O.carry .. data
                    local wb = sec.base + O.off - #O.carry
                    local from = 1
                    while true do
                        local p = w:find(S1, from, true)
                        if not p then break end
                        from = p + 1
                        -- S1 4 字节 + disp32 4 字节 ⇒ S2 从 p+8 开始
                        if p + (#S1 + DISP_AT) + #S2 - 1 <= #w
                           and w:sub(p + #S1 + DISP_AT, p + #S1 + DISP_AT + #S2 - 1) == S2 then
                            local a, dup = wb + p - 1, false
                            for i = 1, #O.hits do
                                if O.hits[i] == a then dup = true break end
                            end
                            if not dup then O.hits[#O.hits + 1] = a end
                            if #O.hits > 1 then          -- 已经不唯一，没必要扫完
                                O.scanned = O.scanned + n
                                O.state, O.reason = 'failed', 'AOB 命中不唯一'
                                log(string.format('aob: 失败：%s（>=2 个：0x%X 0x%X）',
                                    O.reason, O.hits[1], O.hits[2]))
                                return
                            end
                        end
                    end
                    O.carry = data:sub(-OVERLAP)
                    O.scanned = O.scanned + n
                else
                    O.carry = ''
                end
                O.off = O.off + n
                budget = budget - n
            end
        end
        if O.qi > #O.queue then resolve() end
    end

    -- ---------------------------------------------------------------- ⑤ 对外 API
    local API = {}
    API.sig = SIG_TEXT

    API.frame = function()
        if O.state == 'scanning' then step() end
    end

    API.request = function()
        if O.state == 'scanning' then return true end
        if O.state == 'ok'      then return true end
        return start()                      -- failed 之后再调 = 重新来一遍
    end

    API.status = function()
        return {
            state = O.state, reason = O.reason, base = O.base,
            r15 = O.r15, consumer = O.consumer, disp = O.disp,
            scanned = O.scanned, total = O.total, sections = O.sections,
            frames = O.frames, ms = O.ms, at = O.at,
            slots = O.slots, slots_ok = O.slots_ok,
            sig = SIG_TEXT, slot_max = SLOT_MAX, rec_read = REC_READ,
            budget = BUDGET,
        }
    end

    API.base = function() return O.base end

    API.slot = function(id)
        if O.state ~= 'ok' then return nil, O.reason or ('状态 ' .. tostring(O.state)) end
        id = tonumber(id)
        if not id or id ~= math.floor(id) or id < 0 or id > SLOT_MAX then
            return nil, 'id 越界（0..' .. SLOT_MAX .. '）'
        end
        local b = mem_read(O.base + id * 8, 8)
        if not b then return nil, 'slot 读不出来' end
        local p = s_u64(b, 0)
        if not sane_ptr(p) then return nil, 'slot 指针不像堆地址' end
        return p
    end

    API.rec = function(id, n)
        n = tonumber(n) or REC_READ
        if n ~= math.floor(n) or n < 1 or n > 0x100 then return nil, '长度越界（1..256）' end
        local p, why = API.slot(id)
        if not p then return nil, why end
        local b = mem_read(p, n)
        if not b then return nil, '记录读不出来' end
        return b
    end

    return API
end

return M