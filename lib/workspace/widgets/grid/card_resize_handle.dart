import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/motion/expressive_motion.dart';
import 'package:zephyr/i18n/strings.g.dart';

/// 尺寸手柄在按下时接管指针，横向泳道与纵向内容滚动不会抢走拖拽。
class CardResizeHandle extends StatefulWidget {
  const CardResizeHandle({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required this.label,
  });

  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
  final String label;

  @override
  State<CardResizeHandle> createState() => _CardResizeHandleState();
}

class _CardResizeHandleState extends State<CardResizeHandle> {
  bool _pressed = false;
  Offset _delta = Offset.zero;

  void _start(DragStartDetails details) {
    _delta = Offset.zero;
    setState(() => _pressed = true);
    HapticFeedback.selectionClick();
    widget.onStart();
  }

  void _finish({bool cancelled = false}) {
    if (!_pressed) return;
    setState(() => _pressed = false);
    if (cancelled) {
      widget.onCancel();
    } else {
      widget.onEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = ExpressiveMotion.duration(
      context,
      ExpressiveMotion.effectDuration,
    );
    return Semantics(
      label: t.workspace.dragToResize,
      value: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        child: Tooltip(
          message: _pressed ? widget.label : t.workspace.dragToResize,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _ImmediateResizeGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _ImmediateResizeGestureRecognizer
                  >(
                    _ImmediateResizeGestureRecognizer.new,
                    (recognizer) => recognizer
                      ..dragStartBehavior = DragStartBehavior.down
                      ..onStart = _start
                      ..onUpdate = (details) {
                        _delta += details.delta;
                        widget.onUpdate(_delta);
                      }
                      ..onEnd = (_) {
                        _finish();
                      }
                      ..onCancel = () {
                        _finish(cancelled: true);
                      },
                  ),
            },
            child: SizedBox(
              width: 40,
              height: 36,
              child: Center(
                child: AnimatedScale(
                  scale: _pressed ? .88 : 1,
                  duration: duration,
                  curve: ExpressiveMotion.spatialCurve,
                  child: AnimatedContainer(
                    duration: duration,
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _pressed
                          ? scheme.primary
                          : scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(_pressed ? 8 : 10),
                      boxShadow: _pressed
                          ? [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: .3),
                                blurRadius: 10,
                              ),
                            ]
                          : [],
                    ),
                    child: GlyphIcon(
                      AppGlyphs.openInFull,
                      size: 16,
                      color: _pressed
                          ? scheme.onPrimary
                          : scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImmediateResizeGestureRecognizer extends PanGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    // Pan 的已接管指针取消也会走 onEnd；先撤回预览，避免误保存。
    if (event is PointerCancelEvent) onCancel?.call();
    super.handleEvent(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // 只在明确的尺寸手柄上立即接受；标题和卡片正文仍走正常手势仲裁。
    resolve(GestureDisposition.accepted);
  }
}
