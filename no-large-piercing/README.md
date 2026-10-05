# No Large Piercing

**下载：** [`../dist/No-Large-Piercing-v1.6.zip`](../dist/)（或仓库 Releases 页）

> **分类：优化类（Optimization）**
> **状态：逻辑已实机验证**（2026-09-25 验证 v1.3/v1.4 的写入与自洽校验；**v1.5/v1.6 的调度改动尚未实机验证**）
> **形态：Lua 注入型运行时内存补丁**
> **前置（推荐）：HD2 Scanner（core 线 v0.8.0+）** —— 找表交给它；没装时自动回退到自带的一次性全量扫描

把《绝地潜兵2》里**大型穿刺类命中特效**从数据表中去掉。纯客户端内存改动，**不修改任何游戏文件**，停用即完全还原。

## 它改了什么

游戏在子弹/弹丸命中时，会按 `HitEffectDamageType` 播一个"命中特效档位"。其中两个档位是：

| 值 | 枚举名 | 含义 |
|---:|---|---|
| `3` | `HitEffectDamageType_PiercingLarge` | 大口径动能穿刺 |
| `4` | `HitEffectDamageType_PiercingLargeHEAT` | 大口径破甲（HEAT） |

本 mod 把数据表里**所有**这两档的记录改写掉：

| 包 | 管理器内名称 | 改写结果 |
|---|---|---|
| `No-Large-Piercing-v1.6.zip` | **No Large Piercing** | → `0` (`None`)，**完全不打**大型穿刺特效 |

> **v1.5 起只维护这一个包**：`No Large Piercing (Medium)`（`→ 2` 降档版）已停止维护/发布，需要时可用 `python tools\build_mod.py no_large_piercing_medium` 自行打包（源码仍在仓库里）。
> 两个变体仍然**互斥**（共用同一把锁），万一同时启用，后加载的那个会打印提示并退出。

## 改动面

| 表 | 字段（记录内偏移） | 记录尺寸 | 你游戏里的条数 | 被改条目 |
|---|---|---:|---:|---:|
| `ProjectileSettings`（直击 / 弹道） | `+232` `effect_damage_type` | 272 B | 350 | **102**（`3`×90 + `4`×12） |
| `ExplosionSettings`（爆炸） | `+76` `hit_effect_damage_type` | 152 B | 422 | **4**（`3`×4） |

受影响的射弹/爆炸条目包含：**AC-8 机炮、GR-8 无后坐力炮、EAT-17 次抛、EAT-411 荡平者、RL-77 空爆、E/AT-12 反坦克炮台、EXO-45 外骨骼导弹、MG-206 重机枪、R-63 勤勉、P-2/P-35 手枪**，以及**机器人各型火箭弹 / 火炮 / 坦克炮、光能族等离子与光束、虫族酸液、轨道与飞鹰系战备**等。完整清单见 [`INTRO.md`](INTRO.md)。

## 依赖

* **Bingus Shared Loader v15 或更高**（loader 日志首行 `Bingus Shared Loader loader-v1x; API 1`）
* **HD2 Scanner（core 线 v0.8.0+）· 可选但强烈建议** —— `_G.HD2Scanner` 在时找表交给它，本 mod 一次内存都不扫；没有它则回退到自带的一次性全量扫描（开机多花约 20 秒）
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）

## 安装

1. 从 [`../dist/`](../dist/) 取包；
2. 用 mod 管理器导入并启用；
3. 进游戏。装了 HD2 Scanner 时：本 mod 订阅它的数据表广播（这两张表就是它的已登记表），启动约 2 秒后催它插队一轮（≈0.5 秒）→ 拿到两张表的全部副本地址 → 写入 + 回读 → **本体不再扫内存**；没装 Scanner 时回退「启动扫一遍、写完即停」。两种情况都不必先进任务。

## 检查日志

`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\NoLargePiercing.log`

