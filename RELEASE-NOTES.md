# v1.2.1 — 模组合集（6 个 mod）

> GitHub Release 用 tag **`v1.2.1`**，附件是全部 6 个 mod 的包 + `SHA256SUMS.txt`。
> 上一版 `v1.0.1` 只有 4 个 mod；`v1.2` 是外骨骼两版的首发。

**日期**：2026-09-25 ～ **验证环境**：Helldivers 2 `1.8.45850.0` + Bingus Shared Loader **v16（API 1）**

## 📦 合集内容（6 个 mod）

| # | 包 | 管理器内名称 | 作用 |
|---|---|---|---|
| 1 | `AC8-Rack-Backpack-v1.0.zip` | **AC-8 Cut-Content 75rnd Backpack** | 把「AC-8 机炮」包架上的背包，从原版 **50 发**备弹换成**废案版本 75 发**备弹背包 |
| 2 | `Guard-Dog-MG43-v1.0.zip` | **Stronger Kinetic Guard Dog** | 机枪犬（`drone_mg`）挂载的武器 → **SEAF MG-43（实弹）**，火力更强 |
| 3 | `TD-110-Co-Op-v1.0.zip` | **TD-110 Co-Op** | 暴风漩涡坦克（TD-110）激光指示器水平射界 **±20° → ±180°**；炮手位 `+24` → 烟雾弹发射器、驾驶员位 `+48` → 激光指示器（按位置对调） |
| 4 | `TD-110-Busier-Driver-v1.0.zip` | **Busier TD-110 Driver** | TD-110 驾驶员位 `+48` 的烟雾弹发生器 → **手操重机枪炮台**（可被驾驶员操作的实弹炮台）。**与 #3 二选一**（改同一个槽） |
| 5 | `More-Balanced-Exosuit-Patriot-v1.1.zip` | **More Balanced Exosuit - Patriot** | **携带爱国者外骨骼战备时，额外携带解放者外骨骼战备**；同时挂载对调 + 两台外骨骼可用次数 1、冷却 0 |
| 6 | `More-Balanced-Exosuit-Emancipator-v1.1.zip` | **More Balanced Exosuit - Emancipator** | **携带解放者外骨骼战备时，额外携带爱国者外骨骼战备**；其余同 #5。**与 #5 二选一**（同时装会战备套娃崩溃） |

> 除两对二选一（**#3/#4**、**#5/#6**）之外，其余 mod 可以任意组合同时使用。

## 🆕 本次更新（外骨骼 v1.1）

在「挂载对调 + 携带 A 外骨骼战备时额外携带 B 外骨骼战备」之外，对**爱国者（EXO-45）和解放者（EXO-49）两条战备记录**各加两处改动：

| 字段 | 记录内偏移 | 原版 | 现在 |
|---|---|---|---|
| `use`（可用次数） | `package-88` | 3 | **1** |
| `cooldown_duration_success`（冷却） | `package-64`（float） | 420.0 | **0.0** |
| `cooldown_duration_fail` | `package-60`（float） | 0.0 | 0.0 |

* `use` **只写一次**、写完不再干涉 —— 这一次用掉就没了（不会一直维持在 1 变成无限次）；
* 冷却**持续维护**（静态配置，本来就不该变）；
* 记录定位仍是 **package 值 + `icon` 校验**，同 package 的 `PresidentReward` 变体不会被误改。

## 🔧 各 mod 详细说明

### 1. AC-8 Cut-Content 75rnd Backpack（AC-8 废案 75 发备弹背包）
改写 `MountComponentData` 里 AC-8 机炮包架的背包条目：原版 50 发备弹 → 废案版本 **75 发备弹**。
定位用背包自身的资源哈希 + 「命中点前后必须是机炮本体」的内容校验，不依赖表布局。

### 2. Stronger Kinetic Guard Dog（更强的实弹狗）
把机枪犬 `drone_mg` 挂载的武器换成 **SEAF MG-43**（实弹），火力与手感更强。

### 3. TD-110 Co-Op（更强调合作的 TD-110）
两件事：① 激光指示器水平射界 **±20° → ±180°**；② 两个挂载位按位置对调（炮手 `+24` → 烟雾弹发射器、驾驶员 `+48` → 激光指示器），
`node` 等其它字段一律不动。
⚠ **时序**：`MountComponentData` 只在生成载具时读一次 —— 进任务后先等 `TankStormCoop.log` 出现
`挂载补丁已就绪：现在可以召唤 / 重新召唤载具了`，**再**召唤坦克（射界是实时读的，不用等）。

### 4. Busier TD-110 Driver（更忙的 TD-110 驾驶员）
TD-110 Co-Op 的替代方案：只把驾驶员位 `+48` 的烟雾弹发生器换成**手操重机枪炮台**（`14005565984326167830`），
不动炮手位、不调射界。**与 TD-110 Co-Op 二选一**（同一个槽）。

