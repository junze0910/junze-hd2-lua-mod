# Junze's HD2 Lua Mods（君则的 HD2 Lua Mod）

Unofficial **runtime memory patches** for Helldivers 2 — no game files are modified.

| Mod (name shown in mod managers) | Tag | What it does |
|---|---|---|
| **AC-8 Cut-Content 75rnd Backpack** | — | Swaps the AC-8 autocannon's rack backpack for the **cut-content 75-round spare backpack** (vanilla: 50 rounds) |
| **Stronger Kinetic Guard Dog** | — | Swaps the guard dog's mounted weapon for the **SEAF MG-43** (kinetic), for stronger firepower |
| **TD-110 Co-Op** | — | Widens the TD-110 storm tank's laser designator yaw to **±180°**, and swaps the two mount slots (gunner ← smoke launcher, driver ← laser designator) |
| **Busier TD-110 Driver** | — | Alternative to TD-110 Co-Op: replaces the TD-110 driver-slot **smoke launcher** with a **manually-operated heavy MG turret** (pick one of the two — they touch the same slot) |
| **More Balanced Exosuit - Patriot** | — | Exosuit arm swap (see below), **plus**: carrying the **Patriot** exosuit stratagem also gives you the **Emancipator** one — and **both exosuits get 1 use / 0 cooldown** |
| **More Balanced Exosuit - Emancipator** | — | Same arm swap, **plus**: carrying the **Emancipator** stratagem also gives you the **Patriot** one — **both exosuits get 1 use / 0 cooldown** (pick **one** of these two — running both crashes the stratagem list) |
| **No Large Piercing** | **Optimization** | Rewrites every **large-piercing hit-effect tier** (`HitEffectDamageType` `3` `PiercingLarge` / `4` `PiercingLargeHEAT`) to **`0` `None`** — no large-piercing impact FX at all |
| **No Large Piercing (Medium)** | **Optimization** | Same rewrite, but to **`2` `PiercingMedium`** — downgrades the tier instead of removing it (**pick one** of these two) |

Ready-to-install packages: [`dist/`](dist/) (prebuilt zip) · source code in each subfolder.

> **Tags.** `Optimization` is the only tag so far — it currently holds the two **No Large Piercing** variants. Other mods are untagged on purpose.

> 中文说明见下方。**当前版本 v1.3（模组合集，8 个 mod）**：前四个 + 外骨骼 v1.1 + **No Large Piercing 两版**均已实机验证；两对二选一（TD-110 Co-Op / 更忙的驾驶员、外骨骼爱国者版 / 解放者版）、以及 **No Large Piercing / 中口径版** 见下表。

《绝地潜兵 2》(Helldivers 2) 自研 Lua 内存补丁合集。**不修改任何游戏文件**，只在游戏运行时改写内存里的数据表。

## Mod 一览

