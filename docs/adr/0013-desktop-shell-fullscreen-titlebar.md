# 桌面外壳：全屏时自制标题栏整条让位，全屏状态以「窗口自己报的事件」为唯一真相

桌面上 Rossi 自己画一条 40px 的标题栏（`lib/widgets/desktop/custom_title_bar.dart`）——
macOS 侧窗口用了 `TitleBarStyle.hidden`（原生标题文字隐藏、内容顶到窗口最上面），
窗口级的拖拽/关闭得应用自己补上。用户报的是：**已经全屏了，顶上还压着这条写着 Breeze 的栏**。

## 事实

- **原生标题栏不是嫌疑对象。** `WindowLogic.initWindow` 用的是
  `titleBarStyle: TitleBarStyle.hidden`；macOS 侧实现是 `titleVisibility = .hidden` +
  `titlebarAppearsTransparent = true` + `styleMask.insert(.fullSizeContentView)`
  （window_manager 0.5.2 `WindowManager.swift:379`）。也就是说窗口顶部**没有**系统画的标题文字，
  用户看到的那条只能是自己画的。
- **判「这条横条是谁画的」用像素，不靠猜。** 用户给的是窗口顶部的裁切（2552×120）：
  - 亮带恰好是 `y=0..39`，**40px = `CustomTitleBar` 的 `height: 40`**（原生标题栏是 28pt，
    2× 屏上 56px，对不上）；带下沿直接是阅读器内容。
  - 带内唯一的深色像素是 42px 宽的 "Breeze"，中心 x≈1320，而图像中心 1276 —— **偏右 +44px**，
    正是 `custom_title_bar.dart` 里那个「为红绿灯留出的 80px 前置占位」造成的
    （`80 + (W-80)/2 = W/2 + 40`）。
  - 左上角 80px 内**没有红绿灯三点**：`setTitleBarStyle` 的 `windowButtonVisibility` 默认
    `true`，它们本该在。不在 ⇒ 窗口处于**原生全屏**（全屏时系统把红绿灯收走）。
  - 判据还差一条：右上角那条红色斜带是 Flutter 的 debug 横幅，它**压在这条亮带上** ⇒
    亮带在 Flutter 树里，不在系统层。
  - 结论：**窗口确实在原生全屏，而应用仍画着自己的标题栏。**
- **错在哪。** `ReaderDesktopFullscreenService` 只记「应用自己请求的切换」
  （阅读器 AppBar 上的全屏按钮 → `setFullscreen`）。用户按 **⌃⌘F、视图菜单里的「进入全屏」
  或绿灯**时应用毫不知情，状态停在 `false`，标题栏就留在那里。
  `window_manager` 的 `WindowListener` 早就有 `onWindowEnterFullScreen` /
  `onWindowLeaveFullScreen`（macOS 从 `windowDidEnterFullScreen` 发 `enter-full-screen`），
  而项目里**没有任何地方监听它**。

## 决定

1. **全屏状态的唯一真相是窗口自己。** `ReaderDesktopFullscreenService` 兼作 `WindowListener`，
   **构造时即登记**（App 第一次 build 就取到它，早于任何一次全屏切换，也早于阅读器被打开 ——
   于是「没开阅读器时按 ⌃⌘F」也能抓到）；两个事件直接写 `fullscreenNotifier`。
2. **应用自己的切换只算「请求」。** `setFullscreen` 先乐观更新（动画要几百毫秒，
   等它回来才动 UI 会顿一下），过渡结束后**与窗口对账**（`isFullScreen()`）：
   窗口没真的全屏就改回去 —— 不留「应用说全屏、窗口没全屏」的错账（这次的 bug 就是错账）。
3. **`fullscreenNotifier` 只有一个出口。** 订阅者（外壳的标题栏、阅读器 AppBar 的图标）
   不许各自去问窗口 —— 那会造出第二本账，就是这次坏法的根源。
4. **全屏时标题栏整条不建**，不是「透明 / 隐藏但仍占 40px」：这 40px 要还给内容。
   为此把 `main.dart` 里那段 `ValueListenableBuilder + Column` 抽成
   `lib/widgets/desktop/desktop_shell_frame.dart` —— 让「让位」这件事能被 widget test 钉住。

## 判据

| 判据 | 结果 |
|---|---|
| `flutter test test/desktop/desktop_shell_frame_test.dart` | **5 passed** |
| `python3 test/workspace/mutation_check.py desktop_shell` | **4/4 变异体被捕获**（都是判据失败，不是编译错） |

- 判别「让位」**看矩形**：标题栏是 40px 的一行，「不占位」= 内容的 `top` 变成 `0`。
  只看 `findsNothing` 不够 —— 「标题栏不建了但留个 40px 占位」照样让 `findsNothing` 通过（M16 就是这条）。
- 变异体：M13 `onWindowEnterFullScreen` 变空（**= 用户报的那个 bug 本身**）、
  M14 `onWindowLeaveFullScreen` 变空、M15 全屏时照旧建标题栏、M16 假让位（留占位）。

**顺带修掉变异工装自己的一个缺陷**：跨文件判据组里，前一个变异体会**留在别的文件**里，
让后一个变异体因为别人的错变红 —— 假红和假绿一样有毒（它让「已捕获」这个结论失去意义）。
现在每个变异体都先还原全部文件，再单独写这一个变异。修完重跑三套：**15/15 被捕获**。

## 残留（明确记账）

- 阅读器 `ReaderLifecycleController._isDesktopFullscreen` 仍是它自己的一本账（决定 AppBar 上
  那个图标），所以 ⌃⌘F 进全屏后图标会滞后一格。**本次没改**：那块文件正被另一路工作占用，
  且它联动 `onRefreshState` / 音量同步，需要在真机上验，不宜顺手改。
  **留待**：把它也接到 `fullscreenNotifier` 上。
- **本机没有 Xcode**（`flutter test … -d macos` 报 `Xcode not installed`），所以「⌃⌘F 之后标题栏真的没了」
  这一条**没有在真机上复验过**，只在框架层验到了「事件 → 状态 → 让位」。
- **Windows / Linux 侧未实测**：那边至少保留原有路径（应用自己的按钮仍写状态），不依赖这两个事件。
