-- HD2 Scanner / kernel —— 扫描内核（**阶段 1**）
-- 资源名: mods/junze/hd2_scanner/kernel      （不带 -- HD2-Addon 头，不被 loader 单独发现）
--
-- 设计: docs/SCANNER-设计定稿.md  §4 状态机 / §5 定位算法 / §6 API / §7.2 declare_need
--
-- 阶段 1 范围（刻意做小）:
--   ✅ 偏移直读（每个区段**先探 1 次**标志位，命中才读那 5 个偏移 —— 不抄那个 ×6 的笨探针）
--   ✅ 广播 + 失效检测
--   ✅ next_at + urgent（落实 §7.2 的 declare_need 同步刷新）
--   ❌ **不做 HUNT**（落空只记日志）。理由：阶段 1 不接消费者，退化路径没人用，
--      内核小一半、风险小一半。等阶段 2 再补。
--
-- 红线: 本文件**只读**。没有 WriteProcessMemory / VirtualProtect。
local M = {}

-- 实测常量（定稿 §10，来源：MissionProbe v4 三次会话）
--   组件表 7 张**同住一个区段**，固定偏移
local COMPONENT = {
    { off = 0x8111C,   hash = 0xFB8D88A3, size = 52000, name = 'WeaponMagazineComponentData' },
    { off = 0x5DDC5C,  hash = 0xA98BB156, size = 42568, name = 'HellpodRackComponentData'    },
    { off = 0x6F0A0C,  hash = 0xDDB5C03F, size = 5072,  name = 'HellpodPayloadComponentData' },
    { off = 0x1A0622C, hash = 0x1EBA7593, size = 7960,  name = 'TurretComponentData'         },
    { off = 0x1C6A3FC, hash = 0x3845B1E0, size = 24744, name = 'MountComponentData'          },
    -- v0.8.2 新增：武器的弹道组件（projectile_type 在记录 +0）。装甲车线的 40mm 弹种切换用它。
    { off = 0x2C414EC, hash = 0x45171B68, size = 176224, name = 'ProjectileWeaponComponentData' },
    -- v0.8.3 新增：武器的「开火模式/功能」组件（function_info @ 记录 +168，内存记录长 1232 B）。
    --            ⚠ 目前**还没有消费者**：「游戏内可编程弹药切换」在装甲车辆线已回退，
    --              这里只是先把表广播出来备用（要用时别再重新挖偏移）。
    { off = 0x18F0AEC, hash = 0x88E4DBB1, size = 462592, name = 'WeaponDataComponentData' },
}
-- 探针：先读第 1 张的偏移，若「LDLD + 哈希」对上 ⇒ 这个区段就是组件区段
local GATE = { off = COMPONENT[1].off, hash = COMPONENT[1].hash }

--   常驻表：各自独占一个区段，表在区段 +0x4；⚠ +0x4 假阳性多，**必须比对类型哈希**
local STANDALONE = {
    { off = 0x4, hash = 0xBD4042C2, size = 95216, name = 'ProjectileSettings' },
    { off = 0x4, hash = 0x2AEA2592, size = 67800, name = 'ExplosionSettings'  },
}

local NAME = {}
for _, e in ipairs(COMPONENT)  do NAME[e.hash] = e.name end
for _, e in ipairs(STANDALONE) do NAME[e.hash] = e.name end

local LIMIT      = 0x0000800000000000   -- 用户态地址上限
local INTERVAL   = 30      -- 秒（定稿 §4）
local WARMUP   = 5       -- 秒：别和开机的签名解析（104 ms）挤在同一帧

