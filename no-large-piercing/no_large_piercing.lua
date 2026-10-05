-- HD2-Addon: mods/dsh/no_large_piercing

-- ===========================================================================
--  No Large Piercing —— 命中特效等级 → 0 (HitEffectDamageType_None)
--
--  ★ v1.6【找表交给 HD2 Scanner 前置】（仓库 core 线）：Scanner 本来就每 30 秒定位
--    ProjectileSettings / ExplosionSettings（它的已登记表）并广播每个副本的 LDLD 地址；
--    本 mod 只做 订阅 → poll → 对每个地址走 apply()，**自己不再扫内存**（开机那 23 秒没了）。
--    Scanner 缺席、或接上后 30 秒还没广播到这两张表 → 自动回退到下面这套自带扫描。
--
--  ★ v1.5 起【一次性写入】（ONE_SHOT）（现在是 Scanner 缺席时的回退路径）：启动时把两张表写完、回读验证，然后
--    彻底停止扫描 —— 不再有维护窗口 / 热区自检 / 兜底全量。稳态开销 0；
--    唯一的常驻动作是「金丝雀」：每 WATCHDOG_EVERY 帧只读已写入的 108 个地址
--    （432 B≈0 成本），发现被冲掉就退回 v1.4 的维护式调度。
--    一次性模式超时（ONE_SHOT_DEADLINE）或金丝雀失效时也会退回维护式调度。
--    ONE_SHOT = false 可整块关掉，回到 v1.4 行为。
--    人工兜底：_G.HD2_NoLargePiercing_Rescan() 清空已写入清单、重走一次扫描。
--
--  把两张设置表里「特效·伤害类型」为 3 或 4 的记录，全部改写为 0：
--     ProjectileSettings.effect_damage_type     (直击/弹道)  343 条 → 改 102 条
--     ExplosionSettings.hit_effect_damage_type  (爆炸)       413 条 → 改   4 条
--
--  枚举 HitEffectDamageType：
--     0 None  ★           1 PiercingSmall    2 PiercingMedium
--     3 PiercingLarge     4 PiercingLargeHEAT
--     5 IncendiarySmall   6 IncendiaryMedium 7 BeamSmall  8 BeamLarge  9 Blunt
--    10 SlashingSmall    11 SlashingLarge   12 VehicleStep  13 PiercingSmallStim
--
--  表布局（LDLD 块；磁盘明文镜像与内存布局一致）：
--     +0   "LDLD"     +4  version=1     +8  typeHash     +12 size
--     +24  16 字节数组描述符 { u64 记录起点偏移(=16), u64 条数 }
--     +40  记录数组
--        ProjectileInfo  272 B  →  +232 u32  effect_damage_type
--        ExplosionInfo   152 B  →  +76  u32  hit_effect_damage_type
--
--  偏移与记录尺寸取自游戏自带 typelib（filediver datalibrary），并用明文
--  generated_projectile_settings.dl_bin / generated_explosion_settings.dl_bin
--  逐条比对验证过（343×6 与 413×8 个字段，0 处不符）。
--
--  只在内存中改写，不触碰磁盘文件；禁用 mod 即完全还原。
--  联机时这是本地改动，其他玩家看不到，且存在反作弊(nProtect GameGuard)风险。
--  ※ 与 mods/dsh/effect_grade_2 互斥，同一时间只能启用其中一个。
-- ===========================================================================

local VERSION = '1.6'
local MOD = 'mods/dsh/no_large_piercing'
if rawget(_G, MOD) then return end

-- 两个变体互斥：都启用会互相覆盖，第二个直接退出
local owner = rawget(_G, 'HD2_NoLargePiercing_Owner')
if owner then
  print('[NoLargePiercing] 检测到已加载的 ' .. tostring(owner) .. '，本实例退出（两个变体只能启用一个）')
  return
end

local state = {
  frame = 0, status = nil, rounds = 0, errs = 0,
  changed = 0, wrote = 0,
  patched = {},          -- [magic] = 表定义（含 count）
  dumped  = {},          -- [magic] = DIAG 已导出
  verified = {},         -- [t]     = 该表已通过一次全量自洽校验
  slots   = {},          -- [addr]  = { expect, magic, t } 已写入的字段地址
  -- 调度
  all_done = false, done_armed = false,
  hot = {}, hot_ticks = 0,          -- [区段 base] = { base, size }：曾经出现过表的区段
  full_interval = 0, full_frame = 0, next_scan_frame = 0,
  regions = nil, region_index = 1, region_offset = 0, prev = '',
  scan_kind = nil, round_hits = 0, empty_rounds = 0,
  -- 一次性模式（v1.5）
  finished = false, oneshot_disabled = false, deadline_hit = false,
}
rawset(_G, MOD, state)
rawset(_G, 'HD2_NoLargePiercing_Owner', MOD)

-- ===========================================================================
-- 目标参数 —— 与 effect_grade_2 唯一的差异就在这里
-- ===========================================================================
local TARGET_VALUE  = 0
local TARGET_LABEL  = '0 (None)'
local SOURCE_VALUES = { [3] = true, [4] = true }

-- ===========================================================================
-- 日志（loader 的 open_log 是覆盖模式，必须自累积、批量落盘）
-- ===========================================================================
local loghist = {}

local function flush_log()
  if #loghist == 0 then return end
  local text = table.concat(loghist, '\n') .. '\n'
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local file = loader and loader.open_log and loader.open_log('NoLargePiercing.log')
    if file then file:write(text); file:close() end
  end)
end

local function report(message, keep)
  if not keep and state.status == message then return end
  state.status = message
  print('[NoLargePiercing] ' .. message)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, message)
  if keep or #loghist % 10 == 0 then flush_log() end
end

local function dump(name, text)
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local file = loader and loader.open_log and loader.open_log(name)
    if file then file:write(text); file:close() end
  end)
end

-- ===========================================================================
-- FFI / kernel32
-- ===========================================================================
local ffi_ok, ffi = pcall(require, 'ffi')
local bit_ok, bit = pcall(require, 'bit')

