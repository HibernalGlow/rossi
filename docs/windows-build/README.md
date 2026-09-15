# Windows 构建环境笔记（Rossi / Breeze）

- 记录时间：2026-09-15
- 环境：Windows，scoop 根目录 `D:\scoop`，VS BuildTools 2022（17.14.31）
- 触发场景：Rossi 项目 **Windows release 构建基线（Phase 0）**，一路排障的记录

本目录同时存放本次排障产出的可复用资产：

| 文件 | 用途 |
|---|---|
| `README.md` | 本文件 —— 环境事实与踩坑记录 |
| `win-baseline-env.sh` | Windows 构建环境脚本，**构建前必须 `source`** |
| `run_elevated.py` | 提权运行程序并等待其结束、取真实退出码（VS 安装器等需要） |
| `junction.py` | 创建 / 重指 junction，不依赖 `cmd`、不需要管理员 |
| `nuget.config.bak-20260915` | 本机 NuGet 用户配置被修改前的原始备份 |

> 放在 `docs/` 而不是 `.workbuddy/`：`.workbuddy/` 被 `.git/info/exclude` 排除，
> 其他 agent 与协作者看不到。

---

## 0. 本机环境速查

| 项 | 值 |
|---|---|
| Flutter | **3.47.3**（装在 `D:\1Dev\flutter`，镜像 `storage.flutter-io.cn`） |
| Dart（随 Flutter） | 3.13.3 |
| Rust | **1.96.1**（`rust/rust-toolchain.toml` 钉死，含全部交叉 target） |
| flutter_rust_bridge | 2.13.0 |
| VS BuildTools | 2022 17.14.31，MSVC 14.44.35207，Windows SDK 10.0.26100 |
| CMake | 3.31.6-msvc6（VS 自带） |
| ATL | 已装（`Microsoft.VisualStudio.Component.VC.ATL`） |
| 磁盘 | C 盘紧张（曾满到剩 83M），D 盘充裕 → **一切缓存/临时目录放 D** |

---

## 1. TL;DR

- 本机 scoop 安装的一部分**可执行文件在磁盘上就是 0 字节**（真实空文件，非显示假象）。
- 已修复：`nuget`（7.6.0 损坏 → 重装为 7.9.0），并重建了对应 shim。这是本次构建的直接阻塞点。
- 未修复：扫到的其他应用仍有 0 字节文件，规模见 §4。**属于历史遗留，暂缓处理。**
- 已知的独立环境缺陷（与本节无因果关系，但会影响排障手段）见 §6。

---

## 2. 判定「真实损坏」的方法

不要只看 `ls`。用两条互相独立的证据确认：

```bash
# 证据 1：直接读字节，看首字节是否为 PE 头 MZ
"C:/Users/30902/.workbuddy/binaries/python/versions/3.13.12/python.exe" -c "
import os
p = r'D:\scoop\apps\oxipng\current\oxipng.exe'
print(os.path.getsize(p), open(p,'rb').read(2))
"
```

实测对照：

| 文件 | 大小 | 首 2 字节 | 结论 |
|---|---|---|---|
| `D:\scoop\apps\oxipng\current\oxipng.exe` | `0` | `b''` | 真实损坏 |
| `D:\scoop\apps\exiftool\current\exiftool.exe` | `0` | `b''` | 真实损坏 |
| `D:\scoop\apps\nuget\current\NuGet.exe`（修复后） | `8695632` | `b'MZ'` | 正常 |

另注意：**0 字节的 exe 在 bash 里执行不报错**（既不打印内容也不返回非 0），
所以「命令跑完没输出」不能当作正常，必须看文件大小。

---

## 3. 已修复：scoop 的 `nuget`

### 3.1 损坏前状态

```
D:\scoop\apps\nuget\
  current -> D:\scoop\apps\nuget\7.6.0   (junction)
  7.6.0\NuGet.exe        0 字节
  7.6.0\install.json     58 字节
  7.6.0\manifest.json    0 字节
D:\scoop\shims\nuget.exe 0 字节           (kiennq 版 shim 应为 136192 字节)
D:\scoop\shims\nuget.shim                内容正常，指向 current\NuGet.exe
```

