# 阅读背景自适应取色

> 一句话：**从当前这一页已经解出来的像素里采出它的边沿色，压暗之后铺成阅读背景。**
> 采样量与图片尺寸无关，且不在翻页关键路径上。

## 1. 参考实现与它的坑

口径参考 neoview：

- `src/nodes/neoview/features/reader/edgeMatchBackground.ts`
  —— 每条边取 6 个色标（`sampleMaxEdge: 48` 降采样后），拼成四条线性渐变；
  代表色是**四边色标的平均**，不是整页平均。
- `src/nodes/neoview/features/reader/ReaderBackgroundLayer.css`
  —— `transition: background-color 300ms ease`；底色要压暗
  （`brightness(0.48)` / `0.56`）；`prefers-reduced-motion` 时不动画。
- `src/nodes/neoview/features/panels/cards/AmbientBackgroundCard.tsx`
  —— 档位与滑条那一套 UI。

**但 neoview 自己把「边缘匹配」关掉了**，`ReaderBackgroundLayer.tsx` 里写着：

> Edge matching is intentionally disabled: it used a hidden Image decode
> and canvas readback on page changes, competing with Reader rendering.

它的实现是「新建一个 `Image` 再解一遍码 → 画进 48 px 画布 → 回读像素」。
所以它踩的坑**不是采样本身，而是又解了一遍图**。这份实现换掉的就是这一步。

## 2. 架构：采样跟着解码走

```
归档/文件夹 → [Rust] LocalSource 解码出 RGBA ──┬─→ 上屏（原本就有的事）
                                              └─→ ambient::sample_edge_palette
                                                    ↓ 每页一次，存在页缓存里
                              探针 stats_json().ambient
                                                    ↓ 每次翻页一次（关掉则不调）
                        ReaderAmbientStore.palette（独立 ValueNotifier）
                                                    ↓ 只惊动背景层
                        ReaderAmbientBackground（RepaintBoundary 圈住）
```

三点刻意的选择：

1. **采样放在 `CachedPage::new_raw` / `set_pixels` 里**（`rust/gpu_present/src/mac_presenter.rs`）
   —— 插页缓存的是**预取线程**，所以这一步不在翻页关键路径上，而且每页只做一次
   （超分轨不重采：超分只改锐度不改颜色分布）。
2. **过桥的只有颜色**：`stats_json()` 里多一个 `ambient` 字段。这一半 JSON 由 Rust
   自己拼、Dart 自己 `jsonDecode`，**Swift 与 C++ 两侧都不用动** —— 它们把 `probe`
   当不透明字符串转发（`gpu_present_bridge.dart` 里那段注释解释了为什么这么分）。
3. **颜色走独立的 notifier，不进 `GpuPresentController` 的通知**。把颜色并进那个
   `ChangeNotifier` 会让 `ImageSurface` 每次取色到达都 `setState` —— 那正是要防的事。

## 3. 界面上为什么是一层独立的东西

阅读器的底色从前是一路 `Container(color:)` 传下去的。动态色**不能**走那条链路：
颜色来自 `context.select(readSetting)`，一变就是整棵阅读子树（`Stack` /
`InteractiveViewer` / 所有页面节点）重建一次。

所以：

- 静态底色照旧由 `resolveReaderBackgroundColor` 算，`Container(color:)` 保留，
  它是**兜底**，也是取色没到时的样子；
- 自适应颜色只叠在 `ReaderAmbientBackground` 这一层里，它压在页面**下面**、
  被 `RepaintBoundary` 圈住、只监听那一个调色板 notifier。

过渡（300 ms）只在**翻页那一次**跑，跑完静止 —— 不是常驻动画。这也是这里不做
neoview 的「流光溢彩 / 极光 / 聚光灯」那三档的原因：常驻动画在阅读器里是持续的
GPU 开销，与「不能影响阅读」直接冲突。全局关掉动画（`noAnimation`）时连这 300 ms
也省掉。

## 4. 成本

| 环节 | 频率 | 量级 |
|---|---|---|
| 采样 | 每页一次（预取线程） | 四边 × 6 色标 × 3 像素 = 72 次读取；外圈透明时最多再往里试探 16 步 |
| 探针读取 | 每次翻页一次（可关） | 一次跨语言往返 |
| 绘制 | 一次翻页后 300 ms | 5 个矩形（1 纯色 + 4 渐变），**不做模糊** |

判据里有一条直接盯这个性质：`ambient::tests::sample_count_does_not_scale_with_page_size`
—— 一张 10000 px 宽的和一张 100 px 宽的页采出的色标数相同，所以不存在"大图取色变慢"。

## 5. 生效范围

只覆盖**本地漫画**（归档 / 散图文件夹），因为只有那条路是「Rust 解码 → GPU 上屏」，
像素才已经在进程里。在线漫画走 `Image.file`，取色需要另开一条路（复用它已经解好的
`ui.Image`），目前**没做** —— 那些页面上自适应档位等价于 `auto`（跟随主题明暗），
见 `resolveReaderBackgroundColor` 里那两个 `case`。

