# HD2 Scanner（HD2 扫描器）

**项目地址 / 下载：** https://github.com/junze0910/junze-hd2-lua-mod/releases/latest

## Description · 简介

HD2 Scanner 是一个**前置 / 核心服务 mod**，本身不添加武器、皮肤或游戏内容。

它负责：

1. 在后台按 `LDLD + 版本 + 类型哈希` 定位游戏内存里的数据表；
2. 把表基址通过 `_G.HD2Scanner` 广播给其他 mod；
3. 提供通用全量内存扫描服务 `memscan`，让其他 mod 不必各自重复扫描数 GB 内存；
4. 提供 **AOB 战备表定位**：在 `game.dll` 代码段里解出 `StratagemSettings` 的记录指针数组，
   让消费者按 ID 直接取记录（ExoLoadout 的附加战备就是靠它，毫秒级、不用全内存扫）。

目前依赖它的 mod：

- AC-8 机炮包架
- Guard Dog MG-43 / GuardDogLoadout
- EXO 战备自选
- 装甲车辆轻度改装
- 自定义补给

## Main features · 主要特性

* **数据表广播**（组件区 7 张 + 常驻 2 张；**需新表的消费者**请用 `request`/`poll` 并自行回退）：
  * `WeaponMagazineComponentData` · `HellpodRackComponentData` · `HellpodPayloadComponentData`
  * `TurretComponentData` · `MountComponentData`
  * `ProjectileWeaponComponentData`（v0.8.2+，弹道组件，`projectile_type` @ `+0`）
  * **`WeaponDataComponentData`（v0.8.3 新增**，开火模式/功能组件，`function_info` @ `+168`）
  * 常驻：`ProjectileSettings` · `ExplosionSettings`
* **通用全量扫描 `memscan`**：
  * 对外 API：`scan_request` / `scan_cancel` / `scan_status`
  * 256 KB 分块，块间重叠，防止 pattern 跨块漏检
  * 默认 8 MB/帧预算，不卡游戏
  * 自身 pattern 自动跳过，避免扫到扫描器自己
  * 多请求排队，一次只跑一个全量扫描
  * 命中只回传地址，由消费者自己做校验和写入
* **AOB 战备表定位**（v0.8.0+）：
  * 对外 API：`strat_table_request` / `strat_table_status` / `strat_table_base` / `strat_slot` / `strat_rec`
  * 在 `game.dll` 代码段里匹配一对固定指令，**要求唯一命中**（多命中直接放弃，不猜）
  * 分帧推进（2 MB/帧），解析过程不卡游戏
  * 任何一步不成立都返回明确失败原因，由消费者决定回退
  * 详见 `Scanner-API.md` §4
* **只读**：Scanner 不写任何游戏数据表；只扫描、只广播
* **自检 11/11**：签名解码器与内存里的 MDL 基准逐位一致
* **稳定扫描**：**v0.8.3 实机（2026-10-05）连续 40 轮 `命中 9`**（7 组件 + 2 常驻，9 张表全部广播），每轮区段数/表数稳定
* **日志**：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log`

## How to use · 使用方法

1. 安装 **Bingus Shared Loader v15+（API 1）**，或兼容的 MDL；
2. 用 HD2 mod 管理器导入 `HD2-Scanner-v0.8.3.zip`；
3. 启用并部署；
4. 启动游戏。Scanner 会自己在后台扫描，无需任何操作（界面上那 3 行只在需要排查时才点）；
5. 如需检查状态，查看 `HD2Scanner.log`。

> 作为前置 mod，它没有单独的设置页，但在**原生 MODS 页**（需要 `Mod Options Menu`）里注册了 3 行：
> **扫描状态**（点一下 = 立刻扫一轮，右边描述框里是实时状态）· **解析战备表（AOB）** · **写诊断到日志**。
> 请把它和依赖它的 mod 一起启用。

## Requirements · 依赖

* **Helldivers 2**
* **Bingus Shared Loader v15+（API 1）**，或兼容的 MDL
* 一个能导入 zip 的 HD2 mod 管理器（HD2MM / Arsenal 等）
* Windows x64

## Compatibility · 兼容性

* 被其他 mod 作为前置使用；单独启用不会改变游戏内容。
* 只读扫描本机内存；不修改任何游戏文件。
* 游戏启用 nProtect GameGuard，使用第三方工具的风险由使用者自行承担。

## Logs · 日志

```text
%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log
```

## Shout outs · 鸣谢

* **Bingus** —— Shared Loader 与 addon 工具链；
* **xypwn** —— filediver 与游戏数据 typelib；
* **CowboyBingus** —— HD2 mod 工具链与参考实现。