# HD2 Scanner API 接口文档

> 适用范围：HD2 Scanner v0.8.0+（AOB 战备表 API 见 §4，v0.8.0 起可用）
> 入口：`_G.HD2Scanner`

---

# 中文

## 0. 概览

`HD2Scanner` 对外提供三类 API：

1. **数据表广播 API**：Scanner 后台定位 LDLD 数据表，把表基址广播给消费者。
2. **通用全量扫描 API (`memscan`)**：消费者提交字节 pattern，Scanner 分片扫描内存并回调命中地址。
3. **AOB 战备表 API**：在 `game.dll` 里解出 `StratagemSettings` 记录指针数组，按 ID 直取记录（§4）。

消费者只读；结构校验、写入、回读都由消费者自己负责。

## 1. 获取接口

```lua
local S = rawget(_G, 'HD2Scanner')
if type(S) ~= 'table' or S.version ~= 1 then return end
```

`HD2Scanner.version` 当前为 `1`。

## 2. 数据表广播 API

### 2.1 `request(type_hash, name)`

订阅一张已知数据表。

```lua
local h = S.request(0x3845B1E0, 'MountComponentData')
```

参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `type_hash` | number | 数据表类型哈希 |
| `name` | string / nil | 可选，日志/诊断用名称 |

返回 handle：

| 字段/方法 | 类型 | 说明 |
|---|---|---|
| `hash` | number | 订阅的 type hash |
| `declare_need()` | function | 请求 Scanner 立刻插队扫描一轮 |
| `cancel()` | function | 取消订阅 |
| `declare_ok()` | function | 空实现，兼容保留 |

建议消费者加载后：

```lua
local h = S.request(RACK_TYPE, 'MountComponentData')
h.declare_need()
```

### 2.2 `poll(type_hash)`

读取广播快照：

```lua
local snap = S.poll(0x3845B1E0)
for _, e in ipairs(snap.entries) do
  print(string.format('addr=0x%X size=%d watched=%s', e.addr, e.size, tostring(e.watched)))
end
print('generation=', snap.generation)
```

返回：

| 字段 | 说明 |
|---|---|
| `entries` | 表副本数组，每项 `{ addr, size, watched? }` |
| `generation` | 快照代号；表地址/副本数变化时递增 |
| `size` | Scanner 已知的期望表大小；不是运行时重新解析的值 |

未订阅/未命中时返回：

```lua
{ entries = {}, generation = 0 }
```

### 2.3 `watch(type_hash, addr)` / `unwatch(type_hash, addr)`

标记/取消标记某个广播条目：

```lua
S.watch(0x3845B1E0, addr)
S.unwatch(0x3845B1E0, addr)
```

⚠️ **兼容占位**：当前版本没有任何消费者会读 `watched`（原先读它的自绘面板已于 2026-10-04 退役），
它**不改变任何行为** —— 定位算法无条件扫描全部已登记的表，与订阅无关。
`request()` / `watch()` / `unwatch()` 保留只为兼容既有消费者，新代码可以不调。

### 2.4 `status()`

返回扫描内核状态表。关键字段：

| 字段 | 说明 |
|---|---|
| `state` | `IDLE` / `PROBING` / `SETTLE` |
| `rounds` | 已完成扫描轮数 |
| `found` | 上一轮命中的表数量 |
| `regions` | 上一轮扫描的区段数 |
| `reads` | 上一轮 ReadProcessMemory 次数 |
| `ms` | 上一轮 CPU 耗时（毫秒） |
| `wall` | 上一轮墙上时间（毫秒） |
| `shard_frames` | 上一轮分片帧数 |
| `last_at` | 上次完成时间 |
| `interval` | 探针周期（秒） |
| `urgent` | 是否有 urgent 挂起 |
| `next_at` | 下次探针时间 |
| `lost` | 掉过的表副本数 |

### 2.5 `published()`

返回当前广播表：

```lua
local pub = S.published()
for hash, slot in pairs(pub) do
  print(hash, slot.name, #slot.entries, slot.generation)
end
```

### 2.6 手动读内存 / 区域枚举

