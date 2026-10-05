# No Large Piercing

**Downloads · 下载：** repository `dist/No-Large-Piercing-v1.6.zip`（或 Releases 页）

<!-- 双语发布页 · Bilingual store page
     Description / Installation instructions / Main features / Requirements / Shout outs
     每段先英文、后中文。Something 需要纯英文可直接用 STORE-PAGE.en.md，纯中文用 STORE-PAGE.zh.md -->

---

## Description · 简介

Removes the **large-piercing hit-effect tier** from Helldivers 2.

When a projectile hits something, the game plays an impact effect whose "tier" comes from
`HitEffectDamageType`. Two of those tiers are large-calibre:

把《绝地潜兵 2》里的**大型穿刺命中特效档**去掉。

弹丸命中目标时，游戏会按 `HitEffectDamageType` 播一个"命中特效档位"，其中两档属于大口径：

| Value / 值 | Enum / 枚举 |
|---:|---|
| `3` | `HitEffectDamageType_PiercingLarge` |
| `4` | `HitEffectDamageType_PiercingLargeHEAT` |

This mod rewrites **every data-table entry** that uses those two tiers:

本 mod 把数据表里**所有**使用这两档的条目改写掉：

| Variant / 版本 | Writes / 写入 | Result / 效果 |
|---|---|---|
| **No Large Piercing** | `0` (`None`) | the large-piercing impact effect never plays at all<br>完全不再播放大型穿刺命中特效 |

> The `→ 2` **Medium** variant was retired in v1.5 — only the `→ 0` build is maintained.<br>> `→ 2` 降档版（Medium）自 v1.5 起停止维护，只保留 `→ 0` 版。

This is a **purely visual** change. Damage, armour penetration, ballistics and balance are untouched.

It is a **runtime memory patch**: no game files are modified, and disabling the mod restores everything.

**纯视觉改动**，不碰伤害、穿甲、弹道和平衡。属于**运行时内存补丁**，不修改任何游戏文件，停用即完全还原。

---

## Installation instructions · 安装说明

1. Install **Bingus Shared Loader v15 or newer** and make sure it is deployed and enabled.
   安装 **Bingus Shared Loader v15 或更高**，确认已部署并启用。
2. Download `No-Large-Piercing-v1.5.zip` (the retired Medium variant is not needed).
   下载 `No-Large-Piercing-v1.5.zip`（已退役的中口径版不需要）。
3. Import the zip with your HD2 mod manager (HD2MM / Arsenal / …) and enable it.
   用 HD2 mod 管理器（HD2MM / Arsenal 等）导入并启用。
4. Launch the game. The projectile / explosion settings tables are resident in memory, so the patch
   lands about **2 seconds after boot** — you do **not** need to enter a mission first.
   If the game is already running, **restart it**: the loader only loads addons at startup and has
   no hot reload.
   启动游戏。射弹 / 爆炸设置表是**常驻内存**的，**开机约 2 秒**后即写入生效，不必先进任务。
   若游戏已在运行，请**重启游戏** —— Loader 只在启动时加载 addon，没有热重载。
