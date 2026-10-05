-- HD2-Addon: mods/dsh/armor_tweaks
--
-- ===========================================================================
--  TD-110 挂载切换（tank_storm_loadout）
--  风暴漩涡坦克 tank_storm = 12738988949818115065 = 0xB0C9FAF4AF8903F9
--
--  ① 挂载四档模式（改【驾驶员位 +48】和【炮手位 +24】两个挂载项的 item）：
--      原装 vanilla : 驾驶员=烟雾弹发射器   炮手=激光制导部件
--      合作 coop    : 驾驶员=激光制导部件   炮手=烟雾弹发射器 或 40mm 机炮武器站（子选项）
--      忙碌 busy    : 驾驶员=重机枪武器站(主) 或 40mm 机炮武器站（子选项）
--                                          炮手=激光制导部件
--      自定义 custom : 两个槽位各自 5 选 1（白名单 = ITEM_LIST）
--     ★ 硬不变量（用户 2026-10-02 拍板）：两个槽位**恰好一个**是激光。
--       三个预设的任何子选项组合都会自检；自定义**同样受限**（面板/MODS 页上写清了原因）。
--
--  配置界面 = ModOptionsMenu（原生 MODS 页）；Scanner 面板那一页只放只读状态 + 诊断。
--
--  ② 射界（TurretComponentData）：**默认**把激光炮塔和加特林主炮的**水平**射界改成
--     ±180（= 360° 全方位）。面板 / cfg 上是一个开关，默认开。
--     ⚠ **只解水平射界（记录 +28 下限 / +32 上限），不解除视角限制** ——
--       驾驶/炮手操作炮塔时的视角范围原样保留。
--     原装值 dl_bin 实测：激光 recIdx 28 = ±20，加特林主炮 recIdx 29 = ±20。
--
--  ⚠ 弹匣不改：旧「忙碌驾驶员」包会把该炮台的 WeaponMagazineComponentData 容量改成
--      1000 发；用户 2026-10-02 拍板**去掉**这条腿 —— 本 mod 不碰那张表。
--
--  离线实测（generated_entities.dl_bin，2026-10-02）：
--      MountComponentData 0x3845B1E0  size=24744  记录区起点 +5184（324×16）  163 条记录
--        TD-110 recIdx 123：
--          槽0 +0   主炮（加特林）  0xD58AE6A04EDB10DE  node 3809236753 = 0xE30C5711
--          槽1 +24  激光制导       0xC36B5B37C058DBDD  node 3085546557 = 0xB7E9B43D  ← 炮手位
--          槽2 +48  烟雾弹发生器   0x3A061009AA31E9CB  node 2043430274 = 0x79CC4582  ← 驾驶员位
--          槽3/4   垂发单元       0x8AFF7F0793A5BCED
--      TurretComponentData 0x1EBA7593  size=7960  记录区起点 +2336（146×16）  74 条记录
--          激光制导 0xC36B5B37C058DBDD recIdx 28  射界 ±20
--          加特林主炮 0xD58AE6A04EDB10DE recIdx 29  射界 ±20
--
--  ⚠ 定位的两条坑（都踩过）：
--      1. 槽1 的 node 0xB7E9B43D 被 TD-220 堡垒共用（同底盘同挂点）——**node 不能当身份**。
--         身份 = 索引区的本体哈希（全表唯一），node 只按【已知槽位下标】做二级复核
--         （与机甲 mod 的写法一致）。实测：起点 +4944 / +4704 也能"找到本体哈希"，
--         但落到的记录槽位全 0 / node 是别的车 —— 只有全槽 node 复核能把它筛掉。
--      2. 记录区起点必须运行时推（索引条数会随版本漂移：322/324 都见过），
--         取【最大的合法候选】=真起点（实测 +5184 / +2336 正是最大值）。
--
--  ⚠ 时序（实机踩过）：MountComponentData 是**生成载具时读一次**的静态配置 →
--      挂载补丁必须早于召唤。切完模式请**重新召唤**坦克。
--      TurretComponentData 的射界是引擎实时读的 → 射界立刻生效，不用等。
--
--  ★ 反复改：覆盖判据 =「白名单 5 件」或「我们自己上次写的值」——**不是**"原装 or 当前目标"，
--    所以 A -> B -> C 能一路改下去（机甲 mod 的 6.24 就是判据太窄 ->「一个槽只能改一次」）。
--    初始化（写回原装）额外走 state.force_vanilla：**即使当前值认不出来也能强制写回**（对应 6.25）。
--
--  红线：只写目标字段；写前 VirtualProtect、写后回读校验；失败一律记 refuse，绝不当成功。
-- ===========================================================================

local VERSION = '1.0.0'
local MOD = 'mods/dsh/armor_tweaks'
if rawget(_G, MOD) then return end
rawset(_G, MOD, { frame = 0, phase = 'starting', writes = 0, refusals = 0, errs = 0,
                  polls = 0, last_gen = -1, last_gen_y = -1 })
local state = rawget(_G, MOD)
state.slots     = {}       -- 挂载项地址 -> 期望字节串（item 的 8 字节 LE）
state.yslots    = {}       -- 射界地址   -> 期望字节串（两个 float 的 8 字节）
state.yaw_orig  = {}       -- 武器哈希   -> 我们进来时看到的原装射界（用于"关掉开关"时写回）
state.yaw_addr  = {}       -- 武器哈希   -> 射界字段的绝对地址（面板读现实值用）
state.yaw_ix    = {}       -- 武器哈希   -> recIdx（诊断用）
state.force_vanilla = false  -- ★「初始化 / 写回原装」时置位：允许强制覆盖"认不出来的当前值"
                             --   （对应机甲 mod 的 6.25：当前值未知时也必须能写回原装）

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
    local file = loader and loader.open_log and loader.open_log('ArmorTweaks.log')
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
  print('[ArmorTweaks] ' .. message)
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
local function le(h)                     -- BE hex -> LE 字节串（u64 / hex 常量都走这个）
  local t = {}
  for i = #h - 1, 1, -2 do t[#t + 1] = string.char(tonumber(h:sub(i, i + 1), 16)) end
  return table.concat(t)
end

local function d32(b, o)                 -- 从字节串 offset o（0 基）读 u32 LE
  return b:byte(o + 1) + b:byte(o + 2) * 256 + b:byte(o + 3) * 65536 + b:byte(o + 4) * 16777216
end

local function hexs(b)                   -- 字节串 -> 内存顺序 hex（u64 律存的就是这个）
  if type(b) ~= 'string' then return '(nil)' end
  return (b:gsub('.', function(c) return string.format('%02X', c:byte()) end))
end

-- ---------------------------------------------------------------- 常量（全部实测）
local MAGIC        = 'LDLD'
local RDATA_OFF    = 24                  -- LDLD 表头；数据从 magic + 24 起

local MOUNT_TYPE   = 0x3845B1E0          -- djb2('MountComponentData')
local MOUNT_REC_SR = 120                 -- 挂载记录长（5 × 24 B）
local SLOT_SR      = 24                  -- 单个挂载项长
local SLOT_NODE_OFF = 8                  -- 挂载项内「挂载点 node」的偏移
local SLOT_FLAG_OFF = 12                 -- 挂载项内那 3 个 u32 的起点（本 mod 不动，只记日志）

local TURRET_TYPE  = 0x1EBA7593          -- djb2('TurretComponentData')
local TURRET_REC_SR = 76                 -- 炮塔记录长
local TURRET_YAW   = 28                  -- 记录内 水平射界下限（+32 = 上限）

