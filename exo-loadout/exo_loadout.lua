-- HD2-Addon: mods/dsh/exo_loadout

-- ===========================================================================
--  EXO 战备自选（exo_loadout）—— 携带机体四选一 / 附加机体三选一 / 手臂改造
--
--  设计依据：本目录 DESIGN.md（含四台机体的实测数据与寻址链）
--
--  ⚠ 两条腿的前置不一样（这是本模组最容易写错的地方）：
--     · 手臂槽位  → MountComponentData 0x3845B1E0 —— **Scanner 能给**（LDLD 表，按类型哈希广播）
--     · 战备附加  → StratagemSettings 0x30EB789E —— **Scanner 给不了**
--                   该表在内存里不是 LDLD 块，只能按 package 值内容搜（沿用旧模组那套）
--
--  ⚠ node 不足以确认机体：爱国者/突破者共用 1137513325+3282525496，
--     解放者/伐木者共用 537031082+1641276944。必须走「实体哈希 → recIdx」，
--     node/pad 只当二级复核。
--
--  红线：本文件**只读 + 只写自己的目标**，不碰别的字段。
-- ===========================================================================

local VERSION = '0.8.0'
local MOD = 'mods/dsh/exo_loadout'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, phase = 'starting', writes = 0, refusals = 0, errs = 0,
                 slots = {}, confirm_phase = nil })
local state = rawget(_G, MOD)

-- ---------------------------------------------------------------- 日志（SKILL 6.15）
-- loader 的 open_log 是 "w" 模式（每次打开都截断），所以累积后一次性落盘。
-- 三条不变量：①环形上限 400  ②连续同一条折叠成 (×N)  ③脏标志 + 1 秒节流。
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
    local file = loader and loader.open_log and loader.open_log('ExoLoadout.log')
    if file then file:write(text); file:close() end
  end)
end

