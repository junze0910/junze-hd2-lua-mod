-- HD2-Addon: mods/dsh/unlock_kit
-- ===========================================================================
--  Unlock Kit v0.6 —— 两件事（每项一个 MOM 开关，打开即写、关掉即还原）：
--    ① 武器：照 LAS22 切变 patch_0 —— 「克隆同类样板 + 只替换身份字段」
--    ② 战备：② StratagemInfo+0x80 bit1 + ③ 注册表记录 +0x14 = 2
--  ⚠ 历史：v0.1f~v0.5 曾尝试「武器配件（JAR-5 弹药）解锁」。
--     v0.5 的 22 笔写入虽全部成功，但**打开主宰（JAR-5）配装页会让游戏崩溃**；
--     用户于 2026-10-04 决定停线，v0.6 起**整块移除**，代码/结论留档在
--     hd2-mod/docs/UNLOCK-KIT-交接.md §10（勿再照 v0.4/v0.5 的升级树/槽7 思路继续）。
-- ===========================================================================
local VERSION = '0.6'
local MOD = 'mods/dsh/unlock_kit'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, writes = 0, errs = 0, undo = {}, status = nil })
local state = rawget(_G, MOD)

local DRY = false

-- 目标一：武器（模型哈希 + 同类样板）
local TARGETS = {
  { id = 'p41', name = 'P-41 巡察者（副武器）',
    hi = 3185701459, lo = 1115697165, tmpl_name = 'P-2 和平制造者',
    tmpl_hi = 98887106, tmpl_lo = 3681436834 },
  { id = 'g11', name = 'G-11 铁蒺藜（投掷物）',
    hi = 694738618, lo = 1835806473, tmpl_name = 'G-6 破片弹',
    tmpl_hi = 1290398391, tmpl_lo = 2242354043 },
}
-- 目标三：战备（配方 = ② StratagemInfo+0x80 bit1 + ③ 注册表记录 +0x14 = 2，实机验证过）
local STRATS = {
  { id = 5,   key = 0x651210DB, name = '轨道照明弹' },
  { id = 26,  key = 0x9D28D826, name = 'FRV 补给型（M-103）' },
  { id = 105, key = 0xEA902C4B, name = '快速侦察载具 FRV（M-102）' },
  { id = 135, key = 0xA9A97CD7, name = 'FRV 炽热型（M-104）' },
  { id = 146, key = 0xB2E060BB, name = '飞鹰·空空导弹（(NOT USED) 废弃条目）' },
  { id = 50,  key = 0x1B7853AC, name = '风暴漩涡（Maelstrom）' },
    -- key/记录号来自实机 dump：id=50 key=0x1B7853AC 记录#2927 type=10 state=1
}
local RVA_FUNC, SIG_FUNC = 0x136FC20, '\x48\x89\x5c\x24\x08\x48\x8b\xd9\x85\xd2\x75'
local RVA_LEA_DISP, RVA_LEA_INSN = 0x136FC3A, 0x136FC37

local RVA_ITEM_SLOT, RVA_CLASS_SLOT = 0x136FDF0, 0x11E7C65
local ROOT_COUNT, ROOT_RECS, ROOT_MAPS, ROOT_GATE = 0x1CE0, 0x1CE4, 0xB9CE4, 0xDDCF8
local REC_SIZE, MAP_SIZE, REG_CAP = 184, 24, 4096
local CLASS_BLOCK, CLASS_STRIDE = 0x1BA0, 32

-- ---------------------------------------------------------------- 日志
local loghist, dirty, at = {}, false, -10
local function flush(force)
  if #loghist == 0 then return end
  local now = os.clock()
  if not force and (not dirty or now - at < 1) then return end
  dirty, at = false, now
  pcall(function()
    local L = rawget(_G, 'CowboyBingusModLoader')
    local f = L and L.open_log and L.open_log('UnlockKit.log')
    if f then f:write(table.concat(loghist, '\n') .. '\n'); f:close() end
  end)
end
local function report(msg, keep)
  if msg == state.status then return end
  state.status = msg
  print('[UnlockKit] ' .. msg)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, msg)
  dirty = true
  if keep then flush(true) end
end

