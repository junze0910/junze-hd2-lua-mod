-- HD2-Addon: mods/dsh/balanced_exosuit_emancipator

-- ===========================================================================
--  更均衡的爱国者/解放者外骨骼 · 携带解放者版（外骨骼三件套 v1.0）
--
--  ① MountComponentData · combat_walker_obsidian（EXO-49 解放者）
--       槽1（右臂）  原 18417602992972518459（右臂加农炮） → 645713022044093730（爱国者加特林炮塔）
--  ② MountComponentData · combat_walker（EXO-45 爱国者）
--       槽0（左臂）  原 9388736439472594613（导弹发射器）  → 16570517418531528145（左臂加农炮）
--  ③ StratagemSettings · 解放者外骨骼（StratagemType_EmancipatorExosuit） 的召唤战备
--       additional_stratagem（"战备附加"槽） 0 → 26（= StratagemType_PatriotExosuit）
--       即：**需携带解放者** —— 召唤解放者时额外附带爱国者（26 号战备）
--
--  ⚠⚠ 与同系列的另一个版本（携带爱国者版）**二选一**：两条记录同时被写成非 0 会形成"战备套娃"（互相附加）
--      并在载具/战备列表生成时崩溃。本 mod 因此带运行时保护：扫到"对向记录"的附加槽
--      已经非 0 就整体拒写（fail-open —— 扫不到对向记录时照常工作）。
--
--  定位思路：
--   · 挂载：索引区 (u64 实体哈希 → u32 recIdx) 直接定位记录；再逐个槽位复核
--     （槽位 node 必须对得上、当前 item 必须是原值或目标值），不合格只记日志。
--   · 战备：**直接搜 package 值**（16658039432250907403 = packages/generated/loadout/combat_walker_obsidian），
--     命中点 = 记录内 package 字段；再校验 +8 处的 icon（14746049704219804392）确认布局；
--     目标字段 = 命中点 + 32（additional_stratagem），并要求两侧 depends_on(+28) /
--     max_in_loadout(+36) 都是 0。完全不依赖飞鹰系、不依赖任何统计特征。
--
--  ⚠ 时序：MountComponentData 是**生成载具时读一次**的静态配置 —— 要在召唤前打好；
--     本 mod 在舰船上只做便宜采样，进任务后转"全量+抢时间"扫描，打完会在日志打印
--     `已就绪`。（战备表只在任务里加载，同理。）
--  ⚠ 附带条目会继承父战备的家族机制（本例都在载具家族内，风险低）。
-- ===========================================================================-- ===========================================================================

local MOD = 'mods/dsh/balanced_exosuit_emancipator'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, phase = 'scanning', writes = 0, refusals = 0, errs = 0, rounds = 0, empty_rounds = 0 })
local state = rawget(_G, MOD)
state.slots  = {}
state.tables = {}
state.seen   = {}
state.priority = {}   -- 探测期发现"有表"的地址 → 全量扫描优先扫这些区域
state.pkg_hits = {}  -- 命中目标 package 的地址（= 该记录 package 字段）
state.counter_hits = {}  -- 命中"对向版 mod"package 的地址（只用于二选一检测）
state.ready  = false

local function hex_be(h) local t = {} for i = 1, #h, 2 do t[#t + 1] = string.char(tonumber(h:sub(i, i+1), 16)) end return table.concat(t) end
local function hex_le(h) local t = {} for i = #h-1, 1, -2 do t[#t + 1] = string.char(tonumber(h:sub(i, i+1), 16)) end return table.concat(t) end
local function decode32(b, o) local a, c, d, e = b:byte(o+1, o+4); return a + c*256 + d*65536 + e*16777216 end
local function decode64(b, o) return decode32(b, o) + decode32(b, o+4) * 4294967296 end
local function hex(b) if not b then return '(nil)' end return (b:gsub('.', function(c) return string.format('%02X', c:byte()) end)) end
local function u8(b, o) return b:byte(o+1) end
local function u32le(b, o) return decode32(b, o) end

-- ---------------------------------------------------------------- 目标（常量）
local ATTACH_VALUE   = 26        -- ★ 战备附加写入值（本版本 = StratagemType_PatriotExosuit）
local ATTACH_EXPECT  = 48        -- 飞鹰系在 additional_stratagem 上的值（本版本 EagleRearm）：用于标定校验
local DRY_RUN        = false     -- true = 只标定/打印，不写入

local MAGIC          = 'LDLD'
local TYPE_RACK      = 0x3845B1E0   -- MountComponentData
local TYPE_STRAT     = 0x30EB789E   -- StratagemSettings
local DATA_OFF       = 24
local MIN_SIZE       = 1024
local MAX_SIZE       = 4194304
local DATA_CAP       = 262144

