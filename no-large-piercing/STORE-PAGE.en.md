# No Large Piercing

**Project page / downloads:** https://github.com/junze0910/junze-hd2-lua-mod/releases/tag/v1.3

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
| **No Large Piercing (Medium)** | `2` (`PiercingMedium`) | downgraded to the medium-calibre tier — hit feedback stays, it is just less heavy |

This is a **purely visual** change. Damage, armour penetration, ballistics and balance are untouched.
It is a **runtime memory patch**: no game files are modified, and disabling the mod restores everything.

## Installation instructions

1. Install **Bingus Shared Loader v15 or newer** and make sure it is deployed and enabled.
2. Download **one** of the two zips (they are mutually exclusive — see Main features).
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
  acid**, and **Orbital / Eagle stratagems** — full 106-entry list in `INTRO.md`.
* **Two mutually exclusive variants.** Enabling both makes the second one print a notice and exit
  automatically — you cannot accidentally run them together.
* **Version-resilient by design.** Validation deliberately does **not** depend on record indices or
  hard-coded table sizes — the game re-orders records and appends new enum IDs between patches.
  If the record layout ever changes, the mod **refuses to write and logs the reason** instead of
  corrupting memory.
* **Self-maintaining.** Re-checks every ~10 s; full re-scan (including re-enumerating memory
  regions) every ~5 min. If the tables exist in several in-memory copies, **all** are rewritten.
* **Auditable.** Every write is read back and verified entry-by-entry; original bytes and the exact
  change list are dumped to the log folder.
* **Memory-only** — nothing written to disk, fully reversible.

## Requirements

* **Helldivers 2** (tested on `1.8.45850.0`)
* **Bingus Shared Loader v15 or newer (API 1)** — required; without it the addon will not load.
* An HD2 mod manager that can import zips (HD2MM / Arsenal / …)
* Windows x64

## Shout outs

* **Bingus** — for Shared Loader and the `.patch_N` addon tooling that makes patches like this possible.
* **xypwn** — for [filediver](https://github.com/xypwn/filediver). The plaintext `datalibrary` it ships,
  together with the game's own typelib, is where the field offsets and record sizes here were derived from.
* **shalzuth** — for [HelldiversData](https://github.com/shalzuth/HelldiversData), the original community
  effort to dump these tables.
* **noro** — for the in-game item ID tables used to put a name on every affected entry.
