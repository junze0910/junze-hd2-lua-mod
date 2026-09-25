## Description

Removes the **large-piercing hit-effect tier** from Helldivers 2.

Whenever a projectile hits something, the game plays an impact effect whose "tier" comes from
`HitEffectDamageType`. Two of those tiers are large-calibre:

| Value | Enum |
|---:|---|
| `3` | `HitEffectDamageType_PiercingLarge` |
| `4` | `HitEffectDamageType_PiercingLargeHEAT` |

This mod rewrites **every data-table entry** that uses those two tiers:

| Variant | Writes | Result |
|---|---|---|
| **No Large Piercing** | `0` (`None`) | the large-piercing impact effect never plays at all |
| **No Large Piercing (Medium)** | `2` (`PiercingMedium`) | downgraded to the medium-calibre tier — hit feedback stays, it is just less heavy |

This is a **purely visual** change. Damage, armour penetration, ballistics and balance are untouched.

It is a **runtime memory patch**: no game files are modified, and disabling the mod restores everything.

## Installation instructions

1. Install **Bingus Shared Loader v15 or newer** and make sure it is deployed and enabled.
2. Download **one** of the two zips (they are mutually exclusive — see Main features).
3. Import the zip with your HD2 mod manager (HD2MM / Arsenal / …) and enable it.
4. Launch the game.
   The projectile / explosion settings tables are resident in memory, so the patch lands about
   **2 seconds after boot** — you do **not** need to enter a mission first.
   If the game is already running, **restart it**: the loader only loads addons at startup and has no hot reload.
5. Verify — open `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`.
   Success looks like this:

```
[NoLargePiercing] 已加载：3/4 → 0 (None)（等待第 120 帧开始扫描）
[NoLargePiercing] 扫描开始：xxxx 个可读区域
[NoLargePiercing] ProjectileSettings @0x...：条数 350（离线镜像 343，+7）；自洽校验通过 eff3=92 eff4=14 不同type=350
[NoLargePiercing] ProjectileSettings @0x...（直击/弹道）：102 条 3/4 → 0 (None)，已回读验证通过
[NoLargePiercing] ExplosionSettings  @0x...：条数 422（离线镜像 413，+9）；自洽校验通过 eff3=4 eff4=0
[NoLargePiercing] ExplosionSettings  @0x...（爆炸）：4 条 3/4 → 0 (None)，已回读验证通过
```

`已回读验证通过` = read-back verified. The two `eff3= / eff4=` numbers are the actual tier counts
that were found, useful for confirming the enum has not drifted between game versions.

## Main features

* Rewrites **102 projectile entries** (`ProjectileSettings.effect_damage_type`, record offset `+232`)
  and **4 explosion entries** (`ExplosionSettings.hit_effect_damage_type`, record offset `+76`).
* Affected entries include the **AC-8 Autocannon, GR-8 Recoilless Rifle, EAT-17, EAT-411,
  RL-77 Airburst, E/AT-12 Anti-Tank Emplacement, EXO-45 exosuit missiles, MG-206, R-63 Diligence,
  P-2 / P-35 sidearms**, plus **bot rockets / artillery / tank guns, Illuminate plasma and beams,
  Terminid acid**, and **Orbital / Eagle stratagems** — the full 106-entry list is in `INTRO.md`.
* **Two mutually exclusive variants.** Enabling both makes the second one print a notice and exit
  automatically, so you cannot accidentally run them together.
* **Version-resilient by design.** Validation deliberately does **not** depend on record indices or
  hard-coded table sizes — the game re-orders records and appends new enum IDs between patches.
  If the record layout ever changes, the mod **refuses to write and logs the reason** instead of
  corrupting memory.
* **Self-maintaining.** Re-checks every ~10 s, and does a full re-scan (including re-enumerating
  memory regions) every ~5 min, so newly loaded copies get patched too. If the tables exist in
  several in-memory copies, **all** of them are rewritten.
* **Auditable.** Every write is read back and verified entry-by-entry. Original bytes and the exact
  change list are dumped to the log folder.
* Memory-only, nothing written to disk, fully reversible.

## Requirements

* **Helldivers 2** (tested on `1.8.45850.0`)
* **Bingus Shared Loader v15 or newer (API 1)** — required. Without it the addon will not load.
* An HD2 mod manager that can import zips (HD2MM / Arsenal / …)
* Windows x64

## Shout outs

* **Bingus** — for Shared Loader and the `.patch_N` addon tooling that makes patches like this possible.
* **xypwn** — for [filediver](https://github.com/xypwn/filediver). The plaintext `datalibrary` it ships,
  together with the game's own typelib, is where the field offsets and record sizes here were derived from.
* **shalzuth** — for [HelldiversData](https://github.com/shalzuth/HelldiversData), the original community
  effort to dump these tables.
* **noro** — for the in-game item ID tables used to put a name on every affected entry.

---

# 中文对照

## Description（简介）

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

## Installation instructions（安装）

1. 安装 **Bingus Shared Loader v15 或更高**，确认已部署并启用；
2. 下载**两个 zip 中的一个**（两者互斥）；
3. 用 HD2 mod 管理器（HD2MM / Arsenal 等）导入并启用；
4. 启动游戏。射弹 / 爆炸设置表是**常驻内存**的，**开机约 2 秒**后即写入生效，不必先进任务。
   若游戏已在运行，请**重启游戏** —— Loader 只在启动时加载 addon，没有热重载；
5. 检查日志 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`，
   看到 `已回读验证通过` 即成功。

## Main features（主要特性）

* 改写 **102 条弹道条目**（`ProjectileSettings.effect_damage_type`，记录内 `+232`）与 **4 条爆炸条目**（`ExplosionSettings.hit_effect_damage_type`，记录内 `+76`）；
* 涉及 **AC-8 机炮、GR-8 无后坐力炮、EAT-17、EAT-411、RL-77 空爆、E/AT-12 反坦克炮台、EXO-45 外骨骼导弹、MG-206、R-63 勤勉、P-2 / P-35 手枪**，以及**机器人各型火箭弹 / 火炮 / 坦克炮、光能族等离子与光束、虫族酸液、轨道与飞鹰系战备**（完整 106 条清单见 `INTRO.md`）；
* **两个版本互斥**，同时启用时后者自动提示并退出；
* **抗版本更新**：校验**不依赖记录下标和固定条数**（官方更新会重排记录、在末尾追加新编号）。一旦记录尺寸或字段偏移变化，会**拒写并记录原因**，而不是乱写内存；
* **自动维护**：每约 10 秒复查、每约 5 分钟重新枚举内存区域并全量重扫；内存里有多份副本时全部改写；
* **可追溯**：每次写入后逐条回读复核，原始字节与改动清单都会落盘；
* 只改内存、不写磁盘、完全可逆。

## Requirements（依赖）

* **Helldivers 2**（测试于 `1.8.45850.0`）
* **Bingus Shared Loader v15 或更高（API 1）** —— 必需，缺少则 addon 不会加载
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）
* Windows x64

## Shout outs（鸣谢）

* **Bingus** —— Shared Loader 与 `.patch_N` addon 工具链；
* **xypwn** —— [filediver](https://github.com/xypwn/filediver)，其内嵌的明文 `datalibrary` 加上游戏自带 typelib，是本文所有字段偏移与记录尺寸的来源；
* **shalzuth** —— [HelldiversData](https://github.com/shalzuth/HelldiversData)，社区最早的数据表导出工作；
* **noro** —— 游戏内提取的道具 ID 表，用于给每条受影响的条目配上名称。
