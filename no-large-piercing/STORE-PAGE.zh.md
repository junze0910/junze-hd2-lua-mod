# No Large Piercing（没有大型穿刺）

**项目地址 / 下载：** https://github.com/junze0910/junze-hd2-lua-mod/releases/tag/v1.3

## Description · 简介

把《绝地潜兵 2》里的**大型穿刺命中特效档**去掉。

弹丸命中目标时，游戏会按 `HitEffectDamageType` 播一个"命中特效档位"，其中两档属于大口径：

| 值 | 枚举 |
|---:|---|
| `3` | `HitEffectDamageType_PiercingLarge` |
| `4` | `HitEffectDamageType_PiercingLargeHEAT` |

本 mod 把数据表里**所有**使用这两档的条目改写掉：

| 版本 | 写入 | 效果 |
|---|---|---|
| **No Large Piercing** | `0`（`None`） | 完全不再播放大型穿刺命中特效 |
| **No Large Piercing (Medium)** | `2`（`PiercingMedium`） | 降档为中口径，保留命中反馈，只是没那么"重" |

**纯视觉改动**，不碰伤害、穿甲、弹道和平衡。属于**运行时内存补丁**，不修改任何游戏文件，停用即完全还原。

## Installation instructions · 安装说明

1. 安装 **Bingus Shared Loader v15 或更高**，确认已部署并启用；
2. 下载**两个 zip 中的一个**（两者互斥，见「主要特性」）；
3. 用 HD2 mod 管理器（HD2MM / Arsenal 等）导入并启用；
4. 启动游戏。射弹 / 爆炸设置表是**常驻内存**的，**开机约 2 秒**后即写入生效，不必先进任务。
   若游戏已在运行，请**重启游戏** —— Loader 只在启动时加载 addon，没有热重载；
5. 检查日志 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`。

```
[NoLargePiercing] 已加载：3/4 → 0 (None)（等待第 120 帧开始扫描）
[NoLargePiercing] 扫描开始：xxxx 个可读区域
[NoLargePiercing] ProjectileSettings @0x...：条数 350（离线镜像 343，+7）；自洽校验通过 eff3=92 eff4=14 不同type=350
[NoLargePiercing] ProjectileSettings @0x...（直击/弹道）：102 条 3/4 → 0 (None)，已回读验证通过
[NoLargePiercing] ExplosionSettings  @0x...：条数 422（离线镜像 413，+9）；自洽校验通过 eff3=4 eff4=0
[NoLargePiercing] ExplosionSettings  @0x...（爆炸）：4 条 3/4 → 0 (None)，已回读验证通过
```

`已回读验证通过` 表示**写入后逐条回读复核通过**。

日志里的 `eff3= / eff4=` 是**实际扫到的档位计数**，可用来确认枚举没有随版本漂移。

## Main features · 主要特性

* 改写 **102 条弹道条目**（`ProjectileSettings.effect_damage_type`，记录内 `+232`）与
  **4 条爆炸条目**（`ExplosionSettings.hit_effect_damage_type`，记录内 `+76`）；
* 涉及 **AC-8 机炮、GR-8 无后坐力炮、EAT-17、EAT-411、RL-77 空爆、E/AT-12 反坦克炮台、
  EXO-45 外骨骼导弹、MG-206、R-63 勤勉、P-2 / P-35 手枪**，以及**机器人各型火箭弹 / 火炮 /
  坦克炮、光能族等离子与光束、虫族酸液、轨道与飞鹰系战备**（完整 106 条清单见 `INTRO.md`）；
* **两个版本互斥**，同时启用时后者自动提示并退出，不会互相覆盖；
* **抗版本更新**：校验**不依赖记录下标与固定条数**（官方更新会重排记录顺序、在末尾追加新编号）。
  一旦记录尺寸或字段偏移变化，会**拒写并记录原因**，而不是乱写内存；
* **自动维护**：每约 10 秒复查；每约 5 分钟重新枚举内存区域并全量重扫。内存里有多份副本时**全部改写**；
* **可追溯**：每次写入后逐条回读复核，原始字节与改动清单都会落盘；
* **只改内存** —— 不写磁盘，完全可逆。

## Requirements · 依赖

* **Helldivers 2**（测试于 `1.8.45850.0`）
* **Bingus Shared Loader v15 或更高（API 1）** —— 必需，缺少则 addon 不会加载
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）
* Windows x64

## Shout outs · 鸣谢

* **Bingus** —— Shared Loader 与 `.patch_N` addon 工具链；
* **xypwn** —— [filediver](https://github.com/xypwn/filediver)，其内嵌的明文 `datalibrary` 加上游戏自带 typelib，是本文所有字段偏移与记录尺寸的来源；
* **shalzuth** —— [HelldiversData](https://github.com/shalzuth/HelldiversData)，社区最早的数据表导出工作；
* **noro** —— 游戏内提取的道具 ID 表，用于给每条受影响的条目配上名称。
