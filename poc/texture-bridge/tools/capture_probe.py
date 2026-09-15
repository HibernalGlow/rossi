"""截取 texture_bridge 窗口，采样关键像素，用来客观验证 BGRA 通道顺序。

为什么需要它：
    原生侧的 handleOpened 计数只能证明「引擎把 shared handle 打开并拿去合成了」，
    不能证明「通道顺序正确」。如果 BGRA 被当成 RGBA 解释，画面上的红蓝会互换，
    但 handle 照样会被正常打开，计数一样增长。只有读真实像素才能区分。

判据（与 gpu_texture_poc.cpp 里的渲染内容对应）：
    texture 顶部三分之一被画成 红 | 绿 | 蓝 三条竖带。
    屏幕上从左到右读到 红/绿/蓝  => 通道正确。
    读到 蓝/绿/红                => BGRA 被当 RGBA，需要翻转。

用法：
    python capture_probe.py [标题子串] [输出png]
"""

import ctypes
import struct
import sys
import time
import zlib
from ctypes import wintypes

user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)

# 必须显式声明句柄相关的 restype：默认 c_int 会在 64 位下截断 HDC 句柄。
user32.GetDC.restype = wintypes.HDC
user32.GetDC.argtypes = [wintypes.HWND]
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
gdi32.CreateCompatibleDC.restype = wintypes.HDC
gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
gdi32.SelectObject.restype = wintypes.HGDIOBJ
gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
gdi32.BitBlt.argtypes = [
    wintypes.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    wintypes.HDC, ctypes.c_int, ctypes.c_int, wintypes.DWORD,
]
gdi32.GetDIBits.argtypes = [
    wintypes.HDC, wintypes.HBITMAP, wintypes.UINT, wintypes.UINT,
    ctypes.c_void_p, ctypes.c_void_p, wintypes.UINT,
]
gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wintypes.HDC]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wintypes.DWORD * 3)]


def find_window(substr):
    hits = []
    proc_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd, _lparam):
        length = user32.GetWindowTextLengthW(hwnd)
        if length > 0 and user32.IsWindowVisible(hwnd):
            buf = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buf, length + 1)
            if substr.lower() in buf.value.lower():
                hits.append((hwnd, buf.value))
        return True

    user32.EnumWindows(proc_type(callback), 0)
    return hits


def capture_client(hwnd):
    """返回 (width, height, rows)，rows 是 top-down 的 RGB 字节串列表。"""
    user32.ShowWindow(hwnd, 9)  # SW_RESTORE
    user32.SetForegroundWindow(hwnd)
    time.sleep(1.5)

    origin = wintypes.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(origin))
    client = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(client))
    width, height = client.right, client.bottom

    screen_dc = user32.GetDC(0)
    mem_dc = gdi32.CreateCompatibleDC(screen_dc)
    bitmap = gdi32.CreateCompatibleBitmap(screen_dc, width, height)
    gdi32.SelectObject(mem_dc, bitmap)
    gdi32.BitBlt(mem_dc, 0, 0, width, height, screen_dc, origin.x, origin.y, 0x00CC0020)

    info = BITMAPINFO()
    info.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    info.bmiHeader.biWidth = width
    info.bmiHeader.biHeight = -height  # 负值 = top-down
    info.bmiHeader.biPlanes = 1
    info.bmiHeader.biBitCount = 32
    info.bmiHeader.biCompression = 0  # BI_RGB

    buffer = ctypes.create_string_buffer(width * height * 4)
    gdi32.GetDIBits(mem_dc, bitmap, 0, height, buffer, ctypes.byref(info), 0)
    raw = buffer.raw

    rows = []
    for y in range(height):
        row = bytearray(width * 3)
        base = y * width * 4
        for x in range(width):
            i = base + x * 4
            # DIB 是 BGRA 排列
            row[x * 3 + 0] = raw[i + 2]
            row[x * 3 + 1] = raw[i + 1]
            row[x * 3 + 2] = raw[i + 0]
        rows.append(bytes(row))

    gdi32.DeleteObject(bitmap)
    gdi32.DeleteDC(mem_dc)
    user32.ReleaseDC(0, screen_dc)
    return width, height, rows


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def classify(rgb):
    r, g, b = rgb
    if r > 150 and g < 90 and b < 90:
        return "红"
    if g > 150 and r < 90 and b < 90:
        return "绿"
    if b > 150 and r < 90 and g < 90:
        return "蓝"
    if r < 40 and g < 40 and b < 40:
        return "近黑"
    if r > 215 and g > 215 and b > 215:
        return "近白"
    return "其他"


def main_argv(title="texture_bridge", out_png="poc-capture.png"):
    """可编程入口，供 run_probe.py 直接调用，避免再走一遍 sys.argv。"""
    # 不设为 DPI aware 的话，GetClientRect 会拿到被缩放过的虚拟坐标，
    # 截屏采样点就会整体错位。
    try:
        user32.SetProcessDPIAware()
    except Exception:
        pass

    hits = find_window(title)
    if not hits:
        print("FAIL 未找到标题包含 %r 的可见窗口" % title)
        print("     应用可能启动失败，或窗口尚未创建完成")
        return 2

    hwnd, real_title = hits[0]
    print("窗口: %r  hwnd=0x%X" % (real_title, hwnd))

    width, height, rows = capture_client(hwnd)
    print("客户区: %d x %d" % (width, height))

    # 顶部三分之一是红/绿/蓝三条竖带。取 y 落在该区域内，
    # x 取三条带各自的中心。
    probe_y = max(4, height // 12)
    samples = [
        ("左带(应为红)", width // 6),
        ("中带(应为绿)", width // 2),
        ("右带(应为蓝)", (width * 5) // 6),
    ]

    print("采样行 y=%d" % probe_y)
    observed = []
    for label, x in samples:
        row = rows[probe_y]
        rgb = (row[x * 3], row[x * 3 + 1], row[x * 3 + 2])
        observed.append(classify(rgb))
        print("  %-14s x=%-5d RGB=%s  -> %s" % (label, x, rgb, classify(rgb)))

    # 整行判空：三条带全黑说明根本没渲染出内容。
    non_black = 0
    row = rows[probe_y]
    for x in range(0, width, 7):
        if row[x * 3] + row[x * 3 + 1] + row[x * 3 + 2] > 60:
            non_black += 1
    print("该行非黑采样点: %d / %d" % (non_black, len(range(0, width, 7))))

    write_png(out_png, width, height, rows)
    print("截图已保存: %s" % out_png)

    print("")
    if observed == ["红", "绿", "蓝"]:
        print("PASS 通道顺序正确：左红 / 中绿 / 右蓝")
        return 0
    if observed == ["蓝", "绿", "红"]:
        print("FAIL 红蓝互换 —— BGRA 被当作 RGBA 解释，需要翻转通道")
        return 1
    print("WARN 未观察到预期的三色带，实际: %s" % observed)
    print("     若全为近黑 => 通道没通；若为其他 => 画面被遮挡或尺寸不匹配")
    return 3


def main():
    title = sys.argv[1] if len(sys.argv) > 1 else "texture_bridge"
    out_png = sys.argv[2] if len(sys.argv) > 2 else "poc-capture.png"
    return main_argv(title, out_png)


if __name__ == "__main__":
    sys.exit(main())