```lua
local bytes = S.read(addr, n)
local regions = S.regions_list()
```

或：

```lua
local bytes = S.api.read(addr, n)
local regions = S.api.regions()
```

`regions_list()` 是**一次性**枚举（`VirtualQuery` 全量），调用有一定开销；
当前发布包内没有消费者在用它（`memscan` 自己内部枚举），保留给排查/自研消费者。

### 2.7 `declare_need()`

不订阅任何表也能催一轮探针（比 `request(...).declare_need()` 更直接）：

```lua
S.declare_need()      -- 置 urgent：下一帧就插队跑一轮
```

Scanner 自己 MOM 面板的「点一下 = 立刻扫一轮」用的就是它。

### 2.8 常用表的字段偏移（实测）

> 偏移都是**记录内相对偏移**；记录长写在括号里。

**`ProjectileWeaponComponentData`** `0x45171B68`（记录 616 B，v0.8.2+）

| 偏移 | 内容 |
|---|---|
| `+0` | `projectile_type`（u32）→ `ProjectileSettings` 的索引 |
| `+4 / +8 / +12` | `rounds_per_minute` x/y/z（**y = 射速**） |
| `+52 / +56 / +60 / +64` | `heat_buildup`（每发积热 / 上限 / 散热速度 / 散热延迟） |
| `+124` | `speed_multiplier` |
| `+128 / +132` | `damage_addends` normal / durable（**本版全 0**） |
| `+136 / +140` | `ap_addends` normal / durable（**本版全 0**） |
| `+572` | `weapon_function_muzzle_velocity`（f32，全表 = 150.0，最好的基准锚） |
| `+576` | `weapon_function_projectile_type`（u32，「模式弹」） |

**`WeaponDataComponentData`** `0x88E4DBB1`（**内存**记录 1232 B；typelib 里写 1216，v0.8.3+）

| 偏移 | 内容 |
|---|---|
| `+168`（8 B） | `function_info` = `{left(u32), right(u32)}`（`WeaponFunctionInfo`） |
| `+176` | `crosshair`（u64） |
| `+1008 / +1016` | `ammo_icon_inner` / `ammo_icon_outer`（u64） |

⚠ 读 `WeaponDataComponentData` 前，消费者的读缓冲上限要 ≥ **462592**（超上限就整表跳过，别硬读）。
⚠ `damage_addends` / `ap_addends` / `speed_multiplier` **本版全是空的**，别当伤害调节入口 —— 改伤害走 `DamageSettings`。

## 3. 通用全量扫描 API (`memscan`)

### 3.1 `scan_request(req)`

```lua
local ok, why = S.scan_request{
  id = 'exo_strat_pkg',
  patterns = {
    { key = 'patriot',     bytes = pkg_le_1 },
    { key = 'emancipator', bytes = pkg_le_2 },
  },
  budget = 8 * 1024 * 1024,
  on_hit  = function(key, addr) end,
  on_done = function(hits) end,
}
```

字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `id` | string | 是 | 唯一请求 ID |
| `patterns` | table | 是 | 数组；每项 `{ key, bytes }` |
| `patterns[i].key` | any | 是 | 回调里回传的 key |
| `patterns[i].bytes` | string | 是 | 原始字节串，长度 1..64 |
| `budget` | number / nil | 否 | 每帧字节预算，默认 8 MB |
| `on_hit` | function / nil | 否 | `on_hit(key, addr)` |
| `on_done` | function / nil | 否 | `on_done(hits)` |

返回：

- `true`：请求已启动或已入队
- `false, reason`：参数非法 / 队列中已有同 ID 请求

### 3.2 回调语义

`on_hit(key, addr)`：

- 命中时立即回调；
- 同一 key 每个地址最多回调一次；
- 每个 key 最多保留 64 个地址；
- 回调运行在 Scanner 的 frame 内，不要在里面做重活或写内存。

`on_done(hits)`：

- 扫描完成时回调；
- `hits[key]` 是该 key 的地址数组；
- 如果请求被取消，则回调 `{ cancelled = true }`。

