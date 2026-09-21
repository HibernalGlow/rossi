part of '../global_setting.dart';
// 阅读快照与环境光暗度常量（rossi）


/// 自适应背景的**压暗程度**允许范围与默认值。
///
/// 默认 45（= 保留 55% 亮度）取自参考实现的实测档位：neoview 的
/// `ReaderBackgroundLayer.css` 用的是 `brightness(0.48)`（流光溢彩）与
/// `brightness(0.56)`（自动匹配）。取色来自页面**边沿**，而漫画页的边沿常常就是
/// 白纸 —— 不压暗的话，白底漫画在暗环境里就是一块刺眼的光斑。
const int readerAmbientDimPercentMin = 0;

const int readerAmbientDimPercentMax = 85;

const int readerAmbientDimPercentDefault = 45;


/// 阅读设置的读入口（**不依赖 `BuildContext`**）。
///
/// 与 [toastSetting] 同一口径：调用点（呈现链路在翻页后决定要不要去读探针）
/// 拿不到 Cubit，而这里读的只是一份内存里的本地库快照。
/// 本地库还没起来（启动早期）或已关闭时回落到默认值 ——
/// 绝不让「读设置」本身把取色链路炸掉。
ReadSettingState get readSettingSnapshot {
  try {
    return objectbox.userSettingBox.get(1)?.globalSetting.readSetting ??
        const ReadSettingState();
  } catch (_) {
    return const ReadSettingState();
  }
}
