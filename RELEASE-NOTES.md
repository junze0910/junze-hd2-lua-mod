# 2026-10-05 — No Large Piercing v1.5（优化类）：改成一次性写入

* **改成一次性写入**：开机扫一遍 → 写完两张表 → 回读复核 → **彻底停止扫描**。不再有维护窗口 / 热区自检 / 兜底全量（v1.4 在静默期仍每 30 秒扫 ≈37 MB 热区、每 3~12 分钟一次全量兜底）。
* **金丝雀**：之后每 60 秒只读已写入的 108 个地址（432 字节）——被写回 `3`/`4` 就补写，地址失效就退回维护式调度。
* **超时保护**：3 分钟没找齐两张表 → 记日志并退回维护式调度；人工兜底 `_G.HD2_NoLargePiercing_Rescan()`。
* **扫描实现优化**：跨块命中不再「上一块尾 2 KB + 本块」拼 MB 级字符串（全轮约 4 GB 拷贝），只拼 14 字节的缝。
* **只维护 `→ 0` 一版**：`No Large Piercing (Medium)`（`→ 2`）自本版起停止维护/发布（源码保留，可 `python tools\build_mod.py no_large_piercing_medium` 自行打包；旧包在 `build/_deprecated/from_dist/`）。
* 离线夹具 `python _probe\test_nlp.py`：**50 / 50 通过**（新增一次性模式 / 金丝雀 / 超时 / 手动钩子 / 跨块缝隙 5 组用例）。
* ⚠ **尚未实机验证**（实机请按 v1.4 的老规矩看 `NoLargePiercing.log`：应出现「一次性写入完成……全部命中」）。

# 2026-10-05 批次 — MODS 页统一分组 + 各 mod 选项精简

**日期**：2026-10-05 ｜ **发布线**：四条线全部更新（`core-v2.0` / `infantry-v2.0` / `vehicle-v2.0` / `logistics-v0.1alpha`）

## 为什么

MOM（Mod Options Menu）**只显示前 8 个分组**（`patch_5.lua`：`MOD_BUTTONS = 8`），排序是**大写标题的字节序**，
然后 `while #list > MOD_BUTTONS do table.remove(list) end` 直接截断。中文标题一定排在 ASCII 之后
⇒ 本仓库几个中文名分组（`自定义补给`、`解锁台`）在有第三方 mod 一起注册时会被**整组砍掉**（不是显示不全，是根本不出现）。

**做法**：所有包的 MODS 选项统一注册到**同一个分组 `A HD2 MOD COLLECTION`** —— 组名以 `A ` 开头
（空格 `0x20` < `AC-8` 的 `C` `0x43`），永远排第 1，稳进前 8。同时把每个 mod 的选项行数压到必要的程度，
全组控制在 MOM 的单组成员上限（`MAX_ROWS = 32`）之内。

## 新版本一览

| 包 | 版本 | 行数 | 本版变更 |
|---|---|---:|---|
| `HD2-Scanner` | 0.8.0 → **0.8.1** | 4 | 新增 `HD2Scanner.mom_group` + 两张成员注册表 `register_reset` / `register_full_scan`；把「全内存扫描（兜底）」「初始化（全局）」两行并进本组；撤掉「写诊断」行 |
| `AC8-Rack-Backpack` | 2.1 → **2.2** | 0 | **不再注册任何 MODS 行**（本来就全自动，不需要手动动作），不再占分组名额 |
| `GuardDogLoadout` | 1.0.1 → **1.0.2** | 1 | 只剩「下挂物品」；「初始化」改由 Scanner 的全局按钮触发 |
| `TD-110-Loadout` | 1.0.1 → **1.0.2** | 3 | 7 行 → 3 行（预设 / 炮手槽位 / 驾驶员槽位）；**水平射界 360° 改成默认行为**，不再占一行；「初始化」改由 Scanner 触发 |
| `ExoLoadout` | 0.8.0 → **0.8.1** | 6 | 8 行 → 6 行（携带 / 附加 / 手臂×4）；「兜底全内存扫描」「初始化」搬到 Scanner 的全局按钮 |
| `Custom-Supply` | 0.1e → **0.1f** | 5 | 9 行 → 5 行：1 行「模式」（补给 / 大炮覆盖）+ 4 行「槽位」。切到大炮模式后**同一条下拉直接换成炮弹**（选项文字是函数，MOM 每次开菜单重算），两个模式各自记住自己的选择 |
| `Unlock-Kit` | 0.6 → **0.7** | 7 | 撤掉只读「侦察」行；解锁战备 6 条 → **5 条**（去掉 ID50） |

## 全组布局（26 行，上限 32）

| # | 行 | 来自 |
|---|---|---|
| 1 | 状态 | Scanner |
| 2 | 解析战备表（AOB） | Scanner |
| 3 | 全内存扫描（兜底） | Scanner（成员通过 `register_full_scan` 挂回调，如机甲的全内存搜 package） |
| 4 | 初始化（全局） | Scanner（成员通过 `register_reset` 挂回调：机甲 / TD-110 / 护卫犬） |
| 5 | 下挂物品 | 护卫犬自选 |
| 6 | 预设 | TD-110 |
| 7 | 炮手槽位 | TD-110 |
| 8 | 驾驶员槽位 | TD-110 |
| 9 | 携带机体 | 机甲 |
| 10 | 附加机体 | 机甲 |
| 11-14 | 手臂 · 携带 左/右 · 附加 左/右 | 机甲 |
| 15 | 模式（补给 / 大炮覆盖） | 自定义补给 |
| 16-19 | 槽位 1-4 | 自定义补给 |
| 20-21 | 解锁 P-41 / G-11 | 解锁台 |
| 22-26 | 解锁战备 ID5 / 26 / 105 / 135 / 146 | 解锁台 |

- **只装其中几个也正确**：MOM 的分组是按「谁注册了」现成拼的，没装的 mod 那些行**根本不存在**，不会留空壳。
- 「初始化（全局）」的描述会自己列出**实际装了谁**（调 `HD2Scanner.reset_names()`），所以不会出现「点了没反应」。

## 两个语义变化（会改变行为，请注意）

