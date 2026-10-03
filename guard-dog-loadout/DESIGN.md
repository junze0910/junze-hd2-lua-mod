# 护卫犬挂载自选（guard_dog_loadout）· 设计

> 状态：**v1.0.1 已实现并离线验证（86/86）**，待实机
> 参照实现：`exo-loadout/exo_loadout.lua` 的**手臂改造**那一条腿（Scanner → MountComponentData）
> 取代：`guard-dog-mg43`（只能写死 MG-43）

## 一、目标

把机枪犬 `drone_mg` 的**挂载武器**（`MountComponentData` 记录槽 0 的 item）做成三选一：

| 选项 | 写入值 | 语义 |
|---|---|---|
| **AR-23P（原装）** | `A32621E3BDE13379` | **不改写**：本来就是原装就零写入；之前被改过就写回原装 |
| **MG-43（SEAF）** | `587878FB76F4B9B1` | 与旧 mod 相同效果 |
| **自定义（读 cfg）** | 用户填的 16 位 BE hex | cfg 为空 / 非法 / 全 0 → **拒写**，日志与面板写明原因 |

> 用户拍板：「原装就是不改写」——AR-23P 只是给玩家看的叫法，它的写入目标是原装哈希本身。
> **与机甲 mod 的差异**：护卫犬只动 8 字节，不碰 `StratagemSettings`、不碰 `use`/冷却。

## 二、实测数据（2026-10 用户提供，已与真表 dump 交叉验证）

| 项 | 值 | 来源 |
|---|---|---|
| 挂载母体（drone_mg 实体哈希） | `A0FF2F9A0CA6992A` | 用户给的十进制 `11601043503813400874` |
| recIdx | `97` | 用户给的「挂载ID」 |
| 挂载位点 node（记录 +8） | `0x53BEC437` = `1405010999` | 用户给的「挂载位点」；也是旧 mod 的 12 字节锚点尾 |
| 原装 item（记录 +0） | `A32621E3BDE13379`（`.../drone_mg/drone_mg_weapon`） | 真表记录 97 |
| SEAF MG-43 item | `587878FB76F4B9B1` | 旧 mod 实测常量 |

真表（`test/fixture_gd.lua` 镜像，24592 B 的版本）：

```
size = 24592   索引 322 条   记录 162 条   记录区起点 = 322*16 = 5152
drone_mg 索引条目在 index[300]：ent=A0FF2F9A0CA6992A  recIdx=97  pad=0（全表唯一）
记录 97 槽 0：+0 item / +8 node=0x53BEC437 / +12 pad=0 / 槽 1~4 全空
```

## 三、Scanner 契约（硬前置）

```lua
local S = rawget(_G, 'HD2Scanner')            -- 要求 S.version == 1 且 S.poll 是函数
S.request(0x3845B1E0, '护卫犬挂载自选')        -- 订阅 MountComponentData
local pub = S.poll(0x3845B1E0)                -- { entries = {{addr, size}}, generation = n }
```

- 消费者**自己做全部校验**（Scanner 定稿 §三 红线 3）
- 没有 Scanner 且未开回滚 → 零写入、不崩、日志明说（每 60 秒重试）
- `_G.GD_USE_SELF_SCAN = true` → 回滚到自扫（见 §六）

## 四、定位与写入（与机甲同构）

1. `validate_table(magic)`：`LDLD` + version==1 + `0x3845B1E0`；size 只做区间检查（**不当指纹**）
2. `layout_cands(data, size)`：纪录区起点 = 16 的倍数 `b`，`(size-b)%120==0`，且索引区每条 `pad==0`、`recIdx<n`
3. **只取最大的那个合法候选**（见 §五）
4. `find_rec`：索引区按 drone_mg 实体哈希的 LE 字节串 → `recIdx`
5. 记录地址 = `magic + 24 + base + recIdx*120`；**复核** `+8 == 0x53BEC437` 且 `+12 == 0`
6. **写入保护（SKILL 6.24）**：只认「原装」「本次目标」「**上次自己写过的值**」
   （`state.slots[addr].item`），其余一律拒写并记日志（日志里指向「初始化」）。
   **唯一的例外是原装**：写回原装永远放行 —— 否则玩家从旧的 `guard-dog-mg43` 切过来时
   （内存里已是 MG-43 = 陌生值）会被自己的保护困死，永远回不到原装。
   `state.slots[addr] = { item = 目标, orig = 原装 }`，`orig` 供初始化恢复。
7. 写 `+0` 的 8 字节 + **回读校验**；失败一律记 refusal