`hits` 结构：

```lua
{
  patriot = { 0x12345678, 0x23456789, ... },
  emancipator = { ... },
}
```

### 3.3 `scan_cancel(id)`

```lua
S.scan_cancel('exo_strat_pkg')
```

取消正在运行或排队中的请求。

### 3.4 `scan_status(id)`

```lua
local st = S.scan_status('exo_strat_pkg')
```

返回：

| 值 | 说明 |
|---|---|
| `idle` | 没有这个请求 |
| `running` | 正在扫描 |
| `queued` | 已排队 |
| `done` | 上一次请求已完成 |

### 3.5 扫描服务内部行为

- `VirtualQuery` 枚举可读 committed 区段
- 区段按大小降序
- 256 KB 分块，块间重叠，防止 pattern 跨块
- 默认 8 MB/帧
- 每个 pattern 自身地址 +/-4096 跳过，避免扫到自己
- 多请求排队，同一时间只跑一个全量扫描
- 命中只回传地址；结构校验/写入由消费者自己做

## 4. AOB 战备表定位 API

> 适用 HD2 Scanner v0.8.0+。旧版 Scanner 没有这一套，消费者必须先 `type(S.strat_rec) == 'function'` 再调。

`StratagemSettings` 在内存里**不是** LDLD 块，无法用类型哈希广播。Scanner 改为在 `game.dll`
代码段里找一对固定指令（来源：StratagemCooldown 2.1.5），解出**战备记录指针数组**的基址：

```text
49 8B 84 C7 ?? ?? ?? ??   mov rax,[r15+rax*8+disp32]
44 8B 80 C8 00 00 00      mov r8d,[rax+0xC8]
8B C2 45 85 C0            mov eax,edx / test r8d,r8d
```

解析**分帧**推进（2 MB/帧；本机 33 MB 代码段 ≈ 17 帧），调用者不用等。

### 4.1 `strat_table_request()`

请求（或重试）解析。幂等：正在扫 / 已成功都直接返回 `true`。

```lua
local ok, why = S.strat_table_request()
```

### 4.2 `strat_table_status()`

```lua
local st = S.strat_table_status()
```

| 字段 | 说明 |
|---|---|
| `state` | `idle` / `scanning` / `ok` / `failed` |
| `reason` | 失败原因（`failed` 时非空） |
| `base` | `ok` 时为战备记录指针数组基址 |
| `r15` / `consumer` / `disp` | 解链中间量，诊断用 |
| `scanned` / `total` | 已扫 / 需扫字节数 |
| `slots` / `slots_ok` | 结构探针：前 256 个槽位里可读指针个数 |
| `ms` / `frames` | 解析耗时 / 分帧数 |

### 4.3 `strat_table_base()`

`ok` 时返回 `base`，否则 `nil`。

### 4.4 `strat_slot(id)`

```lua
local ptr, why = S.strat_slot(27)
```

`slot_ptr(id) = u64 @ table_base + id*8`，带合理地址校验。`id` 范围 `0..255`。

### 4.5 `strat_rec(id, n)`

```lua
local rec, why = S.strat_rec(27)          -- n 默认 0xD0
local pkg  = rec and rec:sub(0xA9, 0xB0)  -- package
```

读记录前 `n` 字节（`1..0x100`）。已知偏移（typelib）：

| 偏移 | 字段 |
|---:|---|
| `+0x00` | id（= 数组下标） |
| `+0x50` | uses（int32，-1 = 无限） |
| `+0x68` / `+0x6C` | cooldown 成功 / 失败 |
| `+0xA8` | package |
| `+0xB0` | icon |
| `+0xC4` | depends_on（期望 0） |
| `+0xC8` | additional_stratagem |
| `+0xCC` | max_in_loadout（期望 0） |

### 4.6 失败与回退

任何一步不成立都**直接失败**，不猜：

- AOB 命中不唯一（≥ 2 处）
- `disp32` / `lea r15` 锚点读不到
- `table_base` 不在合理地址范围
- 前 256 个槽位里一个可读指针都没有（解出来的不是指针数组）