1. **TD-110 射界 360° 成为默认**：不再有开关。`初始化` 会连射界一起写回原装 ±20，并**暂停本局自动套用 360°**，
   直到你再点一次「预设」或重新召唤坦克。
2. **「初始化」是全局动作**：Scanner 组里那一个按钮会把**所有已装并注册了的 mod** 一起还原（机甲 + TD-110 + 护卫犬），
   不能只还原其中一个。

---

# 解锁台 v0.6 — 武器 + 战备解锁（后勤线新增）

**日期**：2026-10-04 ｜ **包**：`dist/Unlock-Kit-v0.6.zip`（9,100 B，SHA256 `963daa53…3572`）｜ **发布线**：`logistics`（并入 `logistics-v0.1alpha` release）

## 本版内容

- **武器 2 把**：P-41 巡察者（副武器）、G-11 铁蒺藜（投掷物）—— 克隆同类样板（P-2 / G-6）+ **只替换身份字段** `+0x00/+0x04/+0x08`，`count` 最后发布
- **战备 6 条**：轨道照明弹（ID5）/ FRV 补给型 M-103（ID26）/ 快速侦察载具 FRV M-102（ID105）/ FRV 炽热型 M-104（ID135）/ 飞鹰·空空导弹（ID146，废弃条目）/ 风暴漩涡（ID50）
  —— `② StratagemInfo +0x80 bit1 = 1` + `③ 注册表记录 +0x14 = 2`
- **只读侦察**一行：打印目标 key / 是否已登记 / 样板下标 / 战备记录与选择位
- 9 行开关都在游戏**原生 ESC → MODS 页 → 「解锁台」**：打开即写、**关掉即按行精确回滚**；开局自动套用 + 每 5 秒复核
- ⚠ **不含武器配件解锁**：JAR-5 弹药线做到 v0.5（22 笔写入全部成功）但**打开主宰配装页会崩**，v0.6 起整块移除；经过与教训见 `hd2-mod/docs/UNLOCK-KIT-交接.md §10`

## 验证

- **2026-10-04 实机通过（用户确认）**：武器 2 把进军械库、6 条战备进战备列表；只读侦察正常
- **前置**：Bingus Shared Loader **v15+**（MODS 页来自 `ModOptionsMenu`）；**HD2 Scanner 可选**（检测到则优先用其战备表 API，否则内置签名兜底）
- 离线夹具：`python _probe\test_unlock_kit.py` → **32/32**

---

# 自定义补给 v0.1e — SEAF 大炮覆盖（已实机通过，已发布）

**日期**：2026-10-04 ｜ **包**：`build/Custom-Supply-v0.1e.zip`（11,705 B）
**SHA-256**：`E0CF9E40E2577EA097EDFD76EB46EB7830B986562EF38F6D94EDDA0D90015756`
**前置**：**Mod Options Menu v1.1+** + **HD2-Scanner-v0.8.0.zip**（硬前置），需 Bingus Shared Loader v15+ ｜ **状态**：已实机通过（用户确认 2026-10-04），**已发布**（`logistics-v0.1alpha`）

在 v0.1d（「爆炸筒」，已实机通过）基础上新增：

- **SEAF 大炮覆盖**：MOM `toggle`，默认关；**仅当场上存在超级地球大炮 / SEAF Artillery 时由玩家手动打开**
- **下层 4 个「大炮槽位」**：`补给类 / 大炮 迷你核弹(+30s) / 大炮 高爆弹(+20s) / 大炮 炸弹(+15s) / 大炮 凝固汽油弹(+10s) / 大炮 静电场(+10s) / 大炮 烟雾弹(+5s) / 爆炸筒(+0s)`
- **关**：只读上层 4 个补给槽；**开**：下层非「补给类」→ 用下层炮弹/爆炸筒，下层「补给类」→ 回退上层对应补给
- 上下两层**独立配置**，不互相同步；炮弹摆位统一 `(0,0,0)/(0,0,0)`
- **实机通过**：6 种 `LoadoutPackage` 炮弹哈希 + 爆炸筒写进包架后均可正常生成 / 使用

**离线夹具**：纯逻辑 36/36、合成内存 29/29、SEAF 覆盖 49/49。

---

# 自定义补给 v0.1b — 内容决定冷却（后勤线首发）

**日期**：2026-10-04 ｜ **包**：`build/Custom-Supply-v0.1b.zip`（10,184 B）
**SHA-256**：`DB141867DDBD024359A280D2C81EE2F79F82744B81831309F23299CF5607C69F`
**前置**：**HD2-Scanner-v0.8.0.zip**（硬前置）｜ **发布线**：`logistics`（并入 `logistics-v0.1alpha` release）

把**补给包架的 4 个槽位**变成可配置：**放什么决定补给给什么，放多少决定冷却多久。**

## 机制

| 槽位里放的 | 简称 | 单件冷却增量 |
|---|---|---:|
| （空槽） | 无 | +0 s |
| 资源点弹药盒 | 弹药盒 | **+5 s** |
| 资源点治疗针剂 | 针剂盒 | **+30 s** |
| 资源点手榴弹包 | 手雷盒 | **+15 s** |
| 补给（模型） | 补给包 | **+30 s** |
| 医疗补给（模型） | 医疗包 | **+15 s** |

冷却 = 30 + 各项之和 → **30 s（四槽全无，默认）～ 150 s（四槽针剂盒 / 补给包）**

## 本版内容

- **MOM 四槽独立配置**：游戏原生 MODS 页 4 个 `choice`，每条下拉的描述**实时显示当前冷却**；不提供预设组合
- **摆位自动化**：针剂盒 `(0,-0.1,-0.1)/(-90,0,0)`、手雷盒 `(0.1,-0.3,0)/(-90,0,0)`；其余物品写原装 0
- **自包含**：内置「让补给战备（ID77 `CONSUMABLES. HEALTH PACK RACK`）可用」的处理，**不需要**额外解锁 mod
- **每 5 秒复核**：选择位 / 可用状态 / 冷却 / 4 个槽位，被游戏改回立刻补回
- **扫描全部交给 Scanner**（`strat_slot` / `scan_request`），mod 自身不做全量扫描
- 会话级：写入只在本次进程内有效，重启即回到原装