function M.new(ctx)
    local P, log = ctx.P, ctx.log
    local U = ctx.platform
    local ffi, kernel, PROC = U.ffi, U.kernel, U.PROC

    local K = {
        state = 'IDLE', rounds = 0, found = 0, regions = 0, reads = 0,
        ms = 0, last_at = nil, interval = INTERVAL, urgent = false,
        next_at = os.clock() + WARMUP, lost = 0, notes = {},
    }

    -- ---------------------------------------------------------------- 平台
    if ffi then pcall(ffi.cdef, [[
        size_t VirtualQuery(const void *address, void *mbi, size_t len);
    ]]) end
    local mbi = (ffi and kernel) and ffi.new('uint8_t[48]') or nil
    local RB  = (ffi and kernel) and ffi.new('uint8_t[16]') or nil
    local RG  = (ffi and kernel) and ffi.new('size_t[1]')   or nil

    -- 复用 16 字节缓冲：一次探针要发上万次读，不能每次 ffi.new（定稿 §2.2 的 117 ms 主要就是"次数税"）
    local function rd16(addr)
        if not (RB and kernel and PROC) or not addr or addr <= 0 then return nil end
        RG[0] = 0
        local ok = pcall(kernel.ReadProcessMemory, PROC,
                         ffi.cast('const void *', addr), RB, 16, RG)
        if ok and tonumber(RG[0]) == 16 then return RB end
        return nil
    end
    -- ⚠ 只读，永远不写。读无效地址只会失败，不会崩（这就是用 ReadProcessMemory 而不是裸指针的原因）
    local function is_ldld(b)
        return b ~= nil and b[0] == 0x4C and b[1] == 0x44 and b[2] == 0x4C and b[3] == 0x44
    end
    local function u32at(b, o)
        return b[o] + b[o+1]*256 + b[o+2]*65536 + b[o+3]*16777216
    end

    -- ---------------------------------------------------------------- 分片探针
    -- 实机实测（2026-10-02）：14,062 区段 / 28,129 次读 / 共 93 ms（≈3.3 µs/次）。
    -- 一轮要做 3 个阶段 ⇒ 约 42,000 个"条目"（枚举 1 条 + 组件门 1 条 + 独立表 1 条）。
    --
    -- ⚠ 用"条数"而不是"时间预算"分片：os.clock() 在 Windows 只有 1 ms 精度，
    --    实测确认极短切片会被量化成 0，量不了 0.2 ms 级的切片。
    --
    -- 每帧条数 = 一盘摊薄的速度。两条约束:
    --   ① 单帧开销 = step × ≈3.3 µs，要远低于一帧预算（16.67 ms @60fps）；
    --   ② 一轮总时长 = 3×区段数 ÷ step ÷ 60 秒，必须**显著小于** INTERVAL。
    --      中间那段空档不是浪费，它是 urgent 的插队窗口 + 掉帧的超支缓冲
    --      （urgent 只在轮次**之间**被消费：见 API.frame 里的 `if SH.active then return`）。
    --
    -- 42,000 ÷ 70 ≈ 600 帧 ≈ 10 s @60fps ⇒ 0.23 ms/帧（一帧预算的 1.4%），空档留 20 s。
    -- ⚠ 别把 step 压到 47 以下（轮长 >15 s，urgent 可插的空档就不到一半）；
    --   ≈24 是硬临界（轮长 29 s ≈ INTERVAL，next_at 永远过期，扫描再也不歇脚）。
    local SHARD_STEP        = 70
    local SHARD_URGENT_STEP = 1400        -- urgent 时快 20 倍：0.5 秒扫完（战备落地前够用）

    local SH = { active = false, phase = nil, regions = nil, i = 0, cursor = 0,
                 guard = 0, found = nil, reads = 0, t0 = 0, cpu = 0,
                 urgent = false, frames = 0 }

    -- 一次 VirtualQuery；返回 base,size,readable；结束/失败返回 nil
    local function vq(cursor)
        if not (ffi and kernel and mbi) then return nil end
        if kernel.VirtualQuery(ffi.cast('const void *', cursor), mbi, 48) == 0 then return nil end
        local base = tonumber(ffi.cast('uint64_t *', mbi)[0])
        local size = tonumber(ffi.cast('uint64_t *', mbi)[3])
        local state = tonumber(ffi.cast('uint32_t *', mbi + 32)[0])
        local prot  = tonumber(ffi.cast('uint32_t *', mbi + 36)[0])
        if size == 0 then return nil end
        local readable = (prot == 0x02 or prot == 0x04 or prot == 0x20 or prot == 0x40)
        return base, size, (state == 0x1000 and readable)
    end

    -- 一次性枚举（给 API 用；探针本身走下面的分片版）
    local function regions()
        local list, cursor, guard = {}, 0x10000, 0
        while cursor < LIMIT and guard < 200000 do
            guard = guard + 1
            local base, size, ok = vq(cursor)
            if not base then break end
            if ok then list[#list + 1] = { base = base, size = size } end
            cursor = base + size
        end
        return list
    end

    local function probe_begin(urgent)
        SH.active, SH.phase, SH.i = true, 'regions', 0
        SH.reads, SH.found, SH.cpu, SH.frames = 0, {}, 0, 0
        SH.regions, SH.cursor, SH.guard = {}, 0x10000, 0
        SH.urgent, SH.t0 = urgent, os.clock()
    end

    -- 推进一轮。返回 true = 这一轮走完了
    local function probe_step()
        local step = SH.urgent and SHARD_URGENT_STEP or SHARD_STEP
        local n, t0 = 0, os.clock()
        SH.frames = SH.frames + 1

        if SH.phase == 'regions' then
            while n < step and SH.cursor < LIMIT and SH.guard < 200000 do
                SH.guard, n = SH.guard + 1, n + 1
                local base, size, ok = vq(SH.cursor)
                if not base then SH.cursor = LIMIT break end
                if ok then SH.regions[#SH.regions + 1] = { base = base, size = size } end
                SH.cursor = base + size
            end
            if SH.cursor >= LIMIT or SH.guard >= 200000 then SH.phase, SH.i = 'component', 0 end
            SH.cpu = SH.cpu + (os.clock() - t0)
            return false
        end

        local total = #SH.regions

        if SH.phase == 'component' then
            while n < step and SH.i < total do
                SH.i, n = SH.i + 1, n + 1
                local base = SH.regions[SH.i].base
                local g = rd16(base + GATE.off); SH.reads = SH.reads + 1
                if is_ldld(g) and u32at(g, 8) == GATE.hash then
                    for k = 1, #COMPONENT do
                        local e = COMPONENT[k]
                        local h = rd16(base + e.off); SH.reads = SH.reads + 1
                        if is_ldld(h) and u32at(h, 8) == e.hash then
                            SH.found[#SH.found + 1] = { hash = e.hash, addr = base + e.off,
                                                        size = e.size, name = e.name }
                        end
                    end
                end
            end
            if SH.i >= total then SH.phase, SH.i = 'standalone', 0 end
            SH.cpu = SH.cpu + (os.clock() - t0)
            return false
        end

        -- standalone：Projectile / Explosion，+0x4，必须比对类型哈希（假阳性多）
        while n < step and SH.i < total do
            SH.i, n = SH.i + 1, n + 1
            local base = SH.regions[SH.i].base
            local h = rd16(base + 0x4); SH.reads = SH.reads + 1
            if is_ldld(h) then
                local hv = u32at(h, 8)
                for k = 1, #STANDALONE do
                    local e = STANDALONE[k]
                    if hv == e.hash then
                        SH.found[#SH.found + 1] = { hash = e.hash, addr = base + 0x4,
                                                    size = e.size, name = e.name }
                    end
                end
            end
        end
        SH.cpu = SH.cpu + (os.clock() - t0)
        if SH.i >= total then SH.active = false return true end
        return false
    end

    -- ---------------------------------------------------------------- ② 广播
    local PUB = {}                      -- hash -> { entries = {{addr,size}}, generation, name }
    local function addrs_of(list)
        local s = {}
        for i = 1, #list do s[#s + 1] = string.format('0x%X', list[i].addr) end
        return table.concat(s, ' ')
    end

    local function broadcast(found)
        local by = {}
        for i = 1, #found do
            local e = found[i]
            by[e.hash] = by[e.hash] or {}
            by[e.hash][#by[e.hash] + 1] = { addr = e.addr, size = e.size }
        end
        for hash, list in pairs(by) do
            local slot = PUB[hash]
            local same = slot ~= nil and #slot.entries == #list
            if same then
                for i = 1, #list do
                    if slot.entries[i].addr ~= list[i].addr then same = false break end
                end
            end
            if not same then
                local gen = (slot and slot.generation or 0) + 1
                PUB[hash] = { entries = list, generation = gen, name = NAME[hash] or ('0x%X'):format(hash) }
                log(string.format('kernel: 广播 %s  x%d  gen=%d  %s',
                    PUB[hash].name, #list, gen, addrs_of(list)))
            end
        end
        for hash, slot in pairs(PUB) do
            if not by[hash] then
                PUB[hash] = nil
                log(string.format('kernel: 失去 %s（本轮没扫到）', slot.name))
            end
        end
    end

    -- ---------------------------------------------------------------- ③ 失效检测（盯已发布地址的 16B 头）
    local function verify_published()
        for hash, slot in pairs(PUB) do
            local alive, dead = {}, 0
            for i = 1, #slot.entries do
                local e = slot.entries[i]
                local b = rd16(e.addr)
                if is_ldld(b) and u32at(b, 8) == hash then
                    alive[#alive + 1] = e
                else
                    dead = dead + 1
                end
            end
            if dead > 0 then
                K.lost = K.lost + dead
                log(string.format('kernel: %s 掉了 %d 份（剩 %d）', slot.name, dead, #alive))
                if #alive > 0 then
                    slot.entries, slot.generation = alive, slot.generation + 1
                else
                    PUB[hash] = nil
                end
            end
        end
    end

    -- ---------------------------------------------------------------- ④ 对外 API（定稿 §6）
    local SUBS = {}                     -- hash -> {name=...}
    local API = { version = 1 }         -- 定稿 §6

    function API.request(type_hash, name)
        SUBS[type_hash] = { name = name or NAME[type_hash] or ('0x%X'):format(type_hash) }
        return {
            hash = type_hash,
            declare_ok   = function() end,
            declare_need = function() K.urgent = true end,      -- ★ §7.2：立刻同步刷新
            cancel       = function() SUBS[type_hash] = nil end,
        }
    end

    function API.poll(type_hash)
        local slot = PUB[type_hash]
        if not slot then return { entries = {}, generation = 0 } end
        return { entries = slot.entries, generation = slot.generation }
    end

    function API.watch(type_hash, addr)
        local slot = PUB[type_hash]
        if not slot then return false end
        for i = 1, #slot.entries do
            if slot.entries[i].addr == addr then slot.entries[i].watched = true return true end
        end
        return false
    end
    API.unwatch = function(type_hash, addr)
        local slot = PUB[type_hash]
        if not slot then return end
        for i = 1, #slot.entries do
            if slot.entries[i].addr == addr then slot.entries[i].watched = nil end
        end
    end

    -- ★ 不订阅任何表也能催一轮：MOM 的「立刻扫一轮」按钮用它（2026-10-04）
    function API.declare_need() K.urgent = true end
    function API.status() return K end
    function API.published() return PUB end
    function API.read(addr, n) return U.mem_read(addr, n) end
    function API.regions_list() return regions() end
    API.api = { read = function(a, n) return U.mem_read(a, n) end,
                regions = function() return regions() end }

    -- ---------------------------------------------------------------- ⑤ 每帧
    function API.frame()
        -- 正在分片：推进一小片
        if SH.active then
            if probe_step() then
                broadcast(SH.found)
                verify_published()
                K.regions, K.reads, K.found = #SH.regions, SH.reads, #SH.found
                K.ms   = SH.cpu * 1000                       -- 真实 CPU 时间（切片累加）
                K.wall = (os.clock() - SH.t0) * 1000         -- 墙上时间（4 秒那个）
                K.shard_frames = SH.frames
                K.rounds = K.rounds + 1
                K.last_at = os.clock()
                -- 阶段 1 不区分 HUNT：命中就 SETTLE，落空还是 IDLE（只记日志）
                K.state = (K.found > 0) and 'SETTLE' or 'IDLE'
                -- 周期从**本轮开始**算，否则分片会把整体周期拖成 34 秒
                K.next_at = SH.t0 + K.interval
                log(string.format(
                    'kernel: 第 %d 轮%s  %s  区段 %d  读 %d  命中 %d  CPU %.0f ms / 墙上 %.1f s（分 %d 帧）',
                    K.rounds, SH.urgent and '【urgent】' or '', K.state,
                    K.regions, K.reads, K.found, K.ms, K.wall / 1000, K.shard_frames))
            end
            return
        end
        -- 到点（或 urgent）就**开始**一轮；剩下的交给上面的分片
        local now = os.clock()
        if K.urgent or now >= K.next_at then
            local urgent = K.urgent
            K.urgent = false
            probe_begin(urgent)
            K.state = 'PROBING'
        end
    end

    log(string.format('kernel: 就绪（阶段 1，不做 HUNT）；首个探针 %.0f 秒后', WARMUP))
    return API
end

return M