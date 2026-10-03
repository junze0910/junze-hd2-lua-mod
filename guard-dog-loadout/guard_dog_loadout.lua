-- HD2-Addon: mods/dsh/guard_dog_loadout

-- ===========================================================================
--  护卫犬挂载自选（guard_dog_loadout）—— 机枪犬 drone_mg 的挂载武器三选一
--
--  player-facing 选项（Scanner 插件页 / ModOptionsMenu）：
--      AR-23P（原装）  = 写回原装 drone_mg_weapon（语义=不改写）
--      MG-43（SEAF）   = 587878FB76F4B9B1
--      自定义（读 cfg） = 用户在 GuardDogLoadout.cfg 里填的 16 位 BE hex
--
--  定位腿与机甲 mod（exo_loadout 的手臂改造）**逐行同构**：
--      Scanner 广播 MountComponentData 0x3845B1E0
--        -> 运行时推记录区起点（索引条数会随版本变：322/324 都见过）
--        -> 索引区 (u64 实体, u32 recIdx, u32 pad=0) 找 drone_mg -> recIdx
--        -> 记录 +0 的 8 字节 item
--      二级复核：记录 +8 的挂载位点 node == 0x53BEC437（= 1405010999）
--
--  实测数据（用户 2026-10 提供 + 表 dump 交叉验证）：
--      drone_mg 实体 = A0FF2F9A0CA6992A      recIdx = 97      挂载位点 = 0x53BEC437
--      原装 item     = A32621E3BDE13379（.../drone_mg/drone_mg_weapon）
--      size=24592 的版本：索引 322 条 / 记录 162 条，记录区起点 = 322*16 = 5152
--      drone_mg 索引条目在 index[300]：ent 命中唯一、pad=0
--
--  红线：只写目标记录 +0 的 8 字节；其余 112 字节一字不动。
-- ===========================================================================

local VERSION = '1.0.1'
local MOD = 'mods/dsh/guard_dog_loadout'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, phase = 'starting', writes = 0, refusals = 0, errs = 0,
                  slots = {}, polls = 0, last_gen = -1 })
local state = rawget(_G, MOD)

-- ---------------------------------------------------------------- 日志（SKILL 6.15）
-- loader 的 open_log 是 "w" 模式（每次打开都截断），所以累积后一次性落盘。
-- ①环形上限 400  ②连续同一条折叠成 (×N)  ③脏标志 + 1 秒节流。
local LOG_CAP = 400
local loghist, log_dirty, log_at = {}, false, -10

local function flush_log(force)
  if #loghist == 0 then return end
  local now = os.clock()
  if not force and (not log_dirty or now - log_at < 1) then return end
  log_dirty, log_at = false, now
  local text = table.concat(loghist, '\n') .. '\n'
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local file = loader and loader.open_log and loader.open_log('GuardDogLoadout.log')
    if file then file:write(text); file:close() end
  end)
end

local function report(message, keep)
  if message == state.status then
    state.repeat_n = (state.repeat_n or 1) + 1
    if #loghist > 0 then
      loghist[#loghist] = ('[frame %d] %s  (×%d)'):format(state.frame, message, state.repeat_n)
      log_dirty = true
    end
    return
  end
  state.status, state.repeat_n = message, 1
  print('[GuardDogLoadout] ' .. message)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, message)
  if #loghist > LOG_CAP then table.remove(loghist, 1) end
  log_dirty = true
  if keep then flush_log(true) end
end

local function dump(name, text)
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local f = loader and loader.open_log and loader.open_log(name)
    if f then f:write(text); f:close() end
  end)
end

-- ---------------------------------------------------------------- 工具
local function le(h)                     -- BE hex -> LE 字节串（u64 律存字符串，SKILL 6.1）
  local t = {}
  for i = #h - 1, 1, -2 do t[#t + 1] = string.char(tonumber(h:sub(i, i + 1), 16)) end
  return table.concat(t)
end

