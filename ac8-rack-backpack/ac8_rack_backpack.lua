-- HD2-Addon: mods/dsh/ac8_rack_backpack

-- ===========================================================================
--  AC-8 机炮（战备）包架：把背包节点上的背包换成另一个实体
--
--    包架实体  = 0x5F41C4DCABE95421  weapon_rack_automatic_cannon
--    原背包    = 0xE60AE045E0090F4C  automatic_cannon_backpack（AC-8 机炮背包模型）
--    新背包    = 0x26BDDF070C31B275
--
--  表 HellpodRackComponentData：djb2 类型哈希 0xA98BB156
--    HellpodRackComponent = 8 x RackAttach[64] + 尾部字段
--    RackAttach：+0 u64 Item / +8 u32 Node / +12 Vec3 Offset / +24 Vec3 Rot /
--                +36/+40/+44 三个 u32 事件 / +48 u8 / +52 RackSide(u32) / +56 u8
--    AC-8 包架（旧版明文镜像实测，rec 4，568 字节）：
--      +0   机炮 0xA8CFFB316F0B5C5F  node 0x76C6D1E3  RackSide 2 (Left)
--      +64  背包 0xE60AE045E0090F4C  node 0xEE08A75F  RackSide 1 (Right)
--      +128 机炮（左侧第二份）
--      +192 背包（右侧第二份）
--      +556 SpawnPayloadSize = 2
--    → 旧背包哈希在整张表里只出现这 2 次；s1/s3 是同一件背包的两份，必须一起改。
--
--  v6（2026-09-24）—— 学 double_leveller（荡平）那套：
--    1) 定位表只认 LDLD + 版本 + 类型哈希，**不再校验 size / 索引条数 / 记录下标**
--       （这些随版本变，是 9/22 更新后三条 mod 静默失效的根因）；
--    2) 目标字段靠内容定位：在表数据里找"旧背包哈希"，再用
--       "命中点往前 64 / 192 字节处必须是 AC-8 机炮本体" 这个上下文确认，
--       因此完全不依赖记录大小与索引布局；
--    3) 一轮里扫到几张表副本就全打（"命中第一个就收工" = 更新后会翻车的坑）；
--    4) 复查改成逐个字段直读 8 字节，掉一份补一份；空轮指数退避。
--
--  红线：任何校验不符就只记日志、绝不写入。所有 >2^53 的哈希一律用
--        "十六进制文本 → 字节串" 构造，绝不过 Lua number。
--  设计说明：docs/AC8-Rack-Backpack-v6-DESIGN.md
-- ===========================================================================

local MOD = 'mods/dsh/ac8_rack_backpack'
if rawget(_G, MOD) then return end
rawset(_G, MOD, {
  frame = 0, status = 'starting', phase = 'scanning',
  writes = 0, refusals = 0, errs = 0, rounds = 0, empty_rounds = 0,
})
local state = rawget(_G, MOD)
state.slots = {}          -- 已写入的字段地址（绝对地址）→ 存活表
state.tables = {}         -- 见过的表副本（magic 地址）→ 维护扫描的观察窗口中心
state.next_scan_frame = 0
state.maintain_frame = 0
state.full_frame = 0
state.gave_up = false
state.seen = {}

-- ---------------------------------------------------------------- 日志
-- loader 的 open_log 是 "w" 模式（每次打开都截断），所以累积后一次性落盘；
-- 关键消息立刻落盘，另外每 60 帧周期性落盘一次（SKILL 6.10）。
local loghist = {}
local function flush_log()
  if #loghist == 0 then return end
  local text = table.concat(loghist, '\n') .. '\n'
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local file = loader and loader.open_log and loader.open_log('AC8RackBackpack.log')
    if file then file:write(text); file:close() end
  end)
end

local function report(message, keep)
  if not keep and state.status == message then return end
  state.status = message
  print('[AC8RackBackpack] ' .. message)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, message)
  flush_log()
end

local function dump(name, text)
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local file = loader and loader.open_log and loader.open_log(name)
    if file then file:write(text); file:close() end
  end)
end

