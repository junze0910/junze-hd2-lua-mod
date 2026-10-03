# HD2 Scanner API 接口文档

> 适用范围：HD2 Scanner v0.7.0+
> 入口：`_G.HD2Scanner`

---

# 中文

## 0. 概览

`HD2Scanner` 对外提供两类 API：

1. **数据表广播 API**：Scanner 后台定位 LDLD 数据表，把表基址广播给消费者。
2. **通用全量扫描 API (`memscan`)**：消费者提交字节 pattern，Scanner 分片扫描内存并回调命中地址。

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

当前版本中 `watched` 主要供诊断/UI 状态使用，不改变定位算法。

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

## 4. 已知数据表类型哈希

| 表 | type_hash |
|---|---:|
| `MountComponentData` | `0x3845B1E0` |
| `HellpodRackComponentData` | `0xA98BB156` |
| `HellpodPayloadComponentData` | `0xDDB5C03F` |
| `WeaponMagazineComponentData` | `0xFB8D88A3` |
| `TurretComponentData` | `0x1EBA7593` |
| `ProjectileSettings` | `0xBD4042C2` |
| `ExplosionSettings` | `0x2AEA2592` |

## 5. 最小消费者示例

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

---

# English

## 0. Overview

`HD2Scanner` exposes two API families:

1. **Data table broadcast API**: the background kernel locates LDLD tables and broadcasts their addresses.
2. **Generic full-memory scan API (`memscan`)**: consumers submit byte patterns and receive hit addresses.

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

Marks an entry as watched. Currently used for diagnostics/UI state.

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

## 4. Known type hashes

| Table | type_hash |
|---|---:|
| MountComponentData | `0x3845B1E0` |
| HellpodRackComponentData | `0xA98BB156` |
| HellpodPayloadComponentData | `0xDDB5C03F` |
| WeaponMagazineComponentData | `0xFB8D88A3` |
| TurretComponentData | `0x1EBA7593` |
| ProjectileSettings | `0xBD4042C2` |
| ExplosionSettings | `0x2AEA2592` |

## 5. Minimal consumer example

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