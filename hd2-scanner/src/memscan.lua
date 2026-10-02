-- HD2 Scanner / memscan —— 通用全量内存扫描服务
-- 资源名: mods/junze/hd2_scanner/memscan   （不带 -- HD2-Addon 头，不被 loader 单独发现）
--
-- 对外只暴露 request / cancel / status / frame；Scanner 入口把前三个挂到 _G.HD2Scanner。
-- 每个请求:
--   { id=..., patterns={ {key=..., bytes=...}, ... }, budget=..., on_hit=..., on_done=... }
-- 扫描在 Scanner 的 frame 循环里分片推进，默认 8 MB/帧。
local M = {}

function M.new(ctx)
  local P, log = ctx.P, ctx.log
  local U = ctx.platform
  local ffi, kernel, PROC = U.ffi, U.kernel, U.PROC
  if not (ffi and kernel and PROC) then return nil end

  pcall(ffi.cdef, [[
    size_t VirtualQuery(const void *address, void *mbi, size_t len);
  ]])
  local mbi = ffi.new('uint8_t[48]')
  local RBUF_CAP = 262144 + 64
  local RBUF = ffi.new('uint8_t[?]', RBUF_CAP)
  local RGOT = ffi.new('size_t[1]')
  local LIMIT = 0x0000800000000000
  local CHUNK = 262144
  local DEFAULT_BUDGET = 8 * 1024 * 1024
  local MAX_HITS = 64

  local S = { running = nil, queue = {}, last = nil }

  local function read_at(addr, n)
    if not n or n <= 0 or n > RBUF_CAP then return nil end
    RGOT[0] = 0
    local ok = pcall(kernel.ReadProcessMemory, PROC,
                     ffi.cast('const void *', addr), RBUF, n, RGOT)
    if not ok or tonumber(RGOT[0]) ~= n then return nil end
    return ffi.string(RBUF, n)
  end

  local function regions()
    local out, addr = {}, 0x10000
    while addr < LIMIT do
      if kernel.VirtualQuery(ffi.cast('const void *', addr), mbi, 48) == 0 then break end
      local base = tonumber(ffi.cast('uint64_t *', mbi)[0])
      local size = tonumber(ffi.cast('uint64_t *', mbi)[3])
      local st   = tonumber(ffi.cast('uint32_t *', mbi + 32)[0])
      local prot = tonumber(ffi.cast('uint32_t *', mbi + 36)[0])
      if not base or not size or size <= 0 then break end
      local readable = (prot == 0x02 or prot == 0x04 or prot == 0x08 or
                        prot == 0x20 or prot == 0x40 or prot == 0x80)
      if st == 0x1000 and readable then
        out[#out + 1] = { base = base, size = size }
      end
      addr = base + size
    end
    table.sort(out, function(a, b) return a.size > b.size end)
    return out
  end

  local function self_addrs(req)
    local list = {}
    for _, p in ipairs(req.patterns) do
      local a = tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', p.bytes)))
      if a and a ~= 0 then list[#list + 1] = a end
    end
    return list
  end

  local function is_self_hit(list, a)
    for i = 1, #list do
      local d = a - list[i]
      if d > -4096 and d < 4096 then return true end
    end
    return false
  end

  local function validate(req)
    if type(req) ~= 'table' or type(req.id) ~= 'string' or req.id == '' then
      return false, 'bad id'
    end
    if type(req.patterns) ~= 'table' or #req.patterns == 0 then
      return false, 'bad patterns'
    end
    for _, p in ipairs(req.patterns) do
      if type(p) ~= 'table' or p.key == nil or type(p.bytes) ~= 'string' then
        return false, 'bad pattern entry'
      end
      local n = #p.bytes
      if n < 1 or n > 64 then return false, 'pattern size out of range' end
    end
    if req.on_hit ~= nil and type(req.on_hit) ~= 'function' then return false, 'bad on_hit' end
    if req.on_done ~= nil and type(req.on_done) ~= 'function' then return false, 'bad on_done' end
    return true
  end

  local function begin(req)
    local regs = regions()
    local maxlen = 1
    for _, p in ipairs(req.patterns) do
      if #p.bytes > maxlen then maxlen = #p.bytes end
    end
    S.running = {
      req = req, regions = regs, ri = 1, off = 0, scanned = 0,
      hits = {}, seen = {}, maxover = maxlen - 1, self = self_addrs(req),
    }
    log(('memscan: start id=%s regions=%d patterns=%d')
        :format(req.id, #regs, #req.patterns))
  end

  local function finish(hits)
    local req = S.running.req
    local scanned = S.running.scanned
    S.last = { id = req.id, hits = hits, scanned = scanned }
    S.running = nil
    if type(req.on_done) == 'function' then pcall(req.on_done, hits) end
    log(('memscan: done id=%s scanned=%.1fMB')
        :format(req.id, scanned / 1048576))
  end

  local function frame()
    if not S.running then
      local req = table.remove(S.queue, 1)
      if req then begin(req) end
      return
    end
    local r = S.running
    local budget = tonumber(r.req.budget) or DEFAULT_BUDGET
    if budget <= 0 then budget = DEFAULT_BUDGET end
    while budget > 0 and r.ri <= #r.regions do
      local reg = r.regions[r.ri]
      if r.off >= reg.size then
        r.ri, r.off = r.ri + 1, 0
      else
        local n = math.min(CHUNK, reg.size - r.off)
        local want = n
        if r.off + n + r.maxover <= reg.size then want = n + r.maxover end
        local buf = read_at(reg.base + r.off, want)
        if buf then
          r.scanned = r.scanned + n
          for _, p in ipairs(r.req.patterns) do
            local from = 1
            while true do
              local pos = buf:find(p.bytes, from, true)
              if not pos then break end
              from = pos + 1
              local abs = reg.base + r.off + pos - 1
              if not is_self_hit(r.self, abs) then
                local seen = r.seen[p.key]
                if not seen then seen = {} r.seen[p.key] = seen end
                if not seen[abs] then
                  local list = r.hits[p.key]
                  if not list then list = {} r.hits[p.key] = list end
                  if #list < MAX_HITS then
                    seen[abs] = true
                    list[#list + 1] = abs
                    if type(r.req.on_hit) == 'function' then
                      pcall(r.req.on_hit, p.key, abs)
                    end
                  end
                end
              end
            end
          end
        end
        r.off = r.off + n
        budget = budget - n
      end
    end
    if r.ri > #r.regions then finish(r.hits) end
  end

  return {
    request = function(req)
      local ok, why = validate(req)
      if not ok then return false, why end
      if S.running then
        for _, q in ipairs(S.queue) do
          if q.id == req.id then return false, 'duplicate queued id' end
        end
        S.queue[#S.queue + 1] = req
      else
        begin(req)
      end
      return true
    end,
    cancel = function(id)
      if S.running and S.running.req.id == id then
        local req = S.running.req
        S.running = nil
        if type(req.on_done) == 'function' then pcall(req.on_done, { cancelled = true }) end
        return true
      end
      for i, q in ipairs(S.queue) do
        if q.id == id then table.remove(S.queue, i); return true end
      end
      return false
    end,
    status = function(id)
      if S.running and S.running.req.id == id then return 'running' end
      for _, q in ipairs(S.queue) do if q.id == id then return 'queued' end end
      if S.last and S.last.id == id then return 'done' end
      return 'idle'
    end,
    frame = frame,
  }
end

return M
