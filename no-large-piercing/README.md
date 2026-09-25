# No Large Piercing

> **分类：优化类（Optimization）**
> **状态：已实机验证**（2026-09-25，Helldivers 2 运行时内存补丁）

把《绝地潜兵2》里**大型穿刺类命中特效**从数据表中去掉。纯客户端内存改动，**不修改任何游戏文件**，停用即完全还原。

## 它改了什么

游戏在子弹/弹丸命中时，会按 `HitEffectDamageType` 播一个"命中特效档位"。其中两个档位是：

| 值 | 枚举名 | 含义 |
|---:|---|---|
| `3` | `HitEffectDamageType_PiercingLarge` | 大口径动能穿刺 |
| `4` | `HitEffectDamageType_PiercingLargeHEAT` | 大口径破甲（HEAT） |

本 mod 把数据表里**所有**这两档的记录改写掉：

| 包 | 管理器内名称 | 改写结果 |
|---|---|---|
| `No-Large-Piercing-v1.0.zip` | **No Large Piercing** | → `0` (`None`)，**完全不打**大型穿刺特效 |
| `No-Large-Piercing-Medium-v1.0.zip` | **No Large Piercing (Medium)** | → `2` (`PiercingMedium`)，**降档**为中口径穿刺 |

> 两个包**互斥**，只启用其中一个。同时启用时后加载的那个会打印提示并退出。

## 改动面

| 表 | 字段（记录内偏移） | 记录尺寸 | 你游戏里的条数 | 被改条目 |
|---|---|---:|---:|---:|
| `ProjectileSettings`（直击 / 弹道） | `+232` `effect_damage_type` | 272 B | 350 | **102**（`3`×90 + `4`×12） |
| `ExplosionSettings`（爆炸） | `+76` `hit_effect_damage_type` | 152 B | 422 | **4**（`3`×4） |

受影响的射弹/爆炸条目包含：**AC-8 机炮、GR-8 无后坐力炮、EAT-17 次抛、EAT-411 荡平者、RL-77 空爆、E/AT-12 反坦克炮台、EXO-45 外骨骼导弹、MG-206 重机枪、R-63 勤勉、P-2/P-35 手枪**，以及**机器人各型火箭弹 / 火炮 / 坦克炮、光能族等离子与光束、虫族酸液、轨道与飞鹰系战备**等。完整清单见 [`INTRO.md`](INTRO.md)。

## 依赖

* **Bingus Shared Loader v15 或更高**（loader 日志首行 `Bingus Shared Loader loader-v1x; API 1`）
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）

## 安装

1. 从 [`../dist/`](../dist/) 取包；
2. 用 mod 管理器导入并启用；
3. 进游戏。射弹 / 爆炸设置表是**常驻内存**的，进游戏约 **2 秒**后即写入生效，不必等进任务。

## 检查日志

`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`

```
[NoLargePiercing] 已加载：3/4 → 0 (None)（等待第 120 帧开始扫描）
[NoLargePiercing] 扫描开始：xxxx 个可读区域
[NoLargePiercing] ProjectileSettings @0x...：条数 350（离线镜像 343，+7）；自洽校验通过 eff3=92 eff4=14 不同type=350
[NoLargePiercing] ProjectileSettings @0x...（直击/弹道）：102 条 3/4 → 0 (None)，已回读验证通过
[NoLargePiercing] ExplosionSettings  @0x...：条数 422（离线镜像 413，+9）；自洽校验通过 eff3=4 eff4=0
[NoLargePiercing] ExplosionSettings  @0x...（爆炸）：4 条 3/4 → 0 (None)，已回读验证通过
```

看到 `已回读验证通过` 即成功。日志里那两个 `eff3=? eff4=?` 是**实际扫到的档位计数**，用于确认枚举没有随版本漂移。

同时会在日志目录导出两张表的完整清单（`ProjectileSettings_<地址>.DIAG.csv` / `ExplosionSettings_<地址>.DIAG.csv`），含每一条记录的 `index,type,aux,eff`。

## 卸载

mod 管理器里禁用即可 —— 改动只存在于运行时内存，游戏重启后数据表从磁盘重新加载，**不留任何痕迹**。

## 注意

* **联机风险**：这是客户端本地改动，**其他玩家看不到**，会造成表现不一致；游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。建议单人 / 自己开房时使用。
* 本 mod 改的是**命中视觉特效的档位**，**不改任何伤害数值**。
* 游戏更新后若日志出现「自洽校验失败」，说明记录尺寸或字段偏移变了，此时 mod 会**拒写并留下日志**，不会乱写。

详见 [`INTRO.md`](INTRO.md)（原理、完整特效清单、踩坑记录）。
