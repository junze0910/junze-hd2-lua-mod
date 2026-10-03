-- HD2-Addon: mods/dsh/strat_diff

-- ===========================================================================
--  战备解锁 · 进程内内存差异探针（**只读**）
--
--  背景：外部 ReadProcessMemory 被 GameGuard 挡掉后，唯一能看清「外挂解锁时
--        到底写了哪些字节」的办法就是让 mod 在进程内自己 diff。
--        外挂特征：纯内存写、重启失效、不碰装备注册表、不碰玩家数据根对象。
--
--  三段式：
--     S0 拍基线 → 你跑外挂 → S1 拍快照 → 等几秒 → S2 稳定性复查
--        S0↔S1 = 变化页（外挂写入 + 游戏自身 churn）
--        S1↔S2 = 噪声页（churn 会反复变）
--        **稳定候选 = (S0≠S1) 且 (S1==S2)**  ← 外挂写入正是这个特征
--
--  实现：
--    · 全进程 4KB 页哈希；ffi 缓冲存 addr(u64)+hash(u32)，只留两代（滚动）
--      上限 3,000,000 页 ≈ 36 MB/代
--    · 分帧预算（SKILL 6.5：一次扫太多会把游戏饿死）
--    · 日志三件套：环形上限 400 / ×N 折叠 / 脏标志节流（SKILL 6.15）
--    · 地址是 Lua 双精度安全区（< 2^53）；哈希用 int32 位运算，不用 u64
--
--  红线：本文件**只读** —— 不出现任何写内存 / 改页保护 API 的名字（grep 守线）
-- ===========================================================================

local VERSION = '0.2'
local MOD = 'mods/dsh/strat_diff'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, phase = 'starting', scans = 0, errs = 0,
                  stable = {}, noisy = {}, cand = {} })
local state = rawget(_G, MOD)

-- ---------------------------------------------------------------- 日志
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
    local f = loader and loader.open_log and loader.open_log('StratDiff.log')
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
  print('[StratDiff] ' .. msg)
  loghist[#loghist + 1] = ('[frame %d] %s'):format(state.frame, msg)
  if #loghist > LOG_CAP then table.remove(loghist, 1) end
  log_dirty = true
  if keep then flush_log(true) end
end
report('StratDiff v' .. VERSION .. ' 开始加载…', true)
local function dump_log(name, text)
  pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local f = loader and loader.open_log and loader.open_log(name)
    if f then f:write(text); f:close() end
  end)
end

-- ---------------------------------------------------------------- ffi / kernel32
local ffi_ok, ffi = pcall(require, 'ffi')
if not ffi_ok or type(ffi) ~= 'table' or ffi.os ~= 'Windows' then
  report('ffi 不可用，探针退出', true) return
end
-- ⚠ 多个 addon 共用同一个 Lua 状态：ffi.cdef 重复声明不同签名会直接抛错，
--   而加载期抛错 = 连日志都写不出来（本 mod v0.1 就是这么静默死掉的）。
pcall(ffi.cdef, [[
  void  *GetCurrentProcess(void);
  int    ReadProcessMemory(void *, void *, void *, size_t, size_t *);
  size_t VirtualQuery(const void *, void *, size_t);
]])
local k = ffi.load('kernel32')
local self = k.GetCurrentProcess()
local okbit, bit = pcall(require, 'bit')

-- ---------------------------------------------------------------- 常量
local PAGE        = 4096
local CHUNK       = 1024 * 1024          -- 单次 ReadProcessMemory 上限
local CAP         = 3000000              -- 页上限
local BUDGET      = 8 * 1024 * 1024      -- 每帧扫描预算（8MB ≈ 0.3ms@60fps）
local MIN_REGION  = 4096

local buf, gA, gB, prev, cur
local function ensure_buffers()
  if buf then return true end
  local function alloc(n)
    buf = ffi.new('uint8_t[?]', CHUNK + 64)
    gA = { addr = ffi.new('uint64_t[?]', n), hash = ffi.new('uint32_t[?]', n), n = 0 }
    gB = { addr = ffi.new('uint64_t[?]', n), hash = ffi.new('uint32_t[?]', n), n = 0 }
  end
  local ok, err = pcall(alloc, CAP)
  if not ok then
    buf, gA, gB = nil, nil, nil
    CAP = 2000000
    ok, err = pcall(alloc, CAP)
  end
  if not ok then report('缓冲分配失败: ' .. tostring(err), true) return false end
  cur = gA
  report(('缓冲就绪：上限 %d 页 (约 %.0f MB)'):format(CAP, CAP * 12 / 1048576), true)
  return true
end