local function report(message, keep)
  if message == state.status then            -- 连续同一条：原地累加，不新增行
    state.repeat_n = (state.repeat_n or 1) + 1
    if #loghist > 0 then
      loghist[#loghist] = ('[frame %d] %s  (×%d)'):format(state.frame, message, state.repeat_n)
      log_dirty = true
    end
    return
  end
  state.status, state.repeat_n = message, 1
  print('[ExoLoadout] ' .. message)
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

-- ---------------------------------------------------------------- 四台机体（实测，2026-10-02）
-- 实体哈希来自 StratagemSettings 的「装载一号」；recIdx 来自 MountComponentData 索引区；
-- node/pad/item 来自对应记录的槽 0（左臂）/ 槽 1（右臂）。
-- ⚠⚠ u64（实体/package/icon/臂件）律存【BE 十六进制字符串】，绝不能用 Lua 数字
--   —— 它们是 1e18 量级，超过 2^53，LuaJIT 的 number 存不下会静默失真
--   （实例：7298250363396168598 变成 ...704，差 106）。见 SKILL §6.1。
--   node / recIdx / pad 这种小整数才用 number。
local function le(h)                     -- BE hex -> LE 字节串（= 内存里的字节序）
  local t = {}
  for i = #h - 1, 1, -2 do t[#t + 1] = string.char(tonumber(h:sub(i, i + 1), 16)) end
  return table.concat(t)
end

local EXO = {
{ id = 27, key = 'patriot', name = '爱国者 EXO-45',
  ent = '79E4B3D2DA5E45E3', rec_idx = 17,
  pkg = '22749A294788AF66', icon = '396ECA60A6E80E17',
  left  = { node = 1137513325, pad = 2, item = '824B7E0C4C879EB5' },
  right = { node = 3282525496, pad = 1, item = '08F6089289C83D22' } },

{ id = 10, key = 'emancipator', name = '解放者 EXO-49',
  ent = 'C2D449ECF7FACAB1', rec_idx = 107,
  pkg = 'E72D3E9B05C3DB0B', icon = 'CCA47E13FC4682E8',
  left  = { node = 537031082,  pad = 2, item = 'E5F64DCC3BFE9DD1' },
  right = { node = 1641276944, pad = 1, item = 'FF9878576A4C543B' } },

{ id = 88, key = 'breacher', name = '突破者 EXO-55',
  ent = '35DBF54F016F3624', rec_idx = 105,
  pkg = '7DE417DB7552D9FC', icon = 'A16325D3F60F1077',
  left  = { node = 1137513325, pad = 2, item = '65489809A8181B96' },
  right = { node = 3282525496, pad = 1, item = 'DF51FE8D62F294BE' } },

{ id = 91, key = 'lumberer', name = '伐木者 EXO-51',
  ent = '7B2326F6FD9C8069', rec_idx = 106,
  pkg = '0A4BD8A1833F11B2', icon = 'C9C24C7E931BBC83',
  left  = { node = 537031082,  pad = 2, item = '0736BEE2D6328726' },
  right = { node = 1641276944, pad = 1, item = '17C5D12D8D5DEE2C' } },
}

local BY_ID, BY_KEY = {}, {}
for i, e in ipairs(EXO) do
  e.index = i
  BY_ID[e.id], BY_KEY[e.key] = e, e
end

-- ---------------------------------------------------------------- 选择 + cfg 持久化
-- 默认：携带爱国者、附加解放者、手臂全用原装
local DEFAULT_EXTRA = rawget(_G, 'EXO_DEFAULT_EXTRA') or 'none'
local CFG = { carry = 'patriot', extra = DEFAULT_EXTRA, arms = {} }
local CFG_FILE
do
  local loader = rawget(_G, 'CowboyBingusModLoader')
  local base = loader and type(loader.log_directory) == 'string'
               and loader.log_directory:gsub('[/\\]Logs$', '') or '.'
  CFG_FILE = base .. '/ExoLoadout.cfg'
end

local function cfg_write_default()
  pcall(function()
    local f = io.open(CFG_FILE, 'w')
    if not f then return end
    f:write('# EXO 战备自选 —— 改完 1 秒内热生效\n')
    f:write('# 机体 key: patriot(爱国者) / emancipator(解放者) / breacher(突破者) / lumberer(伐木者)\n')
    f:write('carry=patriot        # 携带机体（四选一）\n')
    f:write('extra=' .. DEFAULT_EXTRA .. '           # 附加机体（无 / 四选一，不能与 carry 相同）\n')
    f:write('# 手臂：写 item 哈希。候选 = 携带两台各自的同侧原装件（可在两台间互换）\n')
    f:write('# arm_<key>_L= / arm_<key>_R= ，留空则用该机体原装\n')
    f:close()
  end)
end

local function cfg_load()
  local f = io.open(CFG_FILE, 'r')
  if not f then cfg_write_default() return end
  local text = f:read('*a') f:close()
  if not text then return end
  for line in text:gmatch('[^\r\n]+') do
    line = line:gsub('#.*$', '')                       -- 先砍行尾注释（2026-10-02 踩过）
    local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k and v and v ~= '' then
      local b, sl = k:match('^arm_(%w+)_([LR])$')
      if b and sl then
        -- item 一律 16 位 BE 十六进制；不能用 tonumber：u64 超 2^53 会静默失真（SKILL 6.1）
        if #v == 16 and v:match('^%x+$') then CFG.arms[b .. '.' .. sl] = v:upper() end
      elseif k == 'carry' or k == 'extra' then
        CFG[k] = v
      end
    end
  end
end
cfg_load()

local function cfg_save()
  -- ⚠ 不再静默吞错：io.open('w') 会**立刻截断**文件，后面任何一步出错都会留下空文件
  --   （交接单记过这个坑）。所以出错要记下来，别让它无声无息。
  local ok, err = pcall(function()
    local f = io.open(CFG_FILE, 'w')
    if not f then error('io.open 失败: ' .. tostring(CFG_FILE)) end
    f:write('# EXO 战备自选\n')
    f:write('carry=' .. tostring(CFG.carry) .. '\n')
    f:write('extra=' .. tostring(CFG.extra) .. '\n')
    for _, e in ipairs(EXO) do
      for _, sl in ipairs({ 'L', 'R' }) do
        local it = CFG.arms[e.key .. '.' .. sl]
        if it then f:write(('arm_%s_%s=%s\n'):format(e.key, sl, it)) end
      end
    end
    f:close()
  end)
  if not ok then
    state.cfg_err = tostring(err)
    report('cfg 保存失败: ' .. tostring(err), true)
  else
    state.cfg_err = nil
  end
  return ok
end

local function pick_carry() return BY_KEY[CFG.carry] end
local function pick_extra() return BY_KEY[CFG.extra] end

-- ---------------------------------------------------------------- 手臂候选池
-- 用户 2026-10-02 定：允许跨机体，但**只在携带的两台之间**互换。
-- 所以候选池 = 这两台各自的同侧 item（+ 各自的同侧额外变体）。
-- 解放者第三个变体 MK3 是**右手**（用户："右左右" = 手臂/MK2/MK3 依次为 右/左/右）。
local EXTRA_ARMS = {
  emancipator = { R = { '3E3A31261A124454' } },   -- MK3(右) 200发
}
-- ⚠ 弹药量是玩家能直接感觉到的差异（2026-10-02 用户提供）：
--   解放者「手臂(右)」100 发 vs「手臂MK3(右)」**200 发** —— 所以 MK3 不是换皮，是个有实战意义的选择。
--   其余臂件的弹药量尚未核对，先不标。
local ARM_NAME = {
  ['824B7E0C4C879EB5'] = '火箭发射器',
  ['08F6089289C83D22'] = '加特林',
  ['E5F64DCC3BFE9DD1'] = '机炮（左）',
  ['FF9878576A4C543B'] = '机炮（右）100发',
  ['3E3A31261A124454'] = '机炮（右）200发',
  ['65489809A8181B96'] = '护盾',
  ['DF51FE8D62F294BE'] = '霰弹枪',
  ['0736BEE2D6328726'] = '喷火器',
  ['17C5D12D8D5DEE2C'] = '反坦克炮',
}
local function arm_name(item) return ARM_NAME[item] or ('item ' .. tostring(item)) end

-- slot: 'L' | 'R' —— 同侧互换，不跨左右
local function candidates(slot)
  local out, seen = {}, {}
  local function push(body)
    if not body then return end
    local v = (slot == 'L') and body.left or body.right
    if v and v.item and not seen[v.item] then seen[v.item] = true; out[#out+1] = v.item end
    local ex = EXTRA_ARMS[body.key] and EXTRA_ARMS[body.key][slot]
    if ex then
      for _, it in ipairs(ex) do
        if not seen[it] then seen[it] = true; out[#out+1] = it end
      end
    end
  end
  push(pick_carry()); push(pick_extra())
  -- 排序，让 cfg 与 UI 的输出稳定（不依赖 body 顺序）
  table.sort(out)
  return out
end

local function is_candidate(slot, item)
  for _, it in ipairs(candidates(slot)) do if it == item then return true end end
  return false
end

-- 取某机体某槽最终要写的 item：cfg 里合法就用它，否则回落到该机体的原装
local function arm_item(body, slot)
  local want = CFG.arms[body.key .. '.' .. slot]
  if want and is_candidate(slot, want) then return want end
  return (slot == 'L') and body.left.item or body.right.item
end

-- ---------------------------------------------------------------- 自检
-- 离线能验的都在这里：四台的数据自洽 + 选择合法（尤其**自引用保护**）。
-- u64 一律用「16 位 BE 十六进制字符串」表示（SKILL 6.1：LuaJIT 的 number 只有 53 位）
local function is_hex16(v)
  return type(v) == 'string' and #v == 16 and v:match('^%x+$') ~= nil
end

local function selfcheck()
  local ok, bad = 0, {}
  local function chk(cond, why) if cond then ok = ok + 1 else bad[#bad + 1] = why end end

  chk(#EXO == 4, '机体数应为 4，实际 ' .. #EXO)
  local seen_id, seen_key, seen_rec = {}, {}, {}
  for _, e in ipairs(EXO) do
    chk(not seen_id[e.id],    '战备ID 重复: ' .. e.id)
    chk(not seen_key[e.key],  'key 重复: ' .. e.key)
    chk(not seen_rec[e.rec_idx], 'recIdx 重复: ' .. e.rec_idx)
    seen_id[e.id], seen_key[e.key], seen_rec[e.rec_idx] = true, true, true
    chk(e.rec_idx >= 0 and e.rec_idx < 200, e.key .. ': recIdx 越界 ' .. e.rec_idx)
    chk(is_hex16(e.pkg),  e.key .. ': pkg 必须是 16 位十六进制，实际 ' .. tostring(e.pkg))
    chk(is_hex16(e.icon), e.key .. ': icon 必须是 16 位十六进制，实际 ' .. tostring(e.icon))
    chk(is_hex16(e.ent),  e.key .. ': ent 必须是 16 位十六进制，实际 ' .. tostring(e.ent))
    chk(e.left.pad == 2,  e.key .. ': 左臂 pad 应为 2，实际 ' .. e.left.pad)
    chk(e.right.pad == 1, e.key .. ': 右臂 pad 应为 1，实际 ' .. e.right.pad)
    chk(e.left.node ~= e.right.node, e.key .. ': 左右 node 不应相同')
    chk(is_hex16(e.left.item),  e.key .. ': 左臂 item 必须是 16 位十六进制')
    chk(is_hex16(e.right.item), e.key .. ': 右臂 item 必须是 16 位十六进制')
  end
  -- 结构性事实 ②：node 只有两套，必须成对出现
  chk(BY_KEY.patriot.left.node == BY_KEY.breacher.left.node,   '爱国者/突破者 左 node 应共用')
  chk(BY_KEY.patriot.right.node == BY_KEY.breacher.right.node, '爱国者/突破者 右 node 应共用')
  chk(BY_KEY.emancipator.left.node == BY_KEY.lumberer.left.node,   '解放者/伐木者 左 node 应共用')
  chk(BY_KEY.emancipator.right.node == BY_KEY.lumberer.right.node, '解放者/伐木者 右 node 应共用')
  chk(BY_KEY.emancipator.left.node ~= BY_KEY.patriot.left.node,    '两套 node 不应混同')

  -- 自引用保护（取代旧版的"二选一"）
  local c, x = pick_carry(), pick_extra()
  chk(c ~= nil, '携带机体未选/不存在: ' .. tostring(CFG.carry))
  chk(CFG.extra == 'none' or x ~= nil, '附加机体未选/不存在: ' .. tostring(CFG.extra))
  chk(c and (not x or c.id ~= x.id), '★ 自引用：附加机体不能等于携带机体')

  -- 手臂候选池（用户定的"只在携带两台之间互换"）
  if c and x then
    for _, sl in ipairs({ 'L', 'R' }) do
      local cand = candidates(sl)
      chk(#cand >= 2, ('%s 槽候选应 >= 2（两台各一件），实际 %d'):format(sl, #cand))
      local function has(it) for _, v in ipairs(cand) do if v == it then return true end end return false end
      chk(has(c.left.item) or has(c.right.item), c.key .. ' 的原装件应落在候选池里')
      chk(has(x.left.item) or has(x.right.item), x.key .. ' 的原装件应落在候选池里')
    end
    -- 跨机体拿到的候选也要在（例：爱国者+解放者 时，左槽应同时有两者）
    local Lc = candidates('L')
    local function has2(list, it) for _, v in ipairs(list) do if v == it then return true end end return false end
    chk(has2(Lc, c.left.item) and has2(Lc, x.left.item), '左槽应含携带两台的左臂件')
    local Rc = candidates('R')
    chk(has2(Rc, c.right.item) and has2(Rc, x.right.item), '右槽应含携带两台的右臂件')
    -- arm_item：携带的两台最终必须落在候选池；**非携带**的必须回落成自己的原装
    for _, e in ipairs(EXO) do
      for _, sl in ipairs({ 'L', 'R' }) do
        local own = (sl == 'L') and e.left.item or e.right.item
        local got = arm_item(e, sl)
        if is_candidate(sl, own) then
          chk(is_candidate(sl, got),
              ('%s.%s 最终 item 必须落在候选池（实际 %s）'):format(e.key, sl, tostring(got)))
        else
          chk(got == own, ('%s.%s 不在候选池，应回落成原装'):format(e.key, sl))
        end
      end
    end
  end
  -- 解放者三件都是机炮：左槽只能装「机炮（左）」，右槽只能装「机炮（右）」两档
  -- ⚠ 只在**携带了解放者**时才成立 —— 别的配置下这三件根本不在候选池里
  if BY_KEY.emancipator and (CFG.carry == 'emancipator' or CFG.extra == 'emancipator') then
    chk(is_candidate('L', 'E5F64DCC3BFE9DD1'), '解放者 机炮（左）应在左槽候选')
    chk(not is_candidate('L', '3E3A31261A124454'), '解放者 机炮（右）200发）不该在左槽候选')
    chk(not is_candidate('R', 'E5F64DCC3BFE9DD1'), '解放者 机炮（左）不该在右槽候选')
  end

  return ok, bad
end

local n_ok, bad = selfcheck()
state.selfcheck = { ok = n_ok, bad = bad }
-- 诊断/测试口子：可直接改 state.cfg（同一张表），然后 state.recheck() 重跑自检
state.cfg = CFG
state.exo  = EXO
-- 供夹具驱动（与 state.cfg / state.recheck 同类）
state.candidates   = candidates
state.is_candidate = is_candidate
state.arm_item     = arm_item
state.arm_name     = arm_name
state.le           = le
state.save         = cfg_save
state.load         = cfg_load
function state.recheck()
  local o, b = selfcheck()
  state.selfcheck = { ok = o, bad = b }
  return o, b
end
do
  local s = ('自检 %d/%d'):format(n_ok, n_ok + #bad)
  if #bad > 0 then s = s .. ' —— ' .. table.concat(bad, '; ') end
  report(s, #bad > 0)
end

-- ⚠⚠ local 必须声明在【所有用它的函数之前】（Lua 词法作用域是位置性的）。
--   2026-10-02 踩到：手臂写入块里的 apply_all 用了 SCAN，而 local SCAN 在它后面 →
--   解析成全局 nil → 手臂一直写不进去（日志里是 `attempt to index global 'SCAN'`）。
-- （short_name 也必须在用它的 apply_rack 之前）
local function short_name(e) return e.name:match('^(%S+)') or e.name end
local USE_SELF_SCAN = (rawget(_G, 'EXO_USE_SELF_SCAN') == true)
local SCAN = { api = nil, retry_at = 0, warned = false, polls = 0, applied = 0 }

-- ---------------------------------------------------------------- ffi / kernel32（读写 + 改页保护）
-- 与 guard_dog / 旧 exosuit 同一套写法；VirtualQuery 的 protect 要先用 bit.band 剥掉修饰位再比。
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
    } EXO_MBI;
    void  *GetCurrentProcess(void);
    int    ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
    int    WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
    int    VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
    size_t VirtualQuery(const void *address, EXO_MBI *info, size_t length);
  ]]
  local kernel  = ffi.load('kernel32')
  local process = kernel.GetCurrentProcess()
  local M = {}
  function M.read(address, size)
    if not address or address <= 0 or size <= 0 then return nil end
    local buf, got = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
    local ok2 = pcall(kernel.ReadProcessMemory, process, ffi.cast('const void *', address), buf, size, got)
    if not ok2 or tonumber(got[0]) ~= size then return nil end
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
  local mbi = ffi.new('EXO_MBI[1]')
  function M.regions()
    local test_regions = rawget(_G, 'EXO_TEST_REGIONS')
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
if not api_ok then report('ffi/kernel32 不可用，手臂写入关闭: ' .. tostring(api), true) end

-- ---------------------------------------------------------------- 手臂写入（MountComponentData）
local RACK_TYPE    = 0x3845B1E0
local RACK_SR      = 120        -- 记录长
local RACK_SLOT_SR = 24         -- 槽长
local RDATA_OFF    = 24         -- LDLD 表头
local R_MIN, R_MAX = 1024, 4194304
local R_CAP        = 262144
local MAGIC        = 'LDLD'
local SLOT_NO      = { L = 0, R = 1 }     -- 槽0 = 左臂、槽1 = 右臂
local SLOT_PAD     = { L = 2, R = 1 }     -- pad 是白送的第三个校验条件

local function d32(b, o) return b:byte(o+1) + b:byte(o+2)*256 + b:byte(o+3)*65536 + b:byte(o+4)*16777216 end
local function hexs(b)
  if not b then return '(nil)' end
  return (b:gsub('.', function(ch) return string.format('%02X', ch:byte()) end))
end

-- 表头三件套：魔数 / version / 类型哈希（size 只做区间检查）
local function rack_size(magic)
  local h = api and api.read(magic, RDATA_OFF)
  if not h or h:sub(1, 4) ~= MAGIC then return nil end
  if d32(h, 4) ~= 1 or d32(h, 8) ~= RACK_TYPE then return nil end
  local size = d32(h, 12)
  if not size or size < R_MIN or size > R_MAX then return nil end
  return size
end

-- 记录区起点候选：16 的倍数 + 剩余能被记录长整除 + 索引区每条都合法
-- （索引条数会随版本变，322/324 都见过 —— 所以必须推，不能硬编码）
local function layout_cands(data, size)
  local cands, ni = {}, 1
  while true do
    local b = ni * 16
    if b + RACK_SR > size then break end
    if (size - b) % RACK_SR == 0 then
      local n = (size - b) / RACK_SR
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

-- 索引区里按【实体哈希的 LE 字节串】找 recIdx -> 记录在 data 里的偏移
local function find_rec(data, base, nr, ent_le)
  local q = data:find(ent_le, 1, true)
  while q do
    if (q - 1) % 16 == 0 and q - 1 + 16 <= base then
      local ix, pad = d32(data, q - 1 + 8), d32(data, q - 1 + 12)
      if pad == 0 and ix < nr then return base + ix * RACK_SR, ix end
    end
    q = data:find(ent_le, q + 1, true)
  end
  return nil
end

-- 写 8 字节 + 回读校验（失败一律记 refuse，绝不当成功）
local function write8(address, bytes)
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

-- 一张表副本：选起点 -> 逐槽复核 -> 写
--   mode = 'config'  写用户配置的 item
--   mode = 'vanilla' 写回原装 item（初始化 / 确认的第一阶段）
local function apply_rack(magic, mode, force)
  if not api then return end
  local size = rack_size(magic)
  if not size then return end
  if size > R_CAP then
    report(('表 0x%X 声明 size=%d 超过读取上限，跳过'):format(magic, size)) return
  end
  local data = api.read(magic + RDATA_OFF, size)
  if not data then return end

  local c, x = pick_carry(), pick_extra()
  if not c then return end
  if x and x.id == c.id then return end

  -- 槽位复核：node + pad 都要对。
  -- ⚠ node 只有两套（爱国者/突破者共用、解放者/伐木者共用）——光看 node 分不出机体！
  local function slot_ok(cand, body, sl)
    local rec = find_rec(data, cand.base, cand.n, le(body.ent))
    if not rec then return false end
    local o = rec + SLOT_NO[sl] * RACK_SLOT_SR
    local want_node = (sl == 'L') and body.left.node or body.right.node
    return d32(data, o + 8) == want_node and d32(data, o + 12) == SLOT_PAD[sl]
  end

  local cands = layout_cands(data, size)
  local chosen
  for _, cand in ipairs(cands) do
    if slot_ok(cand, c, 'L') and slot_ok(cand, c, 'R')
       and (not x or (slot_ok(cand, x, 'L') and slot_ok(cand, x, 'R'))) then
      chosen = cand break
    end
  end
  if not chosen then
    if not state.rack_warned or state.frame - state.rack_warned > 6000 then
      state.rack_warned = state.frame
      report(('表 0x%X：%d 个候选起点都没通过槽位复核（size=%d），本轮拒写'):format(
        magic, #cands, size), true)
    end
    return
  end
  state.rack_magic, state.rack_layout = magic, chosen.base

  for _, body in ipairs(x and { c, x } or { c }) do
    for _, sl in ipairs({ 'L', 'R' }) do
      local rec, ix = find_rec(data, chosen.base, chosen.n, le(body.ent))
      if rec then
        local o = rec + SLOT_NO[sl] * RACK_SLOT_SR
        local address = magic + RDATA_OFF + o
        local cur  = data:sub(o + 1, o + 8)
        local orig = (sl == 'L') and body.left.item or body.right.item
        local cfg  = arm_item(body, sl)
        -- 目标值随 mode 变；「另一个合法值」永远是"这次不想要的那个"
        local want = (mode == 'vanilla') and orig or cfg
        local other = (mode == 'vanilla') and cfg or orig
        local last = state.slots[address] and state.slots[address].item
        local who  = short_name(body) .. ((sl == 'L') and ' 左臂' or ' 右臂')
        if cur == le(want) then
          state.slots[address] = { item = want, orig = orig, who = who }
        elseif force or want == orig or cur == le(other) or (last and cur == le(last)) then
          if write8(address, le(want)) then
            state.writes = state.writes + 1
            state.slots[address] = { item = want, orig = orig, who = who }
            report(('%s：%s %s -> %s（recIdx %d，node/pad 未动）'):format(
              (mode == 'vanilla') and '还原' or '已改手臂', who, arm_name(other), arm_name(want), ix), true)
          end
        else
          state.refusals = state.refusals + 1
          report(('表 0x%X：%s 当前 %s 既非原装也非目标，拒写（recIdx %d）'):format(
            magic, who, hexs(cur), ix), true)
        end
      end
    end
  end
end

-- 写后复查：被游戏冲掉就重写（消费者自己的正确性底线）
local function recheck()
  if not api then return end
  local live, fixed, drop = 0, 0, 0
  for address, info in pairs(state.slots) do
    local cur = api.read(address, 8)
    if cur == le(info.item) then
      live = live + 1
    elseif write8(address, le(info.item)) then
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

-- 对 Scanner 广播的每一张表副本跑一遍
local function apply_all(mode, force)
  if not api or not SCAN.api then return 0 end
  local snap = SCAN.api.poll(RACK_TYPE)
  SCAN.polls = SCAN.polls + 1
  local n = 0
  if type(snap) == 'table' and type(snap.entries) == 'table' then
    for i = 1, #snap.entries do
      local e = snap.entries[i]
      if type(e) == 'table' and type(e.addr) == 'number' then
        local ok2, err = pcall(apply_rack, e.addr, mode, force)
        if not ok2 then
          state.errs = state.errs + 1
          if state.errs <= 3 then report('apply_rack 异常: ' .. tostring(err), true) end
        else
          n = n + 1
        end
      end
    end
  end
  return n
end

local function restore_arms_all()
  if not api then return 0 end
  local n = 0
  for address, info in pairs(state.slots or {}) do
    local orig = info.orig
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

-- ---------------------------------------------------------------- StratagemSettings 旧路径（package 内容搜）
local STRAT_ADD_OFF = 32        -- additional_stratagem 相对 package 字段
local STRAT_NEI_A   = 28        -- depends_on（应为 0）
local STRAT_NEI_B   = 36        -- max_in_loadout（应为 0）
local OFF_USE       = -88       -- use 相对 package 字段
local USE_BYTES     = le('00000002')
local ZERO4         = '\0\0\0\0'
local STRAT_CHUNK   = 256 * 1024
local STRAT_OVER    = 64
local STRAT_BUDGET  = 8 * 1024 * 1024   -- 每帧扫描预算，约 0.5~1 ms

-- ★ AOB 优先路径：Scanner 从 game.dll 里解出「战备记录指针数组」，按 ID 直接取记录。
--   记录首的绝对偏移，与上面那套「相对 package 字段」的偏移一一对应：
--     +0x00 id    +0x50 use    +0xA8 package    +0xB0 icon
--     +0xC4 depends_on(=0)     +0xCC max_in_loadout(=0)    +0xC8 additional(= package+32)
local STRAT_PKG_OFF  = 0xA8     -- = 旧路径的 c（package 字段）
local STRAT_ICON_OFF = 0xB0
local STRAT_DEP_OFF  = 0xC4
local STRAT_MAX_OFF  = 0xCC
local STRAT_REC_READ = 0xD0     -- 一次读够（覆盖到 +0xCC）
local STRAT_ID_MAX   = 255      -- 指针数组上界（与参考实现 / Scanner 一致）

local AOB = { api = nil, retry_at = 0, next_try = 0, slot_id = {}, why = nil, hits = 0 }

local function aob_api()
  if AOB.api then return AOB.api end
  local now = os.clock()
  if now < AOB.retry_at then return nil end
  AOB.retry_at = now + 60
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and type(S.strat_rec) == 'function'
     and type(S.strat_slot) == 'function' and type(S.strat_table_status) == 'function' then
    AOB.api = S
    report('已接上 HD2Scanner：AOB 战备表定位可用（优先路径）', true)
    return S
  end
  return nil
end

state.strat_hits = state.strat_hits or {}
state.strat_addr = state.strat_addr or {}
state.strat_slots = state.strat_slots or {}
state.strat_orig = state.strat_orig or {}
state.strat_regions, state.strat_done = nil, false
state.strat_ok, state.strat_scanned = false, 0
state.strat_scan_requested = false
state.strat_scanner_active = false
state.strat_scanner_used = false
state.strat_ri, state.strat_off = 1, 0

local STRAT_PATTERNS = {}
for _, e in ipairs(EXO) do
  local pkg, icon = le(e.pkg), le(e.icon)
  e._pkg_le, e._icon_le = pkg, icon
  STRAT_PATTERNS[#STRAT_PATTERNS + 1] = pkg
  STRAT_PATTERNS[#STRAT_PATTERNS + 1] = icon
end
local SELF_ADDRS = {}
for _, s2 in ipairs(STRAT_PATTERNS) do
  local p = tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', s2)))
  if p and p ~= 0 then SELF_ADDRS[#SELF_ADDRS + 1] = p end
end
local function is_self_hit(a)
  for i = 1, #SELF_ADDRS do
    local d = a - SELF_ADDRS[i]
    if d > -4096 and d < 4096 then return true end
  end
  return false
end
local function strat_collect_regions()
  local all = api and api.regions and api.regions() or {}
  local list = {}
  for i = 1, #all do
    if all[i].size >= 65536 then list[#list + 1] = all[i] end
  end
  table.sort(list, function(a, b) return a.size > b.size end)
  return list
end

local function strat_begin()
  state.strat_regions = strat_collect_regions()
  state.strat_ri, state.strat_off = 1, 0
  state.strat_done, state.strat_scanned = false, 0
  if #state.strat_regions == 0 then state.strat_done = true return end
  report(('战备内容搜：%d 个区域，开始扫 package 值'):format(#state.strat_regions), true)
end

local function strat_scan_step()
  if not (api and api.regions) then return end
  local c, x = pick_carry(), pick_extra()
  if not (c and x and c.id ~= x.id) then return end
  if not state.strat_regions then strat_begin() end
  if state.strat_done then return end
  local budget = STRAT_BUDGET
  while budget > 0 and state.strat_ri <= #state.strat_regions do
    local r = state.strat_regions[state.strat_ri]
    if state.strat_off >= r.size then
      state.strat_ri, state.strat_off = state.strat_ri + 1, 0
    else
      local n = math.min(STRAT_CHUNK, r.size - state.strat_off)
      local want = n
      if state.strat_off + n + STRAT_OVER <= r.size then want = n + STRAT_OVER end
      local buf = api.read(r.base + state.strat_off, want)
      if buf then
        state.strat_scanned = state.strat_scanned + n
        for _, e in ipairs({ c, x }) do
          local pat, pos = e._pkg_le, 1
          while true do
            local q = buf:find(pat, pos, true)
            if not q then break end
            pos = q + 1
            local abs = r.base + state.strat_off + q - 1
            if not is_self_hit(abs) then
              local hits = state.strat_hits[e.key]
              if not hits then hits = {} state.strat_hits[e.key] = hits end
              if #hits < 16 then hits[#hits + 1] = abs end
            end
          end
        end
      end
      state.strat_off = state.strat_off + n
      budget = budget - n
    end
  end
  if state.strat_ri > #state.strat_regions then
    state.strat_done = true
    report(('战备内容搜完成：扫过 %.1f MB，%s=%d 命中 / %s=%d 命中'):format(
      state.strat_scanned / 1048576,
      short_name(c), #(state.strat_hits[c.key] or {}),
      short_name(x), #(state.strat_hits[x.key] or {})), true)
  end
end
local function strat_validate(body)
  local hits = state.strat_hits[body.key]
  if not hits then return nil end
  for i = 1, #hits do
    local c = hits[i]
    local icon = api.read(c + 8, 8)
    if icon == body._icon_le then
      local pre  = api.read(c + STRAT_NEI_A, 4)
      local post = api.read(c + STRAT_NEI_B, 4)
      if pre == ZERO4 and post == ZERO4 then return c end
    end
  end
  return nil
end

-- AOB 复核：用 package / icon / 邻字段确认这条记录就是我们找的那台机体。
-- 命中返回 package 字段地址（记录首 + 0xA8）—— 与旧路径的 c 语义完全一致，
-- 所以下游 strat_write_additional / strat_write_use 一行都不用改。
local function strat_aob_probe(S, id, body)
  local rec = S.strat_rec(id, STRAT_REC_READ)
  if not rec then return false end
  if rec:sub(STRAT_PKG_OFF + 1,  STRAT_PKG_OFF + 8)  ~= body._pkg_le  then return false end
  if rec:sub(STRAT_ICON_OFF + 1, STRAT_ICON_OFF + 8) ~= body._icon_le then return false end
  if rec:sub(STRAT_DEP_OFF + 1,  STRAT_DEP_OFF + 4)  ~= ZERO4        then return false end
  if rec:sub(STRAT_MAX_OFF + 1,  STRAT_MAX_OFF + 4)  ~= ZERO4        then return false end
  local ptr = S.strat_slot(id)
  if not ptr then return false end
  return ptr + STRAT_PKG_OFF
end

-- AOB 直取：返回 package 字段地址；拿不到返回 nil + 原因（不抛错）
local function strat_aob_find(body)
  local S = aob_api()
  if not S then return nil, 'no-scanner' end
  local okst, st = pcall(S.strat_table_status)
  if not okst or type(st) ~= 'table' then return nil, 'bad-status' end
  if st.state ~= 'ok' then
    local now = os.clock()
    if st.state ~= 'scanning' and now >= AOB.next_try then
      AOB.next_try = now + 60
      pcall(S.strat_table_request)
      if st.state == 'failed' then
        report('AOB 战备表解析失败（60 秒后重试，先走兜底）：' .. tostring(st.reason), true)
      end
    end
    return nil, 'table:' .. tostring(st.state)
  end
  -- ① 记住过的槽位 / EXO 自带的 id：直取
  local cached = AOB.slot_id[body.key]
  if cached then
    local c = strat_aob_probe(S, cached, body)
    if c then return c, 'cache' end
    AOB.slot_id[body.key] = nil
  end
  local c = strat_aob_probe(S, body.id, body)
  if c then AOB.slot_id[body.key] = body.id return c, 'id' end
  -- ② 全表枚举（一次就记住槽位号，之后走 ①）
  for id = 0, STRAT_ID_MAX do
    if id ~= body.id then
      c = strat_aob_probe(S, id, body)
      if c then AOB.slot_id[body.key] = id return c, ('scan:%d'):format(id) end
    end
  end
  return nil, 'not-found'
end

-- AOB 优先填充（返回填上的条数）；只在还缺地址时调用
local function strat_aob_fill(c, x)
  local n = 0
  for _, body in ipairs({ c, x }) do
    if not state.strat_addr[body.key] then
      local a, why = strat_aob_find(body)
      AOB.why = why
      if a then
        state.strat_addr[body.key] = a
        AOB.hits = AOB.hits + 1
        n = n + 1
        report(('AOB 定位：%s -> 0x%X（%s）'):format(short_name(body), a, tostring(why)), true)
      end
    end
  end
  return n
end
local function strat_write_additional(carry, extra)
  local c = state.strat_addr[carry.key]
  if not c then return false end
  local addr = c + STRAT_ADD_OFF
  local cur = api.read(addr, 4)
  if not cur then return false end
  if not state.strat_orig[addr] then state.strat_orig[addr] = cur end
  local width = 4
  if cur:byte(2) == 0 and cur:byte(3) == 0 and cur:byte(4) == 0 then width = 1 end
  local want = (width == 1) and string.char(extra.id) or le(string.format('%08X', extra.id))
  local now  = (width == 1) and cur:byte(1) or d32(cur, 0)
  if now == extra.id then
    state.strat_slots[addr] = { bytes = want }
    return true
  end
  if now ~= 0 then
    state.refusals = state.refusals + 1
    report(('战备附加：%s +32 当前 %d 既非 0 也非目标 %d，拒写'):format(
      short_name(carry), now, extra.id), true)
    return false
  end
  if write8(addr, want) then
    state.writes = state.writes + 1
    state.strat_slots[addr] = { bytes = want }
    report(('已改战备附加：%s -> %s（+32，宽度 %d）'):format(
      short_name(carry), short_name(extra), width), true)
    return true
  end
  return false
end

local function strat_write_use(body)
  local c = state.strat_addr[body.key]
  if not c then return false end
  local addr = c + OFF_USE
  local cur = api.read(addr, 4)
  if not cur then return false end
  if not state.strat_orig[addr] then state.strat_orig[addr] = cur end
  if cur == USE_BYTES then
    state.strat_slots[addr] = { bytes = USE_BYTES }
    return true
  end
  if write8(addr, USE_BYTES) then
    state.writes = state.writes + 1
    state.strat_slots[addr] = { bytes = USE_BYTES }
    report(('战备 use：%s -> 2（package-88）'):format(short_name(body)), true)
    return true
  end
  return false
end

local function restore_strat()
  if not (api and api.read) then return end
  local n = 0
  for addr, bytes in pairs(state.strat_orig or {}) do
    local cur = api.read(addr, #bytes)
    if cur and cur ~= bytes then
      if write8(addr, bytes) then n = n + 1 end
    end
  end
  state.strat_orig, state.strat_addr = {}, {}
  state.strat_hits, state.strat_regions = {}, nil
  state.strat_done, state.strat_ok = false, false
  state.strat_scan_requested = false
  state.strat_scanner_active = false
  state.strat_scanner_used = false
  state.strat_stop_reported = false
  if n > 0 then report(('初始化：已恢复战备字段 %d 处'):format(n), true) end
end

local function strat_step()
  if rawget(_G, 'EXO_DISABLE_STRAT_SCAN') == true then return end
  if not (api and api.regions) then return end
  local c, x = pick_carry(), pick_extra()
  if not c then return end
  if x and x.id == c.id then x = nil end
  local pair = c.key .. '|' .. (x and x.key or 'none')
  if state.strat_pair ~= pair then
    restore_strat()
    state.strat_pair = pair
  end
  if not x then
    if next(state.strat_orig or {}) then restore_strat() end
    state.strat_ok = false
    state.strat_scan_requested = false
    return
  end
  for _, body in ipairs({ c, x }) do
    local a = state.strat_addr[body.key]
    if a and api.read(a + 8, 8) ~= body._icon_le then state.strat_addr[body.key] = nil end
  end
  -- ★ 优先路径：AOB 直取（Scanner 解出的战备表指针数组）。
  --   拿不到才轮到下面「全内存搜 package 值」的兜底；每 2 秒试一次，不每帧枚举。
  if not (state.strat_addr[c.key] and state.strat_addr[x.key]) then
    if rawget(_G, 'EXO_DISABLE_AOB') ~= true then
      local now = os.clock()
      if not state.strat_aob_at or now - state.strat_aob_at >= 2 then
        state.strat_aob_at = now
        strat_aob_fill(c, x)
      end
    end
  end
  if not state.strat_addr[c.key] then state.strat_addr[c.key] = strat_validate(c) end
  if not state.strat_addr[x.key] then state.strat_addr[x.key] = strat_validate(x) end  if state.strat_addr[c.key] and state.strat_addr[x.key] then
    local wa = strat_write_additional(c, x)
    local w1 = strat_write_use(c)
    local w2 = strat_write_use(x)
    state.strat_ok = true
    state.strat_scan_requested = false
    state.strat_done = true
    state.strat_hits, state.strat_regions = {}, nil
    if not state.strat_stop_reported then
      state.strat_stop_reported = true
      if wa or w1 or w2 then
        report('战备内容搜：目标已写入，扫描自动停止', true)
      else
        report('兜底内容搜：已定位目标，但写入未成功；扫描停止', true)
      end
    end
    return
  end
  if state.strat_scanner_active then return end
  if state.strat_scanner_used and state.strat_done then
    state.strat_scan_requested = false
    state.strat_hits, state.strat_regions = {}, nil
    if not state.strat_stop_reported then
      state.strat_stop_reported = true
      report('兜底全扫描：未找到目标记录，扫描停止（AOB 也没找到，可能需要更新签名）', true)
    end
    return
  end
  if state.strat_scanner_used then return end
  local auto = rawget(_G, 'EXO_AUTO_SCAN') == true
  if not (state.strat_scan_requested or auto) then return end
  if state.strat_done then
    state.strat_scan_requested = false
    state.strat_hits, state.strat_regions = {}, nil
    report('兜底内容搜：未找到目标记录，扫描停止（兜底与 AOB 都没找到，可能需要更新签名）', true)
    return
  end
  strat_scan_step()
end

local function start_strat_scan()
  state.strat_hits, state.strat_addr, state.strat_regions = {}, {}, nil
  state.strat_done, state.strat_ok, state.strat_next_at = false, false, nil
  state.strat_scan_requested, state.strat_stop_reported = false, false
  state.strat_scanner_active, state.strat_scanner_used = false, false
  local c, x = pick_carry(), pick_extra()
  if not (c and x and c.id ~= x.id) then
    report('全扫描：当前没有有效的携带/附加组合', true)
    return false
  end
  -- ★ AOB 优先：能直取就不扫内存（「全扫描只在别的路都走不通时才用」的落点）
  if rawget(_G, 'EXO_DISABLE_AOB') ~= true then
    state.strat_aob_at = os.clock()
    if strat_aob_fill(c, x) == 2 then
      report('定位：AOB 已直取两条记录，跳过全扫描', true)
      return true
    end
  end
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and type(S.scan_request) == 'function' then
    state.strat_scanner_active = true
    state.strat_scanner_used = true
    local ok, why = S.scan_request{
      id = 'exo_strat_pkg',
      patterns = { { key = c.key, bytes = c._pkg_le }, { key = x.key, bytes = x._pkg_le } },
      budget = 8 * 1024 * 1024,
      on_hit = function(key, addr)
        local hits = state.strat_hits[key]
        if not hits then hits = {} state.strat_hits[key] = hits end
        if #hits < 64 then hits[#hits + 1] = addr end
      end,
      on_done = function()
        state.strat_scanner_active = false
        state.strat_done = true
      end,
    }
    if ok then
      report('Scanner memscan：全扫描已启动', true)
      return true
    end
    state.strat_scanner_active, state.strat_scanner_used = false, false
    report('Scanner memscan 启动失败，回退自扫描: ' .. tostring(why), true)
  end
  state.strat_scan_requested = true
  report('EXO 自扫描：全扫描已启动', true)
  return true
end

-- ---------------------------------------------------------------- Scanner 前置（只用于手臂表）
local RACK_TYPE = 0x3845B1E0          -- MountComponentData

local function scanner_get()
  if SCAN.api then return SCAN.api end
  local now = os.clock()
  if now < SCAN.retry_at then return nil end
  SCAN.retry_at = now + 60
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and tonumber(S.version) == 1 and type(S.poll) == 'function' then
    SCAN.api = S
    if type(S.request) == 'function' then S.request(RACK_TYPE, 'EXO 战备自选') end
    report('已接上 HD2Scanner（前置）：MountComponentData 由 Scanner 提供', true)
    return S
  end
  if not SCAN.warned then
    SCAN.warned = true
    report('未发现 _G.HD2Scanner —— 手臂改造依赖 HD2 Scanner 前置（每 60 秒重试）', true)
  end
  return nil
end

-- ---------------------------------------------------------------- 每帧
local function frame()
  state.frame = state.frame + 1
  flush_log()

  -- 第一帧就把 Scanner 的 AOB 解析点起来：分帧后台跑，解析好就不用扫内存了
  if state.frame == 1 then
    local S0 = aob_api()
    if S0 then pcall(S0.strat_table_request) end
  end

  -- 「确认」的第 2 步：上一帧刚把 4 个槽位复位成原装，这一帧再覆盖成配置。
  -- 隔一帧是刻意的：同一帧连写两次同一地址，中间那次变化游戏根本看不到。
  if state.confirm_phase == 2 then
    state.confirm_phase = nil
    local n2 = apply_all('config')
    report(('确认：第 2 步（覆盖为配置）完成，处理 %d 份表'):format(n2), true)
    return
  end

  local ok3, err3 = pcall(strat_step)
  if not ok3 then
    state.errs = state.errs + 1
    if state.errs <= 5 then report('战备内容搜异常: ' .. tostring(err3)) end
  end

  if not scanner_get() then return end
  local n = apply_all('config')
  SCAN.applied = SCAN.applied + n
  if n > 0 then state.phase = 'armed' end
  if state.frame % 300 == 0 then recheck() end
end

-- ---------------------------------------------------------------- 菜单面板插件
-- ---------------------------------------------------------------- 可调项的 setter
-- choice 行的 set 收到的是**显示名字**（字符串），这里映射回 key / item。
local MOD_OPTIONS = { registered = false }
local BY_NAME = { ['无'] = 'none' }
for _, e in ipairs(EXO) do BY_NAME[e.name] = e.key end

-- 短名：行的标签里已经写了是哪台，值列只放臂件名（长了会撞备注列）

local function set_carry(name)
  local k = BY_NAME[name]
  if not k then return end
  restore_strat()
  CFG.carry = k
  if CFG.extra == k then                     -- 换了携带机体后不能与附加相同
    for _, e in ipairs(EXO) do
      if e.key ~= k then CFG.extra = e.key break end
    end
  end
  if MOD_OPTIONS.refresh_arm_values then pcall(MOD_OPTIONS.refresh_arm_values) end
  cfg_save()
  report(('cfg: carry=%s  extra=%s'):format(CFG.carry, CFG.extra), true)
end

local function set_extra(name)
  local k = BY_NAME[name]
  if not k then return end
  if k ~= 'none' and k == CFG.carry then return end  -- ★ 自引用：直接忽略（自检也会拦）
  restore_strat()
  CFG.extra = k
  if MOD_OPTIONS.refresh_arm_values then pcall(MOD_OPTIONS.refresh_arm_values) end
  cfg_save()
  report('cfg: extra=' .. k, true)
end

local function set_arm(body, slot, name)
  for _, it in ipairs(candidates(slot)) do
    if arm_name(it) == name then
      CFG.arms[body.key .. '.' .. slot] = it
      cfg_save()
      report(('cfg: %s.%s = %s'):format(body.key, slot, name), true)
      return
    end
  end
end

-- 初始化：cfg 回默认（携带=爱国者 / 附加=解放者 / 手臂全原装）
local function reset_cfg()
  CFG.carry, CFG.extra = 'patriot', DEFAULT_EXTRA
  CFG.arms = {}
  state.slots = {}
  cfg_save()
end

local function do_initialize()
  local S = rawget(_G, 'HD2Scanner')
  if S and type(S.scan_cancel) == 'function' then pcall(S.scan_cancel, 'exo_strat_pkg') end
  restore_strat()
  restore_arms_all()
  apply_all('vanilla', true)
  reset_cfg()
  state.strat_hits, state.strat_addr, state.strat_regions = {}, {}, nil
  state.strat_done, state.strat_ok = false, false
  state.strat_scan_requested, state.strat_scanner_active, state.strat_scanner_used = false, false, false
  state.strat_pair = nil
  state.strat_aob_at = nil
  if MOD_OPTIONS.refresh_arm_values then pcall(MOD_OPTIONS.refresh_arm_values) end
  report('初始化：已回默认配置并强制写回原装', true)
end

-- ---------------------------------------------------------------- ModOptionsMenu 适配
-- 存在 _G.ModOptionsMenu 时，把用户设置注册成原生 MODS 页选项。

local function register_mod_options()
  if MOD_OPTIONS.registered then return end
  local mom = rawget(_G, 'ModOptionsMenu')
  if type(mom) ~= 'table' or mom.api ~= 1 then return end
  MOD_OPTIONS.registered = true

  -- 左右手分池：左臂只出左件，右臂只出右件
  local side_items = { L = {}, R = {} }
  local side_seen = { L = {}, R = {} }
  local function add_side(slot, item)
    if item and not side_seen[slot][item] then
      side_seen[slot][item] = true
      side_items[slot][#side_items[slot] + 1] = { item = item, name = arm_name(item) }
    end
  end
  for _, e in ipairs(EXO) do
    add_side('L', e.left.item)
    add_side('R', e.right.item)
  end
  for _, list in pairs(EXTRA_ARMS) do
    for slot, arr in pairs(list) do
      for _, it in ipairs(arr) do add_side(slot, it) end
    end
  end
  for _, slot in ipairs({ 'L', 'R' }) do
    table.sort(side_items[slot], function(a, b)
      if a.name == b.name then return a.item < b.item end
      return a.name < b.name
    end)
  end
  MOD_OPTIONS.side_items = side_items
  local side_choices = { L = {}, R = {} }
  for _, slot in ipairs({ 'L', 'R' }) do
    for i, e in ipairs(side_items[slot]) do side_choices[slot][i] = e.name end
  end

  local function index_of_key(key)
    for i, e in ipairs(EXO) do if e.key == key then return i end end
    return 1
  end
  local function index_of_extra(key)
    if key == 'none' then return 1 end
    return 1 + index_of_key(key)
  end
  local function extra_key_of_index(i)
    i = tonumber(i) or 1
    if i <= 1 then return 'none' end
    local e = EXO[i - 1]
    return e and e.key or 'none'
  end
  MOD_OPTIONS.index_of_extra, MOD_OPTIONS.extra_key_of_index = index_of_extra, extra_key_of_index
  local function index_of_item(slot, item)
    for i, e in ipairs(side_items[slot] or {}) do
      if e.item == item then return i end
    end
    return 1
  end
  MOD_OPTIONS.index_of_key, MOD_OPTIONS.index_of_item = index_of_key, index_of_item

  local carry_id, extra_id = 'exo_loadout.carry', 'exo_loadout.extra'
  MOD_OPTIONS.carry_id, MOD_OPTIONS.extra_id = carry_id, extra_id
  local body_choices = {}
  for i, e in ipairs(EXO) do body_choices[i] = e.name end
  mom.register_option(carry_id, { type = 'choice', label = '携带机体', mod = 'EXO 战备自选',
    choices = body_choices, default = index_of_key(CFG.carry),
    description = '四选一。携带机体的战备附加槽会写入附加机体。' })
  local extra_choices = { '无' }
  for i, e in ipairs(EXO) do extra_choices[#extra_choices + 1] = e.name end
  mom.register_option(extra_id, { type = 'choice', label = '附加机体', mod = 'EXO 战备自选',
    choices = extra_choices, default = index_of_extra(CFG.extra),
    description = '可选无；选无时不写附加，并尽量恢复原值。选好后由 AOB 直取记录自动写入，不需要扫描。' })

  local function role_body(role)
    return (role == 'carry') and pick_carry() or pick_extra()
  end
  local function role_label(role)
    return (role == 'carry') and '携带机体' or '附加机体'
  end
  local ARM_IDS = {}
  for _, role in ipairs({ 'carry', 'extra' }) do
    for _, slot in ipairs({ 'L', 'R' }) do
      local id = 'exo_loadout.arm.' .. role .. '.' .. slot
      ARM_IDS[role .. '.' .. slot] = id
      local body = role_body(role)
      mom.register_option(id, { type = 'choice',
        label = role_label(role) .. ((slot == 'L') and ' 左臂' or ' 右臂'),
        mod = 'EXO 战备自选', choices = side_choices[slot],
        default = body and index_of_item(slot, arm_item(body, slot)) or 1,
        description = '左臂只列左件、右臂只列右件；只在当前携带两台之间互换，非法组合回退。' })
    end
  end
  MOD_OPTIONS.arm_ids = ARM_IDS

  local scan_id, reset_id = 'exo_loadout.scan_now', 'exo_loadout.reset'
  MOD_OPTIONS.scan_id, MOD_OPTIONS.reset_id = scan_id, reset_id
  -- description 是**函数**：MOM 每次开 ESC 菜单都会重算（mod_options_menu API v2）。
  -- 「灰字 = 不用点 / 亮起来 = 该点了」那套提示搬到这里，反正旧面板已退役。
  mom.register_option(scan_id, { type = 'toggle', label = '兜底：全内存扫描（正常不用点）',
    mod = 'EXO 战备自选', default = false,
    description = function()
      local ok, txt = pcall(function()
        local head, st = '当前定位方式：', nil
        if AOB.api then
          local ok2, s2 = pcall(AOB.api.strat_table_status)
          st = (ok2 and type(s2) == 'table') and s2 or nil
        end
        if not AOB.api then
          head = head .. '无 AOB（Scanner 缺失或版本太旧）→ 只有本开关能兜底'
        elseif st and st.state == 'ok' then
          head = head .. 'AOB 直取已就绪 —— 不需要点这个开关'
        else
          head = head .. 'AOB ' .. tostring(st and st.state or '?')
            .. (st and st.reason and ('（' .. tostring(st.reason) .. '）') or '')
            .. ' → 需要本开关兜底'
        end
        return head .. '\n\n正常情况下附加战备不需要扫描：Scanner 用 AOB 直取记录后自动写入。'
          .. '\n只有出现上面那种「需要兜底」的情况（或日志里 AOB 报错 / not-found）时，'
          .. '才点它退回旧的「全内存搜 package 值」（较慢，且仍需手动触发）。'
      end)
      if not ok or type(txt) ~= 'string' or txt == '' then return '战备定位状态读不出来（看 ExoLoadout.log）' end
      if #txt > 390 then txt = txt:sub(1, 390) end
      return txt
    end })
  mom.register_option(reset_id, { type = 'toggle', label = '初始化（原装 + 恢复战备字段 + CFG 复位）',
    mod = 'EXO 战备自选', default = false,
    description = '写回原装手臂、恢复附加/use 原值，并把 CFG 回默认。' })

  local function refresh_arm_values()
    local c, x = pick_carry(), pick_extra()
    for _, pair in ipairs({ { 'carry', c }, { 'extra', x } }) do
      local role, body = pair[1], pair[2]
      if body then
        for _, slot in ipairs({ 'L', 'R' }) do
          local id = ARM_IDS[role .. '.' .. slot]
          if id then mom.set(id, index_of_item(slot, arm_item(body, slot))) end
        end
      end
    end
  end
  MOD_OPTIONS.refresh_arm_values = refresh_arm_values

  local function sync_from_menu()
    local ci = tonumber(mom.get(carry_id)) or 1
    local xi = tonumber(mom.get(extra_id)) or index_of_extra(CFG.extra)
    local c = EXO[ci]
    local xk = extra_key_of_index(xi)
    if c then CFG.carry = c.key end
    if xk == 'none' then
      CFG.extra = 'none'
    elseif xk ~= CFG.carry then
      CFG.extra = xk
    else
      CFG.extra = 'none'
      mom.set(extra_id, 1)
    end
    for _, pair in ipairs({ { 'carry', pick_carry() }, { 'extra', pick_extra() } }) do
      local role, body = pair[1], pair[2]
      if body then
        for _, slot in ipairs({ 'L', 'R' }) do
          local id = ARM_IDS[role .. '.' .. slot]
          local v = id and tonumber(mom.get(id))
          local pick = v and (side_items[slot] or {})[v]
          if pick and is_candidate(slot, pick.item) then
            CFG.arms[body.key .. '.' .. slot] = pick.item
          else
            mom.set(id, index_of_item(slot, arm_item(body, slot)))
          end
        end
      end
    end
    state.recheck()
  end
  pcall(sync_from_menu)

  mom.on_change(carry_id, function(v)
    local e = EXO[tonumber(v) or 0]
    if not e then return end
    restore_strat()
    CFG.carry = e.key
    if CFG.extra == e.key then
      for _, o in ipairs(EXO) do if o.key ~= e.key then CFG.extra = o.key break end end
      mom.set(extra_id, index_of_extra(CFG.extra))
    end
    refresh_arm_values()
    cfg_save()
    state.recheck()
    report(('ModOptionsMenu: carry=%s extra=%s'):format(CFG.carry, CFG.extra), true)
  end)

  mom.on_change(extra_id, function(v)
    local xk = extra_key_of_index(v)
    if xk ~= 'none' and xk == CFG.carry then
      mom.set(extra_id, index_of_extra(CFG.extra))
      report('ModOptionsMenu: 附加机体不能等于携带机体，已回退', true)
      return
    end
    restore_strat()
    CFG.extra = xk
    refresh_arm_values()
    cfg_save()
    state.recheck()
    report('ModOptionsMenu: extra=' .. CFG.extra, true)
  end)

  for _, role in ipairs({ 'carry', 'extra' }) do
    for _, slot in ipairs({ 'L', 'R' }) do
      local id = ARM_IDS[role .. '.' .. slot]
      mom.on_change(id, function(v)
        local body = role_body(role)
        if not body then return end
        local pick = (side_items[slot] or {})[tonumber(v) or 0]
        if not pick then return end
        if not is_candidate(slot, pick.item) then
          mom.set(id, index_of_item(slot, arm_item(body, slot)))
          report(('ModOptionsMenu: %s %s 不在候选池，已回退'):format(short_name(body), slot), true)
          return
        end
        CFG.arms[body.key .. '.' .. slot] = pick.item
        cfg_save()
        report(('ModOptionsMenu: %s.%s = %s'):format(body.key, slot, pick.name), true)
      end)
    end
  end

  mom.on_change(scan_id, function(v)
    if not v then return end
    start_strat_scan()
    mom.set(scan_id, false)
  end)

  mom.on_change(reset_id, function(v)
    if not v then return end
    do_initialize()
    mom.set(carry_id, index_of_key(CFG.carry))
    mom.set(extra_id, index_of_extra(CFG.extra))
    refresh_arm_values()
    mom.set(reset_id, false)
  end)

  report('ModOptionsMenu: EXO 设置已注册到原生 MODS 页（左右手分池）', true)
end
-- ---------------------------------------------------------------- 挂载
local orig = update
if type(orig) == 'function' then
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
    return orig(...)
  end
end

report(('已加载 v%s（ModOptionsMenu 适配；HD2Menu 页面已退役）'):format(VERSION), true)
