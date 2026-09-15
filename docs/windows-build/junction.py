"""Windows 目录 junction (IO_REPARSE_TAG_MOUNT_POINT) 的创建 / 重设，无需管理员权限。

scoop 用 junction 维护 apps/<app>/current。本脚本用于在不依赖 PowerShell / cmd、
且不触发 os.rmdir 安全垫片（它会把空目录移入回收站，对 junction 会 WinError 5）的前提下重建它。
"""
import ctypes
import os
import sys
from ctypes import wintypes

GENERIC_WRITE = 0x40000000
FILE_SHARE_READ = 0x00000001
FILE_SHARE_WRITE = 0x00000002
FILE_SHARE_DELETE = 0x00000004
OPEN_EXISTING = 3
FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000
FSCTL_SET_REPARSE_POINT = 0x000900A4
IO_REPARSE_TAG_MOUNT_POINT = 0xA0000003
MAX_PATH = 260

# PathBuffer 必须声明为字节数组：ctypes 会把 Structure 里的 c_wchar 数组字段
# 自动转成 Python str，导致 byref() 报 "must be a ctypes instance"。
PATHBUF_BYTES = 4 * MAX_PATH * 2

k32 = ctypes.WinDLL("kernel32", use_last_error=True)

k32.CreateFileW.restype = wintypes.HANDLE
k32.CreateFileW.argtypes = [
    wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID,
    wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE,
]
k32.DeviceIoControl.argtypes = [
    wintypes.HANDLE, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
    wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID,
]
k32.CloseHandle.argtypes = [wintypes.HANDLE]
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value


class _MountPointBuffer(ctypes.Structure):
    _fields_ = [
        ("SubstituteNameOffset", wintypes.USHORT),
        ("SubstituteNameLength", wintypes.USHORT),
        ("PrintNameOffset", wintypes.USHORT),
        ("PrintNameLength", wintypes.USHORT),
        ("PathBuffer", ctypes.c_byte * PATHBUF_BYTES),
    ]


class REPARSE_DATA_BUFFER(ctypes.Structure):
    _fields_ = [
        ("ReparseTag", wintypes.ULONG),
        ("ReparseDataLength", wintypes.USHORT),
        ("Reserved", wintypes.USHORT),
        ("MountPointReparseBuffer", _MountPointBuffer),
    ]


def _apply_mount_point(link_path: str, target_path: str) -> None:
    """在已存在的目录上写入 junction 重分析点。不创建、不删除目录本身。"""
    if not os.path.isdir(target_path):
        raise NotADirectoryError(f"目标不存在: {target_path}")

    substitute = "\\??\\" + os.path.abspath(target_path)
    print_name = os.path.abspath(target_path)
    sub_b = substitute.encode("utf-16-le")
    prn_b = print_name.encode("utf-16-le")

    buf = REPARSE_DATA_BUFFER()
    buf.ReparseTag = IO_REPARSE_TAG_MOUNT_POINT
    buf.Reserved = 0
    mp = buf.MountPointReparseBuffer
    mp.SubstituteNameOffset = 0
    mp.SubstituteNameLength = len(sub_b)
    mp.PrintNameOffset = len(sub_b) + 2
    mp.PrintNameLength = len(prn_b)

    payload = sub_b + b"\x00\x00" + prn_b + b"\x00\x00"
    ctypes.memmove(ctypes.byref(mp, _MountPointBuffer.PathBuffer.offset), payload, len(payload))
    buf.ReparseDataLength = 8 + len(payload)

    handle = k32.CreateFileW(
        link_path,
        GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        None,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
        None,
    )
    if handle == INVALID_HANDLE_VALUE:
        err = ctypes.get_last_error()
        raise OSError(err, f"CreateFileW 失败: {link_path}")

    try:
        returned = wintypes.DWORD(0)
        in_size = (
            ctypes.sizeof(wintypes.ULONG)
            + 2 * ctypes.sizeof(wintypes.USHORT)
            + buf.ReparseDataLength
        )
        ok = k32.DeviceIoControl(
            handle, FSCTL_SET_REPARSE_POINT,
            ctypes.byref(buf), in_size,
            None, 0, ctypes.byref(returned), None,
        )
        if not ok:
            err = ctypes.get_last_error()
            raise OSError(err, "FSCTL_SET_REPARSE_POINT 失败")
    finally:
        k32.CloseHandle(handle)


def is_junction(path: str) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return getattr(st, "st_reparse_tag", 0) == IO_REPARSE_TAG_MOUNT_POINT


def create_junction(link_path: str, target_path: str) -> None:
    if os.path.lexists(link_path):
        raise FileExistsError(f"{link_path} 已存在，请改用 retarget")
    os.makedirs(link_path)
    try:
        _apply_mount_point(link_path, target_path)
    except Exception:
        os.rmdir(link_path)
        raise


def retarget_junction(link_path: str, target_path: str) -> None:
    """把已有 junction 重指到新目标，不删除目录。"""
    if not is_junction(link_path):
        raise ValueError(f"{link_path} 不是 junction")
    _apply_mount_point(link_path, target_path)


def describe(path: str) -> dict:
    if not os.path.lexists(path):
        return {"exists": False}
    st = os.lstat(path)
    tag = getattr(st, "st_reparse_tag", 0)
    return {
        "exists": True,
        "reparse_tag": hex(tag),
        "is_junction": tag == IO_REPARSE_TAG_MOUNT_POINT,
        "target": os.readlink(path) if tag else None,
    }


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "create":
        create_junction(sys.argv[2], sys.argv[3])
        print("已创建:", describe(sys.argv[2]))
    elif cmd == "retarget":
        retarget_junction(sys.argv[2], sys.argv[3])
        print("已重指:", describe(sys.argv[2]))
    elif cmd == "info":
        print(describe(sys.argv[2]))
    else:
        raise SystemExit(f"未知命令: {cmd}")
