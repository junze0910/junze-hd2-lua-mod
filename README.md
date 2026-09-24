# Junze's HD2 Lua Mods（君则的 HD2 Lua Mod）

Unofficial **runtime memory patches** for Helldivers 2 — no game files are modified.

| Mod (name shown in mod managers) | What it does |
|---|---|
| **AC-8 Cut-Content 75rnd Backpack** | Swaps the AC-8 autocannon's rack backpack for the **cut-content 75-round spare backpack** (vanilla: 50 rounds) |
| **Stronger Kinetic Guard Dog** | Swaps the guard dog's mounted weapon for the **SEAF MG-43** (kinetic), for stronger firepower |

> 中文说明见下方。两个 mod 均已在实机验证。

《绝地潜兵 2》(Helldivers 2) 自研 Lua 内存补丁合集。**不修改任何游戏文件**，只在游戏运行时改写内存里的数据表。

## Mod 一览

| Mod（管理器内显示的英文名） | 中文名 | 作用 |
|---|---|---|
| **AC-8 Cut-Content 75rnd Backpack** | **AC-8 废案 75 发备弹背包（替换原 50 发背包）** | 把战备「AC-8 机炮」包架上的背包，从原版 50 发备弹换成**废案版本的 75 发备弹背包** |
| **Stronger Kinetic Guard Dog** | **更强的实弹狗** | 把机枪犬 `drone_mg` 挂载的武器换成 **SEAF MG-43（实弹）**，火力更强 |

> 命名说明：mod 管理器会把 manifest 里的 `Name` 当文件夹名用，因此包内使用**纯 ASCII 名**（避免导入时出现"目标名/目录名或卷标语法不正确"）；中文名见上表。

两个 mod 均已在实机验证：日志首行显示 `OK - 补丁生效中（N 处）`，并连续运行 40 分钟以上保持生效。

## 依赖

* **Bingus Shared Loader v15 或更高**（loader 日志首行为 `Bingus Shared Loader loader-v1x; API 1`）
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）

## 安装

1. 从 [Releases](../../releases) 下载对应的 zip；
2. 用 mod 管理器导入并启用（**不要手动把 `Addon/` 拷进 `data/`** —— 多个 addon 的包内文件名相同，会互相覆盖）；
3. 进游戏。数据表是在任务里按需加载的，一般进图后约 1 分钟生效；
4. 检查日志：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`
   * `AC8RackBackpack_STATUS.log`
   * `GuardDogMg43_STATUS.log`

   第一行为 `OK - 补丁生效中（N 处）` 即表示成功。

## 技术要点（为什么这些 mod 不怕小版本更新）

旧做法的通病是把"表大小 / 索引条数 / 记录下标"写死当指纹，游戏一更新就**静默失效**（一个字节都不写、界面上毫无提示）。本项目的 addon 一律：

1. **只认签名**：`LDLD` + `u32 版本(=1)` + `u32 djb2(类型名)`，表大小只做 1024~4MB 的合理区间检查；
2. **内容锚点定位**：用目标字段自身的哈希定位（例如 AC-8 用旧背包哈希 + "命中点往前 64/192 字节必须是机炮本体"这个上下文校验），完全不依赖表布局；
3. **多副本全打**：内存里同类型表可能有多份，只打第一份会出现"用一阵子就失效"；
4. **持续维护**：5 秒逐地址复查、30 秒扫"已知副本 ±32KB"、10 分钟全量兜底；
5. 写前 `VirtualProtect`、写后**回读校验**；任何校验不通过只记日志、绝不写入。

## 目录结构

```
ac8-rack-backpack/
  ac8_rack_backpack.lua   # 源码（首行 -- HD2-Addon: mods/dsh/ac8_rack_backpack 是装载器要求的声明）
  DESIGN.md               # 设计说明
guard-dog-mg43/
  guard_dog_mg43.lua
```

打包成可分发的 zip 用 [Bingus Shared Loader 的 `tools/build_addon.py`](https://github.com/CowboyBingus/BingusSharedLoader)。

## 兼容性

* 验证环境：游戏 `1.8.45850.0`、Bingus Shared Loader v16（API 1）
* 由于不依赖版本相关常量，同大版本内的小更新一般无需改动；若游戏改了数据表内容（例如换了背包哈希），addon 会**拒写并留下日志**，不会乱写。

## 免责声明

* 非官方作品，与 Arrowhead Game Studios / Sony Interactive Entertainment 无任何关联；
* 仅在本机运行时修改内存，**不分发任何游戏资产**；
* 游戏启用了 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

## 许可

MIT，见 [LICENSE](LICENSE)。
