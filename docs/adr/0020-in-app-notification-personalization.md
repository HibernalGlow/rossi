# 应用内提示个性化：统一判定口 + 逐事项开关（**已批准** 2026-10-08）

> **状态：已批准。** 立项口径来自用户的一句话：「现在啥通知走同一个通道，特别是同步通知，没过一会儿就弹窗一次，
> 其实还蛮烦的……先统一接口，然后我可以自定义开启或关闭具体的事项，最好使用成熟的库管理，不要手搓。」
> 批准时追加划界：**「Android 渠道我说的一般是指软件内的那个 toast，不是外物的通知系统，那个先不要动」**，
> 并允许新增依赖与改变既有开关语义。

## 为什么要动：立项的那条 bug 是可定位的，不是观感问题

`lib/page/navigation_bar.dart:106` 有一个 `Timer.periodic(Duration(minutes: 5))` 跑 `_autoSync()`。
改造前那个方法里两条腿的待遇不一样：

| 分支 | 位置 | 改造前是否过开关 |
|---|---|---|
| 同步**成功** | `:478` `if (globalState.syncSetting.syncNotify)` | 过 |
| 同步**失败** | `:485` `showErrorToast(...)` | **不过，裸奔** |

于是只要同步配错或者断网，它**每 5 分钟敲一次且永不停**，而用户手上那个「自动同步通知」开关根本管不到它 ——
这正是「以为个性化过了其实没有」的形态。根页面那条 2 秒同文本去重（`:576`）救不了它，因为间隔是 5 分钟。

顺带清点的现状（不是「都走同一个通道」，是三条并行通道）：

- **应用内提示条**：确实是单一漏斗 `lib/widgets/toast.dart` 的 `_showToast`，约 322 处调用点；
  但拿不到 context 时会绕 `eventBus` 上的 `ToastEvent`，由根页面 `navigation_bar.dart:119` 补弹 —— 这是第二条隐形通道。
- **系统通知**：`flutter_local_notifications`（实装 22.3.0），三个生产者
  （`download_notification_reporter.dart:22`、`comic_follow_service.dart:112`、`foreground_task_service.dart:140`）。
- **裸 SnackBar**：15 处 `ScaffoldMessenger.of(...).showSnackBar`，零封装。
- **手写去重两份**：根页面 2 秒（`navigation_bar.dart:576`）、阅读器切换提示 500 ms（`switch_toast_service.dart:28`）。
- **一条完全没去重的通道**：插件脚本的 `flutter.showToast`（`dart_tools_bridge.dart:58-74`），
  脚本可以在一次抓取的循环里逐章连发。

## 决定

### 1. 判定与渲染分成两层，判定层只有一个入口

新增 `lib/service/notify/`：

```
调用点 ──► NotifyGateway.submit ──► 门禁(_allows) ──► 节流(_admit) ──► 唯一渲染器 ──► ToastOverlayController
```

- `lib/widgets/toast.dart` 仍然是外观层的门面：四个 `show*Toast` 签名**一字未动**（322 处调用点零改动），
  内部改为提交给网关；新增 `notifyAmbient(topic, …)` 给后台事项用。
- **出口内置，不要求宿主先挂东西**：网关的默认渲染器就是提示条（`renderOnToastOverlay`），
  上下文在弹的那一刻现取 —— 调用点的 context 优先，回落到 `navigatorKey.currentContext`。
  第一版我做成「`main()` 里 `attachToastRenderer()` 挂一次，没挂上就丢弃并记日志」，
  被一条既有判据抓到回归：`test/comic_read/reader_top_bar_layout_test.dart` 那条
  「占位按钮不能静默失效」的用例在只搭测试宿主、不走 app 启动流程的场景里直接收不到提示。
  那条隐式前提既会吞掉启动极早期（首帧前）的真提示，也会让任何独立入口静默失效，所以删掉。
- `ToastEvent` 与 eventBus 那一跳**删除**；根页面那条 2 秒手写去重**删除**，语义并入网关（`NotifyTopic.action` 的窗口就是 2 秒）。

**管线是同步写的，不是 `async*` + `StreamTransformer.bind`**：探针实测证明，
生成器里那层 `await for` 是延迟订阅的，`attach()` 之后同步 `add` 进来的第一条会被不缓冲的 `PublishSubject` 吞掉
（`test/service/_notify_probe_test.dart`，已跑已删）。逐键的窗口记账本来也是应用语义，库不知道「什么算同一件事」。

