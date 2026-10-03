-- HD2-Addon: mods/dsh/custom_supply

-- ===========================================================================
--  自定义补给 v0.1a（CUSTOM-SUPPLY）
--
--  机制：补给包架 4 个槽位各填一件（6 选 1），内容决定冷却：
--     CD = 30 + 5·弹药盒 + 30·治疗针剂 + 15·手榴弹包 + 30·补给(模型) + 15·医疗补给(模型)
--     4 槽全「无」→ 30 s；区间 30 ~ 150 s
--
--  写入三处（都要等进任务、表加载之后；内存写是会话级，每局重写）：
--     ① 包架记录 HellpodRackComponent（ID77 用的 health_pack_rack）的 4 个激活槽：
--          RackAttach[i].item @+0x00 / offset @+0x0C / rotation_offset @+0x18
--     ② 战备记录 StratagemInfo[77].cooldown_success @+0x68（float32，秒）
--     ③ 让 ID77「可用」（自包含，不依赖 Strat-Unlock）：
--          StratagemInfo[77] +0x80 bit1 = 1（=数据表 selectable）
--          注册表记录 +0x14 = 2（∈{2,4} 即可用）
--
--  依据：hd2-mod/docs/SUPPLY-CUSTOM-设计定稿.md（typelib / rawdata JSON / AC8 实测三方印证）
--  红线：所有写入 = 预检 → 改页保护 → 写 → 回读 → 失败写回原值
-- ===========================================================================

local VERSION = '0.1b'
local MOD = 'mods/dsh/custom_supply'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, status = 'starting', writes = 0, errs = 0, applied = false })
local state = rawget(_G, MOD)

-- ============================================================ 纯逻辑（可离线测试）
local function hex_le(hex)                       -- "3B8D16C646A729A8" -> 小端字节串
  local out = {}
  for i = #hex - 1, 1, -2 do out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16)) end
  return table.concat(out)
end

local ITEMS = {                                  -- 顺序 = MOM 下拉顺序（索引 1..6）
  -- name = 简称（MOM 下拉 / 日志用）；full = 官方长名（文档 / 对照用）
  { key = 'none',    name = '无',      full = '无',                hex = nil,                cd = 0  },
  { key = 'ammo',    name = '弹药盒',  full = '资源点弹药盒',       hex = '79CCFFD281E3F3A9', cd = 5  },
  { key = 'stim',    name = '针剂盒',  full = '资源点治疗针剂',     hex = 'B4CA4C5B922F7965', cd = 30 },
  { key = 'grenade', name = '手雷盒',  full = '资源点手榴弹包',     hex = '97AF34FBF093409C', cd = 15 },
  { key = 'cache',   name = '补给包',  full = '补给（模型）',       hex = 'A94913CA014F7579', cd = 30 },
  { key = 'medical', name = '医疗包',  full = '医疗补给（模型）',   hex = '3B8D16C646A729A8', cd = 15 },
}
for _, e in ipairs(ITEMS) do
  e.hash_le = e.hex and hex_le(e.hex) or nil
  e.none = (e.hex == nil)
end
local IDX = {}
for i, e in ipairs(ITEMS) do IDX[e.key] = i end

