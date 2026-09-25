-- HD2-Addon: mods/dsh/no_large_piercing_medium

-- ===========================================================================
--  No Large Piercing —— 命中特效等级 → 2 (HitEffectDamageType_PiercingMedium)
--
--  把两张设置表里「特效·伤害类型」为 3 或 4 的记录，全部改写为 2：
--     ProjectileSettings.effect_damage_type     (直击/弹道)  343 条 → 改 102 条
--     ExplosionSettings.hit_effect_damage_type  (爆炸)       413 条 → 改   4 条
--
--  枚举 HitEffectDamageType：
--     0 None              1 PiercingSmall    2 PiercingMedium  ★
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
--  ※ 与 mods/dsh/effect_grade_0 互斥，同一时间只能启用其中一个。
-- ===========================================================================

local MOD = 'mods/dsh/no_large_piercing_medium'
if rawget(_G, MOD) then return end

-- 两个变体互斥：都启用会互相覆盖，第二个直接退出
local owner = rawget(_G, 'HD2_NoLargePiercing_Owner')
if owner then
  print('[NoLargePiercingMedium] 检测到已加载的 ' .. tostring(owner) .. '，本实例退出（两个变体只能启用一个）')
  return
end

local state = {
  frame = 0, status = nil, rounds = 0, errs = 0,
  changed = 0, wrote = 0,
  patched = {},          -- [magic] = 表定义
  dumped  = {},          -- [magic] = DIAG 已导出
}
rawset(_G, MOD, state)
rawset(_G, 'HD2_NoLargePiercing_Owner', MOD)

-- ===========================================================================
-- 目标参数 —— 与 effect_grade_0 唯一的差异就在这里
-- ===========================================================================
local TARGET_VALUE  = 2
local TARGET_LABEL  = '2 (PiercingMedium)'
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
    local file = loader and loader.open_log and loader.open_log('NoLargePiercingMedium.log')
    if file then file:write(text); file:close() end
  end)
end

local function report(message, keep)
  if not keep and state.status == message then return end
  state.status = message
  print('[NoLargePiercingMedium] ' .. message)
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
      -- 只要"已提交 + 可读"（不要求可写：目标页通常是只读的，写入时再 unprotect）
      local readable = bit.band(protect, 0x100) == 0
        and (protect == 0x02 or protect == 0x04 or protect == 0x20
          or protect == 0x40 or protect == 0x80)
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
local function u32_at(bytes, offset)
  local a, b, c, d = bytes:byte(offset + 1, offset + 4)
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
local SCAN_CHUNK        = 1024 * 1024   -- 每次读 1 MB
local SCAN_OVERLAP      = 2048          -- 相邻块重叠，防止表跨边界漏检
local SCAN_BUDGET       = 0.008         -- 每帧最多 8ms CPU
local RECHECK_EVERY     = 600           -- 约 10 秒复查一次
local FULL_RESCAN_EVERY = 18000         -- 约 5 分钟重扫一次

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
local function verify_shape(t, data, count)
  local type_bad, aux_bad, eff_bad = 0, 0, 0
  local seen, distinct = {}, 0
  local eff3, eff4 = 0, 0
  for i = 0, count - 1 do
    local r = i * t.rec_size
    local ty  = u32_at(data, r + t.type_off)
    local aux = u32_at(data, r + t.aux_off)
    local ef  = u32_at(data, r + t.field_off)
    if not ty  or ty  > 4095 then type_bad = type_bad + 1 end
    if not aux or aux > 4095 then aux_bad  = aux_bad  + 1 end
    if not ef  or ef  > 31   then eff_bad  = eff_bad  + 1 end
    if ty and ty > 0 and seen[ty] == nil then seen[ty] = true; distinct = distinct + 1 end
    if ef == 3 then eff3 = eff3 + 1 elseif ef == 4 then eff4 = eff4 + 1 end
  end
  local tol = math.floor(count * 0.02)
  if type_bad > tol then return false, ('type 越界 %d/%d'):format(type_bad, count) end
  if aux_bad  > tol then return false, ('aux  越界 %d/%d'):format(aux_bad,  count) end
  if eff_bad  > tol then return false, ('特效字段越界 %d/%d'):format(eff_bad, count) end
  if distinct < count * 0.5 then return false, ('不同 type 太少 %d/%d'):format(distinct, count) end
  return true, { eff3 = eff3, eff4 = eff4, distinct = distinct }
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
local function apply(magic, t)
  -- 已处理过的表：仅在复查帧重新校验，省掉反复读 60~90 KB
  local known = state.patched[magic]
  if known and known.done and state.frame % RECHECK_EVERY ~= 0 then return end

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
  local shape_ok, shape = verify_shape(t, data, count)
  if not shape_ok then
    report(('%s @0x%X：记录区自洽校验失败（%s），拒绝写入'):format(t.name, magic, tostring(shape)), true)
    return
  end

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
    state.patched[magic] = { t = t, done = true }
    if not known then
      report(('%s @0x%X（%s）：已无 3/4，无需写入'):format(t.name, magic, t.label))
    end
    return
  end

  -- 写入前备份 + 诊断 + 落盘目标清单
  dump(('%s_%X.before.hex'):format(t.name, magic), hex(data))
  if not state.dumped[magic] then
    state.dumped[magic] = true
    pcall(dump_diag, magic, t, data, count, shape)
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
  local wrote, failed = 0, nil
  for _, h in ipairs(hits) do
    local addr = base + h.i * t.rec_size + t.field_off
    local old = api.unprotect(addr, 4)
    if not old then failed = ('记录 %d：VirtualProtect 失败'):format(h.i); break end
    local good = api.write(addr, target)
    api.reprotect(addr, 4, old)
    if not good then failed = ('记录 %d：WriteProcessMemory 失败'):format(h.i); break end
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

  dump(('%s_%X.after.hex'):format(t.name, magic), hex(back))

  state.patched[magic] = { t = t, done = true, wrote = wrote }
  state.changed = state.changed + 1
  state.wrote = state.wrote + wrote

  report(('%s @0x%X（%s）：%d 条 3/4 → %s，已回读验证通过')
    :format(t.name, magic, t.label, wrote, TARGET_LABEL), true)
