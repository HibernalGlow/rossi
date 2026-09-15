"""只读诊断：拆解一个 CBZ 的条目构成、压缩方式、磁盘 vs 解压耗时、图像格式与像素量。

用途是把「翻页慢」在**磁盘 / inflate / 解码**三者之间归因，而不是靠猜：

- 条目表与压缩方式分布 → 判断 deflate 是否真有活干（已压缩的 JPEG 通常是 `comp ≈ raw`）。
- 「冷读」与「纯磁盘顺序读」分开计时 → 磁盘慢还是 inflate 慢，一次分开。
- 嗅探图像格式与像素量 → 解码成本基本由 MPix 决定（见 `docs/v0.1-local-core.md` §12）。

```bash
python poc/local-samples/inspect_cbz.py "E:/path/to/book.cbz"
python poc/local-samples/inspect_cbz.py "E:/dir/*.cbz"        # 支持通配
```

**不改动任何被检查的文件。**
"""

from __future__ import annotations

import glob
import os
import struct
import sys
import time
import zipfile

MAGIC = {
    b"\xff\xd8\xff": "JPEG",
    b"\x89PNG\r\n\x1a\n": "PNG",
    b"GIF8": "GIF",
    b"BM": "BMP",
}


def sniff_format(data: bytes) -> str:
    for magic, name in MAGIC.items():
        if data.startswith(magic):
            return name
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "WebP"
    return "未知"


def jpeg_size(data: bytes) -> tuple[int, int] | None:
    i = 2
    n = len(data)
    while i + 9 < n:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        seg_len = struct.unpack(">H", data[i + 2 : i + 4])[0]
        # SOF0..SOF3, SOF5..SOF7, SOF9..SOF11, SOF13..SOF15
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            # 段内顺序：precision(1) → height(2) → width(2)
            height, width = struct.unpack(">HH", data[i + 5 : i + 9])
            return width, height
        i += 2 + seg_len
    return None


def png_size(data: bytes) -> tuple[int, int] | None:
    if len(data) >= 24 and data[12:16] == b"IHDR":
        w, h = struct.unpack(">II", data[16:24])
        return w, h
    return None


def webp_size(data: bytes) -> tuple[int, int] | None:
    if len(data) < 30:
        return None
    fourcc = data[12:16]
    if fourcc == b"VP8X":
        w = int.from_bytes(data[24:27], "little") + 1
        h = int.from_bytes(data[27:30], "little") + 1
        return w, h
    if fourcc == b"VP8L":
        bits = int.from_bytes(data[21:25], "little")
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if fourcc == b"VP8 ":
        # 关键帧起始码 9D 01 2A 之后是宽高
        if data[23:26] == b"\x9d\x01\x2a":
            w = struct.unpack("<H", data[26:28])[0] & 0x3FFF
            h = struct.unpack("<H", data[28:30])[0] & 0x3FFF
            return w, h
    return None


def dimensions(fmt: str, data: bytes) -> tuple[int, int] | None:
    if fmt == "JPEG":
        return jpeg_size(data)
    if fmt == "PNG":
        return png_size(data)
    if fmt == "WebP":
        return webp_size(data)
    return None


def ms(t0: float) -> float:
    return (time.perf_counter() - t0) * 1000.0


def main() -> int:
    pattern = sys.argv[1] if len(sys.argv) > 1 else "*.cbz"
    found = glob.glob(pattern)
    if not found:
        print(f"未找到匹配 {pattern} 的文件")
        return 1

    for path in found:
        print("=" * 78)
        print("文件:", path)
        print("大小: %.1f MB" % (os.path.getsize(path) / 1e6))

        with zipfile.ZipFile(path) as zf:
            infos = zf.infolist()
            print("条目数:", len(infos))

            methods: dict[int, int] = {}
            for info in infos:
                methods[info.compress_type] = methods.get(info.compress_type, 0) + 1
            label = {0: "STORED(未压缩)", 8: "DEFLATE", 12: "BZIP2", 14: "LZMA"}
            print("压缩方式分布:", {label.get(k, k): v for k, v in methods.items()})

            print("\n--- 前 12 条 ---")
            for info in infos[:12]:
                # 嗅探头部要留够余量：相机原片的 APP1/EXIF 段可达几十 KB，
                # 只读 4 KB 会走不到 SOF 标记，尺寸就成 "?"。
                with zf.open(info) as fh:
                    head = fh.read(256 * 1024) if info.file_size > 0 else b""
                fmt = sniff_format(head)
                dim = dimensions(fmt, head)
                dim_s = f"{dim[0]}x{dim[1]}" if dim else "?"
                mpx = f"{dim[0] * dim[1] / 1e6:.1f} MPix" if dim else ""
                print(
                    f"  {info.filename[:46]:<46} "
                    f"raw={info.file_size / 1e6:6.2f}MB comp={info.compress_size / 1e6:6.2f}MB "
                    f"{fmt:<5} {dim_s:<11} {mpx}"
                )

            # 一条 2 MB 以上的条目，做冷/热读与纯磁盘读对照
            big = [i for i in infos if i.file_size > 2_000_000] or infos[:1]
            info = big[0]
            print(f"\n--- 计时（条目: {info.filename}） ---")

            t0 = time.perf_counter()
            data = zf.read(info.filename)
            cold = ms(t0)

            t0 = time.perf_counter()
            zf.read(info.filename)
            warm = ms(t0)

            with open(path, "rb") as raw:
                t0 = time.perf_counter()
                raw.seek(info.header_offset)
                chunk = raw.read(info.compress_size)
                disk = ms(t0)

            print(f"  冷读（含 inflate + CRC）  : {cold:7.2f} ms")
            print(f"  热读（同进程再读一次）    : {warm:7.2f} ms")
            print(
                f"  纯磁盘顺序读 {len(chunk) / 1e6:.2f} MB: {disk:7.2f} ms "
                f"→ {len(chunk) / 1e6 / max(disk, 1e-6) * 1000:.0f} MB/s"
            )
            delta = cold - disk
            print(
                "  推断：磁盘占 %.0f%%，inflate/解析占 %.0f%%"
                % (100 * disk / max(cold, 1e-6), 100 * max(delta, 0) / max(cold, 1e-6))
            )
            print("  提示：纯磁盘读若远快于冷读，说明瓶颈在 inflate 而非磁盘。")

            fmt = sniff_format(data)
            dim = dimensions(fmt, data)
            if dim:
                w, h = dim
                print(
                    f"  格式 {fmt}  {w}x{h}  {w * h / 1e6:.1f} MPix  "
                    f"→ RGBA 位图 {w * h * 4 / 1e6:.1f} MB"
                )
            else:
                print(f"  格式 {fmt}（未能解析尺寸）")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