**节奏**：Scanner 代际变化时立刻应用；**cfg 热重读 / 面板改选项会把 `last_gen` 置 -1**，
所以下一帧就按新配置写一遍（不等 60 帧）；之后每 60 帧复扫一遍；每 300 帧 `recheck()` 把被冲掉的补丁重写。

### 4.1 初始化（SKILL 6.25）：回原始默认，不是回上次 cfg

`do_initialize()` 的顺序：

1. `restore_vanilla_all()` —— 所有 tracked 槽位写回 `orig`
2. `apply_snap(S.poll(...), VANILLA, 'vanilla', **force = true**)` —— `vanilla_force`：
   只校验 node/pad/recIdx，**当前值不论是什么都强写**（否则"陌生值拒写"会让初始化实际不生效）
3. cfg 复位 `weapon=ar23p, custom=''`
4. 清空运行时状态（slots / layout / rec_ix），`last_gen = -1` 让下一帧重扫
5. `cfg_save()` 落盘 —— **初始化不读** `GuardDogLoadout.cfg`（上次退出的 cfg 是错误语义）
6. 同步 `ModOptionsMenu`（选项回第 1 项、开关关掉）

## 五、⚠ 为什么"只认最大候选"（本 mod 唯一的坑）

记录区起点比真值**小 240 字节**（= 2 条记录 = 15 个索引条目）时，"索引区"退化成真索引的**前缀**，
`layout_cands` 仍然判它合法 —— 而同一个 `recIdx` 会指到**早两条的另一个记录**。
那个记录往往**共用同一个 node**（node 是"槽位类型"不是实体指纹，很多记录都填 `0x53BEC437`），
所以 node/pad 复核抓不住它，会**悄悄写错记录**。

判据：从真起点再往上扩 15 个条目，第 1 个伪条目就落在记录区偏移 0，
它的 `+8` 是 node（1e9 量级）必然 `>= 记录数` → 那一档候选一定被 `layout_cands` 否掉。
**所以"最大合法候选" = 真起点。**

（真表镜像实测：`4912` 与 `5152` 都"合法"，只有 `5152` 指向 drone_mg 的 97 号记录。
`test_gd_loadout.py` 用例 7 用"把记录 97 的 node 改坏"钉住了这个行为：必须**拒写**，不能回退。）

## 六、自扫回滚（`GD_USE_SELF_SCAN`）

没有 Scanner 时的兜底，**复用同一条 `apply_mount`**：分片扫所有可读区域找 `LDLD` 表头，
校验通过就按 §四走。每帧最多读 4 MB，两轮之间隔 30 秒（全扫很贵，真正的数据源是 Scanner）。

## 七、cfg

`%LOCALAPPDATA%\CowboyBingus\Helldivers2\GuardDogLoadout.cfg`，**改完 1 秒热生效**：

```
weapon=ar23p        # ar23p（原装/不改写） | mg43（SEAF） | custom（读下面那行）
custom=             # 16 位 BE 十六进制（物品哈希 u64）。留空 = 自定义项不可用
```

内置项与自定义项互不覆盖：切回内置项时 `custom` 的值留在 cfg 里。

**自定义值的门槛（实测）**

| 写法 | 结果 |
|---|---|
| `custom=587878FB76F4B9B1` / 小写 / 前后空格 / 行尾 `# 注释` | ✅ 生效 |
| `weapon=ar23p` 但 `custom=` 有值 | ✅ **不参与**，内置项零写入（不会误写） |
| `custom=0x587878FB…`（带前缀）/ 长度不足 / 全 0 / 空 / 整行缺失 | ✅ **拒写**：零写入 + 日志写明原因 + 保持当前值 |
| cfg 里另有未知键（`foo=bar`）或注释 | ✅ 忽略，不影响解析 |

- ⚠ **格式对 ≠ 能用**：本 mod **不校验哈希的含义**（那是玩家的责任）。
  填一个不存在/不适配的 item 哈希，会真的写进挂载槽 → 狗可能召唤异常。
- ⚠ **BOM**：PS 5.1 的 `Set-Content -Encoding UTF8` 会写 BOM，落在 `weapon=` 行上会让整行解析失败。
  mod 已**自动剥 BOM**（`test_gd_loadout.py` 用例 20 钉住），但更稳的做法是用不写 BOM 的编辑器。
- ⚠ **注释会被保住了**：`cfg_save` 现在写的是带说明的完整模板（以前只写 3 行裸键），
  所以面板上改一次选项/点初始化，文件里的填写说明不会消失。