## 验证

**实机通过（2026-10-04，构建号 46015）**：

- `★ 选择位 id=77 +0x80 0x01 -> 0x03（回读通过）`
- `★ 可用状态 id=77 记录#841 1 -> 2（回读通过）`（门闸 0→9 期间自动重试，进任务后成功）
- `包架表已定位 0x…（来自 Scanner 命中）` + `★ 槽1..4 = …`（含摆位，回读通过）
- `★ 冷却 id=77 cooldown_success = 45 / 75 / 90 / 95 / 120 s` —— 与公式逐项吻合，改槽即时生效

**离线夹具**：`_probe/test_custom_supply.py` 26/26（纯逻辑）、`_probe/test_custom_supply_mem.py` 25/25（合成内存写入路径：门闸重试 / 幂等 / 复核修回）

## 已知限制

- 只作用于补给战备所用的那台包架（4 个激活槽），**不新增槽位**
- 队友侧显示**未验证**；无「一键还原」按钮；无预设组合

---

# AC-8 机炮背包 v2.1 — 界面退役对齐（替换 v2.0）

**日期**：2026-10-04 ｜ **包**：`build/AC8-Rack-Backpack-v2.1.zip`（14,043 B）
**SHA-256**：`DD0E94B00519218CD0B5576FE70F9F42565FB8C51D4329C2B9CA334D90B463CB`
**前置**：**HD2-Scanner-v0.8.0.zip**（硬前置）｜ **取代**：`AC8-Rack-Backpack-v2.0.zip`

写入逻辑与定位算法**一字未动**；本版只做「界面退役」的对齐：

| 项 | v2.0 | v2.1 |
|---|---|---|
| 自绘面板页（`_G.HD2Menu`） | 有（只读状态：写入数 / 前置 / 阶段 / 表地址 / 手动写一次） | **删除** —— 《HD2Menu 页面体系》2026-10-04 整体退役，渲染宿主 `ui.lua` 早已不在发布包里，页面从来显示不出来 |
| 界面入口 | MODS 页无 | 原生 MODS 页新增一行 **「立刻写一次」**（按 Scanner 广播的地址重写一次挂载，点完自动弹回） |
| 状态/诊断 | 面板页 | `AC8RackBackpack.log`（写入本身是自动的，核心功能不依赖任何 UI） |

## 验证

- `_probe/test_ac8.py`：**ALL PASSED**（含新增用例：MOM 注册「立刻写一次」/ HD2Menu 不再注册 / 
  点完自动弹回 / 调用后 0 异常）
- 实机：**2026-10-04 通过**（与 Scanner v0.8.0 同批验证）

---

# Guard-Dog-MG43 v2.1 —— **最终版**（已被 GuardDogLoadout 取代）

**日期**：2026-10-04 ｜ **包**：`build/Guard-Dog-MG43-v2.1.zip`（11,593 B）
**SHA-256**：`5E618015267844305B5900E0FC76FE22FDA0DEBBBEAE8E3895ECF4B50C1CECE5`
**前置**：**HD2-Scanner-v0.8.0.zip**（硬前置）｜ **取代**：`Guard-Dog-MG43-v2.0.zip`
**状态**：⛔ **已废弃（不再维护）** —— **v2.1 是最后一版**，随本批发布**仅作留档**（`dist/` 里保留，
同时归档一份在 `build/_deprecated/from_dist/`）。新用户请直接装 `GuardDogLoadout`（三选一：原装 / MG-43 / 自定义哈希），
**不要**与本包同时启用。
两者改的是**同一条记录的同一个槽位**（`drone_mg` 挂载武器），同时启用只会互相覆盖。

## 本版内容（功能与 v2.0 相同）

| 项 | v2.0 | v2.1 |
|---|---|---|
| 自绘面板页（`_G.HD2Menu`） | 有（只读状态 + 手动写一次） | **删除**（页面体系 2026-10-04 整体退役，从来显示不出来） |
| 界面入口 | 无 | 原生 MODS 页一行 **「立刻写一次」** |
| 写入 / 定位 / 自检 | — | **一字未动** |

## 验证

- `_probe/test_gd.py`：**ALL PASSED**（含新增用例：MOM 注册 / HD2Menu 不再注册 / 点完自动弹回）
- 实机：**2026-10-04 通过**（与 Scanner v0.8.0 同批验证）

## 弃用指引

* 装 `GuardDogLoadout-v1.0.1.zip`（或更新），**不要**与本包同时启用
* 从本包切到 GuardDogLoadout 时，`GuardDogLoadout` 的「写回原装免检」会处理内存里已经是 MG-43 的情况
* 装完建议点一次 GuardDogLoadout 的「初始化」，回到原装状态再选

---

# ExoLoadout v0.8.0 — 战备记录改为 AOB 直取（全内存扫描降为兜底）

**日期**：2026-10-04 ｜ **包**：`build/ExoLoadout-v0.8.0.zip`（19,374 B）
**SHA-256**：`1118B3DC1BD371914841EB187249D7BF33E08EB5AE0D8E82FF8F13A2353E03BD`
**前置**：**Mod Options Menu v1.1+** + **HD2-Scanner-v0.8.0.zip**（必需；AOB 路径需要 v0.8.0+，旧 Scanner 自动回退）
**取代**：`ExoLoadout-v0.7.2.zip`

战备附加（`additional_stratagem`）以前只能靠**全内存搜 `package` 值**定位记录：要扫几 GB、约十几秒，
而且必须等扫完才能写。v0.8.0 改用 AOB：Scanner 在 `game.dll` 代码段里解出**战备记录指针数组**
（来源：`StratagemCooldown 2.1.5`），按 ID 一次读记录 —— 毫秒级，进图即可写。

## 变化

| 项 | v0.7.2 | v0.8.0 |
|---|---|---|
| 战备记录定位 | 全内存搜 `package` 值（唯一路径） | **AOB 直取**（优先路径） |
| 全内存扫描 | 唯一路径，手动/`EXO_AUTO_SCAN` 触发 | **仅兜底**：AOB 不可用 / 解析失败 / 表里找不到记录时才走 |
| 定位时机 | 扫描完成（进图后十几秒） | 解析完即可（加载阶段就点起来，分帧后台跑） |
| 身份复核 | `icon` + `depends_on` + `max_in_loadout` | **同一套判据**，AOB 路径先用 `package` 再复核 icon/邻字段 |
| 新接口 | — | 新增 `EXO_DISABLE_AOB=true` 可强制走旧路径（排查用） |