| Mod（管理器内显示的英文名） | 中文名 | 分类 | 作用 |
|---|---|---|---|
| **AC-8 Cut-Content 75rnd Backpack** | **AC-8 废案 75 发备弹背包（替换原 50 发背包）** | — | 把战备「AC-8 机炮」包架上的背包，从原版 50 发备弹换成**废案版本的 75 发备弹背包** |
| **Stronger Kinetic Guard Dog** | **更强的实弹狗** | — | 把机枪犬 `drone_mg` 挂载的武器换成 **SEAF MG-43（实弹）**，火力更强 |
| **TD-110 Co-Op** | **更强调合作的 TD-110** | — | 把暴风漩涡坦克（TD-110）激光指示器的水平射界从 ±20° 放宽到 **±180°**，并把两个挂载位**按位置对调**：炮手位换成烟雾弹、驾驶员位换成激光指示器 |
| **Busier TD-110 Driver** | **更忙的 TD-110 驾驶员** | — | TD-110 Co-Op 的**替代方案**：把驾驶员位（`+48`）的**烟雾弹发生器**换成**手操重机枪炮台**（可被驾驶员操作的实弹炮台）。与 TD-110 Co-Op **二选一** |
| **More Balanced Exosuit - Patriot** | **更均衡的爱国者/解放者外骨骼 · 携带爱国者版** | — | **携带爱国者外骨骼战备时，额外携带解放者外骨骼战备**；另有挂载对调 + 两台外骨骼可用次数 1、冷却 0 |
| **More Balanced Exosuit - Emancipator** | **更均衡的爱国者/解放者外骨骼 · 携带解放者版** | — | **携带解放者外骨骼战备时，额外携带爱国者外骨骼战备**；另有挂载对调 + 两台外骨骼可用次数 1、冷却 0。与上一行**二选一**（同时装会战备套娃崩溃） |
| **No Large Piercing** | **没有大型穿刺** | **优化** | 把数据表里所有**大型穿刺命中特效档**（`HitEffectDamageType` = `3` `PiercingLarge` / `4` `PiercingLargeHEAT`）改写为 **`0` `None`** —— 完全不再播放大型穿刺命中特效 |
| **No Large Piercing (Medium)** | **没有大型穿刺（中口径版）** | **优化** | 同样的改写，但目标值改为 **`2` `PiercingMedium`** —— 降档而不是移除。与上一行**二选一** |

> **分类（Tags）**：目前只设了「**优化**」一个标签，里面只有 **No Large Piercing** 两个版本（改大型穿刺命中特效）。
> 其余 mod 暂不归类。

> 命名说明：mod 管理器会把 manifest 里的 `Name` 当文件夹名用，因此包内使用**纯 ASCII 名**（避免导入时出现"目标名/目录名或卷标语法不正确"）；中文名见上表。

八个 mod 的实机/仿真状态：前四个（AC-8、实弹狗、TD-110 Co-Op、更忙的驾驶员）均已在 **2026-09-25** 实机验证（日志首行 `OK - 补丁生效中（N 处）`，连续运行 40 分钟以上保持生效）；**No Large Piercing 两版均在 2026-09-25 实机验证通过**（`NoLargePiercing.log` 出现 `已回读验证通过`，射弹表 102 条 + 爆炸表 4 条 `3`/`4` 档归零）；外骨骼「携带爱国者版」的挂载 + 战备附加原型已在实机验证通过，**外骨骼 v1.1 的「可用次数 → 1、冷却 → 0」也已实机验证**；「携带解放者版」的附加方向与两版的二选一保护为**离线仿真验证**（4 场景 × 14 项全过，见 `more-balanced-exosuit/DESIGN.md`）。外骨骼两版（相同部分）：挂载 **EXO-49 右臂 → 爱国者加特林炮塔**、**EXO-45 左臂 → 左臂加农炮**；两台外骨骼 **可用次数 `use` 3 → 1**、**冷却 `cooldown_duration_success` 420.0 → 0.0**（`use` 只写一次，用掉就没了）。

## 依赖

* **Bingus Shared Loader v15 或更高**（loader 日志首行为 `Bingus Shared Loader loader-v1x; API 1`）
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）

## 安装

1. 从 [`dist/`](dist/) 目录下载 zip（也可在 [Releases](../../releases) 里找到同一份）：

   | 文件 | Mod |
   |---|---|
   | `AC8-Rack-Backpack-v1.0.zip` | AC-8 废案 75 发备弹背包 |
   | `Guard-Dog-MG43-v1.0.zip` | 更强的实弹狗 |
   | `TD-110-Co-Op-v1.0.zip` | 更强调合作的 TD-110 |
   | `TD-110-Busier-Driver-v1.0.zip` | 更忙的 TD-110 驾驶员（与上一个**二选一**） |
   | `More-Balanced-Exosuit-Patriot-v1.1.zip` | 更均衡的外骨骼 · **携带爱国者版**（携带爱国者战备 → 额外携带解放者战备；可用次数 1、冷却 0） |
   | `More-Balanced-Exosuit-Emancipator-v1.1.zip` | 更均衡的外骨骼 · **携带解放者版**（携带解放者战备 → 额外携带爱国者战备；可用次数 1、冷却 0）。与上一个**二选一** |
    | `No-Large-Piercing-v1.0.zip` | 没有大型穿刺（大型穿刺档 → `0` None，完全不打） |
    | `No-Large-Piercing-Medium-v1.0.zip` | 没有大型穿刺 · 中口径版（大型穿刺档 → `2` PiercingMedium）。与上一个**二选一** |