## 八、设置入口

| 入口 | 状态 | 内容 |
|---|---|---|
| `ModOptionsMenu` 原生 MODS 页 | ✅ **主入口** | 「下挂物品」三选一 + 「初始化」开关；**选项的 `description` 里给出 cfg 的完整路径** |
| 直接手改 cfg | ✅ 一直可用 | 1 秒热重读；文件里带填写说明 |
| ~~Scanner 插件页（`_G.HD2Menu`）~~ | ⛔ **已删除** | 2026-10-04 随 `_G.HD2Menu` 页面体系整体退役（渲染宿主 `ui.lua` 不再打包）。原来那一页的内容 = 同样的下拉 + 立刻写一次 + 初始化 + 三档诊断；**下拉与初始化现在都在 MODS 页**，诊断看 `GuardDogLoadout.log` |

> 本 mod 的写入是**自动**的（改配置就立刻写、每 300 帧复查），所以核心功能**不依赖任何 UI** ——
> 没有 ModOptionsMenu 也能靠手改 cfg 用。

> **2026-10-03 变更**：HD2 Scanner 移除了浮动面板（并默认不抢 ESC 页签），`_G.HD2Menu` 仍然导出但没有渲染器。
> 因此对外文档（`STORE-PAGE.zh.md` / `.en.md`）**不再提** Scanner 面板这条入口，UI 一律指 MODS 页。
>
> **2026-10-04 变更**：`_G.HD2Menu` 与 `registry.lua` **整体退役**，本 mod 的页面代码已删除。
> 全仓库现在**只注册 ModOptionsMenu**；新 mod 不要再写 `menu.register` / `HD2MenuQueue`。

### 8.1 cfg 路径写在「右边的描述页」

自定义哈希**必须**改 cfg 文件，所以「该改哪个文件」得让玩家一眼看到。做法与机甲 mod 一致：
`mom.register_option{ ..., description = '...' }` —— 描述是选项表里的一个字段，渲染在右侧描述页。
本 mod 把 `CFG_FILE`（由 `loader.log_directory` 推出的**绝对路径**）拼进「下挂物品」的描述里：

```
AR-23P = 原装（不改写）；MG-43 = SEAF。自定义 = 读 cfg 文件
C:\Users\<你>\AppData\Local\CowboyBingus\Helldivers2\GuardDogLoadout.cfg
的 custom 行（16 位 BE 十六进制物品哈希；留空则该选项不可用）。改完 1 秒热生效。
```

（`test_gd_loadout.py` 用例 16 用假 `loader.log_directory` 把这条链路钉住了。）

> **自定义哈希不做文本框**：ModOptionsMenu 只支持开关 / 固定选项，**不支持自由文本输入**
> （HD2 Scanner 那套面板也是纯鼠标的 —— `ui.lua` §16：面板吃不掉键盘事件，Backspace/Enter
> 会穿透到 ESC 菜单）。所以自定义值只能从 cfg 读，这正是用户方案的意思。

## 九、红线

- 只写目标记录 `+0` 的 8 字节，其余 112 字节一字不动（用例 2 逐字节钉住）
- 写入保护只放行「原装 / 本次目标 / 上次自己写过的值」，陌生值拒写（用例 18）
- 连续换目标必须能写（原装 → A → B，用例 17）；初始化必须能强制回原装（用例 19）
- 写前 `VirtualProtect`、写后回读校验；失败记 refusal，绝不当成功
- 不碰其它记录、其它表；不写任何 UI 结构

## 十、产物

```
junze-hd2-lua-mod/guard-dog-loadout/guard_dog_loadout.lua   （源码，VERSION 单源）
build/GuardDogLoadout-v1.0.1.zip                            （打包产物，SHA256 686DC8B0…）
_probe/test_gd_loadout.py                                   （86 项离线回归：定位/保护/连续换目标/初始化/cfg 边界/源码卫生）
tools/build_mod.py  MODS["guard_dog_loadout"]
```

## 十一、待办

- **实机验证**：装 `HD2-Scanner` + `GuardDogLoadout-v1.0.1.zip`，进任务 → 看
  `Logs\GuardDogLoadout.log`（应出现「已接上 HD2Scanner」+「已写：drone_mg 挂载 …」）
  与 `GuardDogLoadout_STATUS.log`；再换 MG-43 / 自定义各试一次
- 实机确认后：把 `guard-dog-mg43` 归档（包名/目录都退成归档，避免两个 mod 抢同一记录）
- `dist/` 同步欠账（与本 mod 一起补）