-- 挂载记录：1172 字节？不，MountComponentData 记录 = 120 字节 / 5 槽 × 24 字节
local RACK_SR        = 120
local RACK_SLOT_SR   = 24
-- 目标 A：combat_walker_obsidian 槽1
local RACK_A_ENTITY  = hex_le('C2D449ECF7FACAB1')   -- 14038927220542196401
local RACK_A_SLOT    = 1
local RACK_A_EXPECT  = hex_le('FF9878576A4C543B')   -- 18417602992972518459（右臂加农炮）
local RACK_A_NODE    = hex_be('10E6D361')           -- 1641276944
local RACK_A_WANT    = hex_le('08F6089289C83D22')   -- 645713022044093730（爱国者加特林炮塔）
-- 目标 B：combat_walker 槽0
local RACK_B_ENTITY  = hex_le('79E4B3D2DA5E45E3')   -- 8783342891467425251
local RACK_B_SLOT    = 0
local RACK_B_EXPECT  = hex_le('824B7E0C4C879EB5')   -- 9388736439472594613（导弹发射器）
local RACK_B_NODE    = hex_be('6D13CD43')           -- 1137513325
local RACK_B_WANT    = hex_le('E5F64DCC3BFE9DD1')   -- 16570517418531528145（左臂加农炮）

-- 战备记录指纹
local STRAT_REC_SIZE = 400
local WALKER_PAYLOAD = hex_le('C2D449ECF7FACAB1')   -- 载具实体 14038927220542196401（同 RACK_A_ENTITY 的字节序）
local WALKER_PACKAGE = hex_le('E72D3E9B05C3DB0B')   -- 16658039432250907403 packages/generated/loadout/combat_walker_obsidian
local EAGLE_PAYLOADS = {
  hex_le('2EA01CB1676ACA29'),   -- EagleAirstrike
  hex_le('E44B691DC039A505'),   -- Eagle 500kg
  hex_le('397792815583DA29'),   -- Eagle 110mm Rocket
  hex_le('27BB558C893383CC'),   -- Eagle Napalm
  hex_le('1B3BCADABC7EF8D6'),   -- Eagle Smoke
  hex_le('23A60681DD4383EC'),   -- Eagle Strafe / eagle_base
  hex_le('DFBB9A0D8FA27D85'),  -- Eagle Missile / A2A（备选）
}
-- 战备 payload[1] 固定是鹈鹕运输机：用"实体 + 鹈鹕"这对内容直接定位记录（该表在内存里不是 LDLD 块）
local SHUTTLE_PAYLOAD = hex_le('75BE82ED8592A6B3')   -- 8484362704672433843 鹈鹕运输机
-- 战备记录布局（RawData v1.007.000 + typelib 成员逐一对齐；自带偏移锚点 0x5C/0x88/0x188 全部验证通过）：
--   +4 id / +168 package / +176 icon / +196 depends_on / +200 additional_stratagem / +204 max_in_loadout
-- 目标字段 = package 字段地址 + 32
local ICON_WALKER     = hex_le('CCA47E13FC4682E8')   -- 14746049704219804392 icon（对向版用 COUNTER_*）
local STRAT_ADD_OFF   = 32                            -- additional_stratagem 相对 package 的偏移
local STRAT_NEI_A     = 28                            -- depends_on（应为 0）
local STRAT_NEI_B     = 36                            -- max_in_loadout（应为 0）
local ZERO4           = string.char(0, 0, 0, 0)
-- 对向版 mod 的目标记录（用于二选一检测；写的是另一条记录，两个都写会套娃崩溃）
local COUNTER_PACKAGE = hex_le('22749A294788AF66')   -- 2482778796672462694 packages/generated/loadout/combat_walker
local COUNTER_ICON    = hex_le('396ECA60A6E80E17')   -- 4138467624065961495 icon
local WALKER_PAIR     = WALKER_PAYLOAD .. SHUTTLE_PAYLOAD
local EAGLE_PAIRS     = {}
for _, p in ipairs(EAGLE_PAYLOADS) do EAGLE_PAIRS[#EAGLE_PAIRS + 1] = p .. SHUTTLE_PAYLOAD end

local SIG_STRAT = MAGIC .. string.char(1, 0, 0, 0) .. hex_le('30EB789E')   -- StratagemSettings
local SIG_RACK  = MAGIC .. string.char(1, 0, 0, 0) .. hex_le('3845B1E0')   -- MountComponentData
local SELF_PATTERNS = { MAGIC, SIG_STRAT, SIG_RACK, RACK_A_EXPECT, RACK_A_WANT, RACK_B_EXPECT, RACK_B_WANT,
                        WALKER_PAYLOAD, WALKER_PACKAGE, SHUTTLE_PAYLOAD, WALKER_PAIR }
for _, p in ipairs(EAGLE_PAIRS) do SELF_PATTERNS[#SELF_PATTERNS + 1] = p end

-- 环境信息（loader 版本/API），后面赋值
local ENV = { api = nil, version = nil, source = 'n/a' }

-- 扫描/维护节奏（write_status 与扫描驱动都要用，必须在这里声明）
local SCAN_CHUNK, SCAN_OVERLAP, SCAN_BUDGET, SCAN_BUDGET_HURRY = 256 * 1024, 2048, 0.002, 0.016
local PROBE_REGIONS, PROBE_CAP, PROBE_WAIT, PROBE_FAIL_LIMIT = 12, 8 * 1024 * 1024, 120, 40
local MAINTAIN_FRAMES, FULL_RESCAN_FRAMES = 900, 10800
local BACKOFF, MAX_EMPTY = { 2, 2, 4, 4, 8, 15, 30, 60 }, 8

-- ---------------------------------------------------------------- 日志
local loghist = {}
local function dump(name, text)
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local f = loader and loader.open_log and loader.open_log(name)
    if f then f:write(text); f:close() end
  end)
end
local function flush_log()
  if #loghist == 0 then return end
  dump('BalancedExosuitEmancipator.log', table.concat(loghist, '\n') .. '\n')
end
local function report(message, keep)
  if not keep and state.status == message then return end
  state.status = message
  print('[WalkerLoadout] ' .. message)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, message)
  flush_log()