2. 用 mod 管理器导入并启用（**不要手动把 `Addon/` 拷进 `data/`** —— 多个 addon 的包内文件名相同，会互相覆盖）；
   * 本次版本的完整说明（含 TD-110 Co-Op 的时序规则）见 [`RELEASE-NOTES.md`](RELEASE-NOTES.md)；
   * 下载包校验：`dist/SHA256SUMS.txt`——
     `cd dist; certutil -hashfile TD-110-Co-Op-v1.0.zip SHA256`（Git Bash：`sha256sum -c SHA256SUMS.txt`）；
3. 进游戏。数据表是在任务里按需加载的，一般进图后约 1 分钟生效。
   * **装 `TD-110 Co-Op` 时有一条额外规则**：挂载表（`MountComponentData`）是**生成载具时读一次**的静态配置，
     补丁必须**早于召唤载具** —— 进任务后先等 `TankStormCoop.log` 出现
     `挂载补丁已就绪：现在可以召唤 / 重新召唤载具了`（或 `TankStormCoop_STATUS.log` 里 `挂载状态 = 已就绪 ✓`），**再**召唤坦克。
     （同一 mod 里的射界改动是引擎**实时读**的，不需要等。）
   * ⚠ 与任何同样改写 TD-110 驾驶员挂载位（`+48`）的 mod **二选一**（例如 `TD-110 Better Driver Armament`）。
   * **装外骨骼 mod 时同样要等**：挂载表是「生成载具时读一次」、战备表只在任务里加载 —— 进任务后先等
     `BalancedExosuitPatriot_STATUS.log`（或 `BalancedExosuitEmancipator_STATUS.log`）出现
     `三处改动均已就绪：现在可以召唤 / 重新召唤载具了`，**再**召唤外骨骼。
   * ⚠ 外骨骼**两版二选一**：两条战备记录同时被写成非 0 会形成「战备互相附加」（套娃）并在列表生成时崩溃。
     包里带运行时保护（检测到对向版已生效就拒写并写日志），但**请只装一个**。
