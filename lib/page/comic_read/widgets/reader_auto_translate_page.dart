import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/cubit/reader_state.dart';
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/reader/translated_page_controller.dart';
import 'package:zephyr/service/ocr/ocr_settings.dart';

/// 「翻到新的一页自动译」那条开关的执行端。
///
/// # 为什么它不是设置面板里的一颗布尔
///
/// 顶栏那颗芯片是**按页**的（见 `reader_translated_page_chip.dart` 的理由：一张成品页
/// 要十几秒，全局开关等于往后每一页都得等）。这一档就是把「等」交还给愿意等的人：
/// 翻页之后由这里替用户按一次芯片。
///
/// # 为什么单独一个透明组件、挂在正文外面
///
/// 它没有 UI，但**不能**住在上下栏里：栏是揭示式的，平时不画 —— 藏在里面的监听器
/// 会在用户看不到栏的那段时间里不跟着翻页，自动档于是「有时灵有时不灵」。
/// 所以挂在 `PageBloc` 外面，和阅读正文同生同死。
///
/// # 为什么只走公开 API
///
/// `TranslatedPageController` 的 `_turnOn` 是私有的，而 `toggle` 在「这一页已经有译文」时
/// 是**关掉**它。所以这里必须先用公开的 [TranslatedPageController.isOwned] 与
/// [TranslatedPageController.phase] 判掉「已经有归属」和「正在飞」这两格，
/// 再调 [TranslatedPageController.toggle] —— 少判一格就会把用户刚手动关掉的那一页又点开。
class ReaderAutoTranslatePage extends StatefulWidget {
  const ReaderAutoTranslatePage({super.key, required this.child});

  final Widget child;

  @override
  State<ReaderAutoTranslatePage> createState() =>
      _ReaderAutoTranslatePageState();
}

/// 自动档那一格该不该动手 —— 纯函数，为了能被直接量。
///
/// # 为什么把判据抽出来
///
/// 执行链的另外两头（`LocalReadSession` 里的 `presenter`、真的 `GpuPresentController`）
/// 在单测里拿不到，所以「真的翻出了一张译文页」只能真机判（本仓对这种装配早有先例：
/// `local_read_session_translation_gate_test.dart` 开头就明写了哪一行当初只能靠真机）。
/// 但**守卫**不需要呈现器：这一档最贵的错是抢用户 —— 把他刚手动关掉的页又点开、
/// 或者在上一张还在飞的时候再塞一张，那会同时烧两条十几秒的推理。
/// 所以守卫单独抽出来逐格验，链路留待真机。
///
/// # 每一格对应什么错
///
/// - [owned]：这一页已经有译文了。`TranslatedPageController.toggle` 在已归属时是**关掉**，
///   少了这一判，自动档会把用户手动关掉的页当成「还没译」再点一次。
/// - [building]：已经有一张在飞。增强图轨一页只有一份，且译文与超分共用（见
///   `translated_page_controller.dart` 的注释），并发塞第二张只会互相覆盖。
/// - [alreadyTried]：同一页只试一次。构建失败后 `owned` 仍然是 false，
///   没有这一判每次重建都会重新发起一次十几秒的推理。
bool readerAutoTranslateShouldRun({
  required bool auto,
  required bool supported,
  required bool running,
  required bool owned,
  required bool building,
  required bool alreadyTried,
  required int index,
}) {
  return auto &&
      supported &&
      !running &&
      !owned &&
      !building &&
      !alreadyTried &&
      index >= 0;
}

class _ReaderAutoTranslatePageState extends State<ReaderAutoTranslatePage> {
  bool _auto = OcrSettings.defaultAutoTranslatePage;

  /// 已经为哪一页尝试过。同一页只试一次：失败不重试，否则每帧重建都会
  /// 重新发起一次十几秒的推理。翻页或重开开关时清掉。
  int _lastTriedIndex = -1;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    OcrSettings.changes.addListener(_onSettingsChanged);
    unawaited(_loadSetting());
  }

  @override
  void dispose() {
    OcrSettings.changes.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _loadSetting() async {
    final value = await OcrSettings.loadAutoTranslatePage();
    if (!mounted) return;
    final wasOff = !_auto;
    setState(() => _auto = value);
    if (wasOff && value) {
      // 刚打开：当前这一页就补一次，不用等用户翻一页才见效。
      _lastTriedIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runForCurrentPage());
    }
    if (!value) _lastTriedIndex = -1;
  }

  void _onSettingsChanged() => unawaited(_loadSetting());

  void _runForCurrentPage() {
    if (!mounted) return;
    _run(context.read<ReaderCubit>().state.currentSlot);
  }

  Future<void> _run(int index) async {
    final controller = TranslatedPageController.instance;
    if (!readerAutoTranslateShouldRun(
      auto: _auto,
      supported: ocrSupportedHere,
      running: _running,
      owned: controller.isOwned(index),
      building: controller.phase == TranslatedPagePhase.building,
      alreadyTried: index == _lastTriedIndex,
      index: index,
    )) {
      return;
    }
    final source = LocalReadSession.instance.currentSource;
    final presenter = LocalReadSession.instance.presenter;
    if (source == null || presenter == null) return;
    _lastTriedIndex = index;
    _running = true;
    try {
      await controller.toggle(
        source: source,
        presenter: TranslatedPagePresenter.of(presenter),
        index: index,
      );
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ReaderCubit, ReaderState>(
      listenWhen: (previous, current) =>
          previous.currentSlot != current.currentSlot,
      listener: (context, state) => _run(state.currentSlot),
      child: widget.child,
    );
  }
}
