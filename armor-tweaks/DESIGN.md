# 装甲车辆轻度改装（armor_tweaks）· 设计

> 状态：**源码完成 + 离线回归 147/147 通过**（2026-10-05）· **v1.1.0** · 实机待验（M-102 线未上机）
> 版本历史：v1.0.0 = TD-110 + TD-220 + 40mm 弹种（已发布 `vehicle-v2.0`）；v1.0.1 = 40mm「游戏内可编程弹药切换」**已回退**（见 §九）；
> **v1.1.0 = 新增 M-102 快速侦查载具（两个变体）+ 挂载腿改为按车独立**。
> 取代：`td-110-co-op`（TD-110 Co-Op）+ `td-110-driver-armament`（Busier TD-110 Driver）

---

## 一、总览：四条腿 + 三辆车

| 腿 | 目标表 | 改什么 | 生效时机 |
|---|---|---|---|
| ① 挂载 | `MountComponentData` `0x3845B1E0` | TD-110 槽1/槽2、TD-220 槽1、**M-102 槽0（两个变体）**的 item(u64) | 生成载具时读一次 → **重新召唤** |
| ② 射界 | `TurretComponentData` `0x1EBA7593` | 4 条炮塔记录的 `+28/+32`（水平下限/上限）→ ±180 | **实时** |
| ③ 弹种 | `ProjectileWeaponComponentData` `0x45171B68` | 40mm 记录 `+0` u32 `projectile_type`：120 ⇄ 284 | **实时** |
| ④ 状态/落盘 | — | `ArmorTweaks.log` / `ArmorTweaks_STATUS.log`、MOM 页 6 行、Scanner 全局「初始化」 | — |

**射界的 4 个目标**（默认常驻开）：TD-110 激光炮塔（recIdx 28）、TD-110 加特林主炮（29）、TD-220 主炮（26）、TD-220 同轴重机枪（27）。
**M-102 没有射界腿** —— 它的车载武器没有 `TurretComponentData` 记录（Turret 表里 FRV 只出现 M-103 的 AR 哨戒炮）。

---

## 二、挂载腿：按车独立（v1.1.0 的核心改动）

### 2.1 车辆档案（全部 dl_bin + hd2-rawdata 双验证）

| 车 | 本体哈希（索引区键） | recIdx | 槽位 | 槽位 node | 备注 |
|---|---|---|---|---|---|
| TD-110 风暴漩涡 | `B0C9FAF4AF8903F9` | 123 | 槽0 主炮 / **槽1 炮手** / **槽2 驾驶员** / 槽3,4 垂发 | `0xE30C5711` / `0xB7E9B43D` / `0x79CC4582` / … | 只改槽1、槽2 |
| TD-220 堡垒 MK XVI | `16474112801385B6` | 23 | 槽0 主炮 / **槽1 同轴重机枪** | `0xE30C5711` / `0xB7E9B43D` | 只改槽1；`0xB7E9B43D` 与 TD-110 炮手位**共用** |
| M-102 快速侦查 | `CC21C7FFD3EBEFB9` | 19 | **只有槽0** | `0x53BEC437` | 槽1..4 全空 |
| M-102（地图产出） | `E9CD1D0D118886AF` | 117 | **只有槽0** | `0x53BEC437` | 与上一条**逐字段相同** |

> `0xB7E9B43D` 被 TD-110 与 TD-220 共用 ⇒ **node 不能当身份**；身份 = **索引区的本体哈希**（全表唯一），
> node 只按**已知槽位下标**做二级复核（与机甲 mod 的写法一致）。

### 2.2 「按车独立」的判据

```
for 每个候选起点（从最大 base 往小试）:
    对每辆车独立执行：find_rec(本体哈希) -> job.check(node) -> job.write(槽位)
    只要 至少一辆车 复核通过 -> 认定这个 base 是真起点，写入通过的车，跳过没通过的车（记日志）
    一辆都没通过 -> 试下一个候选起点
```

* 跳过日志（6000 帧节流）：
  `挂载表 0x…：以下车辆本轮跳过（按车独立，不影响其它车）—— TD-220：记录没找到；M-102：M-102 槽0 node 复核不过`
* **为什么改**：v1.0.0 的判据是「四条记录全部找到 + 全部复核通过才写」——
  将来任何一个变体改名 / 换模型 / 换挂点，TD-110 也会跟着停写。按车独立后互不牵连。