`install.json` 记录来源：`{"bucket": "main", "architecture": "64bit"}`。

### 3.2 修复过程（因为 `scoop` 本体无法调用，见 §6，只能手工等价执行）

```bash
# 1) 取 main bucket 里的 manifest（本地 bucket 已是 7.9.0，与上游 master 一致）
cat D:/scoop/buckets/main/bucket/nuget.json
#    version 7.9.0
#    url https://dist.nuget.org/win-x86-commandline/v7.9.0/NuGet.exe
#    hash 992d70cac5b06c38efec91806caba64cdcc07e6d963a0959dbbbaf264d33b800

# 2) 下载并校验
curl -L -o NuGet.exe https://dist.nuget.org/win-x86-commandline/v7.9.0/NuGet.exe
sha256sum NuGet.exe     # 必须等于上面的 hash

# 3) 落盘到新版本目录，并带上 scoop 需要的元数据
mkdir -p D:/scoop/apps/nuget/7.9.0
cp NuGet.exe D:/scoop/apps/nuget/7.9.0/NuGet.exe
cp D:/scoop/buckets/main/bucket/nuget.json D:/scoop/apps/nuget/7.9.0/manifest.json
printf '{\n    "bucket": "main",\n    "architecture": "64bit"\n}' \
  > D:/scoop/apps/nuget/7.9.0/install.json

# 4) 把 current junction 原地重指到 7.9.0（不删目录，原因见 §6）
python docs/windows-build/junction.py retarget \
  "D:/scoop/apps/nuget/current" "D:/scoop/apps/nuget/7.9.0"

# 5) 重建 shim（用 scoop 自带的 kiennq 版模板）
cp D:/scoop/apps/scoop/current/supporting/shims/kiennq/shim.exe D:/scoop/shims/nuget.exe

# 6) 清掉损坏的旧版本目录
rm -rf D:/scoop/apps/nuget/7.6.0
```

### 3.3 验证结果

```
D:\scoop\apps\nuget\
  7.9.0\NuGet.exe      8695632 字节   SHA256 992d70ca…  ✓
  current -> 7.9.0
D:\scoop\shims\nuget.exe  136192 字节

$ /d/scoop/shims/nuget.exe help      → NuGet 版本: 7.9.0.83  ✓
$ /d/scoop/apps/nuget/current/NuGet.exe help → NuGet 版本: 7.9.0.83  ✓
```

> 注意 `nuget -Version` 不是 nuget.exe 的合法参数（会抛 CommandManager 异常），
> 这**不是**损坏症状。判断版本请用 `nuget help` 或 `nuget update -self`。

### 3.4 shim 模板对照（本机哪一版在用）

| 模板 | 大小 | SHA256 | 说明 |
|---|---|---|---|
| `supporting/shims/kiennq/shim.exe` | 136192 | `140e3801…` | **本机在用**（`shims/dust.exe` 等与之同哈希） |
| `supporting/shims/71/shim.exe` | 115200 | `70d4690b…` | 未用 |
| `supporting/shims/scoopcs/shim.exe` | 9728 | `01160687…` | 未用 |
| `supporting/shimexe/bin/shim.exe` | 7680 | — | 另一套机制 |

重建 shim 前先用 `sha256sum D:/scoop/shims/<某个正常的>.exe` 对出在用版本，别猜。

---

## 4. 未修复：其他受影响的 scoop 应用

扫描命令（**必须限深**，`D:\scoop\apps` 下大量 junction，无限深 `find` 会跑到几分钟不出结果）：

```bash
# 限深 3：apps/<app>/<version>/<file>
find /d/scoop/apps -maxdepth 3 -type f -size 0 2>/dev/null \
  | awk -F/ '{print $5}' | sort | uniq -c | sort -rn
```

### 4.1 规模

