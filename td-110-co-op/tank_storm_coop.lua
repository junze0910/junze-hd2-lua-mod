-- HD2-Addon: mods/dsh/tank_storm_coop

-- ===========================================================================
--  更强调合作的 TD-110（暴风漩涡坦克 / tank_storm 0xB0C9FAF4AF8903F9）  v1.0
--
--  两处改动：
--
--  ① 激光武器（0xC36B5B37C058DBDD  tank_storm_laser）的水平射界：
--          TurretComponentData 记录 +28（下限）/ +32（上限）
--          从 -20.0 / +20.0  →  -180.0 / +180.0（全方位）
--     定位 = 在该表的索引区按实体哈希读出这条记录的 ID(recIdx，实测 28)。
--     射界是引擎**实时读**的值，所以什么时候打进去都生效。
--     另一条内容模板兜底：内存里凡是还带着 ±20 的那份炮塔记录（表外运行时副本），
--     若命中点 ±256 字节内能看到激光 owner 哈希，也一并改成 ±180。
--
--  ② 按位置替换两个挂载位上的**物品(item)**：
--          MountComponentData 的 TD-110 记录（实测 ID 123）
--            炮手位   (+24 项)  →  烟雾弹     4181046937756232139  0x3A061009AA31E9CB
--            驾驶员位 (+48 项)  →  激光指示器 14081448954912365533 0xC36B5B37C058DBDD
--      只写这两项的 8 字节；node 与其它字段一律不动。目标值"按位置写死"，
--      不依赖 +24 项原本是什么武器。
--
--  ⚠ 最重要的时序规则（实机踩过）：
--      MountComponentData 是**生成载具时读一次**的静态配置 —— 补丁必须**早于召唤载具**。
--      所以本 mod 没进任务前只在舰船上做便宜采样（12 个最大区域 × 8 MB，5 秒一轮），
--      一采样到 LDLD 表就立刻转"全量 + 抢时间"扫描（每帧 6 ms、先扫挂载表），
--      并在日志里打印 `挂载补丁已就绪：现在可以召唤 / 重新召唤载具了`。
--      → 进任务后等这一行出现，再召唤载具。
--      （对照：TurretComponentData 的射界是实时读的，不需要等。）
--
--  记录定位（零布局常量）：
--    · 索引区条目 16 字节 = (u64 实体哈希, u32 ID(recIdx), u32 pad)；ID 随构建漂移，运行时读。
--    · TD-110 挂载记录前 24 字节指纹 DE10DB4EA0E68AD5…（加特林 item + node0 + 槽0 残留）
--      在整块 dl_bin 里唯一；**只锚 node 不行**：TD-220 堡垒（0x16474112801385B6）的
--      槽0/槽1 node 与 TD-110 逐字节相同，全局 find 取第一处会改到 TD-220（真实踩坑）。
--      索引读不出来时才退回"烟雾位 node 0x79CC4582"锚点，并仍然做指纹复核。
--    · 表外副本：全内存按 24 字节指纹找同一条记录的其它副本，一并改（复核不过只记日志）。
--
--  ⚠ 互斥：与 mods/dsh/tank_storm_smoke_swap（TD-110 Better Driver Armament）都要改 +48，二选一。
--  ⚠ 诊断开关：MARKER_MODE = true 时只把炮手位 +24 换成"手操重机枪炮台"（看得见的对照组），
--     用来区分"改表没生效"和"生效了但看不见"。
-- ===========================================================================

local MOD = 'mods/dsh/tank_storm_coop'
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
state.yaw_sites = {}     -- 表外命中的"±20 炮塔模板"地址（已改 / 已是目标，供 CE 对照）
state.yaw_skip_sites = {}-- 同上但**没通过 owner 判据**：附近看不到激光 owner 哈希 → 跳过
state.rack_sites  = {}   -- 表外挂载记录副本：地址 -> 处理结果（written/target/refused）
state.mission_ready = false  -- 采样到任务数据（LDLD 表）之前，只做便宜采样，不做全量扫描

-- ---------------------------------------------------------------- 日志
-- loader 的 open_log 是 "w" 模式（每次打开都截断），所以累积后一次性落盘；
-- 关键消息立刻落盘，另外每 60 帧周期性落盘一次（SKILL 6.10）。
local loghist = {}
local function flush_log()
  if #loghist == 0 then return end
  local text = table.concat(loghist, '\n') .. '\n'
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local file = loader and loader.open_log and loader.open_log('TankStormCoop.log')
    if file then file:write(text); file:close() end
  end)
end