```
# 装了 HD2 Scanner（首选路径）：
[NoLargePiercing] 已加载：3/4 → 0 (None)（一次性写入模式；等待第 120 帧开始扫描）
[NoLargePiercing] 已接上 HD2Scanner（前置）：找表交给 Scanner（urgent 一轮 ≈0.5 秒），本体不扫内存
[NoLargePiercing] ProjectileSettings @0x...：条数 350（离线镜像 343，+7）；自洽校验通过 eff3=90 eff4=12 不同type=350
[NoLargePiercing] ProjectileSettings @0x...（直击/弹道）：102 条 3/4 → 0 (None)，已回读验证通过
[NoLargePiercing] ExplosionSettings  @0x...：条数 422（离线镜像 413，+9）；自洽校验通过 eff3=6 eff4=0
[NoLargePiercing] ExplosionSettings  @0x...（爆炸）：6 条 3/4 → 0 (None)，已回读验证通过
[NoLargePiercing] 已交给 HD2Scanner：2 张表 / 108 个地址全部命中；本体不再扫内存，只在 Scanner 报出新副本或金丝雀发现异常时动手（金丝雀：每 60 秒只读这 108 个地址）

# 没装 Scanner（回退路径，会多出这几行自扫日志）：
[NoLargePiercing] 未发现 _G.HD2Scanner —— 回退到自带的一次性全量扫描（每 60 秒再看一次前置）
[NoLargePiercing] 一次性写入模式：3/4 → 0 (None)；启动时扫一遍（每帧 10 ms），写完即停
[NoLargePiercing] 第 1 轮全量扫描开始：5297 个可读区域（预算 10 ms/帧）
[...两张表写入…]
[NoLargePiercing] 一次性写入完成：2 张表 / 108 个地址全部命中，扫描全部停止（金丝雀：每 60 秒只读这 108 个地址）
```

看到 `已交给 HD2Scanner：……全部命中`（或回退路径的 `一次性写入完成……全部命中`）即成功；每条写入在写入时都已 `已回读验证通过`。日志里的 `eff3=? eff4=?` 是**实际扫到的档位计数**，用于确认枚举没有随版本漂移。

同时会在日志目录导出两张表的完整清单（`ProjectileSettings_<地址>.DIAG.csv` / `ExplosionSettings_<地址>.DIAG.csv`），含每一条记录的 `index,type,aux,eff`。

## 卸载

mod 管理器里禁用即可 —— 改动只存在于运行时内存，游戏重启后数据表从磁盘重新加载，**不留任何痕迹**。

## 注意

* **联机风险**：这是客户端本地改动，**其他玩家看不到**，会造成表现不一致；游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。建议单人 / 自己开房时使用。
* 本 mod 改的是**命中视觉特效的档位**，**不改任何伤害数值**。
* 游戏更新后若日志出现「自洽校验失败」，说明记录尺寸或字段偏移变了，此时 mod 会**拒写并留下日志**，不会乱写。
* **换图后的新副本**：装了 Scanner 时由它负责 —— 它每 30 秒复核一遍，新地址会被广播出来，本 mod 自动补写（不需要手动动作）。
* **回退路径的取舍**：没有 Scanner 时走自带一次性扫描，金丝雀只能发现「原地址上的值被写回」；如果游戏把表**换到新地址**（新副本），它看不到。此时手动调用 `_G.HD2_NoLargePiercing_Rescan()`（会顺带催 Scanner），或把 `ONE_SHOT` 改成 `false` 用回 v1.4 的维护式调度。

详见 [`INTRO.md`](INTRO.md)（原理、完整特效清单、踩坑记录）。

## 找表：交给 HD2 Scanner（v1.6）

装了 **HD2 Scanner**（core 线，仓库 `core-v2.0` 那条发布线）时，本 mod **一次内存扫描都不做**：