* 「开始全扫描（手动）」按钮改成 **AOB 优先**：AOB 能直取时直接跳过全扫描，只写不扫
* ⛔ **旧面板退役（同日）**：exo 的 HD2Menu 页面整体删除；剩下的 MOM 选项里，
  「兜底：全内存扫描（正常不用点）」的**说明改成函数**，每次开 ESC 菜单时重算，直接显示
  「AOB 直取已就绪 —— 不需要点这个开关」或「AOB failed → 需要本开关兜底」
* **UI 跟着简化**：正常流程**完全不用手动扫描**
  * ModOptionsMenu 的「开始全扫描」改名 **「兜底：全内存扫描（正常不用点）」**，说明里写清何时才需要
  * 旧面板那一行按 AOB 状态变文案/颜色：AOB 正常 = 灰字「不需要点」；AOB 不可用或表判失败 = 亮起「点这里」
  * 「附加机体」选项说明改为「选好后由 AOB 直取记录自动写入，不需要扫描」
* 面板新增「战备定位」行：`AOB 直取` / `AOB failed（原因）` / `全内存搜（Scanner 无 AOB）`
* 头部 `VERSION` 0.7.2 → **0.8.0**；手臂改造那一套（`MountComponentData`）行为不变

## 验证

- `_probe/test_exo_aob.py`（新增，**16/16**）：
  - AOB 可用 → 两条记录直取后写完收工，**全扫描一次都没跑**（`strat_hits` 为空、`scanner_used` 为假）
  - AOB 返回 `failed` → 自动回退「全内存搜 `package` 值」，写入结果与 v0.7.x 完全一致
- `_probe/test_exo.py` 全过；`_probe/test_strat.py` 7/7
- 实机：**待验证**

## 实机复验重点

1. 装 `HD2-Scanner-v0.8.0` + 本包进任务 → `HD2Scanner.log` 应出现
   `aob: 战备表已定位 base=0x… consumer=0x… 槽位 n/256 可读`
2. `ExoLoadout.log` 应出现 `AOB 定位：爱国者 -> 0x…（id）`，且**不应**再出现一整轮「战备内容搜」
3. 若出现 `AOB 战备表解析失败（60 秒后重试，先走兜底）` —— 把该行连同 `aob:` 的失败原因一起记下来
   （说明游戏更新动了那几条指令，需要更新签名）

---
# HD2 Scanner v0.8.0 — 新增 AOB 战备表定位 API

**日期**：2026-10-04 ｜ **包**：`build/HD2-Scanner-v0.8.0.zip`（28,846 B）
**SHA-256**：`BD0765BDD1AAA242148A99B5EA1C17E2F0F869C1F16AC2D89EE6E7C6808F04B5`
**取代**：`HD2-Scanner-v0.7.0.zip`（其余 API 完全兼容，纯增量）

`StratagemSettings` 在内存里**不是 LDLD 块**，所以数据表广播那套对它无效 —— 这也正是
ExoLoadout 之前只能全内存搜的原因。v0.8.0 增加第三个 API 家族：在 `game.dll` 代码段里找一对固定指令，
解出**战备记录指针数组**，之后按 ID 直取记录。

## 新增

* **新资源 `aob.lua`**（第 8 个资源；只读，全程 `ReadProcessMemory`）
  * 扫所有可执行段，1 MB 分块 + 0x40 重叠，**要求 AOB 唯一命中**，多命中直接放弃（不猜）
  * 唯一命中点解码 `disp32`，往前 0x1000 倒找 `lea r15,[rip+disp32]` 锚点（要求落在映像首 1 MB）
  * 结构探针：表前 256 个槽位里必须有可读指针，否则判失败
  * **分帧推进**（2 MB/帧；本机 33 MB 代码段 ≈ 17 帧），不卡帧
* **新 API**（`_G.HD2Scanner`，`version` 仍为 1）：
  `strat_table_request()` / `strat_table_status()` / `strat_table_base()` / `strat_slot(id)` / `strat_rec(id, n)`
* **失败一定有原因**：命中不唯一 / `disp32` 读不到 / 锚点没找到 / `table_base` 不合理 /
  槽位全不可读 —— 消费者据此回退（ExoLoadout 就回退到全内存搜）
* 面板新增「战备表（AOB 路径）」一栏：状态、进度、`table_base`、`consumer`/`disp`、槽位可读数，
  外加一键「解析战备表（AOB）」
* `Scanner-API.md` 新增 §4（中英双语），已知表哈希与示例顺延为 §5 / §6
* ⛔ **HD2Menu 页面体系退役（同日）**：自绘面板那套（`registry.lua` + `ui.lua` + 5 个 mod 的页面）
  **整体下架** —— `ui.lua` 早就不在发布包里，页面永远显示不出来。现在包内只有 7 个资源（入口 + 6 模块），
  `registry.lua` 已删除；Scanner 自己在 MOM 注册 3 行（**扫描状态 / 解析战备表 / 写诊断到日志**）。
  `ui.lua` 源码保留在 `src/`（顶部有退役说明，不打包、不加载）。

## 验证

* `test/test_load.py`：**54/54**（新增 20 条）
  * 用 ffi 自留内存合成一块假映像，把 `lea r15 → AOB pair → 指针数组 → 记录` 整条链真跑一遍：
    解出 `ok`、`table_base` 正确、`slot_ptr(3)` 正确、记录 0xD0 可读、package/icon/邻字段就位
  * 安全网：故意放两处命中 → 必须 `failed`，且原因写明「不唯一」
  * 面板自页能渲染、AOB 行与手动解析按钮都在
* `test/test_decoders.py`：OK（解码器未受影响）
* 实机：**待验证**（预期日志见 ExoLoadout v0.8.0 的「实机复验重点」）

---
# GuardDogLoadout v1.0.1 — 写入保护 / 初始化 / cfg 边界修复（替换 v1.0）

