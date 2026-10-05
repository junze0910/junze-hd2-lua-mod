# No Large Piercing

**Downloads:** repository `dist/No-Large-Piercing-v1.6.zip` (or the Releases page)

## Description

Removes the **large-piercing hit-effect tier** from Helldivers 2.

When a projectile hits something, the game plays an impact effect whose "tier" comes from
`HitEffectDamageType`. Two of those tiers are large-calibre:

| Value | Enum |
|---:|---|
| `3` | `HitEffectDamageType_PiercingLarge` |
| `4` | `HitEffectDamageType_PiercingLargeHEAT` |

This mod rewrites **every data-table entry** that uses those two tiers:

| Variant | Writes | Result |
|---|---|---|
| **No Large Piercing** | `0` (`None`) | the large-piercing impact effect never plays at all |

> The `→ 2` **Medium** variant was retired in v1.5 — only the `→ 0` build is maintained.

This is a **purely visual** change. Damage, armour penetration, ballistics and balance are untouched.
It is a **runtime memory patch**: no game files are modified, and disabling the mod restores everything.

## Installation instructions

1. Install **Bingus Shared Loader v15 or newer** and make sure it is deployed and enabled.
2. Download `No-Large-Piercing-v1.5.zip` (the retired Medium variant is not needed).
3. Import the zip with your HD2 mod manager (HD2MM / Arsenal / …) and enable it.
4. Launch the game. The projectile / explosion settings tables are resident in memory, so the patch
   lands about **2 seconds after boot** — you do **not** need to enter a mission first.
   If the game is already running, **restart it**: the loader only loads addons at startup and has
   no hot reload.
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

`已回读验证通过` = **read-back verified** (`eff3= / eff4=` are the actual tier counts found —
useful for confirming the enum has not drifted between game versions).

## Main features

* **102 projectile entries** rewritten (`ProjectileSettings.effect_damage_type`, record offset `+232`)
  and **4 explosion entries** (`ExplosionSettings.hit_effect_damage_type`, record offset `+76`).
* Covers the **AC-8 Autocannon, GR-8 Recoilless Rifle, EAT-17, EAT-411, RL-77 Airburst,
  E/AT-12 Anti-Tank Emplacement, EXO-45 exosuit missiles, MG-206, R-63 Diligence, P-2 / P-35
  sidearms**, plus **bot rockets / artillery / tank guns, Illuminate plasma and beams, Terminid
  acid**, and **Orbital / Eagle stratagems** — full 106-entry list in [INTRO.md](https://github.com/junze0910/junze-hd2-lua-mod/blob/main/no-large-piercing/INTRO.md).
* **Table lookup delegated to HD2 Scanner (v1.6).** Both settings tables are already on the
  Scanner's table list, so this mod does **not scan memory at all**: it subscribes, asks for an
  urgent round (≈0.5 s), and writes every copy the broadcast reports — new copies after a map
  reload are picked up automatically. Without the Scanner it falls back to a one-shot self-scan.
* **Near-zero resident cost.** After the write the only action is a canary re-reading 108
  four-byte addresses once a minute (432 bytes/min).
* **Version-resilient by design.** Validation deliberately does **not** depend on record indices or
  hard-coded table sizes — the game re-orders records and appends new enum IDs between patches.
  If the record layout ever changes, the mod **refuses to write and logs the reason** instead of
  corrupting memory.
* **No background scanning** by default (`ONE_SHOT = false` brings back the old re-check + hot-zone
  + full fallback scheduling, which does rewrite every in-memory copy it can find).
* **Auditable.** Every write is read back and verified entry-by-entry; original bytes and the exact
  change list are dumped to the log folder.
* **Memory-only** — nothing written to disk, fully reversible.

## Requirements

* **Helldivers 2** (tested on `1.8.45850.0`)
* **Bingus Shared Loader v15 or newer (API 1)** — required; without it the addon will not load.
* **HD2 Scanner (core line, v0.8.0+)** — recommended: with it the mod never scans memory; without it the mod falls back to its own one-shot scan.
* An HD2 mod manager that can import zips (HD2MM / Arsenal / …)
* Windows x64

## Shout outs

* **Bingus** — for Shared Loader and the `.patch_N` addon tooling that makes patches like this possible.
* **xypwn** — for [filediver](https://github.com/xypwn/filediver). The plaintext `datalibrary` it ships,
  together with the game's own typelib, is where the field offsets and record sizes here were derived from.
* **Darctor** — for [Helldivers2_RawData](https://github.com/Darctor/Helldivers2_RawData). Its in-memory dump of the game's settings
  tables and its enum name tables (`HitEffectDamageType`, `ProjectileType`, `ExplosionType`) are what the
  field semantics and tier names in this mod are based on.
* **shalzuth** — for [HelldiversData](https://github.com/shalzuth/HelldiversData), the original community
  effort to dump these tables.
* **noro** — for the in-game item ID tables used to put a name on every affected entry.
