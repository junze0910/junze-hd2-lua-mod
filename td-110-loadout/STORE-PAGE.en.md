# TD-110 Loadout

**Project / downloads:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest

**One-liner**: Turn the TD-110 Storm tank into a 4-mode configurable vehicle (Vanilla / Co-op / Busy / Custom),
with an independent 360° horizontal-traverse toggle for the laser turret and the gatling main gun — replacing the
old either/or choice between *TD-110 Co-Op* and *Busier TD-110 Driver*.

**Tags**: `vehicle` `TD-110` `storm tank` `loadout` `traverse` `configurable` `vehicle-v2.0`

## Description

Turns the **TD-110 Storm tank** (`tank_storm`) into a configurable vehicle:

- what goes in the **driver slot** (record `+48`)
- what goes in the **gunner slot** (record `+24`)
- whether the **laser turret** and the **gatling main gun** get a full **360° horizontal traverse**

It replaces two older packages — `TD-110 Co-Op` and `Busier TD-110 Driver`. They wrote to the **same slot of
the same record**, so only one of them could ever be enabled at a time. This mod merges them into one package
with a mode switch: **no more either/or**. Everything happens in runtime memory only — no game files are
touched, and disabling the mod + restarting restores everything.

## Main features

| Mode | Driver slot (`+48`) | Gunner slot (`+24`) |
|---|---|---|
| **Vanilla** | Smoke launcher | Laser designator |
| **Co-op** | Laser designator | **Smoke launcher ⇄ 40mm autocannon** |
| **Busy** | **HMG turret ⇄ 40mm autocannon** | Laser designator |
| **Custom** | 1 of 5 | 1 of 5 |

Five selectable mounts: **HMG turret** · **40mm autocannon** · **extra missile launcher** · **smoke launcher** · **laser designator**.

* **Hard rule: exactly one of the two slots is a laser.** Trying to mount a second laser is **refused**
  (two lasers fight over designation) with the reason logged — this is a deliberate guard, not a bug.
* **360° traverse**: independent toggle, **on by default**, independent of the mode. Widens the **laser turret**
  and the **gatling main gun** horizontal traverse from ±20° to **±180° (full 360°)**.
  ⚠ **Horizontal only — camera/view limits are NOT removed.** Turning the toggle off writes the vanilla ±20° back.
  Traverse is read live by the engine, so it applies immediately.
* **Change it as often as you like**: modes and sub-options can be switched back and forth; the overwrite check
  accepts any mount this mod may have written before, not just vanilla.
* **Initialize**: one click restores everything to vanilla — it can even force its way back when the slot holds
  an unrecognised value written by another mod.
* **Two ways to configure**: the native **ESC → MODS page**, or edit the local cfg (re-read every second).
* **Traceable**: every write is read back and verified, reverted writes are re-applied, all state is logged.

## How to use

1. Install **Bingus Shared Loader v15+ (API 1)** (or a compatible MDL setup).
2. Install **HD2 Scanner v0.7.0+** — a **hard requirement**: it supplies the table addresses.
3. Import `TD-110-Loadout-v1.0.1.zip` in your HD2 mod manager and enable it.
4. Launch the game → **ESC → MODS page → TD-110 Loadout** → pick a mode / sub-option.
5. **After dropping into a mission, do not summon the tank yet** — wait until the log shows the mounts were written.
6. Changing the loadout later requires **re-summoning the tank**. Traverse is exempt (applies live).

```text
[TankStormLoadout] 已接上 HD2Scanner（前置）：挂载表 + 射界表由 Scanner 提供
[TankStormLoadout] 已写：驾驶员位(+48) … -> …（recIdx 123，node/flags 未动）
[TankStormLoadout] 已写射界：激光炮塔（recIdx 28）±20 -> ±180（360°）
```

## Requirements

* **Helldivers 2** (tested on `1.8.45850.0`)
* **Bingus Shared Loader v15+ (API 1)**, or a compatible MDL
* **HD2 Scanner v0.7.0+** — **required**; without it the mod writes nothing and only logs the reason
* An HD2 mod manager able to import zips (HD2MM / Arsenal …)
* Windows x64

## Compatibility

* **Replaces** `TD-110-Co-Op` and `TD-110-Busier-Driver` (deprecated, no longer distributed) — **do not run them together**.
* Local memory only: **other players in co-op will not see your changes**.
* If another TD-110 mod writes a value this mod does not recognise, it **refuses to overwrite** it;
  use **Initialize** to force vanilla back.
* The game runs nProtect GameGuard; use third-party tools at your own risk.

## Known limits

* **Mounts are read once, when a vehicle spawns**: you must **re-summon** the tank after changing the loadout.
  Traverse is read live and is not affected.
* The **HMG turret** in the *Busy* mode is **not a real mount entry** in the game data (it is a standalone weapon
  entity), so it uses its own default ammo setup. An older build patched its magazine to 1000 rounds — **removed
  on request in this version**. Pick the **40mm autocannon** instead if sustained fire matters to you.
* **Horizontal traverse only**: the camera/view limits stay as-is, so the turret turns further than you can look.
* Settings use **ModOptionsMenu** (toggles / fixed choices only) — **no free text input**; edit the cfg for custom hashes.

## Logs

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\TankStormLoadout.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\TankStormLoadout_STATUS.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log
```

## Shout outs

* **Bingus** — Shared Loader, the `Addon` toolchain and the ModOptionsMenu reference;
* **xypwn** — [filediver](https://github.com/xypwn/filediver); its plain-text `datalibrary` plus the game typelib
  are the source of every field offset and record size used here;
* **CowboyBingus** — ModOptionsMenu / panel and logging conventions.