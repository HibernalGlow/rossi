import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/video/view/active_video_scope.dart';

void main() {
  test('旧视频设置升级后默认融合底栏', () {
    expect(const VideoSettings().integrateControlsWithBottomBar, isTrue);
    expect(
      VideoSettings.parse(
        'pinned=true;autoPlay=false',
      ).integrateControlsWithBottomBar,
      isTrue,
    );
  });

  test('融合开关跨存取保持，修改其它播放设置不重置它', () {
    const settings = VideoSettings(
      integrateControlsWithBottomBar: false,
      controlsPinned: true,
      volumePercent: 60,
    );
    final restored = VideoSettings.parse(settings.encode());
    expect(restored.integrateControlsWithBottomBar, isFalse);
    expect(restored.controlsPinned, isTrue);
    expect(restored.volumePercent, 60);
    expect(
      restored.copyWith(maxRate: 4).integrateControlsWithBottomBar,
      isFalse,
    );
    expect(
      restored
          .copyWith(integrateControlsWithBottomBar: true)
          .integrateControlsWithBottomBar,
      isTrue,
    );
  });
}