消费者应当保留兜底路径（ExoLoadout 会退回「全内存搜 package 值」）。
`state == 'failed'` 之后可以再调 `strat_table_request()` 重试。

### 4.7 与广播 API 的关系

AOB 只回答「战备表在哪」。该表不是 LDLD 块，所以不会出现在 `request()` / `poll()`
的广播里，也没有 `generation` —— 表基址变化要消费者自己每秒复核一次记录内容。
## 5. MODS 页分组与成员注册表 API（**v0.8.1 起**）

### 5.1 `HD2Scanner.mom_group`

**字符串**。本仓库所有 mod 在 ModOptionsMenu 里注册选项时统一使用的**分组名**：

```lua
local S = rawget(_G, 'HD2Scanner')
local group = (type(S) == 'table' and type(S.mom_group) == 'string' and S.mom_group ~= '')
              and S.mom_group or 'A HD2 MOD COLLECTION'   -- 旧版 Scanner 兜底：同名硬编码
mom.register_option('mymod.thing', { type = 'toggle', label = '…', mod = group, default = false })
```

为什么必须这样：MOM **只显示前 8 个分组**（`patch_5.lua` 的 `MOD_BUTTONS = 8`），按**大写标题的字节序**
排完后 `while #list > 8 do table.remove(list) end` 直接截断。中文标题一定排在 ASCII 之后 ⇒ 会被**整组砍掉**。
`A HD2 MOD COLLECTION` 以 `A ` 开头（空格 `0x20` < `AC-8` 的 `C` `0x43`），永远排第 1。

⚠ **组内总行数上限 32**（MOM 的 `MAX_ROWS = 32`；第 33 行注册会直接返回 `false`，那一行不会出现）。加行前先算总数。

### 5.2 `register_reset(name, fn)` / `run_resets()` / `reset_names()`

把本 mod 的「初始化」挂到本组的**全局初始化按钮**上（Scanner 组的第 4 行）。

```lua
S.register_reset('机甲', function()
  -- 全部写回原装 + 各自 cfg 复位；必须自己兜异常
end)
```

- `name`：显示用的短名（会出现在全局按钮的描述里，`reset_names()` 会列出它），非空字符串
- `fn`：无参函数。Scanner 用 `pcall` 调，单个失败只记名字、不影响其它成员
- 返回 `true` / `false, reason`；同一个 `name` 重复注册 = 覆盖
- `run_resets()` 返回 `done, failed` 两个数组（都已排序）
- 「初始化」是**全局动作**：装了几个注册过的 mod 就还原几个，不能只还原其中一个

### 5.3 `register_full_scan(name, fn)` / `run_full_scans()` / `full_scan_names()`

同上，挂到本组的**「全内存扫描（兜底）」按钮**上（Scanner 组的第 3 行）。

```lua
S.register_full_scan('机甲', function()
  -- 退回「全内存搜 package 值」这条兜底路径
end)
```

点那个按钮时 Scanner 会依次做三件事：
① 置内核 `urgent`（立刻走一遍完整内存扫描）② 重新解析 AOB 战备表 ③ 调用所有注册的 `fn`。

### 5.4 版本要求与兼容

| API | 最低 Scanner 版本 |
|---|---|
| `strat_table_*` | v0.8.0 |
| `mom_group` / `register_reset` / `register_full_scan` | **v0.8.1** |

旧版 Scanner 没有这些字段 ⇒ 消费商务必先 `type(S.register_reset) == 'function'` 再挂钩，
`mom_group` 则用同名字符串兜底（本仓库各 mod 的做法见 `guard_dog_loadout.lua` 的 `mom_group()`）。

**广播表的版本**：`ProjectileWeaponComponentData` 需 **v0.8.2+**、`WeaponDataComponentData` 需 **v0.8.3+**。
用 `request` / `poll` 拿，拿不到就自己回退 —— 旧版本不会广播它（别假设一定在）。

## 6. 已知数据表类型哈希