-- ---------------------------------------------------------------- ffi / bit
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
    } AC8_MEMORY_BASIC_INFORMATION;
    void   *GetModuleHandleA(const char *name);
    void   *GetCurrentProcess(void);
    int     ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
    int     WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
    int     VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
    size_t  VirtualQuery(const void *address, AC8_MEMORY_BASIC_INFORMATION *info, size_t length);
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
    local size  = #bytes
    local count = ffi.new('size_t[1]')
    local rc = kernel.WriteProcessMemory(process, ffi.cast('void *', address),
                                         ffi.cast('const void *', bytes), size, count)
    if rc == 0 then return false end
    return tonumber(count[0]) == size
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
    local info = ffi.new('AC8_MEMORY_BASIC_INFORMATION[1]')
    local address, result = 0, {}
    while address < 0x7FFFFFFFFFFF do
      if kernel.VirtualQuery(ffi.cast('const void *', address), info, ffi.sizeof(info)) == 0 then break end
      local base  = tonumber(info[0].BaseAddress)
      local size  = tonumber(info[0].RegionSize)
      if not size or size <= 0 then break end
      local protect   = tonumber(info[0].Protect)
      local committed = tonumber(info[0].State) == 0x1000
      local readable  = bit.band(protect, 0x100) == 0
        and (protect == 0x04 or protect == 0x20 or protect == 0x40 or protect == 0x02 or protect == 0x80 or protect == 0x08)
      if committed and readable then
        result[#result + 1] = { base = base, size = size }
      end
      address = base + size
    end
    return result
  end

  return api
end)

if not ok then
  report('disabled: ' .. tostring(api))
  return
end

-- ---------------------------------------------------------------- 环境闸门
-- SKILL 6.18：loader 版本不够时 addon 照样会被加载、照样会跑，只是安静地做不成事，
-- 用户看到的是"一直 working"，真正的原因永远不会出现在日志里。所以先问一句。
-- loader v16 在 _G.CowboyBingusModLoader 里放 { api = 1, version = 16, modules = {} }。
local ENV = { api = nil, version = nil, source = 'n/a' }
do
  local l = rawget(_G, 'CowboyBingusModLoader')
  if type(l) == 'table' then
    ENV.api     = tonumber(l.api)
    ENV.version = tonumber(l.version)
    ENV.source  = 'global'
  end
  if not ENV.api then
    -- 退化：解析共享日志首行 "Bingus Shared Loader loader-v16; API 1"
    pcall(function()
      local base = os.getenv('LOCALAPPDATA')
      local f = base and io.open(base .. '/CowboyBingus/Helldivers2/Logs/BingusSharedLoader.log', 'r')
      if f then
        local first = f:read('*l') or ''
        f:close()
        local v, a = first:match('loader%-v(%d+);%s*API%s*(%d+)')
        ENV.version, ENV.api = tonumber(v), tonumber(a)
        if ENV.api then ENV.source = 'log' end
      end
    end)
  end
end

if ENV.api and ENV.api < 1 then
  local msg = ('FAILED - 前置 Bingus Shared Loader 太旧：API %s (loader v%s)；本 mod 需要 API 1（loader v15+）'):format(
    tostring(ENV.api), tostring(ENV.version))
  dump('AC8RackBackpack_STATUS.log', msg .. '\n')
  report(msg, true)
  return
end

-- ---------------------------------------------------------------- 工具
-- 十六进制文本 -> 字节串（按文本顺序）
local function hex_be(hex)
  local out = {}
  for i = 1, #hex, 2 do
    out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return table.concat(out)
end

-- 十六进制文本（大端写法，如 'A98BB156'）-> 小端字节串
local function hex_le(hex)
  local out = {}
  for i = #hex - 1, 1, -2 do
    out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return table.concat(out)
end