**日期**：2026-10-03 ｜ **包**：`build/GuardDogLoadout-v1.0.1.zip`（13,223 B）
**SHA-256**：`686DC8B097880C16531D24B42CAFEF3B5DD0D8EE4EF6F9D0E2D49F9EEB06AA07`
**前置**：`HD2-Scanner-v0.7.0.zip`（**硬前置**；缺前置时零写入，并把原因写进日志与状态盘）
**取代**：`GuardDogLoadout-v1.0`（v2.0 首发版）。与 `Guard-Dog-MG43-v2.0.zip` **二选一**
—— 两者改的是**同一条记录的同一个槽位**，同时开只会互相覆盖

> 护卫犬 `drone_mg` 的挂载武器**三选一**：**AR-23P（原装 / 不改写）** · **MG-43（SEAF）** · **自定义哈希**（读 cfg）。
> 定位腿与机甲 mod 的手臂改造同构：Scanner 广播 `MountComponentData 0x3845B1E0`
> → 运行时推记录区起点 → 索引 `(实体, recIdx, pad)` → 记录 `+0` 的 8 字节；二级复核 `+8 node == 0x53BEC437`。

## 修复 / 加固

| 项 | 说明 |
|---|---|
| **反复改**（对齐机甲 mod 的 6.24） | `state.slots[addr]` 同时记 `item`（当前目标）与 `orig`（原装）；判据 =「原装」或「本次目标」或「**上次自己写过的值**」。原装 → MG-43 → 自定义 → MG-43 → 原装 **连改 4 次全部生效** |
| **写回原装免检**（6.24 的补充） | `want == 原装` 时直接放行 —— 否则从旧 `Guard-Dog-MG43` 切过来时（内存里已是 MG-43、`last` 为空）会被自己的保护**永久困死**，连"选原装"都回不去 |
| **初始化**（对齐机甲 mod 的 6.25） | 新增 `do_initialize()`：tracked 槽位写回原装 → `vanilla_force` **强写**（只校验 node/pad/recIdx，当前值不论是什么）→ cfg 复位 AR-23P → 清运行时状态 → 同步 ModOptionsMenu。**初始化不读上次退出的 cfg** |
| 拒写提示 | 陌生值拒写；日志写明「既非原装、也非上次自己写过的值」并提示**「想强行写回原装请点『初始化』」** |
| **cfg 立刻生效** | cfg 热重读 / 面板改选项后把 `last_gen` 置 -1 → **下一帧**就按新配置写（以前要等最多 60 帧的复扫节流） |
| **cfg 边界加固** | ① **自动剥 UTF-8 BOM** —— BOM 落在 `weapon=` 行上会让整行匹配失败、**静默**退回默认（PS 5.1 的 `Set-Content -Encoding UTF8` 就会写 BOM）② `cfg_save` 改为写**带说明的完整模板**，以前在面板切一次选项就把注释抹成 3 行裸键 |
| 只动 8 字节 | 记录 `+0` 的 item 之外（含 `+8` node / `+12` pad）一字不动；写后回读校验 |

## 自定义哈希怎么填

cfg：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\GuardDogLoadout.cfg`（**改完 1 秒热生效**；
完整路径也写在 MODS 页选项**右边的描述页**里）

```
weapon=ar23p        # ar23p(原装/不改写) | mg43(SEAF MG-43) | custom(读下面那行)
custom=             # 16 位 BE 十六进制物品哈希；留空 = 自定义项不可用
```

* `custom` **只在 `weapon=custom` 时被读**：内置项（ar23p / mg43）**不受它影响**（实测零写入）
* 大小写 / 前后空格 / 行尾 `# 注释` 都行；带 `0x` 前缀、长度不足、全 0、留空、整行缺失
  → **拒写** + 日志写明原因 + 保持当前值
* ⚠ **格式对 ≠ 能用**：本 mod **不校验哈希的含义**。填不存在的 / 不适配的 item 哈希会**真的写进挂载槽**，
  狗可能召唤异常 —— 自定义项必须填你**确认存在**的 item 哈希
* ⚠ 未知键（自己加的字段）解析时被安全忽略，但**保存时会被丢掉**（整文件按模板重写）—— 别把重要信息写在 cfg 里

## 验证

- `_probe/test_gd_loadout.py`：**86 / 86**
  含用例 17「连改 4 次（原装→MG-43→自定义→MG-43→原装）」、18「陌生值拒写」、
  19「初始化强制写回原装」、20「cfg 边界（内置项不受自定义影响 / 5 种非法写法 / BOM / CRLF / 注释保全）」
- 实机：**待验证**

## 实机复验重点

1. 装 `HD2-Scanner` + 本包进任务 → `Logs\GuardDogLoadout.log` 应出现
   `已接上 HD2Scanner（前置）` 与 `已写：drone_mg 挂载 … -> …（recIdx 97，node=0x53BEC437/pad=0 未动）`
2. `GuardDogLoadout_STATUS.log` 应写 `OK - 补丁生效中（1 处）` + `记录区起点 = 5152`
3. 面板切 **MG-43 → 自定义 → AR-23P**，三次都要**立刻**生效
4. 点一次**「初始化」** → 应写回原装，且 cfg 落盘为 `weapon=ar23p`

## 弃用

* `GuardDogLoadout-v1.0.zip` → 被本版取代（v2.0 首发版；写入保护 + cfg 边界的小修）
* `Guard-Dog-MG43-v2.0.zip` / `v2.1.zip` → ⛔ **已废弃（不再维护）**：与本 mod 改同一条记录的同一个槽位，**二选一**；
  v2.1 是最后一版（留档发布），新装请用本 mod

---

# TD-110 Loadout v1.0.1 — 文案修正 + 「反复改 / 初始化」加固（替换 v1.0）

**日期**：2026-10-03 ｜ **包**：`build/TD-110-Loadout-v1.0.1.zip`（19,174 B）
**SHA-256**：`1B09849A438F6B396022D4664F3A07CBE5CD6053A666EAE46326201E1E72CA42`
**前置**：`HD2-Scanner-v0.7.0.zip`（**硬前置**；缺前置时零写入，并把原因写进日志与状态盘）
**取代**：`TD-110-Co-Op-v1.1` + `TD-110-Busier-Driver-v1.2` —— 两者改的是**同一条记录的同一个槽位**（`MountComponentData` 的 TD-110 记录 `+48`），本来只能二选一

