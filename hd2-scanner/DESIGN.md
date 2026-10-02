# HD2 Scanner

ESC 菜单浮窗 + （规划中的）扫描内核。设计见
[`hd2-mod/docs/MENU-PANEL-设计定稿.md`](../../docs/MENU-PANEL-设计定稿.md)（该文档待随合体改写）。

- 入口资源：`mods/junze/hd2_scanner`
- 依赖：**BSL v15/API1 或 MDL 1.4.2**（任一即可）
- 日志：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\HD2Scanner.log`
- 配置：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\HD2Scanner.cfg`（改完 1 秒热生效）
- 面板位置：`%LOCALAPPDATA%\CowboyBingus\Helldivers2\HD2Scanner.pos`（拖标题栏后自动记）

> **改名记录**：v0.4.1 及以前叫 `HD2 Scanner`（资源名 `mods/junze/hd2_scanner`）。
> 因为「只整浮窗」之后面板不再写游戏内存，原来的「必须拆两个 mod」不再成立，
> 于是把菜单面板并入 Scanner 本体，见下。

## 架构（合体）

```
┌─ HD2 Scanner（一个 mod）──────────────────────────────┐
│  数据层（只读）  ← 待建，见 SCANNER-设计定稿.md          │
│    _G.HD2Scanner = { request, poll, watch }  ← 给其它 mod │
│  菜单浮窗 + 插件注册表（现有）                          │
│    面板自己的页 = 扫描状态（直接读内核，不走 _G）        │
└────────────────────────────────────────────────────────┘
```

## 模块结构（多资源 archive）

一个 `.patch_N` 里放 **6 个 Lua 资源**，只有入口带 `-- HD2-Addon:` 声明：

| 源文件 | 资源名 | 职责 |
|---|---|---|
| `src/hd2_scanner.lua` | `mods/junze/hd2_scanner` | **入口**：守卫 / `P` / 热配置 / 自检基准 / `resolve_once` / 帧循环 / 钩子 / 面板自注册 |
| `src/platform.lua` | `.../hd2_scanner/platform` | ffi、kernel32、内存读写、日志、二进制小工具、`game_open` |
| `src/scan.lua` | `.../hd2_scanner/scan` | **game.dll 签名扫描** + MENU / TAB / FONTS 解码器 |
| `src/ui.lua` | `.../hd2_scanner/ui` | user32 输入、stingray 浮窗渲染、字体装配、拖曳 |
| `src/tab.lua` | `.../hd2_scanner/tab` | 菜单探测（跟随 ESC）+ 页签落位（**默认关闭**） |
| `src/registry.lua` | `.../hd2_scanner/registry` | 插件注册表 / `_G.HD2Menu` / pending 队列 |

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
python test/test_load.py       # 装载 + 插件注册表 + cfg 解析 + 惰性加载（23 项）
python test/test_decoders.py   # 合成镜像单测三个解码器 + 9 个变异
```

夹具注意（踩过的坑，别再踩）：
- **路径必须纯 ASCII** —— Lua 的 `io.open` 按 ANSI 解路径，含中文会静默失败
- **指针值必须真实量级** —— 名字表存的是 `0x7FF9xxxxxxxx` 这种绝对指针，用小地址会让判据 bug 免疫
- **cfg 必须带行尾注释** —— 默认模板每行都有注释，不带注释测不出解析 bug

## 当前状态

| | |
|---|---|
| 浮窗显示 | ✅ 实机验证 |
| 中文文字 | ✅ 实机验证 |
| 拖曳 + 位置记忆 | ✅ 已实现（v0.4.0） |
| 悬停 / 点击闪光 | ✅ 已实现（v0.4.1） |
| 面板自带状态页 | ✅ 已实现（v0.4.2） |
| 不崩 | ✅ 重画前 destroy_gui（v0.3.5 起） |
| **扫描内核** | ⏳ **待建**（SCANNER-设计定稿 阶段 1） |

## 已知 TODO

- **扫描内核**：偏移直读 → 广播 → 失效检测 → 退化全量（设计定稿 §4/§5）
- `font.*` 自检在开机瞬间会 MISMATCH —— 字体子系统那时还没就绪，ui 会在用时重试（**无害**）
- `tab.lua` 的 `claim_tab` 现在默认不走（`claim=off`），代码留着备用