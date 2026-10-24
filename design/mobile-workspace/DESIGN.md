# Rossi 移动端工作台 · 设计登记

> 本文件在此前会话的 DESIGN.md 于 fork 中丢失后重建(2026-10-24),收拢存续决策;HTML 设计稿目录(explore/home)在同次丢失中清空,但其结论已全部落进 `lib/workspace/mobile/` 与导航栈,稿本身不再是交付物。

## 方向(已选定并实现)

三方向对比(01 书桌小组件 / 02 夜灯仪表 / 03 书房登记簿)后用户选定 **01 Breeze Desk**:MD3 Expressive、应用种子色 `#9C4B5E` tonal、数据即小组件。标杆为 Mihon 书库(真实截图)与 Vayana 统计(设计源码)。

## Flutter 落地(全部在工作区,按 §6.6 未提交)

- `lib/workspace/mobile/workspace_mobile_home_page.dart` 工作台首页(展开态):继续阅读 hero + 洞察速览 + 历史/文件/工具入口;≥760 两列。
- `lib/workspace/mobile/workspace_mobile_insights_page.dart` 阅读数据页:`cardsForPanel(insights)` 整页复用 8 张洞察卡,手机单列/展台两列。
- `lib/workspace/mobile/workspace_mobile_card_page.dart` 单卡全屏宿主:`standalone` 复用任意注册表卡(文件管理/历史由此全屏,`FileManagerCard` 零改动)。
- `lib/workspace/mobile/reader_info_sheet.dart` Reader 信息底部面板:底栏工具「更多」菜单唤起,信息面板五卡整批复用(`WorkspaceCubit` 由 sheet 内 BlocProvider 提供)。
- 路由 3 条 + i18n 词条(zh/en);`navigation_bar.dart` 三入口(底栏动作/启动落点/设置入口)按 `hasWorkspaceEntry` 分流:手机进移动首页,平板/桌面进桌面泳道。
- 测试 `test/workspace/mobile_workspace_pages_test.dart` 5 例全过;改动文件 analyze 清零。

## 底栏长按进自定义(2026-10-23 第五、六轮)

`NavigationDock`/`FloatingNavigationBar` 新增可选 `onLongPress` + `longPressDuration`:判定做在 bar 的裸 Listener 里(item 挂 GestureDetector 会把点击拖进手势竞技场,镜片落下变迟);滑动超触控位移取消,触发带中档触感,长按后松手不选中。设置页「外观 → 导航」有开关与时长滑块。测试 `test/widgets/navigation_dock_long_press_test.dart` 4 例。

## 默认长按阈值 2400ms(2026-10-24,用户指定)

- `NavigationSettingState.dockLongPressMilliseconds` 出厂值 800 → **2400**;滑块量程 300..1500 → **300..3000**(100ms 一格)。
- 依据:500ms 平台默认常与切页误触;2400 下长按是「要明确想打开才按得住」的次要意图,误触几乎归零。
- 同步更新:freezed 默认值(codegen 重生成)、`_DockLongPressTile` 的 `_max`/`_default`、`navigation_bar.dart` 与 `navigation_dock.dart` 注释、测试第 4 例(2400 阈值下 500ms 不触发、按满触发)。