> `TD-110-Loadout-v1.0` **从未对外发布**，本版是它的替换版。

## 修复 / 加固

| 项 | 说明 |
|---|---|
| 射界开关文案 | 四处口径统一（Scanner 面板 / MODS 页 / cfg 注释 / 状态盘）：**只解水平射界（±180），不解除视角限制** |
| **反复改**（对齐机甲 mod 的 6.24） | 覆盖判据 =「**白名单 5 件**」或「**我们自己上次写的值**」，**不是**「原装 or 当前目标」→ 合作→忙碌(重机枪)→合作(40mm)→忙碌(40mm)→原装→自定义 **连改 6 次全部生效**，再切回合作也对 |
| **初始化**（对齐机甲 mod 的 6.25） | 新增 `force_vanilla`：槽位 / 射界是「认不出来的值」（别的 mod 写进去的）时，点**初始化**照样能**强行写回原装**；射界那条额外要求「该地址以前验证过」，避免把强制写用到错记录上 |
| 拒写提示 | 拒写日志改成提示「想强行写回原装请点『初始化』」，不再只干说一句"认不出来" |
| 硬不变量 | 四个模式统一：两槽**恰好一个激光**；自定义里想放第二个激光 → 拒改 + MODS 页控件弹回 + 日志说原因 |

## 验证

- `_probe/test_td110.py`：**104 / 104**（新增用例 16「来回切 6 次」、用例 17「复刻 6.25：未知值 → 普通模式拒写 → 初始化强行写回原装 → 之后还能再改」）
- 实机：**v1.0 已实机通过**（`OK - 补丁生效中（挂载 2 处 / 射界 2 处）`，`yaw360 = 1`）；
  v1.0.1 的增量是**文案 + 覆盖判据放宽**，写入路径同源，**建议进任务复验一遍**
- 复验重点：① 四档模式各召唤一次 ② **射界真能转满一圈**（激光 + 加特林）③ 视角限制确实还在 ④ 忙碌档**重机枪的弹药量**（弹匣腿已去掉）

## 弃用

* `TD-110-Loadout-v1.0.zip` → 被本版取代
* `TD-110-Co-Op-v1.1.zip` / `TD-110-Busier-Driver-v1.2.zip` → **已从 `dist/` 下架**
  （三份都留档在仓库外 `hd2-mod/build/_deprecated/`，文件名带「被…取代」）

---

# ExoLoadout v0.7.2 — 挂载/初始化修复

**日期**：2026-10-03 ｜ **包**：`build/ExoLoadout-v0.7.2.zip`（18,907 B）
**SHA-256**：`80E6CBCC47E806CDCB90C5BE60E7405589553D7761853DA94FAAB28D6818CF0A`
**前置**：**Mod Options Menu v1.1+** + **HD2-Scanner-v0.7.0.zip**（必需）。

本版是 ExoLoadout v0.7 的修复版，主要解决三个问题。

## 修复

| 问题 | 原因 | 修复 |
|---|---|---|
| 同一个挂载槽只能改一次 | `apply_rack` 只接受当前值等于原装或本轮目标。第一次写完后当前值等于旧目标，第二次目标变化后就被当成未知值拒写 | `state.slots[address]` 同时记录 `item` 和 `orig`；判断条件加入 `cur == last`，允许从上次写过的值继续切换 |
| 机体先当携带、后当附加时挂载改不动 | 同上：当前值是上一轮配置，既不是本轮原装，也不是本轮目标 | 同上；改为允许上次自己写过的值作为合法来源 |
| 初始化没有回到原始默认，内存里仍是上次退出/上次 Apply 的配置 | 初始化复用了 `apply_all('vanilla')`，当前值未知时仍被同一套保护拒写，所以实际没写成功 | 新增 `vanilla_force`；初始化集中到 `do_initialize()`，强制写回原装并清理扫描缓存 |

## 行为变化

- 初始状态：携带 = 爱国者，附加 = 无，手臂 = 原装
- 写回原装的目标免检：`want == orig` 时直接写，不再看当前值
- 初始化 = 回原始默认，不是回上次退出的 cfg
- 初始化同时清理 `strat_addr / strat_hits / strat_pair / scanner` 状态
- 全量扫描优先交给 `HD2Scanner v0.7.0` 的 `scan_request`；旧 Scanner 回退自扫描
- 扫描完成且写入落盘后自动停止

## 验证

- `test_exo.py`：51/51
- `test_strat.py`：7/7
- 连续两次改挂载合成测试：通过
- **实机：2026-10-03 通过**
  - 自检 76/76
  - 同一挂载槽连续改多次：通过
  - 携带/附加切换后继续改挂载：通过
  - 初始化：战备字段恢复 3 处；强制回默认（爱国者 + 无 + 原装）通过
  - Scanner memscan：14,242 区段 / 5,255.6 MB，约 13 秒扫完
  - 战备附加 + `use=2` 写入成功，写入后自动停止扫描

---
# v2.0 — 三条发布线（前置 / 单兵 / 载具）+ 后勤占位

> **附件已于 2026-10-03 更新到 patch 版**：单兵线换成 `GuardDogLoadout v1.0.1`、载具线换成 `TD-110-Loadout v1.0.1` + `ExoLoadout v0.7.2` —— 三个 patch 的说明见本文件最上面三段。
> 本次起改用**按发布线打 tag**，四条线各自演进（旧仓库级 tag `v1.0`~`v1.3` 保留不动）：
>
> | 发布线 | tag | 本次内容 |
> |---|---|---|
> | 前置 | `core-v2.0` | `HD2-Scanner-v0.7.0.zip` |
> | 单兵 | `infantry-v2.0` | `AC8-Rack-Backpack-v2.0.zip` · `Guard-Dog-MG43-v2.0.zip` · `GuardDogLoadout-v1.0.1.zip` |
> | 载具 | `vehicle-v2.0` | `TD-110-Loadout-v1.0.1.zip` · `ExoLoadout-v0.7.2.zip` |
> | 后勤 | `logistics-v0.1alpha` | **预留线，暂无包** |
>
> 每个 tag 的 Release 附件只带**本线**的包 + `SHA256SUMS.txt`；`dist/` 里则始终是全部当前包。