local function report(message, keep)
  if not keep and state.status == message then return end
  state.status = message
  print('[TankStormCoop] ' .. message)
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
      -- 低 8 位是保护类型，高位是 PAGE_GUARD(0x100)/NOCACHE(0x200)/WRITECOMBINE(0x400) 修饰。
      -- 旧版要求 protect **完全等于**某个值 → 带修饰位的可读区域被整段漏掉。
      local proto     = bit.band(protect, 0xFF)
      local readable  = bit.band(protect, 0x100) == 0
        and (proto == 0x02 or proto == 0x04 or proto == 0x08
             or proto == 0x20 or proto == 0x40 or proto == 0x80)
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
  dump('TankStormCoop_STATUS.log', msg .. '\n')
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
-- 稳定件：LDLD / version / typeHash；记录内相对偏移；挂载项字节形态。
-- 不稳定件（不当指纹）：size、索引条数、记录数、记录区起点、记录下标。
local MAGIC          = 'LDLD'
local SIG_TURRET      = MAGIC .. string.char(1, 0, 0, 0) .. hex_le('1EBA7593')  -- TurretComponentData
local SIG_RACK        = MAGIC .. string.char(1, 0, 0, 0) .. hex_le('3845B1E0')  -- MountComponentData
local TYPE_TURRET     = 0x1EBA7593
local TYPE_RACK       = 0x3845B1E0
local DATA_OFF        = 24
local MIN_SIZE        = 1024
local MAX_SIZE        = 4194304
local DATA_CAP        = 262144
-- ① 射界
local TURRET_SR       = 76
local TURRET_REC      = hex_le('C36B5B37C058DBDD')   -- 激光实体
local YAW_MIN_OLD     = hex_be('0000A0C1')            -- -20.0f
local YAW_MAX_OLD     = hex_be('0000A041')            -- +20.0f
local YAW_MIN_NEW     = hex_be('000034C3')            -- -180.0f
local YAW_MAX_NEW     = hex_be('00003443')            -- +180.0f
local YAW_OFF         = 28                             -- 下限在记录内的偏移（上限=+32）
-- ② 挂载项锚点：**只认烟雾位的 node + 其后 12 字节**（不含 item，所以互换后依然有效）。
--    0x79CC4582 在整张 MountComponentData 里只出现 1 次（暴风坦克记录 +56）→ 可当唯一锚点。
local SMOKE_NODE_ANCHOR = hex_le('79CC4582') .. hex_be('02000000FC52964001010000')
-- 兜底锚点：万一游戏换了挂载项的 flags 字节（锚点后半段），只用 4 字节 node（同样全表唯一）
local SMOKE_NODE_ONLY   = hex_le('79CC4582')
local RACK_ANCHOR_OFF      = 56   -- 锚点（烟雾位 node）在记录内的偏移 = 48(槽) + 8(node)
local RACK_ITEM_SR         = 24   -- 一个挂载项 24 字节
local RACK_GUNNER_OFF      = 24   -- 炮手位 item 在记录内的偏移（node 在 +32）
local RACK_DRIVER_OFF      = 48   -- 驾驶员位 item 在记录内的偏移（node 在 +56 = 锚点）
local RACK_GUNNER_NODE_OFF = 32   -- 炮手位 node 在记录内的偏移（结构校验用）
local RACK_GUNNER_NODE     = hex_le('B7E9B43D')
local SMOKE_ITEM      = hex_le('3A061009AA31E9CB')-- 烟雾弹    4181046937756232139
local LASER_ITEM      = hex_le('C36B5B37C058DBDD')-- 激光制导  14081448954912365533
-- ─────────────────────────────────────────────────────────────
-- 实体哈希：用来从索引区里读出"**这张表自己的 ID**"（recIdx）。
-- ID 会随构建漂移（技能 6.33：写死的下标闸门会静默失效），所以**运行时读**，不写死。
local RACK_ENTITY     = hex_le('B0C9FAF4AF8903F9')-- tank_storm（TD-110 本体）→ 实测 ID 123
local RACK_REC_LEN    = 120                        -- 挂载记录 120 字节
-- 记录前 24 字节指纹：加特林 item(8) + node0(4) + 槽0 残留(12)。
-- 整块 dl_bin 里全局唯一 —— 只锚 node 不够：TD-220 堡垒的槽0/槽1 node 与 TD-110 逐字节相同。
local RACK_PREFIX     = hex_be('DE10DB4EA0E68AD511570CE30200000057FA79CB01010000')
local SILO_ITEM       = hex_le('8AFF7F0793A5BCED')-- 垂发火箭 10015863766813883629（槽3/4，我们不动）
local MG_TURRET_ITEM  = hex_le('C25DC40EDE0E2D16')-- 手操重机枪炮台 14005565984326167830（**看得见**的对照件）
-- ★ 标记模式（诊断用）：只把 炮手位 +24 换成"手操重机枪炮台"，+48 一动不动。
--   目的：把"改表没生效"和"生效了但激光/烟雾看不见"区分开 —— 炮手位若出现可操的重机枪，
--   说明改表这条路是通的、+24 是活槽，问题就只剩"时机/副本"。
local MARKER_MODE     = false
local SILO_NODE_A     = hex_be('C049EE9D')         -- 槽3 node 0x9DEE49C0（复核用）
local SILO_NODE_B     = hex_be('B59EDB27')         -- 槽4 node 0x27DB9EB5（复核用）
-- 射界模板：±20 那条炮塔记录的 +8..+43（36 字节）。
-- rec 26/27/28（TD-220 主炮 / TD-220 同轴机枪 / TD-110 激光指示器）共用这份模板，
-- 所以它**不能**用来区分载具，只能用来兜底抓"表外的运行时副本"。
local YAW_TPL         = hex_be('0000C84100000C42CDCC4C3F000040C0' ..
                               '0000C8410000A0C10000A041CDCCCC3DCDCCCC3D')