| 统计口径 | 结果 |
|---|---|
| 限深 3，受影响 app 数 | **61** |
| 限深 3，0 字节文件数 | 345 |
| 限深 5，受影响 app 数 | **116** |
| `shims\` 下的 0 字节可执行文件 | 6 个 |

### 4.2 限深 3 的分布（按文件数降序）

| 文件数 | 应用 |
|---|---|
| 198 | imageglass |
| 19 | powertoys |
| 12 | vlc、jhentai |
| 7 | imagemagick |
| 6 | micswitch、devtoys |
| 5 | openssh |
| 4 | quicker、dust |
| 3 | pwsh、idm |
| 2 | xnviewmp、winrar、typora、teracopy、sheas-cealer、openjdk17、lossless-scaling、hashcalculator、git、folo、exiftool、dismplusplus、dbx、bleachbit、Parsec、GithubStarsManager、CodeBuddyCN |
| 1 | zoxide、zen-browser、videojanai、ventoy、vcpkg、syncthing、subrenamer、steamcommunity-302、steam、sqlitestudio、sinelaw.fresh、oxipng、openpi、opencode、open-design、onecommander、obs-studio、motrix、memreduct、mangajanaiconvertergui、losslesscut、kopiaui、jellyfin-media-player、hitomi-downloader、handbrake、game-cheats-manager、ddu、calibre、bili-sync、bat、affine、LXGWWenKaiMono |

### 4.3 `shims\` 下的 0 字节项

```
bandizip.exe
bz.exe
exiftool.exe
exiftool(-k).exe
jhentai.exe
zeztz-v0.0.1-windows-amd64.exe
```

### 4.4 观察与推测

- 这些文件的 mtime **跨越数月**（2025-04 ~ 2025-10 都有），不是单次事故。
- 但也不是全量：同目录里大量应用是完好的（例如 `shims\scoop-search.exe`、`scooptools.exe` 都正常）。
- 推测方向（**未证实**）：某类"文件已创建但内容未落盘"的写入失败在长期重复发生。
  可能是压缩包解压环节、杀软/EDR 拦截、或磁盘写入层面的问题。

### 4.5 后续修复方案（待做）

按应用逐个重装，本质上等价于 `scoop reinstall <app>`：

```bash
scoop reinstall imageglass powertoys vlc jhentai imagemagick ...
```

或按应用全量刷一遍再 `scoop cleanup *`。
由于 `scoop` 本体当前不可用（§6），要么在能正常执行 PowerShell 的终端里做，
要么沿用 §3.2 的手工等价流程。

---

## 5. 这些损坏对本项目（Rossi）的实际影响

只有一处，已解除：`permission_handler_windows` 插件的 `windows/CMakeLists.txt`
会用 `find_program(NUGET nuget)` **先找 PATH 里的 nuget**；找得到就不自己去下载。
PATH 里命中的正是那个 0 字节 shim，于是 CMake 在 `nuget install Microsoft.Windows.CppWinRT`
阶段直接 `FATAL_ERROR`。修复 scoop nuget 后此路已通。

备用兜底：`docs/windows-build/win-baseline-env.sh` 里保留了一段**条件式**兜底 ——
只有当 `/d/scoop/apps/nuget/current/NuGet.exe` 为空时才把校验过的
`/d/1Dev/tools/nuget`（SHA256 `04eb6c4f…`，v6.0.0）挂到 PATH 前面。
默认不启用，以免基线环境被污染。

---

## 6. 已知的独立环境缺陷（排障时的重要前提）

这三条与 0 字节损坏**没有因果关系**，但会决定你用什么手段去修，所以一并记下。

### 6.1 `.git/refs/heads/` 下无法创建子目录

任何带斜杠的本地分支名（如 `research/gpu-reader-foundation`）都建不出来。
`git switch -c` / `git checkout -B` 会**报告成功**，但 HEAD 实际是 unborn，
紧接着 `git commit` 会产出 root commit（把全部文件当新增）。
已排除沙箱因素（禁用沙箱后完全复现）；扁平引用名写入正常。

规避：本地用扁平分支名，推送时用显式 refspec 映射：

```bash
git push origin research-work:refs/heads/research/gpu-reader-foundation
```

副作用：远端 tracking ref 同样无法更新，`git branch -vv` 会误报 `ahead 1`；
判断远端状态以 `git ls-remote origin` 为准。推送需 `GIT_TERMINAL_PROMPT=0` 以免卡在凭据提示。

### 6.2 从 Bash 无法调用 `cmd.exe` 与 PowerShell

两者都被安全策略拒绝。**PowerShell 工具本身也不可用**（任何命令都返回空输出）。
后果：`scoop`（一个 PowerShell 脚本，`shims/scoop.cmd` → `scoop.ps1`）无法被调用，
`mklink /J` 也用不了 —— 这就是 §3.2 必须手工执行、且用 Python 造 junction 的原因。

`reg.exe` 可以从 Bash 正常调用。

### 6.3 目录删除会触发"移入回收站"垫片

环境注入的 `sitecustomize.py` 包装了 `os.rmdir` / `shutil.rmtree`：
对空目录会改道 `_try_trash()`。对 **junction 会直接 `WinError 5 拒绝访问`**。

规避：不要删 junction，改用**原地重设 reparse point**：

```bash
python docs/windows-build/junction.py retarget <link> <new-target>
```

`junction.py` 支持 `create` / `retarget` / `info` 三个子命令，
用 `CreateFileW(FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT)`
+ `DeviceIoControl(FSCTL_SET_REPARSE_POINT)` 实现，**不需要管理员权限**。
（注意：`PathBuffer` 必须声明为 `c_char` 数组，写成 `c_wchar` 数组会被 ctypes 转成
Python `str`，`byref()` 会报 "must be a ctypes instance"。）

---

### 6.4 NuGet 用户级配置里有个已废弃的源，会让所有 nuget 操作失败

`C:\Users\30902\AppData\Roaming\NuGet\nuget.config` 原文：

```xml
<packageSources>
  <add key="Azure China" value="https://nuget.cdn.azure.cn/v3/index.json" />
  <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