* **为什么仍然安全**：每辆车的 node 复核是 `u32` 精确比对（假起点命中概率 ≈ 2⁻³²）；且**至少一辆车通过**才认这个 base。
* 覆盖判据不变（见 §六）：白名单件 / 自己上次写的值 / 初始化强制。

### 2.3 M-102 的三档

| 档（cfg `m102`） | item | 哈希 |
|---|---|---|
| `frv`（默认，原装） | M-102 车载重机枪 `frv_mg` | `085C1EDB038EC24E` |
| `hmg` | 重机枪武器站 | `C25DC40EDE0E2D16` |
| `ac40` | 40mm 机炮武器站 | `9872EEB31A5F88FD` |

* `0x085C1EDB038EC24E` = `content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg`，
  它同时也是完整的武器实体：`ProjectileWeapon` recIdx 256（`projectile_type = 271`、rpm y=600、`rpc_synced_fire_events = 0`）、
  `WeaponData` 348、`WeaponMagazine` 258、`WeaponReload` 235、`WeaponCustomization` 179、`LoadoutPackage` 513。
* **不提供 M-104 火焰喷射器**（`0x444880F62CA7EAE8`，虽然它用**同一个 node**）：该武器有资源加载问题（用户 2026-10-05 决定）。
* **不提供弹种切换**：`frv_mg` 的 `rpc_synced_fire_events = 0`，与 40mm 同理（联机只有本机可见），且本批不做。

---

## 三、TD-110 四档模式（v1.0.0 起未变）

| 模式 | 驾驶员位（槽2） | 炮手位（槽1） |
|---|---|---|
| 原装 vanilla | 烟雾弹发射器 | 激光制导部件 |
| 合作 coop | 激光制导部件 | **烟雾弹发射器 ⇄ 40mm 机炮武器站** |
| 忙碌 busy | **重机枪武器站（主）⇄ 40mm 机炮武器站** | 激光制导部件 |
| 自定义 custom | 5 选 1 | 5 选 1 |

* **硬不变量：两个槽位恰好一个激光**（自定义同样受限；违反 = 拒写 + 控件弹回当前值 + 日志说明）。
* 白名单 5 件：重机枪武器站 `C25DC40EDE0E2D16`、40mm 机炮武器站 `9872EEB31A5F88FD`、
  额外导弹发射器 `8AFF7F0793A5BCED`、烟雾弹发射器 `3A061009AA31E9CB`、激光制导部件 `C36B5B37C058DBDD`。
* TD-220 原装同轴重机枪 `439F9E65C18567DA` 与 **M-102 原装重机枪 `085C1EDB038EC24E` 不在可选白名单里**，
  但登记进 `ITEM_LE / KNOWN_ITEM`（要认得出、初始化要写得回）。

---

## 四、射界腿（实时）

* 目标 4 条（§一），记录 `+28` = 下限 f32、`+32` = 上限 f32；原装 ±20（`0xC1A00000 / 0x41A00000`），
  本 mod 写 ±180（`0xC3340000 / 0x43340000`）。
* 认表判据：**所有**目标武器都要找到，且射界是已知形态（±20 / ±180）。只有真起点 +2336 同时满足。
* 例外：**初始化强制回原装**时，允许覆盖「认不出来的形态」，但要求该地址**以前验证过**（对应机甲 mod 的 6.25）。
* ⚠ **只解水平射界，不解除视角限制**。

## 五、弹种腿（实时）

* 40mm 机炮武器站 `9872EEB31A5F88FD` 的 `ProjectileWeaponComponentData` 记录 `+0`：
  **120 = 40mm 穿甲高爆（原装）** ⇄ **284 = 机炮 20mm 防空（近炸子母，「20mm 高射」）**。
* 写入前必须读到 120 或 284，否则拒写（6000 帧节流报告）。
* ⚠ `rpc_synced_fire_events = 0` ⇒ 弹种切换**只有本机可见**（40mm 不广播开火事件；AC-8 / TD-220 主炮才是 1）。

---

## 六、配置界面与 cfg

配置**只有**原生 MODS 页（`_G.ModOptionsMenu`），分组 `A HD2 MOD COLLECTION`，**6 行**：

