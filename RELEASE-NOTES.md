# v1.0.1 — 四个 mod（新增 TD-110 Co-Op，以及它的备选「更忙的 TD-110 驾驶员」）

> GitHub Release 建议用 tag **`v1.0.1`**（`v1.0` 这个 tag 已指向上一版、只有两个 mod）。
> 下面这段可直接整篇粘到 Release 说明里。

**日期**：2026-09-25 ｜ **验证环境**：Helldivers 2 `1.8.45850.0` + Bingus Shared Loader **v16（API 1）**

## 这个版本有什么

### 🆕 TD-110 Co-Op（更强调合作的 TD-110）

对**风暴漩涡坦克（TD-110, `tank_storm`）** 做两件事：

1. **激光指示器的水平射界 ±20° → ±180°**（改 `TurretComponentData` 里那条记录的 `+28`/`+32`）；
2. **两个挂载位按位置对调**：炮手位 `+24` ← 烟雾弹发生器（`4181046937756232139`）， 驾驶员位 `+48` ← 激光指示器（`14081448954912365533`）；挂载 node 与其它字段**一律不动**。

已实机验证：射界 ±180° 生效、挂载对调生效，并且多轮复查都保持（不会被游戏冲掉）。

### 🔀 备选方案：Busier TD-110 Driver（更忙的 TD-110 驾驶员）

如果你**不想对调挂载**、只想让驾驶员位拿到一件能用的真武器，就用这个：

* 把 TD-110 记录（`MountComponentData`，ID 123）里 `+48` 的 **烟雾弹发生器 → 手操重机枪炮台**
  （`14005565984326167830` / `0xC25DC40EDE0E2D16`，一个可被驾驶员操作的实弹炮台，比 `manned_turret` 依赖的组件更少）；
* 它和 **TD-110 Co-Op 改的是同一条记录的同一个槽位（`+48`）**，所以两者**二选一**，同时启用会互相覆盖；
* 同样适用下面那条时序规则：**先等日志出现"已替换"，再召唤载具**。

### ♻️ 另两个 mod（本次重新打包，版本号统一为 v1.0）

| Mod | 作用 |
|---|---|
| **AC-8 Cut-Content 75rnd Backpack** | AC-8 机炮包架的背包：原版 50 发 → **废案 75 发** |
| **Stronger Kinetic Guard Dog** | 机枪犬挂载的武器 → **SEAF MG-43（实弹）**，火力更强 |

## ⚠️ 装 TD-110 Co-Op 必读（实机踩出来的时序规则）

`MountComponentData`（挂载表）是引擎**生成载具时读一次**的静态配置 —— 所以补丁必须**早于召唤载具**：

1. 进任务后**先别召唤**坦克；
2. 等 `TankStormCoop.log` 出现 **`挂载补丁已就绪：现在可以召唤 / 重新召唤载具了`**
   （或 `TankStormCoop_STATUS.log` 里 `挂载状态 = 已就绪 ✓ 现在可以召唤 / 重新召唤载具`）——
   正常在进任务后 **10~60 秒**内出现；
3. **再**召唤 / 重新召唤载具。

> 同一个 mod 里的**射界**是引擎**实时读**的值，什么时候打进去都生效，不需要等。

**互斥**：`TD-110 Co-Op` 与 `TD-110 Better Driver Armament` 都改 TD-110 驾驶员挂载位（`+48`），**二选一**。
另外不要与 `TD-110 Yaw Probe` 同时启用（那是诊断包，会给射界写对照用的标记值）。

## 安装 / 更新

1. 从 `dist/` 拿包（或直接用 mod 管理器导入）：

   | 文件 | Mod |
   |---|---|
   | `TD-110-Co-Op-v1.0.zip` | 更强调合作的 TD-110 |
   | `TD-110-Busier-Driver-v1.0.zip` | 更忙的 TD-110 驾驶员（与上一个**二选一**） |
   | `Guard-Dog-MG43-v1.0.zip` | 更强的实弹狗 |
   | `AC8-Rack-Backpack-v1.0.zip` | AC-8 废案 75 发备弹背包 |

2. 管理器里：**删掉旧条目 → Purge → 导入新包 → 启用 → Deploy**
   （Arsenal 不是覆盖式更新，只导入不 Purge 可能还是旧包在跑）；
3. **不要**手动把包里的 `Addon/` 拷进游戏 `data/`（多个 addon 包内文件名相同，会互相覆盖）。

## 包完整性校验

`dist/SHA256SUMS.txt` 里是三个包的 SHA-256：

```powershell
cd dist
certutil -hashfile TD-110-Co-Op-v1.0.zip SHA256
# 或一次看全：
Get-FileHash *.zip -Algorithm SHA256 | Format-Table -AutoSize
# Linux / Git Bash：
sha256sum -c SHA256SUMS.txt
```

哈希对不上就别装。

| 包 | SHA-256 |
|---|---|
| `TD-110-Co-Op-v1.0.zip` | `68f26fb77a8b515af29e6ee0d2bfc931ff10ed71ed2800035aab94e5df3b01d2` |
| `TD-110-Busier-Driver-v1.0.zip` | `af55feecae17b95025e79dd53e0606d9af87b84a4ec8a969a789607e8cba6400` |
| `Guard-Dog-MG43-v1.0.zip` | `322974a874ed123a8c1c1f6af04373f329575b6a1a47dd1380a921058ad25ce7` |
| `AC8-Rack-Backpack-v1.0.zip` | `a1e53ec459d162703928657d4cded1cec3148b50cdfd0e217e22d51a95de3044` |

## 依赖

* **Bingus Shared Loader v15 或更高**（loader 日志首行 `Bingus Shared Loader loader-v1x; API 1`）；
* 任一支持 zip 导入的 HD2 mod 管理器（HD2MM / Arsenal 等）。

## 免责声明

非官方作品，与 Arrowhead Game Studios / Sony Interactive Entertainment 无任何关联；
仅在游戏运行时修改本机内存，**不分发任何游戏资产**。游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

---

## English (summary)

**v1.0.1 — three mods, now including TD-110 Co-Op**

* 🆕 **TD-110 Co-Op** — TD-110 storm tank: laser designator yaw **±20° → ±180°**, and a positional loadout swap
  (gunner slot `+24` ← smoke launcher, driver slot `+48` ← laser designator). Verified in game.
* 🔀 **Busier TD-110 Driver** — the alternative to the above: driver slot `+48` **smoke launcher → manually-operated
  heavy MG turret** (`14005565984326167830`). Mutually exclusive with TD-110 Co-Op (same slot).
* ♻️ **AC-8 Cut-Content 75rnd Backpack** / **Stronger Kinetic Guard Dog** — repacked, all versions unified to v1.0.
* ⚠️ **Timing rule for TD-110 Co-Op**: `MountComponentData` is read **once when a vehicle spawns** — after dropping into
  a mission, **wait for `挂载补丁已就绪` in the log, then summon the vehicle**. (The yaw limit is read live — no waiting needed.)
* ⚠️ `TD-110 Co-Op` and `TD-110 Better Driver Armament` **rewrite the same slot (`+48`)** — enable only one of them.
* Install through a mod manager (delete old entry → Purge → import → Deploy). Requires Bingus Shared Loader v15+.
