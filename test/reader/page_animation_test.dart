import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/reader/page_animation.dart';

/// 容器嗅探与「按后缀就知道会不会动」这两条判定的测试。
///
/// 夹具全部**按容器规范手写字节**（与 Rust 侧 `local_core/src/animation.rs`
/// 的夹具同一份结构，两边对拍），不依赖仓库里的二进制样本。
void main() {
  List<int> pngChunk(String fourcc, List<int> payload) => <int>[
    ..._u32be(payload.length),
    ...fourcc.codeUnits,
    ...payload,
    ...List<int>.filled(4, 0), // CRC 占位
  ];

  List<int> png(List<List<int>> chunks) => <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunks.expand((List<int> c) => c),
  ];

  List<int> riffChunk(String fourcc, List<int> payload) => <int>[
    ...fourcc.codeUnits,
    ..._u32le(payload.length),
    ...payload,
    if (payload.length.isOdd) 0, // RIFF 块奇数长度补一字节
  ];

  List<int> webp(List<List<int>> chunks) {
    final body = chunks.expand((List<int> c) => c).toList();
    return <int>[
      ...'RIFF'.codeUnits,
      ..._u32le(4 + body.length),
      ...'WEBP'.codeUnits,
      ...body,
    ];
  }

  /// 与 `riffChunk` 同一份排布（fourcc 在前、size 在后），只是 payload 定长 10。
  List<int> vp8x(int flags) => <int>[
    ...'VP8X'.codeUnits,
    ..._u32le(10),
    // payload = flags(1) + 保留(3) + canvas width-1(3) + canvas height-1(3)
    flags,
    ...List<int>.filled(9, 0),
  ];

  group('animatedContainerHead', () {
    test('APNG 看 acTL 的帧数，不看块在不在', () {
      final threeFrames = png(<List<int>>[
        pngChunk('IHDR', List<int>.filled(13, 0)),
        pngChunk('acTL', <int>[0, 0, 0, 3, 0, 0, 0, 0]),
        pngChunk('IDAT', <int>[1, 2, 3]),
      ]);
      expect(animatedContainerHead(threeFrames), isTrue);

      // 单帧 acTL 与静图无异，不能因为「有 acTL」就换渲染路径。
      final oneFrame = png(<List<int>>[
        pngChunk('IHDR', List<int>.filled(13, 0)),
        pngChunk('acTL', <int>[0, 0, 0, 1, 0, 0, 0, 0]),
        pngChunk('IDAT', <int>[1, 2, 3]),
      ]);
      expect(animatedContainerHead(oneFrame), isFalse);

      expect(
        animatedContainerHead(
          png(<List<int>>[
            pngChunk('IHDR', List<int>.filled(13, 0)),
            pngChunk('IDAT', <int>[1, 2, 3]),
            pngChunk('acTL', <int>[0, 0, 0, 9, 0, 0, 0, 0]),
          ]),
        ),
        isFalse,
        reason: '扫到 IDAT 就该收手：acTL 的合法位置只在图像数据之前',
      );

      expect(
        animatedContainerHead(
          png(<List<int>>[
            pngChunk('IHDR', List<int>.filled(13, 0)),
            pngChunk('gAMA', <int>[0, 0, 123, 45]),
            pngChunk('pHYs', List<int>.filled(9, 0)),
            pngChunk('acTL', <int>[0, 0, 0, 2, 0, 0, 0, 1]),
            pngChunk('fcTL', List<int>.filled(26, 0)),
          ]),
        ),
        isTrue,
        reason: '块之间的全局杂项要被跳过而不是被误判',
      );
    });

    test('静图 PNG / 非 PNG 字节都不算动图', () {
      final still = png(<List<int>>[
        pngChunk('IHDR', List<int>.filled(13, 0)),
        pngChunk('IDAT', <int>[1, 2, 3]),
      ]);
      expect(animatedContainerHead(still), isFalse);
      expect(animatedContainerHead('not an image'.codeUnits), isFalse);
      expect(animatedContainerHead(<int>[]), isFalse);
    });

    test('动图 WebP 认 VP8X 标志位，也认 ANIM / ANMF 块', () {
      // 真机排布：第一个块**必须**是 VP8X，ANIM 在它之后 ——
      // 所以「偏移 12 == ANIM」那种判定永远不成立（仓库里原有那条即是如此）。
      expect(
        animatedContainerHead(
          webp(<List<int>>[
            riffChunk('VP8X', <int>[0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            riffChunk('ANIM', <int>[0, 0, 0, 0, 0, 0]),
            riffChunk('ANMF', List<int>.filled(16, 0)),
          ]),
        ),
        isTrue,
      );

      // 只有 VP8X、ANMF 还在头部之外时，靠 animation 标志位（bit1）也要认。
      expect(
        animatedContainerHead(webp(<List<int>>[vp8x(0x12)])),
        isTrue,
        reason: 'alpha(bit2) + animation(bit1)',
      );

      expect(
        animatedContainerHead(
          webp(<List<int>>[riffChunk('VP8 ', List<int>.filled(10, 0))]),
        ),
        isFalse,
      );
      expect(
        animatedContainerHead(webp(<List<int>>[vp8x(0x04)])),
        isFalse,
        reason: '只有 alpha 位、没有 animation 位的扩展格式静图',
      );
    });

    test('头部不够长时宁可漏判', () {
      final animated = webp(<List<int>>[
        riffChunk('VP8X', <int>[0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        riffChunk('ANIM', <int>[0, 0, 0, 0, 0, 0]),
      ]);
      expect(animatedContainerHead(animated.sublist(0, 10)), isFalse);
    });
  });

  group('按后缀判', () {
    test('gif / apng 后缀本身就说得出会动', () {
      expect(animatedByExtensionName('motion.gif'), isTrue);
      expect(animatedByExtensionName('MOTION.GIF'), isTrue);
      expect(animatedByExtensionName('vol.1/loop.apng'), isTrue);
    });

    test('wbp 只是一颗改名的 WebP，不保证会动（neoview media.ts:13）', () {
      expect(animatedByExtensionName('page03.wbp'), isFalse);
      expect(
        needsContainerProbe('page03.wbp'),
        isTrue,
        reason: '伪装表把它归一成 webp，于是与 .webp 一样要查容器',
      );
    });

    test('静图多于动图的档必须查容器，不能按名字接管', () {
      for (final name in ['page01.webp', 'page01.png', 'page01.jpg']) {
        expect(animatedByExtensionName(name), isFalse);
      }
      expect(needsContainerProbe('page01.webp'), isTrue);
      expect(needsContainerProbe('page01.png'), isTrue);
      expect(needsContainerProbe('page01.jpg'), isFalse);
    });

    test('目录名里的点不是后缀', () {
      expect(animatedByExtensionName('a.gif/b.png'), isFalse);
      expect(animatedByExtensionName('no extension'), isFalse);
    });
  });

  group('localPageIsAnimated', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('anim_probe'));
    tearDown(() => temp.deleteSync(recursive: true));

    Future<String?> pathOf(String name, List<int> bytes) async {
      final file = File('${temp.path}/$name')..writeAsBytesSync(bytes);
      return file.path;
    }

    test('散图按头部实测：动图 webp 认得出，静图 webp 不误伤', () async {
      final animated = webp(<List<int>>[
        riffChunk('VP8X', <int>[0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        riffChunk('ANIM', <int>[0, 0, 0, 0, 0, 0]),
      ]);
      final still = webp(<List<int>>[
        riffChunk('VP8 ', List<int>.filled(10, 0)),
      ]);

      expect(
        await localPageIsAnimated(
          name: 'p.webp',
          directPath: () async => pathOf('p.webp', animated),
        ),
        isTrue,
      );
      expect(
        await localPageIsAnimated(
          name: 'p.webp',
          directPath: () async => pathOf('p.webp', still),
        ),
        isFalse,
      );
    });

    test('归档内不做容器嗅探：只认后缀说得出的那几档', () async {
      Future<String?> noPath() async => null;
      expect(
        await localPageIsAnimated(name: 'p.gif', directPath: noPath),
        isTrue,
      );
      expect(
        await localPageIsAnimated(name: 'p.webp', directPath: noPath),
        isFalse,
        reason: '查头部要整条 inflate，代价落在翻页关键路径上（见函数注释）',
      );
    });

    test('文件读不到时答不是动图，不抛', () async {
      expect(
        await animatedFileHead(File('${temp.path}/missing.webp')),
        isFalse,
      );
    });
  });
}

List<int> _u32be(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> _u32le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];