-- ---------------------------------------------------------------- TD-220 / 40mm（2026-10-05 本批新增）
-- 弹道组件表（Scanner v0.8.2 起广播）：projectile_type 在记录 +0（u32）
local PROJ_TYPE     = 0x45171B68          -- djb2('ProjectileWeaponComponentData')
local PROJ_REC_SR   = 616                 -- 弹道组件记录长（272 条 × 616 = 167552，dl_bin 实测）
local PROJ_FIELD    = 0                   -- 记录内 projectile_type 的偏移
local AC40_ENT      = '9872EEB31A5F88FD'  -- 40mm 机炮武器站（弹道组件索引键；recIdx 47）
local AC40_ENT_LE   = le(AC40_ENT)
local PROJ_AP       = 120                 -- 炮_40mm_穿甲高爆（原装）
local PROJ_AA       = 284                 -- 机炮_20mm_防空（近炸子母）——「20mm 高射」

-- TD-220 堡垒 MK XVI：挂载表索引键 + 两槽 node（槽0 主炮 / 槽1 同轴重机枪）
local TD220_ENT     = '16474112801385B6'  -- TD-220 本体（recIdx 23）
local TD220_ENT_LE  = le(TD220_ENT)
local TD220_HMG     = '439F9E65C18567DA'  -- TD-220 同轴重机枪（原装，槽1）
local TD220_SLOT_IX = 1                   -- 槽1 = +24
local NODE_TD220_GUN = 3809236753         -- 0xE30C5711（槽0 主炮）
local NODE_TD220_HMG = 3085546557         -- 0xB7E9B43D（槽1 同轴重机枪；⚠ 与 TD-110 炮手位共用）

local R_MIN, R_MAX, R_CAP = 1024, 4194304, 262144

local RACK_ENT     = 'B0C9FAF4AF8903F9'  -- TD-110 本体（MountComponentData 的索引键）
local RACK_ENT_LE  = le(RACK_ENT)

-- 槽位下标（0 基）与挂载点 node（用户提供，与 dl_bin 逐位吻合）
local SLOT = { gunner = 1, driver = 2 }
local NODE = { gunner   = 3085546557,    -- 0xB7E9B43D（⚠ TD-220 也用它）
               driver   = 2043430274,    -- 0x79CC4582（全表唯一）
               maingun  = 3809236753 }   -- 0xE30C5711（槽0）

-- ---------------------------------------------------------------- 可选挂载物品（白名单）
-- 全部 dl_bin 实测（2026-10-02）。面板 / MODS 页显示的就是 label。
local ITEM_MG    = 'C25DC40EDE0E2D16'  -- 重机枪武器站（⚠ 不在任何挂载表里，是个"武器实体"）
local ITEM_AC40  = '9872EEB31A5F88FD'  -- 40mm 机炮武器站（正规挂载项：rec20.槽0 / rec157.槽0）
local ITEM_SILO  = '8AFF7F0793A5BCED'  -- 额外导弹发射器（= TD-110 槽3/4 的原装发射井）
local ITEM_SMOKE = '3A061009AA31E9CB'  -- 烟雾弹发射器（= TD-110 槽2 原装）
local ITEM_LASER = 'C36B5B37C058DBDD'  -- 激光制导部件（= TD-110 槽1 原装；射界 recIdx 28 = ±20）

local ITEM_LIST = {
  { hex = ITEM_MG,    label = '重机枪武器站',    note = '射界本来就 ±180' },
  { hex = ITEM_AC40,  label = '40mm 机炮武器站', note = '射界本来就 ±180' },
  { hex = ITEM_SILO,  label = '额外导弹发射器',  note = '没有炮塔记录' },
  { hex = ITEM_SMOKE, label = '烟雾弹发射器',    note = 'TD-110 原装·槽2' },
  { hex = ITEM_LASER, label = '激光制导部件',    note = '原装 ±20 → 本 mod 给 360°' },
}

local ITEM_LE, ITEM_LABEL, ITEM_BY_LABEL = {}, {}, {}
for _, it in ipairs(ITEM_LIST) do
  it.le = le(it.hex)
  ITEM_LE[it.hex]        = it.le
  ITEM_LABEL[it.hex]     = it.label
  ITEM_BY_LABEL[it.label] = it.hex
end
-- TD-220 原装同轴重机枪：不在「可选白名单」里（玩家不能主动选它），但**要能写回去**（初始化 / 切回原装）
ITEM_LE[TD220_HMG]    = le(TD220_HMG)
ITEM_LABEL[TD220_HMG] = 'TD-220 同轴重机枪（原装）'

-- 「认识的」item：槽位里的值不在这里面 = 别的 mod 动过 -> 拒写（不覆盖别人的改动）
local KNOWN_ITEM = {}
for _, it in ipairs(ITEM_LIST) do KNOWN_ITEM[it.le] = true end
KNOWN_ITEM[le(TD220_HMG)] = true      -- TD-220 原装同轴重机枪也算「认识的」（否则初始化写不回去）

-- 射界的两种形态（下限 float + 上限 float，共 8 字节 LE）
--   -20.0f = 0xC1A00000 / +20.0f = 0x41A00000（原装）
--   -180.0f = 0xC3340000 / +180.0f = 0x43340000（360° 全方位）
local YAW_OLD = string.char(0x00, 0x00, 0xA0, 0xC1, 0x00, 0x00, 0xA0, 0x41)
local YAW_NEW = string.char(0x00, 0x00, 0x34, 0xC3, 0x00, 0x00, 0x34, 0x43)

-- 射界的目标武器（TurretComponentData 索引键 = 武器实体哈希；recIdx 为 dl_bin 实测值）
local YAW_TARGETS = {
  { hex = 'C36B5B37C058DBDD', le = le('C36B5B37C058DBDD'), label = 'TD-110 激光炮塔'   },  -- recIdx 28
  { hex = 'D58AE6A04EDB10DE', le = le('D58AE6A04EDB10DE'), label = 'TD-110 加特林主炮' },  -- recIdx 29
  -- 2026-10-05：TD-220 堡垒 主炮 + 同轴重机枪 的射界**常驻解锁**（跟 CFG.yaw360 走；初始化会写回 ±20）
  { hex = '1FA1F596769225C2', le = le('1FA1F596769225C2'), label = 'TD-220 主炮'       },  -- recIdx 26
  { hex = '439F9E65C18567DA', le = le('439F9E65C18567DA'), label = 'TD-220 同轴重机枪'  },  -- recIdx 27
}

-- ---------------------------------------------------------------- 预设（4 档模式）
-- 槽位写法：固定值 = { fixed = <item> }；子选项 = { opt = 'cfg键', map = { 键值 = <item> } }
local PRESETS = {
  vanilla = { driver = { fixed = ITEM_SMOKE },
              gunner = { fixed = ITEM_LASER } },
  coop    = { driver = { fixed = ITEM_LASER },
              gunner = { opt = 'coop_gun', map = { smoke = ITEM_SMOKE, autocannon = ITEM_AC40 } } },
  busy    = { driver = { opt = 'busy_gun', map = { hmg = ITEM_MG, autocannon = ITEM_AC40 } },
              gunner = { fixed = ITEM_LASER } },
}

local MODE_CHOICES = { '原装（烟雾 / 激光）', '合作（驾驶员激光）',
                       '忙碌（驾驶员重火力）', '自定义（两槽自由搭配）' }
local MODE_KEY = {
  ['原装（烟雾 / 激光）']    = 'vanilla',
  ['合作（驾驶员激光）']     = 'coop',
  ['忙碌（驾驶员重火力）']   = 'busy',
  ['自定义（两槽自由搭配）'] = 'custom',
}
local MODE_LABEL = {
  vanilla = '原装（烟雾 / 激光）',
  coop    = '合作（驾驶员激光）',
  busy    = '忙碌（驾驶员重火力）',
  custom  = '自定义（两槽自由搭配）',
}

