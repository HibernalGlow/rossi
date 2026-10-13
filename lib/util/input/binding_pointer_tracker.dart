import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:zephyr/util/input/binding_input_capture.dart';

typedef BindingLookup =
    Map<String, dynamic>? Function(Map<String, dynamic> input);

/// 只采集指针，不决定绑定优先级。所有探测与派发均交回核心解析器。
class BindingPointerTracker {
  BindingPointerTracker({
    required this.lookup,
    required this.dispatch,
    this.deferAreaClicks = false,
  });
  final BindingLookup lookup;
  final bool Function(Map<String, dynamic> input) dispatch;

  /// 让阅读器的 onTap 在赢得手势竞争后执行单击区域；视频等子控件的点击不会重复派发。
  final bool deferAreaClicks;
  Map<String, dynamic>? deferredAreaClick;
  final _starts = <int, Offset>{};
  final _positions = <int, Offset>{};
  final _active = <int>{};
  final _holds = <Timer>[];
  final _holdOrigins = <Timer, (Map<int, Offset>, double)>{};
  final _directions = <String>[];
  Offset _last = Offset.zero;
  bool _touch = false;
  int _button = 0;
  int _fingers = 0;
  String? _area;
  bool claimed = false;
  bool _movedBeyondTap = false;
  Timer? _click;
  int? _clickButton;
  Offset? _clickPosition;

  Map<String, dynamic> _pointer(String action, {bool area = false}) => {
    'device': 'mouse',
    if (area) 'area': _area,
    'button': _button,
    'action': action,
  };
  Map<String, dynamic> _touchInput(String gesture) => {
    'device': 'touch',
    'gesture': gesture,
    'fingers': _fingers,
    if (_area != null) 'area': _area,
  };
  Map<String, dynamic> _gesture(String trigger) => {
    'device': 'mouse-gesture',
    'button': _button,
    'directions': [..._directions],
    'trigger': trigger,
  };

  void _cancelHolds() {
    for (final timer in _holds) {
      timer.cancel();
    }
    _holds.clear();
    _holdOrigins.clear();
  }

  void down(PointerDownEvent event, String? area) {
    if (_active.isEmpty) {
      _cancelHolds();
      _starts.clear();
      _positions.clear();
      _directions.clear();
      claimed = false;
      _movedBeyondTap = false;
      deferredAreaClick = null;
      _fingers = 0;
      _last = event.localPosition;
      _touch = isBindingTouchPointer(event.kind);
      _button = bindingMouseButton(event.buttons) ?? 0;
      _area = area;
    }
    _active.add(event.pointer);
    _starts[event.pointer] = event.localPosition;
    _positions[event.pointer] = event.localPosition;
    _fingers = _active.length > _fingers ? _active.length : _fingers;
    _cancelHolds();
    if (claimed) return;
    if (!_touch) {
      if (dispatch(_pointer('press', area: _area != null))) {
        claimed = true;
        return;
      }
      _scheduleHold(_pointer('hold', area: _area != null));
    } else {
      _scheduleHold(_touchInput('long-press'));
    }
  }

  void _scheduleHold(Map<String, dynamic> input, {bool fromCurrent = false}) {
    final binding = lookup(input);
    if (binding == null) return;
    final target = binding['input'] as Map;
    final starts = Map<int, Offset>.from(fromCurrent ? _positions : _starts);
    final tolerance = (target['moveTolerancePx'] as num? ?? 12).toDouble();
    final duration = (target['durationMs'] as num? ?? 500).toInt().clamp(
      100,
      5000,
    );
    final timer = Timer(Duration(milliseconds: duration), () {
      if (claimed || _active.isEmpty) return;
      if (starts.entries.any(
        (entry) =>
            ((_positions[entry.key] ?? entry.value) - entry.value).distance >
            tolerance,
      )) {
        return;
      }
      claimed = dispatch(input);
    });
    _holds.add(timer);
    _holdOrigins[timer] = (starts, tolerance);
  }

  void move(PointerMoveEvent event) {
    if (!_active.contains(event.pointer)) return;
    _positions[event.pointer] = event.localPosition;
    if ((event.localPosition - _starts[event.pointer]!).distance >= 12) {
      _movedBeyondTap = true;
    }
    for (final entry in _holdOrigins.entries) {
      final start = entry.value.$1[event.pointer];
      if (start != null &&
          (event.localPosition - start).distance > entry.value.$2) {
        entry.key.cancel();
      }
    }
    if (_touch || claimed) return;
    final delta = event.localPosition - _last;
    if (delta.distance < 16) return;
    final direction = bindingDirection(delta);
    if (_directions.lastOrNull != direction && _directions.length < 16) {
      _directions.add(direction);
    }
    _last = event.localPosition;
    _cancelHolds();
    _scheduleHold(_gesture('hold'), fromCurrent: true);
  }

  void up(PointerUpEvent event) {
    if (!_active.remove(event.pointer)) return;
    _positions[event.pointer] = event.localPosition;
    _cancelHolds();
    if (_active.isNotEmpty || claimed) return;
    final delta =
        _starts.entries
            .map(
              (entry) => (_positions[entry.key] ?? entry.value) - entry.value,
            )
            .fold(Offset.zero, (a, b) => a + b) /
        _starts.length.toDouble();
    if (_touch) {
      if (delta.distance >= 40) {
        claimed = dispatch(_touchInput('swipe-${bindingDirection(delta)}'));
      } else if (delta.distance < 12 && !_movedBeyondTap) {
        // 区域条件与通用 tap 由核心一次解析；触屏绝不回退到鼠标区域。
        claimed = _areaClick(_touchInput('tap'));
      }
      return;
    }
    if (_directions.isNotEmpty && dispatch(_gesture('instant'))) {
      claimed = true;
      return;
    }
    if (delta.distance > 12) return;
    final click = _pointer('click', area: _area != null);
    final doubleClick = _pointer('double-click', area: _area != null);
    if (deferAreaClicks && _button == 0) {
      _areaClick(click);
      return;
    }
    if (lookup(doubleClick) != null) {
      claimed = true;
      if (_click?.isActive == true &&
          _clickButton == _button &&
          (event.localPosition - _clickPosition!).distance <= 24) {
        _click?.cancel();
        dispatch(doubleClick);
      } else {
        _click?.cancel();
        _clickButton = _button;
        _clickPosition = event.localPosition;
        _click = Timer(kDoubleTapTimeout, () => dispatch(click));
      }
    } else {
      claimed = _areaClick(click);
    }
  }

  bool _areaClick(Map<String, dynamic> input) {
    if (!deferAreaClicks || (!_touch && input['button'] != 0)) {
      return dispatch(input);
    }
    deferredAreaClick = input;
    return false;
  }

  void cancel() {
    deferredAreaClick = null;
    _click?.cancel();
    _cancelHolds();
    _active.clear();
    _starts.clear();
    _positions.clear();
    claimed = true;
  }

  void dispose() {
    cancel();
    _click?.cancel();
  }
}
