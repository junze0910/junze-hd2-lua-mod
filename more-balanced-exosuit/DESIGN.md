# 更均衡的爱国者/解放者外骨骼 · 设计说明（v1.1）

同一份逻辑的**两个方向**，挂载改动完全相同：

* **携带爱国者版**：**携带爱国者外骨骼战备时，额外携带解放者外骨骼战备**；
* **携带解放者版**：**携带解放者外骨骼战备时，额外携带爱国者外骨骼战备**。

再叠一台外骨骼的通用调整：**可用次数 → 1、冷却 → 0**。

| 源文件 | 包 | 需携带 | 效果 | 写入 |
|---|---|---|---|---|
| `balanced_exosuit_patriot.lua` | `More-Balanced-Exosuit-Patriot-v1.1.zip` | 爱国者 | 额外携带解放者 | 爱国者记录 `additional_stratagem` `0 → 10`（`StratagemType_EmancipatorExosuit`） |
| `balanced_exosuit_emancipator.lua` | `More-Balanced-Exosuit-Emancipator-v1.1.zip` | 解放者 | 额外携带爱国者 | 解放者记录 `additional_stratagem` `0 → 26`（`StratagemType_PatriotExosuit`） |

## ① ② 挂载改动（两版相同）

| 记录 | 槽 | 原值 | 新值 |
|---|---|---|---|
| `MountComponentData` · `combat_walker_obsidian`（EXO-49 解放者） | 槽1（右臂） | `18417602992972518459` 右臂加农炮 | `645713022044093730` 爱国者加特林炮塔 |
| `MountComponentData` · `combat_walker`（EXO-45 爱国者） | 槽0（左臂） | `9388736439472594613` 导弹发射器 | `16570517418531528145` 左臂加农炮 |

定位：索引区条目 = `(u64 实体哈希, u32 recIdx, u32 pad)`，按实体哈希读 recIdx 定位记录，再逐个槽位复核
（`node` 必须相等、当前 item 必须是原值或目标值），不合格只记日志。

## ③ 战备附加

直接搜 **package 值**（`packages/generated/loadout/combat_walker` = `2482778796672462694` /
`.../combat_walker_obsidian` = `16658039432250907403`），命中点即记录内 package 字段；再校验 `+8` 处的 `icon`
（`4138467624065961495` / `14746049704219804392`）确认布局；目标字段 = 命中点 `+32`（`additional_stratagem`），
并要求 `depends_on(+28)`、`max_in_loadout(+36)` 都是 `0`，否则拒写。

不依赖飞鹰系记录、不依赖任何统计特征（v1~v4 的统计标定/飞鹰锚点方案已废弃）。

## ④ 两台外骨骼通用调整（可用次数 / 冷却）

| 字段 | 偏移（相对 package 字段） | 原版 | 写入 | 维护方式 |
|---|---|---|---|---|
| `use`（可用次数，u32） | `-88` | 3 | `1` | **只写一次**，之后不再干涉（用掉就该没了） |
| `cooldown_duration_success`（float） | `-64` | 420.0 | `0.0` | 持续维护（静态配置，本不该变） |
| `cooldown_duration_fail`（float） | `-60` | 0.0 | `0.0` | 持续维护 |

偏移来源：`typelib_all.json` 的 `StratagemInfo`（size = 400）成员逐一对齐 ——
`use` 是 5 个 float 之前那个 `UINT32`（+80），随后 `spawn_time/spawn_radius/unk/beacon_linger/extra_travel` 5 个 float，
接着 `cooldown_duration_success`（+104）、`cooldown_duration_fail`（+108），再往后才是 `origin_type/call_in_type/...`。
package 字段在 +168，所以三者相对偏移分别是 `-88 / -64 / -60`。

写入对象是**两台外骨骼**（爱国者 + 解放者）——记录用 package + icon 双重确认，所以
同 package 但 icon 不同的 `PresidentReward` 变体不会被误改。

## ⚠ 两版必须二选一

两条战备记录同时被写成非 0 会形成"战备互相附加"（套娃），在战备/载具列表生成时崩溃。
两版都带**运行时保护**（fail-open）：扫描目标 package 的同时也扫对向版 package，
若对向记录 icon 匹配且附加槽已非 0 → **附加写入整体拒写**并写日志（④ 的调整不受影响，照常生效）。
保护只能兜底，**正常使用请只装一个**。

## 时序

* `MountComponentData` 是**生成载具时读一次**的静态配置 → 必须在召唤前打好；
* `StratagemSettings`（附加槽 / use / 冷却）只在**进任务后加载**；
* 进任务后先等 `BalancedExosuitPatriot_STATUS.log`（或 `...Emancipator_STATUS.log`）出现
  `四项改动均已就绪：现在可以召唤 / 重新召唤载具了`，**再**召唤外骨骼。

## 验证记录（2026-09-25）

* 「携带爱国者版」的挂载两处 + 战备附加（`0 → 10`）：**实机验证通过**（原型 v5.0，游戏 `1.8.45850.0` + loader v16）；
* 离线仿真 4 场景 × 14 项全过（`tmp\_sim_{wl_ok,wl_block,eman_ok,eman_block}.py`）：正常写入、诱饵（同 package 坏 icon）不动、
  飞鹰式记录不动、对向记录不动、邻字段为 0、`use`→1、冷却→0、二选一保护触发；
* 包校验：`More-Balanced-Exosuit-Patriot-v1.1.zip` = `9251312ef4ea536cb56c4c898ba39f46fa0b0a3d06b63e18011332e74af9e421`；`More-Balanced-Exosuit-Emancipator-v1.1.zip` = `97cbd29c029b94e519789a13fe285a504d5465fe3ab16c996805deb5e2583d12`。
