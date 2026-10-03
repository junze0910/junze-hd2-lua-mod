-- HD2-Addon: mods/dsh/strat_unlock

-- ===========================================================================
--  指定解锁某一个战备（数据路，不是代码补丁）
--
--  依据（反汇编 game.dll build 46015 的 unlock_stratagems 判定函数）：
--
--    r10 = *(game.dll + 0x37CB600 + id*8)      ← 按 id 索引的战备信息指针表
--    key = u32[r10 + 4]
--    在装备注册表 mappings(root+0xB9CE4, 24B/条) 里找 u32[mapping+8] == key
--      → 记录号 i
--    record = root + 0x1CE4 + i*184
--    写 u32[record + 0x14] = 2                 ← 与切变模组同一字段（已实机验证）
--
--  表地址不硬编码：从判定函数里那两条 lea 的 disp32 现算（抗 ASLR），
--  并用函数前 11 字节做版本门（不符一律拒写）。
--
--  默认目标 id = 77（CONSUMABLES. HEALTH PACK RACK）
--  可用游戏根目录下的 StratUnlock.cfg 覆盖：一行 ids=77,78,79
--
--  红线：只写自己算出来的那 4 个字节（+0x14）；写前预检、写后回读、失败回滚。
-- ===========================================================================

local VERSION = '1.7'
local MOD = 'mods/dsh/strat_unlock'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, phase = 'starting', writes = 0, refusals = 0, errs = 0,
                  done = {}, rec_cache = {} })
local state = rawget(_G, MOD)

-- ---------------------------------------------------------------- 日志（SKILL 6.15）
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
    local f = loader and loader.open_log and loader.open_log('StratUnlock.log')
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
  print('[StratUnlock] ' .. msg)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, msg)
  if #loghist > LOG_CAP then table.remove(loghist, 1) end
  log_dirty = true
  if keep then flush_log(true) end
end
local function dump_file(name, text)
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local f = loader and loader.open_log and loader.open_log(name)
    if f then f:write(text); f:close() end
  end)
end

-- ---------------------------------------------------------------- ffi / kernel32（照 patch_1）
local ffi_ok, ffi = pcall(require, 'ffi')
local bit_ok, bit = pcall(require, 'bit')
local api_ok, api = pcall(function()
  assert(ffi_ok and ffi, 'ffi unavailable')
  assert(bit_ok and bit, 'bit unavailable')
  assert(ffi.abi('64bit'), 'x64 required')
  -- 用本 mod 专属的 typedef 名，避免和别的 addon 的 cdef 撞车；
  -- 整段仍然 pcall —— 共用 Lua 状态里重复声明不同签名会直接抛错。
  -- ⚠ 所有 addon 共用同一个 Lua 状态，而 ffi.cdef 是「整块原子」的：
  --   一条声明与别人冲突 → **整块都不生效**。所以必须按符号分块 pcall，
  --   否则会出现「ReadProcessMemory 能用、GetModuleHandleA 根本没声明」这种半死状态。
  pcall(ffi.cdef, [[typedef struct { uintptr_t BaseAddress; uintptr_t AllocationBase; uint32_t AllocationProtect; uint32_t PartitionId; size_t RegionSize; uint32_t State; uint32_t Protect; uint32_t Type; } SU_MBI;]])
  pcall(ffi.cdef, [[void *GetModuleHandleA(const char *);]])
  pcall(ffi.cdef, [[void *GetCurrentProcess(void);]])
  pcall(ffi.cdef, [[int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);]])
  pcall(ffi.cdef, [[int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);]])
  pcall(ffi.cdef, [[int VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);]])
  local kernel = ffi.load('kernel32')
  -- 在 pcall 内就把符号全取出来：缺哪个就报哪个，不要让调用点才炸
  local fn_ghm, fn_gcp = kernel.GetModuleHandleA, kernel.GetCurrentProcess
  local fn_rpm, fn_wpm, fn_vp = kernel.ReadProcessMemory, kernel.WriteProcessMemory, kernel.VirtualProtect
  if not fn_gcp then error('读不到 GetCurrentProcess（cdef 被冲突掉）') end
  if not fn_rpm then error('读不到 ReadProcessMemory（cdef 被别的 addon 冲突掉）') end
  if not fn_wpm then error('读不到 WriteProcessMemory（cdef 被冲突掉）') end
  if not fn_vp  then error('读不到 VirtualProtect（cdef 被冲突掉）') end
  if not fn_ghm then error('读不到 GetModuleHandleA（cdef 被冲突掉）') end
  local process = fn_gcp()
  local M = { kernel = kernel, process = process, GetModuleHandleA = fn_ghm }
  function M.read(address, size)
    if not address or address <= 0 or size <= 0 then return nil end
    local buf, got = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
    pcall(fn_rpm, process, ffi.cast('const void *', address), buf, size, got)
    if tonumber(got[0]) ~= size then return nil end
    return ffi.string(buf, size)
  end
  function M.write(address, bytes)
    local got = ffi.new('size_t[1]')
    local ok2 = pcall(fn_wpm, process, ffi.cast('void *', address),
                      ffi.cast('const void *', bytes), #bytes, got)
    return ok2 and tonumber(got[0]) == #bytes
  end
  function M.unprotect(address, size)
    local old = ffi.new('uint32_t[1]')
    local ok2 = pcall(fn_vp, ffi.cast('void *', address), size, 0x04, old)  -- PAGE_READWRITE
    if not ok2 then return nil end
    return tonumber(old[0])
  end
  function M.reprotect(address, size, value)
    if not value then return end
    local old = ffi.new('uint32_t[1]')
    pcall(fn_vp, ffi.cast('void *', address), size, value, old)
  end
  return M
end)
if not api_ok then report('ffi/kernel32 不可用，写入关闭: ' .. tostring(api), true) end
local write_enabled = api_ok and api ~= nil

