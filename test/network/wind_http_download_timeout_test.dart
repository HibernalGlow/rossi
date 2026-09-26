/// `WindHttp.download` 的超时语义：它跑的是**流式**下载，几百 MB 的权重按「整请求上限」
/// 计时必然死在半路（2026-09-26 实测：huggingface 走本机代理 5 MB/s，
/// 343 MB 的识别件要 ~69 s，而默认上限是 30 s）。更糟的是 reqwest 把
/// 「body 还没读完就到期」包成 `Decode`，用户看到的是一句看不出原因的
/// 「error decoding response body」。
///
/// 这里钉住两件事：
/// ① **慢但在动**的连接不许被掐（总时长超过上限也要下得完）；
/// ② 真的**停滞**要掐，而且报错必须说清是停滞、并留下干净的现场（没有 `.part` 残骸）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/src/rust/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var nativeReady = false;
  var nativeError = '';

  // 与仓里其它原生相关测试同口径：初始化必须放在 FakeAsync 区之外。
  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (e) {
      nativeError = '$e';
    }
  });

  late HttpServer server;
  late Directory tmp;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tmp = await Directory.systemTemp.createTemp('rossi_http_download_');
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  void requireNative() {
    if (!nativeReady) {
      markTestSkipped('原生库加载不了（$nativeError）');
    }
  }

  String url() => 'http://127.0.0.1:${server.port}/blob';

  test('慢但在动：总时长超过上限也必须整份下完', () async {
    requireNative();
    // 10 片、每片间隔 150 ms ≈ 1.5 s，而空闲上限只有 400 ms。
    // 按「整请求超时」实现的话这条必红（就是权重下载那句报错的成因）；
    // 按「多久没新字节算停滞」实现，一片都不会漏。
    server.listen((req) async {
      // 必须关缓冲：Dart 的 HttpResponse 默认把小写入攒到 close 才发，
      // 于是客户端看到的是「0 字节然后一次性全到」——那样这两条测试都在测空转，
      // 而不是测「连接在动」。
      req.response.bufferOutput = false;
      for (var i = 0; i < 10; i++) {
        req.response.write('chunk$i|');
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await req.response.close();
    });

    final out = File('${tmp.path}/whole.bin');
    await WindHttp(receiveTimeout: const Duration(milliseconds: 400)).download(
      url(),
      out.path,
    );

    expect(
      await out.readAsString(),
      'chunk0|chunk1|chunk2|chunk3|chunk4|chunk5|chunk6|chunk7|chunk8|chunk9|',
    );
  });

  test('真停滞：要掐掉，报错说清是停滞，且不留 .part 半截', () async {
    requireNative();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    server.listen((req) async {
      req.response.bufferOutput = false;
      req.response.write('头一片');
      await req.response.flush();
      // 卡到远超空闲上限：这条必须被判定成「停滞」，而不是无限等下去。
      await gate.future;
      req.response.write('永远到不了的 second');
      await req.response.close();
    });

    final out = File('${tmp.path}/stalled.bin');
    Object? error;
    try {
      await WindHttp(receiveTimeout: const Duration(milliseconds: 400)).download(
        url(),
        out.path,
      );
    } catch (e) {
      error = e;
    }
    gate.complete();

    expect(error, isNotNull, reason: '停滞的连接必须报错，不许永远挂着');
    expect(
      error.toString(),
      contains('停滞'),
      reason: '报错要一眼看出是「多久没收到字节」，'
          '而不是让人对着 error decoding response body 猜是超时还是网络被掐',
    );
    expect(
      error.toString(),
      matches(RegExp(r'已收 [1-9]')),
      reason: '必须是「收到过东西之后才停滞」—— 一个字节都没到就掐，'
          '测的是连接没建立，不是停滞',
    );
    expect(out.existsSync(), isFalse, reason: '失败的下载不许留下目标文件');
    expect(
      tmp.listSync().whereType<File>().map((f) => f.path).toList(),
      isEmpty,
      reason: '临时文件（.part）也要清干净，别留半截',
    );
  });
}
