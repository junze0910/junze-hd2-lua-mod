# Custom Supply

**Project / download:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest
**Current version:** v0.1e (dev build, in-game verified, unpublished)

## Description

Turns the supply rack's **4 slots** into something you configure: **what you put in decides what the supply drops — how much you put in decides the cooldown.**

- Upper slots: one of 7 items — `None / Ammo box / Stim box / Grenade box / Supply crate / Medical crate / Explosive Barrel`
- v0.1e adds **SEAF Artillery Override**: when the Super Earth Artillery exists, manually enable it and fill the lower 4 slots with 6 shell types / Explosive Barrel; choosing `Supply` falls back to the upper slot
- Cooldown is computed from the effective contents: **30 s (all four empty / explosive barrels) up to 150 s (four stim boxes / supply crates / Mini Nukes)**
- Everything happens in **runtime memory** — no game files are modified; disable the mod and restart to fully revert

## Features

### 1. Four independent slots

Configured in the game's native **ESC → MODS page → "自定义补给"**, four independent dropdowns.

### 2. Contents decide the cooldown

| In the slot | Added cooldown |
|---|---:|
| (empty) | +0 s |
| Ammo box | **+5 s** |
| Stim box | **+30 s** |
| Grenade box | **+15 s** |
| Supply crate | **+30 s** |
| Medical crate | **+15 s** |
| Explosive Barrel | **+0 s** |

```
cooldown = 30 + 5·ammo + 30·stim + 15·grenade + 30·supply_crate + 15·medical_crate
         + 0·explosive_barrel
```

| Example | Cooldown |
|---|---:|
| empty ×4 ← **default** | **30 s** |
| ammo ×4 | 50 s |
| grenade ×4 / medical ×4 | 90 s |
| ammo + stim + grenade + medical | 95 s |
| stim ×4 / supply crate ×4 | **150 s (cap)** |
| Explosive Barrel ×4 (or all four empty) | 30 s |

### 3. Placement is applied automatically

Stim boxes and grenade boxes get a tuned offset/rotation on the rack; the Explosive Barrel and the other items keep zero.

### 2.5 SEAF Artillery Override (v0.1e)

Only for missions where the **Super Earth Artillery / SEAF Artillery** exists; the player enables the toggle manually.

- **Off** (default): only the upper 4 supply slots are read; the lower 4 are ignored.
- **On**: the four new "Artillery slots" take effect one by one:
  - `Supply` → reuse the corresponding upper supply slot (CD and placement);
  - shell / Explosive Barrel → use the lower selection.
- The two layers are **independent** — no syncing.

| Lower choice | Added cooldown |
|---|---:|
| Supply | from upper slot |
| Mini Nuke (SEAF) | +30 s |
| High-Yield Explosive (SEAF) | +20 s |
| Explosive (SEAF) | +15 s |
| Napalm (SEAF) | +10 s |
| Static Field (SEAF) | +10 s |
| Smoke (SEAF) | +5 s |
| Explosive Barrel | +0 s |

All shells use offset/rotation `(0,0,0)/(0,0,0)`.

### 4. Self-contained

No separate unlock mod needed — it makes the supply stratagem usable on its own.

### 5. Re-checked every 5 seconds

Selection bit / availability state / cooldown / the 4 slots are re-verified and restored if the game reverts them.

### 6. Session-scoped and revertible

Writes only live in the current game process; restart the game and everything is stock again.

## Operation flow

1. **Install prerequisites**: Bingus Shared Loader (v15+ / API 1) + **HD2 Scanner v0.8.0+** (required for table location)
2. **Install** `Custom-Supply-v0.1e.zip`
3. **Enter one mission** (the stratagem/rack tables only load in-mission)
4. **Configure**: ESC → MODS → the group, four upper dropdowns; if the Super Earth Artillery exists, manually enable **SEAF Artillery Override** and configure the four lower Artillery slots; each description shows the live cooldown
5. **Takes effect** immediately; if changed mid-mission, from the next mission

## Requirements

| Component | Version |
|---|---|
| Bingus Shared Loader | v15+ (API 1) |
| HD2 Scanner | **v0.8.0+** (required) |
| Game build | `helldivers2.exe` 1.8.46015.0 (Steam build 25480438) |

## Known limits

- No "reset" button; no preset combos (four independent slots)
- **Both the Explosive Barrel (v0.1d) and the SEAF Artillery Override (v0.1e) have been in-game verified** (user confirmed, 2026-10-04)
- What teammates see is **unverified** (depends on their own game data)
- A game update may break locating — the mod then **refuses to write** and logs it

## Logs

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\CustomSupply.log
```