-- 子选项（MODS 页 / 面板的 choice 用；选项文字必须与 get() 返回的**逐字相同**）
local COOP_GUN_CHOICES = { '烟雾弹发射器', '40mm 机炮武器站' }
local COOP_GUN_KEY     = { ['烟雾弹发射器'] = 'smoke', ['40mm 机炮武器站'] = 'autocannon' }
local BUSY_GUN_CHOICES = { '重机枪武器站', '40mm 机炮武器站' }
local BUSY_GUN_KEY     = { ['重机枪武器站'] = 'hmg', ['40mm 机炮武器站'] = 'autocannon' }
local CUSTOM_CHOICES   = {}
for _, it in ipairs(ITEM_LIST) do CUSTOM_CHOICES[#CUSTOM_CHOICES + 1] = it.label end

local function spec_values(spec)
  if spec.fixed then return { spec.fixed } end
  local out = {}
  for _, v in pairs(spec.map or {}) do out[#out + 1] = v end
  table.sort(out)
  return out
end

-- 自检：三个预设的**任何子选项组合**都必须"恰好一个激光"（自定义豁免）
local selfcheck = { bad = {} }
for k, p in pairs(PRESETS) do
  for _, d in ipairs(spec_values(p.driver)) do
    for _, g in ipairs(spec_values(p.gunner)) do
      local cnt = 0
      if d == ITEM_LASER then cnt = cnt + 1 end
      if g == ITEM_LASER then cnt = cnt + 1 end
      if cnt ~= 1 then
        selfcheck.bad[#selfcheck.bad + 1] = ('%s：激光 %d 个（硬不变量要求恰好 1 个）'):format(k, cnt)
      end
      if not ITEM_LE[d] then selfcheck.bad[#selfcheck.bad + 1] = k .. '：驾驶员位用了白名单外的物品' end
      if not ITEM_LE[g] then selfcheck.bad[#selfcheck.bad + 1] = k .. '：炮手位用了白名单外的物品' end
    end
  end
end
table.sort(selfcheck.bad)
state.selfcheck = selfcheck
state.presets, state.items = PRESETS, ITEM_LIST

-- ---------------------------------------------------------------- cfg
-- ★ local CFG, CFG_FILE **必须声明在所有用它的函数之前**
--   （Lua 词法作用域是位置性的；交接单 §四记过两次）
local CFG, CFG_FILE
CFG = { mode = 'coop', coop_gun = 'smoke', busy_gun = 'hmg', yaw360 = true,
        driver = ITEM_LASER, gunner = ITEM_SMOKE,     -- 自定义的出场默认 = 驾驶员激光 / 炮手烟雾
        td220 = 'hmg', proj = 'ap' }                  -- 2026-10-05：TD-220 重机枪位 / 40mm 弹种
do
  local loader = rawget(_G, 'CowboyBingusModLoader')
  local base = loader and type(loader.log_directory) == 'string'
               and loader.log_directory:gsub('[/\\]Logs$', '') or '.'
  CFG_FILE = base .. '/ArmorTweaks.cfg'
end

local function truthy(v)
  v = tostring(v or ''):lower()
  return v == '1' or v == 'true' or v == 'on' or v == 'yes'
end

local function cfg_parse(text)
  for line in text:gmatch('[^\r\n]+') do
    line = line:gsub('#.*$', '')
    local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k == 'mode' then
      if PRESETS[v] or v == 'custom' then CFG.mode = v end
    elseif k == 'coop_gun' and (v == 'smoke' or v == 'autocannon') then
      CFG.coop_gun = v
    elseif k == 'busy_gun' and (v == 'hmg' or v == 'autocannon') then
      CFG.busy_gun = v
    elseif k == 'yaw360' then
      CFG.yaw360 = truthy(v)
    elseif k == 'driver' or k == 'gunner' then
      v = tostring(v or ''):upper()
      if ITEM_LE[v] then CFG[k] = v end            -- 白名单外的值直接忽略
    elseif k == 'td220' then
      if v == 'hmg' or v == 'ac40' then CFG.td220 = v end
    elseif k == 'proj' then
      if v == 'ap' or v == 'aa' then CFG.proj = v end
    end
  end
end

local function cfg_write_default()
  pcall(function()
    local f = io.open(CFG_FILE, 'w')
    if not f then return end
    f:write('# 装甲车辆轻度改装 —— 改完 1 秒内热生效；换挂载后要**重新召唤**载具\n')
    f:write('# mode: vanilla(原装) | coop(合作) | busy(忙碌) | custom(自定义)\n')
    f:write('mode=coop\n')
    f:write('# coop_gun（合作·炮手位）: smoke(烟雾弹) | autocannon(40mm机炮)\n')
    f:write('coop_gun=smoke\n')
    f:write('# busy_gun（忙碌·驾驶员位）: hmg(重机枪) | autocannon(40mm机炮)\n')
    f:write('busy_gun=hmg\n')
    f:write('# yaw360: 1 = 激光 + 加特林 的水平射界都改成 ±180（360°）；0 = 写回原装 ±20\n')
    f:write('#   ⚠ 只解水平射界（+28/+32），**不解除视角限制**；与模式无关\n')
    f:write('yaw360=1\n')
    f:write('# 下面两行只在 mode=custom 时生效（白名单 5 件）：\n')
    f:write('#   ' .. ITEM_MG .. ' 重机枪武器站 | ' .. ITEM_AC40 .. ' 40mm 机炮武器站\n')
    f:write('#   ' .. ITEM_SILO .. ' 额外导弹发射器 | ' .. ITEM_SMOKE .. ' 烟雾弹发射器\n')
    f:write('#   ' .. ITEM_LASER .. ' 激光制导部件\n')
    f:write('driver=' .. tostring(CFG.driver) .. '\n')
    f:write('gunner=' .. tostring(CFG.gunner) .. '\n')
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
    f:write('# 装甲车辆轻度改装\n')
    f:write('mode=' .. tostring(CFG.mode) .. '\n')
    f:write('coop_gun=' .. tostring(CFG.coop_gun) .. '\n')
    f:write('busy_gun=' .. tostring(CFG.busy_gun) .. '\n')
    f:write('yaw360=' .. (CFG.yaw360 and '1' or '0') .. '\n')
    f:write('driver=' .. tostring(CFG.driver) .. '\n')
    f:write('gunner=' .. tostring(CFG.gunner) .. '\n')
    f:write('td220=' .. tostring(CFG.td220) .. '\n')
    f:write('proj=' .. tostring(CFG.proj) .. '\n')
    f:close()
  end)
  if not ok then
    state.cfg_err = tostring(err)
    report('cfg 保存失败: ' .. tostring(err), true)
  else
    state.cfg_err = nil
    cfgt.text = nil
  end
  return ok
end

local cfg_at = 0
local function cfg_hot()
  local now = os.clock()
  if now - cfg_at < 1 then return end
  cfg_at = now
  local text = cfg_read()
  if text and text ~= cfgt.text then
    cfg_parse(text)
    cfgt.text = text
    state.force = true                 -- 刚改过 -> 下一帧不管 generation 先写一轮
    report(('cfg 热重读: mode=%s coop_gun=%s busy_gun=%s yaw360=%s'):format(
      tostring(CFG.mode), tostring(CFG.coop_gun), tostring(CFG.busy_gun),
      CFG.yaw360 and '1' or '0'), true)
  end
end

-- 解析当前 cfg -> 两个槽位的目标 item。失败返回 nil + 原因（拒写）
local function resolve_slot(spec)
  if spec.fixed then return spec.fixed end
  local v = spec.opt and CFG[spec.opt]
  if spec.map and v then return spec.map[v] end
  return nil
end

local function resolve_mode()
  if CFG.mode == 'custom' then
    if not ITEM_LE[CFG.driver] then return nil, '自定义：驾驶员位不在白名单里' end
    if not ITEM_LE[CFG.gunner] then return nil, '自定义：炮手位不在白名单里' end
    -- ★ 硬不变量对自定义同样成立：两槽不能同时是激光（会互相抢引导）
    if CFG.driver == ITEM_LASER and CFG.gunner == ITEM_LASER then
      return nil, '两个激光不能同时装（会互相抢引导）—— 请把其中一个换成别的'
    end
    return { driver = CFG.driver, gunner = CFG.gunner, custom = true }
  end
  local p = PRESETS[CFG.mode]
  if not p then return nil, '未知模式 ' .. tostring(CFG.mode) end
  local d, g = resolve_slot(p.driver), resolve_slot(p.gunner)
  if not d or not g then
    return nil, ('模式 %s 的子选项无效（coop_gun=%s busy_gun=%s）'):format(
      tostring(CFG.mode), tostring(CFG.coop_gun), tostring(CFG.busy_gun))
  end
  return { driver = d, gunner = g }
end

-- 切换 = 目标全变了 -> 清掉旧期望（别让 recheck 跟新目标打架）+ 下一帧强制写一轮
local function touched(what)
  state.slots = {}
  state.force = true
  cfg_save()
  report(what .. ' —— 挂载换完要**重新召唤**坦克才生效', true)
end

local function set_mode(key)
  if not (PRESETS[key] or key == 'custom') or CFG.mode == key then return end
  CFG.mode = key
  touched(('cfg: mode=%s（%s）'):format(key, tostring(MODE_LABEL[key])))
end

local function set_coop_gun(v)
  local k = COOP_GUN_KEY[v]
  if not k or CFG.coop_gun == k then return end
  CFG.coop_gun = k
  touched(('cfg: coop_gun=%s（合作·炮手位 = %s）'):format(k, tostring(v)))
end

local function set_busy_gun(v)
  local k = BUSY_GUN_KEY[v]
  if not k or CFG.busy_gun == k then return end
  CFG.busy_gun = k
  touched(('cfg: busy_gun=%s（忙碌·驾驶员位 = %s）'):format(k, tostring(v)))
end

local function set_custom(slot, label)
  local hex = ITEM_BY_LABEL[label]
  if not hex or CFG[slot] == hex then return end
  local other = (slot == 'driver') and 'gunner' or 'driver'
  if hex == ITEM_LASER and CFG[other] == ITEM_LASER then
    -- 拒绝这次改动（保持原状），并把 MODS 页上的控件弹回当前值
    report(('拒绝：%s 不能再放激光 —— 另一槽已经是激光了（两个激光会抢引导）。已保持原状')
      :format(slot == 'driver' and '驾驶员位(+48)' or '炮手位(+24)'), true)
    if state.mom and state.mom.set then
      local cur = CFG[slot]
      for i, lb in ipairs(CUSTOM_CHOICES) do
        if ITEM_BY_LABEL[lb] == cur then pcall(state.mom.set, 'armor_tweaks.' .. slot, i) end
      end
    end
    return
  end
  CFG[slot] = hex
  touched(('cfg: %s=%s（%s）'):format(slot, hex, tostring(label)))
end

local function set_yaw360(on)
  on = on and true or false
  if CFG.yaw360 == on then return end
  CFG.yaw360 = on
  state.force = true
  state.yslots = {}
  cfg_save()
  report(('cfg: yaw360=%s —— %s（射界是实时读的，立刻生效）'):format(
    on and '1' or '0', on and '激光 + 加特林 水平射界 → ±180（不动视角）' or '写回原装 ±20'), true)
end

-- 前向声明：MOM 段的「把控件拨回当前 cfg」；do_reset 复位 cfg 之后要调它
local mom_sync = nil

local function do_reset()
  state.slots, state.yslots = {}, {}
  state.force_vanilla = true          -- ★ 允许强制覆盖"认不出来的当前值"（6.25）
  CFG.mode, CFG.yaw360 = 'vanilla', false
  CFG.coop_gun, CFG.busy_gun = 'smoke', 'hmg'
  CFG.driver, CFG.gunner = ITEM_LASER, ITEM_SMOKE
  CFG.td220, CFG.proj = 'hmg', 'ap'       -- 2026-10-05：TD-220 重机枪位 + 40mm 弹种也一起还原
  state.force = true
  cfg_save()
  if mom_sync then pcall(mom_sync) end
  report('初始化：全部还原为原装（TD-110 驾驶员=烟雾弹 / 炮手=激光；TD-220 重机枪位=原装同轴重机枪；'
      .. '40mm=穿甲；四条炮塔射界写回 ±20 且本局不再自动套用），cfg 也复位', true)
end

-- ---------------------------------------------------------------- Scanner 前置（硬前置）
-- ⚠ USE_SELF_SCAN / SCAN **必须声明在所有用它们的函数之前**（同一个坑交接单记过两次）
local USE_SELF_SCAN = (rawget(_G, 'TD110_USE_SELF_SCAN') == true)
local SCAN = { api = nil, retry_at = 0, warned = false, polls = 0, req = {} }

local function scanner_get()
  if SCAN.api then return SCAN.api end
  local now = os.clock()
  if now < SCAN.retry_at then return nil end
  SCAN.retry_at = now + 60
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and tonumber(S.version) == 1 and type(S.poll) == 'function' then
    SCAN.api, SCAN.req = S, {}
    if type(S.request) == 'function' then
      local want = { { MOUNT_TYPE, 'TD-110 挂载切换（挂载）' }, { TURRET_TYPE, 'TD-110 挂载切换（射界）' } }
      for _, t in ipairs(want) do
        local ok, h = pcall(S.request, t[1], t[2])
        if ok and h then SCAN.req[#SCAN.req + 1] = h end
      end
    end
    report('已接上 HD2Scanner（前置）：挂载表 + 射界表由 Scanner 提供', true)
    return S
  end
  if not SCAN.warned then
    SCAN.warned = true
    if USE_SELF_SCAN then
      report('未发现 _G.HD2Scanner —— 走自扫回滚路径（TD110_USE_SELF_SCAN=true）', true)
    else
      report('未发现 _G.HD2Scanner —— 本 mod 以 HD2 Scanner 为前置（每 60 秒重试；' ..
             '自扫回滚需 _G.TD110_USE_SELF_SCAN=true）', true)
    end
  end
  return nil
end

-- 定稿 §7.2：要用之前喊一声，让 Scanner 当帧同步刷新（投战备 → 载具生成还有好几秒余量）
local function declare_need()
  for _, h in ipairs(SCAN.req) do
    if type(h) == 'table' and type(h.declare_need) == 'function' then pcall(h.declare_need) end
  end
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
  dump('ArmorTweaks_STATUS.log', msg .. '\n')
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
    } TS_MBI;
    void  *GetCurrentProcess(void);
    int    ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
    int    WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
    int    VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
    size_t VirtualQuery(const void *address, TS_MBI *info, size_t length);
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
  local mbi = ffi.new('TS_MBI[1]')
  function M.regions()
    local test_regions = rawget(_G, 'TS_TEST_REGIONS')
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

-- 自检不过 = 语义坏了 -> 一律不写（加载不报错，日志与面板都看得见原因）
if #selfcheck.bad > 0 then
  report('FAILED - 模式自检不通过（硬不变量：两个槽位恰好一个激光）：' ..
         table.concat(selfcheck.bad, ' | '), true)
  write_enabled = false
end

-- ---------------------------------------------------------------- 定位（与机甲 mod 同构）
-- 表头三件套：魔数 / version / 类型哈希（size 只做区间检查，不当指纹 —— 会随版本漂移）
local function validate_table(magic, type_hash)
  if not write_enabled then return nil end
  local h = api.read(magic, RDATA_OFF)
  if not h or #h < RDATA_OFF or h:sub(1, 4) ~= MAGIC then return nil end
  if d32(h, 4) ~= 1 or d32(h, 8) ~= type_hash then return nil end
  local size = d32(h, 12)
  if not size or size < R_MIN or size > R_MAX then return nil end
  return size
end

-- 记录区起点候选：16 的倍数 + 剩余能被记录长整除 + 索引区每条都合法
-- （索引条数会随版本变 -> 必须运行时推，不能硬编码）
local function layout_cands(data, size, rec_sr)
  local cands, ni = {}, 1
  while true do
    local b = ni * 16
    if b + rec_sr > size then break end
    if (size - b) % rec_sr == 0 then
      local n = (size - b) / rec_sr
      if n >= 4 then
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
local function find_rec(data, base, nr, ent_le, rec_sr)
  local q = data:find(ent_le, 1, true)
  while q do
    if (q - 1) % 16 == 0 and q - 1 + 16 <= base then
      local ix, pad = d32(data, q - 1 + 8), d32(data, q - 1 + 12)
      if pad == 0 and ix < nr then return base + ix * rec_sr, ix end
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
-- ---------------------------------------------------------------- 名字（给日志与面板看）
local NAME_OF_LE = {}
for _, it in ipairs(ITEM_LIST) do NAME_OF_LE[it.le] = it.label end
local function item_name(bytes)
  if type(bytes) ~= 'string' then return '?' end
  return NAME_OF_LE[bytes] or ('未知(' .. hexs(bytes) .. ')')
end
local function yaw_name(bytes)
  if bytes == YAW_NEW then return '±180（360°）' end
  if bytes == YAW_OLD then return '±20' end
  return '?'
end

-- ---------------------------------------------------------------- 腿① 挂载（MountComponentData）
-- 槽位复核：按【已知槽位下标】取 node 逐个对（与机甲 mod 的写法一致）。
-- ⚠ node 只能"确认这条记录是 TD-110 的这套挂载"，**不能当身份**（0xB7E9B43D 被 TD-220 共用）；
--   身份 = 索引区里的本体哈希（全表唯一）。
local function record_ok(data, rec_off)
  if d32(data, rec_off + SLOT.driver  * SLOT_SR + SLOT_NODE_OFF) ~= NODE.driver  then return false, '驾驶员位 node' end
  if d32(data, rec_off + SLOT.gunner  * SLOT_SR + SLOT_NODE_OFF) ~= NODE.gunner  then return false, '炮手位 node' end
  if d32(data, rec_off + 0            * SLOT_SR + SLOT_NODE_OFF) ~= NODE.maingun then return false, '主炮位 node' end
  return true
end

local function slot_flags(data, rec_off, slot)
  local o = rec_off + slot * SLOT_SR + SLOT_FLAG_OFF
  return ('%08X %08X %08X'):format(d32(data, o), d32(data, o + 4), d32(data, o + 8))
end

-- 当前值能不能被覆盖？三档判据（缺一不可，都是踩过坑换来的）：
--  ① 白名单 5 件 —— 本 mod 自己改过的任何状态都能再改。
--     ★ 判据**不是**"原装 or 当前目标"：机甲 mod 的 6.24 就是判据太窄 ->「一个槽只能改一次」。
--  ② 我们自己上次写进去的值（state.slots 里记着；模式切换会清它，所以只是补充）。
--  ③ 强制回原装（初始化）：即使当前值认不出来也允许 —— 6.25 的对策。
local function may_overwrite(address, cur, want_le)
  if not cur then return true end
  if KNOWN_ITEM[cur] then return true end
  if state.slots[address] == cur then return true end
  if state.force_vanilla and (want_le == ITEM_LE[ITEM_SMOKE] or want_le == ITEM_LE[ITEM_LASER]
     or want_le == ITEM_LE[TD220_HMG]) then
    return true
  end
  return false
end

-- 写一个槽位的 8 字节 item。返回 1 = 真写了、0 = 没动
local function write_slot(address, want_le, who, rec_ix)
  local cur = api.read(address, 8)
  if cur == want_le then
    state.slots[address] = want_le
    return 0
  end
  if not may_overwrite(address, cur, want_le) then
    state.refusals = state.refusals + 1
    report(('拒写：%s 当前是 %s —— 不是本 mod 认识的任何一件装备（别的 mod 改过？）；' ..
            '想强行写回原装请点「初始化」'):format(who, hexs(cur)), true)
    return 0
  end
  if write8(address, want_le) then
    state.writes = state.writes + 1
    state.slots[address] = want_le
    report(('已写：%s %s -> %s（recIdx %s，node/flags 未动）'):format(
      who, cur and hexs(cur) or '(读不到)', hexs(want_le), tostring(rec_ix)), true)
    return 1
  end
  return 0
end

-- 一张挂载表副本：选起点 -> 索引定位 TD-110 记录 -> 槽位复核 -> 写两个槽位的 item
-- TD-220 记录复核：槽0 node = 主炮挂点、槽1 node = 同轴机枪挂点
local function td220_record_ok(data, rec_off)
  if d32(data, rec_off + 0 * SLOT_SR + SLOT_NODE_OFF) ~= NODE_TD220_GUN then return false, '槽0 主炮 node' end
  if d32(data, rec_off + TD220_SLOT_IX * SLOT_SR + SLOT_NODE_OFF) ~= NODE_TD220_HMG then return false, '槽1 机枪 node' end
  return true
end

-- 一张挂载表副本：选起点 -> 索引定位 TD-110 / TD-220 两条记录 -> 槽位复核 -> 写槽位
-- 2026-10-05：同一张表里同时照顾两辆车
local function apply_mount(magic, mode)
  if not write_enabled then return 0 end
  local size = validate_table(magic, MOUNT_TYPE)
  if not size then return 0 end
  if size > R_CAP then
    report(('挂载表 0x%X 声明 size=%d 超过读取上限 %d，跳过'):format(magic, size, R_CAP), true)
    return 0
  end
  local data = api.read(magic + RDATA_OFF, size)
  if not data then return 0 end

  local cands = layout_cands(data, size, MOUNT_REC_SR)
  for _, cand in ipairs(cands) do
    local rec_off, rec_ix = find_rec(data, cand.base, cand.n, RACK_ENT_LE,  MOUNT_REC_SR)
    local o220,    ix220  = find_rec(data, cand.base, cand.n, TD220_ENT_LE, MOUNT_REC_SR)
    if rec_off and o220 then
      local ok,  why  = record_ok(data, rec_off)
      local ok2, why2 = td220_record_ok(data, o220)
      if ok and ok2 then
        state.layout, state.rec_ix = cand.base, rec_ix
        state.rec_ix220 = ix220
        local base = magic + RDATA_OFF + rec_off
        local b220 = magic + RDATA_OFF + o220
        state.addr = { driver = base + SLOT.driver * SLOT_SR,
                       gunner = base + SLOT.gunner * SLOT_SR }
        state.addr220 = b220 + TD220_SLOT_IX * SLOT_SR
        if not state.flags_logged then
          state.flags_logged = true
          report(('挂载项 flags（诊断用，本 mod 不动）：主炮 [%s] 炮手 [%s] 驾驶员 [%s]'):format(
            slot_flags(data, rec_off, 0), slot_flags(data, rec_off, SLOT.gunner),
            slot_flags(data, rec_off, SLOT.driver)), true)
        end
        local w = 0
        w = w + write_slot(state.addr.driver, ITEM_LE[mode.driver], 'TD-110 驾驶员位(+48)', rec_ix)
        w = w + write_slot(state.addr.gunner, ITEM_LE[mode.gunner], 'TD-110 炮手位(+24)', rec_ix)
        local ac40 = (CFG.td220 == 'ac40')
        w = w + write_slot(state.addr220,
          ac40 and ITEM_LE[ITEM_AC40] or ITEM_LE[TD220_HMG],
          ac40 and 'TD-220 重机枪位(+24) = 40mm 机炮武器站' or 'TD-220 重机枪位(+24) = 原装同轴重机枪', ix220)
        return w
      elseif not state.node_warned or state.frame - state.node_warned > 6000 then
        state.node_warned = state.frame
        report(('挂载表 0x%X：记录复核不过（TD-110 %s / TD-220 %s），本轮拒写'):format(
          magic, tostring(why), tostring(why2)), true)
        return 0
      end
    end
  end
  if not state.mount_warned or state.frame - state.mount_warned > 6000 then
    state.mount_warned = state.frame
    report(('挂载表 0x%X：%d 个候选起点都没定位到 TD-110 + TD-220 两条记录（size=%d），本轮拒写'):format(
      magic, #cands, size), true)
  end
  return 0
end

-- ---------------------------------------------------------------- 腿② 射界（TurretComponentData）
-- 默认：激光炮塔 + 加特林主炮 一起改成 ±180（360°）。关掉开关 -> 写回原装。
-- 射界是引擎**实时读**的，所以这条腿改完立刻生效（不用重新召唤载具）。
local function apply_yaw(magic, want360)
  if not write_enabled then return 0 end
  local size = validate_table(magic, TURRET_TYPE)
  if not size then return 0 end
  if size > R_CAP then
    report(('射界表 0x%X 声明 size=%d 超过读取上限 %d，跳过'):format(magic, size, R_CAP), true)
    return 0
  end
  local data = api.read(magic + RDATA_OFF, size)
  if not data then return 0 end

  local cands = layout_cands(data, size, TURRET_REC_SR)
  for _, cand in ipairs(cands) do
    -- 认表判据：**所有**目标武器都要找到，且射界是已知形态（±20 / ±180）。
    -- 实测：只有真起点 +2336 同时满足（更小的候选起点上，有的记录会读到别人的数值）。
    local hits, ok = {}, true
    for _, t in ipairs(YAW_TARGETS) do
      local rec_off, rec_ix = find_rec(data, cand.base, cand.n, t.le, TURRET_REC_SR)
      if rec_off then
        local cur = data:sub(rec_off + TURRET_YAW + 1, rec_off + TURRET_YAW + 8)
        -- 认表判据 = 射界是已知形态；例外：初始化强制回原装，且这个地址**以前验证过**（6.25 对策）
        local addr_here = magic + RDATA_OFF + rec_off + TURRET_YAW
        local forced = state.force_vanilla and (not want360)
                       and state.yaw_addr[t.hex] == addr_here
        if cur == YAW_OLD or cur == YAW_NEW or forced then
          hits[#hits + 1] = { t = t, off = rec_off, ix = rec_ix, cur = cur }
        else
          ok = false
        end
      else
        ok = false
      end
      if not ok then break end
    end
    if ok and #hits > 0 then
      state.layout_y = cand.base
      local w = 0
      for _, h in ipairs(hits) do
        if h.cur ~= YAW_NEW then
          state.yaw_orig[h.t.hex] = state.yaw_orig[h.t.hex] or h.cur   -- 记住原装值
        end
        local want = want360 and YAW_NEW or (state.yaw_orig[h.t.hex] or YAW_OLD)
        local address = magic + RDATA_OFF + h.off + TURRET_YAW
        state.yaw_addr[h.t.hex], state.yaw_ix[h.t.hex] = address, h.ix
        if h.cur ~= want then
          if write8(address, want) then
            state.writes = state.writes + 1
            report(('已写射界：%s（recIdx %s）%s -> %s'):format(
              h.t.label, tostring(h.ix), yaw_name(h.cur), yaw_name(want)), true)
            w = w + 1
          end
        end
        state.yslots[address] = want
      end
      return w
    end
  end
  if not state.yaw_warned or state.frame - state.yaw_warned > 6000 then
    state.yaw_warned = state.frame
    report(('射界表 0x%X：%d 个候选起点都没定位到目标记录（激光 + 加特林，size=%d），本轮拒写'):format(
      magic, #cands, size), true)
  end
  return 0
end

-- ---------------------------------------------------------------- 腿③ 40mm 弹种（ProjectileWeaponComponentData）
-- 「40mm 穿甲」(120) <-> 「20mm 高射」(284)。projectile_type = 记录 +0（u32）。实时生效。
local function u32le(v)
  return le(string.format('%08X', v % 4294967296))
end

local function write4(address, bytes)
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

local function proj_name(v)
  if v == PROJ_AP then return '40mm 穿甲（原装）' end
  if v == PROJ_AA then return '20mm 高射' end
  return tostring(v)
end

local function apply_proj(magic)
  if not write_enabled then return 0 end
  local size = validate_table(magic, PROJ_TYPE)
  if not size then return 0 end
  if size > R_CAP then
    report(('弹道表 0x%X 声明 size=%d 超过读取上限 %d，跳过'):format(magic, size, R_CAP), true)
    return 0
  end
  local data = api.read(magic + RDATA_OFF, size)
  if not data then return 0 end
  local want = (CFG.proj == 'aa') and PROJ_AA or PROJ_AP
  local cands = layout_cands(data, size, PROJ_REC_SR)
  for _, cand in ipairs(cands) do
    local rec_off, rec_ix = find_rec(data, cand.base, cand.n, AC40_ENT_LE, PROJ_REC_SR)
    if rec_off then
      local cur = d32(data, rec_off + PROJ_FIELD)
      if cur ~= PROJ_AP and cur ~= PROJ_AA then
        if not state.proj_warned or state.frame - state.proj_warned > 6000 then
          state.proj_warned = state.frame
          report(('弹道表 0x%X：40mm（recIdx %s）当前 projectile_type = %d —— 不是认识的 120/284，拒写'):format(
            magic, tostring(rec_ix), cur), true)
        end
        return 0
      end
      state.proj_layout, state.proj_ix = cand.base, rec_ix
      local address = magic + RDATA_OFF + rec_off + PROJ_FIELD
      state.proj_addr, state.proj_cur = address, cur
      if cur == want then
        state.proj_want = want
        return 0
      end
      if write4(address, u32le(want)) then
        state.writes = state.writes + 1
        state.proj_want = want
        report(('已写弹种：40mm 机炮 %s -> %s（recIdx %s）'):format(
          proj_name(cur), proj_name(want), tostring(rec_ix)), true)
        return 1
      end
      return 0
    end
  end
  if not state.proj_warned or state.frame - state.proj_warned > 6000 then
    state.proj_warned = state.frame
    report(('弹道表 0x%X：%d 个候选起点都没定位到 40mm 记录（size=%d），拒写'):format(
      magic, #cands, size), true)
  end
  return 0
end
-- ---------------------------------------------------------------- Scanner 快照 → 逐副本处理
local function poll_entries(type_hash)
  local snap = SCAN.api.poll(type_hash)
  SCAN.polls = SCAN.polls + 1
  if type(snap) ~= 'table' then return 0, nil end
  return tonumber(snap.generation) or 0, snap.entries
end

local function run_entries(entries, fn)
  local n = 0
  if type(entries) ~= 'table' then return 0 end
  for i = 1, #entries do
    local e = entries[i]
    if type(e) == 'table' and type(e.addr) == 'number' then
      local ok, got = pcall(fn, e.addr)
      if not ok then
        state.errs = state.errs + 1
        if state.errs <= 3 then report('表处理异常: ' .. tostring(got), true) end
      else
        n = n + (tonumber(got) or 0)
      end
    end
  end
  return n
end

-- 写后复查：被游戏冲掉就重写（消费者自己的正确性底线）
local function recheck()
  if not write_enabled then return 0 end
  local live, fixed, drop = 0, 0, 0
  local function pass(map)
    for address, want in pairs(map) do
      local cur = api.read(address, #want)
      if cur == want then
        live = live + 1
      elseif write8(address, want) then
        state.writes = state.writes + 1
        live, fixed = live + 1, fixed + 1
      else
        map[address] = nil
        drop = drop + 1
      end
    end
  end
  pass(state.slots)
  pass(state.yslots)
  if fixed > 0 then report(('复查：重写被冲掉的补丁 %d 处'):format(fixed), true) end
  if drop  > 0 then report(('复查：丢弃失效地址 %d 处'):format(drop), true) end
  return live
end

-- ---------------------------------------------------------------- 自扫回滚（TD110_USE_SELF_SCAN）
-- 没有 Scanner 时的兜底：按 LDLD + 类型哈希自己找表，再走同一条 apply。
-- 分片：每帧最多读 SELF_BUDGET 字节，不卡帧。
local selfw = { regions = nil, ri = 1, off = 0, tail = nil, next_at = 0 }
local SELF_CHUNK  = 1 * 1024 * 1024
local SELF_BUDGET = 4 * 1024 * 1024

local function self_scan_reset()
  selfw.regions, selfw.ri, selfw.off, selfw.tail = nil, 1, 0, nil
end

local function self_scan_step(mode)
  if not write_enabled then return end
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
          if validate_table(addr, MOUNT_TYPE) then
            local ok2 = pcall(apply_mount, addr, mode)
            if not ok2 then state.errs = state.errs + 1 end
          elseif validate_table(addr, TURRET_TYPE) then
            local ok2 = pcall(apply_yaw, addr, CFG.yaw360)
            if not ok2 then state.errs = state.errs + 1 end
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
    report(('自扫完成：看完 %d 个区域，累计写 %d 处（下一轮 30 秒后）'):format(
      #selfw.regions, state.writes), true)
    selfw.next_at = os.clock() + 30
    self_scan_reset()
  end
end

-- ---------------------------------------------------------------- 状态落盘
local function live_n(map)
  local n = 0
  for _ in pairs(map) do n = n + 1 end
  return n
end

local function write_status()
  local live, ylive = live_n(state.slots), live_n(state.yslots)
  local mode, mode_why = resolve_mode()
  local first
  if #selfcheck.bad > 0 then
    first = 'FAILED - 模式自检不通过：' .. table.concat(selfcheck.bad, ' | ')
  elseif not mode then
    first = 'FAILED - 配置被拒：' .. tostring(mode_why)
  elseif live > 0 and (not CFG.yaw360 or ylive > 0) then
    first = ('OK - 补丁生效中（挂载 %d 处 / 射界 %d 处）'):format(live, ylive)
  elseif SCAN.api then
    first = 'WORKING - 等待目标表'
  else
    first = 'WORKING - 等待 Scanner 前置'
  end
  dump('ArmorTweaks_STATUS.log', table.concat({
    first,
    'revision=tank-storm-loadout-' .. VERSION,
    'phase=' .. tostring(state.phase),
    'mode=' .. tostring(CFG.mode) .. '（' .. tostring(MODE_LABEL[CFG.mode]) .. '）'
      .. '  coop_gun=' .. tostring(CFG.coop_gun) .. '  busy_gun=' .. tostring(CFG.busy_gun),
    ('驾驶员位(+48) 目标 = %s'):format(item_name(mode and ITEM_LE[mode.driver] or nil)),
    ('炮手位(+24)   目标 = %s'):format(item_name(mode and ITEM_LE[mode.gunner] or nil)),
    ('射界开关 yaw360 = %s（只解水平 ±180；不解除视角）'):format(
      CFG.yaw360 and '1' or '0（原装 ±20）'),
    ('本体 = %s（recIdx 实测 %s）'):format(RACK_ENT, tostring(state.rec_ix or '?')),
    ('挂载记录区起点 = %s（运行时推，不硬编码）'):format(tostring(state.layout or '?')),
    ('激光炮塔 recIdx = %s   加特林主炮 recIdx = %s'):format(
      tostring(state.yaw_ix[YAW_TARGETS[1].hex] or '?'), tostring(state.yaw_ix[YAW_TARGETS[2].hex] or '?')),
    ('射界记录区起点 = %s'):format(tostring(state.layout_y or '?')),
    ('前置 = Bingus Shared Loader loader-v%s / API %s（%s）'):format(
      tostring(ENV.version or '?'), tostring(ENV.api or '?'), tostring(ENV.source)),
    ('Scanner = %s   polls = %d'):format(SCAN.api and '已接上' or '无', SCAN.polls),
    ('已写=%d 拒绝=%d 帧=%d 存活=%d/%d'):format(
      state.writes, state.refusals, state.frame, live, ylive),
    '★ 挂载换完要**重新召唤**坦克；射界实时读，不用等',
    'updated=' .. os.date('%Y-%m-%d %H:%M:%S'),
  }, '\n') .. '\n')
end

-- ---------------------------------------------------------------- 每帧
local APPLY_EVERY, RECHECK_EVERY, STATUS_EVERY = 60, 300, 300

local function frame()
  state.frame = state.frame + 1
  cfg_hot()
  flush_log()

  local mode, mode_why = resolve_mode()
  if not mode or #selfcheck.bad > 0 then
    -- 配置被拒（例如自定义里两槽都是激光）：日志里说清原因，别让玩家以为 mod 哑了
    if not mode then report('挂载腿拒写：' .. tostring(mode_why)) end
    if state.frame % STATUS_EVERY == 0 then write_status() end
    return
  end

  local S = scanner_get()
  if not S then
    if USE_SELF_SCAN then self_scan_step(mode) end
    if state.frame % STATUS_EVERY == 0 then write_status() end
    return
  end

  local force = state.force == true
  if force then declare_need() end            -- §7.2：立刻同步刷一次，别等 30 秒
  local w0 = state.writes

  local gen, entries = poll_entries(MOUNT_TYPE)
  if force or gen ~= state.last_gen or (state.frame % APPLY_EVERY == 0) then
    state.last_gen = gen
    run_entries(entries, function(a) return apply_mount(a, mode) end)
  end

  local geny, entriesy = poll_entries(TURRET_TYPE)
  if force or geny ~= state.last_gen_y or (state.frame % APPLY_EVERY == 0) then
    state.last_gen_y = geny
    run_entries(entriesy, function(a) return apply_yaw(a, CFG.yaw360) end)
  end

  -- 2026-10-05：40mm 弹种（ProjectileWeaponComponentData，Scanner v0.8.2 起广播）
  local genp, entriesp = poll_entries(PROJ_TYPE)
  if force or genp ~= state.last_gen_p or (state.frame % APPLY_EVERY == 0) then
    state.last_gen_p = genp
    run_entries(entriesp, function(a) return apply_proj(a) end)
  end

  state.force = false
  state.force_vanilla = false         -- 一次性：本轮没用上就作废（下次点初始化会再置位）

  if state.writes > w0 then
    state.phase = 'armed'
    write_status()                            -- 刚写成功：立刻落一份状态
  end
  if state.frame % RECHECK_EVERY == 0 then
    if recheck() == 0 and state.phase == 'armed' then state.phase = 'waiting' end
  end
  if state.frame % STATUS_EVERY == 0 then write_status() end
end
-- ---------------------------------------------------------------- 设置项
local MOD_OPTIONS = { registered = false }

local function action_apply_now()
  local mode, why = resolve_mode()
  if not mode then report('立刻写一次：' .. tostring(why), true) return end
  local S = scanner_get()
  if not S then
    if USE_SELF_SCAN then self_scan_step(mode) end
    report('立刻写一次：没有 Scanner 前置，写不了', true)
    return
  end
  declare_need()
  local gen, entries = poll_entries(MOUNT_TYPE)
  state.last_gen = gen
  local w = run_entries(entries, function(a) return apply_mount(a, mode) end)
  local geny, entriesy = poll_entries(TURRET_TYPE)
  state.last_gen_y = geny
  w = w + run_entries(entriesy, function(a) return apply_yaw(a, CFG.yaw360) end)
  local genp, entriesp = poll_entries(PROJ_TYPE)
  state.last_gen_p = genp
  w = w + run_entries(entriesp, function(a) return apply_proj(a) end)
  recheck()
  report(('立刻写一次：本轮写 %d 处，累计 %d 处'):format(w, state.writes), true)
end
-- ---------------------------------------------------------------- MOM 适配
-- 2026-10-04：并进 HD2 统一分组（A HD2 MOD COLLECTION），行数 7 -> 3：
--   预设（原装 / 合作·烟雾 / 合作·40mm / 忙碌·重机枪 / 忙碌·40mm / 自定义）
--   炮手槽位 / 驾驶员槽位（各 5 项；直接改 = 自动切「自定义」）
-- 射界 360° 改成**默认行为**（不再占一行）；「初始化」挂到 Scanner 的全局按钮。
local MOM_GROUP_FALLBACK = 'A HD2 MOD COLLECTION'
local function mom_group()
  local S = rawget(_G, 'HD2Scanner')
  if type(S) == 'table' and type(S.mom_group) == 'string' and S.mom_group ~= '' then
    return S.mom_group
  end
  return MOM_GROUP_FALLBACK
end

-- 预设 6 档 -> (mode, 子选项)。mode 仍是唯一的真值；预设只是它的快捷方式。
local TD220_CHOICES = { '堡垒同轴重机枪（原装）', '40mm 机炮武器站' }
local PROJ_CHOICES  = { '40mm 穿甲（原装）', '20mm 高射（近炸子母）' }

local PRESET_CHOICES = {
  '原装（烟雾 / 激光）',
  '合作 · 烟雾弹（驾驶员激光）',
  '合作 · 40mm 机炮（驾驶员激光）',
  '忙碌 · 重机枪（炮手激光）',
  '忙碌 · 40mm 机炮（炮手激光）',
  '自定义（直接改下面两槽）',
}
local PRESET_KEYS = {
  { mode = 'vanilla' },
  { mode = 'coop', coop_gun = 'smoke' },
  { mode = 'coop', coop_gun = 'autocannon' },
  { mode = 'busy', busy_gun = 'hmg' },
  { mode = 'busy', busy_gun = 'autocannon' },
  { mode = 'custom' },
}
local function preset_index()
  local m = CFG.mode
  if m == 'vanilla' then return 1 end
  if m == 'coop'  then return (CFG.coop_gun == 'autocannon') and 3 or 2 end
  if m == 'busy'  then return (CFG.busy_gun == 'autocannon') and 5 or 4 end
  return 6
end

local function slot_index(slot)
  for i, lb in ipairs(CUSTOM_CHOICES) do
    if ITEM_BY_LABEL[lb] == CFG[slot] then return i end
  end
  return 1
end

local function apply_preset(i)
  local pk = PRESET_KEYS[i]
  if not pk then return end
  CFG.mode = pk.mode
  if pk.coop_gun then CFG.coop_gun = pk.coop_gun end
  if pk.busy_gun then CFG.busy_gun = pk.busy_gun end
  CFG.yaw360 = true                    -- ★ 射界 360° 是默认行为：点预设 = 重新套用
  touched(('预设 -> %s'):format(PRESET_CHOICES[i]))
end

-- 全局「初始化」：挂到 Scanner 的注册表（旧版 Scanner 没该 API 则跳过）
local RESET_HOOKED = false
local function hook_reset()
  if RESET_HOOKED then return end
  local S = rawget(_G, 'HD2Scanner')
  if type(S) ~= 'table' or type(S.register_reset) ~= 'function' then return end
  local ok, res = pcall(S.register_reset, '装甲车辆', do_reset)
  if ok and res then RESET_HOOKED = true end
end

local function register_mod_options()
  if MOD_OPTIONS.registered then return end
  local mom = rawget(_G, 'ModOptionsMenu')
  if type(mom) ~= 'table' or mom.api ~= 1 then return end
  MOD_OPTIONS.registered = true
  state.mom = mom                      -- 拒绝非法改动时用它把控件弹回当前值
  local MOM_GROUP = mom_group()

  -- ① 预设
  local pid = 'armor_tweaks.preset'
  mom.register_option(pid, { type = 'choice', label = '[TD-110] 预设', mod = MOM_GROUP,
    choices = PRESET_CHOICES, default = preset_index(),
    description = '六档预设：原装 / 合作（驾驶员激光）/ 忙碌（驾驶员重火力）/ 自定义。'
      .. '挂载换完要**重新召唤**坦克才生效。'
      .. '射界 360° 是本 mod 的默认行为：点任意预设都会重新套用；只有「初始化」会写回原装 ±20。' })
  mom.on_change(pid, function(v)
    apply_preset(tonumber(v) or 0)
    if mom_sync then pcall(mom_sync) end
  end)

  -- ② 炮手槽位 / ③ 驾驶员槽位（直接改 = 自动切「自定义」）
  for _, slot in ipairs({ 'driver', 'gunner' }) do
    local sid = 'armor_tweaks.' .. slot
    local who = (slot == 'driver') and '驾驶员' or '炮手'
    mom.register_option(sid, { type = 'choice',
      label = '[TD-110] ' .. who .. '槽位',
      mod = MOM_GROUP, choices = CUSTOM_CHOICES, default = slot_index(slot),
      description = ('直接选 %s 槽里的物品（白名单 5 件）；改完自动切到「自定义」预设。'
        .. '两槽不能同时是激光（会互相抢引导）。挂载换完要重新召唤坦克才生效。'):format(who) })
    mom.on_change(sid, function(v)
      local nm = CUSTOM_CHOICES[tonumber(v) or 0]
      if nm then set_custom(slot, nm) end
      CFG.yaw360 = true
      if mom.set then pcall(mom.set, 'armor_tweaks.preset', preset_index()) end
    end)
  end

  -- ④ TD-220 重机枪位（二选一）
  local t220id = 'armor_tweaks.td220'
  mom.register_option(t220id, { type = 'choice', label = '[TD-220] 重机枪位', mod = MOM_GROUP,
    choices = TD220_CHOICES, default = (CFG.td220 == 'ac40') and 2 or 1,
    description = 'TD-220 堡垒 MK XVI 的同轴重机枪位（槽1 / node 0xB7E9B43D）：原装「堡垒同轴重机枪」，'
      .. '或换成「40mm 机炮武器站」。挂载换完要**重新召唤**载具才生效。' })
  mom.on_change(t220id, function(v)
    CFG.td220 = (tonumber(v) == 2) and 'ac40' or 'hmg'
    CFG.yaw360 = true
    touched(('TD-220 重机枪位 -> %s'):format((CFG.td220 == 'ac40') and '40mm 机炮武器站' or '原装同轴重机枪'))
    if mom_sync then pcall(mom_sync) end
  end)

  -- ⑤ 40mm 弹种（二选一）
  local projid = 'armor_tweaks.proj'
  mom.register_option(projid, { type = 'choice', label = '[40mm] 弹种', mod = MOM_GROUP,
    choices = PROJ_CHOICES, default = (CFG.proj == 'aa') and 2 or 1,
    description = '40mm 机炮打出去的弹：原装「40mm 穿甲高爆」，或「20mm 高射」（近炸子母弹）。'
      .. '这条**实时生效**，不用重新召唤载具。' })
  mom.on_change(projid, function(v)
    CFG.proj = (tonumber(v) == 2) and 'aa' or 'ap'
    CFG.yaw360 = true
    touched(('40mm 弹种 -> %s'):format((CFG.proj == 'aa') and '20mm 高射' or '40mm 穿甲'))
    if mom_sync then pcall(mom_sync) end
  end)

  -- 把 MOM 五个控件拨回当前 cfg（预设切换 / 初始化之后调）
  mom_sync = function()
    if type(mom.set) ~= 'function' then return end
    pcall(mom.set, 'armor_tweaks.preset', preset_index())
    pcall(mom.set, 'armor_tweaks.driver', slot_index('driver'))
    pcall(mom.set, 'armor_tweaks.gunner', slot_index('gunner'))
    pcall(mom.set, 'armor_tweaks.td220', (CFG.td220 == 'ac40') and 2 or 1)
    pcall(mom.set, 'armor_tweaks.proj', (CFG.proj == 'aa') and 2 or 1)
  end

  report(('ModOptionsMenu: 已注册到「%s」（5 行：预设 / TD-110 炮手 + 驾驶员槽位 / TD-220 重机枪位 / 40mm 弹种；初始化在 Scanner 的全局按钮）'):format(MOM_GROUP), true)
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
    local ok4, err4 = pcall(hook_reset)
    if not ok4 then
      state.errs = state.errs + 1
      if state.errs <= 5 then report('Scanner 全局初始化挂钩 error: ' .. tostring(err4)) end
    end
    return orig(...)
  end
end

report(('已加载 v%s（TD-110 mode=%s / TD-220 重机枪位=%s / 40mm 弹种=%s；射界 360°=%s；Scanner 前置）'):format(
  VERSION, tostring(CFG.mode), tostring(CFG.td220), tostring(CFG.proj),
  CFG.yaw360 and '开（默认）' or '关（初始化后，本局不再自动套用）'), true)