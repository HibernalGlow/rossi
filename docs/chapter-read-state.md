# 章节已读 / 未读：两套事实的口径

> 适用范围：漫画详情页章节列表、追更页徽标与未读数、数据同步与备份。
> 相关代码：`lib/page/comic_info/models/chapter_read_state.dart`（纯策略）、
> `lib/service/reader/chapter_read_mark_service.dart`（存储）、
> `lib/page/comic_info/widgets/episode_read_mark_controller.dart`（详情页控制器）、
> `lib/object_box/model.dart` 的 `ComicChapterReadMark` 与 `UnifiedComicHistory`。

## 1. 为什么需要这一层

在此之前，本仓**没有**「某一章已读」这个事实。全库只有一行 `UnifiedComicHistory`
（每部漫画一行），它记的是书签：`chapterOrder` + `pageIndex`。于是「已读」只能这样推断：
`chapter.order <= 书签序号` ⇒ 算读过。

这个推断带来两个做不到：

1. 不打开章节就没法把某一章标成已读或**未读**（标未读更做不到 —— 前缀推断里
   「读过第 80 章」必然把 1..80 全算成已读）。
2. 想批量补标记，只能改书签，而书签同时是「继续阅读」的定位点与追更统计的基线，
   一改就把进度和统计一起弄乱。

上游 `deretame/Breeze` 同样没有这一层（`upstream/main` 里 `hasRead` / `markAsRead` /
章节状态表都为零命中，只有追更页那个漫画级的 `markAllAsRead` 对齐 `lastChapterCount`），
所以这不是「上游已有、本仓又写一份」的重叠实现，AGENTS §13 的上游优先判定不适用。

## 2. 两套事实，各自的唯一写入方

| 事实 | 存储 | 唯一写入方 | 谁读它 |
|------|------|------------|--------|
| **实际读到哪里** | `UnifiedComicHistory.chapterOrder` / `pageIndex` | 阅读器周期保存（`ReaderHistoryService`） | 继续阅读定位、追更基线、章节行推断已读 |
| **用户人为判决** | `ComicChapterReadMark`（一章一行） | 详情页标记操作 | 章节行状态、追更未读数的修正项 |

硬规矩：

- 标记操作**不写**书签行。所以「手动把第 80 章标成已读」不会让「继续阅读」跳到 80 章，
  也不会把 `pageIndex` 抹成别的位置。
- 阅读进度**不删**标记行。读到第 81 章不会把用户手标的第 80 章「未读」悄悄洗掉。
- 从书架/历史里移除一部漫画**不级联**删标记。现状就是每张表只墓碑化自己那行
  （`removeShelfEntryFromHistory` 既不碰追更行也不碰单本偏好），
  清空阅读历史更不该顺手毁掉用户手动打的标记。
- 追更页的 `lastChapterCount`（「上次看到这儿的章数」）仍然只由追更流程自己维护，
  它是**徽标基线**，含义不是「读过」。所以它不参与章节行的显示判定 ——
  否则从没打开的章节会显示成已读。

## 3. 合成规则（`ChapterReadStateModel.stateOf`）

一个章节显示成什么，是这三项的合成，四个状态各自可辨：

```
有标记行 ⇒ markedRead ? 已标记已读 : 已标记未读      // 人为判决优先，且能压过推断
无标记行 ⇒ order <= 书签序号 ? 读到过 : 未读          // 只有书签参与推断
```

`manualUnread` 必须是**存行**而不是删行：删行会退回前缀推断，那一章又变回已读。
这就是实体里 `markedRead` 是 bool 而不是「只有已读才建行」的原因。

## 4. 追更未读数怎么算（`unreadChapterCountWithMarks`）

前缀基线不变，人为标记只作为**窗口内的修正项**：

```
baseline   = clamp(max(书签序号, lastChapterCount), 0, detectedChapterCount)
前缀未读   = clamp(detectedChapterCount - baseline, 0, detectedChapterCount)
多算       = 标记为未读、且 order <= baseline 的章数        // 显式拉回未读
少算       = 标记为已读、且 baseline < order <= detected 的章数 // 提前认了这些章
未读章数   = clamp(前缀未读 + 多算 - 少算, 0, detectedChapterCount)
```

三条口径要说清：

- **没有任何标记时，结果与旧公式逐位相同。** 这条恒等由
  `test/comic_info/chapter_read_state_test.dart` 遍历参数空间证明，
  它就是「别把追更统计弄乱」的机器门禁：不点标记的用户，数字一个都不会变。
- 徽标仍然只在 `hasUpdate` 为真时亮。**人为标未读不会凭空制造「有更新」**，
  它只调整既有更新窗口里的未读章数。没在追更的漫画、或已经追上进度的漫画，
  标未读只改详情页章节行的显示，不改追更页的徽标。
- 超出 `detectedChapterCount` 的标记不参与统计：那一章不在这一轮更新窗口里。
- 追更页的**进度条**仍然只画 `history.chapterOrder / detectedChapterCount`
  （`followReadProgress`）—— 它是「实际读到哪里」的可视化，人为标记不画进那条进度里。
  未读徽标才是被修正的那个数。
- 追更页的「全部标为已读」会把它清掉的每条漫画里**人为标未读**的章节标记一起墓碑化。
  不做这件事，一条手标的未读会让这个按钮按下去永远清不掉（未读项恒 > 0）；
  它替代的是逐章的未读判决，仍然不写书签行。

## 5. 入口与交互

- 章节行**前导槽位**（原来只在多选模式放选中勾）平时显示标记态，是四个状态里
  两个「人为」状态的唯一视觉出口：
  - 轻点 = 在这章的 已读 / 未读 之间直接翻转（最常见的两个动作一步完成）
  - 长按 = 弹「阅读状态」面板，列出 标记已读 / 标记未读 / 标记至此为已读 / 清除标记
- 多选底栏（`_SelectionActionBar`）加 标记已读 / 标记未读 两个按钮，作用于当前选中集，
  这就是「批量修改阅读状态」。选中态复用 `EpisodeDownloadController` 的
  `selectedIds` / `selectionCubit`，**不建第二套选中模型**。
- 进入多选不再要求插件允许下载：阅读标记与下载能力无关。下载/删除按钮在插件不允许时
  仍然禁用，禁用原因照旧走原来的 toast。
- 阅读器不改：读完一章依旧只推进书签；书签推过的章在行上显示为「读到过」。

## 6. 同步与备份

`ComicChapterReadMark` 带 `uniqueKey` / `updatedAt` / `deleted` / `schemaVersion`，
与历史表同一套 LWW 口径，登记在三处，缺一处就是静默丢数据：

- `comic_sync_core.dart` 的 `mergeUnifiedData`（按 `uniqueKey` 合并，`updatedAt` 大者胜）
- `object_box.dart` 的 `_collectObjectBoxDataJson`（启动快照 + 手动备份的取数）
- `backup_codec.dart` 的 `parsers`（恢复时先全量反序列化再清库）