**日期**：2026-10-03 ｜ **验证环境**：Helldivers 2 `1.8.45850.0` + Bingus Shared Loader **v17（API 1）**

## ⚠ 破坏性变更：AC-8 与实弹狗 → **2.0**（改为强依赖前置）

| 包 | 变更 |
|---|---|
| `AC8-Rack-Backpack-v2.0.zip` | 从「自扫内存」改为**强依赖 HD2 Scanner 提供表地址**；另加写前自洽检查 + 日志环形/折叠/节流 |
| `Guard-Dog-MG43-v2.0.zip` | 同上改为**强依赖 HD2 Scanner** |

* **缺前置时不工作，但绝不乱写**：状态行写 `地址来源 = 无 —— 缺 HD2Scanner 前置，本 mod 不工作`，每 60 秒重试（AC-8 保留了 `AC8_USE_SELF_SCAN` 回滚开关）；
* manifest **GUID 不变**（AC-8 `2b8e6c51-…` / 实弹狗 `7f2c8a04-…`）→ mod 管理器里是**更新**同一个条目，不会多出一个；
* 好处：不再各自全内存扫表，两个 mod 的定位成本从「每次全量」降到「读 Scanner 广播的基址」。

## 📦 本版内容

### `core-v2.0` — HD2 Scanner v0.7.0（前置）

后台扫描内核：按 `LDLD + u32 版本 + u32 djb2(类型名)` 签名定位数据表（`MountComponentData` / `HellpodRackComponentData` / `StratagemSettings` 等），把**基址广播**给其他 mod；自带 ESC 浮窗面板与 ModOptionsMenu 原生设置页。

* **只读**：不写游戏内存（面板位置/设置写在本地 `HD2Scanner.cfg` / `.pos`）；
* 时间切片扫描（每帧预算受控），实测连续 51 轮 `命中 7` 稳定、每轮 610~644 帧分 42 帧完成（墙上 0.4~0.5 s）；
* 自检 11/11：解码器与内存里的 MDL 逐位一致。

### `infantry-v2.0` — 单兵线

| 包 | 作用 |
|---|---|
| `AC8-Rack-Backpack-v2.0.zip` | AC-8 机炮包架的备弹背包：原版 **50 发 → 废案 75 发**。定位用背包资源哈希 + 「命中点前后必须是机炮本体」的内容校验，不依赖表布局 |
| `Guard-Dog-MG43-v2.0.zip` | 机枪犬 `drone_mg` 挂载武器 → **SEAF MG-43（实弹）**。锚点 = 旧路径 8 字节 + `+8` 常量，**只改 8 字节** |
| `GuardDogLoadout-v1.0.1.zip` | 护卫犬挂载武器**三选一**：原装 AR-23P / SEAF MG-43 / 自定义哈希（cfg 热重读；非法值拒写并写明原因）。与「更强的实弹狗」**二选一** |

### `vehicle-v2.0` — 载具线

| 包 | 作用 |
|---|---|
| `TD-110-Loadout-v1.0.1.zip` | TD-110 两个挂载位**四档模式**（原装 / 合作 / 忙碌 / 自定义）+ **射界 360° 独立开关**（只解水平 ±180）。硬不变量：两个槽位**恰好一个激光**；取代 `TD-110 Co-Op` + `Busier TD-110 Driver`（两者改的是同一条记录的同一个槽位） |
| `ExoLoadout-v0.7.2.zip` | EXO 战备自选：**携带机体四选一 + 附加机体三选一**（禁自引用）+ **手臂跨机体互换**（只在携带的两台之间）+ `use=2`、**冷却不动**。取代外骨骼两版 —— **不再需要二选一** |
## 校验（SHA-256）

| 包 | SHA-256 |
|---|---|
| `HD2-Scanner-v0.7.0.zip` | `dfc6f878f1f37a6b6bd72fc2fbc0652dce33a3329fef4d62ec0df758ca3eff8d` |
| `AC8-Rack-Backpack-v2.0.zip` | `df2f1b8bf9c07a4c5ca91291aa7cda97f833ebe6dc97f3adf18c449bd498d7f4` |
| `Guard-Dog-MG43-v2.0.zip` | `2f9a2e42f522ecf38e5e609d014a61904825fbb027523a0dc99bfac812ac0594` |
| `GuardDogLoadout-v1.0.1.zip` | `686dc8b097880c16531d24b42cafef3b5dd0d8ee4ef6f9d0e2d49f9eeb06aa07` |
| `TD-110-Loadout-v1.0.1.zip` | `1b09849a438f6b396022d4664f3a07cbe5cd6053a666eae46326201e1e72ca42` |
| `ExoLoadout-v0.7.2.zip` | `80e6cbcc47e806cdcb90c5be60e7405589553d7761853da94faab28d6818cf0a` |

`dist/SHA256SUMS.txt` 里是**当前全部 10 个包**的哈希（含旧线：外骨骼两版、No Large Piercing 两版）。

```powershell
cd dist
Get-FileHash *.zip -Algorithm SHA256      # 或 Linux/Git Bash: sha256sum -c SHA256SUMS.txt
```

## 🔁 模组替代关系（旧包仍留在 dist/，但不再更新）

| 新 | 取代 | 为什么 |
|---|---|---|
| `TD-110-Loadout-v1.0` | `TD-110-Co-Op-v1.1` + `TD-110-Busier-Driver-v1.2` | 两者改的是同一条记录的同一个槽位、本来就只能二选一 → 合并成一个包 + 模式切换 |
| `ExoLoadout-v0.7` | `More-Balanced-Exosuit-{Patriot,Emancipator}-v1.2` | 老方案必须二选一（同时装会战备套娃崩溃）→ 改成可配置，只会写一份记录 |
| `GuardDogLoadout-v1.0` | `Guard-Dog-MG43-v2.0` | 从写死 MG-43 变成三选一（原装 / MG-43 / 自定义） |