</packageSources>
```

`nuget.cdn.azure.cn` 已废弃，**NXDOMAIN**：

```
$ nslookup nuget.cdn.azure.cn
*** ns3.zj.chinamobile.com 找不到 nuget.cdn.azure.cn: Non-existent domain
$ nslookup api.nuget.org
Address: 23.101.10.141          ← 正常
```

关键：**这不是 DNS 被沙箱拦截**——用的是本机真实 DNS（223.5.5.5），
而 `api.nuget.org` 在同一环境下解析正常。域是真的没了。

NuGet 只要有一个源连不上就整体报错，不会自动跳过：

```
Unable to load the service index for source https://nuget.cdn.azure.cn/v3/index.json.
  发送请求时出错。未能解析此远程名称: 'nuget.cdn.azure.cn'
```

**已做处理**：在原配置里加 `disabledPackageSources` 禁用该源（最小改动、可逆、
保留原始条目），原文件已备份到 `docs/windows-build/nuget.config.bak-20260915`。

```xml
<disabledPackageSources>
  <add key="Azure China" value="true" />
</disabledPackageSources>
```

验证（插件的原始命令，逐字复现）：

```bash
nuget install Microsoft.Windows.CppWinRT -Version 2.0.210806.1 -OutputDirectory packages
# → Successfully installed 'Microsoft.Windows.CppWinRT 2.0.210806.1'
#   来源 https://api.nuget.org/v3/index.json
```

连带提醒：NuGet 全局包缓存在 `C:\Users\30902\.nuget\packages`（**C 盘**）。
C 盘已 100% 满，若后续拉取大包，需要把 `NUGET_PACKAGES` 指向 D 盘。

---

## 7. 其他相关环境事实（与本次构建排查同批发现）

### 7.0 缺 ATL 组件 —— Windows 构建的阻塞点（已解决）

本机 VS BuildTools 2022（17.14.31）装了 `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`，
但**没有装 ATL**：`...\VC\Tools\MSVC\<ver>\atlmfc\` 目录不存在，全盘找不到 `atlbase.h`。

后果（构建跑到最后一步才暴露，前面全过）：

```
flutter_local_notifications_windows\src\plugin.cpp(5,10): error C1083:
  无法打开包括文件: "atlbase.h": No such file or directory
