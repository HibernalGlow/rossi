import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/workspace/model/workspace_lane_focus.dart';

void main() {
  test('Reader 窄缝不能挤掉本可完整显示的目标', () {
    const geometry = WorkspaceLaneFocusGeometry(
      start: {'reader': 0, 'right': 410},
      width: {'reader': 400, 'right': 580},
      contentWidth: 990,
    );
    final target = geometry.focusOffset(
      laneId: 'right',
      viewportWidth: 600,
      currentOffset: 0,
      readerLaneId: 'reader',
      readerPeekWidth: 56,
      keepReaderVisible: true,
    );
    expect(target, 390);
    expect(target + 600, greaterThanOrEqualTo(geometry.endOf('right')));
  });

  test('窄缝可与完整显示共存时保留，已可见时不居中', () {
    const geometry = WorkspaceLaneFocusGeometry(
      start: {'reader': 0, 'right': 410},
      width: {'reader': 400, 'right': 300},
      contentWidth: 1000,
    );
    final target = geometry.focusOffset(
      laneId: 'right',
      viewportWidth: 600,
      currentOffset: 0,
      readerLaneId: 'reader',
      readerPeekWidth: 56,
      keepReaderVisible: true,
    );
    expect(target, 110);
    expect(
      geometry.focusOffset(
        laneId: 'right',
        viewportWidth: 600,
        currentOffset: 200,
      ),
      200,
    );
  });

  test('超宽泳道尽可能显示内容，不为留缝额外损失可用宽', () {
    const geometry = WorkspaceLaneFocusGeometry(
      start: {'reader': 0, 'right': 410},
      width: {'reader': 400, 'right': 700},
      contentWidth: 1110,
    );
    expect(
      geometry.focusOffset(
        laneId: 'right',
        viewportWidth: 600,
        currentOffset: 0,
        readerLaneId: 'reader',
        readerPeekWidth: 56,
        keepReaderVisible: true,
      ),
      410,
    );
  });
}