4. 检查日志：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`
   * `AC8RackBackpack_STATUS.log`
    * `NoLargePiercing.log`（No Large Piercing：射弹 + 爆炸两张表）
   * `GuardDogMg43_STATUS.log`
   * `TankStormCoop_STATUS.log`（射界 + 挂载）
   * `BalancedExosuitPatriot_STATUS.log` / `BalancedExosuitEmancipator_STATUS.log`（外骨骼：挂载 + 战备附加）

   第一行为 `OK - 补丁生效中（N 处）` 即表示成功。

## 技术要点（为什么这些 mod 不怕小版本更新）

旧做法的通病是把"表大小 / 索引条数 / 记录下标"写死当指纹，游戏一更新就**静默失效**（一个字节都不写、界面上毫无提示）。本项目的 addon 一律：

1. **只认签名**：`LDLD` + `u32 版本(=1)` + `u32 djb2(类型名)`，表大小只做 1024~4MB 的合理区间检查；
2. **内容锚点定位**：用目标字段自身的哈希定位（例如 AC-8 用旧背包哈希 + "命中点往前 64/192 字节必须是机炮本体"这个上下文校验），完全不依赖表布局；
3. **多副本全打**：内存里同类型表可能有多份，只打第一份会出现"用一阵子就失效"；
4. **持续维护**：5 秒逐地址复查、30 秒扫"已知副本 ±32KB"、10 分钟全量兜底；
5. 写前 `VirtualProtect`、写后**回读校验**；任何校验不通过只记日志、绝不写入；
6. **静态配置表要抢在实体生成前打**：`MountComponentData` 这类"生成时读一次"的表，补丁晚于召唤就完全没效果
   （表现为"写进去了、回读也对、游戏完全不理会"）。做法：没进任务前只在舰船上做便宜采样（12 个最大区域 × 8 MB，5 秒一轮），
   一采样到 LDLD 表立刻转"全量 + 抢时间"扫描（每帧 6 ms、先扫目标表），并在日志里打印"已就绪"；
7. **认记录要 ID + 内容双确认**：索引区条目 16 字节 = `(u64 实体哈希, u32 ID(recIdx), u32 pad)`，
   ID 随构建漂移所以**运行时读**。**只锚 node 不够** —— 同底盘的不同载具会复用同一个 node
   （TD-220 堡垒与 TD-110 的槽0/槽1 node 逐字节相同），全局 `find` 取第一处会改到别的载具。

## 目录结构

```
ac8-rack-backpack/
  ac8_rack_backpack.lua   # 源码（首行 -- HD2-Addon: mods/dsh/ac8_rack_backpack 是装载器要求的声明）
  DESIGN.md               # 设计说明
guard-dog-mg43/
  guard_dog_mg43.lua
td-110-co-op/
  tank_storm_coop.lua
td-110-driver-armament/
  tank_storm_smoke_swap.lua
more-balanced-exosuit/
  balanced_exosuit_patriot.lua       # 携带爱国者版（召唤爱国者 → 附带解放者）
  balanced_exosuit_emancipator.lua   # 携带解放者版（召唤解放者 → 附带爱国者）
  DESIGN.md                          # 设计说明 + 两版二选一的原因与保护
no-large-piercing/
  no_large_piercing.lua              # 大型穿刺 → 0 (None)
  no_large_piercing_medium.lua       # 大型穿刺 → 2 (PiercingMedium)
  README.md                          # 独立说明（安装 / 效果 / 日志 / 卸载）
  INTRO.md                           # Mod 介绍：原理、完整特效清单、踩坑记录
```

打包成可分发的 zip 用 [Bingus Shared Loader 的 `tools/build_addon.py`](https://github.com/CowboyBingus/BingusSharedLoader)。

## 兼容性

* 验证环境：游戏 `1.8.45850.0`、Bingus Shared Loader v16（API 1）
* 五个 mod 已在 **2026-09-25** 实机复验：AC-8 75 发背包、更强的实弹狗、TD-110 Co-Op（射界 ±180 + 挂载对调）、
  更忙的 TD-110 驾驶员（驾驶员位换手操重机枪炮台）、**No Large Piercing（大型穿刺 → 0，两张表均 `已回读验证通过`）**；
  TD-110 Better Driver Armament（驾驶员位换手操重机枪炮台）
* 外骨骼（2026-09-25）：挂载两处 + 「携带爱国者版」的战备附加**实机验证**；**v1.1 的可用次数 → 1、冷却 → 0 实机验证**；「携带解放者版」的附加方向与二选一保护为离线仿真验证（4 场景 × 14 项全过）
* 由于不依赖版本相关常量，同大版本内的小更新一般无需改动；若游戏改了数据表内容（例如换了背包哈希），addon 会**拒写并留下日志**，不会乱写。

## 免责声明

* 非官方作品，与 Arrowhead Game Studios / Sony Interactive Entertainment 无任何关联；
* 仅在本机运行时修改内存，**不分发任何游戏资产**；
* 游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

## 许可

MIT，见 [LICENSE](LICENSE)。
