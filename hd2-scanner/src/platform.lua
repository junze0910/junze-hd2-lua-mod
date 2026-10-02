-- HD2 Scanner / platform —— ffi、kernel32、内存读写、日志、二进制小工具、game.dll 句柄
-- 资源名: mods/junze/hd2_scanner/platform   （不带 -- HD2-Addon 头，不被 loader 发现）
local M = {}

function M.new(ctx)
    local loader, P = ctx.loader, ctx.P     -- P 用于日志抬头；漏了它会让 log_flush 每次都抛错

    -- ---------------------------------------------------------------------------
    -- 2. 平台层
    -- ---------------------------------------------------------------------------
    local ffi_ok, ffi = pcall(require, 'ffi')
    if not ffi_ok then ffi = nil end
    local kernel
    if ffi then
        pcall(ffi.cdef, [[
            int CreateDirectoryA(const char *path, void *security);
            uint32_t GetLastError(void);
            int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
            int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
            void *GetModuleHandleA(const char *name);
            void *GetCurrentProcess(void);
        ]])
        local ok, h = pcall(ffi.load, 'kernel32')
        if ok then kernel = h end
    end
    local PROC = kernel and kernel.GetCurrentProcess() or nil

    local function mkdir_rel(base, parts)
        if not (kernel and base) then return nil end
        local path = base
        for _, part in ipairs(parts) do
            path = path .. '/' .. part
            if kernel.CreateDirectoryA(path, nil) == 0 then
                if kernel.GetLastError() ~= 183 then return nil end
            end
        end
        return path
    end

    local BASE
    if loader and type(loader.log_directory) == 'string' then
        BASE = loader.log_directory:gsub('[/\\]Logs$', '')
    end
    BASE = BASE or ((os.getenv('LOCALAPPDATA') or os.getenv('TEMP') or '.')
                    .. '/CowboyBingus/Helldivers2')

    -- 安全的任意地址读（走 ReadProcessMemory，坏地址返回 nil 而不是崩游戏）
    local function mem_read(addr, size)
        if not (kernel and PROC and ffi) or not addr or addr <= 0 then return nil end
        local buf, got = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
        local ok = pcall(function()
            return kernel.ReadProcessMemory(PROC, ffi.cast('const void *', addr), buf, size, got)
        end)
        if not ok then return nil end
        if ok and tonumber(got[0]) ~= size then return nil end
        return ffi.string(buf, size)
    end

    local function mem_write(addr, data)
        if not (kernel and PROC and ffi) then return false end
        local got = ffi.new('size_t[1]')
        local ok = pcall(function()
            return kernel.WriteProcessMemory(PROC, ffi.cast('void *', addr), data, #data, got)
        end)
        return ok and tonumber(got[0]) == #data
    end

    -- 热路径：复用一块 8 字节暂存，每帧不再 ffi.new 分配
    local RBUF = ffi and ffi.new('uint8_t[8]') or nil
    local RGOT = ffi and ffi.new('size_t[1]') or nil
    local function raw_read(addr, size)
        if not (kernel and PROC and RBUF) or not addr or addr <= 0 then return nil end
        RGOT[0] = 0
        local ok = pcall(kernel.ReadProcessMemory, PROC, ffi.cast('const void *', addr), RBUF, size, RGOT)
        if ok and tonumber(RGOT[0]) == size then return RBUF end
        return nil
    end
    local function rd_u32(addr)
        local b = raw_read(addr, 4); if not b then return nil end
        return b[0] + b[1]*256 + b[2]*65536 + b[3]*16777216
    end
    local function rd_u64(addr)
        local b = raw_read(addr, 8); if not b then return nil end
        local lo = b[0] + b[1]*256 + b[2]*65536 + b[3]*16777216
        local hi = b[4] + b[5]*256 + b[6]*65536 + b[7]*16777216
        return hi * 4294967296 + lo
    end

    -- ---------------------------------------------------------------------------
    -- 3. 日志（缓冲 + 限流）
    -- ---------------------------------------------------------------------------
    local LOGDIR  = mkdir_rel(BASE, {'Logs'}) or (BASE .. '/Logs')
    local LOGFILE = LOGDIR .. '/HD2Scanner.log'
    local logbuf, log_dirty, log_written = {}, false, -1

    local function log(s)
        s = tostring(s)
        print('[HD2Scanner] ' .. s)
        logbuf[#logbuf + 1] = os.date('%H:%M:%S ') .. s
        if #logbuf > 400 then table.remove(logbuf, 1) end
        log_dirty = true
    end

    local function log_flush(force)
        local now = os.clock()
        if not force and (not log_dirty or now - log_written < 1) then return end
        log_dirty, log_written = false, now
        pcall(function()
            local f = io.open(LOGFILE, 'w')
            if not f then return end
            f:write('HD2 Scanner ' .. P.version .. ' (API ' .. P.api .. ')\n')
            f:write(table.concat(logbuf, '\n') .. '\n')
            f:close()
        end)
    end

    -- ---------------------------------------------------------------------------
    -- 4. 二进制小工具
    -- ---------------------------------------------------------------------------
    local function g_u32(get, o)
        return get(o) + get(o+1)*256 + get(o+2)*65536 + get(o+3)*16777216
    end
    local function g_i32(get, o)
        local v = g_u32(get, o)
        if v >= 2147483648 then v = v - 4294967296 end
        return v
    end
    local function s_u32(s, o)          -- 字符串按 0 基偏移读（s_u32(s,0) = 头 4 字节）
        local a,b,c,d = s:byte(o+1, o+4)
        return a + b*256 + c*65536 + d*16777216
    end
    local function s_u64(s, o)
        local lo, hi = s_u32(s, o), s_u32(s, o+4)
        return hi * 4294967296 + lo
    end
    local function hex8(v) return string.format('%08X', v % 4294967296) end

    -- ---------------------------------------------------------------------------
    -- 10. 打开游戏模块，拿 get()
    -- ---------------------------------------------------------------------------
    local GAME = { ready = false }
    local function game_open()
        if GAME.ready then return true end
        if not (ffi and kernel) then GAME.why = 'ffi unavailable' return false end
        local handle = kernel.GetModuleHandleA('game.dll')
        if handle == nil then GAME.why = 'game.dll not loaded' return false end
        local bytes = ffi.cast('const uint8_t *', handle)
        GAME.base  = tonumber(ffi.cast('uintptr_t', handle))
        GAME.get   = function(i) return bytes[i] end
        GAME.ready = true
        return true
    end


    return {
        ffi = ffi, kernel = kernel, PROC = PROC, BASE = BASE,
        mkdir_rel = mkdir_rel,
        mem_read = mem_read, mem_write = mem_write,
        raw_read = raw_read, rd_u32 = rd_u32, rd_u64 = rd_u64,
        g_u32 = g_u32, g_i32 = g_i32, s_u32 = s_u32, s_u64 = s_u64, hex8 = hex8,
        log = log, log_flush = log_flush, LOGDIR = LOGDIR, LOGFILE = LOGFILE,
        GAME = GAME, game_open = game_open,
    }
end

return M