-- 规范值（预设）：只有这两件有手调值；其余 = 原装（全 0）
local PRESET = {
  stim    = { off = { 0.0, -0.1, -0.1 }, rot = { -90.0, 0.0, 0.0 } },
  grenade = { off = { 0.1, -0.3,  0.0 }, rot = { -90.0, 0.0, 0.0 } },
}
local CD_BASE = 30
local SLOTS = 4
local function compute_cd(sel)                   -- sel = { 物品索引×4 }
  local cd, detail = CD_BASE, {}
  for i = 1, SLOTS do
    local e = ITEMS[tonumber(sel[i]) or 1] or ITEMS[1]
    cd = cd + e.cd
    if not e.none then detail[#detail + 1] = e.name end
  end
  return cd, detail
end
state.ITEMS, state.PRESET, state.compute_cd, state.hex_le, state.IDX = ITEMS, PRESET, compute_cd, hex_le, IDX
state.CD_BASE, state.SLOTS = CD_BASE, SLOTS
state.VERSION = VERSION

-- ============================================================ 日志三件套
local LOG_CAP = 300
local loghist, log_dirty, log_at = {}, false, -10
local function flush_log(force)
  if #loghist == 0 then return end
  local now = os.clock()
  if not force and (not log_dirty or now - log_at < 1) then return end
  log_dirty, log_at = false, now
  local text = table.concat(loghist, '\n') .. '\n'
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local f = loader and loader.open_log and loader.open_log('CustomSupply.log')
    if f then f:write(text); f:close() end
  end)
end
local function report(msg, keep)
  if msg == state.status then
    state.repeat_n = (state.repeat_n or 1) + 1
    if #loghist > 0 then
      loghist[#loghist] = ('[frame %d] %s  (×%d)'):format(state.frame, msg, state.repeat_n)
      log_dirty = true
    end
    return
  end
  state.status, state.repeat_n = msg, 1
  print('[CustomSupply] ' .. msg)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, msg)
  if #loghist > LOG_CAP then table.remove(loghist, 1) end
  log_dirty = true
  if keep then flush_log(true) end
end

-- ============================================================ 配置（MOM 优先，cfg 兜底）
local CFG_SEL = { IDX.none, IDX.none, IDX.none, IDX.none }   -- mod 默认状态 = 四槽全无 → CD 30 s
-- 参考：保留原装内容（医疗包 ×4）时 CD = 90 s
local function load_cfg()
  local f = io and io.open('CustomSupply.cfg', 'r')
  if not f then return end
  local text = tostring(f:read('*a')); f:close()
  for i = 1, SLOTS do
    local key = text:match('slot' .. i .. '%s*=%s*([%a_]+)')
    if key and IDX[key] then CFG_SEL[i] = IDX[key] end
  end
  report(('cfg：slot1..4 = %s'):format((function()
    local t = {} for i = 1, SLOTS do t[i] = ITEMS[CFG_SEL[i]].name end return table.concat(t, ' / ')
  end)()), true)
end