平台实现目前只有 macOS（`mac_presenter.rs`）。Windows 的 `presenter.rs` 里没有这个
字段，Dart 侧读到缺失就是 `null`，背景层退回静态底色 —— 不会报错，但也没有效果。

## 6. 开关与默认值

- 档位：`ReaderBackgroundMode` 增加 `adaptive`（单色）与 `adaptiveEdge`（边缘渐变）。
  两者都在全局设置里，跨书、跨重启保持 **（不能放阅读页 State —— 换书即重建）**。
- 压暗程度：`readerAmbientDimPercent`，默认 45（= 保留 55% 亮度），范围 0..85。
  默认值取自 neoview 实测的那一档；取色来自页面**边沿**，而漫画页的边沿常常是白纸，
  不压暗就是一块刺眼的光斑。
- 关掉 = 把档位切回固定底色（`auto` / `black` / `white` / `grey`）。
  关掉之后 `_refreshAmbientPalette` **一次都不会被调**，省下的是真实的往返。

## 7. 跨版本（云同步）

`reader` 块的载荷是**整份 `readSetting` 对象**（形状冻结，见 `sync_service.dart` 里
`_settingsBlockKeys` 上的说明），所以新增字段跟着块自动同步。

危险在枚举：`$enumDecode` 碰到不认识的枚举名会**抛异常**，而这一份 JSON 是那台设备
所有阅读设置的载荷 —— 抛一次就是设置全读不出来。因此
`readerBackgroundMode` 上挂了 `@JsonKey(unknownEnumValue: ReaderBackgroundMode.auto)`：
老客户端收到 `adaptive` 时降级成 `auto`（与它自己的能力相符），不会崩。

## 8. 判据

Rust（`cargo test -p rossi_gpu_present --lib`，29 条）：

| 判据 | 守的是什么 |
|---|---|
| `ambient::sample_count_does_not_scale_with_page_size` | 「最高性能」的可校验形式：8 px 与 4000×6000 的页采出的色标数相同 |
| `ambient::left_and_right_edges_are_sampled_from_their_own_side` | 方向没搞反（把 left/right 写反时，纯色页的用例照样全绿） |
| `ambient::top_and_bottom_edges_are_sampled_from_their_own_side` | 同上，上下 |
| `ambient::transparent_border_is_skipped_when_sampling` | 外圈整圈透明时要往里找，而不是答「这一页是黑的」 |
| `ambient::fully_transparent_page_falls_back_to_black` | 真的整页透明就是黑 —— 与上一条区分开 |
| `ambient::probe_json_shape_is_stable` | 过桥的形状（`#rrggbb`、无换行）不漂移 |
| `mac_presenter::test_mac_presenter_init_and_stats` | 未上屏时是字面 `null`，不是缺字段、也不是编一个黑 |
| `mac_presenter::test_ambient_palette_follows_the_shown_page` | 探针里的配色**属于刚 show 的那一页**（含缓存未命中现场解码那条路、换书要清零） |

Dart（`flutter test test/reader/ambient_palette_test.dart`）：

| 判据 | 守的是什么 |
|---|---|
| `fromProbe 缺字段时整份丢掉` | 半份调色板会让某一条边莫名其妙地变黑；整份丢掉只是退回静态底色 |
| `颜色认不出时也整份丢掉` | 「认不出」不等于「就是黑」 |
| `dimmed 50 真的暗了一半` | 压暗写成 `* 0.99` 也算「变了」，但白纸边色照样刺眼 |
| `dimmed 四条边一起压暗` | 只压代表色时单色档看不出、边缘渐变档四条边会亮着 |
| `edgeGradient stop 严格递增` | 位置不递增时整条边糊成一色，观感上只是「渐变不好看」，不会有人去查 |
| `没开自适应档位时画的是静态底色` | 关掉功能真的不生效，而不是「照画但没人看」 |
| `开了自适应但还没有调色板时退回静态底色` | 取色未到时不能黑屏 |
| `边缘渐变档位真的叠出四条边` | 不是只画了个底色 |
| `调色板变化时…换新色且旧色不在了` | 只断言新色的话，叠了一层而旧的没走也能过 |

> 写 widget 判据时注意：测试树里 `MaterialApp` / `Scaffold` 自身带一个**全透明的
> `ColoredBox`**。用 `find.byType(ColoredBox).first` 抓到的是它（`alpha=0`），
> 断言会变成在校验框架而不是校验背景层 —— 必须 `find.descendant` 收窄到
> `ReaderAmbientBackground` 之下。

## 9. 本地跑判据的环境

- Rust：`cd rust && PATH="/opt/homebrew/bin:$PATH" cargo test -p rossi_gpu_present --lib`
  （cargo 在 `/opt/homebrew/bin`，`rust-toolchain.toml` 锁 1.96.1）。
- Flutter：`CARGO_HOME=/opt/homebrew flutter test ...`。
  `hook/build.dart` 调的是 `$CARGO_HOME/bin/rustup`，而本机 rustup 在 `/opt/homebrew/bin`
  而不是默认的 `~/.cargo/bin` —— 不给 `CARGO_HOME` 就会在原生资产构建那步报找不到 rustup。