-- ---------------------------------------------------------------- ffi
local ffi_ok, ffi = pcall(require, 'ffi')
local api_ok, api = pcall(function()
  assert(ffi_ok and ffi, 'ffi unavailable')
  assert(ffi.abi('64bit'), 'x64 required')
  pcall(ffi.cdef, [[void *GetModuleHandleA(const char *);]])
  pcall(ffi.cdef, [[void *GetCurrentProcess(void);]])
  pcall(ffi.cdef, [[int ReadProcessMemory(void *, const void *, void *, size_t, size_t *);]])
  pcall(ffi.cdef, [[int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);]])
  pcall(ffi.cdef, [[size_t VirtualQuery(const void *, void *, size_t);]])
  local k = ffi.load('kernel32')
  local ghm, gcp, rpm, wpm, vq = k.GetModuleHandleA, k.GetCurrentProcess,
        k.ReadProcessMemory, k.WriteProcessMemory, k.VirtualQuery
  if not ghm then error('缺 GetModuleHandleA（cdef 冲突）') end
  if not gcp then error('缺 GetCurrentProcess（cdef 冲突）') end
  if not rpm then error('缺 ReadProcessMemory（cdef 冲突）') end
  if not wpm then error('缺 WriteProcessMemory（cdef 冲突）') end
  if not vq then error('缺 VirtualQuery（cdef 冲突）') end
  local proc = gcp()
  local M = { GetModuleHandleA = ghm }
  function M.read(address, size)
    if not address or address <= 0 or size <= 0 or size > 4 * 1024 * 1024 then return nil end
    local buf, got = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
    local ok = pcall(rpm, proc, ffi.cast('const void *', address), buf, size, got)
    if not ok or tonumber(got[0]) ~= size then return nil end
    return ffi.string(buf, size)
  end
  function M.write(address, bytes)
    local got = ffi.new('size_t[1]')
    return pcall(wpm, proc, ffi.cast('void *', address), ffi.cast('const void *', bytes),
                 #bytes, got) and tonumber(got[0]) == #bytes
  end
  function M.writable(address, size)
    local info = ffi.new('uint8_t[48]')
    if tonumber(vq(ffi.cast('const void *', address), info, 48)) ~= 48 then return false, 'VirtualQuery 失败' end
    local b = ffi.string(info, 48)
    local function u32o(off)
      local a, c, d, e = b:byte(off + 1, off + 4)
      return a + c * 256 + d * 65536 + e * 16777216
    end
    local function u64o(off) return u32o(off) + u32o(off + 4) * 4294967296 end
    local base, rsize, st, prot, kind = u64o(0), u64o(24), u32o(32), u32o(36), u32o(40)
    if not (address + size <= base + rsize) then return false, '跨越区域边界' end
    if st ~= 0x1000 or prot ~= 4 or kind ~= 0x20000 then
      return false, ('state=0x%X protect=0x%X type=0x%X'):format(st, prot, kind)
    end
    return true
  end
  return M
end)
if not api_ok then report('ffi/kernel32 不可用：' .. tostring(api), true) end

-- ---------------------------------------------------------------- 小工具
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
local function i32(s, off)
  local v = u32(s, off or 0)
  if not v then return nil end
  return v >= 0x80000000 and (v - 0x100000000) or v