| 步骤 | 谁做 | 说明 |
|---|---|---|
| 定位两张表 | **Scanner** | `ProjectileSettings` / `ExplosionSettings` **本来就是 Scanner 的已登记表**：它按「区段基址 +0x4 是不是 `LDLD` + 类型哈希」逐区段读 16 字节定位（≈每区段 1 次读），urgent 一轮 ≈0.5 秒 |
| 订阅 | 本 mod | `HD2Scanner.request(hash, name)`，然后 `declare_need()` 催它插队一轮 |
| 校验 + 写入 | 本 mod | 对 `poll()` 广播出的**每一份副本地址**走同一套：读头 → 自洽校验 → 逐条写入 → 整表回读 |
| 之后 | **Scanner** | 每 30 秒复核一遍；换图后表换到新地址时广播会更新 ⇒ 本 mod 自动补写新副本（旧版要手动重扫） |
| 常驻成本 | 本 mod | 金丝雀：每 60 秒只读已写入的 108 个地址（**432 字节/分钟**） |
| 人工兜底 | 本 mod | `_G.HD2_NoLargePiercing_Rescan()`：清空已写入清单并催 Scanner 插队一轮 |

离线夹具实测（真 LuaJIT + 假内核 + 假 Scanner）：本体**区段枚举 0 次**、总读取 **326 KB**（两张表 + 回读复核）。
对比自扫方案要读完整片约 4 GB 地址空间 —— 这就是 v1.6 换掉找表方式的原因。

## 回退：自带一次性写入（v1.5 行为）

`_G.HD2Scanner` 不在（或接上后 30 秒仍广播不到这两张表）时自动回退，行为等同 v1.5：

| 阶段 | 行为 |
|---|---|
| 启动（第 120 帧 ≈2 s） | 时间切片全量扫描：枚举已提交可读区段，1 MB 块 / 每帧 10 ms 预算，按 `LDLD+版本+类型哈希` 找两张表 |
| 找到 | 内容自洽校验 → 逐条写入 → **整表回读复核** → 记下已写地址 |
| 两张表都写完 | 再只读复核一遍全部地址 → 打印「一次性写入完成」→ **彻底停止扫描** |
| 之后 | 每 60 秒只读已写入的 108 个地址（金丝雀）；被写回 `3`/`4` → 补写；地址失效 → 退回维护式调度 |
| 实现细节 | 跨块命中只拼「上块尾 7 字节 + 本块头 7 字节」的 14 字节缝（不再把 2 KB + 1 MB 拼成整块，省掉全轮约 4 GB 字符串拷贝） |

## 开销对比

| 项 | v1.4（维护式调度） | v1.5（一次性写入） | v1.6（Scanner 优先） |
|---|---|---|---|
| 启动找表 | 全量一轮 ≈23 s（实机：第 120→1381 帧写完，整轮到第 1480 帧） | 23 s（写完即中断该轮） | **≈0.5 s**（Scanner 的 urgent 一轮，与其它 mod 共享）|
| 稳态 | 静默 + 每 30 s 扫热区 ≈37 MB（≈4.4 GB/小时）+ 每 3~12 分钟一次全量兜底（每轮约 4 GB） | **0** | **0**（本体不扫；Scanner 的 30 秒探针是它自己的既定开销） |
| 常驻复查 | 每 10 s 读 108 个地址（≈43 字节/秒） | 每 60 s 读 108 个地址（≈7 字节/秒） | 同 v1.5 |
| 换图后的新副本 | 自动（复查 + 热区 + 兜底全量） | 看不到（需手动钩子 / `ONE_SHOT = false`） | **自动**（Scanner 广播新地址） |

开关：`ONE_SHOT = false` 回到 v1.4 维护式调度；`WATCHDOG_EVERY = 0` 连金丝雀也不要；`SCANNER_GIVEUP_FRAMES` 控制回退判定窗口。

离线回归测试：`python _probe\test_nlp.py`（**63 项**，真 LuaJIT + 假 kernel32 + 假 LDLD 表 + 假 Scanner）。