rxdart 承担的就是传输这一段（`PublishSubject` + `where`），这是它值当一个依赖的地方；
`pubspec.yaml` 里它紧挨着 `event_bus` 放，注释写明用途。

### 2. 事项登记表决定「归不归你关」，而不是所有提示都能关

`NotifyTopic` 每项带三件事：稳定 `id`、`policy`、`throttle` 窗口。`policy` 三态：

| policy | 谁能关 | 理由 |
|---|---|---|
| `actionFeedback` | **谁也都关不掉**（连总闸都不管） | 点了收藏却一声不响，用户读到的是「按钮坏了」。这是可观测性，不是骚扰 |
| `ambient` | 总闸 + 逐事项开关 + 节流窗口 | 「没过一会儿弹一次」全部来自这一类 |
| `selfManaged` | 由它自己的设置块管 | 阅读器切书/翻页/触边界已有 `SwitchToastSettingState` 三条开关；再造一份同名开关就是第二个真源 |

事件上的 `userInitiated` 是第四道口子：同一件事既可能由定时器触发也可能由按钮触发时（手动同步、手动刷新追更），
调用点显式标 `true`，该次按操作反馈直通。

已登记的 `ambient` 事项八条：自动同步成功 / 自动同步失败 / 下载完成 / 下载失败 / 追更更新 /
插件脚本报信 / 外部打开 / 通知权限。设置页遍历 `NotifyTopic.ambientTopics` 自动长出来，
新增事项不必改页面代码。

### 3. 存储只放「偏离」，默认值住在登记表

`NotifySettingState`（`lib/config/global/parts/global_setting_notify_part.dart`）：
`enabled` 总闸 + `Map<String, bool> topics` 覆盖。

- **键用稳定字符串而不是枚举**：这一份 JSON 属于全局设置块，`json_serializable` 对枚举键走 `$enumDecode`，
  碰到不认识的枚举名会**抛异常**，把那台设备上这一整块一起读失败 —— 同一个坑的现场记录写在
  `ReadSettingState.readerBackgroundMode`（`global_setting.dart:400` 附近）。字符串键把「新版本新增了事项」
  降级成「本机没登记过该项」，由该事项的出厂默认接住。
- **默认值不住在存储里**：`NotifyTopic.defaultEnabled` 是唯一出处，于是「恢复默认」与「未登记时回落」用的是同一个数。
  写回时若与默认一致就**删掉这一项**，这张表不会永远只增不减，也让「这一项我没动过」在载荷里看得出来。
- 读入口 `notifySetting` 与 `toastSetting` 同一条防御口径：库没起来就回落默认值，绝不让「读设置」把提示炸掉。

### 4. 节流：合并的是「同一件事」，不是「同一句话」

`dedupKey = 事项 id + 标题 + 正文`。带上正文是刻意的：「《A》下载完成」和「《B》下载完成」是两件不同的事，
压成一条就是丢信息；而自动同步失败每次都是同一句，那才是要压的那个。

被窗口压掉的条数**不丢**，挂到窗口过期后放行的那一条尾部（「（另有 N 次同类提示）」）。
刻意**不**排一条「窗口结束的总结弹窗」：那还是一条弹窗，只是换时间出现。

窗口长度按事项定在登记表里（自动同步 10 分钟、下载 60 秒、追更 5 分钟、插件脚本 3 秒、
通知权限 30 分钟、`action` 沿用改造前的 2 秒、`selfManaged` 为 `null`）。

### 5. 裸 SnackBar 收编（15 处）

改判据前先量过：`rg` 过一遍全部 15 处的 `SnackBar(`，**没有一处带 `action:`**，全是纯文本 ——
所以换成提示条不丢撤销/重试这类按钮能力。类型按语义分（复制成功→success、报错→error、配置问题→warning）。

### 6. `syncNotify` 退役，不再留第二个开关

用户批准「允许改变语义」。落点：

- `SyncSettingState.syncNotify` 字段删除（`global_setting.dart`），同步设置页那行开关删除，
  两条 i18n 键删除，新的 `settings.notify*` 28 条键补上。
