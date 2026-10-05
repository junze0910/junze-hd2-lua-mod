# Armor Tweaks

**Project / downloads:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest
**Current version:** v1.1.0

**One-liner**: Turn three Helldivers 2 armoured vehicles — the **TD-110 Storm tank**, the **TD-220 Bastion MK XVI**
and the **M-102 Fast Recon Vehicle** — into configurable ones: pick the mounted weapons, widen the horizontal
traverse to a full 360°, and switch the 40mm gun between its two ammo types.

**Tags**: `vehicle` `TD-110` `TD-220` `M-102` `FRV` `loadout` `traverse` `vehicle-v2.0`

## Description

Makes three armoured vehicles configurable:

* **TD-110 Storm tank** (`tank_storm`) — what goes in the driver slot and the gunner slot, plus four presets;
* **TD-220 Bastion MK XVI** — keep the coaxial HMG or swap it for the 40mm autocannon turret;
* **M-102 Fast Recon Vehicle** (including the *Map Spawn* variant) — three-way choice of the vehicle weapon;
* **Horizontal traverse** of four turrets (TD-110 laser turret + gatling main gun, TD-220 main gun + coaxial HMG):
  optionally widened from ±20° to **±180° (full 360°)**;
* **40mm ammo type**: 40mm AP/HE ⇄ 20mm AA (proximity-fused cluster).

It replaces the older `TD-110 Co-Op` and `Busier TD-110 Driver` packages — they wrote to the **same slot of the
same record**, so only one could ever be used. Everything happens in **runtime memory only**: no game files are
touched, disabling the mod + restarting restores everything.

## Main features

### 1. Six rows on the native MODS page (group `A HD2 MOD COLLECTION`)

| Row | What it does |
|---|---|
| `[TD-110] Preset` | vanilla / co-op·smoke / co-op·40mm / busy·HMG / busy·40mm / custom |
| `[TD-110] Gunner slot` / `[TD-110] Driver slot` | 1 of 5 each (changing one auto-switches to *custom*) |
| `[TD-220] Coaxial mount` | stock coaxial HMG ⇄ 40mm autocannon turret |
| `[40mm] Ammo type` | 40mm AP/HE ⇄ 20mm AA (proximity-fused cluster) |
| **`[M-102] Vehicle weapon`** | **stock vehicle HMG ⇄ HMG turret ⇄ 40mm autocannon turret** |

### 2. 360° traverse (independent toggle, on by default)

* Widens the **TD-110 laser turret + gatling main gun** and the **TD-220 main gun + coaxial HMG** horizontal
  traverse from ±20° to **±180°**; independent of the selected mode; turning the toggle off writes ±20° back;
* Read live by the engine — applies immediately, no re-summon needed;
* ⚠ **Horizontal only — the camera / view limits are NOT removed.**
* **M-102 has no traverse leg** — its vehicle weapon has no turret record in the game data.

### 3. M-102 vehicle weapon — three choices (new in v1.1.0)

* **stock vehicle HMG** (`frv_mg`, default) ⇄ **HMG turret** ⇄ **40mm autocannon turret**;
* Writes **both variants** in one go: `M-102 Fast Recon Vehicle` and `M-102 Fast Recon Vehicle (Map Spawn)`;
* Changing a mount requires **re-summoning** the M-102.

### 4. Per-vehicle independence (new in v1.1.0)

The mount leg locates, verifies and writes **each vehicle separately**: if one vehicle's record is missing or its
mount node does not match, **only that vehicle is skipped** (the log says which and why) — the others still apply.
The TD-110 no longer stops working because another vehicle's data changed.

### 5. TD-110 hard rule: exactly one of the two slots is a laser

* **One is required**, **two are refused** (they fight over designation);
* A refused change is logged and the UI control snaps back — the same applies in *custom* mode.

### 6. Change it as often as you like / one-click restore

