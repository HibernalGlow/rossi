import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:zephyr/page/comic_read/model/current_page_image_info.dart';
import 'package:zephyr/page/comic_read/widgets/settings/sections/current_page_image_info_section.dart';

void main() {
  test('inspects encoded dimensions and format without rendering pixels', () {
    final encoded = Uint8List.fromList(
      image.encodePng(image.Image(width: 2, height: 3)),
    );
    final facts = inspectImageBytes(encoded);
    expect((facts.format, facts.width, facts.height), ('PNG', 2, 3));
  });

  test('only the reporting page owner can clear current metadata', () {
    final store = CurrentPageImageInfo.instance;
    final first = Object();
    final second = Object();
    store.reportFile(first, '/tmp/first.png');
    store.reportFile(second, '/tmp/second.png');
    store.clear(first);
    expect(store.current?.filePath, '/tmp/second.png');
    store.clear(second);
    expect(store.current, isNull);
  });

  testWidgets('latest page report wins when a slot is reused', (tester) async {
    final store = CurrentPageImageInfo.instance;
    final owner = Object();
    store.reportFileAfterFrame(owner, '/tmp/old.png', () => true);
    store.reportFileAfterFrame(owner, '/tmp/new.png', () => true);
    await tester.pumpWidget(const SizedBox());
    expect(store.current?.filePath, '/tmp/new.png');
    store.clear(owner);
  });
}