| 表 | type_hash |
|---|---:|
| `MountComponentData` | `0x3845B1E0` |
| `HellpodRackComponentData` | `0xA98BB156` |
| `HellpodPayloadComponentData` | `0xDDB5C03F` |
| `WeaponMagazineComponentData` | `0xFB8D88A3` |
| `TurretComponentData` | `0x1EBA7593` |
| `ProjectileWeaponComponentData` | `0x45171B68` |
| `WeaponDataComponentData` | `0x88E4DBB1` |
| `ProjectileSettings` | `0xBD4042C2` |
| `ExplosionSettings` | `0x2AEA2592` |

## 7. 最小消费者示例

```lua
local S = rawget(_G, 'HD2Scanner')
if type(S) ~= 'table' or S.version ~= 1 then return end

local RACK_TYPE = 0x3845B1E0
local h = S.request(RACK_TYPE, 'MountComponentData')

local function frame()
  local snap = S.poll(RACK_TYPE)
  if #snap.entries > 0 then
    local magic = snap.entries[1].addr
    local size = snap.entries[1].size
    -- 消费者在这里自己做校验和写入
  else
    h.declare_need()
  end
end
```

## 8. 界面与消费者的约定（2026-10-04 起）

- ⛔ **不要再注册 `_G.HD2Menu` / `HD2MenuQueue`** —— 那套页面体系（自绘面板 + 对象注册表）
  已整体退役：渲染宿主 `ui.lua` 不再打包，`registry.lua` 已删除。照旧写法注册只会得到一张
  永远不显示的页面（`rawget(_G,'HD2Menu')` 现在是 `nil`）。
- ✅ **界面一律注册原生 `_G.ModOptionsMenu`**（`mom.register_option`）。它只支持
  `toggle` / `choice` / `slider`，**没有只读状态行**；但 `label` / `description` / `choice` 文本
  **可以是函数**，每次打开 ESC 菜单时重算 —— 状态就挂在这两个函数上。
- Scanner 自己在 MODS 页注册了 3 行（供玩家观察/操作，不是给消费者调用的 API）：
  `hd2_scanner.status`（状态 + 点一下立刻扫一轮）· `hd2_scanner.aob`（解析战备表）·
  `hd2_scanner.diag`（把状态写进日志）。

---

# English

## 0. Overview

`HD2Scanner` exposes three API families:

1. **Data table broadcast API**: the background kernel locates LDLD tables and broadcasts their addresses.
2. **Generic full-memory scan API (`memscan`)**: consumers submit byte patterns and receive hit addresses.
3. **AOB stratagem-table API**: resolves the `StratagemSettings` record pointer array from `game.dll` and reads records by id (§4).

The consumer is responsible for validation, writes, and read-back verification.

## 1. Get the interface

```lua
local S = rawget(_G, 'HD2Scanner')
if type(S) ~= 'table' or S.version ~= 1 then return end
```

`HD2Scanner.version` is currently `1`.

## 2. Data table broadcast API

### 2.1 `request(type_hash, name)`

```lua
local h = S.request(0x3845B1E0, 'MountComponentData')
```

Returns a handle:

| Field/Method | Description |
|---|---|
| `hash` | subscribed type hash |
| `declare_need()` | ask Scanner to start an urgent scan now |
| `cancel()` | cancel the subscription |
| `declare_ok()` | no-op, compatibility |

Recommended:

```lua
local h = S.request(RACK_TYPE, 'MountComponentData')
h.declare_need()
```

### 2.2 `poll(type_hash)`

```lua
local snap = S.poll(0x3845B1E0)
for _, e in ipairs(snap.entries) do
  -- e.addr, e.size, e.watched
end
```

Returns:

| Field | Description |
|---|---|
| `entries` | array of `{ addr, size, watched? }` |
| `generation` | snapshot generation; increments when entries change |

If not subscribed or not found:

```lua
{ entries = {}, generation = 0 }
```

### 2.3 `watch` / `unwatch`

```lua
S.watch(type_hash, addr)
S.unwatch(type_hash, addr)
```