local function decode32(bytes, offset)
  local a, b, c, d = bytes:byte(offset + 1, offset + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

local function hex(bytes)
  return (bytes:gsub('.', function(c) return string.format('%02X', c:byte()) end))
end

-- ---------------------------------------------------------------- 常量
-- 稳定性分级：LDLD / version / typeHash 稳定；size、索引条数、记录步长、
-- 记录下标都会随版本变 → 一律不当指纹。记录内的相对偏移属于"内容布局"，稳定。
local MAGIC         = 'LDLD'
local SIGNATURE     = MAGIC .. string.char(1, 0, 0, 0) .. hex_le('A98BB156')
local RACK_TYPE     = 0xA98BB156              -- djb2('HellpodRackComponentData')
local DATA_OFF      = 24
local MIN_SIZE      = 1024                    -- 只做合理区间检查
local MAX_SIZE      = 4194304
local DATA_CAP      = 262144                  -- 单次读取上限
local SLOT0_ITEM    = hex_le('A8CFFB316F0B5C5F')   -- AC-8 机炮本体（s0 的 Item）
local OLD_ITEM      = hex_le('E60AE045E0090F4C')   -- 原背包
local NEW_ITEM      = hex_le('26BDDF070C31B275')   -- 新背包
-- 命中点 → 记录起点 的候选。**大偏移优先**：包架布局是 机炮,背包,机炮,背包，
-- 第二份背包(at=rec+192)用 +192 反推才落到记录真正的 +0；若先试 +64，会先撞上
-- rec+128 的机炮也同样"通过"，日志里的记录下标就会报错（写入地址不受影响）。
local SLOT_CAND     = { 192, 64 }
local SPAWN_OFF     = 556                     -- 仅用于日志
local IDX_HINT      = 140                     -- 仅用于日志（报告记录下标提示）
local REC_SIZE_HINT = 568                     -- 仅用于日志
-- SKILL 6.17：patched 之后持续维护 —— 先扫观察窗口，再全量兜底
local MAINTAIN_FRAMES    = 1800               -- 30 秒一次"已知副本 ±32KB"扫描
local FULL_RESCAN_FRAMES = 36000              -- 10 分钟一次全量兜底

-- ---------------------------------------------------------------- 自我命中规避
-- SKILL 6.2：模式串活在 Lua 堆里，扫内存必然命中自己 → 先取自身地址，命中就跳过
local function string_addr(s)
  local ok2, p = pcall(function()
    return tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', s)))
  end)
  if ok2 and p and p ~= 0 then return p end
  return nil
end

local SELF_ADDRS = {}
for _, s in ipairs({ SIGNATURE, OLD_ITEM, NEW_ITEM, SLOT0_ITEM }) do
  local p = string_addr(s)
  if p then SELF_ADDRS[#SELF_ADDRS + 1] = p end
end

local function is_self_hit(address)
  for i = 1, #SELF_ADDRS do
    local d = address - SELF_ADDRS[i]
    if d > -4096 and d < 4096 then return true end
  end
  return false
end

-- ---------------------------------------------------------------- 定位
-- 表头四条：魔数 / 版本 / 类型哈希 / size 落在合理区间。size 不当指纹。
local function validate_table(magic)
  local head = api.read(magic, DATA_OFF)
  if not head then return nil end
  if head:sub(1, 4) ~= MAGIC then return nil end
  if decode32(head, 4) ~= 1 then return nil end
  if decode32(head, 8) ~= RACK_TYPE then return nil end
  local size = decode32(head, 12)
  if not size or size < MIN_SIZE or size > MAX_SIZE then return nil end
  return size
end

-- 命中点 at（0-based，相对数据区）→ 记录起点 rec：
-- 只要 at-64 或 at-192 处是 AC-8 机炮本体哈希，就说明这条命中在 AC-8 包架记录里。
local function find_record(data, at)
  for i = 1, #SLOT_CAND do
    local rec = at - SLOT_CAND[i]
    if rec >= 0 and rec + 8 <= #data and data:sub(rec + 1, rec + 8) == SLOT0_ITEM then
      return rec, SLOT_CAND[i]
    end
  end
  return nil
end

-- ---------------------------------------------------------------- 写入
local function write_item(address)
  local old = api.unprotect(address, 8)
  if not old then
    state.refusals = state.refusals + 1
    report(('VirtualProtect 失败，拒绝写入 0x%X'):format(address), true)
    return false
  end
  local wrote = api.write(address, NEW_ITEM)
  api.reprotect(address, 8, old)
  if not wrote then
    state.refusals = state.refusals + 1
    report(('WriteProcessMemory 失败 0x%X'):format(address), true)
    return false
  end
  if api.read(address, 8) ~= NEW_ITEM then
    state.refusals = state.refusals + 1
    report(('回读校验失败 0x%X'):format(address), true)
    return false
  end
  return true
end

-- 处理一张表副本：数据区里所有"旧背包"都换成"新背包"；
-- 已经是新背包的记为 already（幂等）；上下文不符的记为 foreign（不看）。
local function apply(magic)
  local size = validate_table(magic)
  if not size then return end
  local want = size
  if want > DATA_CAP then want = DATA_CAP end
  local data = api.read(magic + DATA_OFF, want)
  if not data then return end

  local patched, already, foreign = 0, 0, 0
  local first = nil

  local function pass(pattern, is_new)
    local from = 1
    while true do
      local at1 = data:find(pattern, from, true)
      if not at1 then break end
      from = at1 + 1
      local at = at1 - 1
      local rec, slot = find_record(data, at)
      if not rec then
        foreign = foreign + 1
      elseif is_new then
        state.slots[magic + DATA_OFF + at] = true
        already = already + 1
      else
        local address = magic + DATA_OFF + at
        if write_item(address) then
          state.slots[address] = true
          state.writes = state.writes + 1
          patched = patched + 1
          if not first then first = { rec = rec, slot = slot, size = size, at = at } end
        end
      end
    end
  end

  pass(OLD_ITEM, false)
  pass(NEW_ITEM, true)

  if patched > 0 and first then
    local idx = first.rec - IDX_HINT * 16
    local hint = 'n/a'
    if idx >= 0 and idx % REC_SIZE_HINT == 0 then hint = tostring(idx / REC_SIZE_HINT) end
    local spawn, node = 'n/a', 'n/a'
    local s = data:sub(first.rec + SPAWN_OFF + 1, first.rec + SPAWN_OFF + 4)
    if #s == 4 then spawn = tostring(decode32(s, 0)) end
    local ns = data:sub(first.rec + first.slot + 9, first.rec + first.slot + 12)
    if #ns == 4 then node = string.format('0x%08X', decode32(ns, 0)) end
    dump('AC8RackBackpack_Patch.log', table.concat({
      ('表 0x%X  size=%d  记录起点 +%d  槽位 +%d  Node=%s  SpawnPayloadSize=%s'):format(
        magic, size, first.rec, first.slot, node, spawn),
      ('写入前 该记录前 88 字节: %s'):format(hex(data:sub(first.rec + 1, first.rec + 88))),
    }, '\n') .. '\n')
    state.round_hits = (state.round_hits or 0) + 1
    state.tables[magic] = true
    state.phase = 'patched'
    if state.maintain_frame == 0 then state.maintain_frame = state.frame + MAINTAIN_FRAMES end
    if state.full_frame == 0 then state.full_frame = state.frame + FULL_RESCAN_FRAMES end
    report(('已替换：表 0x%X size=%d 记录(下标提示 %s, Node=%s, SpawnPayloadSize=%s) 槽位 +%d，本轮写了 %d 处'):format(
      magic, size, hint, node, spawn, first.slot, patched), true)
  elseif already > 0 then
    state.round_hits = (state.round_hits or 0) + 1
    state.tables[magic] = true
    state.phase = 'patched'
    if state.maintain_frame == 0 then state.maintain_frame = state.frame + MAINTAIN_FRAMES end
    if state.full_frame == 0 then state.full_frame = state.frame + FULL_RESCAN_FRAMES end
    report(('表 0x%X 已是目标状态（%d 处新背包），无需再写'):format(magic, already))
  elseif foreign > 0 then
    report(('表 0x%X 里有 %d 处同款旧背包哈希，但上下文不是 AC-8 包架，已跳过'):format(magic, foreign), true)
  end

  if size > DATA_CAP then
    report(('注意：表 0x%X 声明 size=%d 超过单次读取上限 %d，只检查了前 %d 字节'):format(
      magic, size, DATA_CAP, DATA_CAP), true)
  end
end

-- ---------------------------------------------------------------- 复查
local function write_status()
  local n = 0
  for _ in pairs(state.slots) do n = n + 1 end
  local first
  if n > 0 then
    first = ('OK - 补丁生效中（%d 处）'):format(n)
  elseif state.gave_up then
    first = 'FAILED - 目标表始终没出现（看 Census.log）'
  else
    first = 'WORKING - 扫描中'
  end
  local copies = 0
  for _ in pairs(state.tables) do copies = copies + 1 end
  dump('AC8RackBackpack_STATUS.log', table.concat({
    first,
    'revision=ac8-rack-backpack-v6.2',
    'phase=' .. tostring(state.phase),
    'updated=' .. os.date('%Y-%m-%d %H:%M:%S'),
    ('前置 = Bingus Shared Loader loader-v%s / API %s（来源 %s）'):format(
      tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)),
    ('表 = HellpodRackComponentData 0x%08X（内容锚点定位，无布局常量）'):format(RACK_TYPE),
    ('已写=%d 处  拒绝=%d  轮次=%d  空轮=%d  帧=%d'):format(
      state.writes, state.refusals, state.rounds, state.empty_rounds, state.frame),
    ('内存里的表副本 = %d 处   观察窗口扫描 = 每 %d 秒   全量兜底 = 每 %d 分钟'):format(
      copies, MAINTAIN_FRAMES / 60, FULL_RESCAN_FRAMES / 3600),
  }, '\n') .. '\n')
end

local function recheck()
  local live, fixed, dropped = 0, 0, 0
  for address in pairs(state.slots) do
    local cur = api.read(address, 8)
    if cur == NEW_ITEM then
      live = live + 1
    elseif cur == OLD_ITEM then
      if write_item(address) then
        state.writes = state.writes + 1
        live, fixed = live + 1, fixed + 1
      else
        state.slots[address] = nil
        dropped = dropped + 1
      end
    else
      state.slots[address] = nil
      dropped = dropped + 1
    end
  end
  if fixed > 0 then report(('复查：重写被冲掉的补丁 %d 处'):format(fixed), true) end
  if dropped > 0 then report(('复查：丢弃失效地址 %d 处'):format(dropped), true) end
  if live == 0 then
    state.slots = {}
    state.tables = {}
    state.maintain_frame = 0
    state.full_frame = 0
    state.phase = 'scanning'
    state.regions = nil
    state.empty_rounds = 0
    state.next_scan_frame = state.frame
    report('复查：已无存活补丁，重新开始全量扫描', true)
  end
end

-- ---------------------------------------------------------------- 普查
-- SKILL 第 1 步：枚举内存里所有 LDLD 块（地址/版本/类型哈希/size），落盘供离线比对
local census, census_hits, census_bytes, census_regions = {}, 0, 0, 0

local function census_note(address)
  local hdr = api.read(address, 16)
  if not hdr or hdr:sub(1, 4) ~= MAGIC then return end
  if decode32(hdr, 4) ~= 1 then return end
  local typ  = decode32(hdr, 8)
  local size = decode32(hdr, 12)
  local key  = string.format('%08X', typ)
  census_hits = census_hits + 1
  local e = census[key]
  if e then e.count = e.count + 1
  else census[key] = { count = 1, addr = address, size = size } end
end

local function census_scan(chunk, chunk_base)
  census_bytes   = census_bytes + #chunk
  census_regions = census_regions + 1
  local from = 1
  while true do
    local f = chunk:find(MAGIC, from, true)
    if not f then break end
    pcall(census_note, chunk_base + f - 1)
    from = f + 1
  end
end

local function census_report()
  local keys = {}
  for k in pairs(census) do keys[#keys + 1] = k end
  table.sort(keys)
  local target = string.format('%08X', RACK_TYPE)
  local out = {}
  out[#out + 1] = ('[frame %d] census：已扫 %d 个区域 / %.1f MB，LDLD 块 %d 个 / %d 种类型'):format(
    state.frame, census_regions, census_bytes / 1048576, census_hits, #keys)
  local e = census[target]
  if e then
    out[#out + 1] = ('  目标表 %s：出现 %d 份，size=%d（合理区间 %d~%d）%s'):format(
      target, e.count, e.size, MIN_SIZE, MAX_SIZE,
      (e.size >= MIN_SIZE and e.size <= MAX_SIZE) and ' <<< 在区间内' or ' (size 异常!)')
  else
    out[#out + 1] = ('  目标表 %s：内存里没找到 <<< 表还没加载（在飞船里？）'):format(target)
  end
  out[#out + 1] = '  内存里全部 LDLD 类型: ' .. table.concat(keys, ' ')
  dump('Census.log', table.concat(out, '\n') .. '\n')
  for _, line in ipairs(out) do report(line) end
end

-- ---------------------------------------------------------------- 扫描驱动
-- SKILL 6.14 + 6.17：
--   * 一轮里扫到几张表副本就全打（命中第一个就收工 = 扫描顺序相关 = 更新后翻车）；
--   * 空轮指数退避，8 轮放弃，留 census，别一直空烧帧。
local SCAN_CHUNK   = 256 * 1024
local SCAN_OVERLAP = 2048
local SCAN_BUDGET  = 0.002
local BACKOFF      = { 2, 4, 8, 16, 30, 60, 120, 300 }
local MAX_EMPTY    = 8

-- SKILL 6.17：同一张表在内存里有几十份，而且进任务/换图时会**再加载一份新的**。
-- "只打第一份" = 一开始生效、过一会儿就失效，而复查还会说一切正常。
-- 所以 patched 之后要持续维护：先扫"已知表副本地址 ±32KB"的观察窗口（几 MB，
-- 比全地址空间便宜两个数量级），再定期全量兜底。
local function collect_regions()
  local all = api.regions()
  local list = {}
  for i = 1, #all do
    if all[i].size >= 65536 then list[#list + 1] = all[i] end
  end
  table.sort(list, function(a, b) return a.size > b.size end)
  return list
end

-- 已知表副本 ±32KB → 合并重叠 → 观察窗口列表
local function collect_windows()
  local out = {}
  for address in pairs(state.tables) do
    local base = address - 32768
    if base < 65536 then base = 65536 end
    out[#out + 1] = { base = base, size = 98304 }
  end
  table.sort(out, function(a, b) return a.base < b.base end)
  local merged = {}
  for i = 1, #out do
    local last = merged[#merged]
    if last and out[i].base <= last.base + last.size then
      local stop = out[i].base + out[i].size
      if stop > last.base + last.size then last.size = stop - last.base end
    else
      merged[#merged + 1] = { base = out[i].base, size = out[i].size }
    end
  end
  return merged
end

local function begin_scan(kind)
  state.scan_kind = kind
  if kind == 'window' then
    state.regions = collect_windows()
    state.window_count = #state.regions
  else
    state.regions = collect_regions()
  end
  state.region_index  = 1
  state.region_offset = 0
  state.previous      = ''
  state.scanned       = 0
  state.seen          = {}
  state.round_hits    = 0
  state.rounds        = state.rounds + 1
  if kind == 'full' and state.phase ~= 'patched' then
    report(('第 %d 轮扫描开始：%d 个可读区域'):format(state.rounds, #state.regions), true)
  end
end

local function slice()
  local deadline = os.clock() + SCAN_BUDGET
  while state.region_index <= #state.regions do
    local region = state.regions[state.region_index]
    while state.region_offset < region.size do
      if os.clock() > deadline then return false end
      local remaining = region.size - state.region_offset
      local amount = SCAN_CHUNK
      if amount > remaining then amount = remaining end
      local buf = api.read(region.base + state.region_offset, amount)
      state.scanned = state.scanned + amount
      if buf then
        pcall(census_scan, buf, region.base + state.region_offset)
        local window_base = region.base + state.region_offset - #state.previous
        local window = state.previous .. buf
        local from = 1
        while true do
          local i = window:find(SIGNATURE, from, true)
          if not i then break end
          local abs = window_base + i - 1
          if not is_self_hit(abs) and not state.seen[abs] then
            state.seen[abs] = true
            -- 不能静默吞错：否则"扫不到"其实是"处理时抛错"
            local ok2, err = pcall(apply, abs)
            if not ok2 then
              state.errs = state.errs + 1
              if state.errs <= 3 then report('命中处理异常: ' .. tostring(err), true) end
            end
          end
          from = i + 1
        end
        state.previous = buf:sub(-SCAN_OVERLAP)
      else
        state.previous = ''
      end
      state.region_offset = state.region_offset + amount
    end
    state.region_index  = state.region_index + 1
    state.region_offset = 0
    state.previous      = ''
  end
  return true
end

local function end_round()
  local kind = state.scan_kind or 'full'
  state.regions = nil

  if (state.round_hits or 0) > 0 then
    state.empty_rounds = 0
    state.phase = 'patched'
    if kind == 'window' then
      local copies = 0
      for _ in pairs(state.tables) do copies = copies + 1 end
      report(('维护扫描：观察窗口 %d 个，内存里表副本 %d 处（本轮命中 %d）'):format(
        state.window_count or 0, copies, state.round_hits), true)
    elseif kind == 'full' then
      report(('第 %d 轮完成：命中（累计写入 %d 处）'):format(state.rounds, state.writes), true)
    end
  elseif kind == 'window' or state.phase == 'patched' then
    -- 维护/兜底扫描没抓到新副本：正常，不记账、不退避
    if kind == 'full' then
      report(('第 %d 轮兜底全量扫描：没有发现新副本'):format(state.rounds), true)
    end
  else
    state.empty_rounds = state.empty_rounds + 1
    local wait = BACKOFF[math.min(state.empty_rounds, #BACKOFF)]
    state.next_scan_frame = state.frame + math.floor(wait * 60)
    report(('第 %d 轮完成：未命中（空轮 %d/%d，%d 秒后再试）'):format(
      state.rounds, state.empty_rounds, MAX_EMPTY, wait))
    if state.empty_rounds >= MAX_EMPTY then
      state.gave_up = true
      state.phase = 'gave_up'
      report(('连续 %d 轮没找到目标表，停止扫描（Census.log 已落盘）'):format(MAX_EMPTY), true)
    end
  end
  write_status()
end

local function run_slice()
  local ok2, finished = pcall(slice)
  if not ok2 then
    state.errs = state.errs + 1
    if state.errs <= 3 then report('扫描异常: ' .. tostring(finished), true) end
    state.regions = nil
    state.next_scan_frame = state.frame + 60
    return
  end
  if finished then end_round() end
end

local function frame()
  state.frame = state.frame + 1
  if state.frame % 60 == 0 then flush_log() end

  -- 已生效：轻量复查 + 维护扫描 + 全量兜底
  if state.phase == 'patched' then
    if state.frame % 300 == 0 then
      recheck()
      write_status()
      if state.phase ~= 'patched' then return end   -- 复查把自己打回扫描
    end
    if not state.regions then
      if state.frame >= (state.full_frame or 0) then
        state.full_frame     = state.frame + FULL_RESCAN_FRAMES
        state.maintain_frame = state.frame + MAINTAIN_FRAMES
        begin_scan('full')
      elseif state.frame >= (state.maintain_frame or 0) then
        state.maintain_frame = state.frame + MAINTAIN_FRAMES
        begin_scan('window')
      end
    end
    if state.regions then run_slice() end
    return
  end

  if state.frame % 300 == 0 and census_regions > 0 then pcall(census_report) end
  if state.gave_up then return end
  if state.frame < (state.next_scan_frame or 0) then return end

  if not state.regions then
    if state.frame < 120 then return end
    begin_scan('full')
    return
  end
  run_slice()
end

-- ---------------------------------------------------------------- 挂载
local original_update = update
if type(original_update) == 'function' then
  update = function(...)
    local ok2, err = pcall(frame)
    if not ok2 then
      state.errs = state.errs + 1
      if state.errs <= 5 then report('frame error: ' .. tostring(err)) end
    end
    return original_update(...)
  end
else
  state.phase = 'no_update'
  report('全局 update 不可用，无法运行', true)
end

report(('已加载 v6.1（内容锚点定位 + 维护扫描）；前置 loader v%s / API %s（来源 %s）'):format(
  tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)))
