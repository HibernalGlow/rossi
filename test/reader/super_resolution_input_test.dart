import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:zephyr/reader/page_source.dart';
import 'package:zephyr/reader/super_resolution_input.dart';

class _ModernSource extends PageSource {
  _ModernSource(this.extension);
  final String extension;
  PageLoadIntent? intent;
  @override
  String get path => '/test/modern.zip';
  @override
  int get pageCount => 1;
  @override
  List<PageRef> get pages => [
    PageRef(index: 0, name: '1$extension', size: BigInt.one),
  ];
  @override
  RasterTargetRef? rasterTargetFor(int index) => null;
  @override
  Future<Uint8List?> getPageBytes(int index) async =>
      throw StateError('JXL/AVIF 原始编码不能冒充 PNG');
  @override
  Future<PageLoadOutcome> load(
    int index, {
    int? targetWidth,
    PageLoadIntent intent = PageLoadIntent.interactive,
  }) async {
    this.intent = intent;
    return PageLoaded(
      RasterPageContent(
        width: 2,
        height: 1,
        sourceWidth: 2,
        sourceHeight: 1,
        rgba: Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]),
      ),
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final extension in ['.jxl', '.avif']) {
    test(
      '$extension input is decoded and encoded as a real full-resolution PNG',
      () async {
        final dir = await Directory.systemTemp.createTemp('rossi_sr_input_');
        try {
          final source = _ModernSource(extension);
          final file = File('${dir.path}/input.png');
          await writeSuperResolutionInput(source, 0, file);
          final png = image.decodePng(await file.readAsBytes())!;
          expect([png.width, png.height], [2, 1]);
          expect(png.getPixel(0, 0).r, 255);
          expect(png.getPixel(1, 0).g, 255);
          expect(source.intent, PageLoadIntent.prefetch);
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