**Compatibility placeholder**: nothing reads `watched` any more (the self-drawn panel that used it
was retired on 2026-10-04) and it changes no behaviour - the kernel scans all known tables
regardless of subscriptions. `request()` / `watch()` / `unwatch()` are kept for existing consumers.

### 2.4 `status()`

Returns the kernel state table. Key fields: `state`, `rounds`, `found`, `regions`, `reads`, `ms`, `wall`, `shard_frames`, `last_at`, `interval`, `urgent`, `next_at`, `lost`.

### 2.5 `published()`

Returns the published table map:

```lua
local pub = S.published()
for hash, slot in pairs(pub) do
  -- slot.name, slot.entries, slot.generation
end
```

### 2.6 Raw memory and regions

```lua
local bytes   = S.read(addr, n)
local regions = S.regions_list()

-- aliases
local bytes2   = S.api.read(addr, n)
local regions2 = S.api.regions()
```

`regions_list()` enumerates every readable region once (`VirtualQuery`), so it is not free.
No shipped consumer uses it today (`memscan` enumerates internally); it is kept for diagnostics.

### 2.7 `declare_need()`

Ask for one probe round without subscribing to any table:

```lua
S.declare_need()      -- sets urgent; a round starts on the next frame
```

This is what Scanner's own MODS-page row ("click = scan one round now") uses.

### 2.8 Common field offsets

> All offsets are **relative to the start of a record**; the record size is given in brackets.

**`ProjectileWeaponComponentData`** `0x45171B68` (record 616 B, v0.8.2+)

| Offset | Content |
|---|---|
| `+0` | `projectile_type` (u32) → index into `ProjectileSettings` |
| `+4 / +8 / +12` | `rounds_per_minute` x/y/z (**y = rate of fire**) |
| `+52 / +56 / +60 / +64` | `heat_buildup` (per shot / max / bleed speed / bleed delay) |
| `+124` | `speed_multiplier` |
| `+128 / +132` | `damage_addends` normal / durable (**all 0 in this build**) |
| `+136 / +140` | `ap_addends` normal / durable (**all 0 in this build**) |
| `+572` | `weapon_function_muzzle_velocity` (f32, 150.0 across the whole table) |
| `+576` | `weapon_function_projectile_type` (u32, the "mode projectile") |

**`WeaponDataComponentData`** `0x88E4DBB1` (**in-memory** record 1232 B; typelib says 1216, v0.8.3+)

| Offset | Content |
|---|---|
| `+168` (8 B) | `function_info` = `{left(u32), right(u32)}` (`WeaponFunctionInfo`) |
| `+176` | `crosshair` (u64) |
| `+1008 / +1016` | `ammo_icon_inner` / `ammo_icon_outer` (u64) |

⚠ Before reading `WeaponDataComponentData`, the consumer read cap must be ≥ **462592** (otherwise the table is skipped).
⚠ `damage_addends` / `ap_addends` / `speed_multiplier` are **empty in this build** — do not use them to tune damage; go to `DamageSettings`.

## 3. Generic full-memory scan API (`memscan`)

### 3.1 `scan_request(req)`

```lua
local ok, why = S.scan_request{
  id = 'exo_strat_pkg',
  patterns = {
    { key = 'patriot',     bytes = pkg_le_1 },
    { key = 'emancipator', bytes = pkg_le_2 },
  },
  budget = 8 * 1024 * 1024,
  on_hit  = function(key, addr) end,
  on_done = function(hits) end,
}
```

Fields:

| Field | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | unique request id |
| `patterns` | table | yes | array of `{ key, bytes }` |
| `patterns[i].key` | any | yes | passed back to callbacks |
| `patterns[i].bytes` | string | yes | raw byte string, length 1..64 |
| `budget` | number / nil | no | bytes per frame, default 8 MB |
| `on_hit` | function / nil | no | `on_hit(key, addr)` |
| `on_done` | function / nil | no | `on_done(hits)` |

Returns:

- `true`: started or queued
- `false, reason`: invalid request or duplicate queued id

### 3.2 Callback semantics

`on_hit(key, addr)`:

- called immediately on a hit
- each address is reported once per key
- up to 64 addresses per key
- runs inside Scanner frame; keep it short and do not write memory here