local function le32(n)                   -- number -> 4 字节 LE
  local b = {}
  for _ = 1, 4 do b[#b + 1] = string.char(n % 256); n = math.floor(n / 256) end
  return table.concat(b)
end

local function d32(b, o)                 -- 从字节串 o（0 基）读 u32 LE
  return b:byte(o + 1) + b:byte(o + 2) * 256 + b:byte(o + 3) * 65536 + b:byte(o + 4) * 16777216
end

local function hexs(b)
  if not b then return '(nil)' end
  return (b:gsub('.', function(c) return string.format('%02X', c:byte()) end))
end

-- ---------------------------------------------------------------- 目标（实测常量）
local MG_TYPE   = 0x3845B1E0             -- djb2('MountComponentData')
local RDATA_OFF = 24                     -- LDLD 表头
local REC_SR    = 120                    -- 记录长
local R_MIN, R_MAX, R_CAP = 1024, 4194304, 262144
local MAGIC     = 'LDLD'

local ENT_HEX   = 'A0FF2F9A0CA6992A'     -- drone_mg 挂载母体
local NODE      = 1405010999             -- 0x53BEC437 挂载位点（记录 +8）
local VANILLA   = 'A32621E3BDE13379'     -- drone_mg_weapon（原装）
local MG43      = '587878FB76F4B9B1'     -- SEAF MG-43
local ENT_LE    = le(ENT_HEX)

local WEAPON_CHOICES = { 'AR-23P（原装）', 'MG-43（SEAF）', '自定义（读 cfg）' }
local WEAPON_KEY     = { ['AR-23P（原装）'] = 'ar23p', ['MG-43（SEAF）'] = 'mg43', ['自定义（读 cfg）'] = 'custom' }
local WEAPON_LABEL   = { ar23p = 'AR-23P（原装）', mg43 = 'MG-43（SEAF）', custom = '自定义（读 cfg）' }

-- ---------------------------------------------------------------- cfg
-- ★ local CFG, CFG_FILE **必须声明在所有用它的函数之前**（Lua 词法作用域是位置性的；
--   交接单 §四记过：CFG 写在函数后面 -> 解析成全局 nil -> 每次渲染面板都抛异常）。
local CFG, CFG_FILE
CFG = { weapon = 'ar23p', custom = '' }
do
  local loader = rawget(_G, 'CowboyBingusModLoader')
  local base = loader and type(loader.log_directory) == 'string'
               and loader.log_directory:gsub('[/\\]Logs$', '') or '.'
  CFG_FILE = base .. '/GuardDogLoadout.cfg'
end

local function cfg_parse(text)
  text = text:gsub('^\239\187\191', '')            -- 剥 UTF-8 BOM：BOM 落在 weapon= 行上会让整行解析失败
  for line in text:gmatch('[^\r\n]+') do
    line = line:gsub('#.*$', '')                       -- 先砍行尾注释
    local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k then
      if k == 'weapon' then
        if WEAPON_LABEL[v] then CFG.weapon = v end
      elseif k == 'custom' then
        v = v or ''
        if v == '' then CFG.custom = ''
        elseif #v == 16 and v:match('^%x+$') then CFG.custom = v:upper() end
      end
    end
  end
end

-- cfg 的完整文本（带说明注释）。默认生成与保存共用它 ——
-- 这样在面板上改一次选项，说明注释也不会被抹掉（以前 cfg_save 只写 3 行裸键）。
local function cfg_text()
  return table.concat({
    '# 护卫犬挂载自选（guard_dog_loadout）—— 改完 1 秒内热生效\n',
    '# weapon: ar23p(原装/不改写) | mg43(SEAF MG-43) | custom(读下面那行)\n',
    'weapon=' .. tostring(CFG.weapon) .. '\n',
    '# custom: 16 位 BE 十六进制（物品哈希 u64）。留空 = 自定义项不可用\n',
    '#   ⚠ 必须填【确实存在】的 item 哈希：格式对但哈希不存在，狗可能召唤异常\n',
    '#   例：custom=587878FB76F4B9B1（= SEAF MG-43）\n',
    'custom=' .. tostring(CFG.custom or '') .. '\n',
  })
end

local function cfg_write_default()
  pcall(function()
    local f = io.open(CFG_FILE, 'w')
    if not f then return end
    f:write(cfg_text())
    f:close()
  end)
end

local cfgt = { text = nil }
local function cfg_read()
  local f = io.open(CFG_FILE, 'r')
  if not f then return nil end
  local text = f:read('*a'); f:close()
  return text
end

local function cfg_load()
  local text = cfg_read()
  if not text then cfg_write_default() return end
  cfg_parse(text)
  cfgt.text = text
end
cfg_load()

local function cfg_save()
  -- ⚠ io.open('w') 会**立刻截断**；中途出错会留下空文件（交接单记过）-> 要记下来
  local ok, err = pcall(function()
    local f = io.open(CFG_FILE, 'w')
    if not f then error('io.open 失败: ' .. tostring(CFG_FILE)) end
    f:write(cfg_text())
    f:close()
  end)
  if not ok then
    state.cfg_err = tostring(err)
    report('cfg 保存失败: ' .. tostring(err), true)
  else
    state.cfg_err = nil
    cfgt.text = nil                                -- 让自己下次写盘不回读旧文本
  end
  return ok
end

-- 秒级热重读：cfg 改完 1 秒内生效（不用重开游戏）
local cfg_at = 0
local function cfg_hot()
  local now = os.clock()
  if now - cfg_at < 1 then return end
  cfg_at = now
  local text = cfg_read()
  if text and text ~= cfgt.text then
    cfg_parse(text)
    cfgt.text = text
    state.last_gen = -1            -- ★ 下一帧立刻按新配置写一遍（不等 APPLY_EVERY）
    report('cfg 热重读: weapon=' .. tostring(CFG.weapon) ..
           ((CFG.weapon == 'custom') and (' custom=' .. tostring(CFG.custom)) or ''), true)
  end
end

-- 解析当前配置 -> 目标 item（16 位 BE hex）。返回 nil + 原因 = 拒写。
local function resolve_target()
  local w = CFG.weapon
  if w == 'ar23p' then return VANILLA, '原装（不改写）' end
  if w == 'mg43'  then return MG43, 'SEAF MG-43' end
  if w == 'custom' then
    local c = tostring(CFG.custom or ''):upper()
    if #c == 16 and c:match('^%x+$') and c ~= '0000000000000000' then
      return c, '自定义'
    end
    return nil, '自定义项不可用：cfg 里 custom 为空 / 非法（需要 16 位十六进制，且不能是全 0）'
  end
  return nil, '未知 weapon=' .. tostring(w)
end

-- ---------------------------------------------------------------- Scanner 前置（硬前置）
-- 读法 A：本 mod = 「判断条件 + 写入目标」+ 执行代码；Scanner 只负责「按类型哈希找到表、广播基址」。
-- ⚠ USE_SELF_SCAN / SCAN **必须声明在所有用它们的函数之前**（同一个坑交接单记过两次）。
local USE_SELF_SCAN = (rawget(_G, 'GD_USE_SELF_SCAN') == true)
local SCAN = { api = nil, retry_at = 0, warned = false, polls = 0 }

local function scanner_get()
  if SCAN.api then return SCAN.api end
  local now = os.clock()
  if now < SCAN.retry_at then return nil end
  SCAN.retry_at = now + 60
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and tonumber(S.version) == 1 and type(S.poll) == 'function' then
    SCAN.api = S
    if type(S.request) == 'function' then S.request(MG_TYPE, '护卫犬挂载自选') end
    report('已接上 HD2Scanner（前置）：MountComponentData 由 Scanner 提供', true)
    return S
  end
  if not SCAN.warned then
    SCAN.warned = true
    if USE_SELF_SCAN then
      report('未发现 _G.HD2Scanner —— 走自扫回滚路径（GD_USE_SELF_SCAN=true）', true)
    else
      report('未发现 _G.HD2Scanner —— 本 mod 以 HD2 Scanner 为前置（每 60 秒重试；自扫回滚需 _G.GD_USE_SELF_SCAN=true）', true)
    end
  end
  return nil
end

-- ---------------------------------------------------------------- 环境闸门（SKILL 6.18）
local ENV = { api = nil, version = nil, source = 'n/a' }
do
  local l = rawget(_G, 'CowboyBingusModLoader')
  if type(l) == 'table' then
    ENV.api, ENV.version, ENV.source = tonumber(l.api), tonumber(l.version), 'global'
  end
  if not ENV.api then
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
  dump('GuardDogLoadout_STATUS.log', msg .. '\n')
  report(msg, true)
  return
end

-- ---------------------------------------------------------------- ffi / kernel32
local ffi_ok, ffi = pcall(require, 'ffi')
local bit_ok, bit = pcall(require, 'bit')
local api_ok, api = pcall(function()
  assert(ffi_ok and ffi, 'ffi unavailable')
  assert(bit_ok and bit, 'bit unavailable')
  assert(ffi.abi('64bit'), 'x64 required')
  ffi.cdef [[
    typedef struct {
      uintptr_t BaseAddress; uintptr_t AllocationBase;
      uint32_t AllocationProtect; uint32_t PartitionId;
      size_t RegionSize; uint32_t State; uint32_t Protect; uint32_t Type;
    } GD_MBI;
    void  *GetCurrentProcess(void);
    int    ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
    int    WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
    int    VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
    size_t VirtualQuery(const void *address, GD_MBI *info, size_t length);
  ]]
  local kernel  = ffi.load('kernel32')
  local process = kernel.GetCurrentProcess()
  local M = {}
  function M.read(address, size)
    if not address or address <= 0 or size <= 0 then return nil end
    local buf, got = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
    pcall(kernel.ReadProcessMemory, process, ffi.cast('const void *', address), buf, size, got)
    if tonumber(got[0]) ~= size then return nil end
    return ffi.string(buf, size)
  end
  function M.write(address, bytes)
    local got = ffi.new('size_t[1]')
    local ok2 = pcall(kernel.WriteProcessMemory, process, ffi.cast('void *', address),
                      ffi.cast('const void *', bytes), #bytes, got)
    return ok2 and tonumber(got[0]) == #bytes
  end
  function M.unprotect(address, size)
    local old = ffi.new('uint32_t[1]')
    local ok2 = pcall(kernel.VirtualProtect, ffi.cast('void *', address), size, 0x40, old)
    if not ok2 then return nil end
    return tonumber(old[0])
  end
  function M.reprotect(address, size, value)
    local old = ffi.new('uint32_t[1]')
    pcall(kernel.VirtualProtect, ffi.cast('void *', address), size, value, old)
  end
  local mbi = ffi.new('GD_MBI[1]')
  function M.regions()
    local test_regions = rawget(_G, 'GD_TEST_REGIONS')
    if type(test_regions) == 'table' then return test_regions end
    local out, addr = {}, 0
    while addr < 0x7FFFFFFFFFFF do
      if kernel.VirtualQuery(ffi.cast('const void *', addr), mbi, ffi.sizeof(mbi)) == 0 then break end
      local base = tonumber(mbi[0].BaseAddress)
      local size = tonumber(mbi[0].RegionSize)
      local st   = tonumber(mbi[0].State)
      local prot = tonumber(mbi[0].Protect)
      if not base or not size or size <= 0 then break end
      local proto = bit.band(prot, 0xFF)
      local readable = bit.band(prot, 0x100) == 0 and
        (proto == 0x02 or proto == 0x04 or proto == 0x08 or proto == 0x20 or proto == 0x40 or proto == 0x80)
      if st == 0x1000 and readable then out[#out + 1] = { base = base, size = size } end
      addr = base + size
    end
    return out
  end
  return M
end)
if not api_ok then report('ffi/kernel32 不可用，写入关闭: ' .. tostring(api), true) end
local write_enabled = api_ok and api ~= nil

-- ---------------------------------------------------------------- 定位（与机甲同构）
-- 表头三件套：魔数 / version / 类型哈希（size 只做区间检查，不当指纹）
local function validate_table(magic)
  if not write_enabled then return nil end
  local h = api.read(magic, RDATA_OFF)
  if not h or #h < RDATA_OFF or h:sub(1, 4) ~= MAGIC then return nil end
  if d32(h, 4) ~= 1 or d32(h, 8) ~= MG_TYPE then return nil end
  local size = d32(h, 12)
  if not size or size < R_MIN or size > R_MAX then return nil end
  return size
end

-- 记录区起点候选：16 的倍数 + 剩余能被记录长整除 + 索引区每条都合法
local function layout_cands(data, size)
  local cands, ni = {}, 1
  while true do
    local b = ni * 16
    if b + REC_SR > size then break end
    if (size - b) % REC_SR == 0 then
      local n = (size - b) / REC_SR
      if n >= 20 then
        local good, k = true, 0
        while k + 16 <= b do
          if d32(data, k + 12) ~= 0 or d32(data, k + 8) >= n then good = false break end
          k = k + 16
        end
        if good then cands[#cands + 1] = { base = b, n = n } end
      end
    end
    ni = ni + 1
  end
  table.sort(cands, function(a, b2) return a.base > b2.base end)   -- 先试"索引区最长"的
  return cands
end

-- 索引区按【实体哈希的 LE 字节串】找 recIdx -> 记录在 data 里的偏移
local function find_rec(data, base, nr, ent_le)
  local q = data:find(ent_le, 1, true)
  while q do
    if (q - 1) % 16 == 0 and q - 1 + 16 <= base then
      local ix, pad = d32(data, q - 1 + 8), d32(data, q - 1 + 12)
      if pad == 0 and ix < nr then return base + ix * REC_SR, ix end
    end
    q = data:find(ent_le, q + 1, true)
  end
  return nil
end

-- 写 8 字节 + 回读校验（失败一律记 refuse，绝不当成功）
local function write8(address, bytes)
  if not write_enabled then return false end
  local old = api.unprotect(address, #bytes)
  if not old then
    state.refusals = state.refusals + 1
    report(('改页保护失败 0x%X'):format(address), true) return false
  end
  local wrote = api.write(address, bytes)
  api.reprotect(address, #bytes, old)
  if not wrote then
    state.refusals = state.refusals + 1
    report(('写失败 0x%X'):format(address), true) return false
  end
  if api.read(address, #bytes) ~= bytes then
    state.refusals = state.refusals + 1
    report(('回读校验失败 0x%X'):format(address), true) return false
  end
  return true
end

-- 一张表副本：推起点 -> 索引找 recIdx -> node/pad 复核 -> 写 +0 的 8 字节
--   mode = 'config'  写配置目标；mode = 'vanilla' 写回原装
local function apply_mount(magic, want_hex, mode, force)
  if not write_enabled then return false end
  local size = validate_table(magic)
  if not size then return false end
  if size > R_CAP then
    report(('表 0x%X 声明 size=%d 超过读取上限 %d，跳过'):format(magic, size, R_CAP), true)
    return false
  end
  local data = api.read(magic + RDATA_OFF, size)
  if not data then return false end

  -- ★ 只认【最大】的合法候选起点。为什么不能用"逐候选试到复核过为止"：
  --   起点比真值小 240 字节（= 2 条记录 = 15 个索引条目）时，"索引区"退化成
  --   真索引的一个前缀，**仍然全部合法**；而同一个 recIdx 会指到早两条的
  --   另一个记录 —— 那个记录往往共用同一个 node（node 是"槽位类型"，不是实体
  --   指纹，很多记录都填 0x53BEC437），node/pad 复核抓不住它，就会写错记录。
  --   真值的判据：从真起点再往上扩 15 个条目，第 1 个伪条目就落在记录区偏移 0，
  --   它的 +8 是 node（1e9 量级）必然 >= 记录数 -> 那一档候选一定被 layout_cands
  --   否掉。所以"最大合法候选"= 真起点（已用真表镜像验证：4912 与 5152 都合法，
  --   只有 5152 指向 drone_mg 的 97 号记录）。
  local cands = layout_cands(data, size)
  local cand = cands[1]
  local rec_off, rec_ix
  if cand then rec_off, rec_ix = find_rec(data, cand.base, cand.n, ENT_LE) end
  if not cand or not rec_off then
    if not state.warn_at or state.frame - state.warn_at > 6000 then
      state.warn_at = state.frame
      report(('表 0x%X：找不到 drone_mg 记录（%d 个合法起点 / size=%d），本轮拒写'):format(
        magic, #cands, size), true)
    end
    return false
  end
  local got_node, got_pad = d32(data, rec_off + 8), d32(data, rec_off + 12)
  if got_node ~= NODE or got_pad ~= 0 then
    if not state.warn_at or state.frame - state.warn_at > 6000 then
      state.warn_at = state.frame
      report(('表 0x%X：drone_mg 记录（recIdx %d）node/pad 复核不过（%d / %d，应 %d / 0），本轮拒写'):format(
        magic, rec_ix, got_node, got_pad, NODE), true)
    end
    return false
  end
  state.layout, state.rec_ix = cand.base, rec_ix

  local address = magic + RDATA_OFF + rec_off
  local cur = data:sub(rec_off + 1, rec_off + 8)
  local want_le = le(want_hex)
  -- ★ 写入保护（SKILL 6.24）：只认「原装」「本次目标」「**上次自己写过的值**」，其余拒写。
  --   为什么必须认 last：第一次写完后 cur 就等于上次目标；不认 last 的话，
  --   第二次换目标（原装 -> A -> B）会把 A 当成陌生值而拒写（机甲 mod 踩过这个坑）。
  --   orig 一并存下来，供「初始化」强制回原装（SKILL 6.25）。
  local info = state.slots[address]
  local last = info and info.item
  if cur == want_le then
    state.slots[address] = { item = want_hex, orig = VANILLA }
    return false
  end
  --   ⚠ 原装目标不受保护限制：写回原装永远是安全的，而且玩家从别的 mod/旧版本
  --   切过来时当前值就是"陌生值"，这时必须能回去（否则会被自己的保护困死）。
  if force or want_hex == VANILLA or cur == le(VANILLA) or (last and cur == le(last)) then
    if write8(address, want_le) then
      state.writes = state.writes + 1
      state.slots[address] = { item = want_hex, orig = VANILLA }
      report(('%s：drone_mg 挂载 %s -> %s（recIdx %d，node=0x%08X/pad=0 未动）'):format(
        force and '强制还原' or ((mode == 'vanilla') and '还原' or '已写'),
        hexs(cur), want_hex, rec_ix, NODE), true)
      return true
    end
    return false
  end
  state.refusals = state.refusals + 1
  report(('拒写：drone_mg 挂载当前 %s 既非原装（%s）也非上次自己写过的值（%s）（recIdx %d）；要强写请点「初始化」'):format(
    hexs(cur), VANILLA, tostring(last or '无'), rec_ix), true)
  return false
end

-- 对 Scanner 广播的每一张表副本跑一遍
local function apply_snap(snap, want_hex, mode, force)
  local n = 0
  if type(snap) == 'table' and type(snap.entries) == 'table' then
    for i = 1, #snap.entries do
      local e = snap.entries[i]
      if type(e) == 'table' and type(e.addr) == 'number' then
        local ok2, err = pcall(apply_mount, e.addr, want_hex, mode, force)
        if not ok2 then
          state.errs = state.errs + 1
          if state.errs <= 3 then report('apply_mount 异常: ' .. tostring(err), true) end
        else
          n = n + 1
        end
      end
    end
  end
  return n
end

-- 写后复查：被游戏冲掉就重写
local function recheck()
  if not write_enabled then return 0 end
  local live, fixed, drop = 0, 0, 0
  for address, info in pairs(state.slots) do
    local item = info and info.item
    local cur = item and api.read(address, 8) or nil
    if cur and cur == le(item) then
      live = live + 1
    elseif write8(address, le(item)) then
      state.writes = state.writes + 1
      live, fixed = live + 1, fixed + 1
    else
      state.slots[address] = nil
      drop = drop + 1
    end
  end
  if fixed > 0 then report(('复查：重写被冲掉的补丁 %d 处'):format(fixed), true) end
  if drop  > 0 then report(('复查：丢弃失效地址 %d 处'):format(drop), true) end
  return live
end

-- 把所有 tracked 槽位写回 orig（原装）。初始化用（SKILL 6.25）。
local function restore_vanilla_all()
  if not write_enabled then return 0 end
  local n = 0
  for address, info in pairs(state.slots or {}) do
    local orig = info and info.orig
    if orig then
      local cur = api.read(address, 8)
      if cur and cur ~= le(orig) then
        if write8(address, le(orig)) then n = n + 1 end
      end
    end
  end
  state.slots = {}
  return n
end

-- ---------------------------------------------------------------- 自扫回滚（GD_USE_SELF_SCAN）
-- 没有 Scanner 时的兜底：按 LDLD + 类型哈希自己找表，然后走同一条 apply_mount。
-- 分片：每帧最多读 SELF_BUDGET 字节，不卡帧。
local selfw = { regions = nil, ri = 1, off = 0, tail = nil, next_at = 0 }
local SELF_CHUNK  = 1 * 1024 * 1024
local SELF_BUDGET = 4 * 1024 * 1024

local function self_scan_reset()
  selfw.regions, selfw.ri, selfw.off, selfw.tail = nil, 1, 0, nil
end

local function self_scan_step(want_hex, mode)
  if not write_enabled then return end
  -- 一轮全扫很贵（要读遍所有可读页），所以两轮之间隔 30 秒；
  -- 真正的数据源是 Scanner，这条路只是没有前置时的兜底。
  if not selfw.regions and os.clock() < selfw.next_at then return end
  if not selfw.regions then
    selfw.regions = api.regions()
    selfw.ri, selfw.off, selfw.tail = 1, 0, nil
    report(('自扫开始：%d 个可读区域'):format(#selfw.regions), true)
    if #selfw.regions == 0 then selfw.regions = nil return end
  end
  local budget = SELF_BUDGET
  while budget > 0 and selfw.ri <= #selfw.regions do
    local r = selfw.regions[selfw.ri]
    if selfw.off >= r.size then
      selfw.ri, selfw.off, selfw.tail = selfw.ri + 1, 0, nil
    else
      local n = math.min(SELF_CHUNK, r.size - selfw.off)
      local chunk = api.read(r.base + selfw.off, n)
      local chunk_base = r.base + selfw.off - (selfw.tail and #selfw.tail or 0)
      if chunk then
        local data = selfw.tail and (selfw.tail .. chunk) or chunk
        local from = 1
        while true do
          local f = data:find(MAGIC, from, true)
          if not f then break end
          from = f + 1
          local addr = chunk_base + f - 1
          if validate_table(addr) then
            local ok2, err = pcall(apply_mount, addr, want_hex, mode)
            if not ok2 then
              state.errs = state.errs + 1
              if state.errs <= 3 then report('自扫 apply 异常: ' .. tostring(err), true) end
            end
          end
        end
        selfw.tail = chunk:sub(-3)
      end
      selfw.off = selfw.off + n
      budget = budget - n
      if selfw.off >= r.size then selfw.ri, selfw.off, selfw.tail = selfw.ri + 1, 0, nil end
    end
  end
  if selfw.ri > #selfw.regions then
    state.phase = 'selfscan-done'
    report(('自扫完成：看完 %d 个区域，累计写 %d 处（下一轮 30 秒后）'):format(#selfw.regions, state.writes), true)
    selfw.next_at = os.clock() + 30
    self_scan_reset()
  end
end

-- ---------------------------------------------------------------- 状态落盘
local function write_status()
  local live = 0
  for _ in pairs(state.slots) do live = live + 1 end
  local want, why = resolve_target()
  local first
  if want and live > 0 then first = ('OK - 补丁生效中（%d 处）'):format(live)
  elseif want           then first = 'WORKING - 等待挂载表'
  else                       first = 'FAILED - ' .. tostring(why) end
  dump('GuardDogLoadout_STATUS.log', table.concat({
    first,
    'revision=guard-dog-loadout-' .. VERSION,
    'phase=' .. tostring(state.phase),
    ('weapon=%s%s'):format(tostring(CFG.weapon),
      (CFG.weapon == 'custom') and ('  custom=' .. tostring(CFG.custom)) or ''),
    ('目标 item = %s'):format(want or '(无)'),
    ('原装 item = %s（初始化回这个）'):format(VANILLA),
    ('实体 = %s   recIdx = %s   挂载位点 node = %d (0x%08X)'):format(
      ENT_HEX, tostring(state.rec_ix or '?'), NODE, NODE),
    ('记录区起点 = %s（运行时推，不硬编码）'):format(tostring(state.layout or '?')),
    ('前置 = Bingus Shared Loader loader-v%s / API %s（%s）'):format(
      tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)),
    ('Scanner = %s   polls = %d'):format(SCAN.api and '已接上' or '无', SCAN.polls),
    ('已写=%d 拒绝=%d 帧=%d 存活=%d'):format(state.writes, state.refusals, state.frame, live),
    'updated=' .. os.date('%Y-%m-%d %H:%M:%S'),
  }, '\n') .. '\n')
end

-- ---------------------------------------------------------------- 每帧
local APPLY_EVERY, RECHECK_EVERY, STATUS_EVERY = 60, 300, 300

local function frame()
  state.frame = state.frame + 1
  cfg_hot()
  flush_log()

  local want, why = resolve_target()
  if not want then
    report('拒写：' .. tostring(why), true)
    if state.frame % STATUS_EVERY == 0 then write_status() end
    return
  end

  local S = scanner_get()
  if not S then
    if USE_SELF_SCAN then self_scan_step(want, 'config') end
    if state.frame % STATUS_EVERY == 0 then write_status() end
    return
  end

  local snap = S.poll(MG_TYPE)
  SCAN.polls = SCAN.polls + 1
  local gen = (type(snap) == 'table' and tonumber(snap.generation)) or 0
  if gen ~= state.last_gen or (state.frame % APPLY_EVERY == 0) then
    state.last_gen = gen
    local w0 = state.writes
    apply_snap(snap, want, 'config')
    if state.writes > w0 then
      state.phase = 'armed'
      write_status()                       -- 刚写成功：立刻落一份状态
    end
  end
  if state.frame % RECHECK_EVERY == 0 then
    if recheck() == 0 and state.phase == 'armed' then state.phase = 'waiting' end
  end
  if state.frame % STATUS_EVERY == 0 then write_status() end
end

-- ---------------------------------------------------------------- 设置项
local MOD_OPTIONS = { registered = false }

local function set_weapon(name)
  local k = WEAPON_KEY[name]
  if not k then return end
  CFG.weapon = k
  cfg_save()
  state.last_gen = -1              -- ★ 立刻按新目标写一遍
  report(('cfg: weapon=%s%s'):format(k,
    (k == 'custom') and (' custom=' .. tostring(CFG.custom)) or ''), true)
end

-- 初始化（SKILL 6.25）：回**原始默认**，不是回上次 cfg。
--   顺序：tracked 槽位写回原装 -> 强制写一遍（vanilla_force，无视"陌生值拒写"）
--        -> cfg 复位为 AR-23P/空 -> 清运行时状态 -> 落盘 -> 同步 ModOptionsMenu。
--   初始化**不读** GuardDogLoadout.cfg（上次退出的 cfg 是错误语义）。
local function do_initialize()
  restore_vanilla_all()                       -- ① 已 track 的槽位写回原装
  local S = rawget(_G, 'HD2Scanner')          -- ② vanilla_force：当前值不论是什么都强写
  if write_enabled and type(S) == 'table' and type(S.poll) == 'function' then
    pcall(apply_snap, S.poll(MG_TYPE), VANILLA, 'vanilla', true)
  end
  CFG.weapon, CFG.custom = 'ar23p', ''        -- ③ cfg 回默认
  state.slots, state.layout, state.rec_ix = {}, nil, nil
  state.last_gen = -1                         -- 下一帧立刻重扫一遍
  cfg_save()                                  -- ④ 落盘
  if MOD_OPTIONS.registered then              -- ⑤ 同步原生 MODS 页
    local mom = rawget(_G, 'ModOptionsMenu')
    if type(mom) == 'table' then
      pcall(function() mom.set('guard_dog_loadout.weapon', 1) end)
      pcall(function() mom.set('guard_dog_loadout.reset', false) end)
    end
  end
  report('初始化：已强制写回原装，cfg 复位为 AR-23P（原装）', true)
end

-- ---------------------------------------------------------------- 菜单面板插件
local function menu_attach(menu)
  menu.register{
    id = 'guard_dog_loadout', title = '护卫犬挂载自选', order = 45, api = 1,
    status = function()
      local want = resolve_target()
      if not want then return { text = '配置无效', tone = 'bad', note = 'custom 空/非法' } end
      local live = 0
      for _ in pairs(state.slots) do live = live + 1 end
      if live > 0 then return { text = '已生效', tone = 'ok', note = tostring(live) .. ' 处' } end
      if SCAN.api then return { text = '待写入', tone = 'warn', note = '等待挂载表' } end
      return { text = '缺前置', tone = 'bad', note = '无 HD2Scanner' }
    end,
    build = function(pctx)
      local D = tonumber(pctx and pctx.detail) or 2
      if D < 1 or D > 3 then D = 2 end
      local rows = {}
      local function add(l, v, tone, note)
        rows[#rows + 1] = { label = l, value = tostring(v), tone = tone or 'text', note = note }
      end

      rows[#rows + 1] = { label = '下挂物品', kind = 'choice', choices = WEAPON_CHOICES,
        get = function() return WEAPON_LABEL[CFG.weapon] or WEAPON_CHOICES[1] end,
        set = function(v) set_weapon(v) end }

      local want, why = resolve_target()
      add('目标 item', want or '(无效)', want and 'ok' or 'bad', want and nil or why)
      if CFG.weapon == 'custom' then
        add('cfg.custom', (CFG.custom ~= '' and CFG.custom) or '(空)', (CFG.custom ~= '') and 'dim' or 'warn',
            '改完 1 秒热生效')
      end

      rows[#rows + 1] = { label = '立刻写一次', kind = 'action', on_click = function()
        local w2, why2 = resolve_target()
        if not w2 then report('立刻写一次：' .. tostring(why2), true) return end
        local S = scanner_get()
        if not S then
          if USE_SELF_SCAN then self_scan_step(w2, 'config') end
          report('立刻写一次：没有 Scanner 前置，写不了', true)
          return
        end
        local n = apply_snap(S.poll(MG_TYPE), w2, 'config')
        recheck()
        report(('立刻写一次：处理 %d 份表，累计写 %d 处'):format(n, state.writes), true)
      end }

      rows[#rows + 1] = { label = '初始化（强制写回原装 + cfg 复位）', kind = 'action', on_click = do_initialize }

      if D >= 3 then
        add('实体 drone_mg', ENT_HEX, 'dim', '挂载母体')
        add('挂载位点 node', ('%d (0x%08X)'):format(NODE, NODE), 'dim', '记录 +8 复核')
        add('recIdx', state.rec_ix or '?', 'dim', '运行时从索引区取')
        add('记录区起点', state.layout or '?', 'dim', '运行时推，不硬编码')
        add('Scanner', SCAN.api and '已接上' or '无', SCAN.api and 'ok' or 'bad', 'MountComponentData')
        add('自扫回滚', USE_SELF_SCAN and '开' or '关', 'dim', 'GD_USE_SELF_SCAN')
        add('cfg', CFG_FILE or '?', 'dim', '1 秒热生效')
        add('写 / 拒 / 帧', ('%d / %d / %d'):format(state.writes, state.refusals, state.frame), 'dim', nil)
        add('poll 次数', SCAN.polls, 'dim', nil)
      end
      return rows
    end,
  }
end

local Q = rawget(_G, 'HD2MenuQueue')
if type(Q) == 'table' then
  Q[#Q + 1] = { id = 'guard_dog_loadout', attach = menu_attach }
elseif rawget(_G, 'HD2Menu') then
  pcall(menu_attach, rawget(_G, 'HD2Menu'))
end

-- ---------------------------------------------------------------- ModOptionsMenu 适配
local function register_mod_options()
  if MOD_OPTIONS.registered then return end
  local mom = rawget(_G, 'ModOptionsMenu')
  if type(mom) ~= 'table' or mom.api ~= 1 then return end
  MOD_OPTIONS.registered = true

  local id = 'guard_dog_loadout.weapon'
  local function index_of(key)
    for i, k in ipairs({ 'ar23p', 'mg43', 'custom' }) do if k == key then return i end end
    return 1
  end
  -- ★ 自定义哈希没有文本框（Scanner 面板是纯鼠标的），所以把 cfg 的**完整路径**
  --   写进 ModOptionsMenu 的描述页 —— 玩家选中这一项时，右边直接看得到该改哪个文件。
  --   （写法与机甲 mod 一致：description = '...' 是选项表里的一个字段）
  mom.register_option(id, { type = 'choice', label = '下挂物品', mod = '护卫犬挂载自选',
    choices = WEAPON_CHOICES, default = index_of(CFG.weapon),
    description = 'AR-23P = 原装（不改写）；MG-43 = SEAF。'
               .. '自定义 = 读 cfg 文件 ' .. tostring(CFG_FILE)
               .. ' 的 custom 行（16 位 BE 十六进制物品哈希；留空则该选项不可用）。改完 1 秒热生效。' })
  mom.on_change(id, function(v)
    local name = WEAPON_CHOICES[tonumber(v) or 0]
    if name then set_weapon(name) end
  end)

  local rid = 'guard_dog_loadout.reset'
  mom.register_option(rid, { type = 'toggle', label = '初始化（写回原装 + cfg 复位）',
    mod = '护卫犬挂载自选', default = false })
  mom.on_change(rid, function(v)
    if not v then return end
    do_initialize()
    mom.set(id, index_of(CFG.weapon))
    mom.set(rid, false)
  end)

  report('ModOptionsMenu: 护卫犬挂载自选已注册到原生 MODS 页', true)
end

-- ---------------------------------------------------------------- 挂载
local prev_update = update
if type(prev_update) == 'function' then
  update = function(...)
    local ok2, err = pcall(frame)
    if not ok2 then
      state.errs = state.errs + 1
      if state.errs <= 5 then report('frame error: ' .. tostring(err)) end
    end
    local ok3, err3 = pcall(register_mod_options)
    if not ok3 then
      state.errs = state.errs + 1
      if state.errs <= 5 then report('ModOptionsMenu error: ' .. tostring(err3)) end
    end
    return prev_update(...)
  end
end

report(('已加载 v%s（目标=%s；Scanner 前置；自定义读 cfg）'):format(
  VERSION, tostring(WEAPON_LABEL[CFG.weapon] or CFG.weapon)), true)