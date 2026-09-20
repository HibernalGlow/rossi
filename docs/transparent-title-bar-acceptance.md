# 「透明标题栏」两个开关的实机验收判据

对应改动：

- **桌面外壳标题栏**：`GlobalSettingState.transparentDesktopTitleBar`（默认**关**）
  + `transparentTitleBarFused`（摆放方式，默认 **false = 独立行**）
  → `DesktopShellFrame` 的三种摆放（`resolveDesktopTitleBarPlacement`）
  + `CustomTitleBar.transparent`。入口在 **设置 → 外观 → 透明标题栏**（仅桌面三平台），
  开关打开后下面出现摆放选择：**独立行（默认）/ 融合浮层**。
- **阅读器顶栏**：`ReadSettingState.transparentTopBar`（默认**关**）+ `topBarScrimOpacityPercent`
  （默认 **85**）→ `resolveReaderTopBarSpec`。入口在 **阅读器设置 → 阅读体验 → 透明顶栏**。

参考实现是 JHenTai：桌面端自制标题栏本身是「独立行」形态（`titleBarStyle: TitleBarStyle.hidden`
+ 自绘栏）；「融合浮层」对应它阅读页菜单浮在画面上的形态。
阅读页透明蒙层是 `readPageMenuColor = Colors.black.withValues(alpha: 0.85)`。

**两个开关的默认档都是「改造前的样子」**，所以「没开过设置页的用户行为不变」是这一轮的第一条红线。

## 已经自动验到的（不必手测）

| 判据 | 覆盖 |
|---|---|
| `flutter test test/desktop/desktop_shell_frame_test.dart` | 摆放判定真值表四种组合 / 透明档下内容顶到 y=0（不是「藏了但留占位」）/ 透明档下标题栏那一层**不画底色** / 关着时底色照旧（成对）/ 透明档 + 全屏整条不建 |
| `flutter test test/comic_read/reader_top_bar_style_test.dart` | 默认档仍是「玻璃 + 收小的阴影」/ 透明档换蒙层且拿掉阴影 / 蒙层由主题 `surface` 算出（深浅两套主题算出两种）/ 0% 与越界值两端钳制 / 关掉后蒙层整个撤掉 |
| `flutter test test/network/sync/settings_sync_block_test.dart` | 桌面端那一键进 `shell` 块并能往返 |

```
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  /opt/homebrew/Caskroom/flutter/3.47.4/flutter/bin/flutter test \
  test/desktop/desktop_shell_frame_test.dart \
  test/comic_read/reader_top_bar_style_test.dart
```

（本机 `flutter test` 有一批 `libobjectbox.dylib` 的基线红，与本次改动无交集。）

## A. 桌面外壳（macOS / Windows / Linux）

- [ ] **D1 默认档零回归**：不带任何设置启动 ⇒ 顶上仍是那条 40px 的实色栏，
      内容从它下面开始（与改动前逐像素一致）。
- [ ] **D2 打开开关**：那一条栏**不再占位** —— 窗口最上面一条带里直接是应用内容
      （工作台 / 阅读页 / 书架都试一遍），应用名与窗口按钮仍浮在上面。
      失败长这样：栏透明了但仍然占着那 40px（内容还是从 40 开始）。
- [ ] **D3 窗口操作不能丢**：透明档下，在那 40px 里拖动仍能移动窗口、双击仍能最大化/还原；
      Windows 上右上角三颗按钮仍能点。失败长这样：透明之后那一片不再接收指针事件。
- [ ] **D4 全屏**：⌃⌘F / 绿灯 / 阅读器顶栏的全屏按钮三种入口进全屏 ⇒ **任何档位下**这一条
      都不见了、内容顶到 `y=0`；退出全屏恢复该档本来的样子。
- [ ] **D5 持久化**：开着退出应用再进 ⇒ 还开着；关掉 ⇒ 立刻回到 D1 的样子。
- [ ] **D6（认下的代价，不是 bug）**：透明档下应用名与按钮直接浮在画面上，
      画面顶端恰好很亮时确实可能看不清。不接受就关掉这个开关 ——
      设置项副标题已写明这一条。

## B. 阅读器顶栏

- [ ] **R1 默认档零回归**：开关关着时顶栏还是那档最实的液态玻璃（模糊 + 半透明底）。
- [ ] **R2 打开开关**：顶栏不再模糊，变成一层半透明蒙层，**画面从顶栏底下透出来**。
      翻到一页「上深下浅」的图最容易看出来。
- [ ] **R3 不透明度滑条**：0% ⇒ 顶栏只剩文字与按钮，画面完全透出来；100% ⇒ 看不出透明。
      滑条只在开关打开时出现。
- [ ] **R4 可读性**：**浅色主题 + 浅色漫画页**下，书名与图标仍然读得清
      （蒙层取的是主题的 `surface`，不是写死的黑；写死黑的话浅色主题会得到白底浅字）。
      *这一条是本轮唯一的视觉风险点，请专门试。*
- [ ] **R5 持久化与作用域**：换书 / 换章 / 重启后保持；关掉立刻回到 R1。
      顶栏唤出、钉住、悬停揭示这三条既有路径都不受影响。

## C. 两个开关同时开（交叉）

- [ ] **X1 重叠观感**：桌面外壳透明 + 阅读器顶栏透明，把阅读器顶栏唤出 ⇒
      它滑到最顶端时与外壳那条透明栏**重叠**（外壳那条在 `Stack` 上层，
      与 JHenTai 桌面端「标题栏条 + 阅读页菜单」是同一层级关系）。
      请确认这个观感可以接受；不接受就要另立一条规则（例如阅读器顶栏自己下沉 40px），
      那属于新决策，**不要按「修 bug」改**。

## 报告格式

不通过时给 **条目号 + 控制台片段或截图**，不要给描述 ——
症状到方法的映射必须是一对一，否则修的人得先猜。
