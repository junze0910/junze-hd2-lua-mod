# Guard Dog Loadout

**Download:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest
**Version:** v1.0.1

## Description

A configurable mounted-weapon mod for the Helldivers 2 **Guard Dog** (machine gun drone, `drone_mg`).

Choose what the drone carries:

- vanilla **AR-23P**
- **SEAF MG-43** (kinetic, more firepower)
- **any item hash you provide**

It replaces the old `Stronger Kinetic Guard Dog`, which hard-coded MG-43 — changing weapons meant
building another package, and running both packages just overwrote each other.

Only **8 bytes of one record** are written. All changes are runtime memory patches. No game files
are modified. Disable the mod and restart the game to fully restore.

## Features

* Mounted weapon: **3-way selectable** — vanilla AR-23P / SEAF MG-43 / custom hash
* **`AR-23P (vanilla)` means "write nothing"**: if the drone is already vanilla there are zero writes;
  if an older mod changed it, vanilla is written back
* Custom hash is read from a cfg file and **hot-reloaded within 1 second** (no restart)
  * invalid values (`0x` prefix, wrong length, all-zero, empty) are **refused** and logged
  * ⚠ the hash is **not validated semantically** — an unknown item hash is written as-is
* **Switch back and forth freely** — the write guard also accepts the value this mod wrote last,
  so it never gets stuck on "one change per slot"
* **Foreign values are refused**, not overwritten (a deliberate guard; use *Initialize* to force)
* **One-click Initialize**: force-writes vanilla and resets the cfg to defaults
* Any change (MODS page or hand-edited cfg) triggers a write **immediately** — no manual "write now" needed
* An automatic 300-frame **re-check** restores clobbered patches
* No game files modified; fully reversible by disabling the mod and restarting

## Operation flow

### 1. Install prerequisites

1. Install **Bingus Shared Loader v15+ (API 1)**, or a compatible MDL;
2. Install **HD2 Scanner v0.7.0+** (supplies the mount table address — **required by this mod**);
3. Install **Mod Options Menu v1.1+** (native MODS settings page; without it you can still edit the cfg by hand);
4. Import `GuardDogLoadout-v1.0.1.zip` with your HD2 mod manager, enable and deploy;
5. Start the game.

### 2. Choose the mounted weapon

On the **native MODS page**: ESC → **MODS** → **Guard Dog Loadout** → `Mounted weapon` (3-way).

Changes are written **immediately** — no separate Apply step.

> The **full cfg path is shown on the right-hand description pane**, if you prefer to edit the file by hand.

> Picking **AR-23P (vanilla)** will **not** change anything — that option literally means "write nothing".

### 3. Custom hash (optional, editable outside the game)

1. Open `%LOCALAPPDATA%\CowboyBingus\Helldivers2\GuardDogLoadout.cfg`;
2. Set:

```text
weapon=custom
custom=587878FB76F4B9B1
```

3. Save — it takes effect **within 1 second**, no restart and no button press.

### 4. Enter a mission — do not deploy the Guard Dog yet

⚠ **This is the easiest trap in this mod**: the mount table (`MountComponentData`) is a static
configuration read **once, when the drone is spawned**, so the patch must land *before* deployment.

1. After entering a mission, **do not deploy** the Guard Dog yet;
2. Wait for these two lines in the log:

```text
[GuardDogLoadout] 已接上 HD2Scanner（前置）：MountComponentData 由 Scanner 提供
[GuardDogLoadout] 已写：drone_mg 挂载 7933E1BDE32126A3 -> 587878FB76F4B9B1（recIdx 97，node=0x53BEC437/pad=0 未动）
```

3. **Then** deploy the Guard Dog.

### 5. Deploy and verify

The drone you deploy uses the current configuration. You can check at any time:

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\GuardDogLoadout_STATUS.log
```

If the first line reads `OK - 补丁生效中（1 处）`, the patch is live.

### 6. Later changes

After every configuration change:

1. Change the selection on the MODS page (or edit the cfg directly);
2. Wait for a fresh `已写：…` line in the log
   (switching between MG-43 and another value logs one immediately; switching back to vanilla
   writes `A32621E3BDE13379` back);
3. **Re-summon / redeploy** the Guard Dog — an already-deployed drone will not follow the change.

### 7. Initialize

To return to the original defaults:

1. On the MODS page, turn on the **Initialize** switch under *Guard Dog Loadout*;
2. It will:
   - write the mounted weapon back to **vanilla AR-23P**
   - reset the cfg to defaults (`weapon=ar23p` / `custom=` empty)
   - clear the write state;
3. The log will read:

```text
[GuardDogLoadout] 初始化：已强制写回原装，cfg 复位为 AR-23P（原装）
```

## Requirements

* **Helldivers 2** (v1.0 verified in-game on `1.8.45850.0` + loader v17)
* **Bingus Shared Loader v15+ (API 1)**, or a compatible MDL
* **HD2 Scanner v0.7.0+** — required (table address source)
* **Mod Options Menu v1.1+** — settings UI prerequisite (native MODS page; without it edit the cfg by hand)
* HD2 mod manager able to import zip packages (HD2MM / Arsenal)
* Windows x64

Required prerequisite: **HD2 Scanner**. Without it this mod performs **zero writes** and only
logs the reason (it never writes blindly). Without Mod Options Menu there is no in-game settings
page, but you can still edit the cfg by hand (hot-reloaded within 1 second).

## Logs

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\GuardDogLoadout.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\GuardDogLoadout_STATUS.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log
```

## Notes

* Only the mounted weapon is touched — 8 bytes of one record; `node`/`pad` and the other 112 bytes are left alone.
* The mount table is read **once, when the drone is spawned** — re-summon / redeploy after changing the setting.
* Picking **AR-23P (vanilla)** and seeing no change is **expected** — that option means "write nothing".
* The custom hash is **not validated semantically**; an unknown item hash may make the drone spawn incorrectly.
* Replaces `Stronger Kinetic Guard Dog` — pick **one** of the two, they write the same slot.
* Not visible to other players in online play.
* Runtime-only memory patch; disable + restart to fully restore.
* Helldivers 2 uses nProtect GameGuard; use third-party tools at your own risk.