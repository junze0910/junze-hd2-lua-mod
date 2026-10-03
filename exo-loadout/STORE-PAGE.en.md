# EXO Loadout (Mech Custom)

**Download:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest
**Version:** v0.8.0

## Description

A configurable EXO stratagem loadout mod for Helldivers 2.

**Supports in-game modification.** All options are changed directly from the native
MODS tab in the ESC menu, with no external config editor required.
Choose:

- which exosuit you carry
- whether to carry an additional exosuit
- which left/right arm weapons each of the two exosuits uses

It replaces the old `More-Balanced-Exosuit-Patriot` / `Emancipator` one-of-two packages.
Only one `additional_stratagem` record is written, so the two records can no longer
reference each other and cause a stratagem loop.

All changes are runtime memory patches. No game files are modified. Disable the mod
and restart the game to fully restore.

## Features

* In-game modification through Mod Options Menu (ESC -> MODS tab)
* Carry exosuit: Patriot EXO-45 / Emancipator EXO-49 / Breacher EXO-55 / Lumberer EXO-51
* Additional exosuit: none / one of the other three (self-reference rejected)
* Left and right arms configured separately:
  * left slots only list left-hand items
  * right slots only list right-hand items
  * cross-body arm swap is allowed only between the currently carried two exosuits
* Writes `additional_stratagem` on the carried record only; the additional record is left untouched
* Writes `use = 2` on both carried and additional records; cooldown is never touched
* **No manual scan needed**: Scanner resolves the stratagem record pointer array by AOB and the mod writes directly
* Full-memory `package` search only as a **fallback**: the MODS-page toggle is labelled
  "fallback: full-memory scan (normally not needed)" and its description box shows the live state
* One-click initialization back to the original default state
* No game files modified; fully reversible by disabling the mod and restarting

## Operation flow

### In-game modification

The mod is designed to be configured entirely in game:

1. Press ESC and open the MODS tab.
2. Select EXO Loadout.
3. Change the carried exosuit, additional exosuit, and left/right arm choices.
4. Press Apply.
5. Done — the write is automatic (Scanner resolves the record by AOB; **no scan to run**).

No cfg file editing or external tool is needed.

### 1. Install prerequisites

1. Install Bingus Shared Loader v18+ (API 1) or compatible MDL.
2. Install Mod Options Menu v1.1+ (native MODS settings tab).
3. Install HD2 Scanner v0.8.0+ (arm table addresses + AOB stratagem-table lookup).
4. Import `ExoLoadout-v0.8.0.zip` with your HD2 mod manager, enable and deploy.
5. Launch the game.

### 2. Open the settings

1. Press ESC.
2. Go to the MODS tab.
3. Select EXO Loadout.

### 3. Configure

1. Carry exosuit: choose one of four.
2. Additional exosuit: none or one of the other three.
3. Carry left arm / right arm: choose the arm items.
4. Additional left arm / right arm: choose the arm items.
5. Press Apply.

### 4. How the record is located (nothing to do)

HD2 Scanner v0.8.0+ resolves the stratagem **record pointer array** by an AOB in `game.dll`
and reads the record by id — **no scan toggle, no waiting**. After you press Apply the log shows:

```text
AOB 定位：爱国者 -> 0x... (id)
已改战备附加：爱国者 -> 解放者（+32，宽度 1）
```

The only case that needs you: if the log says `AOB 战备表解析失败 ... 先走兜底` (the game updated
and the instruction pair moved). Then open **"fallback: full-memory scan (normally not needed)"**
on the MODS page — its **description box** shows the current state
(`AOB 直取已就绪 —— 不需要点这个开关` / `AOB failed (reason) -> this switch is needed`).

### 5. Make the additional stratagem take effect

The exosuit stratagem list is normally built when entering a mission.
If you change it while already in a mission, return to the ship and enter a mission
again to see the additional stratagem entry.

### 6. Later changes

After changing any option:

1. Press Apply — the write is **automatic** (AOB lookup); no scan toggle needed.
2. Only if the fallback message above appears, turn on the fallback scan switch.
3. Re-enter the mission if needed.

### 7. Initialize

Turn on the Initialize toggle and press Apply.
It restores:

- original `additional_stratagem` / `use`
- original arm items
- default CFG: Patriot + no additional + original arms

## Requirements

* Helldivers 2 (tested on Steam build `25480438` / EXE `1.8.46015.0`)
* Bingus Shared Loader v18+ (API 1) or compatible MDL
* Mod Options Menu v1.1+ (settings UI prerequisite)
* HD2 Scanner v0.8.0+ (arm table addresses + AOB stratagem-table lookup; older Scanner falls back to the full-memory search)
* HD2 mod manager able to import zip packages (HD2MM / Arsenal)
* Windows x64

Required prerequisites: Mod Options Menu and HD2 Scanner.
Without Mod Options Menu only the legacy panel fallback is available; without
HD2 Scanner the arm modification leg is unavailable.

## Logs

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\ExoLoadout.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log
```

## Notes

* Not visible to other players in online play.
* Runtime-only memory patch; disable + restart to fully restore.
* Helldivers 2 uses nProtect GameGuard; use third-party tools at your own risk.