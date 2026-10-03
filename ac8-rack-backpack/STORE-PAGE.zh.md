# AC-8 75 发机炮背包（AC8 Rack Backpack）

**项目地址 / 下载：** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest
**当前版本：** v2.1

## Description · 简介

把 AC-8 机炮战备包架上的背包，从原版 **50 发**备弹，换成废案版本的 **75 发**备弹。

只替换包架上的背包实体，不改机炮本体、不改伤害、不改弹道。

属于运行时内存补丁：不修改任何游戏文件，禁用 mod 后重启游戏即完全还原。

## 改动内容

> **v2.1**：只做界面退役对齐 —— 删掉那个**从来显示不出来**的自绘面板页（HD2Menu 体系 2026-10-04 退役），
> 在原生 MODS 页加一行「立刻写一次」。**写入与定位逻辑一字未动**。


| 项 | 原版 | 本 mod |
|---|---|---|
| 背包实体 | `E60AE045E0090F4C`（50 发） | `26BDDF070C31B275`（75 发） |
| 包架槽位 | 左右各一份背包 | s1 / s3 **两份一起替换** |
| 机炮本体 | 不动 | 不动 |
| 伤害 / 弹道 | 不动 | 不动 |

> 两份背包必须一起改，否则包架会出现一边新、一边旧。

## Main features · 主要特性

* **+25 发备弹**：50 -> 75
* **内容锚点定位**：
  * 只认 `LDLD + 版本 + 类型哈希` 找表；
  * 不依赖表大小、索引条数、记录大小、记录下标这些会随版本变化的数字；
  * 用旧背包哈希做内容锚点，再用上下文确认是 AC-8 包架记录。
* **多副本全打**：内存里有多少张 `HellpodRackComponentData` 副本，就全部处理。
* **幂等**：已经是新背包就跳过，不重复写。
* **写后复查**：定期直读字段，被地图重载冲掉就补写。
* **Scanner 前置**：
  * 默认地址由 `HD2 Scanner` 广播提供；
  * 缺少 Scanner 时本 mod 不工作，但绝不乱写；
  * 提供回滚开关 `AC8_USE_SELF_SCAN = true`，可切回旧的自扫描路径。

## How to use · 使用方法

> **MODS 页多了一行**：`立刻写一次` —— 按 Scanner 广播的地址重写一次挂载，点完自动弹回。
> 平时不用点（写入是自动的）；只有怀疑没生效、或想换个时机重写时才用。进度看 `AC8RackBackpack.log`。


1. 安装 **Bingus Shared Loader v15+（API 1）**，或兼容的 MDL；
2. 安装 **HD2 Scanner v0.7.0+**；
3. 用 HD2 管理器导入 `AC8-Rack-Backpack-v2.0.zip`，启用并部署；
4. 启动游戏；
5. 进入任务后，mod 会由 Scanner 提供表地址并自动完成替换；
6. 查看日志确认：

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack.log
```

成功时会看到类似：

```text
已替换：表 0x... s1 / s3 E60AE045E0090F4C -> 26BDDF070C31B275
已写 2 处
```

如果缺少 Scanner，状态会显示：

```text
地址来源 = 无 —— 缺 HD2Scanner 前置，本 mod 不工作
```

## Requirements · 依赖

* **Helldivers 2**
* **Bingus Shared Loader v15+（API 1）**，或兼容的 MDL
* **HD2 Scanner v0.7.0+** —— 必需前置，提供表地址
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）
* Windows x64

## Compatibility · 兼容性

* 只改 AC-8 包架记录里的两份背包实体，不碰其他武器。
* 与修改同一背包哈希的 mod 可能冲突；建议不要和其他 AC-8 背包替换 mod 同时使用。
* 只改本机内存；联机时其他玩家通常看不到你的改动。
* 游戏启用 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

## Logs · 日志

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack_STATUS.log
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\AC8RackBackpack_Patch.log
```

## Shout outs · 鸣谢

* **Bingus** —— Shared Loader 与 addon 工具链；
* **xypwn** —— filediver 与游戏数据 typelib；
* **CowboyBingus** —— HD2 mod 工具链与参考实现。