end
local function le32(v)
  v = v % 4294967296
  return string.char(v % 256, math.floor(v / 256) % 256,
                     math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function replace32(s, off, v) return s:sub(1, off) .. le32(v) .. s:sub(off + 5) end
local function zeros(n) return string.rep('\0', n) end
local function hex(s)
  if type(s) ~= 'string' then return '?' end
  local t = {}
  for i = 1, #s do t[i] = ('%02X'):format(s:byte(i)) end
  return table.concat(t, ' ')
end
local function sane(v) return type(v) == 'number' and v > 0x10000 and v < 0x800000000000 end

-- ---------------------------------------------------------------- 定点定位
local IMG = { base = nil, slots = {} }
local function module_image()
  local h = api.GetModuleHandleA('game.dll')
  if h == nil then return nil end
  local base = tonumber(ffi.cast('uintptr_t', h))
  local head = api.read(base, 0x1000)
  if not head then return nil end
  local pe = u32(head, 0x3C)
  if not pe or pe <= 0 or pe > 0x800 then return nil end
  local size = u32(head, pe + 0x18 + 0x38)
  if not size or size <= 0 then return nil end
  return base, size
end
local function rip_target(rva, o1, o2, o3)
  local insn = api.read(IMG.base + rva, 7)
  if not insn or insn:byte(1) ~= o1 or insn:byte(2) ~= o2 or insn:byte(3) ~= o3 then
    return nil, ('RIP 指令不符 @0x%X（实得 %s）'):format(rva, hex(insn))
  end
  return IMG.base + rva + 7 + i32(insn, 3)
end
local function slot_addr(name, rva, o1, o2, o3)
  if IMG.slots[name] then return IMG.slots[name] end
  local a, why = rip_target(rva, o1, o2, o3)
  if not a then return nil, why end
  IMG.slots[name] = a
  return a
end
local function resolve()
  if not IMG.base then
    if not api_ok then return nil, 'ffi 不可用' end
    local base = module_image()
    if not base then return nil, 'game.dll 基址取不到' end
    IMG.base = base
  end
  return IMG
end

-- ---------------------------------------------------------------- 注册表 / class 表
local function registry()
  local A, why = resolve()
  if not A then return nil, why end
  local sa, e1 = slot_addr('item', RVA_ITEM_SLOT, 0x48, 0x8B, 0x05)
  if not sa then return nil, e1 end
  A.item_slot = sa
  local root = u64(api.read(sa, 8), 0)
  if not sane(root) then return nil, '注册表根指针为空' end
  local gate = u32(api.read(root + ROOT_GATE, 4), 0)
  if gate ~= 12 then return nil, ('注册表未就绪（门闸=%s，要 12）'):format(tostring(gate)) end
  local count = u32(api.read(root + ROOT_COUNT, 4), 0)
  if not count or count < 0 or count >= REG_CAP then return nil, ('count 异常 %s'):format(tostring(count)) end
  return { root = root, count = count }
end
local function class_key(hi, lo)
  local A, why = resolve()
  if not A then return nil, why end
  local sa, e = slot_addr('class', RVA_CLASS_SLOT, 0x48, 0x8B, 0x1D)
  if not sa then return nil, e end
  local classes = u64(api.read(sa, 8), 0)
  if not sane(classes) then return nil, 'class 表指针为空' end
  local blob = api.read(classes, CLASS_BLOCK)
  if not blob then return nil, 'class 表读不到' end
  for i = 0, math.floor(#blob / CLASS_STRIDE) - 1 do
    local off = i * CLASS_STRIDE
    if u32(blob, off) ~= 0 and u32(blob, off + 8) == lo and u32(blob, off + 12) == hi then
      return u32(blob, off), i
    end
  end
  return nil, ('class 表里没有 model=%d:%d（已扫 %d 条）'):format(hi, lo,
    math.floor(#blob / CLASS_STRIDE))
end
local function find_index(reg, key)
  local maps = api.read(reg.root + ROOT_MAPS, reg.count * MAP_SIZE)
  if not maps then return nil, '映射读不到' end
  for i = 0, reg.count - 1 do if u32(maps, i * MAP_SIZE + 8) == key then return i, '+8' end end
  for i = 0, reg.count - 1 do if u32(maps, i * MAP_SIZE + 4) == key then return i, '+4' end end
  return nil
end
local function record_at(reg, idx) return api.read(reg.root + ROOT_RECS + idx * REC_SIZE, REC_SIZE) end
local function map_addr(reg, idx) return reg.root + ROOT_MAPS + idx * MAP_SIZE end

local function write_bytes(addr, bytes, label)
  if DRY then report(('[只读] %s @0x%X：%s'):format(label, addr, hex(bytes)), true) return true end
  local ok, why = api.writable(addr, #bytes)
  if not ok then return false, ('页不可写（%s）'):format(tostring(why)) end
  local old = api.read(addr, #bytes)
  if not old then return false, '写前读不到' end
  if old == bytes then return true end
  if not api.write(addr, bytes) then return false, 'WriteProcessMemory 失败' end
  if api.read(addr, #bytes) ~= bytes then return false, '回读校验失败' end
  return true
end

-- ---------------------------------------------------------------- ③ 战备：+0x80 bit1 + 注册表 +0x14
-- 战备按 id 指针表：Scanner（v0.8+）优先；没有则读判定函数里那条 lea 的 disp32 现算
local function strat_table()
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and type(S.strat_table_request) == 'function'
     and type(S.strat_table_status) == 'function' and type(S.strat_table_base) == 'function' then
    pcall(S.strat_table_request)
    local st = S.strat_table_status() or {}
    if st.state == 'ok' then
      local b = S.strat_table_base()
      if sane(b) then return b, 'SCANNER' end
    end
    return nil, ('Scanner 战备表未就绪（state=%s）'):format(tostring(st.state))
  end
  local sig = api.read(IMG.base + RVA_FUNC, #SIG_FUNC)
  if sig ~= SIG_FUNC then return nil, ('兜底签名不符（%s）'):format(hex(sig)) end
  local db = i32(api.read(IMG.base + RVA_LEA_DISP, 4), 0)
  if not db then return nil, 'lea disp32 读不到' end
  local tbl = IMG.base + RVA_LEA_INSN + 7 + db
  if not sane(tbl) then return nil, ('战备表越界 0x%X'):format(tbl) end
  return tbl, 'FUNC-LEA'
end

local function unlock_strat(t, reg)
  local label = ('战备 %s（ID%d）'):format(t.name, t.id)
  local A, why0 = resolve()
  if not A then report(('%s：%s'):format(label, tostring(why0))) return false end
  local tbl, why = strat_table()
  if not tbl then report(('%s：战备表不可用（%s）'):format(label, tostring(why))) return false end
  local rp = u64(api.read(tbl + t.id * 8, 8), 0)
  if not sane(rp) then report(('%s：按 id 表里槽为空'):format(label)) return false end
  local info = api.read(rp, 0xD0)
  if not info then report(('%s：StratagemInfo 读不到'):format(label)) return false end
  local uses, namep = i32(info, 0x50), u64(info, 0x10)
  if uses == nil or not (namep and sane(namep)) then
    report(('%s：字段不合理（uses=%s name_ptr=%s）→ 拒写'):format(
      label, tostring(uses), tostring(namep)))
    return false
  end
  local undo = {}
  -- ② 选择位 +0x80 bit1
  local bit_addr = rp + 0x80
  local ob = api.read(bit_addr, 1)
  if not ob then report(label .. '：选择位读不到') return false end
  if math.floor(ob:byte(1) / 2) % 2 == 0 then
    local ok, e = write_bytes(bit_addr, string.char(ob:byte(1) + 2), label .. ' 选择位')
    if not ok then report(('%s：写选择位失败：%s'):format(label, tostring(e))) return false end
    undo[#undo + 1] = { kind = 'byte', off = bit_addr, old = ob }
    report(('★ %s：选择位 +0x80 0x%02X → 0x%02X（回读通过）'):format(label, ob:byte(1), ob:byte(1) + 2))
  else
    report(('%s：选择位已是开的（+0x80=0x%02X）'):format(label, ob:byte(1)))
  end
  -- ③ 注册表记录 +0x14 = 2
  local idx = find_index(reg, t.key)
  if not idx then
    report(('%s：注册表里查不到 key=0x%08X'):format(label, t.key))
  else
    local addr = reg.root + ROOT_RECS + idx * REC_SIZE + 0x14
    local old = api.read(addr, 4)
    if not old then
      report(label .. '：状态读不到')
    elseif u32(old, 0) == 2 or u32(old, 0) == 4 then
      report(('%s：记录#%d +0x14 已是 %s（跳过）'):format(label, idx, tostring(u32(old, 0))))
    else
      local ok, e = write_bytes(addr, le32(2), label .. ' 状态')
      if ok then
        undo[#undo + 1] = { kind = 'u32', off = addr, old = u32(old, 0) }
        report(('★ %s：记录#%d +0x14 %s → 2（回读通过）'):format(label, idx, tostring(u32(old, 0))))
      else
        report(('%s：写状态失败：%s'):format(label, tostring(e)))
      end
    end
  end
  if not DRY and #undo > 0 then
    state.undo[#state.undo + 1] = { id = 'strat' .. t.id, kind = 'strat', entries = undo }
    state.writes = state.writes + 1
  end
  return #undo > 0
end

local function revert_strat(t)
  local item
  for i = #state.undo, 1, -1 do
    if state.undo[i].id == 'strat' .. t.id then item = state.undo[i] table.remove(state.undo, i) break end
  end
  if not item then report(('战备 %s：没有可还原的记录'):format(t.name)) return end
  if DRY then report('[只读] 跳过还原') return end
  local n = 0
  for i = #item.entries, 1, -1 do
    local e = item.entries[i]
    if e.kind == 'byte' then
      write_bytes(e.off, e.old, '还原选择位')
    else
      write_bytes(e.off, le32(e.old), '还原状态')
    end
    n = n + 1
  end
  report(('战备 %s：已还原 %d 笔'):format(t.name, n), true)
end

-- ---------------------------------------------------------------- ① 武器：克隆 + 只替换身份
local function unlock_weapon(t, reg)
  local label = t.name
  local key, why = class_key(t.hi, t.lo)
  if not key then report(('%s：拿不到游戏自己的 key —— %s'):format(label, tostring(why))) return false end
  local idx, field = find_index(reg, key)
  if idx then
    report(('%s：key=0x%08X 已在注册表里（下标 %d，按 %s）→ 不适用，跳过'):format(label, key, idx, field))
    return false
  end
  local tkey, twhy = class_key(t.tmpl_hi, t.tmpl_lo)
  if not tkey then report(('%s：样板 key 拿不到 —— %s'):format(label, tostring(twhy))) return false end
  local tidx = find_index(reg, tkey)
  if not tidx then report(('%s：样板 %s 不在注册表里'):format(label, t.tmpl_name)) return false end
  local trec, tmap = record_at(reg, tidx), api.read(map_addr(reg, tidx), MAP_SIZE)
  if not trec or not tmap then report(label .. '：样板记录/映射读不到') return false end
  local n = reg.count
  if n >= REG_CAP then report(('%s：注册表已满'):format(label)) return false end
  local r_addr, m_addr = reg.root + ROOT_RECS + n * REC_SIZE, map_addr(reg, n)
  local rec_old, map_old = api.read(r_addr, REC_SIZE), api.read(m_addr, MAP_SIZE)
  if not rec_old or not map_old then report(label .. '：追加位读不到') return false end
  if rec_old ~= zeros(REC_SIZE) or map_old ~= zeros(MAP_SIZE) then
    report(('%s：追加位 #%d 不是空的 → 拒绝'):format(label, n)) return false
  end
  local new_rec = replace32(replace32(replace32(trec, 0, n), 4, key), 8, key)
  local new_map = replace32(replace32(replace32(tmap, 0, n), 4, key), 8, key)
  report(('★ %s：克隆样板 %s（下标 %d，key=0x%08X）→ 追加到 #%d（key=0x%08X）'):format(
    label, t.tmpl_name, tidx, tkey, n, key), true)
  local ok1, e1 = write_bytes(r_addr, new_rec, label .. ' 记录')
  if not ok1 then report(('%s：写记录失败：%s'):format(label, tostring(e1))) return false end
  local ok2, e2 = write_bytes(m_addr, new_map, label .. ' 映射')
  if not ok2 then
    if not DRY then write_bytes(r_addr, rec_old, label .. ' 回滚记录') end
    report(('%s：写映射失败：%s（已回滚）'):format(label, tostring(e2))) return false
  end
  local c_addr = reg.root + ROOT_COUNT
  local ok3, e3 = write_bytes(c_addr, le32(n + 1), label .. ' count')
  if not ok3 then
    if not DRY then
      write_bytes(m_addr, map_old, label .. ' 回滚映射')
      write_bytes(r_addr, rec_old, label .. ' 回滚记录')
    end
    report(('%s：发布 count 失败：%s（已回滚）'):format(label, tostring(e3))) return false
  end
  if not DRY then
    state.undo[#state.undo + 1] = { id = t.id, kind = 'weapon', rec_addr = r_addr,
                                    map_addr = m_addr, count_addr = c_addr, n = n }
    state.writes = state.writes + 1
  end
  report(('%s：追加完成 count %d → %d（回读通过）'):format(label, n, n + 1), true)
  return true
end

-- ---------------------------------------------------------------- 只读侦察
local function recon()
  local reg, why = registry()
  if not reg then report('侦察：' .. tostring(why), true) return end
  report(('侦察：root=0x%X count=%d'):format(reg.root, reg.count), true)
  for _, t in ipairs(TARGETS) do
    local key = class_key(t.hi, t.lo)
    local idx = key and find_index(reg, key)
    report(('  %s：%s'):format(t.name,
      key and ((idx and ('已在注册表下标 %d'):format(idx) or ('key=0x%08X，未登记'):format(key))
              or 'class 表查不到')))
    local tkey = class_key(t.tmpl_hi, t.tmpl_lo)
    local tidx = tkey and find_index(reg, tkey)
    report(('      样板 %s：%s'):format(t.tmpl_name,
      tkey and (tidx and ('下标 %d（key=0x%08X）'):format(tidx, tkey) or '注册表里查不到')
              or 'class 表查不到'))
  end
  local tbl, twhy = strat_table()
  if tbl then
    local S = rawget(_G, 'HD2Scanner')
    for _, t in ipairs(STRATS) do
      local rp = S and select(1, S.strat_slot and S.strat_slot(t.id)) or u64(api.read(tbl + t.id * 8, 8), 0)
      local idx = find_index(reg, t.key)
      local line = ('  战备 %-28s ID%-4d key=0x%08X'):format(t.name, t.id, t.key)
      line = line .. (idx and ('，注册表下标 %d'):format(idx) or '，注册表里查不到')
      if sane(rp) then
        local b = api.read(rp + 0x80, 1)
        line = line .. (b and ('，+0x80=0x%02X'):format(b:byte(1)) or '，+0x80 读不到')
      else
        line = line .. '，按 id 表槽为空'
      end
      report(line)
    end
  else
    report('  战备表不可用：' .. tostring(twhy))
  end
  report(('  追加位 = count = %d'):format(reg.count))
end

-- ---------------------------------------------------------------- 开局自动套用 + 轻量复核
-- ⚠ 注册表是**每局重建**的：MOM 只记住"这个开关是开的"，但内存里的写入不会留下。
--    所以每次开局（注册表就绪后）必须把打开过的开关重写一遍，之后每 5 秒轻量复核一次。
local MOMDONE = false
local function mom_get(id)
  local m = rawget(_G, 'ModOptionsMenu')
  if m and type(m.get) == 'function' then
    local ok, v = pcall(m.get, id)
    if ok then return v end
  end
  return nil
end

local applied_once, verify_at = false, 0
local function auto_and_verify()
  local reg, why = registry()
  if not reg then
    if not applied_once and state.frame % 300 == 0 then
      report('等注册表就绪（' .. tostring(why) .. '）')
    end
    return
  end
  local now = os.clock()
  -- 开局套用（只做一次）
  if not applied_once then
    applied_once = true
    local n = 0
    for _, t in ipairs(TARGETS) do
      if mom_get('unlock_kit.' .. t.id) then
        local key = class_key(t.hi, t.lo)
        if key and not find_index(reg, key) then
          report(('自动套用：%s'):format(t.name))
          if unlock_weapon(t, reg) then n = n + 1 end
        end
      end
    end
    for _, t in ipairs(STRATS) do
      if mom_get('unlock_kit.strat' .. t.id) then
        report(('自动套用：战备 %s（ID%d）'):format(t.name, t.id))
        unlock_strat(t, reg)
      end
    end
    report(('开局套用完成：%d 个开关是打开的'):format(n), true)
    verify_at = now + 5
    return
  end
  -- 轻量复核（每 5 秒）：只回看"打开过的"，被改回就重写
  if now < verify_at then return end
  verify_at = now + 5
  local redone = 0
  for _, t in ipairs(TARGETS) do
    local id = 'unlock_kit.' .. t.id
    if mom_get(id) then
      local key = class_key(t.hi, t.lo)
      if key then
        local idx = find_index(reg, key)
        local ok = false
        if idx then
          -- 追加过 → 条目在（复核只确认还在）
          ok = true
        else
          local item
          for i = #state.undo, 1, -1 do
            if state.undo[i].id == t.id then item = state.undo[i] break end
          end
          if item then
            report(('%s：条目不见了 → 重写'):format(t.name))
            ok = unlock_weapon(t, reg)
          else
            ok = unlock_weapon(t, reg)
          end
        end
        if ok then redone = redone + 1 end
      end
    end
  end
  for _, t in ipairs(STRATS) do
    if mom_get('unlock_kit.strat' .. t.id) then
      local idx = find_index(reg, t.key)
      if idx then
        local st = u32(api.read(reg.root + ROOT_RECS + idx * REC_SIZE + 0x14, 4), 0)
        if st and st ~= 2 and st ~= 4 then
          report(('战备 %s：记录被改回 %s → 重写'):format(t.name, tostring(st)))
          unlock_strat(t, reg)
        end
      end
    end
  end
  if redone > 0 and redone > 0 then end
end

-- ---------------------------------------------------------------- MOM
local function mom() return rawget(_G, 'ModOptionsMenu') end
local function register_mom()
  if MOMDONE then return end
  local m = mom()
  if type(m) ~= 'table' or type(m.register_option) ~= 'function' then return end
  MOMDONE = true
  local function on(id, fn)
    if type(m.on_change) == 'function' then pcall(m.on_change, id, fn) end
  end
  for _, t in ipairs(TARGETS) do
    pcall(m.register_option, 'unlock_kit.' .. t.id, {
      type = 'toggle', label = '解锁 ' .. t.name, mod = '解锁台', default = false,
      description = ('克隆样板 %s，只替换身份字段；关掉即还原'):format(t.tmpl_name) })
    on('unlock_kit.' .. t.id, function(v)
      local ok, err = pcall(function()
        local reg, why = registry()
        if not reg then report(('%s：%s'):format(t.name, tostring(why)), true) return end
        if v then unlock_weapon(t, reg) else
          local item
          for i = #state.undo, 1, -1 do
            if state.undo[i].id == t.id then item = state.undo[i] table.remove(state.undo, i) break end
          end
          if item and not DRY then
            write_bytes(item.count_addr, le32(item.n), t.name .. ' 还原 count')
            write_bytes(item.map_addr, zeros(MAP_SIZE), t.name .. ' 还原映射')
            write_bytes(item.rec_addr, zeros(REC_SIZE), t.name .. ' 还原记录')
            report(('%s：已还原（count 回 %d）'):format(t.name, item.n), true)
          end
        end
      end)
      if not ok then state.errs = state.errs + 1 report('开关异常: ' .. tostring(err), true) end
    end)
  end
  for _, t in ipairs(STRATS) do
    local id = 'unlock_kit.strat' .. t.id
    pcall(m.register_option, id, {
      type = 'toggle', label = ('解锁战备 %s（ID%d）'):format(t.name, t.id), mod = '解锁台',
      default = false,
      description = '② StratagemInfo +0x80 bit1 + ③ 注册表记录 +0x14 = 2（实机验证过的配方）；关掉即还原' })
    on(id, function(v)
      local ok, err = pcall(function()
        local reg, why = registry()
        if not reg then report(('%s：%s'):format(t.name, tostring(why)), true) return end
        if v then unlock_strat(t, reg) else revert_strat(t) end
      end)
      if not ok then state.errs = state.errs + 1 report('开关异常: ' .. tostring(err), true) end
    end)
  end
  pcall(m.register_option, 'unlock_kit.recon', {
    type = 'toggle', label = '● 侦察（只读）', mod = '解锁台', default = false,
    description = '打印每个目标的 key / 是否已登记 / 样板下标 / 战备记录与选择位；只读，不写字节' })
  on('unlock_kit.recon', function(v)
    if not v then return end
    pcall(recon)
    if type(m.set) == 'function' then pcall(m.set, 'unlock_kit.recon', false) end
  end)
  report(('已注册 ModOptionsMenu：%d 把武器 + %d 条战备 + 1 个侦察'):format(
    #TARGETS, #STRATS), true)
end

-- ---------------------------------------------------------------- 挂载
local orig = rawget(_G, 'update')
local function tick()
  state.frame = state.frame + 1
  if state.frame == 2 or (state.frame % 120 == 0 and not MOMDONE) then register_mom() end
  if state.frame >= 5 then
    local ok, err = pcall(auto_and_verify)
    if not ok then
      state.errs = state.errs + 1
      if state.errs <= 5 then report('自动套用/复核异常: ' .. tostring(err), true) end
    end
  end
  flush(false)
end
if type(orig) == 'function' then
  rawset(_G, 'update', function(...) pcall(tick) return orig(...) end)
else
  rawset(_G, 'update', function(...) pcall(tick) end)
end
report(('Unlock Kit v%s 已加载：%d 把武器（克隆+换身份）+ %d 条战备'):format(VERSION, #TARGETS, #STRATS), true)
return state