`on_done(hits)`:

- called when the scan finishes
- `hits[key]` is an array of addresses
- on cancel: `{ cancelled = true }`

`hits` shape:

```lua
{
  patriot = { 0x12345678, ... },
  emancipator = { ... },
}
```

### 3.3 `scan_cancel(id)`

Cancels a running or queued request.

### 3.4 `scan_status(id)`

Returns one of: `idle`, `running`, `queued`, `done`.

### 3.5 Internal behavior

- enumerates readable committed regions with `VirtualQuery`
- sorts regions by size descending
- 256 KB chunks with overlap
- 8 MB per frame by default
- skips each pattern's own copies within +/-4096
- requests are queued; one full scan at a time
- returns addresses only; the consumer validates and writes

## 4. AOB stratagem-table API

> Requires HD2 Scanner v0.8.0+. Older Scanner builds do not have it — consumers must check
> `type(S.strat_rec) == 'function'` before calling.

`StratagemSettings` is **not** an LDLD block, so it cannot be broadcast by type hash.
Scanner instead finds a fixed instruction pair inside `game.dll`'s code sections
(source: StratagemCooldown 2.1.5) and resolves the **stratagem record pointer array**:

```text
49 8B 84 C7 ?? ?? ?? ??   mov rax,[r15+rax*8+disp32]
44 8B 80 C8 00 00 00      mov r8d,[rax+0xC8]
8B C2 45 85 C0            mov eax,edx / test r8d,r8d
```

Resolution is **stepped across frames** (2 MB/frame; ~17 frames for the 33 MB code section here),
so callers never block.

### 4.1 `strat_table_request()`

Starts (or retries) resolution. Idempotent: scanning/ok both return `true`.

### 4.2 `strat_table_status()`

| Field | Description |
|---|---|
| `state` | `idle` / `scanning` / `ok` / `failed` |
| `reason` | failure reason (non-nil when `failed`) |
| `base` | pointer-array base when `ok` |
| `r15` / `consumer` / `disp` | intermediate values, for diagnostics |
| `scanned` / `total` | bytes scanned / to scan |
| `slots` / `slots_ok` | structural probe: readable pointers among the first 256 slots |
| `ms` / `frames` | resolution time / frame count |

### 4.3 `strat_table_base()`

Returns `base` when `ok`, else `nil`.

### 4.4 `strat_slot(id)`

```lua
local ptr, why = S.strat_slot(27)
```

`slot_ptr(id) = u64 @ table_base + id*8`, with a plausibility check. `id` range `0..255`.

### 4.5 `strat_rec(id, n)`

```lua
local rec, why = S.strat_rec(27)          -- n defaults to 0xD0
local pkg  = rec and rec:sub(0xA9, 0xB0)  -- package
```

Reads the first `n` bytes of the record (`1..0x100`). Known offsets (typelib):

| Offset | Field |
|---:|---|
| `+0x00` | id (= array index) |
| `+0x50` | uses (int32, -1 = unlimited) |
| `+0x68` / `+0x6C` | cooldown success / fail |
| `+0xA8` | package |
| `+0xB0` | icon |
| `+0xC4` | depends_on (expected 0) |
| `+0xC8` | additional_stratagem |
| `+0xCC` | max_in_loadout (expected 0) |

### 4.6 Failure and fallback

Every step fails loudly instead of guessing:

- the AOB matched more than once
- `disp32` / `lea r15` anchor unreadable
- `table_base` implausible
- no readable pointer among the first 256 slots (it was not a pointer array)

Consumers should keep a fallback path (ExoLoadout falls back to a full-memory
`package` value search). After `state == 'failed'`, `strat_table_request()` may be called again.

### 4.7 Relation to the broadcast API

The AOB path only answers "where is the stratagem table". The table is not an LDLD
block, so it never appears in `request()` / `poll()` and has no `generation` — consumers
re-validate the record contents themselves.
## 5. MODS-page group & member registries (since v0.8.1)

### 5.1 `HD2Scanner.mom_group` (string)

