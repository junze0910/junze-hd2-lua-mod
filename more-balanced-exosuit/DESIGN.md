# 更均衡的爱国者/解放者外骨骼 · 设计说明

同一份逻辑的**两个方向**，挂载改动完全相同，只有"战备附加"写哪条记录不同。

| 源文件 | 包 | 需携带 | 效果 | 写入 |
|---|---|---|---|---|
| `balanced_exosuit_patriot.lua` | `More-Balanced-Exosuit-Patriot-v1.0.zip` | 爱国者 | 召唤爱国者时额外附带一台**解放者** | 爱国者记录 `additional_stratagem` `0 → 10`（`StratagemType_EmancipatorExosuit`） |
| `balanced_exosuit_emancipator.lua` | `More-Balanced-Exosuit-Emancipator-v1.0.zip` | 解放者 | 召唤解放者时额外附带一台**爱国者** | 解放者记录 `additional_stratagem` `0 → 26`（`StratagemType_PatriotExosuit`） |

## 挂载改动（两版相同）

| 记录 | 槽 | 原值 | 新值 |
|---|---|---|---|
| `MountComponentData` · `combat_walker_obsidian`（EXO-49 解放者） | 槽1（右臂） | `18417602992972518459` 右臂加农炮 | `645713022044093730` 爱国者加特林炮塔 |
| `MountComponentData` · `combat_walker`（EXO-45 爱国者） | 槽0（左臂） | `9388736439472594613` 导弹发射器 | `16570517418531528145` 左臂加农炮 |

定位：索引区条目 = `(u64 实体哈希, u32 recIdx, u32 pad)`，按实体哈希读 recIdx 定位记录，再逐个槽位复核
（`node` 必须相等、当前 item 必须是原值或目标值），不合格只记日志。

## 战备附加（v5 起的定位方式）

直接搜 **package 值**（`packages/generated/loadout/combat_walker` = `2482778796672462694` /
`.../combat_walker_obsidian` = `16658039432250907403`），命中点即记录内 package 字段；再校验 `+8` 处的 `icon`
（`4138467624065961495` / `14746049704219804392`）确认布局；目标字段 = 命中点 `+32`（`additional_stratagem`），
并要求 `depends_on(+28)`、`max_in_loadout(+36)` 都是 `0`，否则拒写。

不依赖飞鹰系记录、不依赖任何统计特征（v1~v4 的统计标定/飞鹰锚点方案已废弃）。

## ⚠ 两版必须二选一

两条记录同时被写成非 0 会形成"战备互相附加"（套娃），在战备/载具列表生成时崩溃。
因此两版都带**运行时保护**（fail-open）：

* 扫描目标 package 的同时也扫**对向版**的 package；
* 若对向记录 `icon` 匹配且它的附加槽已经非 0 → 本 mod **整体拒写**，并在
  `BalancedExosuit*_STATUS.log` 写一条"检测到对向版已经生效"；
* 扫不到对向记录时照常工作（不会因为检测失败而不生效）。

保护只能兜底，**正常使用请只装一个**。

## 时序

* `MountComponentData` 是**生成载具时读一次**的静态配置 → 必须在召唤前打好；
* `StratagemSettings` 只在**进任务后加载**；
* 进任务后先等 `BalancedExosuitPatriot_STATUS.log`（或 `...Emancipator_STATUS.log`）出现
  `三处改动均已就绪：现在可以召唤 / 重新召唤载具了`，**再**召唤外骨骼。

## 验证记录（2026-09-25）

* 挂载两处 + 战备附加：**携带爱国者版在实机验证通过**（v5.0 逻辑，游戏 `1.8.45850.0` + loader v16）。
* 离线仿真（真实记录布局：package@+168 / icon@+176 / 附加槽@+200）4 个场景 × 8 项全过：
  1. 爱国者版 · 正常 → 爱国者记录写 `10`，诱饵（同 package 坏 icon）不动、飞鹰式记录不动、对向记录不动；
  2. 爱国者版 · 对向已生效 → 拒写且留日志；
  3. 解放者版 · 正常 → 解放者记录写 `26`，同样不动其它记录；
  4. 解放者版 · 对向已生效 → 拒写且留日志。
