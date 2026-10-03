# AC-8 75-Round Autocannon Backpack

**Download:** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest
**Version:** v2.1

## Description

Replaces the backpack on the AC-8 autocannon stratagem rack with the cut-content
75-round backpack.

Only the backpack entity on the rack is replaced. The autocannon itself, damage,
and ballistics are unchanged.

Runtime memory patch only: no game files are modified. Disable the mod and restart
the game to fully restore.

## What changes

> **v2.1**: UI-retirement alignment only — the self-drawn panel page (which could never be shown;
> the HD2Menu system was retired on 2026-10-04) is gone, and a *write once now* row was added to the
> native MODS page. **The write and lookup logic is unchanged.**


| Item | Vanilla | This mod |
|---|---|---|
| Backpack entity | `E60AE045E0090F4C` (50 rounds) | `26BDDF070C31B275` (75 rounds) |
| Rack slots | left and right backpack entries | s1 and s3 are both replaced |
| Autocannon | unchanged | unchanged |
| Damage / ballistics | unchanged | unchanged |

> Both backpack entries must be replaced together; otherwise one side stays vanilla.

## Features

* 50 -> 75 rounds
* Content-anchor lookup:
  * locate the table by `LDLD + version + type hash`
  * does not depend on table size, index count, record size, or record index
  * uses the old backpack hash as an anchor and verifies the AC-8 rack context
* All table copies in memory are patched
* Idempotent: already-patched entries are skipped
* Periodic recheck: if the game reloads the table, the patch is reapplied
* HD2 Scanner prerequisite:
  * address comes from the HD2 Scanner broadcast by default
  * if Scanner is missing, the mod does nothing and never writes blindly
  * rollback flag `AC8_USE_SELF_SCAN = true` restores the legacy self-scan path

## Usage

> **New row on the MODS page**: *write once now* - re-applies the patch to every address
> Scanner broadcasts, then pops back. You normally never need it (writing is automatic); it is
> there for re-writing on demand. Progress goes to `AC8RackBackpack.log`.


1. Install Bingus Shared Loader v15+ (API 1) or compatible MDL.
2. Install HD2 Scanner v0.7.0+.
3. Import `AC8-Rack-Backpack-v2.0.zip` with your HD2 mod manager, enable and deploy.
4. Launch the game.
5. Enter a mission. The mod receives the table address from Scanner and patches it automatically.
6. Check the log:

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack.log
```

Success looks like:

```text
已替换：表 0x... s1 / s3 E60AE045E0090F4C -> 26BDDF070C31B275
已写 2 处
```

Without Scanner:

```text
地址来源 = 无 —— 缺 HD2Scanner 前置，本 mod 不工作
```

## Requirements

* Helldivers 2
* Bingus Shared Loader v15+ (API 1) or compatible MDL
* HD2 Scanner v0.7.0+ (required prerequisite)
* HD2 mod manager able to import zip packages (HD2MM / Arsenal)
* Windows x64

## Compatibility

* Only the two backpack entities in the AC-8 rack record are changed.
* May conflict with other mods that modify the same backpack hash.
* Client-side memory patch; other players usually do not see it.
* Helldivers 2 uses nProtect GameGuard; use third-party tools at your own risk.

## Logs

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack_STATUS.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack_Patch.log
```