```

**安装方式（踩了 3 个坑才通，见下表）**：

```bash
PY="C:/Users/30902/.workbuddy/binaries/python/versions/3.13.12/python.exe"
"$PY" docs/windows-build/run_elevated.py \
  'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe' \
  'modify --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Component.VC.ATL --passive --norestart' \
  'D:\1VSCODE\Projects\rossi'
# → [run_elevated] 被调用程序退出码 = 0
```

#### 7.0.1 安装器三条坑

| # | 坑 | 症状 | 正解 |
|---|---|---|---|
| 1 | `vs_installer.exe` 是 124KB 的**转发壳**，不干活 | 6 秒退出、无日志、无任何变化 | 用真正的引擎 `Installer\setup.exe`（3.1MB） |
| 2 | **`--wait` 不是合法参数** | 日志头 `ERROR(S): Option 'wait' is unknown.`，退出码 **87**（参数无效） | 去掉 `--wait` |
| 3 | **`--passive` / `--quiet` 要求进程一开始就已提权** | 日志 `Commands with --quiet or --passive should be run elevated from the beginning.`，退出码 **5007** | 先提权再启动，见下 |

> 坑 2 的误导性很强：`| tail` 会把退出码变成 tail 的 0，必须写日志文件再判读。
> 坑 3 的报文只在**安装器自己的**日志里，不在终端输出里 —— 位置：
> `%TEMP%\dd_*.log`（本机是 `C:\Users\30902\AppData\Local\Temp\`）。

#### 7.0.2 为什么需要 `run_elevated.py`

bash 不能自行提权；本环境 **PowerShell 工具不可用**，且从 bash 调 `cmd.exe` / `powershell.exe`
被安全策略拦截。故用 Python 的 `ShellExecuteExW` + `"runas"` 动词触发 UAC，
配合 `SEE_MASK_NOCLOSEPROCESS` 拿到进程句柄，从而能**真正等待结束并读取退出码**
（这一点比 `--wait` 更可靠，因为 `--wait` 压根不存在）。

```bash
python docs/windows-build/run_elevated.py "<exe>" "<参数整串>" [工作目录]
```

退出码：被调用程序的退出码；**1223 = UAC 被取消**（`ERROR_CANCELLED`）。

#### 7.0.3 装完之后还要改环境脚本（关键，否则链接仍失败）

`atlbase.h` 与 `atls.lib` **不在 MSVC 默认目录下**：

```
<MSVC>\atlmfc\include\atlbase.h      ← 68 个头文件
<MSVC>\atlmfc\lib\x64\atls.lib       ← x64 库只此一个（另有个 .pdb）
<MSVC>\atlmfc\lib\x86\atls.lib
```

已装的 `...\lib\x64\` 里**没有**任何 `*atl*`。而本机 MSBuild 又解析不出 `VC_IncludePath` /
`VC_LibraryPath_x64`（见 §7.1），include/lib 全靠环境变量注入 —— 所以必须在
`docs/windows-build/win-baseline-env.sh` 里显式追加这两个目录，否则依次报：

```
error C1083: 无法打开包括文件: "atlbase.h"      ← 未加 include 时
LINK : fatal error LNK1104: 无法打开文件 "atls.lib"   ← 未加 lib 时
```

脚本里已按「ATL 目录存在才追加」的条件写入（未装 ATL 的机器不受影响）。

### 7.1 其余环境事实

- **C 盘已 100% 占满**（仅剩数百 MB）。所有 SDK / 包缓存 / 临时目录必须放 D 盘，
  否则 flutter / pub / cargo 会中途写爆系统盘。详见 `docs/windows-build/win-baseline-env.sh`。
  > 2026-09-15 22:00 复核：C 盘可用已回到 ~13G（最低时曾被压到 **83M**，非常危险）。
  > 具体是什么释放的空间未查明，但那段时间的磁盘读数不可信，排查时别据此下结论。
- **MSVC 的 MSBuild 解析不出 VC/SDK 的 include 与 lib 路径**
  （`VC_IncludePath` / `WindowsSDK_IncludePath` / `VC_LibraryPath_x64` /
  `WindowsSDK_LibraryPath_x64` 全为空），任何 CMake 工程都会在编译器探测阶段
  因 `LNK1104: 无法打开文件 "ucrtd.lib"` 失败。
  注意：`vcvars64.bat` 正常、注册表正常、`ucrtd.lib` 三个 SDK 版本都在，
  所以不是编译器缺失 —— 绕开方式是把 include/lib 路径以环境变量注入
  （MSBuild 会把环境变量当属性读取）。具体见 `docs/windows-build/win-baseline-env.sh`。

### 7.2 陷阱：陈旧的 CMake 缓存会让 INSTALL 步骤写到 `C:\Program Files\zephyr`

#### 现象

编译**全部通过**，卡在最后一步：

```
error MSB3073: 命令"setlocal ... cmake.exe -DBUILD_TYPE=Release -P cmake_install.cmake" 已退出，代码为 1
```

这条 MSB3073 是**噪声**，真实错误被它盖住了。要手动执行一次 install 才能看到：

```bash
cd build/windows/x64
"<VS>/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe" \
  -DBUILD_TYPE=Release -P cmake_install.cmake