The single group name every mod from this repo registers its ModOptionsMenu options under:

```lua
local S = rawget(_G, 'HD2Scanner')
local group = (type(S) == 'table' and type(S.mom_group) == 'string' and S.mom_group ~= '')
              and S.mom_group or 'A HD2 MOD COLLECTION'   -- fallback for older Scanner
mom.register_option('mymod.thing', { type = 'toggle', label = '…', mod = group, default = false })
```

Why: MOM shows **only the first 8 groups** (`MOD_BUTTONS = 8`), sorted by the *upper-cased* title and then truncated.
CJK titles always sort after ASCII, so such a group gets dropped entirely. `A HD2 MOD COLLECTION` starts with `A `
(space `0x20` < `C` `0x43`) so it is always group #1.

⚠ **Max 32 options per group** (`MAX_ROWS = 32`); registering a 33rd returns `false` and the row never appears.

### 5.2 `register_reset(name, fn)` / `run_resets()` / `reset_names()`

Hooks the mod's "initialise" into the group's **global reset button** (row 4).

- `fn` is called with no arguments inside `pcall`; failing members are reported by name only.
- `run_resets()` returns sorted `done, failed` arrays. It is a **global** action — it resets every registered mod.

### 5.3 `register_full_scan(name, fn)` / `run_full_scans()` / `full_scan_names()`

Hooks the mod's fallback full-memory search into the group's **"full memory scan" button** (row 3).
Pressing it: ① raises the kernel `urgent` flag, ② re-parses the AOB stratagem table, ③ calls every registered `fn`.

### 5.4 Compatibility

`mom_group` / `register_reset` / `register_full_scan` require **Scanner v0.8.1+**.
Always probe `type(S.register_reset) == 'function'` before hooking; fall back to a hard-coded group name otherwise.

**Broadcast tables**: `ProjectileWeaponComponentData` needs **v0.8.2+**, `WeaponDataComponentData` needs **v0.8.3+**.
Use `request` / `poll` and fall back yourself when it is missing (older builds do not broadcast it).

## 6. Known type hashes

| Table | type_hash |
|---|---:|
| MountComponentData | `0x3845B1E0` |
| HellpodRackComponentData | `0xA98BB156` |
| HellpodPayloadComponentData | `0xDDB5C03F` |
| WeaponMagazineComponentData | `0xFB8D88A3` |
| TurretComponentData | `0x1EBA7593` |
| ProjectileWeaponComponentData | `0x45171B68` |
| WeaponDataComponentData | `0x88E4DBB1` |
| ProjectileSettings | `0xBD4042C2` |
| ExplosionSettings | `0x2AEA2592` |

## 7. Minimal consumer example

```lua
local S = rawget(_G, 'HD2Scanner')
if type(S) ~= 'table' or S.version ~= 1 then return end

local RACK_TYPE = 0x3845B1E0
local h = S.request(RACK_TYPE, 'MountComponentData')

local function frame()
  local snap = S.poll(RACK_TYPE)
  if #snap.entries > 0 then
    local magic = snap.entries[1].addr
    local size  = snap.entries[1].size
    -- validate and write here
  else
    h.declare_need()
  end
end
```

## 8. UI contract for consumers (since 2026-10-04)

- ⛔ **Do not register `_G.HD2Menu` / `HD2MenuQueue` any more.** That page system (self-drawn panel +
  object registry) is retired: its renderer `ui.lua` is no longer packaged and `registry.lua` is gone.
  Registering anyway just creates a page that can never be shown (`rawget(_G,'HD2Menu')` is now `nil`).
- ✅ **Register into the native `_G.ModOptionsMenu`** (`mom.register_option`). It only supports
  `toggle` / `choice` / `slider` - there is **no read-only status row** - but `label`, `description`
  and each `choice` may be **functions**, re-evaluated whenever the ESC menu opens. Park status there.
- Scanner itself registers 3 rows on the MODS page (for players, not a consumer API):
  `hd2_scanner.status` (state + click to scan one round now), `hd2_scanner.aob`,
  `hd2_scanner.diag` (dump state to the log).
