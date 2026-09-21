import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/debug/local_source_debug_page.dart';
import 'package:zephyr/gpu/gpu_present_page.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/src/rust/api/qjs.dart';
import 'package:zephyr/util/impeller_config.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class DebugSettingPage extends StatefulWidget {
  const DebugSettingPage({super.key});

  @override
  State<DebugSettingPage> createState() => _DebugSettingPageState();
}

class _DebugSettingPageState extends State<DebugSettingPage> {
  @override
  void initState() {
    super.initState();
    _loadImpellerConfig();
  }

  Future<void> _loadImpellerConfig() async {
    final supported = await ImpellerConfig.isForceEnableSupported();
    final forceEnableImpeller = supported
        ? await ImpellerConfig.getForceEnableImpeller()
        : false;

    if (!mounted) return;

    final cubit = context.read<GlobalSettingCubit>();
    if (cubit.state.forceEnableImpeller != forceEnableImpeller) {
      cubit.updateState(
        (current) => current.copyWith(forceEnableImpeller: forceEnableImpeller),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.debug,
      child: ListView(
        children: [
          settingSectionTitle(
            context,
            t.settings.debug,
            icon: Icons.bug_report_outlined,
          ),
          _logAddress(state, cubit),
          _enableMemoryDebug(state, cubit),
          _blockRustHttpRequests(state, cubit),
          _showLayoutOverflowStripes(state, cubit),
          if (defaultTargetPlatform == TargetPlatform.android)
            _forceEnableImpeller(state, cubit),
          if (kDebugMode) ...[
            ListTile(
              leading: const Icon(Icons.colorize_outlined),
              title: Text(t.settings.colorPreview),
              subtitle: Text(t.settings.colorPreviewSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushRoute(const ShowColorRoute()),
            ),
            ListTile(
              leading: const Icon(Icons.developer_mode_outlined),
              title: Text(t.settings.qjsRuntimeDebug),
              subtitle: Text(t.settings.qjsRuntimeDebugSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushRoute(const QjsRuntimeDebugRoute()),
            ),
            ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: Text(t.settings.coremlDebug),
              subtitle: Text(t.settings.coremlDebugSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushRoute(const CoreMLUpscaleDebugRoute()),
            ),
          ],
          // 本地来源读取（v0.1 判据 A 的观察窗口）**刻意不放在 kDebugMode 里**：
          // 判据 B/C/D 只在 Release 下成立，需要被观察的窗口却只在 debug 可见，
          // 就等于「量不到」。它是诊断工具而不是功能特性，所以无 i18n 词条，
          // 并走 MaterialPageRoute 直连而不是 @RoutePage（不触发全量 codegen）。
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('本地来源读取（判据 A）'),
            subtitle: const Text('散图文件夹 / CBZ / CBR 直读，含逐页耗时与拒绝类别'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LocalSourceDebugPage(),
              ),
            ),
          ),
          // GPU 上屏（D3D12 共享纹理）。与上一条同理**刻意不放进 kDebugMode**：
          // 这条链路通不通由「引擎有没有来打开共享句柄」判定，而那要拖窗口、
          // 要看合成，只有在 Release 下跑出来的数才作数。
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('GPU 上屏（D3D12 共享纹理）'),
            subtitle: const Text('Rust 解码 → wgpu → GPU 拷贝 → 共享纹理，像素不过桥'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GpuPresentPage()),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _enableMemoryDebug(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.memory_outlined),
      title: Text(t.settings.memoryDebug),
      subtitle: Text(t.settings.memoryDebugSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.enableMemoryDebug,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(enableMemoryDebug: value),
        );
      },
    );
  }

  Widget _logAddress(GlobalSettingState state, GlobalSettingCubit cubit) {
    final logAddress = state.logAddress.trim();
    return ListTile(
      leading: const Icon(Icons.link_outlined),
      title: Text(t.settings.logAddress),
      subtitle: Text(
        logAddress.isEmpty ? t.settings.logAddressSubtitle : logAddress,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        var inputValue = logAddress;
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.settings.logAddress),
            content: TextFormField(
              initialValue: logAddress,
              autofocus: true,
              onChanged: (value) => inputValue = value.trim(),
              decoration: const InputDecoration(
                hintText: 'https://example.com/log',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                child: Text(t.common.cancel),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                child: Text(t.common.ok),
                onPressed: () => Navigator.pop(context, inputValue),
              ),
            ],
          ),
        );

        if (result != null && result != logAddress) {
          cubit.updateState((current) => current.copyWith(logAddress: result));
          showSuccessToast(t.common.settingSaved);
        }
      },
    );
  }

  Widget _blockRustHttpRequests(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.cloud_off_outlined),
      title: Text(t.settings.blockRustHttpRequests),
      subtitle: Text(t.settings.blockRustHttpRequestsSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.blockRustHttpRequests,
      onChanged: (bool value) {
        setHttpRequestsBlocked(blocked: value);
        cubit.updateState(
          (current) => current.copyWith(blockRustHttpRequests: value),
        );
      },
    );
  }

  /// 「黄黑溢出斜纹」总开关。
  ///
  /// 默认开 ＝ Flutter 原生行为。关掉后：本项目自绘的布局不再画条纹
  /// （`QuietRow` / `QuietColumn`，见 `lib/util/layout/quiet_flex.dart`），
  /// 并且全局不再上报「overflowed by … pixels」这类错误（控制台不刷屏）。
  ///
  /// **不放进 `kDebugMode`**：这一项在 release 下本来就无事可做（assert 关掉了），
  /// 但把它藏起来只会让人以为开关没生效 —— 描述里写清楚，比藏起来好。
  Widget _showLayoutOverflowStripes(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.warning_amber_outlined),
      title: Text(t.settings.showLayoutOverflowStripes),
      subtitle: Text(t.settings.showLayoutOverflowStripesSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.showLayoutOverflowStripes,
      onChanged: (bool value) {
        // 落盘 + 写全局标志都在 cubit 里（`_persistAndEmit`），
        // 与 `blockRustHttpRequests` 一个路子，别在页面里再写一遍。
        cubit.updateState(
          (current) => current.copyWith(showLayoutOverflowStripes: value),
        );
      },
    );
  }

  Widget _forceEnableImpeller(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return SwitchListTile(
      secondary: const Icon(Icons.auto_awesome_outlined),
      title: Text(t.settings.forceEnableImpeller),
      subtitle: Text(t.settings.forceEnableImpellerSubtitle),
      thumbIcon: kSettingSwitchThumbIcon,
      value: state.forceEnableImpeller,
      onChanged: (bool value) async {
        cubit.updateState(
          (current) => current.copyWith(forceEnableImpeller: value),
        );
        await ImpellerConfig.setForceEnableImpeller(value);
        showSuccessToast(t.common.restartToTakeEffect);
      },
    );
  }
}