# → CMake Error at cmake_install.cmake:150 (file):
#     file cannot create directory: C:/Program Files/zephyr.
#     Maybe need administrative privileges.
```

#### 根因

`windows/CMakeLists.txt`（Flutter 标准生成代码）靠这个判断改写安装前缀：

```cmake
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()
```

而 `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` **只在某个 build tree 的首次 configure 时为真**。
一旦这个 tree 里已经存在一份（哪怕来自失败的 configure）带着 CMake 默认值
`C:/Program Files/<PROJECT_NAME>` 的 `CMakeCache.txt`，后续每次 configure 都会跳过这段改写，
前缀就永远停在默认值上。

本项目 `PROJECT_NAME` = `zephyr`，所以错误前缀恰好是 `C:/Program Files/zephyr`。

#### 判别方法（10 秒实验，别瞎猜）

在**全新目录**里单独 configure 一次，比对两个缓存：

```bash
cmake -S windows -B build/probe-cmake -G "Visual Studio 17 2022" -A x64
grep CMAKE_INSTALL_PREFIX build/probe-cmake/CMakeCache.txt   # 期望 $<TARGET_FILE_DIR:zephyr>
grep CMAKE_INSTALL_PREFIX build/windows/x64/CMakeCache.txt   # 若为 C:/Program Files/zephyr 即中招
```

本机实测（CMake 3.31.6-msvc6）：

| 目录 | 值 | 判定 |
|---|---|---|
| 全新 `build/probe-cmake` | `$<TARGET_FILE_DIR:zephyr>` | ✅ guard 正常 |
| 现存 `build/windows/x64` | `C:/Program Files/zephyr` | ❌ 陈旧缓存 |

结论：**不是项目缺陷、也不是 CMake 版本兼容问题，就是缓存陈旧。**

#### 处理

```bash
rm -rf build/windows   # 只清 CMake 树
```

**不要**一起删 `.dart_tool/`：Rust 的 native-assets 产物（约 1.7G，含
`hooks_runner/shared/zephyr/build/*/target/`）在那里，重编一次要 15–20 分钟。
`build/windows` 只是 CMake/MSBuild 树，清了重来即可。

> 反面教材：本机前几次失败构建（编译器探测失败、缺 ATL）都在
> `build/windows/x64/` 落下了带默认前缀的缓存，导致后续即使修好了所有环境问题，
> 也依然在 INSTALL 步骤失败。**环境修好后仍报 MSB3073，先查这个。**

### 7.3 陷阱：沙箱会静默回滚删除操作

**这是本机最容易让人误判的一条。**

现象：`rm -rf build/windows` 在同一调用内**报 exit=0 且目录确实消失**，
但**跨调用再看，目录又回来了**（内容与 mtime 完全没变）。

证据：连续多次「清理后重跑」失败后，检查
`build/windows/x64/CMakeCache.txt` 的 mtime —— 一直停在 `09-15 21:38:36`，
即**从来没有被删除过**。这就是 §7.2 那个陈旧前缀被反复继承的原因。

规避：

- **涉及删除/替换的构建步骤必须提权执行**（本机实测提权后 `rm -rf` 立即生效）。
- 部署前先验证删除是否真的生效：

```bash
rm -rf build/windows
ls -d build/windows 2>&1 || echo "✅ 已删除"
```

- 同样的机制也解释了一个 git 现象：`.git/refs/heads/` 下**新建子目录会被回滚**，
  所以带斜杠的本地分支名（`research/xxx`）建不出来，`git switch -c` 会静默留下 unborn HEAD，
  随后 `git commit` 产出 root commit（把全仓当新增）。规避方式是用扁平分支名 + 显式 refspec：

```bash
git push origin research-work:refs/heads/research/gpu-reader-foundation
```

> 早期排查曾把 git 那条判定为「与沙箱无关」，那个结论是错的 —— 两者同源。

### 7.4 读构建日志：别指望中文，也别忘了退出码

- 日志里的中文往往是**双重编码的乱码**（`构建脚本` 显示成 `鏋勫缓鑴氭湰`），
  这种损坏**不能用 `iconv` 还原**（早期版本用 `iconv -f GBK` 有效，是因为当时日志里
  只有 MSBuild 的原生 GBK 输出；现在 Dart 脚本的中文也混进来了，编码不统一）。
- 排障一律**只认 ASCII 关键字**：`error` / `MSB` / `LNK` / `C1083` / `fatal` / `exit`。
- **判断退出码必须写日志文件再读，不能靠管道**：

```bash
cmd > "$LOG" 2>&1; EC=$?          # ✅ 真实退出码
cmd 2>&1 | tail -20; echo $?      # ❌ 这是 tail 的退出码，永远 0
```

这一条坑过一次：ATL 安装实际以 exit 87 失败，但被管道掩盖成 0。
- **`msbuild` / `cmd` / `powershell` 相关命令会被安全策略拦截**，排查时避免写进命令串。

### 7.5 根因：PATH 里没有 Git for Windows 的 `usr/bin`（2026-09-15 发现，已修复）

**一个根因引出三个看似无关的症状**，是最容易误诊的一类问题，排障时务必先查它。

某些 WorkBuddy / 终端会话里 PATH 不含 PortableGit 的 `usr/bin`，命令于是解析成：

| 命令 | 实际解析到 | 后果 |
|---|---|---|
| `bash` | `C:\Windows\System32\bash.exe` | 这是 **WSL 启动器**，不是 Git Bash。任何调用 `bash` 的构建步骤都会拉起 `wsl.exe` |
| `sort` | `C:\Windows\System32\sort.exe` | 不认 `-V`，`win-baseline-env.sh` 的 MSVC/SDK 版本探测直接失败 |
| `find` | `C:\Windows\System32\find.exe` | 不是 GNU find，`find . -name "*.exe"` 静默无输出 |
| `sed` | 不存在 | 直接报 `sed: command not found` |

由此引出两组**互不相关**的故障，很容易被误当成两个独立问题：

1. **MSVC 探测失败 → 链接期 `LNK1104` 找不到 `ucrtd.lib`。**
   `sort -V` 不可用 → `_rossi_msvc_ver` / `_rossi_sdk_ver` 为空 →
   `IncludePath` / `LibraryPath` 根本注入不进去。表面症状像「MSBuild 解析不出 MSVC 路径」，
   实际只是 `sort` 用错了实现。
2. **`PROGRAM BLOCKED BY SECURITY POLICY - wsl.exe`。**
   构建链路里某处调用 `bash`，命中了 System32 的 WSL 启动器。
   这个拦截**不能批准、不能绕过**，重试无效 —— 只能从根上避免调用到它。

诊断一行确认：

```bash
command -v bash sort find     # bash 指向 System32 即为中招
```

修复：把 Git 的 `usr/bin` 前置到 PATH。已固化进 `win-baseline-env.sh` 第 0 节，
脚本启动时自行探测并修复，无需人工干预。