### 5 / 6. 更均衡的爱国者/解放者外骨骼（两个版本，**二选一**）
两版**挂载改动完全相同**：

1. **EXO-49 解放者** 槽1（右臂）：右臂加农炮 → **爱国者的加特林炮塔**（`645713022044093730`）；
2. **EXO-45 爱国者** 槽0（左臂）：导弹发射器 → **左臂加农炮**（`16570517418531528145`）。

区别只在「战备附加」写哪条记录：

| 包 | 版本 | 需携带 | 效果 | 写入 |
|---|---|---|---|---|
| `More-Balanced-Exosuit-Patriot-v1.1.zip` | 携带爱国者版 | 爱国者 | **携带爱国者外骨骼战备时，额外携带解放者外骨骼战备** | 爱国者记录 `0 → 10`（`StratagemType_EmancipatorExosuit`） |
| `More-Balanced-Exosuit-Emancipator-v1.1.zip` | 携带解放者版 | 解放者 | **携带解放者外骨骼战备时，额外携带爱国者外骨骼战备** | 解放者记录 `0 → 26`（`StratagemType_PatriotExosuit`） |

再叠上「两台外骨骼 可用次数 → 1、冷却 → 0」（见上表）。

⚠ **两版必须二选一**：两条记录同时被写成非 0 会形成「战备互相附加」（套娃），在战备/载具列表生成时崩溃。
包里带**运行时保护**（fail-open）：扫到对向版记录附加槽已经非 0 时，附加写入整体拒写并写日志（④ 的调整不受影响）——但请**只装一个**。

⚠ **时序**：进任务后先等 `BalancedExosuitPatriot_STATUS.log`（或 `BalancedExosuitEmancipator_STATUS.log`）出现
`四项改动均已就绪：现在可以召唤 / 重新召唤载具了`，**再**召唤外骨骼。

## 安装 / 更新（所有 mod 通用）

1. 从 `dist/` 或本 Release 附件下载 zip；
2. 管理器里：**删旧条目 → Purge → 导入新包 → 启用 → Deploy**（Arsenal 不是覆盖式更新）；
   装过外骨骼测试包（旧名 `Walker Loadout`）的，先把旧条目删掉；
