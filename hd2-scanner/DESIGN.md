# HD2 Scanner

**前置服务 mod**：数据表定位/广播 + 通用全量内存扫描 + AOB 战备表定位。
界面只有**原生 MODS 页（`_G.ModOptionsMenu`）里的 3 行**；自绘面板已于 2026-10-04 退役。

- 入口资源：`mods/junze/hd2_scanner`
- 依赖：**BSL v15/API1 或 MDL 1.4.2**（任一即可）；界面可选依赖 **Mod Options Menu**
- 日志：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log`
- 配置：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\HD2Scanner.cfg`（改完 1 秒热生效）
- 对外 API：`_G.HD2Scanner`（见 `Scanner-API.md`）

> **界面变迁**：v0.4.1 起自带 ESC 浮窗面板；2026-10-03 默认关闭；**2026-10-04 整个页面体系退役**
> （渲染宿主 `ui.lua` 不再打包，`registry.lua`/`_G.HD2Menu` 删除）。现在一律注册 ModOptionsMenu。
> 历史设计见 [`docs/MENU-PANEL-设计定稿.md`](../../docs/MENU-PANEL-设计定稿.md)（顶部有退役横幅）。

## 架构（合体）

```
┌─ HD2 Scanner（一个 mod）───────────────────────────────────┐
│  数据层（只读）  kernel.lua：LDLD 表定位 + 广播             │
│    _G.HD2Scanner = { request, poll, watch, status, ... }    │
│  memscan.lua   通用全量扫描服务（消费者提交 pattern）        │
│  aob.lua       game.dll AOB → 战备记录指针数组（strat_*）    │
│  界面            ModOptionsMenu 3 行（状态 / AOB / 诊断）    │
└────────────────────────────────────────────────────────────┘
```

## 模块结构（多资源 archive）

一个 `.patch_N` 里放 **6 个 Lua 资源**，只有入口带 `-- HD2-Addon:` 声明：

| 源文件 | 资源名 | 职责 |
|---|---|---|
| `src/hd2_scanner.lua` | `mods/junze/hd2_scanner` | **入口**：守卫 / `P` / 热配置 / 自检基准 / `resolve_once` / 帧循环 / 钩子 / MOM 面板注册 |
| `src/platform.lua` | `.../hd2_scanner/platform` | ffi、kernel32、内存读写、日志、二进制小工具、`game_open` |
| ~~`src/ui.lua`~~ · ~~`src/registry.lua`~~ | — | **已退役（2026-10-04）**：不打包、不加载。界面改走 `_G.ModOptionsMenu`；ui.lua 源码保留在 `src/`（顶部有说明） |
| `src/scan.lua` | `.../hd2_scanner/scan` | **game.dll 签名扫描** + MENU / TAB / FONTS 解码器 |
| `src/tab.lua` | `.../hd2_scanner/tab` | 菜单探测（跟随 ESC）+ 页签落位（**默认关闭**） |
| `src/memscan.lua` | `.../hd2_scanner/memscan` | 通用全量扫描服务（消费者提交 pattern） |
| `src/aob.lua` | `.../hd2_scanner/aob` | **game.dll AOB 解战备记录指针数组**（只读，分帧） |

> ⚠️ `scan.lua` 扫的是 **game.dll 的机器码签名**；将来的扫描内核（扫数据表）是**另一件事**，
> 会作为 `kernel.lua` 新增，别混淆。

### 为什么模块资源不带声明头

loader 的 discovery（`discover.lua:91`）只认「**声明名 == 资源名哈希**」的条目。
模块资源不带声明 ⇒ 不会变成独立 addon（否则管理器里会显示成 6 个 mod）。

⚠️ **别用 `tools/build_addon.py --extra`** —— 那条路径会给每个 extra 也补上声明头。

## 打包

```powershell
python build.py                      # → hd2-mod/build/HD2-Scanner-vX.Y.Z.zip（工作构建）
python build.py --release            # 额外拷进 junze-hd2-lua-mod/dist/ 并打印 SHA256
python build.py --verify <zip>       # 只校验已打好的包
```

产物去向见 SKILL.md §10。**版本号只写在 `src/hd2_scanner.lua` 的 `version = '...'` 里**，build.py 跟着它走。

## 测试（离线，不需要游戏）

```powershell
python test/test_load.py       # 装载 + cfg + AOB 解链 + MOM 面板 + 源码卫生（59 项）
python test/test_decoders.py   # 合成镜像单测三个解码器 + 9 个变异
```

夹具注意（踩过的坑，别再踩）：
- **路径必须纯 ASCII** —— Lua 的 `io.open` 按 ANSI 解路径，含中文会静默失败
- **指针值必须真实量级** —— 名字表存的是 `0x7FF9xxxxxxxx` 这种绝对指针，用小地址会让判据 bug 免疫
- **cfg 必须带行尾注释** —— 默认模板每行都有注释，不带注释测不出解析 bug

## 当前状态

| | |
|---|---|
| 数据表广播（7 张表） | ✅ 实机验证（连续多轮 `命中 7`） |
| 签名解码器自检 11/11 | ✅ 实机验证 |
| `memscan` 通用全量扫描 | ✅ 实机验证（14,242 区段 / 5.2 GB / 约 13 s） |
| AOB 战备表定位（`strat_*`） | ⏳ **待实机验证**（离线：合成映像解链 + 不唯一安全网） |
| MOM 面板 3 行 | ⏳ **待实机验证**（离线：注册/弹回/超长保护） |
| 自绘面板（ui.lua） | ⛔ 已退役（2026-10-04，不再打包） |

## 已知 TODO

- **kernel 的 HUNT 阶段**未实现（落空只记日志）——AOB 路线已覆盖原需求，优先级低
- `font.*` 自检在开机瞬间会 MISMATCH（字体子系统还没就绪）：只在自检里体现，**无害**
- `tab.lua` 的 `claim_tab` 默认不走（`claim=off`）；第 5 槽位实测会崩（`0xC0000026`），
  `allow_5th` 开关现在**真的接线了**（2026-10-04 修）但默认关
- `watch/unwatch/watched` 是**兼容占位**（没有消费者读 `watched`），见 `Scanner-API.md` §2.3