local ok, api = pcall(function()
  assert(ffi_ok and ffi, 'ffi unavailable')
  assert(bit_ok and bit, 'bit unavailable')
  assert(ffi.abi('64bit'), 'Windows x64 is required')
  ffi.cdef [[
    typedef struct {
      uintptr_t BaseAddress;
      uintptr_t AllocationBase;
      uint32_t  AllocationProtect;
      uint32_t  PartitionId;
      size_t    RegionSize;
      uint32_t  State;
      uint32_t  Protect;
      uint32_t  Type;
    } HEG_MEMORY_BASIC_INFORMATION;
    void   *GetCurrentProcess(void);
    int     ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
    int     WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
    int     VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
    size_t  VirtualQuery(const void *address, HEG_MEMORY_BASIC_INFORMATION *info, size_t length);
  ]]
  local kernel  = ffi.load('kernel32')
  local process = kernel.GetCurrentProcess()
  local api = {}

  function api.read(address, size)
    local buffer, count = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
    if kernel.ReadProcessMemory(process, ffi.cast('const void *', address), buffer, size, count) == 0 then
      return nil
    end
    if tonumber(count[0]) ~= size then return nil end
    return ffi.string(buffer, size)
  end

  function api.write(address, bytes)
    local count = ffi.new('size_t[1]')
    if kernel.WriteProcessMemory(process, ffi.cast('void *', address),
        ffi.cast('const void *', bytes), #bytes, count) == 0 then
      return false
    end
    return tonumber(count[0]) == #bytes
  end

  function api.unprotect(address, size)
    local old = ffi.new('uint32_t[1]')
    if kernel.VirtualProtect(ffi.cast('void *', address), size, 0x40, old) == 0 then return nil end
    return tonumber(old[0])
  end

  function api.reprotect(address, size, value)
    local old = ffi.new('uint32_t[1]')
    kernel.VirtualProtect(ffi.cast('void *', address), size, value, old)
  end

  function api.regions()
    local info = ffi.new('HEG_MEMORY_BASIC_INFORMATION[1]')
    local address, result = 0, {}
    while address < 0x7FFFFFFFFFFF do
      if kernel.VirtualQuery(ffi.cast('const void *', address), info, ffi.sizeof(info)) == 0 then break end
      local base = tonumber(info[0].BaseAddress)
      local size = tonumber(info[0].RegionSize)
      if not size or size <= 0 then break end
      local protect   = tonumber(info[0].Protect)
      local committed = tonumber(info[0].State) == 0x1000
      -- ★ 必须先剥掉修饰位再比较；且必须包含 PAGE_WRITECOPY(0x08)
      --   （项目 STATUS.md「已确认的环境事实」#3：区域枚举必须含 0x08）
      local proto = bit.band(protect, 0xFF)
      local readable = bit.band(protect, 0x100) == 0
        and (proto == 0x02 or proto == 0x04 or proto == 0x08 or proto == 0x20
          or proto == 0x40 or proto == 0x80)
      if committed and readable then
        result[#result + 1] = { base = base, size = size }
      end
      address = base + size
    end
    table.sort(result, function(a, b) return a.size > b.size end)
    return result
  end

  function api.address_of(bytes)
    return tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', bytes)))
  end

  return api
end)

if not ok then
  report('disabled: ' .. tostring(api))
  return
end

-- ===========================================================================
-- 小工具
-- ===========================================================================
-- 热路径：把常用全局本地化（扫描/校验每帧要调几千次）
local sbyte, sfind, ssub = string.byte, string.find, string.sub
local mmin, mfloor = math.min, math.floor

local function u32_at(bytes, offset)
  local a, b, c, d = sbyte(bytes, offset + 1, offset + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function u64_at(bytes, offset)
  local lo, hi = u32_at(bytes, offset), u32_at(bytes, offset + 4)
  if not lo or not hi then return nil end
  return lo + hi * 4294967296
end

local function encode_u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
                     math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local function hex(bytes)
  return (bytes:gsub('.', function(c) return string.format('%02X', c:byte()) end))
end

local function hex_le(h)
  local t = {}
  for i = #h - 1, 1, -2 do t[#t + 1] = string.char(tonumber(h:sub(i, i + 1), 16)) end
  return table.concat(t)
end

-- ===========================================================================
-- 目标表定义
--   base 指纹一律【不含被改字段】，这样写入后仍然成立，复查才有意义。
-- ===========================================================================
-- 扫描/复查节奏
-- ★ 与同项目其它 mod 对齐（tank_storm_coop / walker_loadout 都是 256KB + 2ms）。
--   旧的 1MB / 8ms 在 60fps 下等于直接砍掉一半帧预算。
local SCAN_CHUNK        = 256 * 1024    -- 常态每次读 256 KB（细粒度 → 每帧占用平滑）
local SCAN_CHUNK_HURRY  = 1024 * 1024   -- 抢时间阶段用 1 MB（少一点每块的固定开销，
                                        --   否则 256KB 块的固定成本会吃掉预算，找表慢一个量级）
local SEAM_KEEP         = 7             -- 跨块缝隙保留字节数（= 签名长度-1；v1.5 不再整块拼接）
local SCAN_BUDGET       = 0.002         -- 常态：每帧最多 2 ms CPU
local SCAN_BUDGET_HURRY = 0.010         -- 抢时间：还没打完时每帧 10 ms
                                        --   实机 v1.3：6ms + 256KB 块 → 找表用了 3363 帧(≈56s)，
                                        --   比旧版 8ms 的 327 帧慢一个量级。找表是一次性的、
                                        --   稳态已归零，所以这里给足预算。
local HURRY_ROUNDS      = 6             -- 前 6 轮按抢时间模式跑
local RECHECK_EVERY     = 600           -- 约 10 秒复查一次（只读已写入的 4 字节地址）
local MAINTAIN_FRAMES   = 600           -- 约 10 秒扫一次「已知表 ±32KB」观察窗口（约 290 KB/次）
local FULL_RESCAN_EVERY = 10800         -- 兜底全量重扫基准：3 分钟
local FULL_RESCAN_MAX   = 43200         -- 兜底全量重扫上限：12 分钟（连续无收获就翻倍退避）
local BACKOFF           = { 2, 2, 4, 4, 8, 15, 30, 60, 120, 300 }  -- 空轮等待（秒）
local WINDOW_MARGIN     = 32768         -- 观察窗口半径
local DIAG              = false         -- 诊断转储开关（before/after.hex、DIAG.csv）
-- ★ 静默：确认「注入已生效 + 稳定」之后彻底停止扫描。
--   静默期只保留 slots 复查（108 个地址 × 4 字节 / 10 秒 ≈ 43 字节/秒），
--   一旦复查发现任何异常就自动退出静默、恢复扫描 —— 所以静默不是"失联"。
local QUIET_MODE            = true    -- false = 保持维护式扫描（观察窗口 + 兜底全量）
local QUIET_AFTER_CHECKS    = 3       -- 连续 N 次复查无异常 → 判定稳定（约 30 秒）
-- ★ 热区记忆：命中过的内存区段会被记住，静默期只重扫这些区段。
--   实测（EffectGrade0.log）：原始副本在 0x2795C2F0004，之后 12 轮全量扫描里
--   每一次都能在【完全不同的新地址】找到完整表 —— 全都落在 0x7C8D0000~0x7EE00000
--   约 37 MB 的一段里。全量扫 4 GB 只为发现这些，代价 100 倍以上。
--   热区自检 ≈ 37 MB / 次（约全量的 1%），30 秒一轮；再每 QUIET_FULL_EVERY 轮
--   做一次真·全量兜底，防止表跑到从未出现过的区段。
local QUIET_FALLBACK_FRAMES = 1800  -- 静默期热区自检周期（约 30 秒）；0 = 关闭（真静默）
local QUIET_FULL_EVERY      = 40    -- 每 N 次热区自检做一次全量兜底（约 20 分钟）

-- ★ 一次性写入模式（v1.5 默认）
--   启动时扫一遍内存 → 写完两张表 → 回读验证 → 彻底停扫（稳态 0 成本）。
--   与 ONE_SHOT=false 的旧调度（观察窗口 / 热区自检 / 兜底全量）互斥。
local ONE_SHOT              = true
local ONE_SHOT_DEADLINE     = 10800   -- 入口帧起 3 分钟内没找齐两张表 → 记日志并退出一次性模式
local WATCHDOG_EVERY        = 3600    -- 金丝雀周期（帧，≈60 秒）；0 = 完全静默，连金丝雀也不要
local SCANNER_GIVEUP_FRAMES = 1800    -- 接上 Scanner 后 30 秒仍拿不到这两张表 → 回退自带扫描

-- 现在是「抢时间」阶段吗？
--   一次性模式：找表阶段全程抢时间（整轮只跑一次，且有 ONE_SHOT_DEADLINE 兜底）；
--   维护式调度：只有前 HURRY_ROUNDS 轮抢时间。
local function hurry_now()
  if state.all_done then return false end
  if ONE_SHOT and not state.oneshot_disabled then return true end
  return (state.rounds or 0) <= HURRY_ROUNDS
end

local MAGIC      = 'LDLD'
local DESC_OFF   = 24      -- 16 字节数组描述符
local COUNT_OFF  = 32      -- u32 记录条数
local BASE_OFF   = 40      -- 记录数组起点（= 24 + 描述符内的 16）

local TABLES = {
  {
    name       = 'ProjectileSettings',
    label      = '直击/弹道',
    type_hash  = 0xBD4042C2,
    rec_size   = 272,
    want_count = 343,      -- 离线镜像（filediver datalibrary）的条数，仅用于日志对比
    min_count  = 343,      -- 基线指纹所需最低条数（= 最大指纹下标 + 1）
    field_off  = 232,      -- effect_damage_type
    type_off   = 0,        -- ProjectileType
    aux_off    = 60,       -- damage_info_type
    -- {下标, ProjectileType, damage_info_type}
    baseline   = { {0, 282, 228}, {50, 250, 10}, {150, 245, 255}, {250, 247, 202}, {342, 259, 153} },
  },
  {
    name       = 'ExplosionSettings',
    label      = '爆炸',
    type_hash  = 0x2AEA2592,
    rec_size   = 152,
    want_count = 413,
    min_count  = 413,
    field_off  = 76,       -- hit_effect_damage_type
    type_off   = 0,        -- ExplosionType
    aux_off    = 4,        -- damage_type
    -- {下标, ExplosionType, damage_type}
    baseline   = { {0, 270, 282}, {50, 37, 341}, {150, 72, 260}, {250, 250, 471}, {412, 29, 639} },
  },
}

for _, t in ipairs(TABLES) do
  t.sig = MAGIC .. string.char(1, 0, 0, 0) .. hex_le(string.format('%08X', t.type_hash))
end

-- ===========================================================================
-- 前置：HD2 Scanner（core 线）—— 找表交给它
--   Scanner 的 kernel 已登记 ProjectileSettings(0xBD4042C2) / ExplosionSettings(0x2AEA2592)
--   （它按"区段基址 +0x4 是不是 LDLD + 类型哈希"逐个区段读 16 字节定位，代价 ≈ 每区段 1 次读，
--    而不是我们整片 4 GB 的扫），命中后广播 {addr = LDLD 魔数地址, size}，并每 30 秒复核、
--    地址变化时递增 generation（换图后的新副本它会重新报出来）。
--   我们只订阅 + poll + 写入；Scanner 缺席时回退到本文件自带的一次性全量扫描。
-- ===========================================================================
local SCAN = {
  api = nil, retry_at = 0, warned = false,
  polls = 0, applied = 0, attached_at = nil, gave_up = false,
}

-- ===========================================================================
-- 自检测：模式串就活在 Lua 堆里，扫描必然会命中自己
-- ===========================================================================
local SELF_ADDRS = {}
for _, t in ipairs(TABLES) do
  local a = api.address_of(t.sig)
  if a then SELF_ADDRS[#SELF_ADDRS + 1] = a end
end

local function is_self_hit(address)
  for _, a in ipairs(SELF_ADDRS) do
    if address >= a - 64 and address < a + 4096 then return true end
    if a >= address and a < address + 4096 then return true end
  end
  return false
end

-- ===========================================================================
-- 记录区自洽校验（★ 不依赖记录顺序）
--   新版把记录重排过了，所以"下标 N 应该是某个枚举值"这种指纹必然失配。
--   这里只检查"这些字段应该长什么样"：枚举值域 + 取值多样性。
--   记录尺寸或字段偏移一旦变化，这几条会同时崩掉，照样拦得住。
-- ===========================================================================
-- sample = nil → 全量逐条校验；sample = N → 均匀抽样 N 条。
--   本版本首次见到某张表时做全量；之后内存里冒出来的新副本只抽样
--   （布局已被全量校验证明过，抽样足以发现记录尺寸/字段偏移变化）。
local function verify_shape(t, data, count, sample)
  local step = 1
  if sample and count > sample then step = mfloor(count / sample) end
  local type_bad, aux_bad, eff_bad = 0, 0, 0
  local seen, distinct, checked = {}, 0, 0
  local eff3, eff4 = 0, 0
  for i = 0, count - 1, step do
    local r = i * t.rec_size
    local ty  = u32_at(data, r + t.type_off)
    local aux = u32_at(data, r + t.aux_off)
    local ef  = u32_at(data, r + t.field_off)
    checked = checked + 1
    if not ty  or ty  > 4095 then type_bad = type_bad + 1 end
    if not aux or aux > 4095 then aux_bad  = aux_bad  + 1 end
    if not ef  or ef  > 31   then eff_bad  = eff_bad  + 1 end
    if ty and ty > 0 and seen[ty] == nil then seen[ty] = true; distinct = distinct + 1 end
    if ef == 3 then eff3 = eff3 + 1 elseif ef == 4 then eff4 = eff4 + 1 end
  end
  local tol = mfloor(checked * 0.02)
  if type_bad > tol then return false, ('type 越界 %d/%d'):format(type_bad, checked) end
  if aux_bad  > tol then return false, ('aux  越界 %d/%d'):format(aux_bad,  checked) end
  if eff_bad  > tol then return false, ('特效字段越界 %d/%d'):format(eff_bad, checked) end
  if distinct < checked * 0.5 then return false, ('不同 type 太少 %d/%d'):format(distinct, checked) end
  return true, { eff3 = eff3, eff4 = eff4, distinct = distinct, checked = checked }
end

-- 诊断导出：把实际读到的整张表落盘，供离线核对
local function dump_diag(magic, t, data, count, shape)
  local lines = {}
  lines[#lines + 1] = ('# table=%s  magic=0x%X  count=%d  rec_size=%d  field_off=%d  type_off=%d  aux_off=%d')
    :format(t.name, magic, count, t.rec_size, t.field_off, t.type_off, t.aux_off)
  lines[#lines + 1] = ('# 离线镜像条数=%d   自洽校验: eff3=%d eff4=%d 不同type=%d')
    :format(t.want_count, shape.eff3, shape.eff4, shape.distinct)
  local dist, keys = {}, {}
  for i = 0, count - 1 do
    local v = u32_at(data, i * t.rec_size + t.field_off)
    if dist[v] == nil then keys[#keys + 1] = v end
    dist[v] = (dist[v] or 0) + 1
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = ('%s:%d'):format(tostring(k), dist[k]) end
  lines[#lines + 1] = '# 特效字段值分布: ' .. table.concat(parts, ' ')
  lines[#lines + 1] = 'index,type,aux,eff'
  for i = 0, count - 1 do
    local r = i * t.rec_size
    lines[#lines + 1] = ('%s,%s,%s,%s'):format(i,
      tostring(u32_at(data, r + t.type_off)),
      tostring(u32_at(data, r + t.aux_off)),
      tostring(u32_at(data, r + t.field_off)))
  end
  dump(('%s_%X.DIAG.csv'):format(t.name, magic), table.concat(lines, '\n') .. '\n')
end

-- ===========================================================================
-- 定位记录区起点
--   文件镜像里描述符的 u64 是【相对 magic+24 的偏移】(=16)；
--   若运行时被重定位成绝对指针，则该 u64 是个大地址。
--   两种都试，用"记录里的 type 字段是否落在合理值域"来裁决。
-- ===========================================================================
local function probe_base(magic, t, count)
  local cands, seen = {}, {}
  local function add(v)
    if v and v > 0 and not seen[v] then seen[v] = true; cands[#cands + 1] = v end
  end

  local desc = api.read(magic + DESC_OFF, 16)
  if desc then
    local p = u64_at(desc, 0)
    if p then
      if p < 0x100000 then add(magic + DESC_OFF + p) end   -- 相对偏移
      if p > 0x10000  then add(p) end                      -- 绝对指针
    end
  end
  add(magic + BASE_OFF)                                    -- 固定布局

  local sample = math.min(count, 16)
  for _, base in ipairs(cands) do
    local head = api.read(base, t.rec_size * sample)
    if head and #head == t.rec_size * sample then
      local sane = true
      for i = 0, sample - 1 do
        local v = u32_at(head, i * t.rec_size + t.type_off)
        if not v or v > 1023 then sane = false; break end
      end
      if sane then return base end
    end
  end
  return nil
end

-- ===========================================================================
-- 写入
-- ===========================================================================
-- 统一的写入入口（unprotect → write → reprotect）
local function write_bytes(address, bytes, size)
  local old = api.unprotect(address, size)
  if not old then return false end
  local good = api.write(address, bytes)
  api.reprotect(address, size, old)
  return good
end

-- 记下这块表所在的内存区段（热区）——静默期只重扫这些区段
local function note_hot(magic)
  local regs = state.regions
  if not regs then return end
  for i = 1, #regs do
    local r = regs[i]
    if magic >= r.base and magic < r.base + r.size then
      state.hot[r.base] = { base = r.base, size = r.size }
      return
    end
  end
end

-- 两张目标表是否都已定位并生效
local function resolved_tables()
  local seen, n = {}, 0
  for _, rec in pairs(state.patched) do
    if not seen[rec.t] then seen[rec.t] = true; n = n + 1 end
  end
  return n
end

-- 重算 all_done；首次达标时预约「维护窗口 + 兜底全量」
local function refresh_done()
  local done = resolved_tables() >= #TABLES
  state.all_done = done
  if done and not state.done_armed then
    state.done_armed  = true
    state.full_interval = FULL_RESCAN_EVERY
    state.full_frame    = state.frame + FULL_RESCAN_EVERY
    state.next_scan_frame = state.frame + MAINTAIN_FRAMES
  elseif not done then
    state.done_armed = false
  end
  -- 有新发现/新写入 → 静默计时重新开始
  state.stable_checks, state.quiet = 0, false
end

local function apply(magic, t)
  local known = state.patched[magic]
  -- 已处理过的表交给 slots 复查，扫描阶段直接跳过（省掉每次 60~90 KB 重读）
  if known and known.done then return end

  local header = api.read(magic, BASE_OFF)
  if not header or #header < BASE_OFF then return end
  if header:sub(1, 4) ~= MAGIC then return end
  if u32_at(header, 4) ~= 1 then return end
  if u32_at(header, 8) ~= t.type_hash then return end

  local count = u32_at(header, COUNT_OFF)
  if not count or count < 1 or count > 8192 then
    report(('%s @0x%X：条数 %s 异常，拒绝写入'):format(t.name, magic, tostring(count)), true)
    return
  end
  -- 游戏更新常在末尾追加条目。只要"不少于基线指纹所需"就按追加处理；
  -- 指纹仍逐条硬校验，结构一旦变化（记录尺寸/字段位移）照样会被拒。
  if count < t.min_count then
    report(('%s @0x%X：条数 %d 少于基线所需 %d，拒绝写入')
      :format(t.name, magic, count, t.min_count), true)
    return
  end

  local base = probe_base(magic, t, count)
  if not base then
    report(('%s @0x%X：记录区定位失败，拒绝写入'):format(t.name, magic), true)
    return
  end

  local total = count * t.rec_size
  local data = api.read(base, total)
  if not data or #data ~= total then
    report(('%s @0x%X：读取记录区失败（%d 字节）'):format(t.name, magic, total), true)
    return
  end

  -- ★ 自洽校验（不依赖记录顺序）
  --   本版本首次见到该表做全量逐条；之后的新副本只均匀抽样 32 条
  local shape_ok, shape = verify_shape(t, data, count, state.verified[t] and 32 or nil)
  if not shape_ok then
    report(('%s @0x%X：记录区自洽校验失败（%s），拒绝写入'):format(t.name, magic, tostring(shape)), true)
    return
  end
  state.verified[t] = true

  if not known then
    dump(('%s_%X.header.txt'):format(t.name, magic),
      ('magic=0x%X\nversion=%d\ntype=0x%08X\nsize=%d\ncount=%d\n离线镜像条数=%d\n记录尺寸=%d\n记录区字节=%d\n')
      :format(magic, u32_at(header, 4), u32_at(header, 8), u32_at(header, 12),
              count, t.want_count, t.rec_size, count * t.rec_size))
    if count ~= t.want_count then
      report(('%s @0x%X：条数 %d（离线镜像 %d，%+d）；自洽校验通过 eff3=%d eff4=%d 不同type=%d')
        :format(t.name, magic, count, t.want_count, count - t.want_count,
                shape.eff3, shape.eff4, shape.distinct), true)
    end
  end

  -- 收集待改记录
  local hits = {}
  for i = 0, count - 1 do
    local v = u32_at(data, i * t.rec_size + t.field_off)
    if v and SOURCE_VALUES[v] then
      hits[#hits + 1] = { i = i, from = v, type = u32_at(data, i * t.rec_size + t.type_off) }
    end
  end

  if #hits == 0 then
    state.patched[magic] = { t = t, count = count, done = true }
    note_hot(magic)
    state.round_hits = (state.round_hits or 0) + 1
    refresh_done()
    if not known then
      report(('%s @0x%X（%s）：已无 3/4，无需写入'):format(t.name, magic, t.label))
    end
    return
  end

  -- 写入前备份 + 诊断 + 落盘目标清单
  --   诊断转储默认关闭：整表 hex 要跑几十万次 string.format，是明确的卡顿源
  if DIAG then
    dump(('%s_%X.before.hex'):format(t.name, magic), hex(data))
    if not state.dumped[magic] then
      state.dumped[magic] = true
      pcall(dump_diag, magic, t, data, count, shape)
    end
  end
  do
    local lines = { ('# %s @0x%X  count=%d rec=%d field+%d  共 %d 条待改')
      :format(t.name, magic, count, t.rec_size, t.field_off, #hits) }
    for _, h in ipairs(hits) do
      lines[#lines + 1] = ('index=%-4s type=%-6s %d -> %d')
        :format(tostring(h.i), tostring(h.type), h.from, TARGET_VALUE)
    end
    dump(('%s_%X.targets.txt'):format(t.name, magic), table.concat(lines, '\n') .. '\n')
  end

  local target = encode_u32(TARGET_VALUE)
  local wrote, failed, addrs = 0, nil, {}
  for _, h in ipairs(hits) do
    local addr = base + h.i * t.rec_size + t.field_off
    if not write_bytes(addr, target, 4) then
      failed = ('记录 %d：写入失败'):format(h.i)
      break
    end
    addrs[#addrs + 1] = addr
    wrote = wrote + 1
  end

  if failed then
    report(('%s @0x%X：写入中断 —— %s（已写 %d/%d）')
      :format(t.name, magic, failed, wrote, #hits), true)
    return
  end

  -- 回读逐条复核
  local back = api.read(base, total)
  local bad = 0
  if back and #back == total then
    for _, h in ipairs(hits) do
      if u32_at(back, h.i * t.rec_size + t.field_off) ~= TARGET_VALUE then bad = bad + 1 end
    end
  else
    bad = -1
  end
  if bad ~= 0 then
    report(('%s @0x%X：回读校验失败（%s），本次改动不可信')
      :format(t.name, magic, bad < 0 and '读取失败' or (bad .. ' 条不符')), true)
    return
  end

  if DIAG then dump(('%s_%X.after.hex'):format(t.name, magic), hex(back)) end

  -- 记录已写入的字段地址：复查只读这几个 4 字节，不再整表重读
  for _, addr in ipairs(addrs) do
    state.slots[addr] = { expect = target, magic = magic, t = t }
  end
  state.patched[magic] = { t = t, count = count, done = true, wrote = wrote }
  note_hot(magic)
  state.round_hits = (state.round_hits or 0) + 1
  refresh_done()
  state.changed = state.changed + 1
  state.wrote = state.wrote + wrote

  report(('%s @0x%X（%s）：%d 条 3/4 → %s，已回读验证通过')
    :format(t.name, magic, t.label, wrote, TARGET_LABEL), true)
end

-- ===========================================================================
-- 调度：全量搜索 / 维护窗口 / 兜底全量
-- ===========================================================================
local started = false

-- 已知表副本的「观察窗口」（地址 ±WINDOW_MARGIN），重叠的合并。
-- 维护阶段只扫这几百 KB，比全量几 GB 便宜 4~5 个数量级。
local function collect_windows()
  local list = {}
  for magic, rec in pairs(state.patched) do
    local total = BASE_OFF + (rec.count or 0) * rec.t.rec_size
    local base = magic - WINDOW_MARGIN
    if base < 0x10000 then base = 0x10000 end
    list[#list + 1] = { base = base, size = total + WINDOW_MARGIN * 2 }
  end
  table.sort(list, function(a, b) return a.base < b.base end)
  local out = {}
  for i = 1, #list do
    local w = list[i]
    local last = out[#out]
    if last and w.base <= last.base + last.size then
      local stop = w.base + w.size
      if stop > last.base + last.size then last.size = stop - last.base end
    else
      out[#out + 1] = { base = w.base, size = w.size }
    end
  end
  return out
end

-- 热区列表（合并重叠）
local function collect_hot()
  local list = {}
  for _, r in pairs(state.hot) do list[#list + 1] = { base = r.base, size = r.size } end
  table.sort(list, function(a, b) return a.base < b.base end)
  local out = {}
  for i = 1, #list do
    local w = list[i]
    local last = out[#out]
    if last and w.base <= last.base + last.size then
      local stop = w.base + w.size
      if stop > last.base + last.size then last.size = stop - last.base end
    else
      out[#out + 1] = { base = w.base, size = w.size }
    end
  end
  return out
end

local function begin_scan(kind)
  if kind == 'window' then
    state.regions = collect_windows()
  elseif kind == 'hot' then
    state.regions = collect_hot()
  else
    -- ★ 必须重新收集：游戏会把表加载到新分配的区块里
    state.regions = api.regions()
    state.rounds = (state.rounds or 0) + 1
  end
  if not state.regions or #state.regions == 0 then
    state.regions = nil
    state.next_scan_frame = state.frame + 60
    return
  end
  state.region_index, state.region_offset, state.prev = 1, 0, ''
  state.scan_kind, state.round_hits = kind, 0
  if kind == 'full' and not state.all_done then
    local ms = (hurry_now() and SCAN_BUDGET_HURRY or SCAN_BUDGET) * 1000
    report(('第 %d 轮全量扫描开始：%d 个可读区域（预算 %d ms/帧）')
      :format(state.rounds, #state.regions, mfloor(ms)))
  end
end

-- 在 buffer 里找两张表的签名并逐条 apply；limit 非 nil 时只接受 found <= limit 的命中
local function scan_buffer(buffer, buffer_base, limit)
  for _, t in ipairs(TABLES) do
    local from = 1
    while true do
      local found = sfind(buffer, t.sig, from, true)
      if not found then break end
      if limit and found > limit then break end
      local abs = buffer_base + found - 1
      if not is_self_hit(abs) then
        local hit_ok, hit_err = pcall(apply, abs, t)
        if not hit_ok then
          state.errs = state.errs + 1
          if state.errs <= 5 then report('命中处理异常: ' .. tostring(hit_err), true) end
        end
      end
      from = found + 1
    end
  end
end

local function slice()
  local hurry = hurry_now()
  local deadline = os.clock() + (hurry and SCAN_BUDGET_HURRY or SCAN_BUDGET)
  while state.region_index <= #state.regions do
    local region = state.regions[state.region_index]
    while state.region_offset < region.size do
      if os.clock() > deadline then return false end
      local amount = mmin(hurry and SCAN_CHUNK_HURRY or SCAN_CHUNK,
                          region.size - state.region_offset)
      local chunk_base = region.base + state.region_offset
      local chunk = api.read(chunk_base, amount)
      if chunk then
        scan_buffer(chunk, chunk_base, nil)
        -- ★ 跨块命中：数据表可能横跨 chunk 边界。v1.4 用 prev..chunk 整块拼接
        --   （每块一次 MB 级字符串拷贝 + 整块二次搜索）；v1.5 只留「签名长度-1」
        --   字节的缝，在 ≤14 B 的小串里找那些"起始位置落在上一块里"的命中。
        local prev = state.prev or ''
        if #prev > 0 then
          scan_buffer(prev .. ssub(chunk, 1, SEAM_KEEP), chunk_base - #prev, #prev)
        end
        state.prev = ssub(chunk, -SEAM_KEEP)
      else
        state.prev = ''        -- 读失败必须清空，否则下一块的缝会算错
      end
      state.region_offset = state.region_offset + amount
    end
    state.region_index, state.region_offset, state.prev = state.region_index + 1, 0, ''
  end
  return true
end

local function end_round()
  local kind = state.scan_kind or 'full'
  local hits = state.round_hits or 0
  state.regions, state.round_hits = nil, 0

  if not state.all_done then
    if hits > 0 then
      state.empty_rounds = 0
      state.next_scan_frame = state.frame + 60
      report(('第 %d 轮结束：命中 %d 处，继续找表'):format(state.rounds, hits))
    else
      state.empty_rounds = (state.empty_rounds or 0) + 1
      local wait = BACKOFF[mmin(state.empty_rounds, #BACKOFF)]
      state.next_scan_frame = state.frame + mfloor(wait * 60)
      report(('第 %d 轮结束：未命中（空轮 %d，%d 秒后再试）')
        :format(state.rounds, state.empty_rounds, wait))
    end
    return
  end

  if kind == 'window' then
    if hits > 0 then report(('维护扫描：抓到 %d 处新副本'):format(hits), true) end
    state.next_scan_frame = state.frame + MAINTAIN_FRAMES
  elseif kind == 'hot' then
    if hits > 0 then report(('热区自检：抓到 %d 处新副本'):format(hits), true) end
  else
    if hits > 0 then
      state.full_interval = FULL_RESCAN_EVERY
      report(('全量扫描：本轮处理 %d 处，退避重置为 %d 分钟')
        :format(hits, mfloor(FULL_RESCAN_EVERY / 3600)), true)
    else
      state.full_interval = mmin((state.full_interval or FULL_RESCAN_EVERY) * 2, FULL_RESCAN_MAX)
      report(('兜底全量扫描：无新副本（下次间隔 %d 分钟）')
        :format(mfloor(state.full_interval / 3600)))
    end
    state.full_frame = state.frame + state.full_interval
    state.next_scan_frame = state.frame + MAINTAIN_FRAMES
  end
end

-- 复查：只读已写入的 4 字节地址（原来是整表重读 + 逐条校验）
local function recheck()
  local live, fixed = 0, 0
  local bad = nil
  for address, info in pairs(state.slots) do
    local cur = api.read(address, 4)
    if cur == info.expect then
      live = live + 1
    else
      local v = cur and u32_at(cur, 0) or nil
      if v and SOURCE_VALUES[v] then
        -- 被游戏写回 3/4 → 重写一次
        if write_bytes(address, info.expect, 4) then
          fixed = fixed + 1
          live  = live + 1
        else
          state.slots[address] = nil
          bad = bad or {}; bad[info.magic] = true
        end
      else
        state.slots[address] = nil
        bad = bad or {}; bad[info.magic] = true
        report(('复查：0x%X 的值变成 %s（既非目标也非 3/4），丢弃')
          :format(address, cur and hex(cur) or 'nil'), true)
      end
    end
  end
  if fixed > 0 then
    -- 游戏正在回写 → 说明维护节奏被打到，退避重置，兜底回到基准频率
    state.full_interval = FULL_RESCAN_EVERY
    state.full_frame    = state.frame + FULL_RESCAN_EVERY
    report(('复查：重写被冲掉的补丁 %d 处（兜底间隔重置为 %d 分钟）')
      :format(fixed, mfloor(FULL_RESCAN_EVERY / 3600)), true)
  end
  if bad then
    local n = 0
    for magic in pairs(bad) do
      if state.patched[magic] then state.patched[magic] = nil; n = n + 1 end
    end
    if n > 0 then
      refresh_done()          -- 可能把 all_done 打回 false
      state.empty_rounds = 0
      state.next_scan_frame = state.frame + 30
      report(('复查：%d 张表的地址已失效（表被释放/换图），安排重扫'):format(n), true)
    end
  end

  -- ★ 稳定性判定：连续 QUIET_AFTER_CHECKS 次复查都干干净净 → 进入静默
  if fixed > 0 or bad then
    state.stable_checks = 0
    if state.quiet then
      state.quiet = false
      state.next_scan_frame = state.frame + 30
      report('复查发现异常 → 退出静默，恢复扫描', true)
    end
  else
    state.stable_checks = (state.stable_checks or 0) + 1
    if QUIET_MODE and state.all_done and not state.quiet
       and state.stable_checks >= QUIET_AFTER_CHECKS then
      state.quiet = true
      state.regions = nil
      local n = 0
      for _ in pairs(state.slots) do n = n + 1 end
      report(('已确认生效：连续 %d 次复查无异常 → 进入静默，停止一切扫描；'
        .. '只保留 %d 个地址 × 4 字节的复查（约 %d 字节/秒）')
        :format(QUIET_AFTER_CHECKS, n, mfloor(n * 4 * 60 / RECHECK_EVERY)), true)
    end
  end
end

-- ===========================================================================
-- 一次性模式（v1.5）：写完就停 + 金丝雀
-- ===========================================================================
-- 只读复查：已写入的 108 个地址 × 4 字节（不是整表）。
--   rewrite = true 时顺手补写那些被游戏写回 3/4 的地址。
local function verify_slots(rewrite)
  local live, missing, rewrote = 0, 0, 0
  for address, info in pairs(state.slots) do
    local cur = api.read(address, 4)
    if cur == info.expect then
      live = live + 1
    elseif rewrite and cur and SOURCE_VALUES[u32_at(cur, 0)] then
      if write_bytes(address, info.expect, 4) then
        live, rewrote = live + 1, rewrote + 1
      else
        missing = missing + 1
      end
    else
      missing = missing + 1
    end
  end
  return live, missing, rewrote
end

-- 一次性模式收尾：再确认一遍全部地址，然后从此不再扫描
local function one_shot_finish()
  state.regions = nil
  local slots = 0
  for _ in pairs(state.slots) do slots = slots + 1 end
  local _, missing = verify_slots(false)
  if missing > 0 or slots == 0 then
    state.oneshot_disabled = true
    state.next_scan_frame = state.frame + 30
    report(('一次性写入未能确认（%d/%d 个地址不是目标值）→ 退回维护式调度，继续复查/重扫')
      :format(missing, slots), true)
    return
  end
  state.finished = true
  local tail
  if WATCHDOG_EVERY > 0 then
    tail = ('（金丝雀：每 %d 秒只读这 %d 个地址）'):format(mfloor(WATCHDOG_EVERY / 60), slots)
  else
    tail = '（金丝雀已关闭：之后不做任何事）'
  end
  if SCAN.api and not SCAN.gave_up then
    report(('已交给 HD2Scanner：%d 张表 / %d 个地址全部命中；本体不再扫内存，'
      .. '只在 Scanner 报出新副本或金丝雀发现异常时动手%s')
      :format(resolved_tables(), slots, tail), true)
  else
    report(('一次性写入完成：%d 张表 / %d 个地址全部命中，扫描全部停止%s')
      :format(resolved_tables(), slots, tail), true)
  end
end

-- 金丝雀：一次性模式下唯一的常驻开销（默认每次 432 字节）
local function canary()
  local _, missing, rewrote = verify_slots(true)
  if rewrote > 0 then
    report(('金丝雀：补写被冲掉的 %d 处（游戏在把值写回 3/4）'):format(rewrote), true)
  end
  if missing > 0 then
    state.finished, state.oneshot_disabled = false, true
    state.quiet, state.stable_checks, state.empty_rounds = false, 0, 0
    state.next_scan_frame = state.frame + 1
    report(('金丝雀：%d 个地址已失效（表被释放/换图）→ 退出一次性模式，恢复维护式调度')
      :format(missing), true)
  end
end

-- 手动重新写入一次（一次性模式的人工兜底）：清掉「已完成」状态、重走启动扫描。
--   换图后如果发现大型穿刺特效回来了，调用它重新定位/重写两张表。
rawset(_G, 'HD2_NoLargePiercing_Rescan', function()
  state.finished, state.oneshot_disabled, state.deadline_hit = false, false, false
  state.patched, state.slots, state.verified = {}, {}, {}
  state.all_done, state.done_armed, state.round_hits = false, false, 0
  state.quiet, state.stable_checks, state.empty_rounds = false, 0, 0
  state.regions = nil
  state.deadline_frame = state.frame + ONE_SHOT_DEADLINE
  state.next_scan_frame = state.frame + 1
  state.manual_rounds = (state.manual_rounds or 0) + 1
  if SCAN.api and type(SCAN.api.declare_need) == 'function' then pcall(SCAN.api.declare_need) end
  report(('手动重新扫描（第 %d 次）：已清空已写入清单，重新定位两张表%s')
    :format(state.manual_rounds, SCAN.api and '（已催 Scanner 插队一轮）' or ''), true)
  return true
end)

-- ---------------------------------------------------------------- Scanner 前置
-- 懒接入：每 60 秒看一次 _G.HD2Scanner（addon 加载顺序不保证 Scanner 在前）
local function scanner_get()
  if SCAN.api then return SCAN.api end
  if SCAN.gave_up then return nil end
  local now = os.clock()
  if now < SCAN.retry_at then return nil end
  SCAN.retry_at = now + 60
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and tonumber(S.version) == 1
     and type(S.poll) == 'function' and type(S.request) == 'function' then
    SCAN.api = S
    SCAN.attached_at = state.frame
    for _, t in ipairs(TABLES) do
      pcall(S.request, t.type_hash, t.name)
    end
    if type(S.declare_need) == 'function' then pcall(S.declare_need) end   -- 0.5 秒插队一轮
    if state.regions and not state.all_done then
      state.regions = nil
      report('已接上 HD2Scanner（前置）：中止自带的扫描，找表改由 Scanner 提供', true)
    else
      report('已接上 HD2Scanner（前置）：找表交给 Scanner（urgent 一轮 ≈0.5 秒），本体不扫内存', true)
    end
    return S
  end
  if not SCAN.warned then
    SCAN.warned = true
    report('未发现 _G.HD2Scanner —— 回退到自带的一次性全量扫描（每 60 秒再看一次前置）', true)
  end
  return nil
end

-- 把 Scanner 广播的每一份副本都过一遍 apply()（已处理过的地址会立刻返回）
local function scanner_poll_apply()
  local S = SCAN.api
  if not S then return 0 end
  local n = 0
  for _, t in ipairs(TABLES) do
    local ok, snap = pcall(S.poll, t.type_hash)
    SCAN.polls = SCAN.polls + 1
    if ok and type(snap) == 'table' and type(snap.entries) == 'table' then
      for i = 1, #snap.entries do
        local e = snap.entries[i]
        if type(e) == 'table' and type(e.addr) == 'number' and e.addr > 0 then
          local ok2, err2 = pcall(apply, e.addr, t)
          if not ok2 then
            state.errs = state.errs + 1
            if state.errs <= 5 then report('Scanner 副本处理异常: ' .. tostring(err2), true) end
          else
            n = n + 1
          end
        end
      end
    end
  end
  SCAN.applied = SCAN.applied + n

  if state.all_done and not state.finished then one_shot_finish() end

  if state.finished and WATCHDOG_EVERY > 0 and state.frame % WATCHDOG_EVERY == 0 then
    local okc, errc = pcall(canary)
    if not okc then report('金丝雀异常: ' .. tostring(errc), true) end
  end

  -- Scanner 在，但一直广播不到这两张表 → 回退到自带扫描
  if not state.all_done and SCAN.attached_at
     and (state.frame - SCAN.attached_at) > SCANNER_GIVEUP_FRAMES then
    SCAN.gave_up = true
    report(('Scanner 在 %d 帧内没有广播到这两张表 → 回退到自带的一次性全量扫描')
      :format(SCANNER_GIVEUP_FRAMES), true)
  end
  return n
end

local function frame(dt)
  state.frame = state.frame + 1

  if not started then
    if state.frame < 120 then return end
    started = true
    state.next_scan_frame = state.frame
    state.deadline_frame = state.frame + ONE_SHOT_DEADLINE
    scanner_get()                      -- 前置在就接上（不在则记一次日志 + 60 秒后再看）
    if SCAN.api and not SCAN.gave_up then
      report(('已接上 HD2Scanner：3/4 → %s；找表交给 Scanner，本体不扫内存')
        :format(TARGET_LABEL), true)
    elseif ONE_SHOT and not state.oneshot_disabled then
      report(('一次性写入模式：3/4 → %s；启动时扫一遍（每帧 %d ms），写完即停')
        :format(TARGET_LABEL, mfloor(SCAN_BUDGET_HURRY * 1000)), true)
    else
      report(('目标 3/4 → %s；常态每帧预算 %d ms，打完前 %d ms')
        :format(TARGET_LABEL, mfloor(SCAN_BUDGET * 1000), mfloor(SCAN_BUDGET_HURRY * 1000)), true)
    end
  end

  -- 前置可能比我们后加载（addon 顺序不保证）→ 每帧探测；已接上时是空操作
  if not SCAN.api then scanner_get() end

  -- ★ 前置 HD2 Scanner 在 → 找表完全交给它（每帧只 poll 两下，成本≈0）
  if SCAN.api and not SCAN.gave_up then
    local okS, errS = pcall(scanner_poll_apply)
    if not okS then
      state.errs = state.errs + 1
      if state.errs <= 5 then report('Scanner 取表异常: ' .. tostring(errS), true) end
    end
    return
  end

  -- ★ 一次性模式（v1.5 默认）：两张表都写完 → 彻底停扫（只留金丝雀）。
  if state.finished then
    if WATCHDOG_EVERY > 0 and state.frame % WATCHDOG_EVERY == 0 then
      local okc, errc = pcall(canary)
      if not okc then report('金丝雀异常: ' .. tostring(errc), true) end
    end
    return
  end
  if ONE_SHOT and not state.oneshot_disabled then
    if state.all_done then one_shot_finish(); return end
    if not state.deadline_hit and state.frame >= (state.deadline_frame or 0) then
      state.deadline_hit, state.oneshot_disabled = true, true
      report(('一次性写入超时（%d 帧内只定位到 %d/%d 张表）→ 本次会话退回维护式调度，继续按退避重试')
        :format(ONE_SHOT_DEADLINE, resolved_tables(), #TABLES), true)
    end
  end

  if state.frame % RECHECK_EVERY == 0 then
    local ok1, err1 = pcall(recheck)
    if not ok1 then report('复查异常: ' .. tostring(err1), true) end
  end

  if state.regions then
    local ok2, finished = pcall(slice)
    if not ok2 then
      state.errs = state.errs + 1
      report('扫描异常: ' .. tostring(finished), true)
      state.regions = nil
      state.next_scan_frame = state.frame + 60
    elseif finished then
      end_round()
    end
    return
  end

  -- ★ 静默：注入已确认生效且稳定 → 不做任何扫描。
  --   QUIET_FALLBACK_FRAMES > 0 时保留一个极稀疏的兜底自检。
  if state.quiet then
    -- 静默期自检：默认只扫【热区】（便宜 ~100 倍）；每 QUIET_FULL_EVERY 轮
    -- 或热区为空时，才做一次真·全量兜底。
    if QUIET_FALLBACK_FRAMES > 0 and state.frame % QUIET_FALLBACK_FRAMES == 0 then
      state.hot_ticks = (state.hot_ticks or 0) + 1
      local hot = collect_hot()
      if #hot == 0 or (QUIET_FULL_EVERY > 0 and state.hot_ticks % QUIET_FULL_EVERY == 0) then
        begin_scan('full')
      else
        begin_scan('hot')
      end
    end
    return
  end

  if state.frame < (state.next_scan_frame or 0) then return end

  if not state.all_done then
    begin_scan('full')                       -- 还在找表：全量
  elseif state.frame >= (state.full_frame or 0) then
    begin_scan('full')                       -- 兜底全量
  else
    begin_scan('window')                     -- 维护：只扫已知表 ±32KB
  end
end

local previous = update
local function guarded(dt, ...)
  local ok4, why = pcall(frame, dt)
  if not ok4 then report('frame error: ' .. tostring(why)) end
  return ...
end

update = function(dt, ...)
  if previous then return guarded(dt, previous(dt, ...)) end
  guarded(dt)
end

local old_shutdown = shutdown
shutdown = function(...)
  if old_shutdown then return old_shutdown(...) end
end

report(('已加载：3/4 → %s（%s；等待第 120 帧开始扫描）')
  :format(TARGET_LABEL, ONE_SHOT and '一次性写入模式' or '维护式调度'), true)