-- ============================================================ ffi / kernel32
local ffi_ok, ffi = pcall(require, 'ffi')
local api_ok, api = pcall(function()
  assert(ffi_ok and ffi, 'ffi unavailable')
  assert(ffi.abi('64bit'), 'x64 only')
  local miss = {}
  local function cd(sig, tag)
    local o, e = pcall(ffi.cdef, sig)
    if not o then miss[#miss + 1] = tag .. ':' .. tostring(e) end
  end
  cd([[ typedef struct { uintptr_t BaseAddress; uintptr_t AllocationBase; uint32_t AllocationProtect;
        uint32_t PartitionId; size_t RegionSize; uint32_t State; uint32_t Protect; uint32_t Type; } CS_MBI; ]], 'mbi')
  cd('void *GetModuleHandleA(const char *name);', 'gmh')
  cd('void *GetCurrentProcess(void);', 'gcp')
  cd('int ReadProcessMemory(void *p, const void *a, void *b, size_t s, size_t *r);', 'rpm')
  cd('int WriteProcessMemory(void *p, void *a, const void *b, size_t s, size_t *w);', 'wpm')
  cd('int VirtualProtect(void *a, size_t s, uint32_t np, uint32_t *old);', 'vp')
  cd('size_t VirtualQuery(const void *a, CS_MBI *i, size_t l);', 'vq')
  local k = ffi.load('kernel32')
  local process = k.GetCurrentProcess()
  local a = { missing = miss }
  function a.GetModuleHandleA(name) return k.GetModuleHandleA(name) end
  function a.read(address, size)
    local buf, got = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
    if k.ReadProcessMemory(process, ffi.cast('const void *', address), buf, size, got) == 0 then return nil end
    if tonumber(got[0]) ~= size then return nil end
    return ffi.string(buf, size)
  end
  function a.write(address, bytes)
    local n = #bytes
    local got = ffi.new('size_t[1]')
    local rc = k.WriteProcessMemory(process, ffi.cast('void *', address), ffi.cast('const void *', bytes), n, got)
    if rc == 0 then return false end
    return tonumber(got[0]) == n
  end
  function a.unprotect(address, size)
    local old = ffi.new('uint32_t[1]')
    if k.VirtualProtect(ffi.cast('void *', address), size, 0x40, old) == 0 then return nil end
    return tonumber(old[0])
  end
  function a.reprotect(address, size, value)
    local old = ffi.new('uint32_t[1]')
    k.VirtualProtect(ffi.cast('void *', address), size, value, old)
  end
  return a
end)
local write_enabled = api_ok and api ~= nil
if api_ok and api and api.missing and #api.missing > 0 then
  report('cdef 缺失: ' .. table.concat(api.missing, ' | '), true)
  write_enabled = false
end
if not write_enabled then report('ffi/kernel32 不可用，只做诊断不写入: ' .. tostring(api), true) end

-- ============================================================ 工具
local function u32(s, off)
  off = off or 0
  if type(s) ~= 'string' or #s < off + 4 then return nil end
  local a, b, c, d = s:byte(off + 1, off + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function u64(s, off)
  local lo, hi = u32(s, off), u32(s, off + 4)
  if not lo or not hi then return nil end
  return lo + hi * 4294967296
end
local function f32(s, off)
  local v = u32(s, off or 0)
  if not v then return nil end
  local sign = 1
  if v >= 0x80000000 then sign, v = -1, v - 0x80000000 end
  local exp = math.floor(v / 0x800000)
  local mant = v % 0x800000
  if exp == 0 then
    if mant == 0 then return 0 end
    return sign * (mant / 0x800000) * 2 ^ (-126)
  elseif exp == 255 then
    return mant == 0 and (sign * math.huge) or (0 / 0)
  end
  return sign * (1 + mant / 0x800000) * 2 ^ (exp - 127)
end
local function le32(v)
  v = v % 4294967296
  return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function le_f32(x)
  local neg = false
  if x < 0 then neg, x = true, -x end
  local bits
  if x == 0 then bits = 0
  else
    local exp = math.floor(math.log(x) / math.log(2))
    if exp < -126 then bits = 0
    else
      local mant = math.floor((x / 2 ^ exp - 1) * 0x800000 + 0.5)
      if mant >= 0x800000 then mant, exp = 0, exp + 1 end
      bits = (exp + 127) * 0x800000 + mant
    end
  end
  if neg then bits = bits + 0x80000000 end
  return le32(bits)
end
state.u32, state.u64, state.f32, state.le_f32 = u32, u64, f32, le_f32

-- ============================================================ 写入基元
local function write_bytes(addr, bytes, label)
  if not write_enabled then return false, '写入被禁用' end
  local n = #bytes
  local old = api.read(addr, n)
  if not old then return false, '写前读不到' end
  if old == bytes then return true, old, true end          -- 已是目标值（幂等）
  local prot = api.unprotect(addr, n)
  if not prot then state.errs = state.errs + 1 return false, '改页保护失败' end
  local ok = api.write(addr, bytes)
  api.reprotect(addr, n, prot)
  if not ok then state.errs = state.errs + 1 return false, 'WriteProcessMemory 失败' end
  if api.read(addr, n) ~= bytes then
    state.errs = state.errs + 1
    local p2 = api.unprotect(addr, n)
    api.write(addr, old)
    api.reprotect(addr, n, p2)
    return false, '回读不符（已写回原值）'
  end
  state.writes = state.writes + 1
  return true, old, false
end

-- ============================================================ 战备表定位（交给 Scanner）
--  SKILL §6.20：全量扫描一律走 Scanner 的公共服务，mod 只做校验和写。
--  Scanner v0.8.0+ 提供 strat_table_request / strat_table_status / strat_slot / strat_rec，
--  其中 strat_slot(id) 直接返回 StratagemInfo 指针 —— 正是我们要写的地址。
--  兜底：只走"固定 RVA + 签名校验"（不扫描，只有两次小读），版本不符就拒写。
local RVA_ITEM_SLOT = 0x347CEF8
local RVA_FUNC, SIG_FUNC, RVA_LEA_B = 0x136FC20, '\x48\x89\x5C\x24\x08\x48\x8B\xD9\x85\xD2\x75', 0x136FC3A
local ROOT_COUNT, ROOT_RECS, ROOT_MAPS, ROOT_GATE = 0x1CE0, 0x1CE4, 0xB9CE4, 0xDDCF8
local REG_REC, REG_MAP = 184, 24
local ID_TARGET = 77
local KEY_TARGET = 2229216190            -- HEALTH PACK RACK 的 key（0x84DF23BE）
local BIT_SEL = 0x80
local OFF_USES, OFF_CD, OFF_NAME = 0x50, 0x68, 0x10
local ADDR = { base = nil, tbl = nil, slot = nil, route = nil }

local function scanner()
  local S = rawget(_G, 'HD2Scanner')
  if type(S) ~= 'table' then return nil, 'Scanner 未安装' end
  if type(S.strat_table_request) ~= 'function' or type(S.strat_slot) ~= 'function'
     or type(S.scan_request) ~= 'function' then
    return nil, 'Scanner 版本过旧（需要 v0.8.0+ 的 strat_* / scan_request）'
  end
  return S
end

local function module_base()
  local fn = api and api.GetModuleHandleA
  if type(fn) ~= 'function' then return nil end
  local h = fn('game.dll')
  if h == nil then return nil end
  local v = tonumber(ffi.cast('uintptr_t', h))          -- cdata NULL 不等于 nil，必须按数值判
  if not v or v == 0 then return nil end
  return v
end

-- 兜底：固定 RVA + 签名校验（不做任何扫描）
local function route_fixed()
  local base = module_base()
  if not base then return nil, nil, 'game.dll 拿不到' end
  if api.read(base + RVA_FUNC, 11) ~= SIG_FUNC then return nil, base, '判定函数签名不符（版本已变，拒写）' end
  local d = api.read(base + RVA_LEA_B, 4)
  local tbl = base + RVA_LEA_B + 4 + (u32(d, 0) or 0)
  return tbl, base, 'FIXED-RVA'
end

-- 拿 StratagemInfo 指针（Scanner 优先，兜底固定 RVA）
local function strat_ptr(id)
  local S = scanner()
  if S then
    pcall(S.strat_table_request)                       -- 幂等：正在扫/已成功都直接返回
    local ok, ptr = pcall(S.strat_slot, id)
    if ok and type(ptr) == 'number' and ptr > 0x10000 then
      ADDR.route = 'SCANNER'
      local base = module_base()
      if base then ADDR.base, ADDR.slot = base, base + RVA_ITEM_SLOT end
      return ptr, 'SCANNER'
    end
    local st = select(2, pcall(S.strat_table_status))
    if type(st) == 'table' and st.state ~= 'ok' then
      return nil, ('Scanner 战备表 state=%s'):format(tostring(st.state))
    end
  end
  local tbl, base, route = route_fixed()
  if not tbl then return nil, tostring(route) end
  ADDR.base, ADDR.tbl, ADDR.slot, ADDR.route = base, tbl, base + RVA_ITEM_SLOT, route
  local p = u64(api.read(tbl + id * 8, 8), 0)
  if not p or p < 0x10000 then return nil, '兜底：id 指针为空' end
  return p, route
end

local function strat_info(id)
  if not write_enabled then return nil, 'ffi 不可用' end
  local ptr, why = strat_ptr(id)
  if not ptr then return nil, why end
  local si = api.read(ptr, 0xD0)
  if not si then return nil, ('id=%d StratagemInfo 读不到'):format(id) end
  return ptr, si
end

local function reg_record(ptr)
  local base = module_base()
  local root_addr = ADDR.slot or (base and base + RVA_ITEM_SLOT)
  if not root_addr then
    return nil, ('item_slot 地址拿不到（base=%s, GetModuleHandleA=%s）'):format(
      tostring(base), type(api and api.GetModuleHandleA)) 
  end
  local root = u64(api.read(root_addr, 8), 0)
  if not root or root == 0 then return nil, '注册表根为空（表未加载）' end
  local gate = u32(api.read(root + ROOT_GATE, 4), 0)
  if gate ~= 12 then return nil, ('门闸 = %s（期望 12）'):format(tostring(gate)) end
  local cnt = u32(api.read(root + ROOT_COUNT, 4), 0)
  if not cnt or cnt <= 0 or cnt > 4096 then return nil, '条目数异常' end
  local key = u32(api.read(ptr + 4, 4), 0)
  if not key then return nil, '读不到 key' end
  local maps = api.read(root + ROOT_MAPS, cnt * REG_MAP)
  if not maps then return nil, 'mappings 读不到' end
  for i = 0, cnt - 1 do
    if u32(maps, i * REG_MAP + 8) == key then
      return root + ROOT_RECS + i * REG_REC + 0x14, i, key
    end
  end
  return nil, ('mappings 里没有 key=0x%X'):format(key)
end

-- ============================================================ 包架表定位（LDLD + 内容锚点）
local RACK_TYPE = hex_le('A98BB156')          -- djb2('HellpodRackComponentData')
local RACK_SIG = 'LDLD' .. string.char(1, 0, 0, 0) .. RACK_TYPE
local RACK_SLOT, RACK_SPAWN_OFF = 64, 0x22C
local SL_ITEM, SL_NODE, SL_OFF, SL_ROT, SL_SIDE = 0x00, 0x08, 0x0C, 0x18, 0x34
local ANCHOR = ITEMS[IDX.medical].hash_le      -- 原装 health_pack_rack 的 4 槽都是它
local RACKADDR = nil

local function rack_find_in(block)
  local pos = 1
  while true do
    local q = block:find(ANCHOR, pos, true)
    if not q then return nil end
    pos = q + 1
    local ok = true
    for k = 1, SLOTS - 1 do                    -- 4 槽同物、步长 64
      if block:sub(q + k * RACK_SLOT, q + k * RACK_SLOT + 7) ~= ANCHOR then ok = false break end
    end
    if ok then
      local base = q - 1
      local spawn = u32(block, base + RACK_SPAWN_OFF)
      local sides = {}
      for k = 0, SLOTS - 1 do sides[k + 1] = u32(block, base + k * RACK_SLOT + SL_SIDE) end
      if spawn and spawn >= 1 and spawn <= 8 and sides[1] == 1 and sides[2] == 2 and sides[3] == 1 and sides[4] == 2 then
        return base
      end
    end
  end
end

local RACK_HITS, RACK_REQ = {}, false
local RACKADDR_LAST = nil
local function rack_on_hit(key, addr)                 -- Scanner 回调里只存地址，别做重活
  if #RACK_HITS < 64 then RACK_HITS[#RACK_HITS + 1] = addr end
end

-- 结构校验（不依赖内容锚点）：spawn_payload_size 合理 + 前 4 槽 rack_side = 1/2/1/2
local function rack_looks_like_record(addr)
  local buf = api.read(addr, RACK_SPAWN_OFF + 8)
  if not buf then return false end
  local spawn = u32(buf, RACK_SPAWN_OFF)
  if not spawn or spawn < 1 or spawn > 8 then return false end
  local s1, s2 = u32(buf, SL_SIDE), u32(buf, RACK_SLOT + SL_SIDE)
  local s3, s4 = u32(buf, 2 * RACK_SLOT + SL_SIDE), u32(buf, 3 * RACK_SLOT + SL_SIDE)
  return s1 == 1 and s2 == 2 and s3 == 1 and s4 == 2
end

local function locate_rack()
  if RACKADDR then return RACKADDR end
  if not write_enabled then return nil, 'ffi 不可用' end
  local S, why = scanner()
  if not S then return nil, why end
  if not RACK_REQ then
    local ok, w = S.scan_request{
      id = 'cs_rack_table',
      patterns = { { key = 'rack', bytes = RACK_SIG } },   -- 'LDLD' + ver1 + typeHash 0xA98BB156
      budget = 4 * 1024 * 1024,
      on_hit = rack_on_hit,
    }
    if not ok then return nil, 'scan_request 失败: ' .. tostring(w) end
    RACK_REQ = true
    report('已向 Scanner 请求扫描包架表（LDLD + typeHash 0xA98BB156）', true)
  end
  for _, addr in ipairs(RACK_HITS) do
    local head = api.read(addr, 16)
    if head then
      local size = u32(head, 12)
      if size and size >= 1024 and size <= 4194304 then
        local block = api.read(addr, size)
        local rel = block and rack_find_in(block)
        if rel then
          RACKADDR, RACKADDR_LAST = addr + rel, addr + rel
          report(('包架表已定位 0x%X（槽 0 = 0x%X，来自 Scanner 命中）'):format(addr, RACKADDR), true)
          return RACKADDR
        end
      end
    end
  end
  -- 锚点找不到（表被重载、或槽已被我们改成非原装）→ 沿用上次地址，做结构校验
  if RACKADDR_LAST and rack_looks_like_record(RACKADDR_LAST) then
    RACKADDR = RACKADDR_LAST
    report(('包架记录沿用上次地址 0x%X（锚点已不存在，结构校验通过）'):format(RACKADDR), true)
    return RACKADDR
  end
  local st = select(2, pcall(S.scan_status, 'cs_rack_table'))
  local state = (type(st) == 'table') and (st.state or st.status) or '?'
  return nil, ('未找到（Scanner state=%s，命中 %d 处）'):format(tostring(state), #RACK_HITS)
end

-- ============================================================ 计算 + 应用
local function sel_from_mom()
  local sel = {}
  local mom = rawget(_G, 'ModOptionsMenu')
  for i = 1, SLOTS do
    local v
    if mom and mom.get then
      local ok, got = pcall(mom.get, 'custom_supply.slot' .. i)
      if ok then v = tonumber(got) end
    end
    sel[i] = v or CFG_SEL[i] or 1
    if sel[i] < 1 or sel[i] > #ITEMS then sel[i] = 1 end
  end
  return sel
end

local function apply_all()
  local sel = sel_from_mom()
  local cd, detail = compute_cd(sel)
  report(('配置：%s → CD = %d s'):format((function()
    local t = {} for i = 1, SLOTS do t[i] = ITEMS[sel[i]].name end return table.concat(t, ' / ')
  end)(), cd), true)

  local ptr, si = strat_info(ID_TARGET)
  if not ptr then report('战备记录定位失败：' .. tostring(si), true) return false end
  if u32(si, 4) ~= KEY_TARGET then
    report(('id=%d 的 key 不是 0x%X（结构已变，拒写）'):format(ID_TARGET, KEY_TARGET), true)
    return false
  end
  -- ③ 让 ID77 可用：+0x80 bit1 + 注册表 +0x14 = 2
  local bit = api.read(ptr + BIT_SEL, 1)
  if bit and (bit:byte(1) % 4) >= 2 then
    report('选择位已是开的（+0x80 bit1 = 1）')
  else
    local b = bit and bit:byte(1) or 0
    local ok, why = write_bytes(ptr + BIT_SEL, string.char(b + 2), 'bit1')
    report(('★ 选择位 id=%d +0x80 0x%02X -> 0x%02X（%s）'):format(ID_TARGET, b, b + 2, ok and '回读通过' or tostring(why)), true)
    if not ok then return false end
  end
  local reg_addr, idx, why2 = reg_record(ptr)
  if not reg_addr then report('注册表定位失败：' .. tostring(idx), true) return false end
  local st = u32(api.read(reg_addr, 4), 0)
  if st ~= 2 and st ~= 4 then
    local ok, why3, idem = write_bytes(reg_addr, le32(2), 'state')
    report(('★ 可用状态 id=%d 记录#%d %s -> 2（%s）'):format(ID_TARGET, idx, tostring(st), ok and '回读通过' or tostring(why3)), true)
    if not ok then return false end
  else
    report(('可用状态 id=%d 记录#%d 已是 %d（无需写）'):format(ID_TARGET, idx, st))
  end

  -- ① 包架 4 槽
  local rack, whyr = locate_rack()
  if not rack then report('包架定位失败：' .. tostring(whyr), true) return false end
  for i = 1, SLOTS do
    local e = ITEMS[sel[i]]
    local addr = rack + (i - 1) * RACK_SLOT
    if e.none then
      local ok, why4 = write_bytes(addr + SL_ITEM, string.rep('\0', 8), 'item0')
      if not ok then report(('槽%d 清空失败：%s'):format(i, tostring(why4)), true) return false end
      report(('★ 槽%d = 无（item=0）'):format(i), true)
    else
      local ok, why4 = write_bytes(addr + SL_ITEM, e.hash_le, 'item')
      if not ok then report(('槽%d item 写入失败：%s'):format(i, tostring(why4)), true) return false end
      local p = PRESET[e.key]
      local off = p and p.off or { 0, 0, 0 }
      local rot = p and p.rot or { 0, 0, 0 }
      local ok2 = write_bytes(addr + SL_OFF, le_f32(off[1]) .. le_f32(off[2]) .. le_f32(off[3]), 'offset')
      local ok3 = write_bytes(addr + SL_ROT, le_f32(rot[1]) .. le_f32(rot[2]) .. le_f32(rot[3]), 'rot')
      report(('★ 槽%d = %s  offset=(%g,%g,%g) rot=(%g,%g,%g)  [%s/%s]'):format(
        i, e.name, off[1], off[2], off[3], rot[1], rot[2], rot[3],
        ok2 and 'offset OK' or 'offset FAIL', ok3 and 'rot OK' or 'rot FAIL'), true)
    end
  end
  -- ② 冷却
  local okcd, whycd = write_bytes(ptr + OFF_CD, le_f32(cd), 'cd')
  report(('★ 冷却 id=%d cooldown_success = %d s（%s）'):format(ID_TARGET, cd, okcd and '回读通过' or tostring(whycd)), true)
  if not okcd then return false end
  state.applied = true
  return true
end

local function verify()
  -- ① 解锁三条件里的 ②③（v1.7 有这条，v0.1a 第一版漏了 —— 重建后会自动补回）
  local ptr, si = strat_info(ID_TARGET)
  if not ptr then
    report('复核：战备记录不可用 → 重新定位', true)
    state.applied = false
    return false
  end
  local bit = api.read(ptr + BIT_SEL, 1)
  if not bit or (bit:byte(1) % 4) < 2 then
    report(('复核：选择位 +0x80 被关掉（%s）→ 重开'):format(bit and ('0x%02X'):format(bit:byte(1)) or '读不到'), true)
    state.applied = false
    return false
  end
  local reg_addr, idx = reg_record(ptr)
  if not reg_addr then
    report(('复核：注册表未就绪（%s）→ 重新应用'):format(tostring(idx)), true)
    state.applied = false
    return false
  end
  local st = u32(api.read(reg_addr, 4), 0)
  if st ~= 2 and st ~= 4 then
    report(('复核：可用状态被改回 %s → 重写为 2（记录#%s）'):format(tostring(st), tostring(idx)), true)
    state.applied = false
    return false
  end

  -- ② 冷却 + 包架 4 槽
  local sel = sel_from_mom()
  local cd = compute_cd(sel)
  local cur_cd = f32(si, OFF_CD)
  local bad
  if math.abs((cur_cd or -1) - cd) > 0.01 then bad = 'CD 不符' end
  local rack = RACKADDR
  if not bad and rack then
    for i = 1, SLOTS do
      local e = ITEMS[sel[i]]
      local want = e.none and string.rep('\0', 8) or e.hash_le
      if api.read(rack + (i - 1) * RACK_SLOT + SL_ITEM, 8) ~= want then bad = ('槽%d 被改回'):format(i) break end
    end
  elseif not rack then
    bad = '包架地址未知'
  end
  if bad then
    report(('复核：%s → 重新定位并应用'):format(bad), true)
    RACKADDR = nil                          -- 表可能被游戏重载 → 下一轮重新定位
    state.applied = false
    return false
  end
  return true
end

-- ============================================================ MOM 注册
local MOMDONE = false
local function register_mom()
  if MOMDONE then return end
  local mom = rawget(_G, 'ModOptionsMenu')
  if type(mom) ~= 'table' or type(mom.register_option) ~= 'function' then return end
  MOMDONE = true
  local choices = {}
  for i, e in ipairs(ITEMS) do choices[i] = e.name end
  for i = 1, SLOTS do
    local id = 'custom_supply.slot' .. i
    mom.register_option(id, {
      type = 'choice', label = ('补给槽位 %d'):format(i), mod = '自定义补给',
      choices = choices, default = CFG_SEL[i] or IDX.none,
      description = function()
        local sel = sel_from_mom()
        local cd = compute_cd(sel)
        return ('当前 CD = %d s（4 槽：%s）'):format(cd, (function()
          local t = {} for k = 1, SLOTS do t[k] = ITEMS[sel[k]].name end return table.concat(t, ' / ')
        end)())
      end,
    })
    if mom.on_change then
      mom.on_change(id, function(v)
        local ok, err = pcall(function()
          local sel = sel_from_mom()
          sel[i] = tonumber(v) or sel[i]
          report(('槽位 %d 改为 %s → 重算 CD = %d s'):format(i, ITEMS[sel[i]].name, compute_cd(sel)), true)
          state.applied = false                -- 下一帧重新应用
        end)
        if not ok then state.errs = state.errs + 1 report('on_change 异常: ' .. tostring(err), true) end
      end)
    end
  end
  report('已注册 ModOptionsMenu：4 个补给槽位（choice）', true)
end

-- ============================================================ 帧
local function tick()
  state.frame = state.frame + 1
  if state.frame % 60 == 0 then flush_log() end
  if not MOMDONE and state.frame % 60 == 0 then pcall(register_mom) end
  if state.frame < 120 then return end
  if not state.applied then
    if state.next_try and state.frame < state.next_try then return end
    local ok, res = pcall(apply_all)
    if not ok then
      state.errs = state.errs + 1
      if state.errs <= 5 then report('apply 异常: ' .. tostring(res), true) end
      state.applied = false
    end
    state.next_try = state.frame + 180
    return
  end
  if state.frame % 300 == 0 then pcall(verify) end
end

local previous = update
update = function(dt, ...)
  local ok, why = pcall(tick)
  if not ok then state.errs = state.errs + 1 if state.errs <= 5 then report('tick 异常: ' .. tostring(why), true) end end
  if previous then return previous(dt, ...) end
end

if state.frame == 0 then
  load_cfg()
  register_mom()
  report(('自定义补给 v%s 已加载：4 槽 / CD 30~150 s（%s）'):format(VERSION,
    write_enabled and '写入开启' or '只读诊断模式'), true)
end
return state