-- ---------------------------------------------------------------- 小工具
local function u32(s, off)
  off = off or 0                      -- 双保险：漏传偏移时按 0 处理，不再抛"arithmetic on nil"
  if type(s) ~= 'string' or #s < off + 4 then return nil end
  local a, b, c, d = s:byte(off + 1, off + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function u8(s, off)
  off = off or 0
  if type(s) ~= 'string' or #s < off + 1 then return nil end
  return s:byte(off + 1)
end
local function u64(s, off)
  local lo, hi = u32(s, off), u32(s, off + 4)
  if not lo or not hi then return nil end
  return lo + hi * 4294967296
end
local function i32(s, off)
  local v = u32(s, off or 0)
  if not v then return nil end
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end
local function f32(s, off)                      -- 纯 Lua 解 float32，避免往共享 cdef 里塞 union
  local bits = u32(s, off)
  if not bits then return nil end
  local sign = 1
  if bits >= 0x80000000 then sign = -1 bits = bits - 0x80000000 end
  local exp  = math.floor(bits / 0x800000)
  local mant = bits % 0x800000
  if exp == 0 then
    if mant == 0 then return 0 end
    return sign * (mant / 0x800000) * 2 ^ (-126)
  elseif exp == 255 then
    return mant == 0 and (sign * math.huge) or (0 / 0)
  end
  return sign * (1 + mant / 0x800000) * 2 ^ (exp - 127)
end
local function le32(v) return string.char(v % 256, math.floor(v / 256) % 256,
                                          math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
local function hex(s)
  if type(s) ~= 'string' then return '?' end
  local t = {}
  for i = 1, #s do t[i] = ('%02X'):format(s:byte(i)) end
  return table.concat(t, ' ')
end

-- ---------------------------------------------------------------- 地址解析
-- 主路线 = SKILL §6.27「用 game.dll AOB 定位战备指针数组」（来源 StratagemCooldown 2.1.5）
-- 兜底   = 判定函数 unlock_stratagems 里那两条 lea 的 disp32（本次实测两者指向同一张表）
local AOB_P1 = '\x49\x8B\x84\xC7'                                  -- mov rax,[r15 + rax*8 + disp32]
local AOB_P2 = '\x44\x8B\x80\xC8\x00\x00\x00\x8B\xC2\x45\x85\xC0'  -- mov r8d,[rax+0xC8]; mov eax,edx; test r8d,r8d
local AOB_BACK     = 0x1000      -- 倒找 lea 的范围
local LEA_R15      = { 0x4C, 0x8D, 0x3D }   -- lea r15,[rip+disp32]

local RVA_FUNC        = 0x136FC20   -- 兜底：判定函数入口
local SIG_FUNC        = '\x48\x89\x5C\x24\x08\x48\x8B\xD9\x85\xD2\x75'
local RVA_LEA_B_DISP  = 0x136FC3A   -- 兜底：那条 lea 的 disp32 位置
local RVA_ITEM_SLOT   = 0x347CEF8   -- *(here) = 装备注册表根
local ROOT_COUNT, ROOT_RECS, ROOT_MAPS, ROOT_GATE = 0x1CE0, 0x1CE4, 0xB9CE4, 0xDDCF8
local REC_SIZE, MAP_SIZE = 184, 24

local ADDR = { base = nil, tbl_by_id = nil, item_slot = nil, route = nil }

local function module_image()
  local h = api.GetModuleHandleA('game.dll')
  if h == nil then return nil, nil end
  local base = tonumber(ffi.cast('uintptr_t', h))
  local head = api.read(base, 0x1000)
  if not head then return nil end
  local pe = u32(head, 0x3C)
  if not pe or pe <= 0 or pe > 0x800 then return nil end
  local size = u32(head, pe + 0x18 + 0x38)          -- OptionalHeader.SizeOfImage
  if not size or size <= 0 then return nil end
  return base, size
end

local function sane_ptr(v, base, size)
  if type(v) ~= 'number' or v <= 0x10000 then return false end
  if v >= 0x800000000000 then return false end
  return true
end

-- 1MB 分块 + 0x40 重叠扫镜像，找 AOB（只有前缀是字面量，用 find 保速度）
local function scan_aob(base, size)
  local CH, OV = 1024 * 1024, 0x40
  local hits = {}
  local off = 0
  while off < size do
    local want = math.min(CH + OV, size - off)
    local buf = api.read(base + off, want)
    if buf then
      local pos = 1
      while true do
        local q = buf:find(AOB_P1, pos, true)
        if not q then break end
        pos = q + 1
        if buf:sub(q + 8, q + 8 + #AOB_P2 - 1) == AOB_P2 then
          hits[#hits + 1] = base + off + q - 1
          if #hits > 4 then return hits end        -- 多于 1 个就是 ambiguous，早停
        end
      end
    end
    off = off + CH
  end
  return hits
end

local function route_aob(base, size)
  local hits = scan_aob(base, size)
  if #hits == 0 then return nil, 'AOB 0 命中' end
  if #hits > 1 then return nil, ('AOB %d 命中（ambiguous）'):format(#hits) end
  local consumer = hits[1]
  local disp = i32(api.read(consumer + 4, 4), 0)
  if not disp then return nil, 'consumer+4 disp32 读不到' end
  local lo = math.max(base, consumer - AOB_BACK)
  local win = api.read(lo, consumer - lo)
  if not win then return nil, '倒找窗口读不到' end
  local lea
  for i = #win - 2, 1, -1 do
    if win:byte(i) == LEA_R15[1] and win:byte(i + 1) == LEA_R15[2] and win:byte(i + 2) == LEA_R15[3] then
      lea = lo + i - 1
      break
    end
  end
  if not lea then return nil, ('倒找 lea r15 失败（%d 字节内）'):format(consumer - lo) end
  local ldisp = i32(api.read(lea + 3, 4), 0)
  if not ldisp then return nil, 'lea disp32 读不到' end
  local r15_base = lea + 7 + ldisp
  local table = r15_base + disp
  if not sane_ptr(table, base, size) then return nil, ('table 越界 0x%X'):format(table) end
  return table, nil, { route = 'AOB', consumer = consumer, lea = lea, r15 = r15_base, disp = disp }
end

-- Scanner v0.8.0+ 自带 AOB 战备表 API：有就优先用它（SKILL §6.20 全量扫描集中到 Scanner）
-- 旧版 Scanner 没有这一套 → 必须逐个 type() 探测，判空后再调
local function scanner_aob()
  local S = rawget(_G, 'HD2Scanner')
  if type(S) ~= 'table' then return nil end
  if type(S.strat_table_request) ~= 'function' or type(S.strat_table_status) ~= 'function'
     or type(S.strat_table_base) ~= 'function' or type(S.strat_slot) ~= 'function'
     or type(S.strat_rec) ~= 'function' then return nil end
  return S
end

local function route_func(base, _size)
  local sig = api.read(base + RVA_FUNC, #SIG_FUNC)
  if sig ~= SIG_FUNC then return nil, ('兜底签名不符，实得 %s'):format(hex(sig)) end
  local db = i32(api.read(base + RVA_LEA_B_DISP, 4), 0)
  if not db then return nil, '兜底 lea disp32 读不到' end
  return base + 0x136FC37 + 7 + db, nil, { route = 'FUNC-LEA' }
end

local function resolve()
  if ADDR.base then return ADDR end
  if not api_ok then return nil, 'ffi 不可用' end
  local base, size = module_image()
  if not base then return nil, 'game.dll 基址/镜像大小取不到' end

  local S = scanner_aob()
  if S then
    pcall(S.strat_table_request)                    -- 幂等：正在扫/已成功都直接 true；分帧推进不卡帧
    local st = S.strat_table_status() or {}
    if st.state ~= 'ok' then
      return nil, ('Scanner 战备表未就绪（state=%s%s）'):format(
        tostring(st.state), st.reason and ('：' .. tostring(st.reason)) or '')
    end
    local sbase = S.strat_table_base()
    if not sbase then return nil, 'Scanner 报 ok 但 base 为空' end
    ADDR.base, ADDR.tbl_by_id, ADDR.item_slot = base, sbase, base + RVA_ITEM_SLOT
    ADDR.route, ADDR.scanner = 'SCANNER-AOB', S
    report(('地址解析 OK：路线=SCANNER-AOB base=0x%X 按id表=0x%X item_slot=0x%X'):format(
      base, sbase, ADDR.item_slot), true)
    report(('  Scanner: slots_ok=%s/%s  scanned=%s/%s  %s ms'):format(
      tostring(st.slots_ok), tostring(st.slots), tostring(st.scanned), tostring(st.total), tostring(st.ms)))
    return ADDR
  end
  local tbl, why_aob, info = route_aob(base, size)
  local why_back
  if not tbl then
    report('AOB 路线失败（' .. tostring(why_aob) .. '），回退兜底路线', true)
    tbl, why_back, info = route_func(base, size)
    if not tbl then
      return nil, ('两条路线都失败：AOB=%s / 兜底=%s'):format(tostring(why_aob), tostring(why_back))
    end
  end
  -- 表里前 16 个槽至少要有 1 个合理指针：
  --   全空 = 表还没加载（开机/飞船界面属正常）；有值 = 表已就绪
  -- （只检查 slot[1] 太脆：单个 id 未必有值）
  local alive = 0
  for sid = 1, 16 do
    local v = u64(api.read(tbl + sid * 8, 8), 0)
    if v and v > 0x10000 and v < 0x800000000000 then alive = alive + 1 end
  end
  if alive == 0 then
    return nil, 'table 前 16 槽全为空（表还没加载，或结构已变）'
  end
  ADDR.base, ADDR.tbl_by_id, ADDR.item_slot, ADDR.route = base, tbl, base + RVA_ITEM_SLOT, info
  report(('地址解析 OK：路线=%s base=0x%X 按id表=0x%X item_slot=0x%X'):format(
    tostring(info and info.route), base, tbl, ADDR.item_slot), true)
  if info and info.consumer then
    report(('  AOB consumer=0x%X lea=0x%X r15_base=0x%X disp=0x%X'):format(
      info.consumer, info.lea, info.r15, info.disp))
  end
  return ADDR
end
-- ---------------------------------------------------------------- 目标 id
local TARGETS = { 77 }        -- 默认：77 号（CONSUMABLES. HEALTH PACK RACK）
-- 自动模式状态机：进游戏后自己等表就绪、自己写，不需要任何界面操作
local AUTO = { enabled = true, next_at = 0, tries = 0, applied = {}, announced = {}, done = false }
-- 复核（SKILL/Scanner-API §4.7：表基址会变，消费者要自己定期复核）
-- 廉价路径：缓存 root + 记录地址，复核只需 3 次小 read；root 变了才重建索引（那一次才贵）
local VERIFY_EVERY = 5     -- 复核周期（秒）；cfg 里 verify=0 可关闭
-- 判定函数（unlock_stratagems，RVA 0x136FC20）的三道条件，缺一不可：
--   ① StratagemInfo +0xC0 bit0
--   ② StratagemInfo +0x80 bit1  = 明文数据表的 selectable（不在列表里的条目这一位是 0）
--   ③ 注册表记录 +0x14 ∈ {2,4}   （或 mapping[+0x10] 跳过去的那条记录满足）
-- 只写 ③ 对"不在列表里"的条目无效（② 先返回假）—— 这就是 v1.4~v1.6 写 77 无效的原因。
-- cfg 里 bit=1 才动 ②；默认 0：不改产品行为、离线夹具行为不变。
local WRITE_BIT = false

-- StratUnlock.cfg（游戏根目录，可选）：
--     ids=77          （可写多个：ids=77,78）
--     auto=0          （关掉自动写入，只做诊断）
local function load_cfg()
  local f = io and io.open('StratUnlock.cfg', 'r')
  if not f then return end
  local text = tostring(f:read('*a')); f:close()
  local am = text:match('auto%s*=%s*(%d+)')
  if am and tonumber(am) == 0 then AUTO.enabled = false end
  local vm = text:match('verify%s*=%s*(%d+)')
  if vm then VERIFY_EVERY = tonumber(vm) or 5 end
  local bm = text:match('bit%s*=%s*(%d+)')
  if bm and tonumber(bm) == 1 then WRITE_BIT = true end
  local seg = text:match('ids%s*=%s*([%d%s,]*)')
  if seg then
    local list = {}
    for num in seg:gmatch('%d+') do
      local v = tonumber(num)
      if v and v > 0 and v < 4096 then list[#list + 1] = v end
    end
    if #list > 0 then TARGETS = list end
  end
  report(('cfg：ids=%s  auto=%s  verify=%ds  bit=%s'):format(table.concat(TARGETS, ','), AUTO.enabled and '1' or '0', VERIFY_EVERY, WRITE_BIT and '1' or '0'), true)
end

-- ---------------------------------------------------------------- 解析一条战备
local function resolve_one(id)
  local A = resolve()
  if not A then return nil, '地址未解析' end
  local rp, si
  if A.scanner then
    rp, si = A.scanner.strat_slot(id)
    if not rp then return nil, ('id=%d Scanner.strat_slot 失败：%s'):format(id, tostring(si)) end
    local rec, why3 = A.scanner.strat_rec(id, 0xD0)
    if not rec then return nil, ('id=%d Scanner.strat_rec 失败：%s'):format(id, tostring(why3)) end
    si = rec
  else
    rp = u64(api.read(A.tbl_by_id + id * 8, 8), 0)
    if not rp or rp == 0 then return nil, ('id=%d 在按id表里是空指针'):format(id) end
    si = api.read(rp, 0xD0)
    if not si then return nil, ('id=%d 读不到 StratagemInfo'):format(id) end
  end
  local uses  = i32(si, 0x50)          -- 笔记：+80 uses，-1 = 无限
  local cd    = f32(si, 0x68)          -- 笔记：+104/-108 cooldown，这里取 +0x68
  local namep = u64(si, 0x10)          -- 笔记：+0x10 名称字符串指针
  local ok_uses = uses and (uses == -1 or (uses >= 1 and uses <= 200))
  local ok_cd   = cd and (cd >= -1 and cd <= 7200)
  local ok_name = namep and namep > 0x10000 and namep < 0x800000000000
  if not (ok_uses and ok_cd and ok_name) then
    return nil, ('id=%d 记录字段不合理（uses=%s cooldown=%s name_ptr=%s）→ 结构已变，拒写'):format(
      id, tostring(uses), tostring(cd), tostring(namep))
  end
  local kr = api.read(rp + 4, 4)
  local key = u32(kr, 0)
  if not key then return nil, ('id=%d 读不到 r10+4'):format(id) end
  local root = u64(api.read(A.item_slot, 8), 0)
  if not root or root == 0 then return nil, '注册表根指针为空' end
  local gate = u32(api.read(root + ROOT_GATE, 4), 0)
  local cnt  = u32(api.read(root + ROOT_COUNT, 4), 0)
  if gate ~= 12 then return nil, ('初始化门闸 = %s（期望 12）'):format(tostring(gate)) end
  if not cnt or cnt <= 0 or cnt > 4096 then return nil, ('条目数异常 %s'):format(tostring(cnt)) end
  for i = 0, cnt - 1 do
    local m = api.read(root + ROOT_MAPS + i * MAP_SIZE, MAP_SIZE)
    if m and u32(m, 8) == key then
      local rec = api.read(root + ROOT_RECS + i * REC_SIZE, REC_SIZE)
      if not rec then return nil, ('记录 %d 读不到'):format(i) end
      return { id = id, r10 = rp, key = key, index = i, count = cnt,
               addr = root + ROOT_RECS + i * REC_SIZE + 0x14,
               bit_addr = rp + 0x80, bit = u8(si, 0x80),
               rec_index = u32(rec, 0), rec_key = u32(rec, 4), rec_id = u32(rec, 8),
               type = u32(rec, 12), state = u32(rec, 20),
               uses = uses, cd = cd, namep = namep }
    end
  end
  return nil, ('mappings 里没有 key=0x%X（id=%d）'):format(key, id)
end

-- ---------------------------------------------------------------- 写
local function write_state32(addr, value)
  if not write_enabled then return false, '写入被禁用（ffi 不可用）' end
  local oldbytes = api.read(addr, 4)
  if not oldbytes then return false, '写前读不到' end
  local oldv = u32(oldbytes, 0)
  local newbytes = le32(value)
  local prot = api.unprotect(addr, 4)
  if not prot then state.refusals = state.refusals + 1 return false, '改页保护失败' end
  local ok = api.write(addr, newbytes)
  api.reprotect(addr, 4, prot)
  if not ok then state.refusals = state.refusals + 1 return false, 'WriteProcessMemory 失败' end
  if api.read(addr, 4) ~= newbytes then
    state.refusals = state.refusals + 1
    -- 回读失败 -> 立刻写回原值
    local p2 = api.unprotect(addr, 4)
    api.write(addr, oldbytes)
    api.reprotect(addr, 4, p2)
    return false, '回读校验失败（已尝试写回）'
  end
  return true, oldv
end

-- 单字节置位写入（+0x80 |= mask）：同一套预检 / 回读 / 失败回写
local function set_bit8(addr, mask)
  if not write_enabled then return false, '写入被禁用（ffi 不可用）' end
  local oldbytes = api.read(addr, 1)
  if not oldbytes then return false, '写前读不到' end
  local oldv = oldbytes:byte(1)
  local newv = oldv
  if math.floor(oldv / mask) % 2 == 0 then newv = oldv + mask end
  if newv == oldv then return true, oldv, newv end
  local newbytes = string.char(newv)
  local prot = api.unprotect(addr, 1)
  if not prot then state.refusals = state.refusals + 1 return false, '改页保护失败' end
  local ok = api.write(addr, newbytes)
  api.reprotect(addr, 1, prot)
  if not ok then state.refusals = state.refusals + 1 return false, 'WriteProcessMemory 失败' end
  if api.read(addr, 1) ~= newbytes then
    state.refusals = state.refusals + 1
    local p2 = api.unprotect(addr, 1)
    api.write(addr, oldbytes)
    api.reprotect(addr, 1, p2)
    return false, '回读校验失败（已尝试写回）'
  end
  return true, oldv, newv
end

-- ---------------------------------------------------------------- 动作
local function act_preview()
  local A, why = resolve()
  if not A then report('预览失败: ' .. why, true) return end
  for _, id in ipairs(TARGETS) do
    local r, why2 = resolve_one(id)
    if not r then
      report(('预览 id=%d → 失败: %s'):format(id, why2), true)
    else
      report(('预览 id=%d → r10=0x%X key=0x%X 记录#%d type=%d id字段=0x%X 状态=%d  写入地址=0x%X'):format(
        r.id, r.r10, r.key, r.index, r.type or -1, r.rec_id or 0, r.state or -1, r.addr), true)
      report(('        StratagemInfo 校验（§6.27）：uses=%s  cooldown=%s  name_ptr=0x%X'):format(
        tostring(r.uses), tostring(r.cd), r.namep or 0))
    end
  end
end

local function act_apply()
  local A, why = resolve()
  if not A then report('解锁失败: ' .. why, true) return end
  local n = 0
  for _, id in ipairs(TARGETS) do
    local r, why2 = resolve_one(id)
    if not r then
      report(('解锁 id=%d → 解析失败: %s'):format(id, why2), true)
    elseif r.state == 2 then
      report(('解锁 id=%d → 记录#%d 已经是 2（跳过）'):format(id, r.index), true)
    else
      local ok, old = write_state32(r.addr, 2)
      if ok then
        n = n + 1
        state.writes = state.writes + 1
        state.done[#state.done + 1] = { addr = r.addr, old = old, id = id, index = r.index }
        report(('★ 解锁 id=%d → 记录#%d 地址=0x%X  %s -> 2  (回读通过)'):format(
          id, r.index, r.addr, tostring(old)), true)
      else
        report(('解锁 id=%d → 写入失败: %s'):format(id, tostring(old)), true)
      end
    end
  end
  report(('本次写入 %d 条；累计 %d 条。去军械库战备页看 77 号是否出现。'):format(n, state.writes), true)
end

local function act_revert()
  local n = 0
  for i = #state.done, 1, -1 do
    local item = state.done[i]
    if item.old then
      local ok, err = write_state32(item.addr, item.old)
      if ok then n = n + 1 report(('还原 id=%d 地址=0x%X -> %d'):format(item.id, item.addr, item.old)) end
      if not ok then report(('还原失败 id=%d: %s'):format(item.id, tostring(err)), true) end
    end
    table.remove(state.done, i)
  end
  report(('还原 %d 条'):format(n), true)
end

local function act_dump()
  local A, why = resolve()
  if not A then report('导出失败: ' .. why, true) return end
  local cnt, locked = 0, 0
  for id = 1, 200 do
    local r = resolve_one(id)
    if r then
      cnt = cnt + 1
      if r.state ~= 2 then locked = locked + 1 end
      if r.state ~= 2 then
        report(('  未解锁 id=%-3d 记录#%-4d type=%-3d state=%s key=0x%X'):format(
          id, r.index, r.type or -1, tostring(r.state), r.key))
      end
    end
  end
  report(('状态表导出完成：可解析 %d 条，其中未解锁 %d 条'):format(cnt, locked), true)
end

-- ---------------------------------------------------------------- 全表状态导出（只读，跑一次）
-- 目的：分辨「注册表状态是不是逐条拥有位」
--   若 149 条的记录号各不相同、state 有 1 有 2  → 单点解锁成立
--   若记录号大量重复 / state 全 2              → 该字段不是拥有位，只能走代码路（全解锁）
local DUMPED = false
local dump_progression, dump_records   -- 前向声明：dump_all 里要调它们
local function dump_all()
  local A = resolve()
  if not A then return false end
  local root = u64(api.read(A.item_slot, 8), 0)
  if not root then return false end
  local cnt = u32(api.read(root + ROOT_COUNT, 4), 0)
  -- 注册表还没初始化（门闸 != 12 / count 不合理）→ 返回 false，调用方下次重试
  if u32(api.read(root + ROOT_GATE, 4), 0) ~= 12 then return false end
  if not cnt or cnt <= 0 or cnt > 4096 then return false end
  local maps = api.read(root + ROOT_MAPS, cnt * MAP_SIZE)
  local recs = api.read(root + ROOT_RECS, cnt * REC_SIZE)
  if not maps or not recs then return false end
  local bykey = {}
  for i = 0, cnt - 1 do
    local k = u32(maps, i * MAP_SIZE + 8)
    if k and not bykey[k] then bykey[k] = i end
  end
  local lines, ok_n, not2, dup = {}, 0, 0, 0
  local seen, skey2id = {}, {}
  for id = 1, 400 do
    local rp
    if A.scanner then rp = select(1, A.scanner.strat_slot(id)) else rp = u64(api.read(A.tbl_by_id + id * 8, 8), 0) end
    if rp and rp > 0x10000 then
      local key = u32(api.read(rp + 4, 4), 0) or 0
      local i = bykey[key]
      if i then
        local off = i * REC_SIZE
        local ty, st = u32(recs, off + 0x0C), u32(recs, off + 0x14)
        ok_n = ok_n + 1
        if st ~= 2 then not2 = not2 + 1 end
        if seen[i] then dup = dup + 1 end
        seen[i] = true
        skey2id[key] = id
        lines[#lines + 1] = ('id=%-3d key=0x%08X 记录#%-4d type=%-3d state=%s  重号=%s'):format(
          id, key, i, ty or -1, tostring(st), seen[i] and '是' or '否')
      else
        lines[#lines + 1] = ('id=%-3d key=0x%08X 未在 mappings 里匹配到'):format(id, key)
      end
    end
  end
  dump_file('StratUnlock_table.log', table.concat(lines, '\\n') .. '\\n')
  pcall(dump_records)                       -- 只读：全部记录原样（找"拥有位"用）
  pcall(dump_progression, skey2id)          -- 只读，判据：切变第③段是否适用
  report(('状态表导出：可解析 %d 条，state≠2 的 %d 条，记录号重复 %d 条 → StratUnlock_table.log'):format(
    ok_n, not2, dup), true)
  return true
end

-- ---------------------------------------------------------------- 廉价复核
-- 返回 state（number）或 nil,why。成功路径只读 3 处：slot(8B) / root(8B) / state(4B)
local function quick_state(id)
  local A = resolve()
  if not A then return nil, '地址未解析' end
  local rp
  if A.scanner then
    rp = select(1, A.scanner.strat_slot(id))
  else
    rp = u64(api.read(A.tbl_by_id + id * 8, 8), 0)
  end
  if not rp or rp <= 0x10000 then return nil, 'slot 空了' end
  local root = u64(api.read(A.item_slot, 8), 0)
  if not root or root == 0 then return nil, '注册表根空了' end
  local c = state.rec_cache[id]
  if not (c and c.root == root) then
    local r, why = resolve_one(id)            -- 只在 root 变了时走这条贵路径
    if not r then return nil, tostring(why) end
    state.rec_cache[id] = { root = root, addr = r.addr, index = r.index, bit_addr = r.bit_addr }
    return r.state
  end
  local b = api.read(c.addr, 4)
  if not b then return nil, '状态读不到' end
  return u32(b, 0)
end

-- ---------------------------------------------------------------- 只读：progression(升级/授权表) 的 grant 导出
-- 判据（对应切变模组第 ③ 段）：切变当年除了翻 +0x14，还必须往升级树插 {1,key,1} 的 grant，
-- 附件才真解锁。这里只读地检查：**已解锁战备的 key 是否也出现在 grant 里**。
-- 结构（切变模组实测）：progression 全局 RVA 0x347CE78 → 头 24B{+0=2,+8=rows,+16=count}
--   组 112B{+0=key,+12=owner,+96=levels,+104=level_count}
--   级 0x848B{+0x828=grants,+0x830=grant_count,+0x838=branches,+0x840=branch_count}
--   grant 12B{u32 state, u32 key, u32 value}
local PROG_SLOT_RVA = 0x347CE78
-- 只读：把全部战备记录（400B）原样导出 —— 用于「同表差分」找"拥有位"
-- 判据：把 ~150 条记录按字段转置，找那个"只有少数几条不同值"的字段（你缺 9 个 → 应有 9 条离群）
dump_records = function()
  local A = resolve()
  if not A then return end
  local lines, n = {}, 0
  for id = 0, 200 do
    local rp
    if A.scanner then rp = select(1, A.scanner.strat_slot(id))
    else rp = u64(api.read(A.tbl_by_id + id * 8, 8), 0) end
    if rp and rp > 0x10000 then
      local rec = api.read(rp, 0x190)                 -- 400 字节整条
      if rec then
        n = n + 1
        local t = {}
        for i = 1, #rec do t[i] = ('%02X'):format(rec:byte(i)) end
        lines[#lines + 1] = ('id=%-3d '):format(id) .. table.concat(t)
      end
    end
  end
  dump_file('StratUnlock_records.log', table.concat(lines, '\n') .. '\n')
  report(('记录导出：%d 条 × %d 字节 → StratUnlock_records.log'):format(n, 0x190), true)
end

dump_progression = function(skey2id)
  local A = resolve()
  if not A then return end
  local pbase = u64(api.read(A.base + PROG_SLOT_RVA, 8), 0)
  if not pbase or pbase == 0 then report('progression 指针为空（表未加载）', true) return end
  local hdr = api.read(pbase, 24)
  if not hdr then report('progression 头读不到', true) return end
  local kind, rows, gn = u32(hdr, 0), u64(hdr, 8), u32(hdr, 16)
  if kind ~= 2 or not rows or not gn or gn < 1 or gn > 200 then
    report(('progression 头异常（kind=%s count=%s）'):format(tostring(kind), tostring(gn)), true)
    return
  end
  local lines, hit, total = {}, 0, 0
  for g = 0, gn - 1 do
    local row = api.read(rows + g * 112, 112)
    if row then
      local gk, go, lvp, lvn = u32(row, 0), u32(row, 12), u64(row, 96), u32(row, 104)
      if lvp and lvn and lvn > 0 and lvn <= 64 then
        for l = 0, lvn - 1 do
          local lv = api.read(lvp + l * 0x848, 0x848)
          if lv then
            local gp, gc = u64(lv, 0x828), u32(lv, 0x830)
            if gp and gc and gc > 0 and gc <= 128 then
              for k = 0, gc - 1 do
                local gr = api.read(gp + k * 12, 12)
                if gr then
                  total = total + 1
                  local st, key = u32(gr, 0), u32(gr, 4)
                  local sid = key and skey2id[key]
                  if sid then
                    hit = hit + 1
                    lines[#lines + 1] = ('组%-3d key=0x%08X owner=0x%08X 级%d grant[%d] state=%s → 战备 id=%d'):format(
                      g, gk or 0, go or 0, l, k, tostring(st), sid)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  dump_file('StratUnlock_progression.log', table.concat(lines, '\n') .. '\n')
  report(('progression 导出：扫过 %d 个 grant，其中 %d 个 key 命中战备（明细 → StratUnlock_progression.log）'):format(total, hit), true)
end

-- ---------------------------------------------------------------- 自动解锁（默认路径）
local function auto_step()
  if not AUTO.enabled then return end
  local now = os.clock()

  -- ---- 复核模式：已经写过之后，每 VERIFY_EVERY 秒花 3 次小 read 确认状态还在 ---
  if AUTO.done then
    if VERIFY_EVERY <= 0 then return end          -- cfg verify=0：只写一次，不复核
    if now < (AUTO.verify_at or 0) then return end
    AUTO.verify_at = now + VERIFY_EVERY
    for _, id in ipairs(TARGETS) do
      if AUTO.applied[id] then
        if WRITE_BIT then
          local c0 = state.rec_cache[id]
          if c0 and c0.bit_addr then
            local bb = api.read(c0.bit_addr, 1)
            if not bb then
              report(('复核：id=%d 选择位读不到 → 重新定位'):format(id), true)
              state.rec_cache[id] = nil
              ADDR.base, ADDR.scanner = nil, nil
              AUTO.done, AUTO.tries = false, 0
              return
            elseif math.floor(bb:byte(1) / 2) % 2 == 0 then
              local okb, ob, nb = set_bit8(c0.bit_addr, 0x02)
              report(('复核：id=%d 选择位被关掉（0x%02X）→ 重开为 0x%02X（%s）'):format(
                id, bb:byte(1), nb or 0, okb and 'OK' or 'FAIL'), true)
            end
          end
        end
        local st, why = quick_state(id)
        if st == nil then
          -- 表或根变了 → 丢掉缓存，下一轮重新完整定位
          state.rec_cache[id] = nil
          ADDR.base, ADDR.scanner = nil, nil
          AUTO.done = false
          AUTO.tries = 0
          report(('复核：id=%d 不可用（%s）→ 重新定位'):format(id, tostring(why)), true)
          return
        elseif st ~= 2 and st ~= 4 then
          local c = state.rec_cache[id]
          local ok = c and write_state32(c.addr, 2)
          report(('复核：id=%d 状态被改回 %s → 重写为 2（%s）'):format(id, tostring(st), ok and 'OK' or 'FAIL'), true)
        end
      end
    end
    return
  end

  if now < AUTO.next_at then return end
  AUTO.tries = AUTO.tries + 1
  local A, why = resolve()
  if not A then
    AUTO.next_at = now + 3
    if AUTO.tries <= 3 or AUTO.tries % 40 == 0 then
      report(('自动解锁：等表就绪（第 %d 次：%s）'):format(AUTO.tries, tostring(why)), true)
    end
    return
  end
  if not DUMPED then
    local okd, res = pcall(dump_all)
    if okd and res == true then DUMPED = true end   -- 注册表没就绪时不算数，下次再来
  end
  local allok = true
  for _, id in ipairs(TARGETS) do
    local r, why2 = resolve_one(id)
    if not r then
      allok = false
      if not AUTO.announced['r' .. id] then
        AUTO.announced['r' .. id] = true
        report(('自动解锁 id=%d 解析失败：%s'):format(id, why2), true)
      end
    else
        -- 条件 ②：+0x80 bit1（=数据表的 selectable）。不在列表里的条目这一位是 0，
        -- 判定函数会在这里就返回假 —— 不打开这一位，写 ③ 永远没用。
        if WRITE_BIT then
          local okb, ob, nb = set_bit8(r.bit_addr, 0x02)
          if okb and nb ~= ob then
            report(('★ 选择位 id=%d → +0x80 0x%02X -> 0x%02X（回读通过）'):format(id, ob, nb), true)
          elseif okb then
            report(('选择位 id=%d 本来就是开的（+0x80=0x%02X）'):format(id, ob), true)
          else
            allok = false
            report(('选择位 id=%d 写入失败：%s'):format(id, tostring(ob)), true)
          end
        end
        -- 条件 ③：注册表记录 +0x14 ∈ {2,4}
        if r.state == 2 or r.state == 4 then
          if not AUTO.applied[id] then
            AUTO.applied[id] = true
            report(('自动解锁：id=%d 记录#%d 已经是 %d（无需写）'):format(id, r.index, r.state), true)
          end
        else
          local ok, old = write_state32(r.addr, 2)
          if ok then
            AUTO.applied[id] = true
            state.writes = state.writes + 1
            state.done[#state.done + 1] = { addr = r.addr, old = old, id = id, index = r.index }
            report(('★ 自动解锁 id=%d → 记录#%d 地址=0x%X  %s -> 2（回读通过）'):format(
              id, r.index, r.addr, tostring(old)), true)
          else
            allok = false
            report(('自动解锁 id=%d 写入失败：%s'):format(id, tostring(old)), true)
          end
        end
    end
  end
  if allok then
    AUTO.done = true
    AUTO.verify_at = now + VERIFY_EVERY
    report(('自动解锁收尾：本次会话共写 %d 处；之后每 %d 秒复核一次（每次仅 3 次小 read）。'):format(
      state.writes, VERIFY_EVERY), true)
  else
    AUTO.next_at = now + 5
  end
end

-- ---------------------------------------------------------------- ModOptionsMenu（本版本不注册，保留备用）
local MOMDONE = false
local function register_mod_options()
  if MOMDONE then return end
  local mom = rawget(_G, 'ModOptionsMenu')
  if type(mom) ~= 'table' or mom.api ~= 1 then return end
  MOMDONE = true
  local MID = '战备指定解锁'
  local function opt(id, label, desc, fn)
    mom.register_option(id, { type = 'toggle', label = label, mod = MID, default = false, description = desc })
    mom.on_change(id, function(v)
      if not v then return end
      local ok, err = pcall(fn)
      if not ok then state.errs = state.errs + 1 report('动作失败: ' .. tostring(err), true) end
      pcall(mom.set, id, false)
    end)
  end
  opt('stratunlock.preview', '① 预览（只读）', '解析目标 id 的 r10/key/记录号/type/状态，不写任何东西', act_preview)
  opt('stratunlock.apply',   '② 解锁（写 +0x14 = 2）', '写前预检 + 写后回读，失败自动写回', act_apply)
  opt('stratunlock.revert',  '③ 还原', '把本次会话写过的记录写回原值', act_revert)
  opt('stratunlock.dump',    '④ 导出全部状态（只读）', '列出所有未解锁的战备 id / 记录号 / type', act_dump)
  report('已注册 ModOptionsMenu（4 个开关）', true)
end

-- ---------------------------------------------------------------- Scanner 说明
local function scanner_note()
  local S = rawget(_G, 'HD2Scanner')
  report(S and ('检测到 HD2Scanner v' .. tostring(S.version) .. '（本 mod 用自带 FFI，不依赖它）')
            or '未检测到 HD2Scanner（无硬前置，自带 FFI）', true)
end

-- ---------------------------------------------------------------- 挂载
local orig = rawget(_G, 'update')
local function tick()
  state.frame = state.frame + 1
  if state.frame == 2 then
    load_cfg()
    scanner_note()
    report(('目标 id：%s —— 自动模式，进入游戏后自己解锁，不需要任何界面操作'):format(
      table.concat(TARGETS, ',')), true)
  end
  if state.frame >= 5 then
    local ok2, err2 = pcall(auto_step)
    if not ok2 then
      state.errs = state.errs + 1
      if state.errs <= 5 then
        report('★ auto_step 异常: ' .. tostring(err2), true)
        if state.errs == 5 then
          report('★ 自动解锁已停用（异常 5 次，不再重试）—— 不是"在等表"，是已经停了', true)
        end
      end
      if state.errs >= 5 then AUTO.done = true end
    end
  end
  flush_log(false)
end
if type(orig) == 'function' then
  rawset(_G, 'update', function(...) pcall(tick) return orig(...) end)
else
  rawset(_G, 'update', function(...) pcall(tick) end)
end
report(('StratUnlock v%s 已加载：自动解锁 id=%s（无界面操作）'):format(VERSION, table.concat(TARGETS, ',')), true)
return state