end

-- ===========================================================================
-- 内存扫描（时间切片）
-- ===========================================================================
local regions, cursor, offset_in, started = nil, 1, 0, false

local function slice()
  local deadline = os.clock() + SCAN_BUDGET
  while cursor <= #regions do
    local region = regions[cursor]
    while offset_in < region.size do
      if os.clock() > deadline then return false end
      local amount = math.min(SCAN_CHUNK, region.size - offset_in)
      local chunk = api.read(region.base + offset_in, amount)
      if chunk then
        -- 与上一块尾部拼接：数据表可能横跨 chunk 边界，不拼就会整张漏掉
        local prev = state.prev or ''
        local window = prev .. chunk
        local window_base = region.base + offset_in - #prev
        for _, t in ipairs(TABLES) do
          local from = 1
          while true do
            local found = window:find(t.sig, from, true)
            if not found then break end
            local abs = window_base + found - 1
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
        state.prev = chunk:sub(-SCAN_OVERLAP)
      end
      offset_in = offset_in + amount
    end
    cursor, offset_in = cursor + 1, 0
    state.prev = ''
  end
  return true
end

local function recheck()
  local dead = nil
  for magic, rec in pairs(state.patched) do
    local good = pcall(apply, magic, rec.t)
    if not good then dead = dead or {}; dead[#dead + 1] = magic end
  end
  if dead then
    for _, m in ipairs(dead) do state.patched[m] = nil end
  end
end

local function frame(dt)
  state.frame = state.frame + 1

  if not started then
    if state.frame < 120 then return end
    started = true
    regions = api.regions()
    report(('扫描开始：%d 个可读区域；目标 ProjectileSettings/ExplosionSettings 的 3/4 → %s')
      :format(#regions, TARGET_LABEL), true)
  end

  if cursor <= #regions then
    local ok2, finished = pcall(slice)
    if not ok2 then
      report('扫描异常: ' .. tostring(finished), true)
      cursor, offset_in = cursor + 1, 0
    elseif finished then
      cursor, offset_in = cursor + 1, 0
      if cursor > #regions then
        state.rounds = state.rounds + 1
        report(('第 %d 轮扫描结束：命中并处理 %d 张表，累计改写 %d 条')
          :format(state.rounds, state.changed, state.wrote), true)
      end
    end
    return
  end

  -- 扫描完成：定期复查已处理的表（地图重载可能把改动冲掉）
  if state.frame % RECHECK_EVERY == 0 then
    local ok3, err3 = pcall(recheck)
    if not ok3 then report('复查异常: ' .. tostring(err3), true) end
  end
  -- 定期重新全扫描，捕捉新加载的拷贝
  if state.frame % FULL_RESCAN_EVERY == 0 then
    cursor, offset_in = 1, 0
    state.prev = ''
    -- ★ 必须重新收集：游戏可能把表加载到新分配的区块里，
    --   沿用启动时的区域列表会整张漏掉
    regions = api.regions()
    report(('开始新一轮全量扫描（%d 个可读区域）'):format(#regions), true)
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

report(('已加载：3/4 → %s（等待第 120 帧开始扫描）'):format(TARGET_LABEL), true)