## 验证记录

| 项 | 结论 |
|---|---|
| `HD2 Scanner v0.7.0` | **2026-10-03 实机**：自检 11/11、连续 51 轮 `命中 7`、面板正常 |
| `AC8-Rack-Backpack-v2.0` | **Scanner 前置接线/日志/自洽检查已在 1.2.4 实机通过**（`已写 2 处`）；2.0 为版本号 + 打包改动，离线回归 **44/44** |
| `Guard-Dog-MG43-v2.0` | 离线回归 **32/32**；**本代未实机**（挂载定位逻辑与已实机的 1.2 同源，改的是前置接线） |
| `GuardDogLoadout v1.0` | **2026-10-03 实机**：`OK - 补丁生效中（1 处）`（默认原装 → 零写入） |
| `TD-110-Loadout v1.0` | **2026-10-03 实机**：`OK - 补丁生效中（挂载 2 处 / 射界 2 处）`，`yaw360 = 1` |
| `ExoLoadout v0.7` | **2026-10-03 实机**：自检 73/73、手臂逐槽写入成功（日志中有意保留一处 `拒写` 告警 = 「既非原装也非目标就拒写」的保护生效） |

## 免责声明

非官方作品，与 Arrowhead Game Studios / Sony Interactive Entertainment 无任何关联；仅在游戏运行时修改本机内存，**不分发任何游戏资产**。游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

---
# v1.3 — No Large Piercing（优化类，**增量发布**）

> GitHub Release 用 tag **`v1.3`**，**附件只有优化类的 2 个包 + `SHA256SUMS.txt`**（不重复打包其他 mod）。
> 其余 6 个 mod 请到上一版合集 **[`v1.2.1`](https://github.com/junze0910/junze-hd2-lua-mod/releases/tag/v1.2.1)** 下载。

**日期**：2026-09-25 ～ **验证环境**：Helldivers 2 `1.8.45850.0` + Bingus Shared Loader **v16（API 1）**

## 📦 本版内容（2 个包）

| 包 | 管理器内名称 | Tag | 作用 |
|---|---|---|---|
| `No-Large-Piercing-v1.0.zip` | **No Large Piercing** | **优化** | 大型穿刺命中特效（`HitEffectDamageType` `3` `PiercingLarge` / `4` `PiercingLargeHEAT`）→ **`0` (`None`)**，完全不再播放 |
| `No-Large-Piercing-Medium-v1.0.zip` | **No Large Piercing (Medium)** | **优化** | 同样改写 → **`2` (`PiercingMedium`)**，降档为中口径，保留命中反馈 |

> 两版**二选一**（改的是同一批字段）。同时启用时后加载的那个会打印提示并自动退出。
> **`优化` / `Optimization` 是目前唯一的 tag**，只包含这两个 mod；其余 mod 暂不归类。

## 🆕 改动面

把《绝地潜兵2》里**大型穿刺类命中特效**从数据表中整体去掉。**纯视觉档位改动，不涉及任何伤害数值。**

| 表 | 字段（记录内偏移） | 记录尺寸 | 游戏内条数 | 被改条目 |
|---|---|---:|---:|---:|
| `ProjectileSettings`（直击 / 弹道） | `+232` `effect_damage_type` | 272 B | 350 | **102**（`3`×90 + `4`×12） |
| `ExplosionSettings`（爆炸） | `+76` `hit_effect_damage_type` | 152 B | 422 | **4**（`3`×4） |

涉及 **AC-8 机炮、GR-8 无后坐力炮、EAT-17 次抛、EAT-411 荡平者、RL-77 空爆、E/AT-12 反坦克炮台、EXO-45 外骨骼导弹、MG-206 重机枪、R-63 勤勉、P-2/P-35 手枪**，以及**机器人各型火箭弹 / 火炮 / 坦克炮、光能族等离子与光束、虫族酸液、轨道与飞鹰系战备**等。完整清单（含枚举编号与名称）见 [`no-large-piercing/INTRO.md`](https://github.com/junze0910/junze-hd2-lua-mod/blob/main/no-large-piercing/INTRO.md)。

## 🔧 原理

两张设置表都是 **LDLD 数据块**（`+0` 魔数、`+8` 类型哈希、`+32` 条数、`+40` 记录数组）。运行时流程：

1. 时间切片扫描内存，按 `LDLD + 版本 + 类型哈希` 签名定位两张表（块间 2 KB 重叠，防止表跨扫描块边界漏检）
2. 定位记录区（描述符相对偏移 / 绝对指针 / 固定 `+40` 三种布局都试，用内容裁决）
3. **内容自洽校验** —— 枚举值域 + 取值多样性，**不依赖记录下标**
4. 逐条 `VirtualProtect` 放开只读页 → 写 4 字节 → 恢复保护属性
5. **整块回读逐条复核**，不符则拒绝并记日志
6. 每 ~10 秒复查；每 ~5 分钟重新枚举内存区域并全量重扫（内存里可能有多份副本，全部改写）

**实机验证**：2026-09-25，两张表均 `已回读验证通过`，`3`/`4` 档计数归零。

**日志**：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`

## ⚠ 关于"记录下标不能当指纹"（本版踩坑记录）

第一版把「记录下标 + 枚举值」当指纹，实机被拒写。排查后确认：官方在版本更新时会**重排记录在表里的排列顺序**，且会**在末尾追加**新枚举编号（弹头 `344..350`、爆炸 `416..422`），但**已有编号不顺延**。

因此本 mod 的校验**完全不依赖记录下标**，只检查内容形态；记录尺寸或字段偏移一旦变化仍会被拦下。详细排查过程见 [`no-large-piercing/INTRO.md` §四](https://github.com/junze0910/junze-hd2-lua-mod/blob/main/no-large-piercing/INTRO.md)。

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
| 外骨骼 v1.1 · **可用次数 → 1、冷却 → 0**（两台外骨骼） | **实机验证 ✓**（2026-09-25） |
| 外骨骼 · 携带解放者版的附加方向、两版二选一保护 | **离线仿真**（真实记录布局，4 场景 × 14 项全过，详见 `more-balanced-exosuit/DESIGN.md`） |

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
