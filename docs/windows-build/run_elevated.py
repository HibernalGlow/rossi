#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
以提权方式运行一个程序，并等待其结束、返回真实退出码。

为什么需要它：
  Visual Studio 安装器（setup.exe / vs_installer.exe）在执行 modify / --quiet /
  --passive 时要求**进程从启动那一刻起就是提权状态**，否则会直接失败并写日志：
      Commands with --quiet or --passive should be run elevated from the beginning.
      Exit Code: 5007
  而 bash 无法自行提权，PowerShell 工具在部分环境下不可用。
  本脚本用 ShellExecuteExW 的 "runas" 动词触发 UAC，并用 SEE_MASK_NOCLOSEPROCESS
  拿到进程句柄，从而可以真正等待完成并读取退出码
  （注意：安装器的 --wait 参数在 4.5.x 是非法参数，会返回 exit 87）。

用法：
  python run_elevated.py "<exe 绝对路径>" "<参数整串>" [工作目录]

退出码：
  0      被调用程序自身返回 0
  非 0   被调用程序的退出码
  1223   UAC 被用户取消（ERROR_CANCELLED）
  其它    ShellExecuteExW 失败，见 stderr 的 Win32 错误号
"""

import ctypes
import sys
from ctypes import wintypes

SEE_MASK_NOCLOSEPROCESS = 0x00000040
SW_SHOWNORMAL = 1
INFINITE = 0xFFFFFFFF
ERROR_CANCELLED = 1223


class SHELLEXECUTEINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("fMask", ctypes.c_ulong),
        ("hwnd", wintypes.HWND),
        ("lpVerb", wintypes.LPCWSTR),
        ("lpFile", wintypes.LPCWSTR),
        ("lpParameters", wintypes.LPCWSTR),
        ("lpDirectory", wintypes.LPCWSTR),
        ("nShow", ctypes.c_int),
        ("hInstApp", wintypes.HINSTANCE),
        ("lpIDList", ctypes.c_void_p),
        ("lpClass", wintypes.LPCWSTR),
        ("hkeyClass", wintypes.HKEY),
        ("dwHotKey", wintypes.DWORD),
        ("hIcon", wintypes.HANDLE),
        ("hProcess", wintypes.HANDLE),
    ]


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    exe = sys.argv[1]
    params = sys.argv[2]
    workdir = sys.argv[3] if len(sys.argv) > 3 else None

    shell32 = ctypes.WinDLL("shell32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    shell32.ShellExecuteExW.argtypes = [ctypes.POINTER(SHELLEXECUTEINFO)]
    shell32.ShellExecuteExW.restype = wintypes.BOOL

    sei = SHELLEXECUTEINFO()
    sei.cbSize = ctypes.sizeof(SHELLEXECUTEINFO)
    sei.fMask = SEE_MASK_NOCLOSEPROCESS
    sei.lpVerb = "runas"          # 触发 UAC
    sei.lpFile = exe
    sei.lpParameters = params
    sei.lpDirectory = workdir
    sei.nShow = SW_SHOWNORMAL

    print(f"[run_elevated] exe    = {exe}")
    print(f"[run_elevated] params = {params}")
    print("[run_elevated] 等待 UAC 授权……", flush=True)

    if not shell32.ShellExecuteExW(ctypes.byref(sei)):
        err = ctypes.get_last_error()
        if err == ERROR_CANCELLED:
            print("[run_elevated] UAC 被取消（用户点了「否」或超时）")
            return ERROR_CANCELLED
        print(f"[run_elevated] ShellExecuteExW 失败，Win32 错误号 = {err}")
        return 1

    if not sei.hProcess:
        print("[run_elevated] 已启动，但未拿到进程句柄（无法等待）")
        return 0

    print("[run_elevated] 已提权启动，等待其结束……", flush=True)
    kernel32.WaitForSingleObject(sei.hProcess, INFINITE)
    code = wintypes.DWORD()
    kernel32.GetExitCodeProcess(sei.hProcess, ctypes.byref(code))
    kernel32.CloseHandle(sei.hProcess)
    print(f"[run_elevated] 被调用程序退出码 = {code.value}")
    return code.value


if __name__ == "__main__":
    sys.exit(main())
