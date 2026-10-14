# comic_read view parts 维护笔记

`comic_read.dart` 按职责拆成了 8 个 part，后面回看逻辑时可先按下面索引找。

## 快速索引

- `comic_read_init_part.dart`
  - 初始化和释放：控制器、订阅、历史管理器、首帧收尾。
- `comic_read_interaction_part.dart`
  - 阅读交互：键盘、点击/双击、缩放、多指锁滚动、行列模式容器。
- `comic_read_system_ui_part.dart`
  - 系统 UI 和音量键拦截：菜单显隐联动、Android 特殊处理、防抖同步。
- `comic_read_auto_read_part.dart`
  - 自动阅读：参数同步、计时器、暂停/继续、右下角浮动按钮。
- `comic_read_slideshow_part.dart`
  - 幻灯片放映：整页驻留计时、结束策略（停 / 循环本章 / 续下一章）、
    暂停/继续、屏上驻留指示。与自动滚屏是两套独立计时器。
- `comic_read_page_order_part.dart`
  - 页面排序：把当前章的「显示位置 → 源下标」交给 `ReaderSessionCoordinator`，
    供缩略图条 / 滑动条预览 / 页名提示 / 工作区页面列表按下标取页。
- `comic_read_magnifier_part.dart`
  - 放大镜：当前页取样窗口（落位矩形 + 位图）的报告与生命周期。
- `comic_read_eink_part.dart`
  - 墨水屏：整屏刷新按钮与按页数自动刷新。
- `comic_read_view_part.dart`
  - 页面拼装：顶栏 / 底栏 / 页码 / 进度条的构造与跳页编排。

## 状态管理

半无缝章节拼接逻辑已迁移到 `lib/page/comic_read/cubit/reader_seamless_cubit.dart`。
自动阅读、系统 UI 等副作用已收敛到 `lib/page/comic_read/controller/` 下的专用控制器。
手动页序住在 `cubit/reader_page_order_cubit.dart`（会话级，刻意不落盘），
档位住在 `ReadSettingState.readerPageOrderMode`。

## 常用定位方式

- 先从 `comic_read.dart` 的 `build` 看当前入口状态。
- 查初始化问题直接看 `comic_read_init_part.dart`。
- 查手势/翻页/缩放冲突看 `comic_read_interaction_part.dart`。
- 查状态栏或音量键行为看 `comic_read_system_ui_part.dart`。
- 查自动阅读不触发或频率异常看 `comic_read_auto_read_part.dart`。
- 查幻灯片不放 / 到章末行为不对看 `comic_read_slideshow_part.dart` 与
  `controller/reader_slideshow_controller.dart`。
- 查「某一处和画面差一页」看 `comic_read_page_order_part.dart`：多半是某一处
  还在按页表下标取页，而没有按显示顺序取。
- 查放大镜不出 / 取错像素看 `comic_read_magnifier_part.dart` 与
  `widgets/magnifier/`。
- 查章节加载/过渡卡片/无缝拼接看 `reader_seamless_cubit.dart`。
