"""解码器离线回归：合成镜像单测 MENU / TAB / FONTS 三个解码器（+ 变异测试）。

磁盘上的 game.dll 是加壳的（熵 8.0，见 SKILL.md 6.13），没法离线验签名本身；
这里只验**解码算术**——把一段合成机器码摆好，看解码器能不能原样把数字读回来。
off-by-one 之类的错会立刻暴露。

注意：现在只需 require `.../platform` 和 `.../scan` 两个模块，不再需要整个 mod。
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness

# ------------------------------------------------------------------ 常量（事实）
MENU_SIG = ("40 53 48 83 EC 20 48 8B 1D ?? ?? ?? ?? 8B 03 3B C2 75 ?? 80 BB ?? ?? 00 00 00 74 ?? "
            "44 8B C0 48 8D 15 ?? ?? ?? ?? 48 8D 05 ?? ?? ?? ?? 48 8D 0D ?? ?? ?? ?? 4E 8B 04 C0")
TAB_SIG = ("49 8D 9F ?? ?? ?? ?? BA ?? ?? 00 00 48 8B CB C6 83 ?? ?? ?? ?? 01 E8 ?? ?? ?? ?? "
           "41 B8 03 00 00 00 48 8D 15 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 48 8B D3 "
           "41 C7 87 ?? ?? ?? ?? 03 00 00 00 49 8D 4F 10 41 88 B7 ?? ?? ?? ??")
SET_LABELS_PROLOGUE = ("48 89 54 24 10 53 56 48 83 EC 68 0F 29 74 24 30 48 8B C2 48 89 7C 24 60 "
                       "48 8B F1 4C 89 6C 24 50 4C 89 7C 24 40 41 BF 08 00 00 00 45 3B C7 45 8B EF "
                       "45 0F 4C E8 44 89 A9")
SET_LABEL_HEAD = "48 83 EC 28 4C 8B D9 39 91 10 01 00 00"
ARG_SIG = ("40 53 48 83 EC 20 48 8B D9 48 81 C1 10 01 00 00 E8 ?? ?? ?? ?? 84 C0 74 ?? "
           "8B 93 B8 00 00 00 8B C2 83 C8 02 89 83 B8 00 00 00 3B C2 74")
ARG_RECORD_HEAD = "48 89 5C 24 18 57 48 83 EC 40 44 0F B6 99 58 01 00 00"
FONTS_SIG = ("48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 48 89 7C 24 20 41 54 41 56 41 57 "
             "0F 57 C0 8B C1 0F 57 C9 4C 8D 25 ?? ?? ?? ?? 33 DB 0F 11 05 ?? ?? ?? ?? "
             "48 8D 3C C5 00 00 00 00 33 C0 4E 8B 94 27")

E = dict(menu_global=0x12340, menu_open=2185, menu_names=0x29000,
         tab_bar=1248, tab_count=57448, tab_labels=57320, tab_text=8296,
         tab_first=0x2C00, tab_set_labels=0x20000, tab_set_arg=0x22300,
         font_font_hex="aabbccdd11223344", font_atlas_hex="0f1e2d3c4b5a6978",
         font_material_hex="deadbeefcafebabe")
E["tab_state"] = E["tab_bar"] + E["tab_first"] + 2012
E["tab_flag"] = E["tab_state"] + 17
LABELS3 = (0xD876B36E, 0x78934E12, 0x8C02BD80)
# ⚠ 名字表里存的是**绝对指针**（0x7FF9xxxxxxxx 量级），夹具必须用真实量级，
#   否则 read_names 的「指针范围判据写错」这类 bug 测试根本抓不到（2026-10-02 吃了这个亏）。
BASE = 0x7FF900000000


def build_fixture():
    IMG = 0x30000
    img = bytearray(IMG)
    def w32(o, v): struct.pack_into("<I", img, o, v & 0xFFFFFFFF)
    def w16(o, v): struct.pack_into("<H", img, o, v & 0xFFFF)
    def w64(o, v): struct.pack_into("<Q", img, o, v & 0xFFFFFFFFFFFFFFFF)
    def wsig(o, sig):
        for i, t in enumerate(sig.split()):
            if t != "??": img[o + i] = int(t, 16)
    def wb(o, s): img[o:o + len(s)] = s.encode("latin-1")

    w16(0, 0x5A4D)
    PE, TSTART, TSIZE = 0x80, 0x1000, 0x28000
    w32(0x3C, PE); img[PE:PE + 4] = b"PE\0\0"
    w16(PE + 6, 1); w16(PE + 20, 0xF0); w32(PE + 24 + 56, IMG)
    sh = PE + 24 + 0xF0
    w32(sh + 8, TSIZE); w32(sh + 12, TSTART); w32(sh + 36, 0x60000020)

    at = TSTART + 0x1000                       # MENU
    wsig(at, MENU_SIG)
    w32(at + 9,  E["menu_global"] - (at + 13))
    w32(at + 21, E["menu_open"])
    w32(at + 41, E["menu_names"] - (at + 45))
    for i, nm in enumerate(["None", "InGame", "Hologram", "Count"]):
        o = 0x2A000 + i * 0x40; wb(o, nm)
        w64(E["menu_names"] + 8 * i, BASE + o)      # 真实量级的绝对指针

    at = TSTART + 0x2000                       # TAB
    wsig(at, TAB_SIG)
    w32(at + 3,  E["tab_bar"])
    w32(at + 36, 0x28000 - (at + 40))
    w32(at + 44, E["tab_set_labels"] - (at + 48))
    w32(at + 54, E["tab_state"])
    w32(at + 69, E["tab_flag"])
    for i, v in enumerate(LABELS3): w32(0x28000 + 4 * i, v)

    FN = E["tab_set_labels"]
    wsig(FN, SET_LABELS_PROLOGUE)
    w32(FN + 0x38, E["tab_count"])
    img[FN + 0x4A] = 0x81; img[FN + 0x4B] = 0xC1
    w32(FN + 0x4C, E["tab_labels"])
    img[FN + 0x100] = 0x48; img[FN + 0x101] = 0x8D; img[FN + 0x102] = 0xBE
    w32(FN + 0x103, E["tab_first"])
    wb(FN + 0x110, "\x48\x81\xc7\x48\x0d\x00\x00")
    LL = FN + 0x120
    wb(LL, "\x8b\x1c\xa8\x48\x8d\x8f")
    w32(LL + 6, E["tab_text"] - E["tab_first"])
    wb(LL + 10, "\x8b\xd3\xe8")
    w32(LL + 13, 0x22000 - (LL + 17))
    wsig(0x22000, SET_LABEL_HEAD)

    AA = E["tab_set_arg"]
    wsig(AA, ARG_SIG)
    w32(AA + 17, 0x24000 - (AA + 21))
    wsig(0x24000, ARG_RECORD_HEAD)

    at = TSTART + 0x3000                       # FONTS
    wsig(at, FONTS_SIG)
    w32(at + 0x25, 0 - (at + 0x29))
    img[at + 0x25E:at + 0x262] = b"\x4b\x89\x84\x21"
    img[at + 0x268:at + 0x26C] = b"\x4b\x89\x84\x21"
    w32(at + 0x262, 0x8000); w32(at + 0x26C, 0x9000)
    w32(at + 0x2E, 0xA000 - (at + 0x32))
    w64(0x8000, 0xAABBCCDD11223344)
    w64(0x9000, 0x0F1E2D3C4B5A6978)
    w64(0xA008, 0x2C000)
    w64(0x2C018, 0xDEADBEEFCAFEBABE)
    return bytes(img)


CHECK_LUA = r'''
RESULT = (function()
    local platform = require('mods/junze/hd2_scanner/platform').new({
        loader = { log_directory = [=[%s/Logs]=] }, P = {} })
    local scan = require('mods/junze/hd2_scanner/scan').new({ platform = platform })
    local s = FIX
    local get = function(i) return s:byte(i + 1) end
    local out = {}
    local function san(v) local x = tostring(v):gsub('[^\32-\126]', '?') return x:sub(1, 120) end
    local function put(k, v) out[#out+1] = k .. '=' .. san(v) end

    -- 名字表的条目是绝对指针：读它要按 BASE 映射回夹具缓冲区
    local function readmem_abs(a, n)
        if a < BASE then return nil end
        return s:sub(a - BASE + 1, a - BASE + n)
    end

    local ts, tsz, why = scan.text_section(get)
    put('text_start', ts); put('text_size', tsz); put('image_size', why)

    local mok, menu = pcall(scan.MENU.resolve, get, ts, tsz)
    if mok and menu then
        put('menu_global', string.format('%%d', menu.global))
        put('menu_open', menu.open)
        put('menu_names', string.format('%%d', menu.names))
        local names = scan.MENU.read_names(readmem_abs, BASE, menu)
        put('names', table.concat({names[0] or '?', names[1] or '?', names[2] or '?', names[3] or '?'}, ','))
    else put('menu_err', 'ERR') end

    local tok, tab = pcall(scan.TAB.resolve, get, ts, tsz)
    if tok and tab then
        for _, k in ipairs({'bar','count','labels','text','state','flag','first','set_labels','set_arg'}) do
            put('tab_'..k, string.format('%%d', tab[k]))
        end
        put('labels3', string.format('%%X,%%X,%%X', tab.expected[0], tab.expected[1], tab.expected[2]))
    else put('tab_err', 'ERR') end

    local fok, slots = pcall(scan.FONTS.resolve, get, ts, tsz)
    if fok and slots then
        for _, k in ipairs({'font','atlas','material'}) do
            put('slot_'..k, string.format('%%d', slots[k]))
        end
        local rok, h = pcall(scan.FONTS.read, function(a, n) return s:sub(a + 1, a + n) end, 0, slots)
        if rok and h then
            put('font_hex', h.font); put('atlas_hex', h.atlas); put('material_hex', h.material)
        else put('font_read_err', 'ERR') end
    else put('font_err', 'ERR') end
    return table.concat(out, '\n')
end)()
''' % harness.WORK.replace("\\", "/")


def run(scan_override=None):
    lua = harness.new_lua()
    if scan_override is not None:
        lua.globals()["MUT_SRC"] = scan_override
        lua.execute("package.preload['mods/junze/hd2_scanner/scan'] = "
                    "function() local f = assert(loadstring(MUT_SRC, '@scan')); return f() end")
    lua.globals()["BASE"] = BASE      # 名字表条目是绝对指针，Lua 侧要用同一个基址
    lua.globals()["FIX"] = build_fixture()
    lua.execute(CHECK_LUA)
    out = {}
    for line in lua.eval("RESULT").split("\n"):
        if "=" in line:
            k, v = line.split("=", 1); out[k] = v
    return out


EXPECT = {
    "text_start": str(0x1000), "text_size": str(0x28000), "image_size": str(0x30000), "menu_global": str(E["menu_global"]), "menu_open": str(E["menu_open"]),
    "menu_names": str(E["menu_names"]), "names": "None,InGame,Hologram,Count",
    "tab_bar": str(E["tab_bar"]), "tab_count": str(E["tab_count"]), "tab_labels": str(E["tab_labels"]),
    "tab_text": str(E["tab_text"]), "tab_state": str(E["tab_state"]), "tab_flag": str(E["tab_flag"]),
    "tab_first": str(E["tab_first"]), "tab_set_labels": str(E["tab_set_labels"]),
    "tab_set_arg": str(E["tab_set_arg"]),
    "labels3": "%X,%X,%X" % LABELS3,
    "slot_font": str(0x8000), "slot_atlas": str(0x9000), "slot_material": str(0xA008),
    "font_hex": E["font_font_hex"], "atlas_hex": E["font_atlas_hex"], "material_hex": E["font_material_hex"],
}
ERRS = ("menu_err", "tab_err", "font_err", "font_read_err")

MUTATIONS = [
    ("M6  MENU.global 差一字节", "global = at + 13 + g_i32(get, at + 9)", "global = at + 14 + g_i32(get, at + 9)"),
    ("M7  MENU.names 差一字节", "names  = at + 45 + g_i32(get, at + 41)", "names  = at + 44 + g_i32(get, at + 41)"),
    ("M8  tab.first 读错位", "first = g_u32(get, fn + i + 3)", "first = g_u32(get, fn + i + 4)"),
    ("M9  LABEL_LOOP text 错位", "layout.text      = first + g_i32(get, fn + i + 6)", "layout.text      = first + g_i32(get, fn + i + 7)"),
    ("M10 set_label 目标错位", "layout.set_label = fn + i + 17 + g_i32(get, fn + i + 13)", "layout.set_label = fn + i + 16 + g_i32(get, fn + i + 13)"),
    ("M11 state 自检放宽", "assert(layout.state - layout.bar - first == 2012", "assert(layout.state - layout.bar - first == 2013"),
    ("M12 字体 marker 偏移错", "assert(marker(at + 0x25e) and marker(at + 0x268)", "assert(marker(at + 0x25f) and marker(at + 0x268)"),
    ("M13 FONTS material +8 丢", "return { font = font, atlas = atlas, material = material_table + 8 }", "return { font = font, atlas = atlas, material = material_table }"),
    ("M14 指针范围判据写成 0x80000000",
     "if p < 0x10000 or p >= 0x0000800000000000 then break end",
     "if p == 0 or p > 0x80000000 then break end"),
]


def vet(r):
    bad = [k for k in ERRS if k in r]
    for k, want in EXPECT.items():
        if r.get(k) != want:
            bad.append("%s=%r!=%r" % (k, r.get(k), want))
    return bad


def main():
    scan = harness.source_of("scan.lua")
    bad = vet(run())
    print('[%s] 原始解码器  %s' % ("PASS" if not bad else "FAIL", bad[:3] if bad else "全部字段一致"))
    if bad:
        return 1
    problems = 0
    for label, old, new in MUTATIONS:
        if scan.count(old) != 1:
            print("[SKIP] %s: 锚点 %d 处" % (label, scan.count(old))); problems += 1; continue
        mb = vet(run(scan.replace(old, new)))
        if mb: print("[caught] %-26s -> %s" % (label, mb[0][:64]))
        else:  print("[MISS]   %-26s 变异未被抓住" % label); problems += 1
    print("\nDECODER SUITE:", "OK" if problems == 0 else "PROBLEM x%d" % problems)
    return 0 if problems == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())