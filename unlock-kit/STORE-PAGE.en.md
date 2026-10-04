# Unlock Kit

**Project / download:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest
**Current version:** v0.6

## Description

Turns "unlock X" into an **on/off switch per target** on the game's native **ESC → MODS page** — writing on enable, reverting on disable.

- **2 weapons**: P-41 Ombudsman (sidearm), G-11 Incendiary (throwable) — done by **cloning a same-class template and replacing identity fields only**
- **6 stratagems**: Orbital Illumination Flare / FRV Resupply (M-103) / Fast Recon Vehicle (M-102) / FRV Incinerator (M-104) / Eagle Air-to-Air Missiles (unused entry) / Maelstrom
- **One read-only recon row**: prints target key / registered? / template index / stratagem record and selectable bit
- Everything happens in **runtime memory** — no game files are modified; disable the mod and restart to fully revert

> ✅ **v0.6 is in-game verified** (user confirmed, 2026-10-04): both weapons, all 6 stratagems and the read-only recon work.
> ⚠️ **Explicit whitelist only — there is no "unlock everything".** **No attachment unlocks** (removed in v0.6, see below).

## Features

### 1. One switch per target

Under the native **ESC → MODS page → "解锁台"** group; enabling writes immediately, disabling rolls back precisely (per row).

### 2. Weapon unlock = clone a same-class template, identity fields only

The template's 184-byte registry record and 24-byte mapping (P-41 ← P-2, G-11 ← G-6) are copied **byte-for-byte** to the append slot;
only `+0x00/+0x04/+0x08` are replaced, and `count` is published last. In-game verified: both weapons appear in the armory.

### 3. Stratagem unlock = selectable bit + record state

- `StratagemInfo +0x80 bit1 = 1` (equals the data table's `selectable`)
- registry record `+0x14 = 2` (2 or 4 means available/registered)

In-game verified for 6 stratagems (ID 5 / 26 / 105 / 135 / 146 / 50).

### 4. Auto-applied on every launch

The registry is rebuilt each session and memory writes are session-scoped, so every launch the mod re-writes whatever switches are still ON.

### 5. Re-checked every 5 seconds

Weapon entries and stratagem bits/records are re-verified and restored if the game reverts them.

### 6. Session-scoped and revertible

Writes only live in the current game process; restart the game to go fully stock. To revert immediately, turn the switch **off**.

### 7. Read-only recon

The `● 侦察（只读）` toggle prints the current state once and writes nothing — useful for troubleshooting.

## Operation flow

1. **Install the prerequisite**: Bingus Shared Loader **v15+** (its `ModOptionsMenu` provides the MODS page)
2. **Install** `Unlock-Kit-v0.6.zip`
3. **Enter one mission** (registry / upgrade trees only load in-mission)
4. **Configure**: ESC → MODS → "解锁台" → enable the switches you want
5. **Takes effect** immediately on enable; the stratagem list is built on mission start, so changes usually show up **next mission**

## Requirements

| Component | Version |
|---|---|
| Bingus Shared Loader | **v15+** (API 1; verified on loader-v17) |
| HD2 Scanner | **Optional** (used when present for the stratagem table, otherwise a built-in signature fallback) |
| Game build | `helldivers2.exe` 1.8.46015.0 (Steam build 25480438) |

## Compatibility

- Writes only the **listed targets'** registry records/mappings and their `StratagemInfo` selectable bit; nothing else
- Coexists with other mods; but mods writing the **same stratagem record** (e.g. Strat-Unlock) touch the same memory — install only one of them
- No new slots, no slot count changes; **no attachment unlocks**

## Known limits

- **No "unlock everything"** — the target list is an explicit whitelist in the source
- The stratagem list is built on mission start → changes usually appear next mission
- **Weapon-attachment (JAR-5 ammo) unlocking was removed**: v0.5 wrote everything successfully but **opening the Dominator customization page crashed the game** (line parked by the author)
- A game update may break locating — the mod then **refuses to write** and logs it

## Logs

```
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\UnlockKit.log
```

Expected: `★ P-41 … 追加完成 count …` (weapons) or `★ 战备 …：选择位 +0x80 … → 0x03` + `记录#… +0x14 … → 2`.

## Shout outs

- **LAS-22 Shear** (`_inspect/shear`) — the reference implementation for "clone a same-class template" and the stratagem three-condition recipe
- **CowboyBingus / Bingus Shared Loader** — addon loader and the native `ModOptionsMenu` MODS page
- **HD2 Scanner** — AOB stratagem-table locator (used when present, as an optional speed-up)
- `Helldivers2_RawData` — plain-data component tables (basis for offsets and "selectable bit")
