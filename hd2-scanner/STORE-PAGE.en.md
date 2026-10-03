# HD2 Scanner

**Download:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest

## Description

HD2 Scanner is a core / prerequisite service mod. It does not add weapons, skins or gameplay content.

It provides:

1. Background discovery of LDLD data tables in game memory.
2. Table address broadcast to other mods through `_G.HD2Scanner`.
3. A generic full-memory scan service, `memscan`, so other mods do not each rescan several GB of memory.
4. **AOB stratagem-table lookup**: resolves the `StratagemSettings` record pointer array from `game.dll`,
   so consumers can read records by id directly (this is how ExoLoadout attaches stratagems - no full scan).

Current consumers:

- AC-8 Rack Backpack
- Guard Dog MG-43 / GuardDogLoadout
- EXO Loadout

## Features

* Data table broadcast:
  * MountComponentData
  * HellpodRackComponentData
  * HellpodPayloadComponentData
  * WeaponMagazineComponentData
  * TurretComponentData
  * ProjectileSettings
  * ExplosionSettings
* Generic full-memory scanning via `scan_request` / `scan_cancel` / `scan_status`:
  * 256 KB chunks with overlap
  * 8 MB per frame budget
  * self-pattern skip
  * request queue, one scan at a time
  * returns only addresses; consumers validate and write
* AOB stratagem-table lookup (v0.8.0+):
  * API: `strat_table_request` / `strat_table_status` / `strat_table_base` / `strat_slot` / `strat_rec`
  * matches a fixed instruction pair in `game.dll` code, **unique match required** (ambiguous = give up)
  * stepped across frames (2 MB/frame), never blocks the game
  * every failure returns a reason, so consumers can fall back
  * see `Scanner-API.md` section 4
* Read-only: Scanner never writes game data tables
* Registers **3 rows in the native MODS tab** (needs Mod Options Menu):
  **scan status** (click = run one round now; the description box shows live state),
  **resolve stratagem table (AOB)**, and **write diagnostics to log**
* Self-check 11/11: decoders match the MDL reference bit-for-bit
* Stable scanning: 7 table hits per round in live play
* Log: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log`

## Usage

1. Install Bingus Shared Loader v15+ (API 1) or compatible MDL.
2. Import `HD2-Scanner-v0.8.0.zip` with your HD2 mod manager.
3. Enable and deploy.
4. Launch the game. Scanner runs in the background; no user action is required.
5. Check `HD2Scanner.log` if needed.

## Requirements

* Helldivers 2
* Bingus Shared Loader v15+ (API 1) or compatible MDL
* HD2 mod manager able to import zip packages (HD2MM / Arsenal)
* Windows x64

## Compatibility

* Used as a prerequisite by other mods; enabling it alone does not change gameplay.
* Read-only memory scanning; no game files are modified.
* Helldivers 2 uses nProtect GameGuard; use third-party tools at your own risk.

## Logs

`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log`