end

-- ---------------------------------------------------------------- ffi / bit
local ffi_ok, ffi = pcall(require, 'ffi')
local bit_ok, bit = pcall(require, 'bit')
local ok, api = pcall(function()
  assert(ffi_ok and ffi, 'ffi unavailable'); assert(bit_ok and bit, 'bit unavailable'); assert(ffi.abi('64bit'), 'x64 required')
  ffi.cdef [[
    typedef struct { uintptr_t BaseAddress; uintptr_t AllocationBase; uint32_t AllocationProtect; uint32_t PartitionId;
      size_t RegionSize; uint32_t State; uint32_t Protect; uint32_t Type; } WL_MBI;
    void *GetCurrentProcess(void);
    int ReadProcessMemory(void *p, const void *a, void *b, size_t s, size_t *r);
    int WriteProcessMemory(void *p, void *a, const void *b, size_t s, size_t *w);
    int VirtualProtect(void *a, size_t s, uint32_t n, uint32_t *o);
    size_t VirtualQuery(const void *a, WL_MBI *i, size_t l);
  ]]
  local k = ffi.load('kernel32'); local proc = k.GetCurrentProcess(); local api = {}
  function api.read(a, n)
    local b, c = ffi.new('uint8_t[?]', n), ffi.new('size_t[1]')
    if k.ReadProcessMemory(proc, ffi.cast('const void *', a), b, n, c) == 0 then return nil end
    if tonumber(c[0]) ~= n then return nil end
    return ffi.string(b, n)
  end
  function api.write(a, s)
    local c = ffi.new('size_t[1]')
    if k.WriteProcessMemory(proc, ffi.cast('void *', a), ffi.cast('const void *', s), #s, c) == 0 then return false end
    return tonumber(c[0]) == #s
  end
  function api.unprotect(a, n) local o = ffi.new('uint32_t[1]'); if k.VirtualProtect(ffi.cast('void *', a), n, 0x40, o) == 0 then return nil end return tonumber(o[0]) end
  function api.reprotect(a, n, v) local o = ffi.new('uint32_t[1]'); k.VirtualProtect(ffi.cast('void *', a), n, v, o) end
  function api.regions()
    local i = ffi.new('WL_MBI[1]'); local a, out = 0, {}
    while a < 0x7FFFFFFFFFFF do
      if k.VirtualQuery(ffi.cast('const void *', a), i, ffi.sizeof(i)) == 0 then break end
      local base, size, prot = tonumber(i[0].BaseAddress), tonumber(i[0].RegionSize), tonumber(i[0].Protect)
      if not size or size <= 0 then break end
      local proto = bit.band(prot, 0xFF)
      local readable = bit.band(prot, 0x100) == 0 and (proto == 0x02 or proto == 0x04 or proto == 0x08 or proto == 0x20 or proto == 0x40 or proto == 0x80)
      if tonumber(i[0].State) == 0x1000 and readable then out[#out + 1] = { base = base, size = size } end
      a = base + size
    end
    return out
  end
  return api
end)
if not ok then report('disabled: ' .. tostring(api)); return end

-- ---------------------------------------------------------------- 工具
local function write_bytes(address, bytes)
  local old = api.unprotect(address, #bytes)
  if not old then state.refusals = state.refusals + 1; report(('VirtualProtect 失败 0x%X'):format(address), true); return false end
  local wrote = api.write(address, bytes)
  api.reprotect(address, #bytes, old)
  if not wrote then state.refusals = state.refusals + 1; report(('WriteProcessMemory 失败 0x%X'):format(address), true); return false end
  if api.read(address, #bytes) ~= bytes then state.refusals = state.refusals + 1; report(('回读校验失败 0x%X'):format(address), true); return false end
  return true
end

-- 自我命中规避
local SELF_ADDRS = {}
for _, s in ipairs(SELF_PATTERNS) do
  local p = tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', s)))
  if p and p ~= 0 then SELF_ADDRS[#SELF_ADDRS + 1] = p end
end
local function is_self_hit(a)
  for i = 1, #SELF_ADDRS do local d = a - SELF_ADDRS[i]; if d > -4096 and d < 4096 then return true end end
  return false
end

local function validate(magic, want)
  local h = api.read(magic, DATA_OFF)
  if not h or h:sub(1,4) ~= MAGIC then return nil end
  if decode32(h, 4) ~= 1 or decode32(h, 8) ~= want then return nil end
  local size = decode32(h, 12)
  if not size or size < MIN_SIZE or size > MAX_SIZE then return nil end
  return size
end

-- ---------------------------------------------------------------- ① 挂载
local function apply_rack(magic)
  local size = validate(magic, TYPE_RACK)
  if not size or size > DATA_CAP then return end
  local data = api.read(magic + DATA_OFF, size)
  if not data then return end

  -- 记录区起点候选（16 的倍数 + (size-b) 能被记录长整除 + 索引区条目合法）
  local cands = {}
  local ni = 1
  while true do
    local b = ni * 16
    if b + RACK_SR > size then break end
    if (size - b) % RACK_SR == 0 then
      local n = (size - b) / RACK_SR
      local good, k = true, 0
      while k + 16 <= b do
        if decode32(data, k + 12) ~= 0 or decode32(data, k + 8) >= n then good = false break end
        k = k + 16
      end
      if good and n >= 20 then cands[#cands + 1] = { base = b, n = n } end
    end
    ni = ni + 1
  end
  if #cands == 0 then return end
  table.sort(cands, function(a, b) return a.base > b.base end)   -- 先试"索引区最长"的

  local function find_rec(base, nr, entity_le)
    local q = data:find(entity_le, 1, true)
    while q do
      if (q - 1) % 16 == 0 and q - 1 + 16 <= base then
        local ix, pad = decode32(data, q - 1 + 8), decode32(data, q - 1 + 12)
        if pad == 0 and ix < nr then return base + ix * RACK_SR, ix end
      end
      q = data:find(entity_le, q + 1, true)
    end
    return nil
  end

  -- 只做结构复核（不写）：记录存在 + 该槽 node 对得上
  local function check_slot(base, nr, entity_le, slot, node_le)
    local rec_off = find_rec(base, nr, entity_le)
    if not rec_off then return false end
    local o = rec_off + slot * RACK_SLOT_SR
    return data:sub(o + 9, o + 12) == node_le
  end

  -- 选起点：两条目标记录都要通过复核（防"更大但错误"的候选）
  local chosen = nil
  for _, c in ipairs(cands) do
    if check_slot(c.base, c.n, RACK_A_ENTITY, RACK_A_SLOT, RACK_A_NODE)
       and check_slot(c.base, c.n, RACK_B_ENTITY, RACK_B_SLOT, RACK_B_NODE) then chosen = c break end
  end
  if not chosen then
    if not state.rack_warned or state.frame - state.rack_warned > 6000 then
      state.rack_warned = state.frame
      report(('表 0x%X：%d 个候选起点都没通过槽位复核（size=%d），本轮拒写'):format(magic, #cands, size), true)
    end
    return
  end
  if state.rack_base ~= chosen.base then
    state.rack_base = chosen.base
    report(('表 0x%X：采用记录区起点 +%d（%d 条记录），按索引 ID 定位两条外骨骼记录'):format(
      magic, chosen.base, chosen.n), true)
  end

  local function do_slot(entity_le, slot, expect_item, node_le, want_item, tag)
    local rec_off, ix = find_rec(chosen.base, chosen.n, entity_le)
    if not rec_off then report(('表 0x%X：索引里没有 %s'):format(magic, tag), true); return end
    local s = rec_off + slot * RACK_SLOT_SR
    local address = magic + DATA_OFF + s
    local cur  = data:sub(s + 1, s + 8)
    local node = data:sub(s + 9, s + 12)
    if node ~= node_le then
      state.refusals = state.refusals + 1
      report(('表 0x%X：%s 槽%d node=%s（期望 %s），拒写'):format(magic, tag, slot, hex(node), hex(node_le)), true)
      return
    end
    if cur == want_item then
      state.slots[address] = { kind = 'item', expect = want_item }
      state.round_hits = (state.round_hits or 0) + 1
      state.tables[magic] = size
      report(('表 0x%X：%s 槽%d 已是目标 item（recIdx %d）'):format(magic, tag, slot, ix))
      return
    end
    if cur ~= expect_item then
      state.refusals = state.refusals + 1
      report(('表 0x%X：%s 槽%d 当前 item=%s 既非原值也非目标值，拒写（recIdx %d）'):format(
        magic, tag, slot, hex(cur), ix), true)
      return
    end
    if DRY_RUN then report(('（DRY_RUN）本应写 %s 槽%d：%s → %s（recIdx %d）'):format(
      tag, slot, hex(cur), hex(want_item), ix), true); return end
    if write_bytes(address, want_item) then
      state.writes = state.writes + 1
      state.slots[address] = { kind = 'item', expect = want_item }
      state.round_hits = (state.round_hits or 0) + 1
      state.tables[magic] = size
      report(('已改挂载：表 0x%X %s 槽%d %s → %s（recIdx %d，node 未动）'):format(
        magic, tag, slot, hex(cur), hex(want_item), ix), true)
      dump('BalancedExosuitEmancipator_Addresses.log', table.concat({
        ('挂载表基址        = 0x%X (size=%d, 起点 +%d, %d 条)'):format(magic, size, chosen.base, chosen.n),
        ('%s 槽%d item      = 0x%X（recIdx %d）'):format(tag, slot, address, ix),
        ('写入前 / 写入后   = %s / %s'):format(hex(cur), hex(api.read(address, 8) or '')),
      }, '\n') .. '\n')
    end
  end

  do_slot(RACK_A_ENTITY, RACK_A_SLOT, RACK_A_EXPECT, RACK_A_NODE, RACK_A_WANT, 'EXO-49(obsidian)')
  do_slot(RACK_B_ENTITY, RACK_B_SLOT, RACK_B_EXPECT, RACK_B_NODE, RACK_B_WANT, 'EXO-45(patriot)')

  -- 登记"两处挂载是否都已就位"（只有全部三处都完成，才允许进维护模式）
  local function slot_is_want(entity_le, slot, want)
    local rec_off = find_rec(chosen.base, chosen.n, entity_le)
    if not rec_off then return false end
    local s = rec_off + slot * RACK_SLOT_SR
    return data:sub(s + 1, s + 8) == want
  end
  state.rack_ok = slot_is_want(RACK_A_ENTITY, RACK_A_SLOT, RACK_A_WANT)
              and slot_is_want(RACK_B_ENTITY, RACK_B_SLOT, RACK_B_WANT)
end

-- ---------------------------------------------------------------- ③ 战备附加（纯内容定位）
-- 目标记录由 package 值 + icon（+8）双重确认；附加槽 = package + 32；
-- 邻字段 depends_on(+28) / max_in_loadout(+36) 必须为 0 才写。
-- 同时扫"对向版 mod"的 package，用于二选一保护（见 strat_try_apply）。
local function strat_scan_chunk(window, wb)
  -- 目标 package 与"对向 mod"的 package 都扫（对向只用于检测，不写）
  local function scan(pat, tab)
    local from = 1
    while true do
      local i = window:find(pat, from, true)
      if not i then break end
      from = i + 1
      local c = wb + i - 1                       -- package 字段地址
      if not is_self_hit(c) then tab[c] = true end
    end
  end
  scan(WALKER_PACKAGE, state.pkg_hits)
  scan(COUNTER_PACKAGE, state.counter_hits)
end

local function strat_try_apply()
  if state.strat_ok then return end
  -- ⚠ 二选一保护：对向记录已被写入（附加槽非 0）→ 本 mod 拒写，避免"战备套娃"崩溃
  --   fail-open：没扫到对向记录（或 icon 不匹配）时照常工作。
  if not state.counter_blocked then
    for c in pairs(state.counter_hits) do
      local cicon = api.read(c + 8, 8)
      if cicon == COUNTER_ICON then
        local cv = api.read(c + STRAT_ADD_OFF, 4)
        if cv and decode32(cv, 0) ~= 0 then
          state.counter_blocked = true
          report(('战备附加：检测到**对向版 mod 已经生效**（对向 package 0x%X，附加槽 = %d）——两个版本同时启用会因战备套娃崩溃，本 mod 拒绝写入，请二选一。'):format(
            c, decode32(cv, 0)), true)
        end
      end
    end
  end
  if state.counter_blocked then return end
  local hits = {}
  for c in pairs(state.pkg_hits) do hits[#hits + 1] = c end
  table.sort(hits)
  if #hits == 0 then
    if not state.strat_warned or state.frame - state.strat_warned > 6000 then
      state.strat_warned = state.frame
      report('战备附加：还没扫到目标 package 值', true)
    end
    return
  end
  local good = 0
  for _, c in ipairs(hits) do
    local icon = api.read(c + 8, 8)
    if icon ~= ICON_WALKER then
      if not state.icon_warned or state.frame - state.icon_warned > 6000 then
        state.icon_warned = state.frame
        report(('战备附加：0x%X 命中 package 值但 icon=%s（期望 %s）→ 跳过'):format(
          c, hex(icon or ''), hex(ICON_WALKER)), true)
      end
    else
      good = good + 1
      local address = c + STRAT_ADD_OFF
      local cur  = api.read(address, 4)
      local pre  = api.read(c + STRAT_NEI_A, 4)
      local post = api.read(c + STRAT_NEI_B, 4)
      if not cur or not pre or not post then
        report(('战备附加：0x%X 读不到字段（package+%d）'):format(c, STRAT_ADD_OFF), true)
      elseif pre ~= ZERO4 or post ~= ZERO4 then
        state.refusals = state.refusals + 1
        report(('战备附加：0x%X 的邻字段非 0（depends_on=%s max_in_loadout=%s），拒写'):format(
          c, hex(pre), hex(post)), true)
      else
        local width, now = 4, decode32(cur, 0)
        if cur:byte(2) ~= 0 or cur:byte(3) ~= 0 or cur:byte(4) ~= 0 then width, now = 1, cur:byte(1) end
        local want = (width == 4) and hex_le(string.format('%08X', ATTACH_VALUE)) or string.char(ATTACH_VALUE)
        if now == ATTACH_VALUE then
          state.slots[address] = { kind = 'attach', expect = want }
          state.round_hits = (state.round_hits or 0) + 1
          state.strat_ok = true
          report(('战备附加：0x%X 已是目标值 %d（package+%d，宽度 %d）'):format(c, ATTACH_VALUE, STRAT_ADD_OFF, width))
        elseif now ~= 0 then
          state.refusals = state.refusals + 1
          report(('战备附加：0x%X 当前值 %d 既不是 0 也不是 %d，拒写（package+%d）'):format(
            c, now, ATTACH_VALUE, STRAT_ADD_OFF), true)
        elseif DRY_RUN then
          report(('（DRY_RUN）战备附加本应写 %d（package+%d，宽度 %d，package 址 0x%X）'):format(
            ATTACH_VALUE, STRAT_ADD_OFF, width, c), true)
        elseif write_bytes(address, want) then
          state.writes = state.writes + 1
          state.slots[address] = { kind = 'attach', expect = want }
          state.round_hits = (state.round_hits or 0) + 1
          state.strat_ok = true
          state.tables[c] = 1024
          report(('已改战备附加：%d → %d（package 0x%X，字段 = package+%d，宽度 %d，icon 校验通过）'):format(
            now, ATTACH_VALUE, c, STRAT_ADD_OFF, width), true)
          dump('BalancedExosuitEmancipator_StratSites.log', table.concat({
            ('package 字段地址    = 0x%X（= packages/generated/loadout/combat_walker_obsidian）'):format(c),
            ('icon 字段           = 0x%X（校验通过 ✓）'):format(c + 8),
            ('附加槽地址          = 0x%X（package+%d）'):format(address, STRAT_ADD_OFF),
            ('写入前 / 写入后     = %s / %s'):format(hex(cur), hex(api.read(address, width) or '')),
            ('邻字段 depends_on / max_in_loadout = %s / %s'):format(hex(pre or ''), hex(post or '')),
          }, '\n') .. '\n')
        end
      end
    end
  end
  if good == 0 and not state.strat_warned2 then
    state.strat_warned2 = true
    report(('战备附加：%d 个 package 命中点都没有通过 icon 校验（可能版本变了）'):format(#hits), true)
  end
end

local function apply(magic)
  local head = api.read(magic + 8, 4)
  if not head then return end
  local typ = decode32(head, 0)
  if typ == TYPE_RACK then apply_rack(magic) end
end

-- ---------------------------------------------------------------- 复查 / 状态
local function write_status()
  local n = 0
  for _ in pairs(state.slots) do n = n + 1 end
  local copies = 0
  for _ in pairs(state.tables) do copies = copies + 1 end
  local first = (n > 0) and ('OK - 补丁生效中（%d 处）'):format(n)
             or (state.gave_up and 'FAILED - 目标表始终没出现（看 Census.log）' or 'WORKING - 扫描中')
  dump('BalancedExosuitEmancipator_STATUS.log', table.concat({
    first,
    'revision=walker-loadout-emancipator-1.0' .. (DRY_RUN and '-dryrun' or ''),
    'phase=' .. tostring(state.phase),
    'updated=' .. os.date('%Y-%m-%d %H:%M:%S'),
    ('前置 = Bingus Shared Loader loader-v%s / API %s（来源 %s）'):format(tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)),
    '改动 = ①EXO-49 槽1 右臂加农炮→加特林炮塔 ②EXO-45 槽0 导弹发射器→左臂加农炮 ③战备附加 0→10',
    (state.ready and '战备状态 = 已就绪 ✓ 可以在飞船上看附加条目了（列表在进任务时定型，改完请回飞船重新进任务）' or '战备状态 = 未就绪 ✗ 先别召唤载具（正在抢时间扫表：每帧 16ms，优先战备表）'),
    ('已写=%d 处  拒绝=%d  轮次=%d  空轮=%d  帧=%d'):format(state.writes, state.refusals, state.rounds, state.empty_rounds, state.frame),
    ('内存里的表副本 = %d 处   维护扫描 = 每 %d 秒'):format(copies, MAINTAIN_FRAMES / 60),
  }, '\n') .. '\n')
end

local function recheck()
  local live, dropped = 0, 0
  for address, info in pairs(state.slots) do
    local cur = api.read(address, #info.expect)
    if cur == nil then state.slots[address] = nil; dropped = dropped + 1
    elseif cur == info.expect then live = live + 1
    else
      report(('复查：0x%X 的值变成 %s（%s，期望 %s）'):format(address, hex(cur), info.kind, hex(info.expect)), true)
      state.slots[address] = nil; dropped = dropped + 1
    end
  end
  if dropped > 0 then report(('复查：丢弃失效地址 %d 处'):format(dropped), true) end
  if live == 0 then
    state.slots = {}; state.tables = {}; state.phase = 'scanning'
    state.rack_ok, state.strat_ok = false, false
    state.regions = nil; state.next_scan_frame = state.frame
    report('复查：已无存活补丁，重新开始全量扫描', true)
  end
end

-- ---------------------------------------------------------------- 扫描

local function collect_regions()
  local all = api.regions(); local list = {}
  for i = 1, #all do if all[i].size >= 65536 then list[#list + 1] = all[i] end end
  table.sort(list, function(a, b) return a.size > b.size end)
  return list
end
local function collect_windows()
  local out = {}
  for a in pairs(state.tables) do out[#out + 1] = { base = math.max(65536, a - 32768), size = 98304 } end
  table.sort(out, function(x, y) return x.base < y.base end)
  local m = {}
  for i = 1, #out do
    local last = m[#m]
    if last and out[i].base <= last.base + last.size then
      local stop = out[i].base + out[i].size
      if stop > last.base + last.size then last.size = stop - last.base end
    else m[#m + 1] = out[i] end
  end
  return m
end

local function begin_scan(kind)
  state.scan_kind = kind
  state.regions = (kind == 'window') and collect_windows() or collect_regions()
  if kind == 'full' and next(state.priority) then
    local pri, rest = {}, {}
    for i = 1, #state.regions do
      local r, hit = state.regions[i], false
      for a in pairs(state.priority) do if a >= r.base and a < r.base + r.size then hit = true break end end
      if hit then pri[#pri + 1] = r else rest[#rest + 1] = r end
    end
    for i = 1, #rest do pri[#pri + 1] = rest[i] end
    state.regions = pri
  end
  state.region_index, state.region_offset, state.previous = 1, 0, ''
  state.seen, state.round_hits = {}, 0
  state.rounds = state.rounds + 1
  if kind == 'full' and state.phase ~= 'patched' then report(('第 %d 轮扫描开始：%d 个区域'):format(state.rounds, #state.regions), true) end
end

local function slice()
  local hurry = (state.scan_kind == 'full') and not (state.rack_ok and state.strat_ok) and (state.rounds <= 30)
  local deadline = os.clock() + (hurry and SCAN_BUDGET_HURRY or SCAN_BUDGET)
  while state.region_index <= #state.regions do
    local region = state.regions[state.region_index]
    while state.region_offset < region.size do
      if os.clock() > deadline then return false end
      local amount = math.min(SCAN_CHUNK, region.size - state.region_offset)
      local buf = api.read(region.base + state.region_offset, amount)
      state.scanned = (state.scanned or 0) + amount
      if buf then
        local wb = region.base + state.region_offset - #state.previous
        local window = state.previous .. buf
        -- ① 优先：战备表签名（附加条目时效性最强，越早打越好）
        local sf = 1
        while true do
          local i = window:find(SIG_STRAT, sf, true)
          if not i then break end
          sf = i + 1
          local abs = wb + i - 1
          if not is_self_hit(abs) and not state.seen[abs] then
            state.seen[abs] = true
            local ok2, err = pcall(apply, abs)
            if not ok2 then state.errs = state.errs + 1; if state.errs <= 3 then report('战备表处理异常: ' .. tostring(err), true) end end
          end
        end
        -- ② 通用 LDLD（挂载表 + 其它）
        local from = 1
        while true do
          local i = window:find(MAGIC, from, true)
          if not i then break end
          from = i + 1
          local abs = wb + i - 1
          if not is_self_hit(abs) and not state.seen[abs] then
            state.seen[abs] = true
            local ok2, err = pcall(api and apply, abs)
            if not ok2 then state.errs = state.errs + 1; if state.errs <= 3 then report('命中处理异常: ' .. tostring(err), true) end end
          end
        end
        -- ③ 战备附加：纯内容定位（payload = 实体 + 鹈鹕，纯内容定位 + 自标定偏移）
        local ok3, err3 = pcall(strat_scan_chunk, window, wb)
        if not ok3 then state.errs = state.errs + 1; if (state.strat_errs or 0) < 3 then state.strat_errs = (state.strat_errs or 0) + 1; report('战备内容扫描异常: ' .. tostring(err3), true) end end
        local ok4, err4 = pcall(strat_try_apply)
        if not ok4 then state.errs = state.errs + 1; if (state.strat_errs or 0) < 3 then state.strat_errs = (state.strat_errs or 0) + 1; report('战备附加异常: ' .. tostring(err4), true) end end
        state.previous = buf:sub(-SCAN_OVERLAP)
      else state.previous = '' end
      state.region_offset = state.region_offset + amount
    end
    state.region_index, state.region_offset, state.previous = state.region_index + 1, 0, ''
  end
  return true
end

local function end_round()
  local ok5, err5 = pcall(strat_try_apply)
  if not ok5 and state.errs <= 3 then report('战备附加异常(end_round): ' .. tostring(err5), true) end
  local kind = state.scan_kind or 'full'
  state.regions = nil
  if (state.rack_ok and state.strat_ok) then
    state.empty_rounds, state.phase = 0, 'patched'   -- 只有三处全部完成才进维护模式
    if not state.ready then
      state.ready = true
      report('三处改动均已就绪：**现在可以召唤 / 重新召唤载具了**', true)
    end
    if kind == 'window' then
      report(('维护扫描：窗口 %d 个，命中 %d'):format(#(state.regions or {}), state.round_hits))
    end
  elseif (state.round_hits or 0) > 0 then
    -- 只完成了一部分（例如挂载已改好、战备表还没加载）→ 不休眠，继续全量扫描
    state.empty_rounds = 0
    state.next_scan_frame = state.frame + 60
    report(('部分完成：挂载=%s 战备=%s —— 继续全量扫描（等战备表加载）'):format(
      tostring(state.rack_ok), tostring(state.strat_ok)), true)
  elseif kind == 'window' or state.phase == 'patched' then
    -- 维护扫描没命中：正常
  else
    state.empty_rounds = state.empty_rounds + 1
    local wait = BACKOFF[math.min(state.empty_rounds, #BACKOFF)]
    state.next_scan_frame = state.frame + math.floor(wait * 60)
    report(('第 %d 轮完成：未命中（空轮 %d/%d，%d 秒后再试）'):format(state.rounds, state.empty_rounds, MAX_EMPTY, wait))
    if state.empty_rounds >= MAX_EMPTY then state.gave_up = true; state.phase = 'gave_up'; report('连续多轮没找到目标表，停止扫描', true) end
  end
  write_status()
end

local function run_slice()
  local ok2, finished = pcall(slice)
  if not ok2 then state.errs = state.errs + 1; state.regions = nil; state.next_scan_frame = state.frame + 60; report('扫描异常: ' .. tostring(finished), true); return end
  if finished then end_round() end
end

-- 舰船待命采样（设置表只在任务里加载）
local function probe_run()
  if not state.probe_list then
    local all = collect_regions(); local list = {}
    for i = 1, math.min(#all, PROBE_REGIONS) do list[#list + 1] = { base = all[i].base, size = math.min(all[i].size, PROBE_CAP) } end
    state.probe_list, state.probe_index, state.probe_offset, state.probe_prev = list, 1, 0, ''
  end
  local deadline = os.clock() + SCAN_BUDGET
  while state.probe_index <= #state.probe_list do
    local r = state.probe_list[state.probe_index]
    while state.probe_offset < r.size do
      if os.clock() > deadline then return false end
      local amount = math.min(SCAN_CHUNK, r.size - state.probe_offset)
      local buf = api.read(r.base + state.probe_offset, amount)
      if buf then
        local wb = r.base + state.probe_offset - #state.probe_prev
        local window = state.probe_prev .. buf
        local fi = 1
        while true do
          local f = window:find(MAGIC, fi, true)
          if not f then break end
          fi = f + 1
          local abs = wb + f - 1
          local hdr = api.read(abs, 16)
          if hdr and decode32(hdr, 4) == 1 then
            state.priority[abs] = true
            local typ = decode32(hdr, 8)
            if (typ == TYPE_STRAT or typ == TYPE_RACK) and not state.seen[abs] then
              state.seen[abs] = true
              report(('加载期就发现目标表（0x%X type=0x%08X）→ 立即修补'):format(abs, typ), true)
              pcall(apply, abs)
            end
          end
        end
        state.probe_prev = buf:sub(-SCAN_OVERLAP)
      else state.probe_prev = '' end
      state.probe_offset = state.probe_offset + amount
    end
    state.probe_index, state.probe_offset, state.probe_prev = state.probe_index + 1, 0, ''
  end
  state.probe_list = nil
  state.ready_probe = true
  local npri = 0
  for _ in pairs(state.priority) do npri = npri + 1 end
  report(('采样完成（%d 个地址见到表）→ 转全量扫描，优先扫这些区域'):format(npri), true)
  return true
end

local function frame()
  state.frame = state.frame + 1
  if state.frame % 60 == 0 then flush_log() end
  if state.phase == 'patched' and state.rack_ok and state.strat_ok then
    if state.frame % 300 == 0 then recheck(); write_status(); if state.phase ~= 'patched' then return end end
    if not state.regions then
      if state.frame >= (state.full_frame or 0) then state.full_frame = state.frame + FULL_RESCAN_FRAMES; state.maintain_frame = state.frame + MAINTAIN_FRAMES; begin_scan('full')
      elseif state.frame >= (state.maintain_frame or 0) then state.maintain_frame = state.frame + MAINTAIN_FRAMES; begin_scan('window') end
    end
    if state.regions then run_slice() end
    return
  end
  if state.gave_up then return end
  if state.frame < (state.next_scan_frame or 0) then return end
  if state.frame < 120 then return end
  if not state.probe_ok then
    if not probe_run() then return end
    if state.ready_probe then state.probe_ok = true; return end
    state.probe_fails = (state.probe_fails or 0) + 1
    if state.probe_fails >= PROBE_FAIL_LIMIT then state.probe_ok = true; report('采样多次没看到 LDLD，转全量扫描', true)
    else state.next_scan_frame = state.frame + PROBE_WAIT; report(('待命：内存里没有 LDLD 表（还没进任务？）%d 秒后再试'):format(PROBE_WAIT / 60)) end
    return
  end
  if not state.regions then begin_scan('full'); return end
  run_slice()
end

-- ---------------------------------------------------------------- 环境闸门 + 挂载
do
  local l = rawget(_G, 'CowboyBingusModLoader')
  if type(l) == 'table' then ENV.api, ENV.version, ENV.source = tonumber(l.api), tonumber(l.version), 'global' end
  if not ENV.api then
    pcall(function()
      local base = os.getenv('LOCALAPPDATA')
      local f = base and io.open(base .. '/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log', 'r')
      if f then
        local first = f:read('*l') or ''; f:close()
        local v, a = first:match('loader%-v(%d+);%s*API%s*(%d+)')
        ENV.version, ENV.api = tonumber(v), tonumber(a)
        if ENV.api then ENV.source = 'log' end
      end
    end)
  end
end
if ENV.api and ENV.api < 1 then
  local msg = ('FAILED - 前置 Bingus Shared Loader 太旧：API %s (loader v%s)；需要 API 1（loader v15+）'):format(tostring(ENV.api), tostring(ENV.version))
  dump('BalancedExosuitEmancipator_STATUS.log', msg .. '\n'); report(msg, true); return
end

local original_update = update
if type(original_update) == 'function' then
  update = function(...)
    local ok2, err = pcall(frame)
    if not ok2 then state.errs = state.errs + 1; if state.errs <= 5 then report('frame error: ' .. tostring(err)) end end
    return original_update(...)
  end
else
  state.phase = 'no_update'; report('全局 update 不可用，无法运行', true)
end

report(('已加载 v1.0·携带解放者版（更均衡的爱国者/解放者外骨骼：EXO-49 槽1→加特林炮塔 / EXO-45 槽0→左臂加农炮 / 召唤解放者额外附带 %d 号战备 = 爱国者））；前置 loader v%s / API %s（来源 %s）'):format(
  ATTACH_VALUE, tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)))