| 行 id | 标签 | 类型 |
|---|---|---|
| `armor_tweaks.preset` | `[TD-110] 预设` | choice × 6 |
| `armor_tweaks.gunner` | `[TD-110] 炮手槽位` | choice × 5 |
| `armor_tweaks.driver` | `[TD-110] 驾驶员槽位` | choice × 5 |
| `armor_tweaks.td220` | `[TD-220] 重机枪位` | choice × 2 |
| `armor_tweaks.proj` | `[40mm] 弹种` | choice × 2 |
| `armor_tweaks.m102` | `[M-102] 车载武器` | choice × 3 |

**「初始化」**挂在 Scanner 的全局注册表（`HD2Scanner.register_reset('装甲车辆', do_reset)`）：
写回原装 + cfg 复位 + 清期望 + `state.force_vanilla`（允许强制覆盖认不出来的值）。

cfg：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\ArmorTweaks.cfg`（1 秒热重读），
键：`mode / coop_gun / busy_gun / yaw360 / driver / gunner / td220 / proj / m102`。

---

## 七、红线

* 只写目标字段（挂载槽的 8 字节 item / 射界 8 字节 / 弹种的 4 字节）；**node、flags 一字不动**。
* 挂载槽里的值不在白名单（= 别的 mod 改过）→ **拒写**，不覆盖别人；想回原装用「初始化」。
* 写前 `VirtualProtect`、写后**回读校验**；失败一律记 refuse，绝不当成功。
* 不碰 `WeaponMagazineComponentData`（弹匣腿按用户决定去掉）。
* 不写网络包；只改本机内存。

---

## 八、离线回归（`_probe\test_armor_tweaks.py`，147 条断言）

假内存里合成三张真布局的表：`MountComponentData`（324 索引 × 163 记录 × 120 B）、
`TurretComponentData`（146 × 74 × 76 B）、`ProjectileWeaponComponentData`（542 × 272 × 616 B）；
起点与 dl_bin 实测一致（+5184 / +2336 / +8672）。

覆盖：默认 coop + 射界 360、四档模式与两个子选项、双激光被拒、非白名单拒写、类型哈希改坏、
索引抽记录（TD-110 / TD-220 / **M-102 两个变体**）、node 改坏（TD-110 / **M-102 地图产出**）、
**按车独立**、初始化强制回原装（6.25）、幂等、日志与 STATUS 落盘、MOM 注册与联动（6 行）、
TD-220 二档、40mm 弹种二档、**M-102 三档**。

---

## 九、已回退：40mm「游戏内可编程弹药切换」（v1.0.1，知识留着）

做法（照 AC-8 配方，曾通过 129/129）：① `WeaponDataComponentData.function_info.left = 8`
（`WeaponFunctionType_ProgrammableAmmo`）② `ProjectileWeaponComponentData.weapon_function_projectile_type = 备选弹`。

**为什么回退**：
1. 是「凭空造」的切换 —— 官方只有 6 把武器带 `function_info.left = 8`（P-92 / P-33 / RL-77 / AC-8 / WASP / GR-8），
   40mm 原本 `{None, None}`，**没上机验证过**；
2. **不同步到队友** —— 40mm 的 `rpc_synced_fire_events = 0`，弹种切换只有本机可见。
   保留 MOM 的 `[40mm] 弹种`（直接改 `projectile_type`，实时生效、已验证）。

**反例**：TD-220 主炮填了 `weapon_function_projectile_type = 36` 却 `function_info = {None,None}` ⇒ 数据残留，切不了。

---

## 十、待办

- ~~实机验证 v1.1.0 / TD-110 / TD-220 线~~：**已实机运行通过（用户确认，2026-10-05）** —— TD-110 / TD-220 / M-102 三辆车。
  ⚠ 未留原始日志行：按 §6.33 的精神，要对外写"实测细节"（射界能否转满一圈 / M-102 后两档手感）还得补一次带日志的复验。
- Arsenal 库换代：库里还是 `HD2-Scanner-v0.8.1` 与 `TD-110-Loadout-v1.0.2`；Armor-Tweaks 要作为**新条目**导入，旧的 TD-110-Loadout 手动删。
4. `Scanner-API.md` 补表：`ProjectileWeaponComponentData 0x45171B68` / `WeaponDataComponentData 0x88E4DBB1`。