* Modes and sub-options can be switched back and forth: the overwrite check accepts any mount this mod may have
  written before, not just vanilla;
* **Initialize** (the Scanner group's global button) restores everything at once — and can force its way back even
  when another mod wrote an unrecognised value into the slot.

## Operation flow

1. Install **Bingus Shared Loader v15+ (API 1)** (or a compatible MDL).
2. Install **Mod Options Menu v1.1+** (the native MODS page).
3. Install **HD2 Scanner v0.8.2+** — a **hard requirement**: it supplies the table addresses. Without it the mod writes nothing.
4. Import `Armor-Tweaks-v1.1.0.zip` in your HD2 mod manager and enable/deploy it.
5. Launch the game → **ESC → MODS page → `A HD2 MOD COLLECTION`** → pick presets / slots / ammo type.
6. **After dropping into a mission, do not summon a vehicle yet** — wait until the log shows the mounts were written.
7. Changing a loadout later requires **re-summoning that vehicle**. Traverse and ammo type are exempt (apply live).

```text
[ArmorTweaks] 已接上 HD2Scanner（前置）：挂载表 + 射界表由 Scanner 提供
[ArmorTweaks] 已写：TD-110 驾驶员位(+48) … -> …（recIdx 123，node/flags 未动）
[ArmorTweaks] 已写：M-102 车载武器位(slot0) = 重机枪武器站 … -> …（recIdx 19，node/flags 未动）
```

## Requirements

* **Helldivers 2** (tested on `1.8.45850.0`)
* **Bingus Shared Loader v15+ (API 1)**, or a compatible MDL
* **Mod Options Menu v1.1+**
* **HD2 Scanner v0.8.2+** — **required**; without it the mod writes nothing and only logs the reason
* An HD2 mod manager able to import zips (HD2MM / Arsenal …)
* Windows x64

## Compatibility

* **Replaces** `TD-110-Co-Op` and `TD-110-Busier-Driver` (deprecated, no longer distributed) — do not run them together.
* **v1.1.0 keeps the same GUID / module id as v1.0.0** — it is the same entry in your mod manager, just swap the package.
* Local memory only: **other players in co-op will not see your changes** (the mod sends no network packets).
* **Per-vehicle independence**: an unrecognised vehicle is skipped on its own, the others still apply.
* If another mod writes a value this mod does not recognise, it **refuses to overwrite** it; use **Initialize** to force vanilla back.
* The game runs nProtect GameGuard; use third-party tools at your own risk.

## Known limits

* **Mounts are read once, when a vehicle spawns**: re-summon the vehicle after changing the loadout. Traverse and ammo type are read live.
* The **M-102 HMG turret / 40mm autocannon turret** reuse normal mount items, but their **mount node differs from the
  stock `frv_mg`** — **written and read back successfully in-game on 2026-10-05** (both variants: recIdx 19 and 117, zero refusals);
  if it misbehaves on your build, switch back to the stock vehicle HMG.
* The **M-104 flamethrower is not offered** (that weapon has resource-loading problems; user decision, 2026-10-05).
* **Horizontal traverse only**: the camera/view limits stay as-is, so the turret turns further than you can look.
* The *Busy* mode's **HMG turret** is **not a real mount entry** in the game data (it is a standalone weapon entity),
  so it uses its own default ammo setup. An older build patched its magazine to 1000 rounds — **removed on request**.
* Settings use **ModOptionsMenu** (toggles / fixed choices only) — **no free text input**; edit the cfg for custom hashes.

## Logs

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ArmorTweaks.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ArmorTweaks_STATUS.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log
```

## Shout outs

* **Bingus** — Shared Loader, the `Addon` toolchain and the ModOptionsMenu reference;
* **xypwn** — [filediver](https://github.com/xypwn/filediver); its plain-text `datalibrary` plus the game typelib
  are the source of every field offset and record size used here;
* **CowboyBingus** — ModOptionsMenu / panel and logging conventions.