local YAW_TPL_YAW_OFF = 20                             -- 模板内 ±20 的起点（= 记录 +28）
-- 收紧判据：命中点附近必须能看到"激光 owner 哈希"（= TURRET_REC 的字节）
-- 才算这份副本属于激光指示器。表内 rec 26/27/28 内容逐字节相同，光看模板分不出是谁；
-- 看不到 owner 哈希 → 当"别的载具的副本"跳过（只记日志）。
local YAW_TPL_OWNER_RADIUS = 256
-- 目标状态（按位置指定，不依赖"当前是什么"）：
--    炮手位   (+24)  = SMOKE_ITEM   烟雾弹
--    驾驶员位 (+48)  = LASER_ITEM   激光制导
local MID_OLD         = YAW_MIN_OLD
local MID_NEW         = YAW_MIN_NEW
local SELF_PATTERNS   = { SIG_TURRET, SIG_RACK, TURRET_REC, SMOKE_NODE_ANCHOR, SMOKE_NODE_ONLY,
                          SMOKE_ITEM, LASER_ITEM, YAW_MIN_OLD, YAW_MAX_OLD, YAW_MIN_NEW, YAW_MAX_NEW,
                          RACK_ENTITY, RACK_PREFIX, YAW_TPL }
-- 扫描提速后把维护间隔收紧（挂载表在任务里会被重新分配，必须尽快把新副本补上）
local MAINTAIN_FRAMES    = 900    -- 15 秒
local FULL_RESCAN_FRAMES = 10800  -- 3 分钟
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
for _, s in ipairs(SELF_PATTERNS) do
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
local function validate_table(magic, want_type)
  local head = api.read(magic, DATA_OFF)
  if not head then return nil end
  if head:sub(1, 4) ~= MAGIC then return nil end
  if decode32(head, 4) ~= 1 then return nil end
  if decode32(head, 8) ~= want_type then return nil end
  local size = decode32(head, 12)
  if not size or size < MIN_SIZE or size > MAX_SIZE then return nil end
  return size
end

