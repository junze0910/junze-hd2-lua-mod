-- HD2 Scanner / registry —— 插件注册表 + _G.HD2Menu
-- 资源名: mods/junze/hd2_scanner/registry
local M = {}

function M.new(ctx)
    local P, log = ctx.P, ctx.log

    -- ---------------------------------------------------------------------------
    -- 17. 插件注册表 + _G.HD2Menu
    -- ---------------------------------------------------------------------------
    local function sort_pages()
        table.sort(P.pages, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.id < b.id
        end)
    end

    local function unregister(id)
        for i, page in ipairs(P.pages) do
            if page.id == id then
                table.remove(P.pages, i)
                P.by_id[id] = nil
                P.revision = P.revision + 1
                if P.page == id then P.page, P.cursor = 'root', 1 end
                if P.cursor > #P.pages and P.page == 'root' then
                    P.cursor = math.max(1, #P.pages)
                end
                log('plugin unregistered: ' .. id)
                return true
            end
        end
        return false
    end

    local function register(plugin)
        if type(plugin) ~= 'table' then return nil, 'plugin must be a table' end
        if type(plugin.id) ~= 'string' or plugin.id == '' then return nil, 'plugin.id required' end
        if plugin.api ~= nil and plugin.api ~= P.api then
            log('plugin ' .. plugin.id .. ' rejected: api ' .. tostring(plugin.api) .. ' ~= ' .. tostring(P.api))
            return nil, 'api mismatch'
        end
        if P.by_id[plugin.id] then
            return { id = plugin.id, unregister = function() return unregister(plugin.id) end }
        end
        local page = {
            id = plugin.id,
            title = type(plugin.title) == 'string' and plugin.title or plugin.id,
            order = tonumber(plugin.order) or 100,
            status = plugin.status, build = plugin.build, settings = plugin.settings,
            fails = 0, disabled = nil,
        }
        P.pages[#P.pages + 1] = page
        P.by_id[page.id] = page
        sort_pages()
        P.revision = P.revision + 1
        log('plugin registered: ' .. page.id .. ' (' .. page.title .. ')')
        return { id = page.id, unregister = function() return unregister(page.id) end }
    end

    local API = {
        api = P.api, version = P.version,
        register = register, unregister = unregister,
        log = function(s) log('[plugin] ' .. tostring(s)) end,
        page_count = function() return #P.pages end,
    }
    rawset(_G, 'HD2Menu', API)
    P.api_table = API

    local queued = rawget(_G, 'HD2MenuQueue')
    if type(queued) == 'table' then
        for _, entry in ipairs(queued) do
            if type(entry) == 'table' and type(entry.attach) == 'function' then
                local ok, err = pcall(entry.attach, API)
                if not ok then log('queued plugin failed: ' .. tostring(entry.id) .. ': ' .. tostring(err)) end
            end
        end
        rawset(_G, 'HD2MenuQueue', nil)
    end


    return {
        register = register,
        unregister = unregister,
        api = API,
        pages = P.pages,
    }
end

return M