-- ---------------------------------------------------------------- 区域枚举
local function readable(pr)
  local p = pr % 256
  return p == 2 or p == 4 or p == 8 or p == 32 or p == 64 or p == 128
end
local function u32at(s, off)
  local a, b, c, d = s:byte(off + 1, off + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end
local function u64at(s, off)
  local lo, hi = u32at(s, off), u32at(s, off + 4)
  if not hi then return nil end
  return lo + hi * 4294967296
end
local function regions()
  local out, addr, guard = {}, 0, 0
  while guard < 300000 do
    guard = guard + 1
    local info = ffi.new('uint8_t[48]')
    if tonumber(k.VirtualQuery(ffi.cast('const void *', addr), info, 48)) ~= 48 then break end
    local s = ffi.string(info, 48)
    local b, sz, st, pr = u64at(s, 0), u64at(s, 24), u32at(s, 32), u32at(s, 36)
    if not (b and sz) or sz <= 0 then break end
    if st == 0x1000 and readable(pr) and sz >= MIN_REGION then
      out[#out + 1] = { base = b, size = sz }
    end
    local nxt = b + sz
    if nxt <= addr then break end
    addr = nxt
    if addr > 0x7FFFFFFFFFFF then break end
  end
  return out
end

-- ---------------------------------------------------------------- 哈希
local function hash_page(p, base)
  local h = 0
  if bit then
    for i = 0, PAGE / 4 - 1 do h = bit.bxor(bit.rol(h, 5), p[base + i]) end
  else
    for i = 0, PAGE / 4 - 1 do h = (h * 31 + p[base + i]) % 4294967296 end
  end
  return h
end

-- ---------------------------------------------------------------- 扫描状态机
local scan = { regs = nil, ri = 1, off = 0, pages = 0, bytes = 0, capped = false }
local function scan_begin(g)
  if not ensure_buffers() then return end
  scan.regs, scan.ri, scan.off = regions(), 1, 0
  scan.pages, scan.bytes, scan.capped = 0, 0, false
  g.n = 0
  cur = g
  report(('扫描开始：%d 个可读区域，预算 %.0f MB/帧'):format(#scan.regs, BUDGET / 1048576))
end
local function scan_step()
  if not scan.regs then return true end
  local budget = BUDGET
  local g = cur
  while budget > 0 and scan.ri <= #scan.regs do
    local r = scan.regs[scan.ri]
    if scan.off >= r.size then
      scan.ri, scan.off = scan.ri + 1, 0
    else
      local want = math.min(CHUNK, r.size - scan.off)
      local got = ffi.new('size_t[1]')
      if k.ReadProcessMemory(self, ffi.cast('const void *', r.base + scan.off), buf, want, got) ~= 0 then
        local n = math.floor(want / PAGE)
        local p = ffi.cast('uint32_t *', buf)
        for j = 0, n - 1 do
          if g.n >= CAP then scan.capped = true break end
          g.n = g.n + 1
          g.addr[g.n - 1] = r.base + scan.off + j * PAGE
          g.hash[g.n - 1] = hash_page(p, j * (PAGE / 4))
        end
        scan.bytes = scan.bytes + want
      end
      scan.off = scan.off + want
      budget = budget - want
      if scan.capped then break end
    end
  end
  if scan.ri > #scan.regs or scan.capped then
    scan.regs = nil
    state.scans = state.scans + 1
    report(('扫描#%d 完成：%d 页 / %.2f GB%s'):format(
      state.scans, g.n, scan.bytes / 1073741824, scan.capped and '  ★触顶' or ''), true)
    return true
  end
  return false
end

-- ---------------------------------------------------------------- 比对
local function compare(why)
  local a, b = prev, cur
  if not a or a.n == 0 or b.n == 0 then report('没有两代可比（先拍基线）', true) return {} end
  local changed, ia, ib = {}, 1, 1
  while ia <= a.n and ib <= b.n do
    local x, y = a.addr[ia - 1], b.addr[ib - 1]
    if x == y then
      if a.hash[ia - 1] ~= b.hash[ib - 1] then changed[#changed + 1] = x end
      ia, ib = ia + 1, ib + 1
    elseif x < y then ia = ia + 1
    else ib = ib + 1 end
  end
  report(('比对[%s]：A=%d 页 B=%d 页 → 变化 %d 页'):format(why, a.n, b.n, #changed), true)
  return changed
end

local function to_set(list)
  local s = {}
  for i = 1, #list do s[list[i]] = true end
  return s
end

-- ---------------------------------------------------------------- 导出候选页内容
local function dump_pages(list, name, limit)
  local out = {}
  local n = math.min(#list, limit or 40)
  for i = 1, n do
    local a = list[i]
    local got = ffi.new('size_t[1]')
    if k.ReadProcessMemory(self, ffi.cast('const void *', a), buf, PAGE, got) ~= 0 then
      out[#out + 1] = ('PAGE 0x%X'):format(a)
      local s = ffi.string(buf, PAGE)
      for row = 0, PAGE / 16 - 1 do
        local t = {}
        for c = 1, 16 do t[c] = ('%02X'):format(s:byte(row * 16 + c)) end
        out[#out + 1] = ('%04X: %s'):format(row * 16, table.concat(t, ' '))
      end
    else
      out[#out + 1] = ('PAGE 0x%X 读取失败'):format(a)
    end
  end
  dump_log(name, table.concat(out, '\n') .. '\n')
  report(('已导出 %d 页内容 -> %s'):format(n, name), true)
end

-- ---------------------------------------------------------------- 动作
local function act(fn)
  local ok, err = pcall(fn)
  if not ok then
    state.errs = state.errs + 1
    report('动作失败: ' .. tostring(err), true)
  end
end

-- ---------------------------------------------------------------- ModOptionsMenu
local MOMDONE = false
local function register_mod_options()
  if MOMDONE then return end
  local mom = rawget(_G, 'ModOptionsMenu')
  if type(mom) ~= 'table' or mom.api ~= 1 then return end
  MOMDONE = true
  local MID = '战备差异探针'
  local function opt(id, label, desc, fn)
    mom.register_option(id, { type = 'toggle', label = label, mod = MID,
      default = false, description = desc })
    mom.on_change(id, function(v)
      if not v then return end
      act(fn)
      pcall(mom.set, id, false)
    end)
  end
  opt('stratdiff.s0', '① 拍基线 S0',
      '全进程 4K 页哈希（分帧，约 10~20 秒）。拍完再去跑外挂。', function()
        prev = nil; scan_begin(gA)
      end)
  opt('stratdiff.s1', '② 拍快照 S1（跑完外挂后点）',
      '再哈希一遍并与 S0 比对，列出变化页数。', function()
        prev = gA; scan_begin(gB)
        state.after = 1
      end)
  opt('stratdiff.s2', '③ 稳定性复查 S2',
      '再哈希一遍与 S1 比对；「S0≠S1 且 S1==S2」的页 = 外挂写入的强候选，自动导出内容。',
      function()
        prev = gB; scan_begin(gA)
        state.after = 2
      end)
  opt('stratdiff.dump', '④ 导出当前候选页内容',
      '把已知的候选页内容 dump 到 StratDiffPages.log。', function()
        dump_pages(state.cand, 'StratDiffPages.log', 40)
      end)
  report('已注册 ModOptionsMenu（4 个开关）', true)
end

-- ---------------------------------------------------------------- 扫描结束后收尾
local function after_scan()
  if state.after == 1 then
    state.after = nil
    local ch = compare('S0->S1')
    state.raw = ch
    report(('S0->S1 变化 %d 页（含游戏 churn）。现在等 5~10 秒再点 ③'):format(#ch), true)
  elseif state.after == 2 then
    state.after = nil
    local ch2 = compare('S1->S2')
    local set2 = to_set(ch2)
    local stable = {}
    for _, a in ipairs(state.raw or {}) do
      if not set2[a] then stable[#stable + 1] = a end
    end
    state.cand = stable
    report(('★ 稳定候选 %d 页（S1->S2 又变的 %d 页已剔除）'):format(#stable, #ch2), true)
    for i = 1, math.min(#stable, 20) do report(('   候选页 0x%X'):format(stable[i])) end
    dump_pages(stable, 'StratDiffPages.log', 40)
  end
end

-- ---------------------------------------------------------------- Scanner 依赖说明
local function scanner_note()
  local S = rawget(_G, 'HD2Scanner')
  report(S and ('检测到 HD2Scanner v' .. tostring(S.version) .. '（本探针不依赖它，用自带 FFI）')
            or '未检测到 HD2Scanner（无硬前置，自带 FFI 路径）', true)
end

-- ---------------------------------------------------------------- update 钩子
local orig = rawget(_G, 'update')
local function tick()
  state.frame = state.frame + 1
  register_mod_options()
  if state.frame == 2 then scanner_note() end
  if scan.regs then
    local done = scan_step()
    if done then after_scan() end
  end
  flush_log(false)
end
if type(orig) == 'function' then
  rawset(_G, 'update', function(...) pcall(tick) return orig(...) end)
else
  rawset(_G, 'update', function(...) pcall(tick) end)
end
report('已加载 v' .. VERSION .. '：①拍基线 → 跑外挂 → ②拍快照 → 等几秒 → ③稳定性复查', true)
return state
