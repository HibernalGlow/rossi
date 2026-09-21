import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/util/path_util.dart';

/// `isLocalComicSource` 的判据。
///
/// 背景（真实回归）：旧实现判 Windows 盘符用的是 `contains(':/')`，
/// 而**任何** `http://` / `https://` 串都含 `:/`；`//host/…` 又以 `/` 开头。
/// 于是 `getCachePicture` / `downloadImageWithRetry` /
/// `reader_image_prefetch_controller` 里的「本地来源」守卫对**任何网络图片地址**
/// 都为真 —— 请求根本没发出去，`getCachePicture` 直接返回哨兵串 `'404'`，
/// 界面上就是 404 占位图（wnacg 的图床 `img5.wnimg2.cfd` 即如此）。
///
/// 因此这里必须成对断言：网络地址**不再**被判成本地，
/// 同时真正的本地路径**不能**被误伤（只改一头的"修复"会把本地漫画读坏）。
void main() {
  group('网络地址不是本地来源（原回归的正向判据）', () {
    // wnacg 图床的真实形态：`?verify=<时间戳>-<HMAC>` 签名 + http 协议。
    const wnacgImageUrl =
        'http://img5.wnimg2.cfd/data/3858/21/0001.webp'
        '?verify=1789797600-yqTUog0tCMwMdZEOqn0HwA9gDootMI9XHanhUVgz5Wg';

    test('http/https 图片地址（含签名串）判为非本地', () {
      expect(isLocalComicSource('wnacg', wnacgImageUrl), isFalse);
      expect(
        isLocalComicSource(
          'wnacg',
          wnacgImageUrl.replaceFirst('http:', 'https:'),
        ),
        isFalse,
      );
      expect(
        isLocalComicSource('wnacg', 'https://t4.wnimg2.cfd/data/t/1.png'),
        isFalse,
      );
    });

    test('协议相对地址 //host/... 判为非本地（首段是主机名）', () {
      expect(
        isLocalComicSource('wnacg', '//img5.wnimg2.cfd/data/3858/21/1.webp'),
        isFalse,
      );
      expect(isLocalComicSource('wnacg', '//localhost:8080/a.jpg'), isFalse);
    });

    test('URL 以归档扩展名结尾也仍是非本地（扩展名分支不得抢先命中）', () {
      expect(
        isLocalComicSource('plugin-a', 'https://cdn.example.com/a.zip'),
        isFalse,
      );
      expect(
        isLocalComicSource('plugin-a', 'http://cdn.example.com/b.cbz'),
        isFalse,
      );
    });

    test('isNetworkAddress 自身：URL 为真，路径为假', () {
      expect(isNetworkAddress('http://a.b/c'), isTrue);
      expect(isNetworkAddress('HTTPS://A.B/C'), isTrue);
      expect(isNetworkAddress('//img5.wnimg2.cfd/x'), isTrue);
      expect(isNetworkAddress('/Users/glow/comics'), isFalse);
      expect(isNetworkAddress('//foo/bar'), isFalse); // POSIX 双斜杠路径
      expect(isNetworkAddress('C:/comics'), isFalse);
    });
  });

  group('真正的本地来源仍必须为真（防过度修复）', () {
    test('POSIX 绝对路径与双斜杠路径', () {
      expect(isLocalComicSource('plugin-a', '/Users/glow/comics/a'), isTrue);
      expect(isLocalComicSource('plugin-a', '//foo/bar'), isTrue);
    });

    test('Windows 盘符路径（必须是串首的盘符）', () {
      expect(isLocalComicSource('plugin-a', r'C:\comics\a'), isTrue);
      expect(isLocalComicSource('plugin-a', 'c:/comics/a'), isTrue);
      // 锚定的意义：非串首的 `:/` 不再被当成盘符。
      expect(isLocalComicSource('plugin-a', 'note:/comics/a'), isFalse);
    });

    test('归档路径（相对路径 + 扩展名）', () {
      for (final ext in const ['zip', 'cbz', 'rar', 'cbr', '7z', 'tar']) {
        expect(
          isLocalComicSource('plugin-a', 'comics/a.$ext'),
          isTrue,
          reason: '.$ext 归档应判为本地',
        );
      }
    });

    test('from 为 local / local_source 时短路为真（封面与归档都走这条）', () {
      expect(isLocalComicSource('local', ''), isTrue);
      expect(isLocalComicSource('local_source', 'whatever'), isTrue);
      // 短路优先于网络判定：本地会话里 url 字段可能是任意串。
      expect(
        isLocalComicSource('local', 'http://img5.wnimg2.cfd/a.webp'),
        isTrue,
      );
    });

    test('普通插件 id / 漫画 id 判为非本地（否则会绕开插件运行时）', () {
      expect(isLocalComicSource('wnacg', '385821'), isFalse);
      expect(isLocalComicSource('plugin-a', 'comic/385821/1.jpg'), isFalse);
      expect(isLocalComicSource('plugin-a', ''), isFalse);
    });
  });

  group('相邻工具函数', () {
    test('extractImageExtension 取路径扩展名，不吃查询串', () {
      expect(
        extractImageExtension(
          'http://img5.wnimg2.cfd/data/3858/21/0001.webp?verify=1789797600-abc',
        ),
        'webp',
      );
      expect(extractImageExtension('/tmp/a.CBZ'), 'cbz');
      expect(extractImageExtension('no-extension'), 'jpg');
    });
  });

  group('本地分支守卫（图片层：网络请求不得命中本地分支）', () {
    const wnacgImageUrl =
        'http://img5.wnimg2.cfd/data/3858/21/0001.webp'
        '?verify=1789797600-yqTUog0tCMwMdZEOqn0HwA9gDootMI9XHanhUVgz5Wg';

    // 这一条就是"超分是否可达"的根判据：本地分支是早返回，位置在网络下载与
    // **全部**超分调用之前。网络请求一旦落进本地分支，超分段整段被跳过。
    test('网络页面请求不进本地分支 ⇒ 网络分支（含超分段）可达', () {
      expect(
        isLocalPictureRequest(
          from: 'wnacg',
          cartoonId: '385821',
          url: wnacgImageUrl,
          extern: const {'priority': 0},
        ),
        isFalse,
      );
      expect(
        isLocalPictureRequest(
          from: 'wnacg',
          cartoonId: '385821',
          url: '//img5.wnimg2.cfd/data/3858/21/1.webp',
        ),
        isFalse,
      );
      // 图片层会把它当 url 传，因此这里也必须为假（否则下载队列直接抛 notFound）。
      expect(isLocalPictureRequest(from: 'wnacg', url: wnacgImageUrl), isFalse);
      // 对照：同一组 from/cartoonId 只把 url 换成归档路径，就必须翻成 true。
      // 少了这一对，"url 子句被摘掉"也能骗过上面两条（cartoonId 恰好无害）。
      expect(
        isLocalPictureRequest(
          from: 'wnacg',
          cartoonId: '385821',
          url: '/comics/a.cbz',
        ),
        isTrue,
      );
    });

    test('本地 GPU 呈现会话仍进本地分支（超分归呈现器，不走图片层）', () {
      expect(
        isLocalPictureRequest(
          from: 'local',
          cartoonId: '/comics/a.zip',
          url: '/comics/a.zip',
          extern: const {'isLocalGpu': true},
        ),
        isTrue,
      );
      // isLocalGpu 单独成立即短路，即使 from 是插件 id、url 是网络地址。
      expect(
        isLocalPictureRequest(
          from: 'wnacg',
          cartoonId: '385821',
          url: wnacgImageUrl,
          extern: const {'isLocalGpu': true},
        ),
        isTrue,
      );
    });

    test('本地路径 / 归档形态仍进本地分支', () {
      expect(
        isLocalPictureRequest(from: 'plugin-a', url: '/tmp/a.cbz'),
        isTrue,
      );
      expect(
        isLocalPictureRequest(from: 'plugin-a', cartoonId: 'comics/a.7z'),
        isTrue,
      );
    });
  });
}