5. Verify — open `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`.
   检查日志 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`。

```
[NoLargePiercing] 已加载：3/4 → 0 (None)（等待第 120 帧开始扫描）
[NoLargePiercing] 扫描开始：xxxx 个可读区域
[NoLargePiercing] ProjectileSettings @0x...：条数 350（离线镜像 343，+7）；自洽校验通过 eff3=92 eff4=14 不同type=350
[NoLargePiercing] ProjectileSettings @0x...（直击/弹道）：102 条 3/4 → 0 (None)，已回读验证通过
[NoLargePiercing] ExplosionSettings  @0x...：条数 422（离线镜像 413，+9）；自洽校验通过 eff3=4 eff4=0
[NoLargePiercing] ExplosionSettings  @0x...（爆炸）：4 条 3/4 → 0 (None)，已回读验证通过
```

`已回读验证通过` = **read-back verified**.

`eff3= / eff4=` are the actual tier counts that were found — useful for confirming the enum has not
drifted between game versions.

`已回读验证通过` 表示**写入后逐条回读复核通过**。

日志里的 `eff3= / eff4=` 是**实际扫到的档位计数**，可用来确认枚举没有随版本漂移。

---

## Main features · 主要特性

* **102 projectile entries** rewritten (`ProjectileSettings.effect_damage_type`, record offset `+232`)
  and **4 explosion entries** (`ExplosionSettings.hit_effect_damage_type`, record offset `+76`).
  改写 **102 条弹道条目**（`ProjectileSettings.effect_damage_type`，记录内 `+232`）与
  **4 条爆炸条目**（`ExplosionSettings.hit_effect_damage_type`，记录内 `+76`）。

* Covers the **AC-8 Autocannon, GR-8 Recoilless Rifle, EAT-17, EAT-411, RL-77 Airburst,
  E/AT-12 Anti-Tank Emplacement, EXO-45 exosuit missiles, MG-206, R-63 Diligence, P-2 / P-35
  sidearms**, plus **bot rockets / artillery / tank guns, Illuminate plasma and beams, Terminid
  acid**, and **Orbital / Eagle stratagems** — full 106-entry list in [INTRO.md](https://github.com/junze0910/junze-hd2-lua-mod/blob/main/no-large-piercing/INTRO.md).
  涉及 **AC-8 机炮、GR-8 无后坐力炮、EAT-17、EAT-411、RL-77 空爆、E/AT-12 反坦克炮台、
  EXO-45 外骨骼导弹、MG-206、R-63 勤勉、P-2 / P-35 手枪**，以及**机器人各型火箭弹 / 火炮 /
  坦克炮、光能族等离子与光束、虫族酸液、轨道与飞鹰系战备**（完整 106 条清单见 [INTRO.md](https://github.com/junze0910/junze-hd2-lua-mod/blob/main/no-large-piercing/INTRO.md)）。

* **Table lookup delegated to HD2 Scanner (v1.6).** The two settings tables are already on the
  Scanner's table list, so this mod does **not scan memory at all**: it subscribes, asks for an
  urgent round (≈0.5 s), and writes whatever copies the broadcast reports — new copies after a
  map reload are picked up automatically. Without the Scanner it falls back to a one-shot self-scan
  at boot.
  **v1.6 = 找表交给 HD2 Scanner**：这两张表本来就是 Scanner 的已登记表，本 mod 自己**不扫内存**，只订阅 + 催一轮（≈0.5 秒）+ 写它广播的每份副本（换图后的新副本会自动补上）；没装 Scanner 则回退到开机一次性自扫。
* **One-shot, near-zero resident cost.** The write happens once; afterwards the only action is a
  canary that re-reads 108 four-byte addresses once a minute (432 bytes/min).
  **一次性写入**：写完即停扫；常驻开销只剩每分钟读 108 个 4 字节地址（432 字节/分钟）的金丝雀。
* **Retired variants.** The old `→ 2` Medium build and the old maintenance-style scheduling
  (`ONE_SHOT = false`) both still exist, but only the `→ 0` one-shot build is maintained.
  `→ 2` 中口径版与旧的维护式调度（`ONE_SHOT = false`）都还在，但只维护 `→ 0` 的一次性版本。

* **Version-resilient by design.** Validation deliberately does **not** depend on record indices or
  hard-coded table sizes — the game re-orders records and appends new enum IDs between patches.
  If the record layout ever changes, the mod **refuses to write and logs the reason** instead of
  corrupting memory.
  **抗版本更新**：校验**不依赖记录下标与固定条数**（官方更新会重排记录顺序、在末尾追加新编号）。
  一旦记录尺寸或字段偏移变化，会**拒写并记录原因**，而不是乱写内存。

* **Self-maintaining.** Re-checks every ~10 s; full re-scan (including re-enumerating memory
  regions) every ~5 min. If the tables exist in several in-memory copies, **all** are rewritten.
  **自动维护**：每约 10 秒复查；每约 5 分钟重新枚举内存区域并全量重扫。内存里有多份副本时**全部改写**。

* **Auditable.** Every write is read back and verified entry-by-entry; original bytes and the exact
  change list are dumped to the log folder.
  **可追溯**：每次写入后逐条回读复核，原始字节与改动清单都会落盘。

* **Memory-only** — nothing written to disk, fully reversible.
  **只改内存** —— 不写磁盘，完全可逆。

---

## Requirements · 依赖

* **Helldivers 2** (tested on `1.8.45850.0`)
* **HD2 Scanner (core line, v0.8.0+) — recommended**: with it this mod never scans memory; without it the mod falls back to its own one-shot scan — 《绝地潜兵 2》（测试于 `1.8.45850.0`）
* **Bingus Shared Loader v15 or newer (API 1)** — required; without it the addon will not load.
  **Bingus Shared Loader v15 或更高（API 1）** —— 必需，缺少则 addon 不会加载
* An HD2 mod manager that can import zips (HD2MM / Arsenal / …) —— 能导入 zip 的 HD2 mod 管理器
* Windows x64

---

## Shout outs · 鸣谢

* **Bingus** — for Shared Loader and the `.patch_N` addon tooling that makes patches like this possible.
  Shared Loader 与 `.patch_N` addon 工具链。
* **xypwn** — for [filediver](https://github.com/xypwn/filediver). The plaintext `datalibrary` it ships,
  together with the game's own typelib, is where the field offsets and record sizes here were derived from.
  其内嵌的明文 `datalibrary` 加上游戏自带 typelib，是本文所有字段偏移与记录尺寸的来源。
* **Darctor** — for [Helldivers2_RawData](https://github.com/Darctor/Helldivers2_RawData). Its in-memory dump of the game's settings
  tables and its enum name tables (`HitEffectDamageType`, `ProjectileType`, `ExplosionType`) are what the
  field semantics and tier names in this mod are based on.
  其游戏设置表内存 dump 与枚举名表（`HitEffectDamageType` / `ProjectileType` / `ExplosionType`），
  是本文字段语义与档位名称的依据。
* **shalzuth** — for [HelldiversData](https://github.com/shalzuth/HelldiversData), the original community
  effort to dump these tables. 社区最早的数据表导出工作。
* **noro** — for the in-game item ID tables used to put a name on every affected entry.
  游戏内提取的道具 ID 表，用于给每条受影响的条目配上名称。