- 老载荷里多出来的 `syncNotify` 键会被 `fromJson` 忽略（不报错）；老客户端读到没有这个键的新载荷时按默认 `true` 走。
- **接受的一次性代价**：以前把 `syncNotify` 关过的人，升级后「自动同步完成」这一项会回到开
  （但失败那条从此受 10 分钟窗口管，这正是立项要修的东西）。不做「从旧字段迁移」的兼容层 ——
  那会留下一个 UI 上看不见却影响判断的输入。

## 明确不做（本轮划的界）

1. **系统通知那一路完全不动**：`flutter_local_notifications` 的调用、Android 通知渠道、前台服务通知一律原样。
   后果要说明白：把「下载完成」「追更更新」在提示个性化里关掉，**只安静掉应用内那半条**，
   通知栏那半条照旧响；要一起安静得动系统层，本轮不做。设置页底部有一行说明这条边界。
2. **不做「前台只弹应用内 / 后台只发系统通知」的路由**：那要求改系统通知的发送时机，与 1 冲突。
3. **`notifySetting` 不进云同步名单**（`sync_service_rossi_part.dart` 的块名表）。
   那是本机音量级的偏好，跨设备同步反而会在这台机上把刚关掉的提示叫醒；
   要同步就是一行数组的事，且那个文件此刻在别的 lane 里是脏的，不硬碰。
4. **不换渲染层**：仓库里 `toastification: ^3.0.1`（`pubspec.yaml:33`）是**已声明但零引用**的依赖
   （实测 `rg toastification lib` 无命中）。它的 `ToastificationConfig` 覆盖得住
   `alignment`/`itemWidth`/`animationDuration`/`maxToastLimit`/`marginBuilder`，
   3.2.0 的 `showCustom` 还允许 `BuildContext?` 为空并回落到全局 `ToastificationWrapper` ——
   也就是说本仓那 915 行自研提示条（`widgets/toast/toast_overlay.dart` + `toast_card.dart` + `util/toast/toast_style.dart`）
   原则上可以退役。本轮不做，因为换渲染层**对本用户抱怨的那件事一点帮助都没有**，
   而代价是 5 个平台的视觉无法在本机全部回读 + 重写 `test/widgets/toast_test.dart` 的 4 条判据。等点名再做。

## 证据分级

| 结论 | 等级 |
|---|---|
| 立项那条 bug（`:478` 过门禁、`:485` 不过） | 本机读代码实测，行号可回读 |
| 322 处提示调用 / 15 处 SnackBar / 无 `action:` | 本机 `rg` 计数，脚本按文件报数 |
| `async*` 生成器吞第一条 | 本机探针实测（`+0` 条送达），不是推测 |
| 「出口要先手动挂」这条隐式前提会吃掉反馈 | 本机 `flutter test` 抓到：`reader_top_bar_layout_test` 的「占位不能静默失效」用例实测收不到提示（日志里就是那句「渲染器尚未挂载，丢弃」），据此改设计 |
| 门禁与节流的 12 条判据 | 本机 `flutter test`，含阳性对照 |
| `unknownEnumValue` 那类枚举解码崩 | 沿用仓内既有记录（`readerBackgroundMode` 注释） |
| 设置页与提示条在五端的**观感** | **未实机验证**，见验收清单 |

## 验收（交付时的编号清单）

1. 设置 → 提示个性化：能看到八项后台事项 + 总闸；关掉「自动同步失败」后，把 WebDAV 地址改成一个不存在的 host，
   等两轮 5 分钟定时器，**一次都不响**。
2. 不关开关时：失败提示第一次照响，第二次起 10 分钟窗口内不重复；窗口过后若还在失败，那条尾部带「（另有 N 次同类提示）」。
3. 总闸关掉后，点收藏、点保存仍应有回应（这是判据，不是回归）。
4. 手动同步（同步设置页里点「立即同步」）不受任何静音影响。
5. 下载完成/追更：应用内那半条能被关；**通知栏那半条仍会响**，这是划定的界，不是 bug。
   安卓上「下载完成」这条**本来就没有应用内那半条**（`download_queue_manager.dart:370` 那个
   `!Platform.isAndroid` 分支，改造前就如此），所以在安卓上它没有可关的东西 —— 不是漏接线。

## 未决

- 换 `toastification` 作为渲染层（见「明确不做」§4 的量数），要不要做由用户点名。
- 逐事项的**窗口长度**目前是写死的常数。要不要开放成一个可调项（例如「重复提示至少隔 N 分钟」），
  本轮没做，因为用户要的是「能不能关」，不是「隔多久」。