local function write_bytes(address, bytes)
  local old = api.unprotect(address, #bytes)
  if not old then
    state.refusals = state.refusals + 1
    report(('VirtualProtect 失败，拒绝写入 0x%X'):format(address), true)
    return false
  end
  local wrote = api.write(address, bytes)
  api.reprotect(address, #bytes, old)
  if not wrote then
    state.refusals = state.refusals + 1
    report(('WriteProcessMemory 失败 0x%X'):format(address), true)
    return false
  end
  if api.read(address, #bytes) ~= bytes then
    state.refusals = state.refusals + 1
    report(('回读校验失败 0x%X'):format(address), true)
    return false
  end
  return true
end

-- ① TurretComponentData：把激光的水平射界改成 ±180
local function apply_turret(magic)
  local size = validate_table(magic, TYPE_TURRET)
  if not size or size > DATA_CAP then return end
  local data = api.read(magic + DATA_OFF, size)
  if not data then return end

  -- 枚举候选记录区起点：16 的倍数 + 整除 + 索引区 recIdx 全部 < 记录数；取最大
  local base, nr = nil, nil
  local ni = 1
  while true do
    local b = ni * 16
    if b + TURRET_SR > size then break end
    local rem = size - b
    if rem % TURRET_SR == 0 then
      local n = rem / TURRET_SR
      local ok, k = true, 0
      while k + 16 <= b do
        local pad = decode32(data, k + 12)
        local ix  = decode32(data, k + 8)
        if pad ~= 0 or ix >= n then ok = false break end
        k = k + 16
      end
      if ok then base, nr = b, n end
    end
    ni = ni + 1
  end
  if not base then return end

  -- 从索引区读激光的记录下标
  local p = data:find(TURRET_REC, 1, true)
  local rec_off = nil
  while p do
    -- 索引条目是 16 字节一条：(u64 实体哈希, u32 recIdx, u32 pad)
    -- 必须 (p-1) % 16 == 0 才是"真条目"，否则可能是跨条目的巧合字节串。
    if (p - 1) % 16 == 0 and p - 1 + 16 <= base then
      local ix  = decode32(data, p - 1 + 8)
      local pad = decode32(data, p - 1 + 12)
      if pad == 0 and ix < nr then rec_off = base + ix * TURRET_SR break end
    end
    p = data:find(TURRET_REC, p + 1, true)
  end
  if not rec_off or rec_off + TURRET_SR > #data then return end

  local cur = data:sub(rec_off + YAW_OFF + 1, rec_off + YAW_OFF + 8)
  local address = magic + DATA_OFF + rec_off + YAW_OFF
  if cur == YAW_MIN_NEW .. YAW_MAX_NEW then
    state.slots[address] = { kind = 'yaw', expect = YAW_MIN_NEW .. YAW_MAX_NEW }
    state.round_hits = (state.round_hits or 0) + 1
    state.tables[magic] = size
    state.phase = 'patched'
    if state.maintain_frame == 0 then state.maintain_frame = state.frame + MAINTAIN_FRAMES end
    if state.full_frame == 0 then state.full_frame = state.frame + FULL_RESCAN_FRAMES end
    report(('表 0x%X size=%d 记录区起点 +%d：激光射界已是 ±180（下标 %d）'):format(
      magic, size, base, (rec_off - base) / TURRET_SR))
    return
  end
  if cur ~= YAW_MIN_OLD .. YAW_MAX_OLD then
    state.refusals = state.refusals + 1
    report(('表 0x%X：激光记录的射界既不是 ±20 也不是 ±180，已跳过'):format(magic), true)
    return
  end
  if write_bytes(address, YAW_MIN_NEW .. YAW_MAX_NEW) then
    state.slots[address] = { kind = 'yaw', expect = YAW_MIN_NEW .. YAW_MAX_NEW }
    state.writes = state.writes + 1
    state.round_hits = (state.round_hits or 0) + 1
    state.tables[magic] = size
    state.phase = 'patched'
    if state.maintain_frame == 0 then state.maintain_frame = state.frame + MAINTAIN_FRAMES end
    if state.full_frame == 0 then state.full_frame = state.frame + FULL_RESCAN_FRAMES end
    report(('已改射界：表 0x%X size=%d 记录区起点 +%d 激光(下标 %d) 水平射界 -20/+20 → -180/+180'):format(
      magic, size, base, (rec_off - base) / TURRET_SR), true)
    dump('TankStormCoop_Addresses.log', table.concat({
      ('表基址        = 0x%X   (size=%d)'):format(magic, size),
      ('记录区起点    = magic+%d   (数据区内 +%d)'):format(DATA_OFF + base, base),
      ('激光记录      = 0x%X   (下标 %d)'):format(magic + DATA_OFF + rec_off, (rec_off - base) / TURRET_SR),
      ('射界下限 +28  = 0x%X'):format(address),
      ('射界上限 +32  = 0x%X'):format(address + 4),
      ('写入后回读    = %s'):format(hex(api.read(address, 8) or '')),
    }, '\n') .. '\n')
  end
end

-- ---------------------------------------------------------------- 挂载记录写入
-- TD-110 挂载记录的"结构复核 + 按位置写入"。**表内（索引 ID 定位）与表外副本共用这一份**。
-- 返回 'written' | 'target' | 'refused'
local function rack_write_record(rec, tag, rec_id, magic, size)
  -- 结构校验 ⓪：记录前 24 字节必须与 TD-110 指纹逐字节相同
  --   （加特林 item + node0 + 槽0 残留；TD-220 在这一段就已经不同）
  local prefix = api.read(rec, 24)
  if prefix ~= RACK_PREFIX then
    state.refusals = state.refusals + 1
    report(('挂载 0x%X（%s）：前 24 字节指纹不符（%s），拒写'):format(
      rec, tag, hex(prefix or '')), true)
    return 'refused'
  end
  -- 结构校验 ①：炮手位 node + 槽3/槽4 必须是垂发（且 node 对得上）
  local gn  = api.read(rec + RACK_GUNNER_NODE_OFF, 4)
  local i72 = api.read(rec + 72, 8)
  local i96 = api.read(rec + 96, 8)
  local n72 = api.read(rec + 72 + 8, 4)
  local n96 = api.read(rec + 96 + 8, 4)
  if gn ~= RACK_GUNNER_NODE or i72 ~= SILO_ITEM or i96 ~= SILO_ITEM
     or n72 ~= SILO_NODE_A or n96 ~= SILO_NODE_B then
    state.refusals = state.refusals + 1
    report(('挂载 0x%X（%s）：槽位复核不过（+32=%s +72=%s +96=%s），拒写'):format(
      rec, tag, hex(gn or ''), hex(i72 or ''), hex(i96 or '')), true)
    return 'refused'
  end

  local gunner_addr = rec + RACK_GUNNER_OFF    -- +24 炮手位
  local driver_addr = rec + RACK_DRIVER_OFF    -- +48 驾驶员位
  local gi = api.read(gunner_addr, 8)
  local di = api.read(driver_addr, 8)
  if not gi or not di then return 'refused' end

  local function mark()
    local g2, d2 = api.read(gunner_addr, 8), api.read(driver_addr, 8)
    if g2 then state.slots[gunner_addr] = { kind = 'item', expect = g2 } end
    if d2 then state.slots[driver_addr] = { kind = 'item', expect = d2 } end
    state.round_hits = (state.round_hits or 0) + 1
    if magic then state.tables[magic] = size end
    state.phase = 'patched'
    if not state.rack_ready then
      state.rack_ready = true
      report('挂载补丁已就绪：**现在可以召唤 / 重新召唤载具了**（挂载是生成载具时读一次，补丁必须早于生成）', true)
    end
    if state.maintain_frame == 0 then state.maintain_frame = state.frame + MAINTAIN_FRAMES end
    if state.full_frame == 0 then state.full_frame = state.frame + FULL_RESCAN_FRAMES end
  end

  local where
  if magic then
    where = ('表 0x%X 记录 0x%X（ID=%s，数据区内 +%d，%s）'):format(
      magic, rec, tostring(rec_id), rec - DATA_OFF - magic, tag)
  else
    where = ('记录 0x%X（%s）'):format(rec, tag)
  end

  if MARKER_MODE then
    if gi == MG_TURRET_ITEM then
      mark()
      report(where .. '：炮手位已是"手操重机枪炮台"（标记模式目标状态）')
      return 'target'
    end
    if write_bytes(gunner_addr, MG_TURRET_ITEM) then
      state.writes = state.writes + 1
      mark()
      report(where .. ('（**标记模式**） 炮手位 +24 %s → 手操重机枪炮台 C25DC40EDE0E2D16（+48 未动）'):format(
        hex(gi)), true)
      dump('TankStormCoop_Addresses.log', table.concat({
        ('命中记录          = 0x%X   （%s，标记模式）'):format(rec, tag),
        ('炮手位 item +24   = 0x%X   写入前 %s → 现 %s'):format(
          gunner_addr, hex(gi), hex(api.read(gunner_addr, 8) or '')),
        ('驾驶员位 +48      = 0x%X   保持原样 %s'):format(driver_addr, hex(di)),
      }, '\n') .. '\n')
      return 'written'
    end
    report(where .. '：标记写入失败', true)
    return 'refused'
  end

  if gi == SMOKE_ITEM and di == LASER_ITEM then
    mark()
    report(where .. '：炮手位已是烟雾弹、驾驶员位已是激光指示器（目标状态）')
    return 'target'
  end

  local ok1 = write_bytes(gunner_addr, SMOKE_ITEM)   -- +24 炮手位 → 烟雾弹
  local ok2 = write_bytes(driver_addr, LASER_ITEM)   -- +48 驾驶员位 → 激光指示器
  if not (ok1 and ok2) then
    report(where .. ('：写入失败（+24 %s / +48 %s）'):format(tostring(ok1), tostring(ok2)), true)
    return 'refused'
  end
  state.writes = state.writes + 2
  mark()
  local slots = {}
  for i = 0, 4 do slots[#slots + 1] = hex(api.read(rec + i * RACK_ITEM_SR, 8) or '') end
  report(where .. ('  炮手位 +24 %s → 烟雾弹  驾驶员位 +48 %s → 激光指示器（node 未动）'):format(
    hex(gi), hex(di)), true)
  report(('   该记录 5 槽 item：%s'):format(table.concat(slots, ' ')))
  local out = {}
  if magic then out[#out + 1] = ('表基址            = 0x%X   (size=%d)'):format(magic, size) end
  out[#out + 1] = ('命中记录          = 0x%X   （%s%s）'):format(
    rec, tag, rec_id and ('，ID=' .. tostring(rec_id)) or '')
  out[#out + 1] = ('炮手位 item +24   = 0x%X   写入前 %s → 现 %s'):format(
    gunner_addr, hex(gi), hex(api.read(gunner_addr, 8) or ''))
  out[#out + 1] = ('驾驶员位 item +48 = 0x%X   写入前 %s → 现 %s'):format(
    driver_addr, hex(di), hex(api.read(driver_addr, 8) or ''))
  if not magic then out[#out + 1] = '（这是**表外副本**：表内那份之外，内存里还有同样内容的记录）' end
  dump('TankStormCoop_Addresses.log', table.concat(out, '\n') .. '\n')
  return 'written'
end

-- ② MountComponentData：按位置替换两个挂载项的 item 哈希（node 与其它字段一律不动）
local function apply_rack(magic)
  local size = validate_table(magic, TYPE_RACK)
  if not size or size > DATA_CAP then return end
  local data = api.read(magic + DATA_OFF, size)
  if not data then return end

  local found = 0
  local seen_rec = {}

  -- 一条命中记录的处理：rec 是该挂载记录的**绝对地址**，rec_id = 这张表里的 ID(recIdx)
  local function handle(rec, anchor_tag, rec_id)
    if seen_rec[rec] then return end
    seen_rec[rec] = true
    found = found + 1
    rack_write_record(rec, anchor_tag, rec_id, magic, size)
  end

  -- 锚点（烟雾位 node，全表唯一）→ 记录起点 = 锚点位置 − 56
  local function pass(pat, tag)
    local from = 1
    while true do
      local a = data:find(pat, from, true)
      if not a then break end
      from = a + 1
      if a - 1 >= RACK_ANCHOR_OFF then
        local ok2, err = pcall(handle, magic + DATA_OFF + (a - 1) - RACK_ANCHOR_OFF, tag)
        if not ok2 then report('挂载命中处理异常: ' .. tostring(err), true) end
      end
    end
  end

  -- 主路径：**按索引区里的 ID 定位**。
  --   每个表有自己的 ID 空间；ID 会随构建漂移，所以运行时从索引区读，不写死。
  --   读到的记录再用 24 字节指纹 + 槽位复核确认，两条都对才落笔。
  do
    local base, nr = nil, nil                 -- 记录区起点 / 记录条数（枚举候选，同射界那张表）
    local ni = 1
    while true do
      local b = ni * 16
      if b + RACK_REC_LEN > size then break end
      local rem = size - b
      if rem % RACK_REC_LEN == 0 then
        local n = rem / RACK_REC_LEN
        local ok2, k = true, 0
        while k + 16 <= b do
          local pad = decode32(data, k + 12)
          local ix  = decode32(data, k + 8)
          if pad ~= 0 or ix >= n then ok2 = false break end
          k = k + 16
        end
        if ok2 then base, nr = b, n end
      end
      ni = ni + 1
    end
    if base then
      local p = data:find(RACK_ENTITY, 1, true)
      while p do
        -- 索引条目 16 字节一条：(u64 实体哈希, u32 ID(recIdx), u32 pad)
        if (p - 1) % 16 == 0 and p - 1 + 16 <= base then
          local ix  = decode32(data, p - 1 + 8)
          local pad = decode32(data, p - 1 + 12)
          if pad == 0 and ix < nr then
            handle(magic + DATA_OFF + base + ix * RACK_REC_LEN, ('索引 ID=%d'):format(ix), ix)
            break
          end
        end
        p = data:find(RACK_ENTITY, p + 1, true)
      end
    end
  end

  -- 兜底：索引区没读出来时，才退回"烟雾位 node 锚点"
  pass(SMOKE_NODE_ANCHOR, 'node+flags')
  if found == 0 then pass(SMOKE_NODE_ONLY, 'node(4B)兜底(无指纹复核)') end

  if found == 0 then
    -- 没命中不是错误（换图后表副本可能还没加载），但值得记一笔
    state.round_misses = (state.round_misses or 0) + 1
    if state.round_misses <= 2 then
      report(('表 0x%X：没找到锚点 0x79CC4582（size=%d，数据区前 32 字节 %s）'):format(
        magic, size, hex(data:sub(1, 32))), true)
    end
  end
end

local function apply(magic)
  local head = api.read(magic + 8, 4)
  if not head then return end
  local typ = decode32(head, 0)
  if typ == TYPE_TURRET then apply_turret(magic)
  elseif typ == TYPE_RACK then apply_rack(magic) end
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
  dump('TankStormCoop_STATUS.log', table.concat({
    first,
    'revision=tank-storm-coop-1.0',
    'phase=' .. tostring(state.phase),
    'updated=' .. os.date('%Y-%m-%d %H:%M:%S'),
    ('前置 = Bingus Shared Loader loader-v%s / API %s（来源 %s）'):format(
      tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)),
    ('表 = TurretComponentData 0x1EBA7593（射界 ±180）+ MountComponentData 0x3845B1E0（按位置替换挂载物品，node 不动）'),
    ('挂载记录定位 = 索引 ID(recIdx) + 24 字节记录指纹 双确认；读不到索引时才退回烟雾位 node 0x79CC4582 锚点'),
    ('射界模板：已改 %d 处 / 因缺 owner 哈希跳过 %d 处'):format(
      (function() local n = 0 for _ in pairs(state.yaw_sites) do n = n + 1 end return n end)(),
      (function() local n = 0 for _ in pairs(state.yaw_skip_sites) do n = n + 1 end return n end)()),
    (state.rack_ready
      and '挂载状态 = 已就绪 ✓ 现在可以召唤 / 重新召唤载具（补丁必须早于生成载具）'
      or  '挂载状态 = 未就绪 ✗ 先别召唤载具（正在扫表；等这行变成"已就绪"）'),
    ('已写=%d 处  拒绝=%d  轮次=%d  空轮=%d  帧=%d'):format(
      state.writes, state.refusals, state.rounds, state.empty_rounds, state.frame),
    ('内存里的表副本 = %d 处   观察窗口扫描 = 每 %d 秒   全量兜底 = 每 %d 分钟'):format(
      copies, MAINTAIN_FRAMES / 60, FULL_RESCAN_FRAMES / 3600),
  }, '\n') .. '\n')

  -- 表外命中的"±20 炮塔模板"地址：给 CE 对照用（谁才是游戏真正在用的那份）
  local sites = {}
  for a in pairs(state.yaw_sites) do sites[#sites + 1] = a end
  if #sites > 0 then
    table.sort(sites)
    local lines = { ('[frame %d] 表外"±20 炮塔模板"命中 %d 处（需要 owner 判据通过；表内已由索引路处理）:'):format(state.frame, #sites) }
    for i = 1, math.min(#sites, 40) do
      lines[#lines + 1] = ('  0x%X   射界字段 = 0x%X'):format(sites[i], sites[i] + YAW_TPL_YAW_OFF)
    end
    local skips = {}
    for a in pairs(state.yaw_skip_sites) do skips[#skips + 1] = a end
    if #skips > 0 then
      table.sort(skips)
      lines[#lines + 1] = ('  --- 跳过（附近 %d 字节内没有 owner 哈希，等 CE 确认是不是别的载具）共 %d 处：'):format(YAW_TPL_OWNER_RADIUS, #skips)
      for i = 1, math.min(#skips, 40) do
        lines[#lines + 1] = ('  0x%X   （未改）'):format(skips[i])
      end
    end
    dump('TankStormCoop_YawSites.log', table.concat(lines, '\n') .. '\n')
  end

  -- 表外挂载记录副本清单（诊断：表内那份之外，内存里还有几份、处理结果如何）
  local rsites = {}
  for a, r in pairs(state.rack_sites) do rsites[#rsites + 1] = a end
  if #rsites > 0 then
    table.sort(rsites)
    local rl = { ('[frame %d] 表外"TD-110 挂载记录"副本 %d 处：'):format(state.frame, #rsites) }
    for i = 1, math.min(#rsites, 40) do
      rl[#rl + 1] = ('  0x%X   → %s'):format(rsites[i], tostring(state.rack_sites[rsites[i]]))
    end
    dump('TankStormCoop_RackSites.log', table.concat(rl, '\n') .. '\n')
  end
end

local function recheck()
  local live, fixed, reverted, unreadable, dropped = 0, 0, 0, 0, 0
  for address, info in pairs(state.slots) do
    local cur = api.read(address, #info.expect)
    if cur == nil then
      unreadable = unreadable + 1
      state.slots[address] = nil
    elseif cur == info.expect then
      live = live + 1
    elseif info.kind == 'yaw' and cur == YAW_MIN_OLD .. YAW_MAX_OLD then
      -- 被游戏改回成 -20/+20：重写一次
      reverted = reverted + 1
      report(('复查：射界被改回 -20/+20（0x%X），重写'):format(address), true)
      if write_bytes(address, info.expect) then
        state.writes = state.writes + 1
        live, fixed = live + 1, fixed + 1
      else
        state.slots[address] = nil
        dropped = dropped + 1
      end
    else
      -- 既不是"已生效"也不是"被改回原值" → 打印实际值，便于定位
      dropped = dropped + 1
      report(('复查：0x%X 的值变成 %s（%s，期望 %s）'):format(
        address, hex(cur), info.kind, hex(info.expect)), true)
      state.slots[address] = nil
    end
  end
  if fixed > 0 then report(('复查：重写被冲掉的补丁 %d 处'):format(fixed), true) end
  if reverted > 0 then report(('复查：有 %d 处射界被游戏回写（正在反复重写）'):format(reverted)) end
  if unreadable > 0 then report(('复查：%d 处地址已不可读（表被释放/移动）'):format(unreadable), true) end
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
  local target = string.format('%08X', TABLE_TYPE)
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
local SCAN_BUDGET  = 0.002      -- 常态：每帧最多 2 ms（技能 6.42）
-- 抢时间模式：挂载是**生成载具时读一次**的静态配置，补丁必须早于生成，
--   所以还没打到表时：每帧给 6 ms、且只找两张表的签名（跳过普查/射界模板/表外副本），
--   打到表（phase=patched）后立刻回到 2 ms。前 HURRY_ROUNDS 轮都按抢时间模式跑。
local SCAN_BUDGET_HURRY = 0.006
local HURRY_ROUNDS      = 4
local BACKOFF      = { 2, 2, 4, 4, 8, 15, 30, 60 }   -- 空轮等待缩短，尽快重试
local MAX_EMPTY    = 8

-- SKILL 6.17：同一张表在内存里有几十份，而且进任务/换图时会**再加载一份新的**。
-- "只打第一份" = 一开始生效、过一会儿就失效，而复查还会说一切正常。
-- 所以 patched 之后要持续维护：先扫"已知表副本地址 ±32KB"的观察窗口（几 MB，
-- 比全地址空间便宜两个数量级），再定期全量兜底。
local function collect_regions()
  local all = api.regions()
  local list = {}
  for i = 1, #all do
    -- 旧版是 65536：表副本若落在小区域里会被整段跳过（"内存里有表却永远扫不到"）。
    if all[i].size >= 8192 then list[#list + 1] = all[i] end
  end
  table.sort(list, function(a, b) return a.size > b.size end)
  return list
end

-- ---------------------------------------------------------------- 舰船待命采样
-- 组件表**只在任务里加载**，舰船上整轮全量扫描纯属浪费 —— 而且会把"进任务 → 打补丁"拖后 1~2 分钟
-- （挂载是生成载具时读一次，补丁晚了就不生效）。所以先只采样最大的几个区域：
--   · 看到任何 LDLD 块 → 任务数据已到位 → 立刻转"全量 + 抢时间"扫描（先扫挂载表）
--   · 什么都没看到 → 待命，几秒后再采样（CPU 几乎为零）
local PROBE_REGIONS     = 12
local PROBE_CAP         = 8 * 1024 * 1024
local PROBE_BUDGET      = 0.002
local PROBE_WAIT_FRAMES = 300                 -- 采样没发现 → 5 秒后再来
local PROBE_FAIL_LIMIT  = 20                  -- 连续 20 次都没有 → 兜底走全量（表可能在采样区之外）

local function begin_probe()
  local all = collect_regions()               -- 已按 size 降序
  local list = {}
  for i = 1, math.min(#all, PROBE_REGIONS) do
    local r = all[i]
    list[#list + 1] = { base = r.base, size = math.min(r.size, PROBE_CAP) }
  end
  state.probe_list   = list
  state.probe_index  = 1
  state.probe_offset = 0
  state.probe_prev   = ''
  state.probe_bytes  = 0
end

-- 返回 true = 这一轮采样跑完了（发现或没发现都算跑完）
local function probe_run()
  if not state.probe_list then begin_probe() end
  local deadline = os.clock() + PROBE_BUDGET
  while state.probe_index <= #state.probe_list do
    local region = state.probe_list[state.probe_index]
    while state.probe_offset < region.size do
      if os.clock() > deadline then return false end
      local amount = math.min(SCAN_CHUNK, region.size - state.probe_offset)
      local buf = api.read(region.base + state.probe_offset, amount)
      state.probe_bytes = state.probe_bytes + amount
      if buf then
        local window_base = region.base + state.probe_offset - #state.probe_prev
        local window = state.probe_prev .. buf
        local i = window:find(SIG_RACK, 1, true) or window:find(SIG_TURRET, 1, true)
        if i then
          report(('采样到目标表（0x%X 附近）→ 立刻转全量抢时间扫描'):format(window_base + i - 1), true)
          state.mission_ready = true
          state.probe_list = nil
          return true
        end
        if window:find(MAGIC, 1, true) then
          report(('采样到 LDLD 表（已进任务，共采样 %.0f MB）→ 立刻转全量抢时间扫描'):format(
            state.probe_bytes / 1048576), true)
          state.mission_ready = true
          state.probe_list = nil
          return true
        end
        state.probe_prev = buf:sub(-SCAN_OVERLAP)
      else
        state.probe_prev = ''
      end
      state.probe_offset = state.probe_offset + amount
    end
    state.probe_index  = state.probe_index + 1
    state.probe_offset = 0
    state.probe_prev   = ''
  end
  state.probe_list = nil
  return true
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

-- 已知 LDLD 表覆盖的地址范围（模板兜底时跳过"表内"命中：那些交给索引路，避免误伤同模板的其它载具）
local function inside_known_table(address)
  for magic, size in pairs(state.tables) do
    if type(size) == 'number' and address >= magic and address < magic + DATA_OFF + size then
      return true
    end
  end
  return false
end

-- 射界模板兜底：内存里凡是还带着 ±20 的那份炮塔记录（表外副本 / 运行时实例），一并改成 ±180。
-- 模板本身包含 ±20 这两个字节 ⇒ 已改过的记录不会再命中 ⇒ 天然幂等。
-- 命中点附近有没有"激光 owner 哈希"（±YAW_TPL_OWNER_RADIUS 字节）
local function owner_nearby(site)
  local radius = YAW_TPL_OWNER_RADIUS
  local from   = site - radius
  if from < 0x10000 then from = 0x10000 end
  local size   = (site + radius) - from + 8
  local blob   = api.read(from, size)
  if blob and blob:find(TURRET_REC, 1, true) then return true end
  -- 整段读不到（跨区域）→ 退化成左右两小段
  local a = api.read(site - 128, 128)
  if a and a:find(TURRET_REC, 1, true) then return true end
  local b = api.read(site + 76, 128)
  if b and b:find(TURRET_REC, 1, true) then return true end
  return false
end

local function scan_yaw_template(window, window_base)
  local from = 1
  while true do
    local i = window:find(YAW_TPL, from, true)
    if not i then break end
    from = i + 1
    local site = window_base + i - 1              -- 模板起点 = 记录 +8
    if not is_self_hit(site) and not inside_known_table(site) then
      -- 收紧判据：附近看不到激光 owner 哈希 → 当别的载具的副本，跳过（只记日志）
      if not owner_nearby(site) then
        state.yaw_skip_sites[site] = true
        if not state.yaw_skip_frame or state.frame - state.yaw_skip_frame > 1200 then
          state.yaw_skip_frame = state.frame
          report(('射界模板命中 0x%X：±%d 字节内没有激光 owner 哈希，按"别的载具的副本"跳过'):format(
            site, YAW_TPL_OWNER_RADIUS), true)
        end
      else
      state.yaw_sites[site] = true
      local address = site + YAW_TPL_YAW_OFF      -- 记录 +28
      local cur = api.read(address, 8)
      if cur == YAW_MIN_OLD .. YAW_MAX_OLD then
        if write_bytes(address, YAW_MIN_NEW .. YAW_MAX_NEW) then
          state.writes = state.writes + 1
          state.round_hits = (state.round_hits or 0) + 1
          state.slots[address] = { kind = 'yaw', expect = YAW_MIN_NEW .. YAW_MAX_NEW }
          state.phase = 'patched'
          if state.maintain_frame == 0 then state.maintain_frame = state.frame + MAINTAIN_FRAMES end
          if state.full_frame == 0 then state.full_frame = state.frame + FULL_RESCAN_FRAMES end
          report(('已改射界(模板兜底)：0x%X 记录 ±20 → ±180（表外副本）'):format(site), true)
        end
      elseif cur and cur ~= YAW_MIN_NEW .. YAW_MAX_NEW then
        report(('射界模板命中 0x%X，但 +28 既不是 ±20 也不是 ±180（%s），跳过'):format(site, hex(cur)), true)
      end
      end
    end
  end
end

-- 挂载表外副本兜底：全内存按"记录前 24 字节指纹"找 TD-110 挂载记录的**其它副本**
-- （运行时实例 / 被引擎搬走的那份），同样按位置改 +24/+48。
-- 与射界模板兜底同一个思路：只打表内不够时，把外面那份也打掉。
local function scan_rack_copies(window, window_base)
  local from = 1
  while true do
    local n = window:find(RACK_PREFIX, from, true)
    if not n then break end
    from = n + 1
    local rec = window_base + n - 1          -- 指纹就是记录 +0..+23 ⇒ 命中处即记录起点
    if not is_self_hit(rec) and not inside_known_table(rec) then
      local rc = rack_write_record(rec, '表外副本', nil, nil, nil)
      state.rack_sites[rec] = rc
    end
  end
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
  local hurry    = (state.scan_kind == 'full') and ((state.rounds or 0) <= HURRY_ROUNDS)
  local deadline = os.clock() + (hurry and SCAN_BUDGET_HURRY or SCAN_BUDGET)
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
        if not hurry then pcall(census_scan, buf, region.base + state.region_offset) end
        local window_base = region.base + state.region_offset - #state.previous
        local window = state.previous .. buf
        -- 抢时间模式先扫挂载表（MountComponentData），它才是"必须在召唤前打好"的那张
        for _, sig in ipairs(hurry and { SIG_RACK, SIG_TURRET } or { SIG_TURRET, SIG_RACK }) do
          local from = 1
          while true do
            local i = window:find(sig, from, true)
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
        end
        -- 射界模板兜底 + 挂载表外副本：这两件是"重活"，抢时间模式下先跳过（后面的轮次会补）
        if not hurry then
          pcall(scan_yaw_template, window, window_base)
          pcall(scan_rack_copies, window, window_base)
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
  if state.frame < 120 then return end

  -- 还没确认"进了任务"之前，只做便宜采样（舰船上不白扫）
  if not state.mission_ready then
    if not probe_run() then return end          -- 采样没跑完
    if state.mission_ready then return end      -- 发现了，下一帧走全量
    state.probe_fails = (state.probe_fails or 0) + 1
    if state.probe_fails >= PROBE_FAIL_LIMIT then
      report(('采样 %d 次都没看到 LDLD，转全量扫描（表可能在采样区之外）'):format(state.probe_fails), true)
      state.mission_ready = true
    else
      state.next_scan_frame = state.frame + PROBE_WAIT_FRAMES
      report(('待命：内存里没有任何 LDLD 表（还没进任务？）—— 采样 %d MB，%d 秒后再试'):format(
        (state.probe_bytes or 0) / 1048576, PROBE_WAIT_FRAMES / 60))
    end
    return
  end

  if not state.regions then
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

report(('已加载 v1.0（TD-110：射界 ±180 + 按位置替换挂载物品〔记录 ID + 24 字节指纹定位〕）；前置 loader v%s / API %s（来源 %s）'):format(
  tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)))