3. **不要**手动把包里的 `Addon/` 拷进游戏 `data/`（多个 addon 的包内文件名相同，会互相覆盖）；
4. 检查日志：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\` 下的
   `AC8RackBackpack_STATUS.log`、`GuardDogMg43_STATUS.log`、`TankStormCoop_STATUS.log`、
   `BalancedExosuitPatriot_STATUS.log` / `BalancedExosuitEmancipator_STATUS.log`，
   首行 `OK - 补丁生效中（N 处）` 即生效。

## 校验（SHA-256）

| 包 | SHA-256 |
|---|---|
| `AC8-Rack-Backpack-v1.0.zip` | `a1e53ec459d162703928657d4cded1cec3148b50cdfd0e217e22d51a95de3044` |
| `Guard-Dog-MG43-v1.0.zip` | `322974a874ed123a8c1c1f6af04373f329575b6a1a47dd1380a921058ad25ce7` |
| `TD-110-Co-Op-v1.0.zip` | `aa388d0055e6bf170cdbde398bdf52ffd214346eefb28995aa189928a8e66f45` |
| `TD-110-Busier-Driver-v1.0.zip` | `19ff00d5c6a2a588aa98e72242040071cfdc03d21c187a33a27a17c55986cefa` |
| `More-Balanced-Exosuit-Patriot-v1.1.zip` | `9251312ef4ea536cb56c4c898ba39f46fa0b0a3d06b63e18011332e74af9e421` |
| `More-Balanced-Exosuit-Emancipator-v1.1.zip` | `97cbd29c029b94e519789a13fe285a504d5465fe3ab16c996805deb5e2583d12` |

`dist/SHA256SUMS.txt` 里是以上 6 个包的哈希；Git Bash 用 `sha256sum -c SHA256SUMS.txt` 一次校验。

## 验证记录

| Mod | 状态 |
|---|---|
| AC-8 75 发背包 / 更强的实弹狗 / TD-110 Co-Op / 更忙的 TD-110 驾驶员 | **实机验证**（2026-09-25，连续运行 40 分钟以上保持生效） |
| 外骨骼 · 携带爱国者版（挂载 + 战备附加 `0 → 10`） | **实机验证**（原型 v5.0） |
| 外骨骼 · 携带解放者版、两版二选一保护、可用次数/冷却改动 | **离线仿真**（真实记录布局，4 场景 × 14 项全过，详见 `more-balanced-exosuit/DESIGN.md`） |

## 免责声明

非官方作品，与 Arrowhead Game Studios / Sony Interactive Entertainment 无任何关联；
仅在游戏运行时修改本机内存，**不分发任何游戏资产**。游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

---

# v1.2 — 更均衡的爱国者/解放者外骨骼（两个版本，**二选一**）

> GitHub Release 建议用 tag **`v1.2`**（`v1.0.1` 是上一版：四个 mod；v1.1.0 未发布，直接跳 v1.2）。下面这段可整篇粘到 Release 说明里。

**日期**：2026-09-25 ～ **验证环境**：Helldivers 2 `1.8.45850.0` + Bingus Shared Loader **v16（API 1）**

## 这个版本有什么

### 🦾 更均衡的爱国者/解放者外骨骼

两个方向、**挂载改动完全相同**：

1. **EXO-49 解放者** 槽1（右臂）：右臂加农炮 → **爱国者的加特林炮塔**（`645713022044093730`）；
2. **EXO-45 爱国者** 槽0（左臂）：导弹发射器 → **左臂加农炮**（`16570517418531528145`）。

区别只在「战备附加」（`StratagemSettings.additional_stratagem`）写哪条记录：

| 包 | 版本 | 需携带 | 效果 | 写入 |
|---|---|---|---|---|
| `More-Balanced-Exosuit-Patriot-v1.0.zip` | 携带爱国者版 | 爱国者 | **携带爱国者外骨骼战备时，额外携带解放者外骨骼战备** | 爱国者记录 `0 → 10`（`StratagemType_EmancipatorExosuit`） |
| `More-Balanced-Exosuit-Emancipator-v1.0.zip` | 携带解放者版 | 解放者 | **携带解放者外骨骼战备时，额外携带爱国者外骨骼战备** | 解放者记录 `0 → 26`（`StratagemType_PatriotExosuit`） |

⚠ **两版必须二选一**：两条记录同时被写成非 0 会形成「战备互相附加」（套娃），在战备/载具列表生成时崩溃。
包里带**运行时保护**（fail-open）：扫到对向版的记录附加槽已经非 0 时整体拒写并写日志 —— 但请**只装一个**，不要依赖它。

**定位方式（本版起）**：不再依赖飞鹰记录或统计特征，直接搜 `package` 值
（`packages/generated/loadout/combat_walker` / `.../combat_walker_obsidian`），命中点 `+8` 校验 `icon`，
附加槽 = 命中点 `+32`，并要求 `depends_on(+28)`、`max_in_loadout(+36)` 均为 0，否则拒写。

**⚠ 时序**：`MountComponentData` 只在**生成载具时读一次**、`StratagemSettings` 只在**进任务后加载** ——
进任务后先等 `BalancedExosuitPatriot_STATUS.log`（或 `BalancedExosuitEmancipator_STATUS.log`）出现
`三处改动均已就绪：现在可以召唤 / 重新召唤载具了`，**再**召唤外骨骼。

## 安装 / 更新

| 文件 | Mod |
|---|---|
| `More-Balanced-Exosuit-Patriot-v1.0.zip` | 携带爱国者版（召唤爱国者 → 附带解放者） |
| `More-Balanced-Exosuit-Emancipator-v1.0.zip` | 携带解放者版（召唤解放者 → 附带爱国者）。**与上一个二选一** |

1. 如果你装过外骨骼的测试包（旧名 `Walker Loadout` / `walker_loadout`），**先在管理器里删掉旧条目**再导入新版；
2. 管理器里：**删旧条目 → Purge → 导入新包 → 启用 → Deploy**（Arsenal 不是覆盖式更新）；
3. **不要**手动把包里的 `Addon/` 拷进游戏 `data/`（多个 addon 的包内文件名相同，会互相覆盖）。

`dist/SHA256SUMS.txt` 里是所有包的 SHA-256：

```powershell
cd dist
Get-FileHash *.zip -Algorithm SHA256 | Format-Table -AutoSize
# Linux / Git Bash:
sha256sum -c SHA256SUMS.txt
```

| 包 | SHA-256 |
|---|---|
| `More-Balanced-Exosuit-Patriot-v1.0.zip` | `0f7c9ad697d87bdeb840ccec7dfbb76a75c2a62b859795f618d6f544113b9e19` |
| `More-Balanced-Exosuit-Emancipator-v1.0.zip` | `bf1f1afa2f34296af227446e58b4a7ff8a67cf47b253ee0c6baeb169846a5ce7` |

## 验证记录

* 「携带爱国者版」的挂载两处 + 战备附加（`0 → 10`）：**实机验证通过**；
* 两版的离线仿真（真实记录布局：`package@+168` / `icon@+176` / 附加槽 `+200`）4 场景 × 8 项全过：
  正常写入 / 诱饵（同 package 坏 icon）不动 / 飞鹰式记录不动 / 对向记录不动 / 邻字段为 0 / 二选一保护触发；
* 详见 `more-balanced-exosuit/DESIGN.md`。

## 免责声明

非官方作品，与 Arrowhead Game Studios / Sony Interactive Entertainment 无任何关联；
仅在游戏运行时修改本机内存，**不分发任何游戏资产**。游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

---

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
| `TD-110-Co-Op-v1.0.zip` | `aa388d0055e6bf170cdbde398bdf52ffd214346eefb28995aa189928a8e66f45` |
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
