///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsZhCn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zhCn,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh-CN>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	dynamic operator[](String key) => _meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$workspace$zh_CN workspace = Translations$workspace$zh_CN.internal(_root);

	/// zh-CN: 'Rossi'
	String get appName => 'Rossi';

	late final Translations$common$zh_CN common = Translations$common$zh_CN.internal(_root);
	late final Translations$error$zh_CN error = Translations$error$zh_CN.internal(_root);
	late final Translations$navigation$zh_CN navigation = Translations$navigation$zh_CN.internal(_root);
	late final Translations$settings$zh_CN settings = Translations$settings$zh_CN.internal(_root);
	late final Translations$bookshelf$zh_CN bookshelf = Translations$bookshelf$zh_CN.internal(_root);
	late final Translations$comicInfo$zh_CN comicInfo = Translations$comicInfo$zh_CN.internal(_root);
	late final Translations$reader$zh_CN reader = Translations$reader$zh_CN.internal(_root);
	late final Translations$plugin$zh_CN plugin = Translations$plugin$zh_CN.internal(_root);
	late final Translations$gestureLock$zh_CN gestureLock = Translations$gestureLock$zh_CN.internal(_root);
	late final Translations$appBootstrap$zh_CN appBootstrap = Translations$appBootstrap$zh_CN.internal(_root);
	late final Translations$comments$zh_CN comments = Translations$comments$zh_CN.internal(_root);
	late final Translations$cache$zh_CN cache = Translations$cache$zh_CN.internal(_root);
	late final Translations$dataBackup$zh_CN dataBackup = Translations$dataBackup$zh_CN.internal(_root);
	late final Translations$webdavSync$zh_CN webdavSync = Translations$webdavSync$zh_CN.internal(_root);
	late final Translations$ocr$zh_CN ocr = Translations$ocr$zh_CN.internal(_root);
	late final Translations$realSr$zh_CN realSr = Translations$realSr$zh_CN.internal(_root);
	late final Translations$about$zh_CN about = Translations$about$zh_CN.internal(_root);
	late final Translations$oldHome$zh_CN oldHome = Translations$oldHome$zh_CN.internal(_root);
	late final Translations$more$zh_CN more = Translations$more$zh_CN.internal(_root);
	late final Translations$search$zh_CN search = Translations$search$zh_CN.internal(_root);
	late final Translations$discover$zh_CN discover = Translations$discover$zh_CN.internal(_root);
	late final Translations$searchResult$zh_CN searchResult = Translations$searchResult$zh_CN.internal(_root);
	late final Translations$comicList$zh_CN comicList = Translations$comicList$zh_CN.internal(_root);
	late final Translations$comicEntry$zh_CN comicEntry = Translations$comicEntry$zh_CN.internal(_root);
	late final Translations$comicFollow$zh_CN comicFollow = Translations$comicFollow$zh_CN.internal(_root);
	late final Translations$changelog$zh_CN changelog = Translations$changelog$zh_CN.internal(_root);
	late final Translations$webview$zh_CN webview = Translations$webview$zh_CN.internal(_root);
	late final Translations$oldRanking$zh_CN oldRanking = Translations$oldRanking$zh_CN.internal(_root);
	late final Translations$login$zh_CN login = Translations$login$zh_CN.internal(_root);
	late final Translations$fontSetting$zh_CN fontSetting = Translations$fontSetting$zh_CN.internal(_root);
	late final Translations$download$zh_CN download = Translations$download$zh_CN.internal(_root);
	late final Translations$foregroundTask$zh_CN foregroundTask = Translations$foregroundTask$zh_CN.internal(_root);
	late final Translations$notification$zh_CN notification = Translations$notification$zh_CN.internal(_root);
	late final Translations$update$zh_CN update = Translations$update$zh_CN.internal(_root);
	late final Translations$dialog$zh_CN dialog = Translations$dialog$zh_CN.internal(_root);
	late final Translations$shelfMenu$zh_CN shelfMenu = Translations$shelfMenu$zh_CN.internal(_root);
	late final Translations$video$zh_CN video = Translations$video$zh_CN.internal(_root);
	late final Translations$bindingEditor$zh_CN bindingEditor = Translations$bindingEditor$zh_CN.internal(_root);
	late final Translations$plat$zh_CN plat = Translations$plat$zh_CN.internal(_root);
}

// Path: workspace
class Translations$workspace$zh_CN {
	Translations$workspace$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '$title (点击展开泳道)'
	String laneTapExpandHint({required Object title}) => '${title} (点击展开泳道)';

	/// zh-CN: '$title（点按收起泳道）'
	String laneTapCollapseHint({required Object title}) => '${title}（点按收起泳道）';

	/// zh-CN: '$title （按住可拖动重排泳道）'
	String laneDragHint({required Object title}) => '${title} （按住可拖动重排泳道）';

	/// zh-CN: '$title（在泳道菜单中选择“编辑布局”可排序）'
	String laneSortHint({required Object title}) => '${title}（在泳道菜单中选择“编辑布局”可排序）';

	/// zh-CN: '允许 $min–$max'
	String allowedRange({required Object min, required Object max}) => '允许 ${min}–${max}';

	/// zh-CN: '停靠$label'
	String dockToName({required Object label}) => '停靠${label}';

	/// zh-CN: '泳道宽度：$px px'
	String laneWidthPx({required Object px}) => '泳道宽度：${px} px';

	/// zh-CN: '停靠到$label'
	String dockToLabel({required Object label}) => '停靠到${label}';

	/// zh-CN: '$count 格'
	String slotCount({required Object count}) => '${count} 格';

	/// zh-CN: '当前每行 $columns 格'
	String columnsPerRow({required Object columns}) => '当前每行 ${columns} 格';

	/// zh-CN: '$n 图'
	String imagesCountBadge({required Object n}) => '${n} 图';

	/// zh-CN: '最高 $value'
	String highestPage({required Object value}) => '最高 ${value}';

	/// zh-CN: '$n 部'
	String worksCount({required Object n}) => '${n} 部';

	/// zh-CN: '占 $v%'
	String sharePercent({required Object v}) => '占 ${v}%';

	/// zh-CN: '少'
	String get heatLegendLow => '少';

	/// zh-CN: '$label · $count 条 $hours'
	String periodDetailLine({required Object label, required Object count, required Object hours}) => '${label} · ${count} 条\n${hours}';

	/// zh-CN: '恢复「$title」'
	String restoreNamed({required Object title}) => '恢复「${title}」';

	/// zh-CN: '全宽并撑满高度'
	String get fullWidthFullHeight => '全宽并撑满高度';

	/// zh-CN: '$w × $h · 松开保存'
	String resizePreview({required Object w, required Object h}) => '${w} × ${h} · 松开保存';

	/// zh-CN: '跳过的条目： $lines'
	String portSkippedLines({required Object lines}) => '跳过的条目：\n${lines}';

	/// zh-CN: '当前 $n 天'
	String streakNowDays({required Object n}) => '当前 ${n} 天';

	/// zh-CN: '多在$period'
	String mostlyAt({required Object period}) => '多在${period}';

	/// zh-CN: '$months 个月前'
	String monthsAgo({required Object months}) => '${months} 个月前';

	/// zh-CN: '$n 部画册'
	String artbookCount({required Object n}) => '${n} 部画册';

	/// zh-CN: '看到 P.$pageNum'
	String seenAtPage({required Object pageNum}) => '看到 P.${pageNum}';

	/// zh-CN: '$count 条 · $percent%'
	String sourceMixItem({required Object count, required Object percent}) => '${count} 条 · ${percent}%';

	/// zh-CN: '样本记录 · $n 个来源'
	String sourceMixHeader({required Object n}) => '样本记录 · ${n} 个来源';

	/// zh-CN: '$date：连续 $value 天'
	String streakPointLine({required Object date, required Object value}) => '${date}：连续 ${value} 天';

	/// zh-CN: '$label：$value 天'
	String streakDaysLine({required Object label, required Object value}) => '${label}：${value} 天';

	/// zh-CN: '$label · $position/$total · 展开$title'
	String insightHeaderExpand({required Object label, required Object position, required Object total, required Object title}) => '${label} · ${position}/${total} · 展开${title}';

	/// zh-CN: '$weekday $hour · $count 条记录'
	String heatCellLine({required Object weekday, required Object hour, required Object count}) => '${weekday} ${hour} · ${count} 条记录';

	/// zh-CN: '高峰 · $weekday $hour'
	String heatPeakLabel({required Object weekday, required Object hour}) => '高峰 · ${weekday} ${hour}';

	/// zh-CN: '高峰 $weekday $hour'
	String heatPeakShort({required Object weekday, required Object hour}) => '高峰 ${weekday} ${hour}';

	/// zh-CN: '$day · 每格 $hours 小时 · 展开阅读热力'
	String compactHeatmapExpandHours({required Object day, required Object hours}) => '${day} · 每格 ${hours} 小时 · 展开阅读热力';

	/// zh-CN: '$hours 小时/格'
	String hoursPerCell({required Object hours}) => '${hours} 小时/格';

	/// zh-CN: '$day · 展开阅读热力'
	String compactHeatmapExpand({required Object day}) => '${day} · 展开阅读热力';

	/// zh-CN: '$period记录最多'
	String busiestPeriodLabel({required Object period}) => '${period}记录最多';

	/// zh-CN: '周$day：$count 条记录'
	String weekdayRecordLine({required Object day, required Object count}) => '周${day}：${count} 条记录';

	/// zh-CN: '周$day最活跃'
	String busiestWeekdayLabel({required Object day}) => '周${day}最活跃';

	/// zh-CN: '$key · $count 条最后阅读记录'
	String selectedLastReadLines({required Object key, required Object count}) => '${key} · ${count} 条最后阅读记录';

	/// zh-CN: '$key：$count 条记录'
	String dayRecordLine({required Object key, required Object count}) => '${key}：${count} 条记录';

	/// zh-CN: '$n 天活跃'
	String activeDaysCount({required Object n}) => '${n} 天活跃';

	/// zh-CN: '折叠$title'
	String collapseNamed({required Object title}) => '折叠${title}';

	/// zh-CN: '插入至：$name'
	String insertTarget({required Object name}) => '插入至：${name}';

	/// zh-CN: '$activeCount 项开启'
	String activeSwitchCount({required Object activeCount}) => '${activeCount} 项开启';

	/// zh-CN: '已开 $activeCount / 3 项'
	String switchToastActiveOf3({required Object activeCount}) => '已开 ${activeCount} / 3 项';

	/// zh-CN: '峰值 $value'
	String peakAllocated({required Object value}) => '峰值 ${value}';

	/// zh-CN: '失败 · $error'
	String failedWith({required Object error}) => '失败 · ${error}';

	/// zh-CN: '共 $n 个在册'
	String registeredCount({required Object n}) => '共 ${n} 个在册';

	/// zh-CN: '$ready / $total 就绪'
	String readyOfTotal({required Object ready, required Object total}) => '${ready} / ${total} 就绪';

	/// zh-CN: '$n 个图源'
	String sourceCountLabel({required Object n}) => '${n} 个图源';

	/// zh-CN: '$kind 文件'
	String fileKindLabel({required Object kind}) => '${kind} 文件';

	/// zh-CN: '穿透深度：$value'
	String passthroughDepthLabel({required Object value}) => '穿透深度：${value}';

	/// zh-CN: '内容布局：$value'
	String contentLayoutLabel({required Object value}) => '内容布局：${value}';

	/// zh-CN: '排序：$value'
	String sortFieldLabel({required Object value}) => '排序：${value}';

	/// zh-CN: '条目样式：$value'
	String entryStyleLabel({required Object value}) => '条目样式：${value}';

	/// zh-CN: '类型：$value'
	String filterTypeLabel({required Object value}) => '类型：${value}';

	/// zh-CN: '层数 ≤$n'
	String depthLimitLabel({required Object n}) => '层数 ≤${n}';

	/// zh-CN: '第 $n 层以下未搜'
	String notSearchedBelow({required Object n}) => '第 ${n} 层以下未搜';

	/// zh-CN: '已看 $n'
	String searchScanned({required Object n}) => '已看 ${n}';

	/// zh-CN: '命中 $n'
	String searchHits({required Object n}) => '命中 ${n}';

	/// zh-CN: '$v 万条'
	String tenThousandRecords({required Object v}) => '${v} 万条';

	/// zh-CN: '$label · 慢盘上要几十秒，结果扫完一次给出'
	String slowScanNote({required Object label}) => '${label} · 慢盘上要几十秒，结果扫完一次给出';

	/// zh-CN: '正在递归搜索 · 已扫 $scanned'
	String recursiveSearchScanned({required Object scanned}) => '正在递归搜索 · 已扫 ${scanned}';

	/// zh-CN: '恢复页签：$title'
	String restoreTabTitle({required Object title}) => '恢复页签：${title}';

	/// zh-CN: '已选 $n 项'
	String selectedCount({required Object n}) => '已选 ${n} 项';

	/// zh-CN: '筛选: $query'
	String filteringBy({required Object query}) => '筛选: ${query}';

	/// zh-CN: '页面 $n'
	String pageN({required Object n}) => '页面 ${n}';

	/// zh-CN: '打开本地漫画出错: $error'
	String openLocalComicFailed({required Object error}) => '打开本地漫画出错: ${error}';

	/// zh-CN: '$days 天前'
	String daysAgo({required Object days}) => '${days} 天前';

	/// zh-CN: '$n 项'
	String childCount({required Object n}) => '${n} 项';

	/// zh-CN: '当前这一层没有匹配「$query」的条目，可用上面的「在子目录里搜」往下找'
	String noMatchThisLevelSuggest({required Object query}) => '当前这一层没有匹配「${query}」的条目，可用上面的「在子目录里搜」往下找';

	/// zh-CN: '子目录里没有匹配「$query」的条目'
	String noMatchInSubdirs({required Object query}) => '子目录里没有匹配「${query}」的条目';

	/// zh-CN: '$n 个'
	String tasksCount({required Object n}) => '${n} 个';

	/// zh-CN: '$n 本'
	String booksCount({required Object n}) => '${n} 本';

	/// zh-CN: '内置'
	String get builtinWord => '内置';

	/// zh-CN: '在线图源 · $from'
	String onlineSourceFrom({required Object from}) => '在线图源 · ${from}';

	/// zh-CN: '还剩 $n 页'
	String pagesRemaining({required Object n}) => '还剩 ${n} 页';

	/// zh-CN: '当前页 · 共 $total 页'
	String currentOfTotalPages({required Object total}) => '当前页 · 共 ${total} 页';

	/// zh-CN: '$month月$day日'
	String dateMD({required Object month, required Object day}) => '${month}月${day}日';

	/// zh-CN: '$year年$month月$day日'
	String dateYMD({required Object year, required Object month, required Object day}) => '${year}年${month}月${day}日';

	/// zh-CN: '$weekday $range：$count 条记录'
	String heatmapCell({required Object weekday, required Object range, required Object count}) => '${weekday} ${range}：${count} 条记录';

	/// zh-CN: '这 $count 项'
	String theseCountItems({required Object count}) => '这 ${count} 项';

	/// zh-CN: '文件内重复 $n 条'
	String duplicateInFileCount({required Object n}) => '文件内重复 ${n} 条';

	/// zh-CN: '保留本地 $n 条'
	String keptLocalCount({required Object n}) => '保留本地 ${n} 条';

	/// zh-CN: '更新进度 $n 条'
	String progressUpdatedCount({required Object n}) => '更新进度 ${n} 条';

	/// zh-CN: '跳过 $n 条'
	String skippedCount({required Object n}) => '跳过 ${n} 条';

	/// zh-CN: '已存在 $n 条'
	String alreadyPresentCount({required Object n}) => '已存在 ${n} 条';

	/// zh-CN: '复活 $n 条'
	String revivedCount({required Object n}) => '复活 ${n} 条';

	/// zh-CN: '新增 $n 条'
	String addedCount({required Object n}) => '新增 ${n} 条';

	/// zh-CN: 'uniqueKey 与 source:comicId 不一致，应为 $expected'
	String keyMismatch({required Object expected}) => 'uniqueKey 与 source:comicId 不一致，应为 ${expected}';

	/// zh-CN: '第 $n 条'
	String itemNumber({required Object n}) => '第 ${n} 条';

	/// zh-CN: '不支持的格式版本 $version'
	String unsupportedFormatVersion({required Object version}) => '不支持的格式版本 ${version}';

	/// zh-CN: '不是合法的 JSON：$error'
	String invalidJson({required Object error}) => '不是合法的 JSON：${error}';

	/// zh-CN: '导入$label失败：$error'
	String portImportFailed({required Object label, required Object error}) => '导入${label}失败：${error}';

	/// zh-CN: '读不了这个文件：$error'
	String portFileUnreadable({required Object error}) => '读不了这个文件：${error}';

	/// zh-CN: '导出$label失败：$error'
	String portExportFailed({required Object label, required Object error}) => '导出${label}失败：${error}';

	/// zh-CN: '已导出 $count 条$label $target'
	String portExportDone({required Object count, required Object label, required Object target}) => '已导出 ${count} 条${label}\n${target}';

	/// zh-CN: '$label还是空的，没有可导出的内容'
	String portListEmpty({required Object label}) => '${label}还是空的，没有可导出的内容';

	/// zh-CN: '$summary 首个失败原因：$failure'
	String opFirstFailure({required Object summary, required Object failure}) => '${summary}　首个失败原因：${failure}';

	/// zh-CN: '$verb$subject，选个目录粘贴'
	String pickPasteTarget({required Object verb, required Object subject}) => '${verb}${subject}，选个目录粘贴';

	/// zh-CN: '已把$subject移到回收站，$hint（在系统废纸篓里）'
	String movedToTrashSystem({required Object subject, required Object hint}) => '已把${subject}移到回收站，${hint}（在系统废纸篓里）';

	/// zh-CN: '已把$subject移到回收站，$hint'
	String movedToTrash({required Object subject, required Object hint}) => '已把${subject}移到回收站，${hint}';

	/// zh-CN: '打不开文件管理器：$error'
	String cannotOpenFileManager({required Object error}) => '打不开文件管理器：${error}';

	/// zh-CN: '已复制 $count 条路径'
	String pathsCopied({required Object count}) => '已复制 ${count} 条路径';

	/// zh-CN: '$subject将被删除。$outcome。'
	String deleteConfirmSubject({required Object subject, required Object outcome}) => '${subject}将被删除。${outcome}。';

	/// zh-CN: '$subject将被永久删除，不进入回收站，也无法撤销。'
	String deleteForeverWarning({required Object subject}) => '${subject}将被永久删除，不进入回收站，也无法撤销。';

	/// zh-CN: '正在加载'
	String get loadingShort => '正在加载';

	/// zh-CN: '阅读中枢'
	String get readingHubTitle => '阅读中枢';

	/// zh-CN: '章节 ID'
	String get chapterIdLabel => '章节 ID';

	/// zh-CN: '竖幅'
	String get portraitFormat => '竖幅';

	/// zh-CN: '窥视'
	String get peep => '窥视';

	/// zh-CN: '高频标签'
	String get topTags => '高频标签';

	/// zh-CN: '馆藏'
	String get libraryLabel => '馆藏';

	/// zh-CN: '预加载路径'
	String get preloadPath => '预加载路径';

	/// zh-CN: '预加载状态'
	String get preloadStatus => '预加载状态';

	/// zh-CN: '顶栏 = 退出 / 书名 / 切模式 / 重置布局那一行'
	String get topBarIsThatRow => '顶栏 = 退出 / 书名 / 切模式 / 重置布局那一行';

	/// zh-CN: '页面路径'
	String get pagePath => '页面路径';

	/// zh-CN: '页面模板同样可以使用 {{book.*}} 变量；点击任一变量胶囊可直接插入。'
	String get pageTemplateBookVars => '页面模板同样可以使用 {{book.*}} 变量；点击任一变量胶囊可直接插入。';

	/// zh-CN: '页面标题模板'
	String get pageTitleTemplate => '页面标题模板';

	/// zh-CN: '页面文件名'
	String get pageFileName => '页面文件名';

	/// zh-CN: '页面提示模板'
	String get pageToastTemplate => '页面提示模板';

	/// zh-CN: '页面描述模板'
	String get pageDescriptionTemplate => '页面描述模板';

	/// zh-CN: '页面导航'
	String get pageNavigation => '页面导航';

	/// zh-CN: '页表未就绪'
	String get pageListNotReady => '页表未就绪';

	/// zh-CN: '页表总量'
	String get pageListTotal => '页表总量';

	/// zh-CN: '页表'
	String get pageList => '页表';

	/// zh-CN: '页码'
	String get pageNumber => '页码';

	/// zh-CN: '页地址'
	String get pageUrl => '页地址';

	/// zh-CN: '页修改'
	String get pagesModified => '页修改';

	/// zh-CN: '音频'
	String get audioLabel => '音频';

	/// zh-CN: '面积依据'
	String get areaBasis => '面积依据';

	/// zh-CN: '面板栏：悬浮'
	String get panelBarFloating => '面板栏：悬浮';

	/// zh-CN: '面板栏（拖动换边或转悬浮，右键或长按设置）'
	String get panelBarHint => '面板栏（拖动换边或转悬浮，右键或长按设置）';

	/// zh-CN: '隐藏泳道宽度徽标'
	String get hideLaneWidthBadge => '隐藏泳道宽度徽标';

	/// zh-CN: '隐藏工作台顶栏'
	String get hideWorkspaceTopBar => '隐藏工作台顶栏';

	/// zh-CN: '随翻页刷新；量不到的项不猜'
	String get refreshPerPageNoGuessing => '随翻页刷新；量不到的项不猜';

	/// zh-CN: '随机漫游'
	String get randomRoam => '随机漫游';

	/// zh-CN: '随机'
	String get randomLabel => '随机';

	/// zh-CN: '除条目名外，连同它在搜索根之下的相对路径一起匹配'
	String get matchRelativePath => '除条目名外，连同它在搜索根之下的相对路径一起匹配';

	/// zh-CN: '限制在泳道内'
	String get confineToLane => '限制在泳道内';

	/// zh-CN: '限制在本泳道'
	String get confineToThisLane => '限制在本泳道';

	/// zh-CN: '阅读进度（%）'
	String get readingProgressPercent => '阅读进度（%）';

	/// zh-CN: '阅读进度'
	String get readingProgressLabel => '阅读进度';

	/// zh-CN: '阅读热力'
	String get readingHeat => '阅读热力';

	/// zh-CN: '阅读滤镜'
	String get readingFilter => '阅读滤镜';

	/// zh-CN: '阅读洞察'
	String get readingInsights => '阅读洞察';

	/// zh-CN: '阅读概览'
	String get readingOverview => '阅读概览';

	/// zh-CN: '阅读来源'
	String get readingSources => '阅读来源';

	/// zh-CN: '阅读时段'
	String get readingPeriods => '阅读时段';

	/// zh-CN: '阅读工作孔'
	String get readingWorkhole => '阅读工作孔';

	/// zh-CN: '阅读器泳道空闲中'
	String get readerLaneIdle => '阅读器泳道空闲中';

	/// zh-CN: '阅读器 (Reader)'
	String get readerEn => '阅读器 (Reader)';

	/// zh-CN: '阅读历史 (History)'
	String get readingHistoryEn => '阅读历史 (History)';

	/// zh-CN: '阅读历史'
	String get readingHistory => '阅读历史';

	/// zh-CN: '阅读切换悬浮提示'
	String get readingToastOverlay => '阅读切换悬浮提示';

	/// zh-CN: '阅读中'
	String get readingLabel => '阅读中';

	/// zh-CN: '长按拖动排序 / 换泳道'
	String get longPressDragReorder => '长按拖动排序 / 换泳道';

	/// zh-CN: '量不到图头'
	String get imageHeaderUnmeasured => '量不到图头';

	/// zh-CN: '重置布局（不影响当前正在读的这一本）'
	String get resetLayoutHint => '重置布局（不影响当前正在读的这一本）';

	/// zh-CN: '重命名书签列表'
	String get renameBookmarkList => '重命名书签列表';

	/// zh-CN: '重命名 / 删除当前列表'
	String get renameDeleteList => '重命名 / 删除当前列表';

	/// zh-CN: '部在队列'
	String get booksQueued => '部在队列';

	/// zh-CN: '适合当前面板的布局与尺寸'
	String get layoutFitsPanel => '适合当前面板的布局与尺寸';

	/// zh-CN: '退出独占 (Exit Solo)'
	String get exitSoloEn => '退出独占 (Exit Solo)';

	/// zh-CN: '退出独占'
	String get exitSolo => '退出独占';

	/// zh-CN: '退出时间线'
	String get exitTimeline => '退出时间线';

	/// zh-CN: '退出搜索结果，回到这个页签自己的目录'
	String get exitSearchToFolder => '退出搜索结果，回到这个页签自己的目录';

	/// zh-CN: '退出工作台（Esc 亦可）'
	String get exitWorkspaceHint => '退出工作台（Esc 亦可）';

	/// zh-CN: '退出工作台'
	String get exitWorkspace => '退出工作台';

	/// zh-CN: '退出多选'
	String get exitMultiselect => '退出多选';

	/// zh-CN: '退出后恢复横移切面板'
	String get restoreSwipeAfterExit => '退出后恢复横移切面板';

	/// zh-CN: '连续阅读'
	String get streakReading => '连续阅读';

	/// zh-CN: '连续天数'
	String get streakDays => '连续天数';

	/// zh-CN: '连续'
	String get streakLabel => '连续';

	/// zh-CN: '进行中任务'
	String get runningTasks => '进行中任务';

	/// zh-CN: '进度'
	String get progressLabel => '进度';

	/// zh-CN: '进入文件夹'
	String get enterFolder => '进入文件夹';

	/// zh-CN: '这是一条切换提示的预览'
	String get thisIsSwitchToastPreview => '这是一条切换提示的预览';

	/// zh-CN: '这个面板里的卡片都被收起来了'
	String get allCardsCollapsed => '这个面板里的卡片都被收起来了';

	/// zh-CN: '这个平台没有可调用的文件管理器'
	String get noFileManagerOnPlatform => '这个平台没有可调用的文件管理器';

	/// zh-CN: '这个列表里还没有书签'
	String get listHasNoBookmarks => '这个列表里还没有书签';

	/// zh-CN: '这一项要落到本地归档才有量具'
	String get itemNeedsLocalArchive => '这一项要落到本地归档才有量具';

	/// zh-CN: '这一项'
	String get thisItem => '这一项';

	/// zh-CN: '这一墙'
	String get thisWall => '这一墙';

	/// zh-CN: '还没有安装任何插件'
	String get noPluginsInstalled => '还没有安装任何插件';

	/// zh-CN: '还没有书签，去详情页点收藏吧'
	String get noBookmarksYet => '还没有书签，去详情页点收藏吧';

	/// zh-CN: '近 7 日阅读趋势'
	String get last7ReadingTrend => '近 7 日阅读趋势';

	/// zh-CN: '近 7 日记录'
	String get last7Records => '近 7 日记录';

	/// zh-CN: '近 7 日'
	String get last7Days => '近 7 日';

	/// zh-CN: '近 3 天'
	String get last3Days => '近 3 天';

	/// zh-CN: '近 28 日记录'
	String get last28Records => '近 28 日记录';

	/// zh-CN: '近 28 日活跃'
	String get last28Active => '近 28 日活跃';

	/// zh-CN: '近 28 日暂无记录'
	String get last28NoRecords => '近 28 日暂无记录';

	/// zh-CN: '近 28 日'
	String get last28Days => '近 28 日';

	/// zh-CN: '边界提示文案'
	String get boundaryToastText => '边界提示文案';

	/// zh-CN: '载体分布'
	String get carrierDistribution => '载体分布';

	/// zh-CN: '载体'
	String get carrierLabel => '载体';

	/// zh-CN: '转到目录'
	String get goToFolder => '转到目录';

	/// zh-CN: '跳转栏'
	String get jumpBar => '跳转栏';

	/// zh-CN: '路径操作'
	String get pathActions => '路径操作';

	/// zh-CN: '路径'
	String get pathLabel => '路径';

	/// zh-CN: '跨图源聚合搜索'
	String get aggregateSourceSearch => '跨图源聚合搜索';

	/// zh-CN: '趋势'
	String get trendLabel => '趋势';

	/// zh-CN: '超分阶段'
	String get upscaleStage => '超分阶段';

	/// zh-CN: '超分开关'
	String get upscaleSwitch => '超分开关';

	/// zh-CN: '超分后'
	String get afterUpscale => '超分后';

	/// zh-CN: '资源工作孔'
	String get resourceWorkhole => '资源工作孔';

	/// zh-CN: '调试源'
	String get debugSource => '调试源';

	/// zh-CN: '读到章节末尾继续翻页时提醒'
	String get toastAtChapterEnd => '读到章节末尾继续翻页时提醒';

	/// zh-CN: '详细信息'
	String get detailedInformation => '详细信息';

	/// zh-CN: '详细'
	String get detailedLabel => '详细';

	/// zh-CN: '该泳道 (More) · 编辑布局'
	String get laneMoreEditLayout => '该泳道 (More) · 编辑布局';

	/// zh-CN: '访问'
	String get visits => '访问';

	/// zh-CN: '设置与工具'
	String get settingsAndTools => '设置与工具';

	/// zh-CN: '触发条件'
	String get triggerCondition => '触发条件';

	/// zh-CN: '触发全关'
	String get triggersAllOff => '触发全关';

	/// zh-CN: '解码缓冲 + 图片缓存'
	String get decodeBufferPlusCache => '解码缓冲 + 图片缓存';

	/// zh-CN: '视图模式（时间线下不适用）'
	String get viewModeNotInTimeline => '视图模式（时间线下不适用）';

	/// zh-CN: '视图模式'
	String get viewModeLabel => '视图模式';

	/// zh-CN: '见下方明细'
	String get seeDetailsBelow => '见下方明细';

	/// zh-CN: '装饰图形'
	String get decorativeShapes => '装饰图形';

	/// zh-CN: '装新图源'
	String get installNewSource => '装新图源';

	/// zh-CN: '获取中…'
	String get fetching => '获取中…';

	/// zh-CN: '自由缩略图'
	String get freeThumbnails => '自由缩略图';

	/// zh-CN: '自定义布局'
	String get customLayout => '自定义布局';

	/// zh-CN: '翻页提示'
	String get pageTurnToast => '翻页提示';

	/// zh-CN: '翻页或跳页时实时反馈页码'
	String get pageToastShowsNumber => '翻页或跳页时实时反馈页码';

	/// zh-CN: '翻页动画'
	String get pageAnimation => '翻页动画';

	/// zh-CN: '翻訳'
	String get jpTranslated => '翻訳';

	/// zh-CN: '网络图片 · 下载后走图片缓存'
	String get networkImageCached => '网络图片 · 下载后走图片缓存';

	/// zh-CN: '缺少标题'
	String get missingTitle => '缺少标题';

	/// zh-CN: '缺少 source 或 comicId'
	String get missingSourceOrComicId => '缺少 source 或 comicId';

	/// zh-CN: '缩略图'
	String get thumbnailsLabel => '缩略图';

	/// zh-CN: '编辑路径'
	String get editPath => '编辑路径';

	/// zh-CN: '编辑时长按页签排序、跨泳道移动，或长按栏头图标重排泳道'
	String get editLongPressHints => '编辑时长按页签排序、跨泳道移动，或长按栏头图标重排泳道';

	/// zh-CN: '编辑布局'
	String get editLayout => '编辑布局';

	/// zh-CN: '编码格式'
	String get encodedFormat => '编码格式';

	/// zh-CN: '编码大小'
	String get encodedSize => '编码大小';

	/// zh-CN: '综合内容数量、最近使用与阅读状态。'
	String get weightBlendsEverything => '综合内容数量、最近使用与阅读状态。';

	/// zh-CN: '继续上次阅读'
	String get resumeLastReading => '继续上次阅读';

	/// zh-CN: '统计中'
	String get counting => '统计中';

	/// zh-CN: '纹理就绪'
	String get textureReady => '纹理就绪';

	/// zh-CN: '纹理'
	String get texture => '纹理';

	/// zh-CN: '紧凑列表'
	String get compactList => '紧凑列表';

	/// zh-CN: '粘贴到这一项'
	String get pasteIntoItem => '粘贴到这一项';

	/// zh-CN: '粘贴到当前目录'
	String get pasteHere => '粘贴到当前目录';

	/// zh-CN: '篇幅分布'
	String get lengthDistribution => '篇幅分布';

	/// zh-CN: '篇幅'
	String get lengthLabel => '篇幅';

	/// zh-CN: '突出正在阅读的内容。'
	String get emphasiseReading => '突出正在阅读的内容。';

	/// zh-CN: '突出最近使用的内容。'
	String get emphasiseRecent => '突出最近使用的内容。';

	/// zh-CN: '穿透模式'
	String get passthroughMode => '穿透模式';

	/// zh-CN: '空隙填充'
	String get gapFill => '空隙填充';

	/// zh-CN: '空隙与组件'
	String get gapComponentsTitle => '空隙与组件';

	/// zh-CN: '随机图形与小组件同在一处调整：先选总口径，再逐项开关；每一项都能直接看到实际样子。'
	String get gapComponentsDescription => '随机图形与小组件同在一处调整：先选总口径，再逐项开关；每一项都能直接看到实际样子。';

	/// zh-CN: '预览'
	String get gapPreviewLabel => '预览';

	/// zh-CN: '全部开启'
	String get gapEnableAll => '全部开启';

	/// zh-CN: '全部关闭'
	String get gapDisableAll => '全部关闭';

	/// zh-CN: '随机图形'
	String get gapShapesSection => '随机图形';

	/// zh-CN: '小组件'
	String get gapWidgetsSection => '小组件';

	/// zh-CN: '有机团'
	String get gapShapeBlob => '有机团';

	/// zh-CN: '星芒'
	String get gapShapeBurst => '星芒';

	/// zh-CN: '四叶草'
	String get gapShapeClover => '四叶草';

	/// zh-CN: '宝石'
	String get gapShapeGem => '宝石';

	/// zh-CN: '拱门'
	String get gapShapeArch => '拱门';

	/// zh-CN: '花形'
	String get gapShapeFlower => '花形';

	/// zh-CN: '圆环'
	String get gapShapeRing => '圆环';

	/// zh-CN: '波纹'
	String get gapShapeWave => '波纹';

	/// zh-CN: '收官进度'
	String get gapCompletion => '收官进度';

	/// zh-CN: '阅读热力'
	String get gapHeatmap => '阅读热力';

	/// zh-CN: '星期节律'
	String get gapWeekday => '星期节律';

	/// zh-CN: '收藏跨度'
	String get gapSpan => '收藏跨度';

	/// zh-CN: '待读存量'
	String get gapUnread => '待读存量';

	/// zh-CN: '下一里程碑'
	String get gapMilestone => '下一里程碑';

	/// zh-CN: '平均进度'
	String get gapAverageProgress => '平均进度';

	/// zh-CN: '读完'
	String get gapFinishedBooks => '读完';

	/// zh-CN: '未读'
	String get gapUnreadBooks => '未读';

	/// zh-CN: '近 8 周'
	String get gapHeatWindow => '近 8 周';

	/// zh-CN: '星期分布'
	String get gapWeekdayRhythm => '星期分布';

	/// zh-CN: '天跨度'
	String get gapSpanDaysLabel => '天跨度';

	/// zh-CN: '最早'
	String get gapSpanEarliest => '最早';

	/// zh-CN: '待开始'
	String get gapUnreadPool => '待开始';

	/// zh-CN: '还差'
	String get gapMilestoneHint => '还差';

	/// zh-CN: '$on / $total 开启'
	String gapComponentCount({required Object on, required Object total}) => '${on} / ${total} 开启';

	/// zh-CN: '最小 $w × $h'
	String gapMinSize({required Object w, required Object h}) => '最小 ${w} × ${h}';

	/// zh-CN: '恢复默认'
	String get gapResetDefaults => '恢复默认';

	/// zh-CN: '尺寸'
	String get wallTabSize => '尺寸';

	/// zh-CN: '布局'
	String get wallTabLayout => '布局';

	/// zh-CN: '组件'
	String get wallTabComponents => '组件';

	/// zh-CN: '封面'
	String get wallTabCover => '封面';

	/// zh-CN: '权重'
	String get wallTabWeights => '权重';

	/// zh-CN: '空闲'
	String get idleState => '空闲';

	/// zh-CN: '移到回收站（无法撤销）'
	String get moveToTrashNoUndo => '移到回收站（无法撤销）';

	/// zh-CN: '移到回收站'
	String get moveToTrash => '移到回收站';

	/// zh-CN: '目录路径'
	String get folderPath => '目录路径';

	/// zh-CN: '目录'
	String get folderLabel => '目录';

	/// zh-CN: '画面调节'
	String get imageTuning => '画面调节';

	/// zh-CN: '画幅构成'
	String get aspectComposition => '画幅构成';

	/// zh-CN: '画幅'
	String get aspectFormat => '画幅';

	/// zh-CN: '用随机的 Expressive 轮廓与图标补满空隙。'
	String get fillWithExpressiveShapes => '用随机的 Expressive 轮廓与图标补满空隙。';

	/// zh-CN: '独占该栏 (Solo 聚焦)'
	String get soloThisLaneEn => '独占该栏 (Solo 聚焦)';

	/// zh-CN: '独占该栏'
	String get soloThisLane => '独占该栏';

	/// zh-CN: '状态'
	String get statusLabel => '状态';

	/// zh-CN: '点击折叠'
	String get clickToCollapse => '点击折叠';

	/// zh-CN: '点击展开'
	String get clickToExpand => '点击展开';

	/// zh-CN: '点击封面'
	String get tapCover => '点击封面';

	/// zh-CN: '点击填入'
	String get clickToFill => '点击填入';

	/// zh-CN: '漫画归档'
	String get comicArchive => '漫画归档';

	/// zh-CN: '漫画 ID'
	String get comicIdLabel => '漫画 ID';

	/// zh-CN: '漢化'
	String get chineseLocalized => '漢化';

	/// zh-CN: '渲染路径'
	String get renderPath => '渲染路径';

	/// zh-CN: '清除搜索并收起'
	String get clearSearchAndCollapse => '清除搜索并收起';

	/// zh-CN: '深夜'
	String get lateNight => '深夜';

	/// zh-CN: '活跃峰值'
	String get activePeak => '活跃峰值';

	/// zh-CN: '活跃天数'
	String get activeDays => '活跃天数';

	/// zh-CN: '活跃'
	String get activeState => '活跃';

	/// zh-CN: '没有符合搜索或类型筛选的条目'
	String get noEntriesAfterFilter => '没有符合搜索或类型筛选的条目';

	/// zh-CN: '没有条目'
	String get noEntries => '没有条目';

	/// zh-CN: '没有已启用的图源'
	String get noEnabledSource => '没有已启用的图源';

	/// zh-CN: '没有可显示的条目'
	String get nothingToDisplay => '没有可显示的条目';

	/// zh-CN: '没有匹配的页面'
	String get noMatchingPages => '没有匹配的页面';

	/// zh-CN: '没有匹配的阅读记录'
	String get noMatchingHistory => '没有匹配的阅读记录';

	/// zh-CN: '没有匹配的书签'
	String get noMatchingBookmarks => '没有匹配的书签';

	/// zh-CN: '沉浸工作孔'
	String get immersiveWorkhole => '沉浸工作孔';

	/// zh-CN: '永久删除？'
	String get deleteForeverQuestion => '永久删除？';

	/// zh-CN: '永久删除'
	String get deleteForever => '永久删除';

	/// zh-CN: '每周阅读节奏'
	String get weeklyReadingRhythm => '每周阅读节奏';

	/// zh-CN: '每一项都来自记账字段，不来自「我调过所以应该好了」'
	String get everyFieldIsMeasured => '每一项都来自记账字段，不来自「我调过所以应该好了」';

	/// zh-CN: '正常'
	String get normalState => '正常';

	/// zh-CN: '正在递归搜索，结果扫完一次给出…'
	String get recursiveSearchPending => '正在递归搜索，结果扫完一次给出…';

	/// zh-CN: '正在递归搜索…'
	String get recursiveSearching => '正在递归搜索…';

	/// zh-CN: '正在跟随阅读进度'
	String get followingProgress => '正在跟随阅读进度';

	/// zh-CN: '正在编辑布局 · 菜单内完成编辑'
	String get editingLayoutFinishInMenu => '正在编辑布局 · 菜单内完成编辑';

	/// zh-CN: '正在统计阅读历史'
	String get countingReadingHistory => '正在统计阅读历史';

	/// zh-CN: '横幅'
	String get bannerLabel => '横幅';

	/// zh-CN: '根路径'
	String get rootPath => '根路径';

	/// zh-CN: '根据原图横竖比例分配卡片空间。'
	String get areaByAspectRatio => '根据原图横竖比例分配卡片空间。';

	/// zh-CN: '样本最长 · 天'
	String get longestSampleDays => '样本最长 · 天';

	/// zh-CN: '样本最长'
	String get longestSample => '样本最长';

	/// zh-CN: '栏头标题右边那颗「400px」'
	String get theWidthBadgeNextToHeader => '栏头标题右边那颗「400px」';

	/// zh-CN: '标题'
	String get titleLabel => '标题';

	/// zh-CN: '来源键'
	String get sourceKey => '来源键';

	/// zh-CN: '来源类型'
	String get sourceType => '来源类型';

	/// zh-CN: '来源构成'
	String get sourceComposition => '来源构成';

	/// zh-CN: '来源拆分'
	String get sourceBreakdown => '来源拆分';

	/// zh-CN: '来源修改于'
	String get sourceModifiedAt => '来源修改于';

	/// zh-CN: '来源'
	String get sourceLabel => '来源';

	/// zh-CN: '条目数'
	String get entryCount => '条目数';

	/// zh-CN: '条有更新'
	String get itemsUpdated => '条有更新';

	/// zh-CN: '条内容'
	String get itemsContent => '条内容';

	/// zh-CN: '本话已读完 · 准备下一话'
	String get chapterDonePreparingNext => '本话已读完 · 准备下一话';

	/// zh-CN: '本平台不支持'
	String get platformUnsupported => '本平台不支持';

	/// zh-CN: '本地漫画 (Local Manga)'
	String get localComicsEn => '本地漫画 (Local Manga)';

	/// zh-CN: '本地漫画'
	String get localComics => '本地漫画';

	/// zh-CN: '本地作品'
	String get localWorks => '本地作品';

	/// zh-CN: '本地'
	String get localLabel => '本地';

	/// zh-CN: '末页提示'
	String get lastPageToast => '末页提示';

	/// zh-CN: '未开启'
	String get notTurnedOn => '未开启';

	/// zh-CN: '未启用'
	String get notEnabled => '未启用';

	/// zh-CN: '服务器'
	String get serverLabel => '服务器';

	/// zh-CN: '最多 32 层'
	String get maxThirtyTwoLevels => '最多 32 层';

	/// zh-CN: '最后一页提示文案'
	String get lastPageToastText => '最后一页提示文案';

	/// zh-CN: '暂无阅读历史'
	String get noReadingHistory => '暂无阅读历史';

	/// zh-CN: '暂无记录'
	String get noRecordsYet => '暂无记录';

	/// zh-CN: '暂无热力记录'
	String get noHeatRecords => '暂无热力记录';

	/// zh-CN: '暂无启用的插件'
	String get noEnabledPlugins => '暂无启用的插件';

	/// zh-CN: '暂无历史访问记录'
	String get noVisitHistory => '暂无历史访问记录';

	/// zh-CN: '普通卡占 1 格，宽卡占 2 格'
	String get normalOneWideTwoSlots => '普通卡占 1 格，宽卡占 2 格';

	/// zh-CN: '晚间'
	String get eveningNight => '晚间';

	/// zh-CN: '晚上'
	String get eveningLabel => '晚上';

	/// zh-CN: '显示隐藏文件'
	String get showHiddenFiles => '显示隐藏文件';

	/// zh-CN: '显示目标'
	String get showTarget => '显示目标';

	/// zh-CN: '显示快速切换栏'
	String get showQuickSwitchBar => '显示快速切换栏';

	/// zh-CN: '显示工作台顶栏'
	String get showWorkspaceTopBar => '显示工作台顶栏';

	/// zh-CN: '显示子文件名'
	String get showSubFileNames => '显示子文件名';

	/// zh-CN: '时间信息'
	String get timeInformation => '时间信息';

	/// zh-CN: '时段'
	String get timePeriod => '时段';

	/// zh-CN: '早期收藏'
	String get earlyFavourites => '早期收藏';

	/// zh-CN: '无法撤销'
	String get cannotUndo => '无法撤销';

	/// zh-CN: '无动画'
	String get noAnimation => '无动画';

	/// zh-CN: '方幅'
	String get squareFormat => '方幅';

	/// zh-CN: '新建页签'
	String get newTab => '新建页签';

	/// zh-CN: '新建书签列表'
	String get newBookmarkList => '新建书签列表';

	/// zh-CN: '新名称'
	String get newName => '新名称';

	/// zh-CN: '文件管理'
	String get fileManagement => '文件管理';

	/// zh-CN: '文件浏览'
	String get fileBrowsing => '文件浏览';

	/// zh-CN: '文件操作（复制 / 移动 / 删除）'
	String get fileOperations => '文件操作（复制 / 移动 / 删除）';

	/// zh-CN: '文件夹优先'
	String get foldersFirst => '文件夹优先';

	/// zh-CN: '文件名'
	String get fileNameLabel => '文件名';

	/// zh-CN: '数值越大越突出；0 关闭该项。多项命中时取最高权重。'
	String get weightBiggerWins => '数值越大越突出；0 关闭该项。多项命中时取最高权重。';

	/// zh-CN: '改为悬浮'
	String get switchToFloating => '改为悬浮';

	/// zh-CN: '收起搜索'
	String get collapseSearch => '收起搜索';

	/// zh-CN: '收起子项'
	String get collapseChildren => '收起子项';

	/// zh-CN: '收起子文件夹'
	String get collapseSubfolders => '收起子文件夹';

	/// zh-CN: '收起信息'
	String get collapseInformation => '收起信息';

	/// zh-CN: '收藏时间'
	String get favouriteTime => '收藏时间';

	/// zh-CN: '收藏夹'
	String get favouriteList => '收藏夹';

	/// zh-CN: '支持 zip, cbz, 文件夹、PDF 及图片打包归档。Rust 侧快速解压并直入 D3D12/Metal 合成链。'
	String get localOpenSupportDesc => '支持 zip, cbz, 文件夹、PDF 及图片打包归档。Rust 侧快速解压并直入 D3D12/Metal 合成链。';

	/// zh-CN: '撤销上一步'
	String get undoLastStep => '撤销上一步';

	/// zh-CN: '摘要'
	String get summaryLabel => '摘要';

	/// zh-CN: '搜索（空格分词，-排除）'
	String get searchSpaceExclude => '搜索（空格分词，-排除）';

	/// zh-CN: '搜索页码或文件名...'
	String get searchPageOrFileName => '搜索页码或文件名...';

	/// zh-CN: '搜索栏'
	String get searchField => '搜索栏';

	/// zh-CN: '搜索标题 / 作者 / 来源'
	String get searchTitleAuthorSource => '搜索标题 / 作者 / 来源';

	/// zh-CN: '插件运行状态'
	String get pluginRunState => '插件运行状态';

	/// zh-CN: '插件市场'
	String get pluginMarket => '插件市场';

	/// zh-CN: '控制面板'
	String get controlPanel => '控制面板';

	/// zh-CN: '接管'
	String get takeOver => '接管';

	/// zh-CN: '接着看'
	String get keepReading => '接着看';

	/// zh-CN: '排序（时间线固定按时间排）'
	String get sortingTimelineFixed => '排序（时间线固定按时间排）';

	/// zh-CN: '排序模式'
	String get sortMode => '排序模式';

	/// zh-CN: '按自定义标签权重突出内容。'
	String get emphasiseByTagWeights => '按自定义标签权重突出内容。';

	/// zh-CN: '按文件占用空间分配展示面积。'
	String get areaByDiskUsage => '按文件占用空间分配展示面积。';

	/// zh-CN: '按天看时间线'
	String get timelineByDay => '按天看时间线';

	/// zh-CN: '按住标题拖动排序'
	String get dragTitleToReorder => '按住标题拖动排序';

	/// zh-CN: '按主题整理书签。创建后可以把书签移动到这个列表。'
	String get bookmarkListDesc => '按主题整理书签。创建后可以把书签移动到这个列表。';

	/// zh-CN: '拖动调整工作孔尺寸'
	String get dragResizeWorkhole => '拖动调整工作孔尺寸';

	/// zh-CN: '拖动调整大小'
	String get dragToResize => '拖动调整大小';

	/// zh-CN: '折叠为紧凑条 (Collapse)'
	String get collapseToBarEn => '折叠为紧凑条 (Collapse)';

	/// zh-CN: '折叠为紧凑条'
	String get collapseToBar => '折叠为紧凑条';

	/// zh-CN: '把这次搜索结果另存一个页签'
	String get saveSearchAsTab => '把这次搜索结果另存一个页签';

	/// zh-CN: '把当前目录设为主页'
	String get setHomeHere => '把当前目录设为主页';

	/// zh-CN: '打开阅读器'
	String get openReader => '打开阅读器';

	/// zh-CN: '打开本地'
	String get openLocal => '打开本地';

	/// zh-CN: '打开或切到另一本漫画时弹出'
	String get toastOnOpenOrSwitch => '打开或切到另一本漫画时弹出';

	/// zh-CN: '打开工作孔'
	String get openWorkhole => '打开工作孔';

	/// zh-CN: '打开书本后显示页面导航'
	String get showPageNavWhenOpen => '打开书本后显示页面导航';

	/// zh-CN: '打开书本后显示文件时间'
	String get showFileTimesWhenOpen => '打开书本后显示文件时间';

	/// zh-CN: '打开书本后显示当前页信息'
	String get showCurrentPageWhenOpen => '打开书本后显示当前页信息';

	/// zh-CN: '打开书本后显示存储信息'
	String get showStorageWhenOpen => '打开书本后显示存储信息';

	/// zh-CN: '打开书本后显示呈现与预取状态'
	String get showPresentPrefetchWhenOpen => '打开书本后显示呈现与预取状态';

	/// zh-CN: '打开一本书后显示书籍信息'
	String get showBookInfoWhenOpen => '打开一本书后显示书籍信息';

	/// zh-CN: '手气不错'
	String get imFeelingLucky => '手气不错';

	/// zh-CN: '恢复默认尺寸'
	String get restoreDefaultSize => '恢复默认尺寸';

	/// zh-CN: '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；点栏顶的独占按钮可让它瞬间撑满视口。'
	String get readerLaneSoloHint => '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；点栏顶的独占按钮可让它瞬间撑满视口。';

	/// zh-CN: '样本内有记录的连续日期 · 不代表完整阅读日志'
	String get footnoteSampleStreakDays => '样本内有记录的连续日期 · 不代表完整阅读日志';

	/// zh-CN: '样本内连续日期 · 不代表完整阅读日志'
	String get footnoteSampleStreak => '样本内连续日期 · 不代表完整阅读日志';

	/// zh-CN: '近 28 日 · 按最后阅读的本地时间分布'
	String get footnotePeriod28 => '近 28 日 · 按最后阅读的本地时间分布';

	/// zh-CN: '近 28 日 · 按星期汇总最后阅读记录'
	String get footnoteWeekday28 => '近 28 日 · 按星期汇总最后阅读记录';

	/// zh-CN: '最近 500 本漫画的最后阅读记录 · 不代表总次数或阅读时长'
	String get footnoteLast500 => '最近 500 本漫画的最后阅读记录 · 不代表总次数或阅读时长';

	/// zh-CN: '点按切换递归层数（$depths 层）。$detail'
	String searchDepthTooltip({required Object depths, required Object detail}) => '点按切换递归层数（${depths} 层）。${detail}';

	/// zh-CN: '六'
	String get shortSat => '六';

	/// zh-CN: '五'
	String get shortFri => '五';

	/// zh-CN: '四'
	String get shortThu => '四';

	/// zh-CN: '三'
	String get shortWed => '三';

	/// zh-CN: '二'
	String get shortTue => '二';

	/// zh-CN: '一'
	String get shortMon => '一';

	/// zh-CN: '日'
	String get shortSun => '日';

	/// zh-CN: '恢复默认宽度'
	String get restoreDefaultWidth => '恢复默认宽度';

	/// zh-CN: '恢复面板栏默认位置'
	String get restorePanelBarPosition => '恢复面板栏默认位置';

	/// zh-CN: '恢复被收起的卡片'
	String get restoreCollapsedCards => '恢复被收起的卡片';

	/// zh-CN: '恢复已关闭页签'
	String get restoreClosedTabs => '恢复已关闭页签';

	/// zh-CN: '总页数'
	String get totalPagesLabel => '总页数';

	/// zh-CN: '待续'
	String get toContinue => '待续';

	/// zh-CN: '待看叠卡'
	String get queueStackCards => '待看叠卡';

	/// zh-CN: '当前页耗时'
	String get currentPageCost => '当前页耗时';

	/// zh-CN: '当前页码'
	String get currentPageNumber => '当前页码';

	/// zh-CN: '当前页文件'
	String get currentPageFile => '当前页文件';

	/// zh-CN: '当前页大小'
	String get currentPageSize => '当前页大小';

	/// zh-CN: '当前页修改于'
	String get currentPageModifiedAt => '当前页修改于';

	/// zh-CN: '当前页交页耗时 (ms)'
	String get currentPageHandoffMs => '当前页交页耗时 (ms)';

	/// zh-CN: '当前连续 · 天'
	String get currentStreakDays => '当前连续 · 天';

	/// zh-CN: '当前连续'
	String get currentStreak => '当前连续';

	/// zh-CN: '当前这一层没有命中；开着「含子目录」再搜一次（整库遍历在慢盘上要几十秒）'
	String get noHitThisLevel => '当前这一层没有命中；开着「含子目录」再搜一次（整库遍历在慢盘上要几十秒）';

	/// zh-CN: '当前目录没有可浏览的漫画或媒体文件'
	String get folderNoMedia => '当前目录没有可浏览的漫画或媒体文件';

	/// zh-CN: '当前文件夹没有可显示的子项'
	String get folderNoChildren => '当前文件夹没有可显示的子项';

	/// zh-CN: '当前搜索或目录快照未包含此文件夹。可进入文件夹查看内部内容。'
	String get folderNotInSnapshot => '当前搜索或目录快照未包含此文件夹。可进入文件夹查看内部内容。';

	/// zh-CN: '归档'
	String get archiveLabel => '归档';

	/// zh-CN: '开着（原图对比中）'
	String get onComparingOriginal => '开着（原图对比中）';

	/// zh-CN: '开着'
	String get switchedOn => '开着';

	/// zh-CN: '开书后这几格会当场填上，量不到的留 —'
	String get fieldsFillOnOpen => '开书后这几格会当场填上，量不到的留 —';

	/// zh-CN: '建链中'
	String get linking => '建链中';

	/// zh-CN: '平均页/话数'
	String get avgPagesPerBook => '平均页/话数';

	/// zh-CN: '常规宽度'
	String get regularWidth => '常规宽度';

	/// zh-CN: '常见标签'
	String get commonTags => '常见标签';

	/// zh-CN: '常看创作者'
	String get topCreators => '常看创作者';

	/// zh-CN: '市场'
	String get market => '市场';

	/// zh-CN: '已达上限'
	String get limitReached => '已达上限';

	/// zh-CN: '已经是最后一页'
	String get isLastPage => '已经是最后一页';

	/// zh-CN: '已清空搜索历史'
	String get searchHistoryCleared => '已清空搜索历史';

	/// zh-CN: '已暂停跟随阅读进度'
	String get followProgressPaused => '已暂停跟随阅读进度';

	/// zh-CN: '已打开文件管理器'
	String get fileManagerOpened => '已打开文件管理器';

	/// zh-CN: '已就绪'
	String get gpuReadyState => '已就绪';

	/// zh-CN: '已复制路径'
	String get pathCopied => '已复制路径';

	/// zh-CN: '已复制'
	String get copied => '已复制';

	/// zh-CN: '已呈现页数'
	String get pagesPresented => '已呈现页数';

	/// zh-CN: '已剪切'
	String get cutDone => '已剪切';

	/// zh-CN: '已写入缓存，请在分享面板里保存'
	String get writtenToCacheShare => '已写入缓存，请在分享面板里保存';

	/// zh-CN: '已中止'
	String get aborted => '已中止';

	/// zh-CN: '工作孔尺寸'
	String get workholeSize => '工作孔尺寸';

	/// zh-CN: '峰值日'
	String get peakDay => '峰值日';

	/// zh-CN: '峰值'
	String get peakValue => '峰值';

	/// zh-CN: '展开泳道'
	String get expandLane => '展开泳道';

	/// zh-CN: '展开时每 3 秒取一次'
	String get polledEvery3s => '展开时每 3 秒取一次';

	/// zh-CN: '展开子项'
	String get expandChildren => '展开子项';

	/// zh-CN: '展开子文件夹'
	String get expandSubfolders => '展开子文件夹';

	/// zh-CN: '展开信息'
	String get expandInformation => '展开信息';

	/// zh-CN: '展开'
	String get expandLabel => '展开';

	/// zh-CN: '展墙设置 · 长按开关展墙'
	String get displayWallSettings => '展墙设置 · 长按开关展墙';

	/// zh-CN: '展墙自定义'
	String get displayWallCustom => '展墙自定义';

	/// zh-CN: '展墙'
	String get displayWall => '展墙';

	/// zh-CN: '层数越大越慢：一次整库遍历在慢盘上要几十秒；太浅会漏掉更深的目录'
	String get searchDepthCostHint => '层数越大越慢：一次整库遍历在慢盘上要几十秒；太浅会漏掉更深的目录';

	/// zh-CN: '就绪等待'
	String get readyWaiting => '就绪等待';

	/// zh-CN: '就绪'
	String get readyState => '就绪';

	/// zh-CN: '尘封重温'
	String get dustyReread => '尘封重温';

	/// zh-CN: '小组件每面墙各出现一次，其余空隙用随机图形补。'
	String get widgetsOnceThenShapes => '小组件每面墙各出现一次，其余空隙用随机图形补。';

	/// zh-CN: '封面网格'
	String get coverGrid => '封面网格';

	/// zh-CN: '封面拼贴'
	String get coverCollage => '封面拼贴';

	/// zh-CN: '封面列表'
	String get coverList => '封面列表';

	/// zh-CN: '封面'
	String get coverLabel => '封面';

	/// zh-CN: '导出为 JSON'
	String get exportAsJson => '导出为 JSON';

	/// zh-CN: '导入 / 导出'
	String get importExport => '导入 / 导出';

	/// zh-CN: '宽度为目标尺寸，列数随面板可用空间自动调整。宽卡占两格，可与普通卡并排。'
	String get cardWidthAutoColumns => '宽度为目标尺寸，列数随面板可用空间自动调整。宽卡占两格，可与普通卡并排。';

	/// zh-CN: '完成编辑'
	String get finishEditing => '完成编辑';

	/// zh-CN: '完成布局'
	String get finishLayout => '完成布局';

	/// zh-CN: '存储信息'
	String get storageInformation => '存储信息';

	/// zh-CN: '存为页签'
	String get saveAsTab => '存为页签';

	/// zh-CN: '子文件：显示全部'
	String get subFilesShowAll => '子文件：显示全部';

	/// zh-CN: '子文件：显示一个'
	String get subFilesShowOne => '子文件：显示一个';

	/// zh-CN: '天有记录'
	String get daysWithRecords => '天有记录';

	/// zh-CN: '大小对比'
	String get sizeCompare => '大小对比';

	/// zh-CN: '大小'
	String get sizeLabel => '大小';

	/// zh-CN: '多列泳道'
	String get multiColumnLanes => '多列泳道';

	/// zh-CN: '多个词元之间取并集（默认全部都要命中）'
	String get searchAnyToken => '多个词元之间取并集（默认全部都要命中）';

	/// zh-CN: '多 · 描边为选中项'
	String get multiOutlinedSelected => '多 · 描边为选中项';

	/// zh-CN: '复制页签'
	String get duplicateTab => '复制页签';

	/// zh-CN: '复制路径'
	String get copyPath => '复制路径';

	/// zh-CN: '复制位置'
	String get copyPosition => '复制位置';

	/// zh-CN: '墨水屏刷屏'
	String get einkRefresh => '墨水屏刷屏';

	/// zh-CN: '基于最近 500 本漫画的最后阅读记录'
	String get basedOnLast500 => '基于最近 500 本漫画的最后阅读记录';

	/// zh-CN: '在读进度'
	String get readingProgress => '在读进度';

	/// zh-CN: '在读'
	String get currentlyReading => '在读';

	/// zh-CN: '在线图源没有本地文件时间'
	String get onlineSourceNoFileTime => '在线图源没有本地文件时间';

	/// zh-CN: '在线图源没有归档'
	String get onlineSourceNoArchive => '在线图源没有归档';

	/// zh-CN: '在线图源'
	String get onlineSource => '在线图源';

	/// zh-CN: '在线'
	String get onlineLabel => '在线';

	/// zh-CN: '在新页签打开'
	String get openInNewTab => '在新页签打开';

	/// zh-CN: '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；'
	String get readerLaneReadsHint => '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；';

	/// zh-CN: '在子目录里搜'
	String get searchSubdirs => '在子目录里搜';

	/// zh-CN: '图集'
	String get gallery => '图集';

	/// zh-CN: '图片尺寸'
	String get imageSize => '图片尺寸';

	/// zh-CN: '图片'
	String get imagesLabel => '图片';

	/// zh-CN: '图源本地聚合'
	String get sourceLocalAggregate => '图源本地聚合';

	/// zh-CN: '图源扩展'
	String get sourceExtensions => '图源扩展';

	/// zh-CN: '图源快捷入口'
	String get sourceShortcuts => '图源快捷入口';

	/// zh-CN: '图源与扩展 (Extensions)'
	String get imageSourcesEn => '图源与扩展 (Extensions)';

	/// zh-CN: '图源与扩展'
	String get imageSources => '图源与扩展';

	/// zh-CN: '图源 · 工具 · OCR'
	String get sourcesToolsOcr => '图源 · 工具 · OCR';

	/// zh-CN: '图像处理阶段'
	String get imageProcessingStage => '图像处理阶段';

	/// zh-CN: '图像信息'
	String get imageInformation => '图像信息';

	/// zh-CN: '固定页签'
	String get pinTab => '固定页签';

	/// zh-CN: '固定到当前位置'
	String get pinHere => '固定到当前位置';

	/// zh-CN: '回到目录'
	String get backToFolder => '回到目录';

	/// zh-CN: '回到主页'
	String get backHome => '回到主页';

	/// zh-CN: '回到「挂进栏头」这个默认形态'
	String get backToLaneHeaderDefault => '回到「挂进栏头」这个默认形态';

	/// zh-CN: '四行连续日期 · 描边为选中日 · 颜色越强，记录越多'
	String get heatmapFourRowsHint => '四行连续日期 · 描边为选中日 · 颜色越强，记录越多';

	/// zh-CN: '周日'
	String get weekdaySun => '周日';

	/// zh-CN: '周六'
	String get weekdaySat => '周六';

	/// zh-CN: '周五'
	String get weekdayFri => '周五';

	/// zh-CN: '周四'
	String get weekdayThu => '周四';

	/// zh-CN: '周三'
	String get weekdayWed => '周三';

	/// zh-CN: '周二'
	String get weekdayTue => '周二';

	/// zh-CN: '周一'
	String get weekdayMon => '周一';

	/// zh-CN: '呈现器'
	String get presenter => '呈现器';

	/// zh-CN: '含子目录统计'
	String get includeSubdirStats => '含子目录统计';

	/// zh-CN: '含子目录'
	String get includeSubdirs => '含子目录';

	/// zh-CN: '向下递归搜索，层数上限由 Rust 侧夹紧'
	String get recursiveSearchHint => '向下递归搜索，层数上限由 Rust 侧夹紧';

	/// zh-CN: '后退'
	String get back => '后退';

	/// zh-CN: '名称与路径 · 空格分词 · -排除 · “短语”'
	String get searchSyntaxHint => '名称与路径 · 空格分词 · -排除 · “短语”';

	/// zh-CN: '名称'
	String get nameLabel => '名称';

	/// zh-CN: '可以撤销'
	String get undoable => '可以撤销';

	/// zh-CN: '只调整当前面板。封面右下角的详情按钮始终向下展开。'
	String get onlyThisPanelDetailsBelow => '只调整当前面板。封面右下角的详情按钮始终向下展开。';

	/// zh-CN: '只插入尺寸相符的汇总小组件，同一款可以重复。'
	String get onlyFittingWidgetsRepeat => '只插入尺寸相符的汇总小组件，同一款可以重复。';

	/// zh-CN: '只合并：一条历史都不会删除；本地进度比文件里更新的，保留本地。'
	String get mergeOnlyHistoryDetail => '只合并：一条历史都不会删除；本地进度比文件里更新的，保留本地。';

	/// zh-CN: '只合并，不会删除或覆盖已有的记录。'
	String get mergeOnlyHistory => '只合并，不会删除或覆盖已有的记录。';

	/// zh-CN: '只合并，不会删除或覆盖已有的书签。'
	String get mergeOnlyBookmarks => '只合并，不会删除或覆盖已有的书签。';

	/// zh-CN: '变更'
	String get changesLabel => '变更';

	/// zh-CN: '发现与工具 (Tools)'
	String get discoverToolsEn => '发现与工具 (Tools)';

	/// zh-CN: '切换为沉浸工作孔 (Workhole)'
	String get switchToWorkholeEn => '切换为沉浸工作孔 (Workhole)';

	/// zh-CN: '切换为多列泳道 (Swimlane)'
	String get switchToSwimlaneEn => '切换为多列泳道 (Swimlane)';

	/// zh-CN: '关闭边栏 (Close)'
	String get closeSidebarEn => '关闭边栏 (Close)';

	/// zh-CN: '关闭当前漫画（回到空态）'
	String get closeCurrentComicFull => '关闭当前漫画（回到空态）';

	/// zh-CN: '关闭当前漫画 (回到空态)'
	String get closeCurrentComicPlain => '关闭当前漫画 (回到空态)';

	/// zh-CN: '书签 (Favorites)'
	String get favoritesEn => '书签 (Favorites)';

	/// zh-CN: '书架 (Bookshelf)'
	String get bookshelfEn => '书架 (Bookshelf)';

	/// zh-CN: '下载与离线 (Downloads)'
	String get downloadsOfflineEn => '下载与离线 (Downloads)';

	/// zh-CN: '上面三颗入口仍然可用：装一个图源后这里会一格一个列出来'
	String get topEntriesStillWork => '上面三颗入口仍然可用：装一个图源后这里会一格一个列出来';

	/// zh-CN: '组件 + 图形'
	String get widgetsPlusShapes => '组件 + 图形';

	/// zh-CN: '小组件'
	String get miniWidgets => '小组件';

	/// zh-CN: '随机图形'
	String get randomShapes => '随机图形';

	/// zh-CN: '打开详情页'
	String get openDetailsPage => '打开详情页';

	/// zh-CN: '向下展开详情'
	String get expandDetailsBelow => '向下展开详情';

	/// zh-CN: '综合'
	String get weightBalanced => '综合';

	/// zh-CN: '阅读状态'
	String get readingStatus => '阅读状态';

	/// zh-CN: '最近使用'
	String get recentlyUsed => '最近使用';

	/// zh-CN: '跟随排序'
	String get followSort => '跟随排序';

	/// zh-CN: '昨天'
	String get yesterday => '昨天';

	/// zh-CN: '取消路径编辑'
	String get cancelPathEdit => '取消路径编辑';

	/// zh-CN: '取消固定'
	String get unpin => '取消固定';

	/// zh-CN: '发现与工具'
	String get discoverTools => '发现与工具';

	/// zh-CN: '双击重置该栏宽度 · 右键打开该泳道的菜单'
	String get doubleTapResetLaneWidth => '双击重置该栏宽度　·　右键打开该泳道的菜单';

	/// zh-CN: '去「插件市场」装一个图源，或导入本地插件包'
	String get installOrImportPlugin => '去「插件市场」装一个图源，或导入本地插件包';

	/// zh-CN: '原图比例'
	String get originalRatio => '原图比例';

	/// zh-CN: '历史记录文件'
	String get historyFile => '历史记录文件';

	/// zh-CN: '历史数据'
	String get historyData => '历史数据';

	/// zh-CN: '卷'
	String get volume => '卷';

	/// zh-CN: '卡片高度'
	String get cardHeight => '卡片高度';

	/// zh-CN: '卡片间距'
	String get cardSpacing => '卡片间距';

	/// zh-CN: '卡片布局'
	String get cardLayout => '卡片布局';

	/// zh-CN: '卡片宽度'
	String get cardWidth => '卡片宽度';

	/// zh-CN: '卡片位置'
	String get cardPosition => '卡片位置';

	/// zh-CN: '占用体积'
	String get occupiedSize => '占用体积';

	/// zh-CN: '匹配路径'
	String get matchPath => '匹配路径';

	/// zh-CN: '加载中'
	String get loadingState => '加载中';

	/// zh-CN: '剪切'
	String get cut => '剪切';

	/// zh-CN: '前进'
	String get forward => '前进';

	/// zh-CN: '前 7 日记录'
	String get last7DaysRecords => '前 7 日记录';

	/// zh-CN: '刷新当前目录'
	String get refreshCurrentFolder => '刷新当前目录';

	/// zh-CN: '到达最后一页时显示提示'
	String get toastOnLastPage => '到达最后一页时显示提示';

	/// zh-CN: '到底啦 ~ 没有更多页面'
	String get reachedLastPage => '到底啦 ~ 没有更多页面';

	/// zh-CN: '删除？'
	String get deleteQuestion => '删除？';

	/// zh-CN: '创建中'
	String get creating => '创建中';

	/// zh-CN: '创建'
	String get create => '创建';

	/// zh-CN: '创作者'
	String get creator => '创作者';

	/// zh-CN: '列表名称'
	String get listName => '列表名称';

	/// zh-CN: '切换页面时显示提示'
	String get toastOnPageSwitch => '切换页面时显示提示';

	/// zh-CN: '切换提示测试'
	String get switchToastTest => '切换提示测试';

	/// zh-CN: '切换提示'
	String get switchToast => '切换提示';

	/// zh-CN: '切换书籍时显示提示'
	String get toastOnBookSwitch => '切换书籍时显示提示';

	/// zh-CN: '切换为沉浸工作孔'
	String get switchToWorkhole => '切换为沉浸工作孔';

	/// zh-CN: '切换为多列泳道'
	String get switchToSwimlane => '切换为多列泳道';

	/// zh-CN: '切换为降序'
	String get switchDescending => '切换为降序';

	/// zh-CN: '切换为升序'
	String get switchAscending => '切换为升序';

	/// zh-CN: '切书提示'
	String get bookSwitchToast => '切书提示';

	/// zh-CN: '内部缩略图'
	String get internalThumbnails => '内部缩略图';

	/// zh-CN: '内置'
	String get builtin => '内置';

	/// zh-CN: '内容数量越多，展示面积越大。'
	String get moreContentMoreArea => '内容数量越多，展示面积越大。';

	/// zh-CN: '内容数量'
	String get contentCount => '内容数量';

	/// zh-CN: '内容分区'
	String get contentSections => '内容分区';

	/// zh-CN: '其他媒体'
	String get otherMedia => '其他媒体';

	/// zh-CN: '关闭页签'
	String get closeTab => '关闭页签';

	/// zh-CN: '关闭边栏'
	String get closeSidebar => '关闭边栏';

	/// zh-CN: '关闭穿透模式'
	String get closePassthroughMode => '关闭穿透模式';

	/// zh-CN: '关闭当前漫画'
	String get closeCurrentComic => '关闭当前漫画';

	/// zh-CN: '关闭工作孔'
	String get closeWorkhole => '关闭工作孔';

	/// zh-CN: '关闭左侧页签'
	String get closeTabsLeft => '关闭左侧页签';

	/// zh-CN: '关闭右侧页签'
	String get closeTabsRight => '关闭右侧页签';

	/// zh-CN: '关闭其他页签'
	String get closeOtherTabs => '关闭其他页签';

	/// zh-CN: '关着'
	String get turnedOff => '关着';

	/// zh-CN: '全部管理'
	String get manageAll => '全部管理';

	/// zh-CN: '全部正常'
	String get allHealthy => '全部正常';

	/// zh-CN: '全部图源'
	String get allImageSources => '全部图源';

	/// zh-CN: '全部关闭'
	String get closeAllTabs => '全部关闭';

	/// zh-CN: '全宽'
	String get fullWidth => '全宽';

	/// zh-CN: '允许移出泳道'
	String get allowLeaveLane => '允许移出泳道';

	/// zh-CN: '像素尺寸'
	String get pixelSize => '像素尺寸';

	/// zh-CN: '偶遇'
	String get serendipity => '偶遇';

	/// zh-CN: '偏好标签权重'
	String get favouriteTagWeight => '偏好标签权重';

	/// zh-CN: '偏好标签'
	String get favouriteTags => '偏好标签';

	/// zh-CN: '修改时间'
	String get modifiedTime => '修改时间';

	/// zh-CN: '修改日期'
	String get modifiedDate => '修改日期';

	/// zh-CN: '修改'
	String get modify => '修改';

	/// zh-CN: '例如：路径：{{book.path}}'
	String get egBookPath => '例如：路径：{{book.path}}';

	/// zh-CN: '例如：第 {{page.indexDisplay}} 页'
	String get egPageIndex => '例如：第 {{page.indexDisplay}} 页';

	/// zh-CN: '例如：已经是最后一页'
	String get egLastPage => '例如：已经是最后一页';

	/// zh-CN: '例如：已切换到 {{book.displayName}}'
	String get egSwitchedToBook => '例如：已切换到 {{book.displayName}}';

	/// zh-CN: '例如：{{page.name}}'
	String get egPageName => '例如：{{page.name}}';

	/// zh-CN: '体积'
	String get sizeVolume => '体积';

	/// zh-CN: '位置与外观在「设置 → 提示样式」里调整。'
	String get toastStyleInSettings => '位置与外观在「设置 → 提示样式」里调整。';

	/// zh-CN: '优先突出当前排序靠前的内容。'
	String get emphasiseTopSorted => '优先突出当前排序靠前的内容。';

	/// zh-CN: '任一词元'
	String get anyToken => '任一词元';

	/// zh-CN: '从该面板收起'
	String get collapseFromPanel => '从该面板收起';

	/// zh-CN: '从此页签新建'
	String get newFromThisTab => '从此页签新建';

	/// zh-CN: '从本地磁盘选择漫画文件夹'
	String get pickComicFolderFromDisk => '从本地磁盘选择漫画文件夹';

	/// zh-CN: '从 JSON 导入'
	String get importFromJson => '从 JSON 导入';

	/// zh-CN: '今天'
	String get today => '今天';

	/// zh-CN: '仅桌面'
	String get desktopOnly => '仅桌面';

	/// zh-CN: '书籍路径（本地来源才有值）'
	String get bookPathLocalOnly => '书籍路径（本地来源才有值）';

	/// zh-CN: '书籍标题模板'
	String get bookTitleTemplate => '书籍标题模板';

	/// zh-CN: '书籍显示名'
	String get bookDisplayName => '书籍显示名';

	/// zh-CN: '书籍提示模板'
	String get bookToastTemplate => '书籍提示模板';

	/// zh-CN: '书籍描述模板'
	String get bookDescriptionTemplate => '书籍描述模板';

	/// zh-CN: '书籍信息'
	String get bookInformation => '书籍信息';

	/// zh-CN: '书签文件'
	String get bookmarkFile => '书签文件';

	/// zh-CN: '书签数据'
	String get bookmarkData => '书签数据';

	/// zh-CN: '书签'
	String get bookmarks => '书签';

	/// zh-CN: '书架（上游原版）'
	String get bookshelfUpstream => '书架（上游原版）';

	/// zh-CN: '书架聚合卡片'
	String get bookshelfAggregateCard => '书架聚合卡片';

	/// zh-CN: '书架 · 收藏 · 文件'
	String get shelfFavoriteFiles => '书架 · 收藏 · 文件';

	/// zh-CN: '书架'
	String get bookshelfTab => '书架';

	/// zh-CN: '书名'
	String get bookTitle => '书名';

	/// zh-CN: '主页：还没设置 · 单击把当前目录设为主页'
	String get homeNotSetYet => '主页：还没设置 · 单击把当前目录设为主页';

	/// zh-CN: '主页（当前）· 右键/长按管理'
	String get homeCurrentManageHint => '主页（当前）· 右键/长按管理';

	/// zh-CN: '主页已设为'
	String get homeSetTo => '主页已设为';

	/// zh-CN: '主页 · 右键/长按管理'
	String get homeManageHint => '主页 · 右键/长按管理';

	/// zh-CN: '主视觉'
	String get heroVisual => '主视觉';

	/// zh-CN: '主要占用'
	String get mainOccupancy => '主要占用';

	/// zh-CN: '临时排序（不记住本目录）'
	String get temporarySort => '临时排序（不记住本目录）';

	/// zh-CN: '中止递归搜索（保留已找到的结果）'
	String get abortRecursiveSearch => '中止递归搜索（保留已找到的结果）';

	/// zh-CN: '与双击栏头标题同一条路'
	String get samePathAsHeaderDoubleClick => '与双击栏头标题同一条路';

	/// zh-CN: '与 Esc、系统返回键同一条路'
	String get samePathAsBackKey => '与 Esc、系统返回键同一条路';

	/// zh-CN: '不规则轮廓之间保留空白。'
	String get keepGapIrregularOutline => '不规则轮廓之间保留空白。';

	/// zh-CN: '不是对象'
	String get notAnObject => '不是对象';

	/// zh-CN: '不对称'
	String get asymmetric => '不对称';

	/// zh-CN: '不填充'
	String get noFill => '不填充';

	/// zh-CN: '下载任务列表'
	String get downloadTaskList => '下载任务列表';

	/// zh-CN: '下载与离线'
	String get downloadsOffline => '下载与离线';

	/// zh-CN: '两周均无记录'
	String get bothWeeksNoRecord => '两周均无记录';

	/// zh-CN: '午后'
	String get earlyAfternoon => '午后';

	/// zh-CN: '午'
	String get noon => '午';

	/// zh-CN: '凌晨'
	String get earlyMorning => '凌晨';

	/// zh-CN: '下午'
	String get afternoon => '下午';

	/// zh-CN: '上午'
	String get morning => '上午';

	/// zh-CN: '上一级'
	String get parentDirectory => '上一级';

	/// zh-CN: '上一窗口无记录'
	String get prevWindowNoRecord => '上一窗口无记录';

	/// zh-CN: '下一段'
	String get nextSegment => '下一段';

	/// zh-CN: '上一段'
	String get prevSegment => '上一段';

	/// zh-CN: 'dart:io 没有创建时间，只报量得到的这几项'
	String get noCreationTimeField => 'dart:io 没有创建时间，只报量得到的这几项';

	/// zh-CN: 'Rust 内存只在展开时取，收起不轮询'
	String get rustMemoryPollHint => 'Rust 内存只在展开时取，收起不轮询';

	/// zh-CN: 'Rust 内存'
	String get rustMemory => 'Rust 内存';

	/// zh-CN: 'GPU 零拷贝直通引擎'
	String get gpuZeroCopyEngine => 'GPU 零拷贝直通引擎';

	/// zh-CN: 'GPU 建链中'
	String get gpuLinking => 'GPU 建链中';

	/// zh-CN: 'GPU 就绪'
	String get gpuReady => 'GPU 就绪';

	/// zh-CN: 'GPU 共享纹理'
	String get gpuSharedTexture => 'GPU 共享纹理';

	/// zh-CN: 'CPU 解码兜底'
	String get cpuDecodeFallback => 'CPU 解码兜底';

	/// zh-CN: 'CPU 解码 / 图片缓存预加载'
	String get cpuDecodePreload => 'CPU 解码 / 图片缓存预加载';

	/// zh-CN: '压缩归档'
	String get compressedArchive => '压缩归档';

	/// zh-CN: 'ZIP 归档'
	String get archiveZip => 'ZIP 归档';

	/// zh-CN: 'TAR 归档'
	String get archiveTar => 'TAR 归档';

	/// zh-CN: 'RAR 归档'
	String get archiveRar => 'RAR 归档';

	/// zh-CN: 'CBZ 归档'
	String get archiveCbz => 'CBZ 归档';

	/// zh-CN: 'CBR 归档'
	String get archiveCbr => 'CBR 归档';

	/// zh-CN: '7Z 归档'
	String get archive7z => '7Z 归档';
}

// Path: common
class Translations$common$zh_CN {
	Translations$common$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '名称不能包含 / 或 \\'
	String get nameNoSlash => '名称不能包含 / 或 \\';

	/// zh-CN: '阶段: $stage'
	String startupStage({required Object stage}) => '阶段: ${stage}';

	/// zh-CN: '应用启动失败'
	String get appStartupFailed => '应用启动失败';

	/// zh-CN: '打开本地漫画（Rossi 原版阅读器 + GPU 零拷贝）'
	String get openLocalComicRossi => '打开本地漫画（Rossi 原版阅读器 + GPU 零拷贝）';

	/// zh-CN: '泳道/工作孔工作台 (NeoView Workspace)'
	String get neoViewWorkspace => '泳道/工作孔工作台 (NeoView Workspace)';

	/// zh-CN: '用 Rossi 打开'
	String get openWithRossi => '用 Rossi 打开';

	/// zh-CN: '在资源管理器中显示'
	String get showInExplorer => '在资源管理器中显示';

	/// zh-CN: '在访达中显示'
	String get showInFinder => '在访达中显示';

	/// zh-CN: '在文件管理器中显示'
	String get showInFileManager => '在文件管理器中显示';

	/// zh-CN: '在文件管理器中打开所在目录'
	String get revealInFileManagerFolder => '在文件管理器中打开所在目录';

	/// zh-CN: '删除列表'
	String get deleteListLabel => '删除列表';

	/// zh-CN: '请输入名称'
	String get pleaseEnterName => '请输入名称';

	/// zh-CN: '确定'
	String get ok => '确定';

	/// zh-CN: '取消'
	String get cancel => '取消';

	/// zh-CN: '保存'
	String get save => '保存';

	/// zh-CN: '删除'
	String get delete => '删除';

	/// zh-CN: '编辑'
	String get edit => '编辑';

	/// zh-CN: '重命名'
	String get rename => '重命名';

	/// zh-CN: '添加'
	String get add => '添加';

	/// zh-CN: '新建'
	String get create => '新建';

	/// zh-CN: '刷新'
	String get refresh => '刷新';

	/// zh-CN: '加载中...'
	String get loading => '加载中...';

	/// zh-CN: '加载失败'
	String get loadingFailed => '加载失败';

	/// zh-CN: '重试'
	String get retry => '重试';

	/// zh-CN: '重新加载'
	String get reload => '重新加载';

	/// zh-CN: '确认'
	String get confirm => '确认';

	/// zh-CN: '关闭'
	String get close => '关闭';

	/// zh-CN: '返回'
	String get back => '返回';

	/// zh-CN: '帮助'
	String get help => '帮助';

	/// zh-CN: '知道了'
	String get gotIt => '知道了';

	/// zh-CN: '施工中'
	String get underConstruction => '施工中';

	/// zh-CN: '在写了，在写了'
	String get comingSoon => '在写了，在写了';

	/// zh-CN: '根目录'
	String get root => '根目录';

	/// zh-CN: '移除'
	String get remove => '移除';

	/// zh-CN: '覆盖'
	String get overwrite => '覆盖';

	/// zh-CN: '已取消'
	String get cancelled => '已取消';

	/// zh-CN: '搜索'
	String get search => '搜索';

	/// zh-CN: '清空'
	String get clear => '清空';

	/// zh-CN: '复制'
	String get copy => '复制';

	/// zh-CN: '粘贴'
	String get paste => '粘贴';

	/// zh-CN: '分享'
	String get share => '分享';

	/// zh-CN: '打开'
	String get open => '打开';

	/// zh-CN: '下载'
	String get download => '下载';

	/// zh-CN: '上传'
	String get upload => '上传';

	/// zh-CN: '导入'
	String get import => '导入';

	/// zh-CN: '导出'
	String get export => '导出';

	/// zh-CN: '成功'
	String get success => '成功';

	/// zh-CN: '失败'
	String get failed => '失败';

	/// zh-CN: '错误'
	String get error => '错误';

	/// zh-CN: '警告'
	String get warning => '警告';

	/// zh-CN: '提示'
	String get info => '提示';

	/// zh-CN: '未知'
	String get unknown => '未知';

	/// zh-CN: '暂无数据'
	String get empty => '暂无数据';

	/// zh-CN: '全部'
	String get all => '全部';

	/// zh-CN: '无'
	String get none => '无';

	/// zh-CN: '默认'
	String get default_ => '默认';

	/// zh-CN: '自定义'
	String get custom => '自定义';

	/// zh-CN: '已开启'
	String get enabled => '已开启';

	/// zh-CN: '已关闭'
	String get disabled => '已关闭';

	/// zh-CN: '跟随系统'
	String get followSystem => '跟随系统';

	/// zh-CN: '浅色模式'
	String get lightMode => '浅色模式';

	/// zh-CN: '深色模式'
	String get darkMode => '深色模式';

	/// zh-CN: '系统'
	String get system => '系统';

	/// zh-CN: '应用'
	String get apply => '应用';

	/// zh-CN: '重置'
	String get reset => '重置';

	/// zh-CN: '下一步'
	String get next => '下一步';

	/// zh-CN: '上一步'
	String get previous => '上一步';

	/// zh-CN: '完成'
	String get done => '完成';

	/// zh-CN: '选择'
	String get select => '选择';

	/// zh-CN: '已选择'
	String get selected => '已选择';

	/// zh-CN: '取消选择'
	String get deselect => '取消选择';

	/// zh-CN: '全选'
	String get selectAll => '全选';

	/// zh-CN: '是'
	String get yes => '是';

	/// zh-CN: '否'
	String get no => '否';

	/// zh-CN: '开'
	String get on => '开';

	/// zh-CN: '关'
	String get off => '关';

	/// zh-CN: '更多'
	String get more => '更多';

	/// zh-CN: '详情'
	String get detail => '详情';

	/// zh-CN: '设置已保存'
	String get settingSaved => '设置已保存';

	/// zh-CN: '设置成功，重启生效'
	String get restartToTakeEffect => '设置成功，重启生效';
}

// Path: error
class Translations$error$zh_CN {
	Translations$error$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '出错了'
	String get generic => '出错了';

	/// zh-CN: '网络错误'
	String get network => '网络错误';

	/// zh-CN: '下载失败'
	String get downloadFailed => '下载失败';

	/// zh-CN: '导入失败: $error'
	String importFailed({required Object error}) => '导入失败: ${error}';

	/// zh-CN: '加载失败'
	String get loadFailed => '加载失败';

	/// zh-CN: '保存失败'
	String get saveFailed => '保存失败';

	/// zh-CN: '权限被拒绝'
	String get permissionDenied => '权限被拒绝';

	/// zh-CN: '未找到'
	String get notFound => '未找到';

	/// zh-CN: '当前平台不支持此功能'
	String get unsupportedPlatform => '当前平台不支持此功能';

	/// zh-CN: '缺少插件来源，无法$action'
	String missingPluginSource({required Object action}) => '缺少插件来源，无法${action}';

	/// zh-CN: '操作失败'
	String get operationFailed => '操作失败';

	/// zh-CN: '执行失败'
	String get executionFailed => '执行失败';
}

// Path: navigation
class Translations$navigation$zh_CN {
	Translations$navigation$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '首页'
	String get home => '首页';

	/// zh-CN: '排行'
	String get rank => '排行';

	/// zh-CN: '书架'
	String get bookshelf => '书架';

	/// zh-CN: '发现'
	String get discover => '发现';

	/// zh-CN: '更多'
	String get more => '更多';

	/// zh-CN: '同步成功！'
	String get syncSuccess => '同步成功！';

	/// zh-CN: '自动同步成功！'
	String get autoSyncSuccess => '自动同步成功！';

	/// zh-CN: '同步失败'
	String get syncFailed => '同步失败';

	/// zh-CN: '自动同步失败'
	String get autoSyncFailed => '自动同步失败';

	/// zh-CN: '请检查网络连接或稍后再试。 $error'
	String syncFailedMessage({required Object error}) => '请检查网络连接或稍后再试。\n${error}';

	/// zh-CN: '登录过期，请重新登录'
	String get loginExpired => '登录过期，请重新登录';

	/// zh-CN: '需要登录'
	String get needLoginTitle => '需要登录';

	/// zh-CN: '去登录'
	String get goLogin => '去登录';

	/// zh-CN: '收起侧栏'
	String get sidebarCollapse => '收起侧栏';

	/// zh-CN: '展开侧栏'
	String get sidebarExpand => '展开侧栏';

	/// zh-CN: '导航栏'
	String get navigationChrome => '导航栏';

	/// zh-CN: 'Arc 风格侧栏'
	String get sidebarEnabled => 'Arc 风格侧栏';

	/// zh-CN: '桌面与平板用左侧侧栏导航；关掉回到改造前的旧侧栏'
	String get sidebarEnabledSubtitle => '桌面与平板用左侧侧栏导航；关掉回到改造前的旧侧栏';

	/// zh-CN: '侧栏展开'
	String get sidebarExpanded => '侧栏展开';

	/// zh-CN: '展开时每条带文案，收起时只有图标；侧栏顶部那颗按钮随时可切'
	String get sidebarExpandedSubtitle => '展开时每条带文案，收起时只有图标；侧栏顶部那颗按钮随时可切';

	/// zh-CN: '悬浮 Dock 栏'
	String get dockEnabled => '悬浮 Dock 栏';

	/// zh-CN: '窄屏用底部悬浮胶囊导航；关掉回到改造前的底部导航栏'
	String get dockEnabledSubtitle => '窄屏用底部悬浮胶囊导航；关掉回到改造前的底部导航栏';

	/// zh-CN: '窄屏自动切移动端布局'
	String get autoNarrowMobileLayout => '窄屏自动切移动端布局';

	/// zh-CN: '窗口窄于下面的阈值时从侧栏切到底部 Dock（桌面小窗、平板分屏）'
	String get autoNarrowMobileLayoutSubtitle => '窗口窄于下面的阈值时从侧栏切到底部 Dock（桌面小窗、平板分屏）';

	/// zh-CN: '窄屏阈值'
	String get narrowNavigationWidth => '窄屏阈值';

	/// zh-CN: '窗口宽度（逻辑像素）小于这个值就算窄屏'
	String get narrowNavigationWidthSubtitle => '窗口宽度（逻辑像素）小于这个值就算窄屏';

	/// zh-CN: '恢复默认（$value）'
	String narrowNavigationWidthReset({required Object value}) => '恢复默认（${value}）';

	/// zh-CN: '更多动作'
	String get moreActions => '更多动作';

	/// zh-CN: '自定义导航'
	String get customize => '自定义导航';

	/// zh-CN: '自定义导航栏'
	String get customizeTitle => '自定义导航栏';

	/// zh-CN: '两段各自拖拽排序、自由添加 / 隐藏；动作行上的箭头在「主区」与「底部快捷区」之间搬'
	String get customizeHint => '两段各自拖拽排序、自由添加 / 隐藏；动作行上的箭头在「主区」与「底部快捷区」之间搬';

	/// zh-CN: '主区'
	String get customizeMainSection => '主区';

	/// zh-CN: '底部快捷区'
	String get customizeActionsSection => '底部快捷区';

	/// zh-CN: '侧栏底部那一排 / Dock 尾部溢出菜单里的入口，只放动作'
	String get customizeActionsHint => '侧栏底部那一排 / Dock 尾部溢出菜单里的入口，只放动作';

	/// zh-CN: '桌面侧栏'
	String get customizeDesktopTab => '桌面侧栏';

	/// zh-CN: '移动端 Dock'
	String get customizeMobileTab => '移动端 Dock';

	/// zh-CN: '恢复默认'
	String get customizeReset => '恢复默认';

	/// zh-CN: '完成'
	String get customizeDone => '完成';

	/// zh-CN: '待添加项目'
	String get customizeAvailable => '待添加项目';

	/// zh-CN: '隐藏'
	String get customizeHide => '隐藏';

	/// zh-CN: '动作'
	String get customizeActionTag => '动作';

	/// zh-CN: '移到主区'
	String get customizeMoveToMain => '移到主区';

	/// zh-CN: '移到底部快捷区'
	String get customizeMoveToActions => '移到底部快捷区';

	/// zh-CN: '工作台'
	String get workspace => '工作台';

	/// zh-CN: '打开本地漫画'
	String get openLocalComic => '打开本地漫画';

	/// zh-CN: 'GPU 上屏'
	String get gpuPresent => 'GPU 上屏';
}

// Path: settings
class Translations$settings$zh_CN {
	Translations$settings$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '这条泳道里的面板都已隐藏 —— 可在「全局设置 → 泳道面板看板」中开启需要显示的面板。'
	String get allLanePanelsHidden => '这条泳道里的面板都已隐藏 ——\n可在「全局设置 → 泳道面板看板」中开启需要显示的面板。';

	/// zh-CN: '漫画归档 · $size'
	String localTreeArchiveSize({required Object size}) => '漫画归档 · ${size}';

	/// zh-CN: '直接打开此文件夹'
	String get localTreeOpenThisFolder => '直接打开此文件夹';

	/// zh-CN: '当前目录下没有发现子文件夹或漫画文件'
	String get localTreeEmpty => '当前目录下没有发现子文件夹或漫画文件';

	/// zh-CN: '读取失败: $error'
	String localTreeReadFailed({required Object error}) => '读取失败: ${error}';

	/// zh-CN: '打开当前文件夹'
	String get localTreeOpenFolder => '打开当前文件夹';

	/// zh-CN: '本地文件树浏览 (mImageViewer 核心)'
	String get localTreeTitle => '本地文件树浏览 (mImageViewer 核心)';

	/// zh-CN: 'native 侧没有返回 Rust 侧诊断（DLL 与桥的版本可能不匹配）。'
	String get debugNoRustDiagnostics => 'native 侧没有返回 Rust 侧诊断（DLL 与桥的版本可能不匹配）。';

	/// zh-CN: '浏览...'
	String get debugBrowse => '浏览...';

	/// zh-CN: '本地来源（散图文件夹 / .cbz / .cbr）'
	String get debugLocalSourceGroup => '本地来源（散图文件夹 / .cbz / .cbr）';

	/// zh-CN: '刷新统计'
	String get debugRefreshStats => '刷新统计';

	/// zh-CN: '竖向（右侧）'
	String get tabSideRight => '竖向（右侧）';

	/// zh-CN: '竖向（左侧）'
	String get tabSideLeft => '竖向（左侧）';

	/// zh-CN: '横向（顶栏）'
	String get tabSideTop => '横向（顶栏）';

	/// zh-CN: '继承触发页签'
	String get tabPolicyTriggering => '继承触发页签';

	/// zh-CN: '继承最近使用的页签'
	String get tabPolicyRecent => '继承最近使用的页签';

	/// zh-CN: '使用预设默认值'
	String get tabPolicyDefaults => '使用预设默认值';

	/// zh-CN: '拖拽面板到此追加至末尾'
	String get dragToLaneEnd => '拖拽面板到此追加至末尾';

	/// zh-CN: '松手放到此泳道末尾'
	String get dropToLaneEnd => '松手放到此泳道末尾';

	/// zh-CN: '移至左泳道'
	String get moveToLeftLane => '移至左泳道';

	/// zh-CN: '移至右泳道'
	String get moveToRightLane => '移至右泳道';

	/// zh-CN: '顺位 #$n'
	String kanbanRank({required Object n}) => '顺位 #${n}';

	/// zh-CN: '在面板栏中显示此面板'
	String get kanbanShowPanel => '在面板栏中显示此面板';

	/// zh-CN: '从面板栏彻底隐藏（不留隐藏图标）'
	String get kanbanHideCompletely => '从面板栏彻底隐藏（不留隐藏图标）';

	/// zh-CN: '此泳道专用于承载正在阅读的漫画页面。可通过上方泳道顺序条或本列右上角箭头，将阅读器调整到左侧、居中或右侧位置。'
	String get kanbanReaderLaneDesc => '此泳道专用于承载正在阅读的漫画页面。可通过上方泳道顺序条或本列右上角箭头，将阅读器调整到左侧、居中或右侧位置。';

	/// zh-CN: '漫画阅读器主画布'
	String get kanbanReaderCanvasTitle => '漫画阅读器主画布';

	/// zh-CN: '显示 $visible 个 · 隐藏 $hidden 个'
	String kanbanVisibleHidden({required Object visible, required Object hidden}) => '显示 ${visible} 个 · 隐藏 ${hidden} 个';

	/// zh-CN: '共 $count 个面板（全部显示）'
	String kanbanAllVisible({required Object count}) => '共 ${count} 个面板（全部显示）';

	/// zh-CN: '阅读器主视图泳道'
	String get kanbanReaderLaneTitle => '阅读器主视图泳道';

	/// zh-CN: '第 $n 栏'
	String kanbanLaneIndex({required Object n}) => '第 ${n} 栏';

	/// zh-CN: '泳道顺序（可左右拖拽或点击箭头调整位置）'
	String get kanbanLaneOrderTitle => '泳道顺序（可左右拖拽或点击箭头调整位置）';

	/// zh-CN: '已彻底隐藏 $count 个面板'
	String kanbanHiddenPanels({required Object count}) => '已彻底隐藏 ${count} 个面板';

	/// zh-CN: '显示中 $count 个面板'
	String kanbanVisiblePanels({required Object count}) => '显示中 ${count} 个面板';

	/// zh-CN: '泳道顺序：$order'
	String kanbanLaneOrder({required Object order}) => '泳道顺序：${order}';

	/// zh-CN: '拖拽或点击按钮即可调整泳道顺序、各泳道内面板顺序及显示/隐藏状态。隐藏后的面板将从面板栏彻底移除，不再显示隐藏图标。'
	String get kanbanDragHint => '拖拽或点击按钮即可调整泳道顺序、各泳道内面板顺序及显示/隐藏状态。隐藏后的面板将从面板栏彻底移除，不再显示隐藏图标。';

	/// zh-CN: '右泳道'
	String get rightLane => '右泳道';

	/// zh-CN: '左泳道'
	String get leftLane => '左泳道';

	/// zh-CN: '泳道面板看板配置'
	String get swimlanePanelKanbanConfigTitle => '泳道面板看板配置';

	/// zh-CN: '本机没有悬停指针：这几块唤出区要鼠标贴住边缘才会生效。触屏上请在 Reader 独占时点左右两侧的窄轨来切换泳道。'
	String get revealZonePointerHint => '本机没有悬停指针：这几块唤出区要鼠标贴住边缘才会生效。触屏上请在 Reader 独占时点左右两侧的窄轨来切换泳道。';

	/// zh-CN: '本泳道自定义 · 毫秒'
	String get laneCustomDelayMs => '本泳道自定义 · 毫秒';

	/// zh-CN: '继承全局：$ms 毫秒'
	String inheritedGlobalDelay({required Object ms}) => '继承全局：${ms} 毫秒';

	/// zh-CN: '分栏视图'
	String get fmViewColumns => '分栏视图';

	/// zh-CN: '树形视图'
	String get fmViewTree => '树形视图';

	/// zh-CN: '内容视图'
	String get fmViewContent => '内容视图';

	/// zh-CN: '默认内容布局'
	String get fmDefaultContentLayout => '默认内容布局';

	/// zh-CN: '默认条目样式'
	String get fmDefaultEntryStyle => '默认条目样式';

	/// zh-CN: '“最近使用”跟随当前活跃页签；“触发页签”跟随发起动作的页签。只继承浏览与搜索选项，查询、结果、历史和选中项各自独立。首次打开没有继承来源时使用预设。'
	String get fmTabPolicyHint => '“最近使用”跟随当前活跃页签；“触发页签”跟随发起动作的页签。只继承浏览与搜索选项，查询、结果、历史和选中项各自独立。首次打开没有继承来源时使用预设。';

	/// zh-CN: '选项来源'
	String get fmTabPolicySource => '选项来源';

	/// zh-CN: 'school_lolita | 学校萝莉 | School Lolita loli'
	String get favoriteTagExampleHint => 'school_lolita | 学校萝莉 | School Lolita\nloli';

	/// zh-CN: '未找到匹配的画师'
	String get noMatchingArtist => '未找到匹配的画师';

	/// zh-CN: '武田弘光 [circle (artist)] 水龙敬'
	String get favoriteArtistExampleHint => '武田弘光\n[circle (artist)]\n水龙敬';

	/// zh-CN: '确认重置 PIN'
	String get confirmResetPin => '确认重置 PIN';

	/// zh-CN: '泳道未单独设置延时时使用此值'
	String get defaultHoverDelaySubtitle => '泳道未单独设置延时时使用此值';

	/// zh-CN: '默认悬停定位延迟'
	String get defaultHoverDelay => '默认悬停定位延迟';

	/// zh-CN: '按下面选好的呈现打开；退出用系统返回键'
	String get enterWorkspaceSubtitle => '按下面选好的呈现打开；退出用系统返回键';

	/// zh-CN: '进入工作台'
	String get enterWorkspace => '进入工作台';

	/// zh-CN: '泳道右移'
	String get kanbanLaneMoveRight => '泳道右移';

	/// zh-CN: '泳道左移'
	String get kanbanLaneMoveLeft => '泳道左移';

	/// zh-CN: '下移面板'
	String get kanbanPanelMoveDown => '下移面板';

	/// zh-CN: '上移面板'
	String get kanbanPanelMoveUp => '上移面板';

	/// zh-CN: '默认隐藏'
	String get kanbanLaneDefaultHidden => '默认隐藏';

	/// zh-CN: '固定泳道'
	String get kanbanLanePinned => '固定泳道';

	/// zh-CN: '已彻底隐藏'
	String get kanbanFullyHidden => '已彻底隐藏';

	/// zh-CN: '显示中'
	String get kanbanVisible => '显示中';

	/// zh-CN: '恢复默认排布'
	String get kanbanRestoreDefault => '恢复默认排布';

	/// zh-CN: '使用看板调整泳道顺序、各泳道上面板的顺序以及显示与彻底隐藏'
	String get swimlanePanelKanbanDesc => '使用看板调整泳道顺序、各泳道上面板的顺序以及显示与彻底隐藏';

	/// zh-CN: '恢复继承全局延迟'
	String get laneHoverDelayInherit => '恢复继承全局延迟';

	/// zh-CN: '悬停定位延迟'
	String get laneHoverDelay => '悬停定位延迟';

	/// zh-CN: '停留后自动移动工作台，让本泳道完整显示'
	String get laneHoverRevealSubtitle => '停留后自动移动工作台，让本泳道完整显示';

	/// zh-CN: '悬停后完整显示'
	String get laneHoverReveal => '悬停后完整显示';

	/// zh-CN: '鼠标进入本泳道后，将键盘操作交给本泳道'
	String get laneKeyboardFollowsMouseSubtitle => '鼠标进入本泳道后，将键盘操作交给本泳道';

	/// zh-CN: '键盘目标跟随鼠标'
	String get laneKeyboardFollowsMouse => '键盘目标跟随鼠标';

	/// zh-CN: '泳道交互'
	String get laneInteraction => '泳道交互';

	/// zh-CN: '泳道顺序 · 各泳道面板排序 · 面板显示与彻底隐藏'
	String get swimlanePanelKanbanSubtitle => '泳道顺序 · 各泳道面板排序 · 面板显示与彻底隐藏';

	/// zh-CN: '泳道与面板看板'
	String get swimlanePanelKanban => '泳道与面板看板';

	/// zh-CN: '预设默认值仅在“使用预设默认值”时采用；默认递归范围沿用下方搜索设置。复制与恢复已关闭页签保留原有设置。'
	String get fmNewTabPresetHint => '预设默认值仅在“使用预设默认值”时采用；默认递归范围沿用下方搜索设置。复制与恢复已关闭页签保留原有设置。';

	/// zh-CN: '默认显示内部条目'
	String get fmNewTabShowInternal => '默认显示内部条目';

	/// zh-CN: '默认显示隐藏项'
	String get fmNewTabShowHidden => '默认显示隐藏项';

	/// zh-CN: '默认启用穿透'
	String get fmNewTabPassthrough => '默认启用穿透';

	/// zh-CN: '新页签启动选项'
	String get fmNewTabStartup => '新页签启动选项';

	/// zh-CN: '导入文件 (TXT/JSON/EMM setting.json)'
	String get importFileTxtJsonEmm => '导入文件 (TXT/JSON/EMM setting.json)';

	/// zh-CN: '搜索画师...'
	String get searchArtistHint => '搜索画师...';

	/// zh-CN: '导入文件 (TXT/JSON)'
	String get importFileTxtJson => '导入文件 (TXT/JSON)';

	/// zh-CN: 'Rust 解码 → wgpu → GPU 拷贝 → 共享纹理，像素不过桥'
	String get debugGpuPresentSubtitle => 'Rust 解码 → wgpu → GPU 拷贝 → 共享纹理，像素不过桥';

	/// zh-CN: 'GPU 上屏（D3D12 共享纹理）'
	String get debugGpuPresent => 'GPU 上屏（D3D12 共享纹理）';

	/// zh-CN: '选一张页 → 检测/识别/擦字/翻译/回填，逐段看耗时与产物'
	String get debugOcrSmokeSubtitle => '选一张页 → 检测/识别/擦字/翻译/回填，逐段看耗时与产物';

	/// zh-CN: 'OCR 成品页冒烟'
	String get debugOcrSmoke => 'OCR 成品页冒烟';

	/// zh-CN: '散图文件夹 / CBZ / CBR 直读，含逐页耗时与拒绝类别'
	String get debugLocalSourceSubtitle => '散图文件夹 / CBZ / CBR 直读，含逐页耗时与拒绝类别';

	/// zh-CN: '本地来源读取（判据 A）'
	String get debugLocalSource => '本地来源读取（判据 A）';

	/// zh-CN: '设置重置 PIN'
	String get setResetPin => '设置重置 PIN';

	/// zh-CN: '让 Rossi 更合你的习惯'
	String get overviewSubtitle => '让 Rossi 更合你的习惯';

	/// zh-CN: '搜索设置分类'
	String get searchCategories => '搜索设置分类';

	/// zh-CN: '没有匹配的分类，请尝试其他关键词'
	String get noMatchingCategories => '没有匹配的分类，请尝试其他关键词';

	/// zh-CN: '外观与反馈'
	String get personalizationGroup => '外观与反馈';

	/// zh-CN: '阅读与画面'
	String get readingGroup => '阅读与画面';

	/// zh-CN: '文件、书架与数据'
	String get libraryGroup => '文件、书架与数据';

	/// zh-CN: '应用与操作'
	String get applicationGroup => '应用与操作';

	/// zh-CN: '窗口'
	String get windowGroup => '窗口';

	/// zh-CN: '同步服务 · 云端备份'
	String get syncDestinationsSubtitle => '同步服务 · 云端备份';

	/// zh-CN: '设置'
	String get title => '设置';

	/// zh-CN: '设置'
	String get globalTitle => '设置';

	/// zh-CN: '外观与显示'
	String get appearance => '外观与显示';

	/// zh-CN: '主题模式'
	String get theme => '主题模式';

	/// zh-CN: '选择策略，切换明暗主题'
	String get themeSubtitle => '选择策略，切换明暗主题';

	/// zh-CN: '主题颜色'
	String get themeColor => '主题颜色';

	/// zh-CN: '导入 Tweakcn 主题'
	String get tweakcnTitle => '导入 Tweakcn 主题';

	/// zh-CN: '粘贴 tweakcn 复制的 CSS 变量，或 shadcn registry 的 JSON'
	String get tweakcnSubtitle => '粘贴 tweakcn 复制的 CSS 变量，或 shadcn registry 的 JSON';

	/// zh-CN: ':root { --background: oklch(1 0 0); --primary: oklch(0.628 0.258 29.2); }'
	String get tweakcnHint => ':root {\n  --background: oklch(1 0 0);\n  --primary: oklch(0.628 0.258 29.2);\n}';

	/// zh-CN: '导入'
	String get tweakcnImport => '导入';

	/// zh-CN: '主题名（可留空）'
	String get tweakcnNameField => '主题名（可留空）';

	/// zh-CN: '点一行即切为当前主题'
	String get tweakcnPickHint => '点一行即切为当前主题';

	/// zh-CN: '$count 个 token · 圆角 $radius'
	String tweakcnEntryMeta({required Object count, required Object radius}) => '${count} 个 token · 圆角 ${radius}';

	/// zh-CN: '删除该主题'
	String get tweakcnDelete => '删除该主题';

	/// zh-CN: '启用导入的主题'
	String get tweakcnEnabled => '启用导入的主题';

	/// zh-CN: '已导入 $count 个颜色 token · 圆角 $radius'
	String tweakcnApplied({required Object count, required Object radius}) => '已导入 ${count} 个颜色 token · 圆角 ${radius}';

	/// zh-CN: '沿用默认'
	String get tweakcnNoRadius => '沿用默认';

	/// zh-CN: '内容为空'
	String get tweakcnFailedEmpty => '内容为空';

	/// zh-CN: '不是能识别的 JSON'
	String get tweakcnFailedJson => '不是能识别的 JSON';

	/// zh-CN: '没有解析出任何颜色 token'
	String get tweakcnFailedNoColors => '没有解析出任何颜色 token';

	/// zh-CN: '以下 token 读不出颜色，已跳过：$keys'
	String tweakcnSkipped({required Object keys}) => '以下 token 读不出颜色，已跳过：${keys}';

	/// zh-CN: '主题没给这些必需 token，已自动补值：$roles'
	String tweakcnFallbackRoles({required Object roles}) => '主题没给这些必需 token，已自动补值：${roles}';

	/// zh-CN: '选择主色，统一应用视觉'
	String get themeColorSubtitle => '选择主色，统一应用视觉';

	/// zh-CN: '语言'
	String get language => '语言';

	/// zh-CN: '切换应用显示语言'
	String get languageSubtitle => '切换应用显示语言';

	/// zh-CN: '跟随系统'
	String get followSystemLanguage => '跟随系统';

	/// zh-CN: '简体中文 (zh_CN)'
	String get languageZhCn => '简体中文 (zh_CN)';

	/// zh-CN: 'English (en_US)'
	String get languageEnUs => 'English (en_US)';

	/// zh-CN: '语言设置已保存，重启应用后全部生效'
	String get languageChangedRestartHint => '语言设置已保存，重启应用后全部生效';

	/// zh-CN: '动态取色'
	String get dynamicColor => '动态取色';

	/// zh-CN: '开启后自动提取内容主色'
	String get dynamicColorSubtitle => '开启后自动提取内容主色';

	/// zh-CN: '字体设置'
	String get fontSettings => '字体设置';

	/// zh-CN: '自定义显示字体'
	String get fontSettingsSubtitle => '自定义显示字体';

	/// zh-CN: '纯黑模式'
	String get amoled => '纯黑模式';

	/// zh-CN: '开启后使用纯黑背景，适配 AMOLED'
	String get amoledSubtitle => '开启后使用纯黑背景，适配 AMOLED';

	/// zh-CN: '异形屏适配'
	String get notchAdaptation => '异形屏适配';

	/// zh-CN: '开启后预留安全区，避免内容遮挡'
	String get notchAdaptationSubtitle => '开启后预留安全区，避免内容遮挡';

	/// zh-CN: '透明标题栏'
	String get transparentDesktopTitleBar => '透明标题栏';

	/// zh-CN: '标题栏不再画底色，与页面背景连成一体（文字与窗口按钮可能因画面颜色而不易看清）；仅桌面端'
	String get transparentDesktopTitleBarSubtitle => '标题栏不再画底色，与页面背景连成一体（文字与窗口按钮可能因画面颜色而不易看清）；仅桌面端';

	/// zh-CN: '独立行'
	String get transparentTitleBarRow => '独立行';

	/// zh-CN: '标题栏仍占一行，只是不带底色；内容从它下面开始（默认）'
	String get transparentTitleBarRowSubtitle => '标题栏仍占一行，只是不带底色；内容从它下面开始（默认）';

	/// zh-CN: '融合浮层'
	String get transparentTitleBarOverlay => '融合浮层';

	/// zh-CN: '内容顶到窗口顶部，标题栏浮在画面之上'
	String get transparentTitleBarOverlaySubtitle => '内容顶到窗口顶部，标题栏浮在画面之上';

	/// zh-CN: '提示样式'
	String get toastStyle => '提示样式';

	/// zh-CN: '设置应用内提示条的位置、时长与大小'
	String get toastStyleSubtitle => '设置应用内提示条的位置、时长与大小';

	/// zh-CN: '位置与尺寸'
	String get toastSectionLayout => '位置与尺寸';

	/// zh-CN: '外观与行为'
	String get toastSectionAppearance => '外观与行为';

	/// zh-CN: '时长与动效'
	String get toastSectionBehavior => '时长与动效';

	/// zh-CN: '显示效果'
	String get toastSectionStyle => '显示效果';

	/// zh-CN: '位置'
	String get toastPosition => '位置';

	/// zh-CN: '提示条停靠在屏幕的哪个角'
	String get toastPositionSubtitle => '提示条停靠在屏幕的哪个角';

	/// zh-CN: '左上'
	String get toastPositionTopLeft => '左上';

	/// zh-CN: '顶部居中'
	String get toastPositionTopCenter => '顶部居中';

	/// zh-CN: '右上'
	String get toastPositionTopRight => '右上';

	/// zh-CN: '左侧居中'
	String get toastPositionMiddleLeft => '左侧居中';

	/// zh-CN: '屏幕居中'
	String get toastPositionCenter => '屏幕居中';

	/// zh-CN: '右侧居中'
	String get toastPositionMiddleRight => '右侧居中';

	/// zh-CN: '左下'
	String get toastPositionBottomLeft => '左下';

	/// zh-CN: '底部居中'
	String get toastPositionBottomCenter => '底部居中';

	/// zh-CN: '右下'
	String get toastPositionBottomRight => '右下';

	/// zh-CN: '边缘留白'
	String get toastEdgePadding => '边缘留白';

	/// zh-CN: '提示条与屏幕边缘的距离'
	String get toastEdgePaddingSubtitle => '提示条与屏幕边缘的距离';

	/// zh-CN: '最大宽度'
	String get toastMaxWidth => '最大宽度';

	/// zh-CN: '提示条宽度上限，窄屏还会再被屏幕宽度收一次'
	String get toastMaxWidthSubtitle => '提示条宽度上限，窄屏还会再被屏幕宽度收一次';

	/// zh-CN: '同屏条数'
	String get toastMaxVisible => '同屏条数';

	/// zh-CN: '屏幕上最多同时堆叠几条，多出来的挤掉最旧的一条'
	String get toastMaxVisibleSubtitle => '屏幕上最多同时堆叠几条，多出来的挤掉最旧的一条';

	/// zh-CN: '自动关闭时长'
	String get toastDuration => '自动关闭时长';

	/// zh-CN: '拖到最左边为常驻，只由关闭按钮收起'
	String get toastDurationSubtitle => '拖到最左边为常驻，只由关闭按钮收起';

	/// zh-CN: '常驻'
	String get toastDurationPermanent => '常驻';

	/// zh-CN: '不透明度'
	String get toastOpacity => '不透明度';

	/// zh-CN: '整条提示（含文字）的不透明度'
	String get toastOpacitySubtitle => '整条提示（含文字）的不透明度';

	/// zh-CN: '进出场动画'
	String get toastAnimation => '进出场动画';

	/// zh-CN: '提示出现与消失的动画时长'
	String get toastAnimationSubtitle => '提示出现与消失的动画时长';

	/// zh-CN: '液态玻璃'
	String get toastLiquidGlass => '液态玻璃';

	/// zh-CN: '开启后提示条使用模糊半透明背景'
	String get toastLiquidGlassSubtitle => '开启后提示条使用模糊半透明背景';

	/// zh-CN: '显示进度条'
	String get toastShowProgressBar => '显示进度条';

	/// zh-CN: '在底部显示一条随剩余时间收缩的细线'
	String get toastShowProgressBarSubtitle => '在底部显示一条随剩余时间收缩的细线';

	/// zh-CN: '显示类型图标'
	String get toastShowIcon => '显示类型图标';

	/// zh-CN: '在提示条左侧显示成功/错误等图标'
	String get toastShowIconSubtitle => '在提示条左侧显示成功/错误等图标';

	/// zh-CN: '显示关闭按钮'
	String get toastShowCloseButton => '显示关闭按钮';

	/// zh-CN: '常驻提示会始终显示关闭按钮'
	String get toastShowCloseButtonSubtitle => '常驻提示会始终显示关闭按钮';

	/// zh-CN: '显示测试提示'
	String get toastPreview => '显示测试提示';

	/// zh-CN: '提示样式预览'
	String get toastPreviewTitle => '提示样式预览';

	/// zh-CN: '这是一条用于预览的提示：长文本会自动换行，不会再被截断、也不会弹成对话框。'
	String get toastPreviewLongMessage => '这是一条用于预览的提示：长文本会自动换行，不会再被截断、也不会弹成对话框。';

	/// zh-CN: '恢复默认提示样式'
	String get toastReset => '恢复默认提示样式';

	/// zh-CN: '已恢复默认提示样式'
	String get toastResetDone => '已恢复默认提示样式';

	/// zh-CN: '内容与网络'
	String get contentAndNetwork => '内容与网络';

	/// zh-CN: '内容'
	String get content => '内容';

	/// zh-CN: '完整来源列表'
	String get fullSourceList => '完整来源列表';

	/// zh-CN: '关闭时，部分来源不会出现在发现页、搜索与插件商店；开启后显示全部来源'
	String get fullSourceListSubtitle => '关闭时，部分来源不会出现在发现页、搜索与插件商店；开启后显示全部来源';

	/// zh-CN: '网络'
	String get network => '网络';

	/// zh-CN: '屏蔽关键词'
	String get maskedKeywords => '屏蔽关键词';

	/// zh-CN: '添加关键词，过滤不想看到的内容（仅搜索生效）'
	String get maskedKeywordsSubtitle => '添加关键词，过滤不想看到的内容（仅搜索生效）';

	/// zh-CN: '暂无屏蔽词'
	String get maskedKeywordsEmpty => '暂无屏蔽词';

	/// zh-CN: '输入新关键词...'
	String get maskedKeywordsInputHint => '输入新关键词...';

	/// zh-CN: '喜欢画师高亮'
	String get favoriteArtistHighlight => '喜欢画师高亮';

	/// zh-CN: '在漫画卡片和详情页醒目标记喜欢的画师'
	String get favoriteArtistHighlightSubtitle => '在漫画卡片和详情页醒目标记喜欢的画师';

	/// zh-CN: '卡片角标'
	String get cardBadges => '卡片角标';

	/// zh-CN: '下载角标'
	String get cardDownloadBadge => '下载角标';

	/// zh-CN: '封面右上角显示下载按钮，点一下直接下载整本'
	String get cardDownloadBadgeSubtitle => '封面右上角显示下载按钮，点一下直接下载整本';

	/// zh-CN: '语言角标'
	String get cardTranslationBadge => '语言角标';

	/// zh-CN: '按标签识别「汉化 / 中文 / 生肉」并标记在封面左上角'
	String get cardTranslationBadgeSubtitle => '按标签识别「汉化 / 中文 / 生肉」并标记在封面左上角';

	/// zh-CN: '阅读按钮'
	String get cardReadButton => '阅读按钮';

	/// zh-CN: '封面正中显示阅读按钮，点一下直接起读（有进度就续读），不必先进详情页'
	String get cardReadButtonSubtitle => '封面正中显示阅读按钮，点一下直接起读（有进度就续读），不必先进详情页';

	/// zh-CN: '未读标识'
	String get cardUnreadIndicator => '未读标识';

	/// zh-CN: '下载后还没读过的书，在封面右上角的下载角标下方显示标识'
	String get cardUnreadIndicatorSubtitle => '下载后还没读过的书，在封面右上角的下载角标下方显示标识';

	/// zh-CN: '未读标识样式'
	String get cardUnreadIndicatorStyle => '未读标识样式';

	/// zh-CN: '三档辨识度递增、占的封面面积也递增，按观感自己挑'
	String get cardUnreadIndicatorStyleSubtitle => '三档辨识度递增、占的封面面积也递增，按观感自己挑';

	/// zh-CN: '圆点'
	String get cardUnreadIndicatorStyleDot => '圆点';

	/// zh-CN: '圆片'
	String get cardUnreadIndicatorStyleDisc => '圆片';

	/// zh-CN: '文字'
	String get cardUnreadIndicatorStyleLabel => '文字';

	/// zh-CN: '卡片交互'
	String get cardInteraction => '卡片交互';

	/// zh-CN: '收藏 / 历史卡片右键菜单'
	String get shelfCardContextMenu => '收藏 / 历史卡片右键菜单';

	/// zh-CN: '右键条目弹出操作菜单（触摸端长按）；含打开、在文件管理新页签打开、复制标题与链接、收藏、移除'
	String get shelfCardContextMenuSubtitle => '右键条目弹出操作菜单（触摸端长按）；含打开、在文件管理新页签打开、复制标题与链接、收藏、移除';

	/// zh-CN: '喜欢画师管理'
	String get favoriteArtistManagement => '喜欢画师管理';

	/// zh-CN: '已添加 $count 位画师'
	String favoriteArtistManagementSubtitle({required Object count}) => '已添加 ${count} 位画师';

	/// zh-CN: '暂未添加画师'
	String get favoriteArtistManagementSubtitleEmpty => '暂未添加画师';

	/// zh-CN: '输入画师名称...'
	String get favoriteArtistInputHint => '输入画师名称...';

	/// zh-CN: '添加'
	String get favoriteArtistAdd => '添加';

	/// zh-CN: '批量导入/编辑'
	String get favoriteArtistBatchImport => '批量导入/编辑';

	/// zh-CN: '每行输入一位画师或逗号分隔；[社团 (画师)] 会原样保留，两个名字都参与匹配'
	String get favoriteArtistBatchImportHint => '每行输入一位画师或逗号分隔；[社团 (画师)] 会原样保留，两个名字都参与匹配';

	/// zh-CN: '已更新画师列表（共 $count 位）'
	String favoriteArtistImportSuccess({required Object count}) => '已更新画师列表（共 ${count} 位）';

	/// zh-CN: '清空全部'
	String get favoriteArtistClear => '清空全部';

	/// zh-CN: '确定要清空所有喜欢的画师吗？'
	String get favoriteArtistClearConfirm => '确定要清空所有喜欢的画师吗？';

	/// zh-CN: '社团名匹配'
	String get favoriteArtistCircleMode => '社团名匹配';

	/// zh-CN: '标题或标签里的社团名算不算命中喜欢画师'
	String get favoriteArtistCircleModeSubtitle => '标题或标签里的社团名算不算命中喜欢画师';

	/// zh-CN: '不认社团名'
	String get favoriteArtistCircleOff => '不认社团名';

	/// zh-CN: '仅在没有画师名时'
	String get favoriteArtistCircleFallback => '仅在没有画师名时';

	/// zh-CN: '独立命中（画师优先）'
	String get favoriteArtistCircleIndependent => '独立命中（画师优先）';

	/// zh-CN: '喜欢画师'
	String get favoriteArtistBadge => '喜欢画师';

	/// zh-CN: '设为喜欢画师'
	String get addToFavoriteArtist => '设为喜欢画师';

	/// zh-CN: '取消喜欢画师'
	String get removeFromFavoriteArtist => '取消喜欢画师';

	/// zh-CN: '已添加到喜欢画师: $name'
	String addedToFavoriteArtist({required Object name}) => '已添加到喜欢画师: ${name}';

	/// zh-CN: '已从喜欢画师移除: $name'
	String removedFromFavoriteArtist({required Object name}) => '已从喜欢画师移除: ${name}';

	/// zh-CN: '收藏 tag 高亮'
	String get favoriteTagHighlight => '收藏 tag 高亮';

	/// zh-CN: '在漫画卡片和详情页醒目标记收藏的 tag'
	String get favoriteTagHighlightSubtitle => '在漫画卡片和详情页醒目标记收藏的 tag';

	/// zh-CN: '收藏 tag 管理'
	String get favoriteTagManagement => '收藏 tag 管理';

	/// zh-CN: '已添加 $count 个 tag'
	String favoriteTagManagementSubtitle({required Object count}) => '已添加 ${count} 个 tag';

	/// zh-CN: '暂未添加 tag'
	String get favoriteTagManagementSubtitleEmpty => '暂未添加 tag';

	/// zh-CN: '输入 tag 名称...'
	String get favoriteTagInputHint => '输入 tag 名称...';

	/// zh-CN: '收藏'
	String get favoriteTagAdd => '收藏';

	/// zh-CN: '搜索 tag...'
	String get favoriteTagSearchHint => '搜索 tag...';

	/// zh-CN: '未找到匹配的 tag'
	String get favoriteTagNotFound => '未找到匹配的 tag';

	/// zh-CN: '批量导入/编辑'
	String get favoriteTagBatchImport => '批量导入/编辑';

	/// zh-CN: '每行一个 tag；别名用 | 分隔，用于适配各站点的写法，例如 school_lolita | 学校萝莉 | School Lolita'
	String get favoriteTagBatchImportHint => '每行一个 tag；别名用 | 分隔，用于适配各站点的写法，例如 school_lolita | 学校萝莉 | School Lolita';

	/// zh-CN: '已更新收藏 tag（共 $count 个）'
	String favoriteTagImportSuccess({required Object count}) => '已更新收藏 tag（共 ${count} 个）';

	/// zh-CN: '清空全部'
	String get favoriteTagClear => '清空全部';

	/// zh-CN: '确定要清空所有收藏 tag 吗？'
	String get favoriteTagClearConfirm => '确定要清空所有收藏 tag 吗？';

	/// zh-CN: '收藏 Tag'
	String get favoriteTagBadge => '收藏 Tag';

	/// zh-CN: '别名'
	String get favoriteTagAliasSection => '别名';

	/// zh-CN: '未设置别名'
	String get favoriteTagAliasEmpty => '未设置别名';

	/// zh-CN: '添加别名'
	String get favoriteTagAliasAdd => '添加别名';

	/// zh-CN: '该 tag 在某个站点里的写法...'
	String get favoriteTagAliasInputHint => '该 tag 在某个站点里的写法...';

	/// zh-CN: '别名用于适配不同图源对同一个 tag 的不同拼法；大小写、全半角和下划线的差异已经自动归一，不必再登记。'
	String get favoriteTagAliasHint => '别名用于适配不同图源对同一个 tag 的不同拼法；大小写、全半角和下划线的差异已经自动归一，不必再登记。';

	/// zh-CN: '已收藏 tag: $name'
	String favoriteTagAdded({required Object name}) => '已收藏 tag: ${name}';

	/// zh-CN: '已取消收藏 tag: $name'
	String favoriteTagRemoved({required Object name}) => '已取消收藏 tag: ${name}';

	/// zh-CN: '已经收藏过这个 tag: $name'
	String favoriteTagAlreadyAdded({required Object name}) => '已经收藏过这个 tag: ${name}';

	/// zh-CN: '已添加别名: $name'
	String favoriteTagAliasAdded({required Object name}) => '已添加别名: ${name}';

	/// zh-CN: '已移除别名: $name'
	String favoriteTagAliasRemoved({required Object name}) => '已移除别名: ${name}';

	/// zh-CN: '这个别名已经存在了'
	String get favoriteTagAliasDuplicate => '这个别名已经存在了';

	/// zh-CN: '收藏此 tag'
	String get addToFavoriteTag => '收藏此 tag';

	/// zh-CN: '取消收藏此 tag'
	String get removeFromFavoriteTag => '取消收藏此 tag';

	/// zh-CN: '收藏 tag 角标'
	String get cardFavoriteTagBadge => '收藏 tag 角标';

	/// zh-CN: '命中收藏 tag 时在封面左上角显示角标'
	String get cardFavoriteTagBadgeSubtitle => '命中收藏 tag 时在封面左上角显示角标';

	/// zh-CN: '简繁转换'
	String get chineseConvert => '简繁转换';

	/// zh-CN: '将漫画标题、简介、章节、评论等转为简体或繁体'
	String get chineseConvertSubtitle => '将漫画标题、简介、章节、评论等转为简体或繁体';

	/// zh-CN: '关闭'
	String get chineseConvertOff => '关闭';

	/// zh-CN: '简体中文'
	String get chineseConvertSimplified => '简体中文';

	/// zh-CN: '繁体中文'
	String get chineseConvertTraditional => '繁体中文';

	/// zh-CN: '代理'
	String get proxy => '代理';

	/// zh-CN: '配置代理地址'
	String get proxySubtitle => '配置代理地址';

	/// zh-CN: '开启后网络请求将经过代理'
	String get proxyEnabledSubtitle => '开启后网络请求将经过代理';

	/// zh-CN: '代理地址'
	String get proxyAddress => '代理地址';

	/// zh-CN: '请输入代理地址（HTTP / SOCKS5）'
	String get proxyHint => '请输入代理地址（HTTP / SOCKS5）';

	/// zh-CN: '当前代理：$currentProxy'
	String proxyCurrent({required Object currentProxy}) => '当前代理：${currentProxy}';

	/// zh-CN: '代理类型'
	String get proxyType => '代理类型';

	/// zh-CN: '选择代理协议'
	String get proxyTypeSubtitle => '选择代理协议';

	/// zh-CN: 'HTTP'
	String get proxyTypeHttp => 'HTTP';

	/// zh-CN: 'SOCKS5'
	String get proxyTypeSocks5 => 'SOCKS5';

	/// zh-CN: '更新下载加速'
	String get updateAccelerate => '更新下载加速';

	/// zh-CN: '开启后优先使用代理加速 GitHub 更新链接'
	String get updateAccelerateSubtitle => '开启后优先使用代理加速 GitHub 更新链接';

	/// zh-CN: '下载失败后持续重试'
	String get retryDownloadUntilSuccess => '下载失败后持续重试';

	/// zh-CN: '下载失败时持续重试直到成功；返回 404 或空数据时停止重试'
	String get retryDownloadUntilSuccessSubtitle => '下载失败时持续重试直到成功；返回 404 或空数据时停止重试';

	/// zh-CN: '下载设置'
	String get downloadSettings => '下载设置';

	/// zh-CN: '下载并发数'
	String get downloadConcurrency => '下载并发数';

	/// zh-CN: '同时下载图片的线程数，若经常遇到风控或限流建议设为 2~3'
	String get downloadConcurrencySubtitle => '同时下载图片的线程数，若经常遇到风控或限流建议设为 2~3';

	/// zh-CN: '同时下载章节数'
	String get downloadTaskConcurrency => '同时下载章节数';

	/// zh-CN: '同时下载几个章节；1 = 逐个下载，遇到风控或验证码时调小'
	String get downloadTaskConcurrencySubtitle => '同时下载几个章节；1 = 逐个下载，遇到风控或验证码时调小';

	/// zh-CN: '单图下载延时'
	String get downloadDelay => '单图下载延时';

	/// zh-CN: '每次图片请求之间的节流间隔，可有效规避源站风控 (429)'
	String get downloadDelaySubtitle => '每次图片请求之间的节流间隔，可有效规避源站风控 (429)';

	/// zh-CN: '失败自动重试次数'
	String get downloadAutoRetryCount => '失败自动重试次数';

	/// zh-CN: '任务遇到网络偶发异常时自动退避重试的上限次数'
	String get downloadAutoRetryCountSubtitle => '任务遇到网络偶发异常时自动退避重试的上限次数';

	/// zh-CN: '同步'
	String get sync => '同步';

	/// zh-CN: '同步配置'
	String get syncConfig => '同步配置';

	/// zh-CN: '进入页面，配置地址与鉴权信息'
	String get syncConfigSubtitle => '进入页面，配置地址与鉴权信息';

	/// zh-CN: '同步服务'
	String get syncService => '同步服务';

	/// zh-CN: '选择服务，统一管理同步策略'
	String get syncServiceSubtitle => '选择服务，统一管理同步策略';

	/// zh-CN: '不启用'
	String get syncServiceNone => '不启用';

	/// zh-CN: 'WebDAV'
	String get syncServiceWebdav => 'WebDAV';

	/// zh-CN: 'S3'
	String get syncServiceS3 => 'S3';

	/// zh-CN: '自动同步'
	String get autoSync => '自动同步';

	/// zh-CN: '开启后在后台定期同步配置'
	String get autoSyncSubtitle => '开启后在后台定期同步配置';

	/// zh-CN: '提示个性化'
	String get notifyPersonalize => '提示个性化';

	/// zh-CN: '决定哪些后台提示会打扰你；你主动操作的回应始终会显示'
	String get notifyPersonalizeSubtitle => '决定哪些后台提示会打扰你；你主动操作的回应始终会显示';

	/// zh-CN: '后台提示总闸已关'
	String get notifySummaryMasterOff => '后台提示总闸已关';

	/// zh-CN: '后台提示全部会响'
	String get notifySummaryAllOn => '后台提示全部会响';

	/// zh-CN: '已静音 $count 项'
	String notifySummaryOffCount({required Object count}) => '已静音 ${count} 项';

	/// zh-CN: '后台自动提示'
	String get notifySectionAmbient => '后台自动提示';

	/// zh-CN: '自动提示'
	String get notifyMaster => '自动提示';

	/// zh-CN: '总闸。关掉后下面这些全部静默；按钮的操作反馈不受影响'
	String get notifyMasterHint => '总闸。关掉后下面这些全部静默；按钮的操作反馈不受影响';

	/// zh-CN: '总闸已关：下面这些值给你留着，但现在一律不响。'
	String get notifyMasterOffNote => '总闸已关：下面这些值给你留着，但现在一律不响。';

	/// zh-CN: '这两类不归这张表管'
	String get notifySectionOutside => '这两类不归这张表管';

	/// zh-CN: '系统通知栏那一路（下载完成、追更）由系统管，要关去系统设置里关，这里关不掉它'
	String get notifySystemChannelNote => '系统通知栏那一路（下载完成、追更）由系统管，要关去系统设置里关，这里关不掉它';

	/// zh-CN: '（另有 $count 次同类提示）'
	String notifyMergedSuffix({required Object count}) => '（另有 ${count} 次同类提示）';

	/// zh-CN: '操作反馈'
	String get notifyTopicAction => '操作反馈';

	/// zh-CN: '点了按钮之后的回应，永远会显示，否则读起来像按钮坏了'
	String get notifyTopicActionHint => '点了按钮之后的回应，永远会显示，否则读起来像按钮坏了';

	/// zh-CN: '阅读器切换提示'
	String get notifyTopicReaderSwitch => '阅读器切换提示';

	/// zh-CN: '切书 / 翻页 / 触到最后一页那三条开关，在工作台的「切换提示」卡片里'
	String get notifyTopicReaderSwitchHint => '切书 / 翻页 / 触到最后一页那三条开关，在工作台的「切换提示」卡片里';

	/// zh-CN: '自动同步完成'
	String get notifyTopicSyncAutoSuccess => '自动同步完成';

	/// zh-CN: '每 5 分钟一次的定期同步；同一句话 10 分钟内最多响一次'
	String get notifyTopicSyncAutoSuccessHint => '每 5 分钟一次的定期同步；同一句话 10 分钟内最多响一次';

	/// zh-CN: '自动同步失败'
	String get notifyTopicSyncAutoFailure => '自动同步失败';

	/// zh-CN: '配错或断网时过去每 5 分钟敲一次且关不掉；现在同一类错误 10 分钟合并成一条'
	String get notifyTopicSyncAutoFailureHint => '配错或断网时过去每 5 分钟敲一次且关不掉；现在同一类错误 10 分钟合并成一条';

	/// zh-CN: '下载完成'
	String get notifyTopicDownloadComplete => '下载完成';

	/// zh-CN: '每完成一本报一次；同一本的重复回调 60 秒内合并'
	String get notifyTopicDownloadCompleteHint => '每完成一本报一次；同一本的重复回调 60 秒内合并';

	/// zh-CN: '下载失败'
	String get notifyTopicDownloadFailed => '下载失败';

	/// zh-CN: '报错文案不同算不同的事，不互相合并'
	String get notifyTopicDownloadFailedHint => '报错文案不同算不同的事，不互相合并';

	/// zh-CN: '追更更新'
	String get notifyTopicFollowUpdate => '追更更新';

	/// zh-CN: '启动后那一次自动检查；手动刷新追更算操作反馈，不会被静音'
	String get notifyTopicFollowUpdateHint => '启动后那一次自动检查；手动刷新追更算操作反馈，不会被静音';

	/// zh-CN: '插件脚本报信'
	String get notifyTopicPluginMessage => '插件脚本报信';

	/// zh-CN: '图源插件自己调出来的提示；脚本能在循环里连发，同一句话 3 秒内合并'
	String get notifyTopicPluginMessageHint => '图源插件自己调出来的提示；脚本能在循环里连发，同一句话 3 秒内合并';

	/// zh-CN: '外部打开'
	String get notifyTopicIntentOpen => '外部打开';

	/// zh-CN: '从系统右键菜单或链接调起时的落点提示'
	String get notifyTopicIntentOpenHint => '从系统右键菜单或链接调起时的落点提示';

	/// zh-CN: '通知权限'
	String get notifyTopicSystemPermission => '通知权限';

	/// zh-CN: '启动时申请系统通知权限被拒的那条提示'
	String get notifyTopicSystemPermissionHint => '启动时申请系统通知权限被拒的那条提示';

	/// zh-CN: '同步设置'
	String get syncSettings => '同步设置';

	/// zh-CN: '开启后使用云端设置覆盖本地设置'
	String get syncSettingsSubtitle => '开启后使用云端设置覆盖本地设置';

	/// zh-CN: '同步插件'
	String get syncPlugins => '同步插件';

	/// zh-CN: '开启后同步插件配置与安装状态'
	String get syncPluginsSubtitle => '开启后同步插件配置与安装状态';

	/// zh-CN: '手动同步'
	String get manualSyncSection => '手动同步';

	/// zh-CN: '上传到云端'
	String get uploadToCloud => '上传到云端';

	/// zh-CN: '以本机数据为准，覆盖云端'
	String get uploadToCloudSubtitle => '以本机数据为准，覆盖云端';

	/// zh-CN: '从云端同步到本机'
	String get downloadFromCloud => '从云端同步到本机';

	/// zh-CN: '以云端数据为准，应用到本机'
	String get downloadFromCloudSubtitle => '以云端数据为准，应用到本机';

	/// zh-CN: '立即上传'
	String get manualUpload => '立即上传';

	/// zh-CN: '立即同步'
	String get manualDownload => '立即同步';

	/// zh-CN: '已上传到云端'
	String get manualUploadSuccess => '已上传到云端';

	/// zh-CN: '已从云端同步到本机'
	String get manualDownloadSuccess => '已从云端同步到本机';

	/// zh-CN: '手动同步失败'
	String get manualSyncFailed => '手动同步失败';

	/// zh-CN: '应用行为'
	String get appBehavior => '应用行为';

	/// zh-CN: '开屏页'
	String get splashPage => '开屏页';

	/// zh-CN: '选择启动页，打开应用直达目标'
	String get splashPageSubtitle => '选择启动页，打开应用直达目标';

	/// zh-CN: '工作台'
	String get startWithWorkspace => '工作台';

	/// zh-CN: '工作台盖住首页时休眠'
	String get workspaceSleepCoveredUi => '工作台盖住首页时休眠';

	/// zh-CN: '进工作台后释放底下列表的图片内存，退回时重新加载'
	String get workspaceSleepCoveredUiSubtitle => '进工作台后释放底下列表的图片内存，退回时重新加载';

	/// zh-CN: '右键面板图标收起该面板'
	String get panelTabRightClickHide => '右键面板图标收起该面板';

	/// zh-CN: '关掉后，泳道面板栏上的图标只负责切换面板，右键与长按不再收起面板。收起是静默的：图标会直接从面板栏消失，面板栏上没有恢复入口，误触后要回「泳道与面板看板」才能找回。'
	String get panelTabRightClickHideSubtitle => '关掉后，泳道面板栏上的图标只负责切换面板，右键与长按不再收起面板。收起是静默的：图标会直接从面板栏消失，面板栏上没有恢复入口，误触后要回「泳道与面板看板」才能找回。';

	/// zh-CN: '跳过更新检查'
	String get skipUpdateCheck => '跳过更新检查';

	/// zh-CN: '本构建是 fork 版本，启动时不再请求上游最新版本，也不再弹出更新提示'
	String get skipUpdateCheckSubtitle => '本构建是 fork 版本，启动时不再请求上游最新版本，也不再弹出更新提示';

	/// zh-CN: '关闭行为'
	String get desktopCloseBehavior => '关闭行为';

	/// zh-CN: '选择点击关闭按钮时的行为'
	String get desktopCloseBehaviorSubtitle => '选择点击关闭按钮时的行为';

	/// zh-CN: '询问'
	String get desktopCloseAsk => '询问';

	/// zh-CN: '隐藏到托盘'
	String get desktopCloseHide => '隐藏到托盘';

	/// zh-CN: '直接关闭'
	String get desktopCloseClose => '直接关闭';

	/// zh-CN: '显示主界面'
	String get showMainWindow => '显示主界面';

	/// zh-CN: '退出'
	String get exitApp => '退出';

	/// zh-CN: '应用锁'
	String get appLock => '应用锁';

	/// zh-CN: '开启后进入应用需要验证'
	String get appLockSubtitle => '开启后进入应用需要验证';

	/// zh-CN: '收藏自动追更'
	String get autoFollowOnCollect => '收藏自动追更';

	/// zh-CN: '开启后收藏漫画时将自动加入追更列表'
	String get autoFollowOnCollectSubtitle => '开启后收藏漫画时将自动加入追更列表';

	/// zh-CN: '下载自动收藏'
	String get autoFavoriteOnDownload => '下载自动收藏';

	/// zh-CN: '开启后下载漫画时将自动加入本地收藏'
	String get autoFavoriteOnDownloadSubtitle => '开启后下载漫画时将自动加入本地收藏';

	/// zh-CN: '下载写入元数据文件'
	String get writeDownloadMetadataFile => '下载写入元数据文件';

	/// zh-CN: '下载完成后在漫画目录写入 original_comic_info.json 与 processed_comic_info.json，便于其他工具识别与再次导入'
	String get writeDownloadMetadataFileSubtitle => '下载完成后在漫画目录写入 original_comic_info.json 与 processed_comic_info.json，便于其他工具识别与再次导入';

	/// zh-CN: '下载时询问选项'
	String get promptDownloadOptions => '下载时询问选项';

	/// zh-CN: '点下载时先选「整本 / 最近章节 / 挑选章节」；关闭后直接下载全部章节'
	String get promptDownloadOptionsSubtitle => '点下载时先选「整本 / 最近章节 / 挑选章节」；关闭后直接下载全部章节';

	/// zh-CN: '左手优化'
	String get leftHandMode => '左手优化';

	/// zh-CN: '开启后将悬浮按钮等操作按钮移到屏幕左侧'
	String get leftHandModeSubtitle => '开启后将悬浮按钮等操作按钮移到屏幕左侧';

	/// zh-CN: '点击封面开始阅读'
	String get clickCoverToStartReading => '点击封面开始阅读';

	/// zh-CN: '在漫画详情页点击封面直接开始阅读'
	String get clickCoverToStartReadingSubtitle => '在漫画详情页点击封面直接开始阅读';

	/// zh-CN: '搜索历史按插件分时间线'
	String get searchHistoryGroupBySource => '搜索历史按插件分时间线';

	/// zh-CN: '开启后每个图源各自一条搜索时间线，不再全部堆在一起；「聚合搜索」是跨全部插件搜出来的，「未分类」是这次改造之前留下的老记录，归属已经丢了'
	String get searchHistoryGroupBySourceSubtitle => '开启后每个图源各自一条搜索时间线，不再全部堆在一起；「聚合搜索」是跨全部插件搜出来的，「未分类」是这次改造之前留下的老记录，归属已经丢了';

	/// zh-CN: '详情页内置阅读按钮'
	String get comicInfoInlineReadButton => '详情页内置阅读按钮';

	/// zh-CN: '桌面端在操作行里「下载」旁边放一个阅读按钮，并撤掉右下角的悬浮按钮'
	String get comicInfoInlineReadButtonSubtitle => '桌面端在操作行里「下载」旁边放一个阅读按钮，并撤掉右下角的悬浮按钮';

	/// zh-CN: '详情页操作栏液态玻璃'
	String get comicInfoRailLiquidGlass => '详情页操作栏液态玻璃';

	/// zh-CN: '桌面端左右两颗悬浮胶囊改用液态玻璃材质；关掉则换成不透明实底加描边'
	String get comicInfoRailLiquidGlassSubtitle => '桌面端左右两颗悬浮胶囊改用液态玻璃材质；关掉则换成不透明实底加描边';

	/// zh-CN: '后台保活'
	String get androidKeepAlive => '后台保活';

	/// zh-CN: '开启后通过前台服务尽量保持应用在后台运行，会显示常驻通知'
	String get androidKeepAliveSubtitle => '开启后通过前台服务尽量保持应用在后台运行，会显示常驻通知';

	/// zh-CN: '返回键退出'
	String get backPressExit => '返回键退出';

	/// zh-CN: '开启后在首页按返回键将退出应用，关闭则仅返回首页'
	String get backPressExitSubtitle => '开启后在首页按返回键将退出应用，关闭则仅返回首页';

	/// zh-CN: '书架设置'
	String get bookshelf => '书架设置';

	/// zh-CN: '书架首页、记忆排序'
	String get bookshelfSubtitle => '书架首页、记忆排序';

	/// zh-CN: '书架首页'
	String get bookshelfHomePage => '书架首页';

	/// zh-CN: '选择书架默认展示的标签'
	String get bookshelfHomePageSubtitle => '选择书架默认展示的标签';

	/// zh-CN: '收藏记忆排序'
	String get bookshelfRememberFavoriteSort => '收藏记忆排序';

	/// zh-CN: '开启后，收藏页会记住你最后一次选择的排序'
	String get bookshelfRememberFavoriteSortSubtitle => '开启后，收藏页会记住你最后一次选择的排序';

	/// zh-CN: '历史记忆排序'
	String get bookshelfRememberHistorySort => '历史记忆排序';

	/// zh-CN: '开启后，历史页会记住你最后一次选择的排序'
	String get bookshelfRememberHistorySortSubtitle => '开启后，历史页会记住你最后一次选择的排序';

	/// zh-CN: '下载记忆排序'
	String get bookshelfRememberDownloadSort => '下载记忆排序';

	/// zh-CN: '开启后，下载页会记住你最后一次选择的排序'
	String get bookshelfRememberDownloadSortSubtitle => '开启后，下载页会记住你最后一次选择的排序';

	/// zh-CN: '自定义导出路径'
	String get customExportPath => '自定义导出路径';

	/// zh-CN: '导出包含封面图'
	String get exportIncludeCover => '导出包含封面图';

	/// zh-CN: '打开后，导出的文件夹或 zip 里会额外带一张封面图（导出时要现场再取一次封面）。默认关：产物里只有该导的页和两份信息 JSON，封面仍按 JSON 里的地址在线显示'
	String get exportIncludeCoverSubtitle => '打开后，导出的文件夹或 zip 里会额外带一张封面图（导出时要现场再取一次封面）。默认关：产物里只有该导的页和两份信息 JSON，封面仍按 JSON 里的地址在线显示';

	/// zh-CN: '详情布局'
	String get detailLayout => '详情布局';

	/// zh-CN: '开启后漫画列表显示为横排详情样式，含作者与分类信息'
	String get detailLayoutSubtitle => '开启后漫画列表显示为横排详情样式，含作者与分类信息';

	/// zh-CN: '章节倒序'
	String get reverseChapters => '章节倒序';

	/// zh-CN: '开启后漫画详情页章节默认倒序显示'
	String get reverseChaptersSubtitle => '开启后漫画详情页章节默认倒序显示';

	/// zh-CN: '存储'
	String get storage => '存储';

	/// zh-CN: '缓存'
	String get cache => '缓存';

	/// zh-CN: '清理缓存'
	String get clearCache => '清理缓存';

	/// zh-CN: '确定要清理所有缓存文件吗？此操作不可撤销。'
	String get clearCacheConfirm => '确定要清理所有缓存文件吗？此操作不可撤销。';

	/// zh-CN: '计算中...'
	String get calculatingCache => '计算中...';

	/// zh-CN: '计算失败'
	String get calculateCacheFailed => '计算失败';

	/// zh-CN: '本地导入/导出'
	String get dataBackup => '本地导入/导出';

	/// zh-CN: '通过 ZIP 在移动端与桌面端迁移设置和数据，保留本机专属配置'
	String get dataBackupSubtitle => '通过 ZIP 在移动端与桌面端迁移设置和数据，保留本机专属配置';

	/// zh-CN: '包含下载的漫画'
	String get includeDownloaded => '包含下载的漫画';

	/// zh-CN: '导出数据'
	String get exportData => '导出数据';

	/// zh-CN: '导入数据'
	String get importData => '导入数据';

	/// zh-CN: '图片处理'
	String get imageProcessing => '图片处理';

	/// zh-CN: '图片超分（实验性）'
	String get realSr => '图片超分（实验性）';

	/// zh-CN: '漫画翻译（成品页）'
	String get ocr => '漫画翻译（成品页）';

	/// zh-CN: '试验性功能，需下载权重与配置翻译端点'
	String get ocrSubtitle => '试验性功能，需下载权重与配置翻译端点';

	/// zh-CN: '试验性功能，可能不稳定'
	String get realSrSubtitle => '试验性功能，可能不稳定';

	/// zh-CN: '墨水屏'
	String get eink => '墨水屏';

	/// zh-CN: '翻页动画 · 整屏刷新 · 加载'
	String get einkSubtitle => '翻页动画 · 整屏刷新 · 加载';

	/// zh-CN: '墨水屏适配'
	String get einkPageTitle => '墨水屏适配';

	/// zh-CN: '已识别为墨水屏设备'
	String get einkDetected => '已识别为墨水屏设备';

	/// zh-CN: '未识别到墨水屏设备，可手动开启'
	String get einkNotDetected => '未识别到墨水屏设备，可手动开启';

	/// zh-CN: '启用墨水屏模式'
	String get einkEnabled => '启用墨水屏模式';

	/// zh-CN: '去除动画，并让屏幕定期整屏刷新'
	String get einkEnabledSubtitle => '去除动画，并让屏幕定期整屏刷新';

	/// zh-CN: '动画与过渡'
	String get einkSectionAnimation => '动画与过渡';

	/// zh-CN: '去除页面切换动画'
	String get einkNoRouteTransition => '去除页面切换动画';

	/// zh-CN: '进入和退出页面直接出图，不做滑动淡入'
	String get einkNoRouteTransitionSubtitle => '进入和退出页面直接出图，不做滑动淡入';

	/// zh-CN: '去除滚动回弹'
	String get einkNoScrollBounce => '去除滚动回弹';

	/// zh-CN: '长图模式拖到边界直接停住'
	String get einkNoScrollBounceSubtitle => '长图模式拖到边界直接停住';

	/// zh-CN: '加载'
	String get einkSectionLoading => '加载';

	/// zh-CN: '刷新'
	String get einkSectionRefresh => '刷新';

	/// zh-CN: '整屏刷新方式'
	String get einkRefreshMode => '整屏刷新方式';

	/// zh-CN: '不刷新'
	String get einkRefreshNone => '不刷新';

	/// zh-CN: '白屏刷'
	String get einkRefreshWhite => '白屏刷';

	/// zh-CN: '黑白全刷'
	String get einkRefreshFull => '黑白全刷';

	/// zh-CN: '整屏刷新会闪一次白或黑白，用来清掉上一页残影。'
	String get einkRefreshHint => '整屏刷新会闪一次白或黑白，用来清掉上一页残影。';

	/// zh-CN: '立即整屏刷新'
	String get einkRefreshNow => '立即整屏刷新';

	/// zh-CN: '已完成整屏刷新'
	String get einkRefreshDone => '已完成整屏刷新';

	/// zh-CN: '每翻 N 页自动整屏刷新'
	String get einkAutoRefreshTurns => '每翻 N 页自动整屏刷新';

	/// zh-CN: '不自动刷新'
	String get einkAutoRefreshOff => '不自动刷新';

	/// zh-CN: '显示刷新按钮'
	String get einkShowRefreshButton => '显示刷新按钮';

	/// zh-CN: '阅读页角落常驻，随时手动整屏刷新'
	String get einkShowRefreshButtonSubtitle => '阅读页角落常驻，随时手动整屏刷新';

	/// zh-CN: '加载时不转圈'
	String get einkNoSpinner => '加载时不转圈';

	/// zh-CN: '转圈动画会让墨水屏反复局刷并留下残影'
	String get einkNoSpinnerSubtitle => '转圈动画会让墨水屏反复局刷并留下残影';

	/// zh-CN: '自动超分'
	String get autoRealSr => '自动超分';

	/// zh-CN: '分辨率阈值'
	String get resolutionThreshold => '分辨率阈值';

	/// zh-CN: '调试'
	String get debug => '调试';

	/// zh-CN: '日志转发地址'
	String get logAddress => '日志转发地址';

	/// zh-CN: '配置后实时转发日志到指定地址'
	String get logAddressSubtitle => '配置后实时转发日志到指定地址';

	/// zh-CN: '内存调试'
	String get memoryDebug => '内存调试';

	/// zh-CN: '开启后在界面显示内存占用信息'
	String get memoryDebugSubtitle => '开启后在界面显示内存占用信息';

	/// zh-CN: '拦截 Rust HTTP 请求'
	String get blockRustHttpRequests => '拦截 Rust HTTP 请求';

	/// zh-CN: '开启后 Rust 端所有 HTTP 请求都会直接失败，不会发送到网络'
	String get blockRustHttpRequestsSubtitle => '开启后 Rust 端所有 HTTP 请求都会直接失败，不会发送到网络';

	/// zh-CN: '显示布局溢出条纹'
	String get showLayoutOverflowStripes => '显示布局溢出条纹';

	/// zh-CN: '关闭后不画黄黑斜纹、也不上报溢出错误；只覆盖本项目的布局，Flutter 自带控件要 profile 构建才看不到条纹'
	String get showLayoutOverflowStripesSubtitle => '关闭后不画黄黑斜纹、也不上报溢出错误；只覆盖本项目的布局，Flutter 自带控件要 profile 构建才看不到条纹';

	/// zh-CN: '强制启用 Impeller'
	String get forceEnableImpeller => '强制启用 Impeller';

	/// zh-CN: 'Android 实验性渲染后端'
	String get forceEnableImpellerSubtitle => 'Android 实验性渲染后端';

	/// zh-CN: '整点颜色看看'
	String get colorPreview => '整点颜色看看';

	/// zh-CN: '打开调色页，快速预览主题色'
	String get colorPreviewSubtitle => '打开调色页，快速预览主题色';

	/// zh-CN: 'QJS 运行时调试'
	String get qjsRuntimeDebug => 'QJS 运行时调试';

	/// zh-CN: '手动输入运行时 ID，抓取调试快照'
	String get qjsRuntimeDebugSubtitle => '手动输入运行时 ID，抓取调试快照';

	/// zh-CN: '调试快照'
	String get qjsRuntimeSnapshot => '调试快照';

	/// zh-CN: '运行时 ID'
	String get qjsRuntimeIdLabel => '运行时 ID';

	/// zh-CN: '例如 0a0e5858-a467-4702-994a-79e608a4589d'
	String get qjsRuntimeIdHint => '例如 0a0e5858-a467-4702-994a-79e608a4589d';

	/// zh-CN: '抓取快照'
	String get qjsRuntimeCapture => '抓取快照';

	/// zh-CN: '抓取中'
	String get qjsRuntimeCapturing => '抓取中';

	/// zh-CN: '复制输出'
	String get qjsRuntimeCopyOutput => '复制输出';

	/// zh-CN: '暂无输出'
	String get qjsRuntimeNoOutput => '暂无输出';

	/// zh-CN: '请先输入运行时 ID'
	String get qjsRuntimeFillId => '请先输入运行时 ID';

	/// zh-CN: '已抓取 $dateTime'
	String qjsRuntimeCapturedAt({required Object dateTime}) => '已抓取 ${dateTime}';

	/// zh-CN: '抓取失败: $error'
	String qjsRuntimeCaptureFailed({required Object error}) => '抓取失败: ${error}';

	/// zh-CN: '当前没有可复制的内容'
	String get qjsRuntimeNoCopyContent => '当前没有可复制的内容';

	/// zh-CN: '已复制到剪贴板'
	String get qjsRuntimeCopied => '已复制到剪贴板';

	/// zh-CN: 'Variable Font 测试'
	String get colorPreviewVariableFont => 'Variable Font 测试';

	/// zh-CN: '已加载: $path'
	String colorPreviewFontLoaded({required Object path}) => '已加载: ${path}';

	/// zh-CN: '还没加载字体，先试推荐样本或者手动选一个 TTF/OTF 文件。'
	String get colorPreviewNoFont => '还没加载字体，先试推荐样本或者手动选一个 TTF/OTF 文件。';

	/// zh-CN: '加载推荐样本'
	String get colorPreviewLoadRecommended => '加载推荐样本';

	/// zh-CN: '选择字体文件'
	String get colorPreviewSelectFont => '选择字体文件';

	/// zh-CN: '按 fontWeight 渲染'
	String get colorPreviewByWeight => '按 fontWeight 渲染';

	/// zh-CN: '按 variable axis 渲染'
	String get colorPreviewByVariableAxis => '按 variable axis 渲染';

	/// zh-CN: '系统默认字体对照'
	String get colorPreviewSystemDefault => '系统默认字体对照';

	/// zh-CN: '正在加载字体...'
	String get colorPreviewLoadingFont => '正在加载字体...';

	/// zh-CN: '加载成功，可以直接对比不同字重。'
	String get colorPreviewLoadSuccess => '加载成功，可以直接对比不同字重。';

	/// zh-CN: '加载失败: $error'
	String colorPreviewLoadFailed({required Object error}) => '加载失败: ${error}';

	/// zh-CN: '红色'
	String get colorRed => '红色';

	/// zh-CN: '粉色'
	String get colorPink => '粉色';

	/// zh-CN: '紫色'
	String get colorPurple => '紫色';

	/// zh-CN: '深紫色'
	String get colorDeepPurple => '深紫色';

	/// zh-CN: '靛蓝色'
	String get colorIndigo => '靛蓝色';

	/// zh-CN: '蓝色'
	String get colorBlue => '蓝色';

	/// zh-CN: '浅蓝色'
	String get colorLightBlue => '浅蓝色';

	/// zh-CN: '青色'
	String get colorCyan => '青色';

	/// zh-CN: '水鸭色'
	String get colorTeal => '水鸭色';

	/// zh-CN: '绿色'
	String get colorGreen => '绿色';

	/// zh-CN: '浅绿色'
	String get colorLightGreen => '浅绿色';

	/// zh-CN: '酸橙色'
	String get colorLime => '酸橙色';

	/// zh-CN: '黄色'
	String get colorYellow => '黄色';

	/// zh-CN: '琥珀色'
	String get colorAmber => '琥珀色';

	/// zh-CN: '橙色'
	String get colorOrange => '橙色';

	/// zh-CN: '深橙色'
	String get colorDeepOrange => '深橙色';

	/// zh-CN: '棕色'
	String get colorBrown => '棕色';

	/// zh-CN: '灰色'
	String get colorGrey => '灰色';

	/// zh-CN: '蓝灰色'
	String get colorBlueGrey => '蓝灰色';

	/// zh-CN: '面具红'
	String get colorMaskRed => '面具红';

	/// zh-CN: '预设颜色'
	String get colorPresets => '预设颜色';

	/// zh-CN: 'CoreML 超分调试'
	String get coremlDebug => 'CoreML 超分调试';

	/// zh-CN: '使用绝对路径模型测试 CoreML 超分'
	String get coremlDebugSubtitle => '使用绝对路径模型测试 CoreML 超分';

	/// zh-CN: '关于与更多'
	String get aboutAndMore => '关于与更多';

	/// zh-CN: '更新日志'
	String get changelog => '更新日志';

	/// zh-CN: '查看各个版本的更新记录'
	String get changelogSubtitle => '查看各个版本的更新记录';

	/// zh-CN: '关于应用'
	String get aboutApp => '关于应用';

	/// zh-CN: '关于 Rossi 的详细信息'
	String get aboutAppSubtitle => '关于 Rossi 的详细信息';

	/// zh-CN: '插件管理'
	String get pluginManagement => '插件管理';

	/// zh-CN: '调试模式'
	String get debugMode => '调试模式';

	/// zh-CN: '调试地址'
	String get debugAddress => '调试地址';

	/// zh-CN: '未设置'
	String get notSet => '未设置';

	/// zh-CN: '文件管理器'
	String get fileManager => '文件管理器';

	/// zh-CN: '本地文件浏览的主页、工具栏与视图记忆'
	String get fileManagerSubtitle => '本地文件浏览的主页、工具栏与视图记忆';

	/// zh-CN: '主页'
	String get fileManagerSectionHome => '主页';

	/// zh-CN: '启用主页键'
	String get fileManagerHomeEnabled => '启用主页键';

	/// zh-CN: '关闭后文件管理器工具栏不再显示主页键'
	String get fileManagerHomeEnabledSubtitle => '关闭后文件管理器工具栏不再显示主页键';

	/// zh-CN: '主页目录'
	String get fileManagerHomePath => '主页目录';

	/// zh-CN: '主页键跳到哪个目录'
	String get fileManagerHomePathSubtitle => '主页键跳到哪个目录';

	/// zh-CN: '未设置'
	String get fileManagerHomePathEmpty => '未设置';

	/// zh-CN: '选择目录'
	String get fileManagerHomePathPick => '选择目录';

	/// zh-CN: '清除主页'
	String get fileManagerHomePathClear => '清除主页';

	/// zh-CN: '已清除主页'
	String get fileManagerHomePathCleared => '已清除主页';

	/// zh-CN: '该目录已不存在，请重新选择'
	String get fileManagerHomePathStale => '该目录已不存在，请重新选择';

	/// zh-CN: '当前平台不支持选择目录'
	String get fileManagerHomePathUnsupported => '当前平台不支持选择目录';

	/// zh-CN: '启动时默认打开主页'
	String get fileManagerOpenHomeOnStart => '启动时默认打开主页';

	/// zh-CN: '文件管理器打开时直接落在主页目录；该目录已不存在时回退到就近还在的目录'
	String get fileManagerOpenHomeOnStartSubtitle => '文件管理器打开时直接落在主页目录；该目录已不存在时回退到就近还在的目录';

	/// zh-CN: '工具栏'
	String get fileManagerSectionToolbar => '工具栏';

	/// zh-CN: '面包屑样式'
	String get breadcrumbStyle => '面包屑样式';

	/// zh-CN: '克制型'
	String get breadcrumbRestrained => '克制型';

	/// zh-CN: '规整圆角与轻量强调，适合日常浏览'
	String get breadcrumbRestrainedHint => '规整圆角与轻量强调，适合日常浏览';

	/// zh-CN: '强表现型'
	String get breadcrumbExpressive => '强表现型';

	/// zh-CN: '柔和起伏与异形端点，突出当前目录'
	String get breadcrumbExpressiveHint => '柔和起伏与异形端点，突出当前目录';

	/// zh-CN: '展开上级路径'
	String get breadcrumbAncestors => '展开上级路径';

	/// zh-CN: '浏览视图'
	String get fileManagerSectionView => '浏览视图';

	/// zh-CN: '记住每个目录的视图与排序'
	String get fileManagerRememberViewState => '记住每个目录的视图与排序';

	/// zh-CN: '每个目录各自记住视图、排序与筛选；关闭后浏览照常，只是不再记忆'
	String get fileManagerRememberViewStateSubtitle => '每个目录各自记住视图、排序与筛选；关闭后浏览照常，只是不再记忆';

	/// zh-CN: '封面网格完整显示文件名'
	String get fileManagerWrapGridTitle => '封面网格完整显示文件名';

	/// zh-CN: '封面网格里的文件名按词换行，最多铺 6 行；格子的总高度不变，行数多了就把封面挤小。关闭时截成 2 行加省略号。两种状态下，鼠标停在整格上都会浮出完整文件名'
	String get fileManagerWrapGridTitleSubtitle => '封面网格里的文件名按词换行，最多铺 6 行；格子的总高度不变，行数多了就把封面挤小。关闭时截成 2 行加省略号。两种状态下，鼠标停在整格上都会浮出完整文件名';

	/// zh-CN: '搜索'
	String get fileManagerSectionSearch => '搜索';

	/// zh-CN: '默认连子目录一起搜'
	String get fileManagerSearchSubfoldersDefault => '默认连子目录一起搜';

	/// zh-CN: '新建页签起手就开着「含子目录」。整库遍历在慢盘上实测要几十秒，所以默认只搜当前这一层；开着这条就不必每次去点那颗开关'
	String get fileManagerSearchSubfoldersDefaultSubtitle => '新建页签起手就开着「含子目录」。整库遍历在慢盘上实测要几十秒，所以默认只搜当前这一层；开着这条就不必每次去点那颗开关';

	/// zh-CN: '页签'
	String get fileManagerSectionTabs => '页签';

	/// zh-CN: '自动恢复上次打开的页签'
	String get fileManagerRestoreTabs => '自动恢复上次打开的页签';

	/// zh-CN: '文件管理器打开时把上次那批页签摆回来。两个以上页签才记，而且只记目录（后退历史与搜索结果不记）；目录已经没了就落在就近还在的父目录。上次开着两个以上页签时，这条比「启动时默认打开主页」优先'
	String get fileManagerRestoreTabsSubtitle => '文件管理器打开时把上次那批页签摆回来。两个以上页签才记，而且只记目录（后退历史与搜索结果不记）；目录已经没了就落在就近还在的父目录。上次开着两个以上页签时，这条比「启动时默认打开主页」优先';

	/// zh-CN: '文件操作'
	String get fileManagerSectionFileOps => '文件操作';

	/// zh-CN: '允许修改文件'
	String get fileManagerFileOperations => '允许修改文件';

	/// zh-CN: '复制、移动、重命名、新建与删除。关闭后右键菜单、多选与操作条都会消失，文件管理器回到只看不改'
	String get fileManagerFileOperationsSubtitle => '复制、移动、重命名、新建与删除。关闭后右键菜单、多选与操作条都会消失，文件管理器回到只看不改';

	/// zh-CN: '主页已更新'
	String get fileManagerHomePathSet => '主页已更新';

	/// zh-CN: '系统集成'
	String get shellIntegration => '系统集成';

	/// zh-CN: '在右键菜单显示「用 Rossi 打开」'
	String get shellIntegrationContextMenu => '在右键菜单显示「用 Rossi 打开」';

	/// zh-CN: '写当前用户的注册表（HKCU），不需要管理员权限；选中文件、选中文件夹、文件夹空白处三处都会出现。应用已经在运行时暂时不会把新目录递进来，要先开一个新 Rossi 窗口。'
	String get shellIntegrationContextMenuSubtitle => '写当前用户的注册表（HKCU），不需要管理员权限；选中文件、选中文件夹、文件夹空白处三处都会出现。应用已经在运行时暂时不会把新目录递进来，要先开一个新 Rossi 窗口。';

	/// zh-CN: '已加入右键菜单'
	String get shellIntegrationRegistered => '已加入右键菜单';

	/// zh-CN: '已从右键菜单移除'
	String get shellIntegrationUnregistered => '已从右键菜单移除';

	/// zh-CN: '菜单项指向的已经不是当前这个 Rossi，关掉再打开一次即可修正'
	String get shellIntegrationStalePath => '菜单项指向的已经不是当前这个 Rossi，关掉再打开一次即可修正';

	/// zh-CN: '修正指向'
	String get shellIntegrationRepair => '修正指向';

	/// zh-CN: 'macOS 的「打开方式 → Rossi」由应用包声明的文档类型决定，一直可用、没有开关；这颗开关只管 Windows。'
	String get shellIntegrationMacHint => 'macOS 的「打开方式 → Rossi」由应用包声明的文档类型决定，一直可用、没有开关；这颗开关只管 Windows。';

	/// zh-CN: '这个路径已经不在了：$path'
	String openIntentMissing({required Object path}) => '这个路径已经不在了：${path}';

	/// zh-CN: '一次只打开第一项，其余 $count 项已忽略'
	String openIntentMultiSkipped({required Object count}) => '一次只打开第一项，其余 ${count} 项已忽略';

	/// zh-CN: '操作绑定'
	String get operationBinding => '操作绑定';

	/// zh-CN: '按键、点击分区与绑定包'
	String get operationBindingEntrySubtitle => '按键、点击分区与绑定包';

	/// zh-CN: '按键与点击对应哪个动作，由这张表决定。保存即刻生效，不需要重启。'
	String get operationBindingSubtitle => '按键与点击对应哪个动作，由这张表决定。保存即刻生效，不需要重启。';

	/// zh-CN: '生效方式'
	String get operationBindingSectionSwitch => '生效方式';

	/// zh-CN: '用绑定表解析按键与点击'
	String get operationBindingRuntime => '用绑定表解析按键与点击';

	/// zh-CN: '关掉后回到内置的固定键位（方向键、WASD、小键盘与 F11），下面的编辑不影响阅读。'
	String get operationBindingRuntimeSubtitle => '关掉后回到内置的固定键位（方向键、WASD、小键盘与 F11），下面的编辑不影响阅读。';

	/// zh-CN: '滚轮按手推的方向翻页'
	String get operationBindingInvertWheel => '滚轮按手推的方向翻页';

	/// zh-CN: '开启后：向上滚=上一页、向下滚=下一页（按手的动作算）。macOS 的系统「自然滚动」已经把滚动增量翻过一次，所以 Mac 上默认开启；关掉则按内容移动的方向算。录制按键与关掉绑定表时的旧规则用同一套判定。'
	String get operationBindingInvertWheelSubtitle => '开启后：向上滚=上一页、向下滚=下一页（按手的动作算）。macOS 的系统「自然滚动」已经把滚动增量翻过一次，所以 Mac 上默认开启；关掉则按内容移动的方向算。录制按键与关掉绑定表时的旧规则用同一套判定。';

	/// zh-CN: '键盘'
	String get operationBindingSectionKeyboard => '键盘';

	/// zh-CN: '点击分区'
	String get operationBindingSectionTap => '点击分区';

	/// zh-CN: '阅读区只分「左半 / 正中 / 右半」三档：上下两排与中排同一动作。'
	String get operationBindingTapSubtitle => '阅读区只分「左半 / 正中 / 右半」三档：上下两排与中排同一动作。';

	/// zh-CN: '左半屏'
	String get operationBindingAreaMiddleLeft => '左半屏';

	/// zh-CN: '正中'
	String get operationBindingAreaMiddleCenter => '正中';

	/// zh-CN: '右半屏'
	String get operationBindingAreaMiddleRight => '右半屏';

	/// zh-CN: '未绑定'
	String get operationBindingUnbound => '未绑定';

	/// zh-CN: '绑定包'
	String get operationBindingSectionBundle => '绑定包';

	/// zh-CN: '导入 JSON'
	String get operationBindingImport => '导入 JSON';

	/// zh-CN: '导入绑定包，支持 bindings 对象或数组；保留全部输入类型、上下文和后续动作。'
	String get operationBindingImportSubtitle => '导入绑定包，支持 bindings 对象或数组；保留全部输入类型、上下文和后续动作。';

	/// zh-CN: '载入'
	String get operationBindingImportConfirm => '载入';

	/// zh-CN: '已载入 $count 条绑定，保存后生效'
	String operationBindingImportLoaded({required Object count}) => '已载入 ${count} 条绑定，保存后生效';

	/// zh-CN: '导出 JSON'
	String get operationBindingExport => '导出 JSON';

	/// zh-CN: '复制当前正在编辑的整张表。'
	String get operationBindingExportSubtitle => '复制当前正在编辑的整张表。';

	/// zh-CN: '复制'
	String get operationBindingCopy => '复制';

	/// zh-CN: '绑定表已复制到剪贴板'
	String get operationBindingCopied => '绑定表已复制到剪贴板';

	/// zh-CN: '保存前会先做校验与冲突检查；导入的内容只有按下保存才会写入。'
	String get operationBindingJsonHint => '保存前会先做校验与冲突检查；导入的内容只有按下保存才会写入。';

	/// zh-CN: '保存'
	String get operationBindingSave => '保存';

	/// zh-CN: '绑定表已保存，即刻生效'
	String get operationBindingSaved => '绑定表已保存，即刻生效';

	/// zh-CN: '放弃修改'
	String get operationBindingDiscard => '放弃修改';

	/// zh-CN: '已放弃未保存的修改'
	String get operationBindingDiscarded => '已放弃未保存的修改';

	/// zh-CN: '有未保存的修改。'
	String get operationBindingDirtyHint => '有未保存的修改。';

	/// zh-CN: '恢复出厂预设'
	String get operationBindingRestoreFactory => '恢复出厂预设';

	/// zh-CN: '恢复 Neo 默认的九宫格、滚轮、键盘和鼠标绑定，并重置轮盘。现有自定义绑定将被替换。'
	String get operationBindingRestoreFactorySubtitle => '恢复 Neo 默认的九宫格、滚轮、键盘和鼠标绑定，并重置轮盘。现有自定义绑定将被替换。';

	/// zh-CN: '添加按键'
	String get operationBindingAddKey => '添加按键';

	/// zh-CN: '未绑定按键'
	String get operationBindingNoKeys => '未绑定按键';

	/// zh-CN: '本仓还没有这个动作的执行体'
	String get operationBindingUnimplemented => '本仓还没有这个动作的执行体';

	/// zh-CN: '按下要绑定的键'
	String get operationBindingRecordTitle => '按下要绑定的键';

	/// zh-CN: '同时按住 Ctrl / Alt / Shift / Win 可以绑定组合键；按 Esc 取消。'
	String get operationBindingRecordHint => '同时按住 Ctrl / Alt / Shift / Win 可以绑定组合键；按 Esc 取消。';

	/// zh-CN: '「$label」没有平台无关的键名，无法绑定'
	String operationBindingRecordUnsupported({required Object label}) => '「${label}」没有平台无关的键名，无法绑定';

	/// zh-CN: '存在冲突的绑定'
	String get operationBindingConflictTitle => '存在冲突的绑定';

	/// zh-CN: '同一个输入只能有一条生效绑定。请删掉或停用其中一条，再保存。'
	String get operationBindingConflictBody => '同一个输入只能有一条生效绑定。请删掉或停用其中一条，再保存。';

	/// zh-CN: '这份绑定表读不懂，已拒绝保存'
	String get operationBindingInvalidTable => '这份绑定表读不懂，已拒绝保存';

	/// zh-CN: '导航'
	String get operationBindingCategoryNavigation => '导航';

	/// zh-CN: '缩放'
	String get operationBindingCategoryZoom => '缩放';

	/// zh-CN: '视图'
	String get operationBindingCategoryView => '视图';

	/// zh-CN: '会话'
	String get operationBindingCategorySession => '会话';

	/// zh-CN: '下一页'
	String get operationBindingActionNextPage => '下一页';

	/// zh-CN: '上一页'
	String get operationBindingActionPreviousPage => '上一页';

	/// zh-CN: '第一页'
	String get operationBindingActionFirstPage => '第一页';

	/// zh-CN: '最后一页'
	String get operationBindingActionLastPage => '最后一页';

	/// zh-CN: '向左翻页'
	String get operationBindingActionPageLeft => '向左翻页';

	/// zh-CN: '向右翻页'
	String get operationBindingActionPageRight => '向右翻页';

	/// zh-CN: '全屏'
	String get operationBindingActionFullscreen => '全屏';

	/// zh-CN: '阅读方向切换'
	String get operationBindingActionToggleDirection => '阅读方向切换';

	/// zh-CN: '书籍模式'
	String get operationBindingActionBookMode => '书籍模式';

	/// zh-CN: '重置视图'
	String get operationBindingActionResetView => '重置视图';

	/// zh-CN: '唤出/收起上下栏'
	String get operationBindingActionToggleBars => '唤出/收起上下栏';

	/// zh-CN: '打开设置'
	String get operationBindingActionOpenSettings => '打开设置';

	/// zh-CN: '放大'
	String get operationBindingActionZoomIn => '放大';

	/// zh-CN: '缩小'
	String get operationBindingActionZoomOut => '缩小';

	/// zh-CN: '适应窗口'
	String get operationBindingActionFitWindow => '适应窗口';

	/// zh-CN: '实际大小'
	String get operationBindingActionActualSize => '实际大小';

	/// zh-CN: '旋转'
	String get operationBindingActionRotateClockwise => '旋转';

	/// zh-CN: '旋转180度'
	String get operationBindingActionRotate180 => '旋转180度';

	/// zh-CN: '绑定的动作'
	String get operationBindingBoundAction => '绑定的动作';

	/// zh-CN: '已停用（不参与冲突判定）'
	String get operationBindingDisabledRow => '已停用（不参与冲突判定）';

	/// zh-CN: '删除这条绑定'
	String get operationBindingRemove => '删除这条绑定';

	/// zh-CN: '布局'
	String get workspaceLayout => '布局';

	/// zh-CN: '默认启动视图 · 泳道焦点与独占 · 悬停唤出区'
	String get workspaceLayoutSubtitle => '默认启动视图 · 泳道焦点与独占 · 悬停唤出区';

	/// zh-CN: '泳道与布局'
	String get laneAndLayout => '泳道与布局';

	/// zh-CN: '默认启动视图'
	String get defaultStartupView => '默认启动视图';

	/// zh-CN: '工作孔'
	String get startupViewEdges => '工作孔';

	/// zh-CN: '泳道'
	String get startupViewSwimlane => '泳道';

	/// zh-CN: '下次打开工作台时走哪条呈现。两种呈现共用同一份记账，切换不会重开当前这一本。'
	String get startupViewHint => '下次打开工作台时走哪条呈现。两种呈现共用同一份记账，切换不会重开当前这一本。';

	/// zh-CN: '泳道焦点与独占'
	String get laneFocusSolo => '泳道焦点与独占';

	/// zh-CN: '控制主泳道独占、切换栏和边缘调阅的响应时机。'
	String get laneFocusSoloSubtitle => '控制主泳道独占、切换栏和边缘调阅的响应时机。';

	/// zh-CN: '点阅读时跳到阅读器泳道'
	String get autoFocusReaderOnOpen => '点阅读时跳到阅读器泳道';

	/// zh-CN: '点「阅读」（详情页那颗、封面上那颗都算，是同一个动作）时把视口和交互交给中央阅读器泳道。关掉后书照样开进那条泳道，但条带一动不动 —— 你可以继续在原来那条泳道里翻，想读的时候自己点过去。'
	String get autoFocusReaderOnOpenSubtitle => '点「阅读」（详情页那颗、封面上那颗都算，是同一个动作）时把视口和交互交给中央阅读器泳道。关掉后书照样开进那条泳道，但条带一动不动 —— 你可以继续在原来那条泳道里翻，想读的时候自己点过去。';

	/// zh-CN: 'Reader 聚焦时自动独占'
	String get readerSoloOnFocus => 'Reader 聚焦时自动独占';

	/// zh-CN: '把交互交给 Reader 时顺带独占整条可用宽，不必再点一次栏头的独占按钮。'
	String get readerSoloOnFocusSubtitle => '把交互交给 Reader 时顺带独占整条可用宽，不必再点一次栏头的独占按钮。';

	/// zh-CN: 'Reader 独占时显示泳道切换栏'
	String get showLaneNavigatorInSolo => 'Reader 独占时显示泳道切换栏';

	/// zh-CN: '其余泳道收成紧凑轨留在条带里，点一条就把交互交给它；关掉则只剩 Reader，靠左右唤出区调回别的泳道。'
	String get showLaneNavigatorInSoloSubtitle => '其余泳道收成紧凑轨留在条带里，点一条就把交互交给它；关掉则只剩 Reader，靠左右唤出区调回别的泳道。';

	/// zh-CN: '允许手动横向滚动'
	String get manualScrollEnabled => '允许手动横向滚动';

	/// zh-CN: '关掉之后条带仍会按激活与揭示自己滚到该看的位置，只是不再响应自己伸手的拖动与滚轮。'
	String get manualScrollEnabledSubtitle => '关掉之后条带仍会按激活与揭示自己滚到该看的位置，只是不再响应自己伸手的拖动与滚轮。';

	/// zh-CN: '阅读器全屏时禁止横向拖动泳道'
	String get blockManualScrollInReaderFullscreen => '阅读器全屏时禁止横向拖动泳道';

	/// zh-CN: '全屏时横向手势只用于翻页，不再把整条泳道条带拽动（那会连阅读器一起拖动）。关掉后全屏与平时一样可拖。'
	String get blockManualScrollInReaderFullscreenSubtitle => '全屏时横向手势只用于翻页，不再把整条泳道条带拽动（那会连阅读器一起拖动）。关掉后全屏与平时一样可拖。';

	/// zh-CN: '泳道栏头'
	String get laneHeaderChrome => '泳道栏头';

	/// zh-CN: '栏头这一行画什么。只影响栏头本身，不动泳道里的内容。'
	String get laneHeaderChromeSubtitle => '栏头这一行画什么。只影响栏头本身，不动泳道里的内容。';

	/// zh-CN: '显示泳道宽度徽标'
	String get showLaneWidthBadge => '显示泳道宽度徽标';

	/// zh-CN: '在泳道标题右边画一颗当前宽度（如「400px」）。默认不画 —— 改宽度用栏头右键菜单里的「常规宽度」；不画时那一段宽度是还给标题与页签条的。'
	String get showLaneWidthBadgeSubtitle => '在泳道标题右边画一颗当前宽度（如「400px」）。默认不画 —— 改宽度用栏头右键菜单里的「常规宽度」；不画时那一段宽度是还给标题与页签条的。';

	/// zh-CN: '面板页签条排序模式'
	String get panelTabSortMode => '面板页签条排序模式';

	/// zh-CN: '开启后长按页签可拖动排序、拖到另一条泳道换位；关闭时按住页签横移就是切换面板（选中态随手指滑动）。'
	String get panelTabSortModeSubtitle => '开启后长按页签可拖动排序、拖到另一条泳道换位；关闭时按住页签横移就是切换面板（选中态随手指滑动）。';

	/// zh-CN: '左右泳道展开延迟'
	String get edgeRevealDelay => '左右泳道展开延迟';

	/// zh-CN: 'Reader 悬停重新聚焦延迟'
	String get readerHoverFocusDelay => 'Reader 悬停重新聚焦延迟';

	/// zh-CN: '启用 Reader 悬停重新聚焦'
	String get readerHoverFocusEnable => '启用 Reader 悬停重新聚焦';

	/// zh-CN: '呼出泳道后自动聚焦'
	String get revealFocusesLane => '呼出泳道后自动聚焦';

	/// zh-CN: '指针在视口左右边缘停够久，就把交互一并交给被揭示的泳道，不必再点一下；Reader 仍留一条窄缝，点它即可回到独占。关掉后揭示只是「看清楚」，离开一会儿自动收回 Reader。'
	String get revealFocusesLaneSubtitle => '指针在视口左右边缘停够久，就把交互一并交给被揭示的泳道，不必再点一下；Reader 仍留一条窄缝，点它即可回到独占。关掉后揭示只是「看清楚」，离开一会儿自动收回 Reader。';

	/// zh-CN: '面板泳道悬停聚焦'
	String get panelLaneHoverFocus => '面板泳道悬停聚焦';

	/// zh-CN: '指针停在左/右泳道里够久也把它激活，与 Reader 共用上面那段延迟。折叠成紧凑轨的泳道不参与，免得读数时扫过去就跳焦点。'
	String get panelLaneHoverFocusSubtitle => '指针停在左/右泳道里够久也把它激活，与 Reader 共用上面那段延迟。折叠成紧凑轨的泳道不参与，免得读数时扫过去就跳焦点。';

	/// zh-CN: '驻留多久才触发，单位毫秒。三套延时各自独立，改一个不会连带改坏另一个。'
	String get delayRangeHint => '驻留多久才触发，单位毫秒。三套延时各自独立，改一个不会连带改坏另一个。';

	/// zh-CN: '悬停唤出区'
	String get hoverRevealZones => '悬停唤出区';

	/// zh-CN: '在画布上拖出矩形，决定指针停在哪儿会把对应内容调出来。'
	String get hoverRevealZonesSubtitle => '在画布上拖出矩形，决定指针停在哪儿会把对应内容调出来。';

	/// zh-CN: '左右两条管泳道揭示，上管工作台顶栏，下管阅读器底栏。拖拽画框，选中后拖四角微调。'
	String get hoverRevealZonesHint => '左右两条管泳道揭示，上管工作台顶栏，下管阅读器底栏。拖拽画框，选中后拖四角微调。';

	/// zh-CN: '左侧'
	String get revealEdgeLeft => '左侧';

	/// zh-CN: '右侧'
	String get revealEdgeRight => '右侧';

	/// zh-CN: '上栏'
	String get revealEdgeTop => '上栏';

	/// zh-CN: '下栏'
	String get revealEdgeBottom => '下栏';

	/// zh-CN: '左右联动'
	String get revealLinkHorizontal => '左右联动';

	/// zh-CN: '上下联动'
	String get revealLinkVertical => '上下联动';

	/// zh-CN: '重置悬停唤出区'
	String get revealReset => '重置悬停唤出区';

	/// zh-CN: 'X'
	String get revealFieldX => 'X';

	/// zh-CN: 'Y'
	String get revealFieldY => 'Y';

	/// zh-CN: '宽'
	String get revealFieldWidth => '宽';

	/// zh-CN: '高'
	String get revealFieldHeight => '高';

	/// zh-CN: '已恢复出厂唤出区'
	String get revealZoneResetDone => '已恢复出厂唤出区';

	/// zh-CN: '快捷键'
	String get operationBindingTabKeyboard => '快捷键';

	/// zh-CN: '轮盘'
	String get operationBindingTabRadial => '轮盘';

	/// zh-CN: '唤出轮盘'
	String get operationBindingActionOpenRadial => '唤出轮盘';

	/// zh-CN: '确认轮盘选项'
	String get operationBindingActionConfirmRadial => '确认轮盘选项';

	/// zh-CN: '切换书库'
	String get operationBindingActionToggleLibrary => '切换书库';

	/// zh-CN: '启用轮盘'
	String get operationBindingRadialEnable => '启用轮盘';

	/// zh-CN: '关掉之后轮盘不再响应，槽位绑定原样保留'
	String get operationBindingRadialEnableSubtitle => '关掉之后轮盘不再响应，槽位绑定原样保留';

	/// zh-CN: '默认轮盘'
	String get operationBindingRadialActiveWheel => '默认轮盘';

	/// zh-CN: '$count 层'
	String operationBindingRadialLayerUnit({required Object count}) => '${count} 层';

	/// zh-CN: '新轮盘'
	String get operationBindingRadialNew => '新轮盘';

	/// zh-CN: '删除轮盘'
	String get operationBindingRadialDelete => '删除轮盘';

	/// zh-CN: '预览'
	String get operationBindingRadialPreview => '预览';

	/// zh-CN: '重置槽位'
	String get operationBindingRadialReset => '重置槽位';

	/// zh-CN: '只重写这个轮盘的出厂槽位，你自绑的其它输入不动'
	String get operationBindingRadialResetSubtitle => '只重写这个轮盘的出厂槽位，你自绑的其它输入不动';

	/// zh-CN: '已启用 · $layers 层 · 点空格添加，点已有槽编辑'
	String operationBindingRadialHint({required Object layers}) => '已启用 · ${layers} 层 · 点空格添加，点已有槽编辑';

	/// zh-CN: '已停用 · 阅读时不会唤出轮盘'
	String get operationBindingRadialHintDisabled => '已停用 · 阅读时不会唤出轮盘';

	/// zh-CN: '外观与几何'
	String get operationBindingRadialAppearance => '外观与几何';

	/// zh-CN: 'r$radius · 内$inner · $variant'
	String operationBindingRadialGeometrySummary({required Object radius, required Object inner, required Object variant}) => 'r${radius} · 内${inner} · ${variant}';

	/// zh-CN: '轮盘尺寸'
	String get operationBindingRadialRadius => '轮盘尺寸';

	/// zh-CN: '内半径（中心空洞）'
	String get operationBindingRadialInnerRadius => '内半径（中心空洞）';

	/// zh-CN: '每层格数'
	String get operationBindingRadialSectors => '每层格数';

	/// zh-CN: '槽位'
	String get operationBindingRadialSlots => '槽位';

	/// zh-CN: '点击轮盘空槽或已有槽'
	String get operationBindingRadialSlotsSubtitle => '点击轮盘空槽或已有槽';

	/// zh-CN: '轮盘名'
	String get operationBindingRadialName => '轮盘名';

	/// zh-CN: '第 $layer 层 · 第 $sector 格'
	String operationBindingRadialSlotLabel({required Object layer, required Object sector}) => '第 ${layer} 层 · 第 ${sector} 格';

	/// zh-CN: '空槽'
	String get operationBindingRadialEmptySlot => '空槽';

	/// zh-CN: '解绑这一格'
	String get operationBindingRadialUnbindSlot => '解绑这一格';

	/// zh-CN: '最多 $max 个轮盘'
	String operationBindingRadialMaxMenus({required Object max}) => '最多 ${max} 个轮盘';

	/// zh-CN: '删除轮盘「$name」？它的槽位绑定会一并移除。'
	String operationBindingRadialDeleteConfirm({required Object name}) => '删除轮盘「${name}」？它的槽位绑定会一并移除。';

	/// zh-CN: '至少要留一个轮盘'
	String get operationBindingRadialDeleteLast => '至少要留一个轮盘';

	/// zh-CN: '轮盘配置不合法，已拒绝保存'
	String get operationBindingRadialInvalid => '轮盘配置不合法，已拒绝保存';

	/// zh-CN: '已重置这个轮盘的出厂槽位'
	String get operationBindingRadialResetDone => '已重置这个轮盘的出厂槽位';

	/// zh-CN: '轮盘 $index'
	String operationBindingRadialNewName({required Object index}) => '轮盘 ${index}';

	/// zh-CN: '新轮盘是空的：槽位需要你一格一格绑'
	String get operationBindingRadialEmptyWheel => '新轮盘是空的：槽位需要你一格一格绑';

	/// zh-CN: '轮盘'
	String get operationBindingCategoryRadial => '轮盘';

	/// zh-CN: '类型'
	String get operationBindingRadialItemKind => '类型';

	/// zh-CN: '执行动作'
	String get operationBindingRadialKindAction => '执行动作';

	/// zh-CN: '跳转轮盘'
	String get operationBindingRadialKindMove => '跳转轮盘';

	/// zh-CN: '目标轮盘'
	String get operationBindingRadialTargetWheel => '目标轮盘';

	/// zh-CN: '图标'
	String get operationBindingRadialIcon => '图标';

	/// zh-CN: '按操作自动匹配'
	String get operationBindingRadialIconAuto => '按操作自动匹配';

	/// zh-CN: '显示文字'
	String get operationBindingRadialLabel => '显示文字';

	/// zh-CN: '槽位'
	String get operationBindingRadialSlotIndex => '槽位';

	/// zh-CN: '启用这一格'
	String get operationBindingRadialItemEnabled => '启用这一格';

	/// zh-CN: '前移'
	String get operationBindingRadialMoveUp => '前移';

	/// zh-CN: '后移'
	String get operationBindingRadialMoveDown => '后移';

	/// zh-CN: '删除这一格'
	String get operationBindingRadialDeleteItem => '删除这一格';

	/// zh-CN: '旋转角度'
	String get operationBindingRadialStartAngle => '旋转角度';

	/// zh-CN: '扫过角'
	String get operationBindingRadialSweepAngle => '扫过角';

	/// zh-CN: '样式'
	String get operationBindingRadialVariant => '样式';

	/// zh-CN: '圆角按钮'
	String get operationBindingRadialVariantSlice => '圆角按钮';

	/// zh-CN: '圆形按钮'
	String get operationBindingRadialVariantBubble => '圆形按钮';

	/// zh-CN: '第 $n 层'
	String operationBindingRadialLayerN({required Object n}) => '第 ${n} 层';

	/// zh-CN: '选中的槽位'
	String get operationBindingRadialSelectedSlot => '选中的槽位';

	/// zh-CN: '点轮盘上的一格来选它；空格会画成 +'
	String get operationBindingRadialPickHint => '点轮盘上的一格来选它；空格会画成 +';

	/// zh-CN: '（空格）'
	String get operationBindingRadialEmptySlotRow => '（空格）';

	/// zh-CN: '动作'
	String get operationBindingRadialActionLabel => '动作';

	/// zh-CN: '导出时一并打包已下载的漫画文件'
	String get includeDownloadedSubtitle => '导出时一并打包已下载的漫画文件';
}

// Path: bookshelf
class Translations$bookshelf$zh_CN {
	Translations$bookshelf$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '藏书'
	String get collectedWorks => '藏书';

	/// zh-CN: '正在阅读'
	String get readingNow => '正在阅读';

	/// zh-CN: '未读作品'
	String get unreadWorks => '未读作品';

	/// zh-CN: '把相关漫画放在一起，方便下次找到。'
	String get createFolderHint => '把相关漫画放在一起，方便下次找到。';

	/// zh-CN: '书架'
	String get title => '书架';

	/// zh-CN: '收藏'
	String get favorite => '收藏';

	/// zh-CN: '历史'
	String get history => '历史';

	/// zh-CN: '下载'
	String get download => '下载';

	/// zh-CN: '筛选'
	String get filter => '筛选';

	/// zh-CN: '搜索列表'
	String get searchList => '搜索列表';

	/// zh-CN: '新建文件夹'
	String get newFolder => '新建文件夹';

	/// zh-CN: '管理'
	String get manage => '管理';

	/// zh-CN: '导入漫画'
	String get importComic => '导入漫画';

	/// zh-CN: '书架说明'
	String get folderHint => '书架说明';

	/// zh-CN: '移出文件夹'
	String get removeFromFolder => '移出文件夹';

	/// zh-CN: '删除收藏'
	String get deleteFavorite => '删除收藏';

	/// zh-CN: '删除历史记录'
	String get deleteHistory => '删除历史记录';

	/// zh-CN: '删除下载记录'
	String get deleteDownload => '删除下载记录';

	/// zh-CN: '确定要删除选中的 $count 条记录吗？'
	String confirmDeleteSelected({required Object count}) => '确定要删除选中的 ${count} 条记录吗？';

	/// zh-CN: '已删除 $count 条记录'
	String deletedRecords({required Object count}) => '已删除 ${count} 条记录';

	/// zh-CN: '暂无可筛选的插件来源'
	String get noFilterSource => '暂无可筛选的插件来源';

	/// zh-CN: '排序'
	String get sort => '排序';

	/// zh-CN: '时间(晚→早)'
	String get sortDesc => '时间(晚→早)';

	/// zh-CN: '时间(早→晚)'
	String get sortAsc => '时间(早→晚)';

	/// zh-CN: '观看时间(晚→早)'
	String get viewSortDesc => '观看时间(晚→早)';

	/// zh-CN: '观看时间(早→晚)'
	String get viewSortAsc => '观看时间(早→晚)';

	/// zh-CN: '漫画源'
	String get source => '漫画源';

	/// zh-CN: '取消全选'
	String get deselectAll => '取消全选';

	/// zh-CN: '重命名收藏夹'
	String get renameFolder => '重命名收藏夹';

	/// zh-CN: '新建收藏夹'
	String get createFolder => '新建收藏夹';

	/// zh-CN: '多选'
	String get multiSelect => '多选';

	/// zh-CN: '复制到'
	String get copyTo => '复制到';

	/// zh-CN: '批量导出'
	String get batchExport => '批量导出';

	/// zh-CN: '批量删除失败'
	String get batchDeleteFailed => '批量删除失败';

	/// zh-CN: '删除选中'
	String get deleteSelected => '删除选中';

	/// zh-CN: '取消选择'
	String get cancel => '取消选择';

	/// zh-CN: '已选择 $count 项'
	String selectedCount({required Object count}) => '已选择 ${count} 项';

	/// zh-CN: '$count 本'
	String folderComicCount({required Object count}) => '${count} 本';

	/// zh-CN: '选择目标文件夹（可多选）'
	String get selectTargetFolder => '选择目标文件夹（可多选）';

	/// zh-CN: '确认删除'
	String get confirmDeleteFolderTitle => '确认删除';

	/// zh-CN: '确定要删除该文件夹吗？文件夹内的内容会被递归删除。'
	String get confirmDeleteFolderContent => '确定要删除该文件夹吗？文件夹内的内容会被递归删除。';

	/// zh-CN: '从文件夹移除'
	String get confirmRemoveComicTitle => '从文件夹移除';

	/// zh-CN: '确定要从当前文件夹移除《$title》吗？'
	String confirmRemoveComicContent({required Object title}) => '确定要从当前文件夹移除《${title}》吗？';

	/// zh-CN: '开始导入漫画（仅支持 zip）'
	String get importComicZipOnly => '开始导入漫画（仅支持 zip）';

	/// zh-CN: '开始导入漫画（仅支持 zip）'
	String get importStarted => '开始导入漫画（仅支持 zip）';

	/// zh-CN: '导入完成：$title'
	String importCompleted({required Object title}) => '导入完成：${title}';

	/// zh-CN: '漫画已存在'
	String get comicExists => '漫画已存在';

	/// zh-CN: '《$title》已经存在于下载列表中，是否覆盖导入？'
	String confirmOverwriteImport({required Object title}) => '《${title}》已经存在于下载列表中，是否覆盖导入？';

	/// zh-CN: '选中的项目中没有可导出的漫画'
	String get noExportableComics => '选中的项目中没有可导出的漫画';

	/// zh-CN: '批量导出完成：$success/$total'
	String batchExportCompleted({required Object success, required Object total}) => '批量导出完成：${success}/${total}';

	/// zh-CN: '已删除 $count 本的本地下载'
	String batchExportDeleted({required Object count}) => '已删除 ${count} 本的本地下载';

	/// zh-CN: '$count 本有页没能打包，已保留它们的本地下载'
	String batchExportKeptIncomplete({required Object count}) => '${count} 本有页没能打包，已保留它们的本地下载';

	/// zh-CN: '批量导出失败: $error'
	String batchExportFailed({required Object error}) => '批量导出失败: ${error}';

	/// zh-CN: '确认删除'
	String get confirmDeleteSelectedTitle => '确认删除';

	/// zh-CN: '确定要删除选中的文件夹和漫画吗？文件夹会递归删除。'
	String get confirmDeleteSelectedContent => '确定要删除选中的文件夹和漫画吗？文件夹会递归删除。';

	/// zh-CN: '取消选择'
	String get cancelSelect => '取消选择';

	/// zh-CN: '全选'
	String get selectAll => '全选';

	/// zh-CN: '移动到'
	String get moveTo => '移动到';

	/// zh-CN: '加入文件夹'
	String get addToFolder => '加入文件夹';

	/// zh-CN: '文件夹名称'
	String get folderName => '文件夹名称';

	/// zh-CN: '• 收藏和书架是联动的：收藏一本漫画，它会出现在书架里；只有把这本漫画从所有收藏文件夹里都删除，才会自动取消收藏。 • 在漫画详情页“取消收藏”，会一次性从所有收藏文件夹里移除这本漫画。 • 下载也是一样：只有把一本漫画从所有下载文件夹里都删除，才会自动删除它的下载文件。'
	String get helpContent => '• 收藏和书架是联动的：收藏一本漫画，它会出现在书架里；只有把这本漫画从所有收藏文件夹里都删除，才会自动取消收藏。\n• 在漫画详情页“取消收藏”，会一次性从所有收藏文件夹里移除这本漫画。\n• 下载也是一样：只有把一本漫画从所有下载文件夹里都删除，才会自动删除它的下载文件。';

	/// zh-CN: '文件夹创建成功'
	String get folderCreated => '文件夹创建成功';

	/// zh-CN: '还没有漫画'
	String get noComic => '还没有漫画';

	/// zh-CN: '还没有阅读记录'
	String get noHistory => '还没有阅读记录';

	/// zh-CN: '还没有下载记录'
	String get noDownload => '还没有下载记录';

	/// zh-CN: '啥都没有'
	String get nothingHere => '啥都没有';

	/// zh-CN: '删除所有下载记录及其文件'
	String get deleteAllDownloadRecordsAndFiles => '删除所有下载记录及其文件';

	/// zh-CN: '清空历史记录'
	String get clearHistoryRecords => '清空历史记录';

	/// zh-CN: '确定要删除所有下载记录及其文件吗？此操作不可恢复！'
	String get confirmDeleteAllDownloadsContent => '确定要删除所有下载记录及其文件吗？此操作不可恢复！';

	/// zh-CN: '确定要清空历史记录吗？此操作不可恢复！'
	String get confirmClearHistoryContent => '确定要清空历史记录吗？此操作不可恢复！';

	/// zh-CN: '所有下载记录及其文件已删除'
	String get allDownloadRecordsAndFilesDeleted => '所有下载记录及其文件已删除';

	/// zh-CN: '历史记录已清空'
	String get historyRecordsCleared => '历史记录已清空';

	/// zh-CN: '选择导出方式'
	String get batchExportTitle => '选择导出方式';

	/// zh-CN: '请选择批量导出为压缩包或文件夹'
	String get batchExportSubtitle => '请选择批量导出为压缩包或文件夹';

	/// zh-CN: '已取消导入'
	String get importCancelled => '已取消导入';

	/// zh-CN: '第$index集'
	String importEpisodeFallback({required Object index}) => '第${index}集';

	/// zh-CN: '导入目录缺少必要的 JSON 文件'
	String get importMissingJson => '导入目录缺少必要的 JSON 文件';

	/// zh-CN: '该版本无法导入，请使用较新的软件版本导出后导入'
	String get importVersionUnsupported => '该版本无法导入，请使用较新的软件版本导出后导入';

	/// zh-CN: '该导出文件缺少来源信息，请使用新版软件重新导出后再导入'
	String get importMissingSource => '该导出文件缺少来源信息，请使用新版软件重新导出后再导入';

	/// zh-CN: '无法获取漫画 ID'
	String get importMissingComicId => '无法获取漫画 ID';

	/// zh-CN: '未在压缩包中找到可导入的漫画目录'
	String get importNoComicDir => '未在压缩包中找到可导入的漫画目录';

	/// zh-CN: '压缩包中包含多个漫画目录，请每次只导入一本'
	String get importMultipleComicDirs => '压缩包中包含多个漫画目录，请每次只导入一本';

	/// zh-CN: '漫画《$title》已存在，未覆盖导入'
	String importComicExistsUncovered({required Object title}) => '漫画《${title}》已存在，未覆盖导入';

	/// zh-CN: '文件夹名称不能为空'
	String get folderNameEmpty => '文件夹名称不能为空';

	/// zh-CN: '文件夹名称不能包含 /'
	String get folderNameSlash => '文件夹名称不能包含 /';

	/// zh-CN: '当前路径下已存在同名文件夹'
	String get folderNameExists => '当前路径下已存在同名文件夹';

	/// zh-CN: '目标位置已存在同名文件夹：$name'
	String targetFolderNameExists({required Object name}) => '目标位置已存在同名文件夹：${name}';

	/// zh-CN: '不能将文件夹移动到自身'
	String get cannotMoveFolderToSelf => '不能将文件夹移动到自身';

	/// zh-CN: '不能将父文件夹移动到子文件夹中'
	String get cannotMoveParentToChild => '不能将父文件夹移动到子文件夹中';

	/// zh-CN: '不能复制文件夹到自身或其子路径下'
	String get cannotCopyFolderToSelfOrChild => '不能复制文件夹到自身或其子路径下';

	/// zh-CN: '移动文件夹时只能选择一个目标文件夹'
	String get moveFoldersOnlyOneTarget => '移动文件夹时只能选择一个目标文件夹';

	/// zh-CN: '确定要删除选中的 $count 条收藏记录吗？'
	String confirmDeleteSelectedFavorites({required Object count}) => '确定要删除选中的 ${count} 条收藏记录吗？';

	/// zh-CN: '确定要删除选中的 $count 条历史记录吗？'
	String confirmDeleteSelectedHistory({required Object count}) => '确定要删除选中的 ${count} 条历史记录吗？';

	/// zh-CN: '确定要删除选中的 $count 条下载记录及文件吗？'
	String confirmDeleteSelectedDownloads({required Object count}) => '确定要删除选中的 ${count} 条下载记录及文件吗？';
}

// Path: comicInfo
class Translations$comicInfo$zh_CN {
	Translations$comicInfo$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '章节 · $count'
	String chapterCount({required Object count}) => '章节 · ${count}';

	/// zh-CN: '页面已关闭，收藏操作已取消'
	String get pageClosedFavoriteCancelled => '页面已关闭，收藏操作已取消';

	/// zh-CN: '预览加载失败'
	String get previewLoadFailed => '预览加载失败';

	/// zh-CN: '显示更多章节'
	String get showMoreChapters => '显示更多章节';

	/// zh-CN: '暂无章节'
	String get noChaptersYet => '暂无章节';

	/// zh-CN: '倒序'
	String get reverseOrderLabel => '倒序';

	/// zh-CN: '恢复正序'
	String get restoreForwardOrder => '恢复正序';

	/// zh-CN: '画面预览'
	String get imagePreview => '画面预览';

	/// zh-CN: '收起详情'
	String get collapseDetails => '收起详情';

	/// zh-CN: '作品工具'
	String get workTools => '作品工具';

	/// zh-CN: '刷新信息'
	String get refreshInformation => '刷新信息';

	/// zh-CN: '云端收藏操作未完成'
	String get cloudFavoriteIncomplete => '云端收藏操作未完成';

	/// zh-CN: '加入追更'
	String get follow => '加入追更';

	/// zh-CN: '不再追更'
	String get unfollow => '不再追更';

	/// zh-CN: '导出漫画'
	String get exportComic => '导出漫画';

	/// zh-CN: '云收藏'
	String get cloudCollect => '云收藏';

	/// zh-CN: '已云收藏'
	String get cloudCollected => '已云收藏';

	/// zh-CN: '该插件暂不支持此功能'
	String get cloudCollectDisabled => '该插件暂不支持此功能';

	/// zh-CN: '收藏到云端中...'
	String get collectingToCloud => '收藏到云端中...';

	/// zh-CN: '取消云收藏中...'
	String get removingCloudCollection => '取消云收藏中...';

	/// zh-CN: '云收藏成功'
	String get cloudCollectSuccess => '云收藏成功';

	/// zh-CN: '已取消云收藏'
	String get cloudUncollectSuccess => '已取消云收藏';

	/// zh-CN: '云收藏操作未完成'
	String get cloudCollectIncomplete => '云收藏操作未完成';

	/// zh-CN: '此漫画已下架'
	String get discontinued => '此漫画已下架';

	/// zh-CN: '点赞 $count'
	String likes({required Object count}) => '点赞 ${count}';

	/// zh-CN: '评论 $count'
	String comments({required Object count}) => '评论 ${count}';

	/// zh-CN: '已收藏'
	String get collected => '已收藏';

	/// zh-CN: '收藏'
	String get collect => '收藏';

	/// zh-CN: '下载'
	String get download => '下载';

	/// zh-CN: '标记已读'
	String get markRead => '标记已读';

	/// zh-CN: '标记未读'
	String get markUnread => '标记未读';

	/// zh-CN: '标记至此为已读'
	String get markThroughRead => '标记至此为已读';

	/// zh-CN: '清除标记'
	String get clearReadMark => '清除标记';

	/// zh-CN: '阅读状态'
	String get readStateMenu => '阅读状态';

	/// zh-CN: '标记只记录你的人为判决，不改动阅读进度，也不影响「继续阅读」的定位。'
	String get readStateMenuHint => '标记只记录你的人为判决，不改动阅读进度，也不影响「继续阅读」的定位。';

	/// zh-CN: '已标记 $count 话为已读'
	String markReadDone({required Object count}) => '已标记 ${count} 话为已读';

	/// zh-CN: '已标记 $count 话为未读'
	String markUnreadDone({required Object count}) => '已标记 ${count} 话为未读';

	/// zh-CN: '已把此前 $count 话标记为已读'
	String markThroughReadDone({required Object count}) => '已把此前 ${count} 话标记为已读';

	/// zh-CN: '未读'
	String get readStateUnread => '未读';

	/// zh-CN: '读到过'
	String get readStateInferred => '读到过';

	/// zh-CN: '已标记已读'
	String get readStateManualRead => '已标记已读';

	/// zh-CN: '已标记未读'
	String get readStateManualUnread => '已标记未读';

	/// zh-CN: '该插件暂不支持此功能'
	String get downloadForbidden => '该插件暂不支持此功能';

	/// zh-CN: '已添加收藏'
	String get addedToCollection => '已添加收藏';

	/// zh-CN: '已取消收藏'
	String get removedFromCollection => '已取消收藏';

	/// zh-CN: '确认取消收藏'
	String get confirmUncollectTitle => '确认取消收藏';

	/// zh-CN: '此项操作会删除该漫画在所有文件夹的记录，是否确认删除？'
	String get confirmUncollectContent => '此项操作会删除该漫画在所有文件夹的记录，是否确认删除？';

	/// zh-CN: '该插件暂不支持此功能'
	String get commentForbidden => '该插件暂不支持此功能';

	/// zh-CN: '禁止评论'
	String get commentForbiddenTitle => '禁止评论';

	/// zh-CN: '返回'
	String get back => '返回';

	/// zh-CN: '选择导出方式'
	String get exportTitle => '选择导出方式';

	/// zh-CN: '请选择将漫画导出为压缩包还是文件夹：'
	String get exportSubtitle => '请选择将漫画导出为压缩包还是文件夹：';

	/// zh-CN: '文件夹'
	String get folder => '文件夹';

	/// zh-CN: '压缩包'
	String get zip => '压缩包';

	/// zh-CN: '导出成功'
	String get exportSuccess => '导出成功';

	/// zh-CN: '当前详情尚未加载完成'
	String get detailsNotLoaded => '当前详情尚未加载完成';

	/// zh-CN: '已加入追更'
	String get followed => '已加入追更';

	/// zh-CN: '已取消追更'
	String get unfollowed => '已取消追更';

	/// zh-CN: '取消追更'
	String get confirmUnfollowTitle => '取消追更';

	/// zh-CN: '确定不再追更《$title》吗？'
	String confirmUnfollowContent({required Object title}) => '确定不再追更《${title}》吗？';

	/// zh-CN: '暂无章节信息'
	String get noChapters => '暂无章节信息';

	/// zh-CN: '章节目录'
	String get chapterList => '章节目录';

	/// zh-CN: '预览'
	String get preview => '预览';

	/// zh-CN: '$count 话'
	String episodeCount({required Object count}) => '${count} 话';

	/// zh-CN: '$index'
	String episodeFallback({required Object index}) => '${index}';

	/// zh-CN: '$index'
	String episodeLabel({required Object index}) => '${index}';

	/// zh-CN: '$count 话'
	String groupEpisodeCount({required Object count}) => '${count} 话';

	/// zh-CN: '未分组'
	String get untitledGroup => '未分组';

	/// zh-CN: '下载本组'
	String get downloadGroup => '下载本组';

	/// zh-CN: '作者'
	String get author => '作者';

	/// zh-CN: '标签'
	String get tags => '标签';

	/// zh-CN: '作品'
	String get works => '作品';

	/// zh-CN: '浏览：$count'
	String views({required Object count}) => '浏览：${count}';

	/// zh-CN: '更新时间：$time'
	String updateTime({required Object time}) => '更新时间：${time}';

	/// zh-CN: '开始阅读'
	String get startRead => '开始阅读';

	/// zh-CN: '继续阅读'
	String get continueRead => '继续阅读';

	/// zh-CN: '上次读到'
	String get lastRead => '上次读到';

	/// zh-CN: '章节'
	String get chapters => '章节';

	/// zh-CN: '相关推荐'
	String get related => '相关推荐';

	/// zh-CN: '简介'
	String get description => '简介';

	/// zh-CN: '收起'
	String get collapse => '收起';

	/// zh-CN: '展开全文'
	String get expandFullText => '展开全文';

	/// zh-CN: '阅读记录'
	String get readHistory => '阅读记录';

	/// zh-CN: '已复制：$label'
	String copied({required Object label}) => '已复制：${label}';

	/// zh-CN: '已将 $name 复制到剪贴板'
	String copiedToClipboard({required Object name}) => '已将 ${name} 复制到剪贴板';

	/// zh-CN: '在原站打开'
	String get openOnSource => '在原站打开';

	/// zh-CN: '点赞中...'
	String get liking => '点赞中...';

	/// zh-CN: '取消点赞中...'
	String get unliking => '取消点赞中...';

	/// zh-CN: '点赞成功'
	String get likeSuccess => '点赞成功';

	/// zh-CN: '已取消点赞'
	String get unlikeSuccess => '已取消点赞';

	/// zh-CN: '该插件暂不支持此功能'
	String get likeDisabled => '该插件暂不支持此功能';

	/// zh-CN: '本地收藏失败: $error'
	String localCollectFailed({required Object error}) => '本地收藏失败: ${error}';

	/// zh-CN: '点赞失败: $error'
	String likeFailed({required Object error}) => '点赞失败: ${error}';

	/// zh-CN: '$error 加载失败，请重试。'
	String loadFailedWithError({required Object error}) => '${error}\n加载失败，请重试。';

	/// zh-CN: '未授予所有文件访问权限，导出已取消'
	String get exportPermissionDenied => '未授予所有文件访问权限，导出已取消';

	/// zh-CN: '导出失败，请重试。 $error'
	String exportFailedWithError({required Object error}) => '导出失败，请重试。\n${error}';

	/// zh-CN: '导出目录：$displayPath'
	String exportDirectory({required Object displayPath}) => '导出目录：${displayPath}';

	/// zh-CN: '导出目录路径过长，无法创建有效的导出结构'
	String get exportPathTooLong => '导出目录路径过长，无法创建有效的导出结构';

	/// zh-CN: '指定的 zip 导出路径超出系统路径长度限制'
	String get zipExportPathTooLong => '指定的 zip 导出路径超出系统路径长度限制';

	/// zh-CN: '下载目录路径过长，无法创建有效的 zip 文件路径'
	String get downloadPathTooLong => '下载目录路径过长，无法创建有效的 zip 文件路径';

	/// zh-CN: '无法为章节创建不重复的文件名：超出路径长度限制'
	String get uniqueFileNameTooLong => '无法为章节创建不重复的文件名：超出路径长度限制';

	/// zh-CN: '漫画$title导出为文件夹完成'
	String exportFolderComplete({required Object title}) => '漫画${title}导出为文件夹完成';

	/// zh-CN: '漫画$title导出为 zip 完成'
	String exportZipComplete({required Object title}) => '漫画${title}导出为 zip 完成';

	/// zh-CN: '未找到可导出的下载漫画: $comicId'
	String exportComicNotFound({required Object comicId}) => '未找到可导出的下载漫画: ${comicId}';

	/// zh-CN: '导出成功后删除本地下载'
	String get exportDeleteAfter => '导出成功后删除本地下载';

	/// zh-CN: '只有全部页面都进了归档、文件确实写完，才会删除。任一条件不满足就保留本地下载，并说明原因。'
	String get exportDeleteAfterSubtitle => '只有全部页面都进了归档、文件确实写完，才会删除。任一条件不满足就保留本地下载，并说明原因。';

	/// zh-CN: '已导出并删除本地下载：$title'
	String exportedAndDeleted({required Object title}) => '已导出并删除本地下载：${title}';

	/// zh-CN: '有 $count 页没能打包进导出文件（$chapters），已保留本地下载'
	String exportDeleteSkippedIncomplete({required Object count, required Object chapters}) => '有 ${count} 页没能打包进导出文件（${chapters}），已保留本地下载';

	/// zh-CN: '本地没有任何可导出的页面，已保留本地下载'
	String get exportDeleteSkippedEmpty => '本地没有任何可导出的页面，已保留本地下载';

	/// zh-CN: '导出文件没通过完整性校验，已保留本地下载'
	String get exportDeleteSkippedArtifact => '导出文件没通过完整性校验，已保留本地下载';

	/// zh-CN: '导出位置就在下载目录里面，删下去会连导出一起删掉，已保留本地下载'
	String get exportDeleteSkippedInsideRoot => '导出位置就在下载目录里面，删下去会连导出一起删掉，已保留本地下载';

	/// zh-CN: '导出完成，但删除本地下载失败：$error'
	String exportDeleteFailed({required Object error}) => '导出完成，但删除本地下载失败：${error}';

	/// zh-CN: '插件未返回有效 favorited 状态'
	String get pluginInvalidFavorited => '插件未返回有效 favorited 状态';

	/// zh-CN: '插件未返回有效 liked 状态'
	String get pluginInvalidLiked => '插件未返回有效 liked 状态';

	/// zh-CN: '添加到自定义收藏夹'
	String get addToCustomFolder => '添加到自定义收藏夹';

	/// zh-CN: '已添加到收藏夹: $name'
	String addedToFolder({required Object name}) => '已添加到收藏夹: ${name}';

	/// zh-CN: '跳过/不添加'
	String get skipAdd => '跳过/不添加';

	/// zh-CN: '确定添加'
	String get confirmAdd => '确定添加';

	/// zh-CN: '无法解析阅读 comicId: $type'
	String resolveComicIdFailed({required Object type}) => '无法解析阅读 comicId: ${type}';

	/// zh-CN: '无法解析阅读章节数: $type'
	String resolveEpsCountFailed({required Object type}) => '无法解析阅读章节数: ${type}';

	/// zh-CN: '收藏到云端'
	String get collectToCloud => '收藏到云端';

	/// zh-CN: '收藏到本地'
	String get collectToLocal => '收藏到本地';

	/// zh-CN: '取消云端收藏'
	String get removeCloudCollection => '取消云端收藏';

	/// zh-CN: '取消本地收藏'
	String get removeLocalCollection => '取消本地收藏';
}

// Path: reader
class Translations$reader$zh_CN {
	Translations$reader$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '切换书籍失败：$error'
	String switchBookFailed({required Object error}) => '切换书籍失败：${error}';

	/// zh-CN: '第 $n 页没能解出来'
	String pageDecodeFailed({required Object n}) => '第 ${n} 页没能解出来';

	/// zh-CN: '打不开：$path'
	String cannotOpenPath({required Object path}) => '打不开：${path}';

	/// zh-CN: 'AI JPEG 降噪'
	String get aiJpegDenoise => 'AI JPEG 降噪';

	/// zh-CN: '没有匹配的已离线漫画'
	String get noMatchingOfflineComics => '没有匹配的已离线漫画';

	/// zh-CN: '搜索已离线漫画'
	String get searchOfflineComics => '搜索已离线漫画';

	/// zh-CN: '未下载（开启时会先问一句）'
	String get stateNotDownloadedAsk => '未下载（开启时会先问一句）';

	/// zh-CN: '已下载'
	String get stateDownloaded => '已下载';

	/// zh-CN: '未开启'
	String get stateOff => '未开启';

	/// zh-CN: '已开启'
	String get stateOn => '已开启';

	/// zh-CN: '无法打开本地漫画: $error'
	String cannotOpenLocalComic({required Object error}) => '无法打开本地漫画: ${error}';

	/// zh-CN: '已缓存 $count 页'
	String cachedPages({required Object count}) => '已缓存 ${count} 页';

	/// zh-CN: '目标 $lang'
	String targetLanguageLabel({required Object lang}) => '目标 ${lang}';

	/// zh-CN: '底部唤出 (${px}px)'
	String bottomRevealPx({required Object px}) => '底部唤出 (${px}px)';

	/// zh-CN: '顶部唤出 (${px}px)'
	String topRevealPx({required Object px}) => '顶部唤出 (${px}px)';

	/// zh-CN: '源第 $index / $total 页'
	String sourcePageOf({required Object index, required Object total}) => '源第 ${index} / ${total} 页';

	/// zh-CN: '手动页序 · $name'
	String manualPageOrderFor({required Object name}) => '手动页序 · ${name}';

	/// zh-CN: '$from（点击切为$to）'
	String tapToSwitchMode({required Object from, required Object to}) => '${from}（点击切为${to}）';

	/// zh-CN: '模型：$state'
	String modelState({required Object state}) => '模型：${state}';

	/// zh-CN: '下载模型失败: $error'
	String modelDownloadFailed({required Object error}) => '下载模型失败: ${error}';

	/// zh-CN: '生效阈值：$value'
	String activeThreshold({required Object value}) => '生效阈值：${value}';

	/// zh-CN: '全局（所有书默认）：$state'
	String globalDefaultState({required Object state}) => '全局（所有书默认）：${state}';

	/// zh-CN: '本书：$state'
	String thisBookState({required Object state}) => '本书：${state}';

	/// zh-CN: '$tooltip 点击切换；按住暂看原图；右侧电源只影响本书'
	String upscaleChipTail({required Object tooltip}) => '${tooltip}\n点击切换；按住暂看原图；右侧电源只影响本书';

	/// zh-CN: '$name 还没接进本仓的阅读器'
	String notWiredIntoReader({required Object name}) => '${name} 还没接进本仓的阅读器';

	/// zh-CN: '$name（本仓尚未实现）'
	String notImplementedYet({required Object name}) => '${name}（本仓尚未实现）';

	/// zh-CN: '一屏 $percent%'
	String oneScreenPercent({required Object percent}) => '一屏 ${percent}%';

	/// zh-CN: '每一页停多久：一步 $step，$min~$max 之间'
	String slideshowDwellHint({required Object step, required Object min, required Object max}) => '每一页停多久：一步 ${step}，${min}~${max} 之间';

	/// zh-CN: '手动旋转 $deg°'
	String manualRotationDeg({required Object deg}) => '手动旋转 ${deg}°';

	/// zh-CN: '窗口边长，逻辑像素（$min~$max，一次 20）'
	String loupeSizeRange({required Object min, required Object max}) => '窗口边长，逻辑像素（${min}~${max}，一次 20）';

	/// zh-CN: '放大倍率（$min%~$max%，一档 25%，400% 起一档翻倍）'
	String loupeZoomRange({required Object min, required Object max}) => '放大倍率（${min}%~${max}%，一档 25%，400% 起一档翻倍）';

	/// zh-CN: '间隔 ${seconds}s'
	String intervalSeconds({required Object seconds}) => '间隔 ${seconds}s';

	/// zh-CN: '$label（点击展开面板）'
	String tapToExpandPanel({required Object label}) => '${label}（点击展开面板）';

	/// zh-CN: '缩放模式：$mode'
	String zoomModeValue({required Object mode}) => '缩放模式：${mode}';

	/// zh-CN: '图像处理已关闭，可在阅读设置中打开开关'
	String get imageProcessingOffReaderHint => '图像处理已关闭，可在阅读设置中打开开关';

	/// zh-CN: '当前平台不支持 GPU 纹理处理'
	String get gpuTextureUnsupported => '当前平台不支持 GPU 纹理处理';

	/// zh-CN: '当前页'
	String get thisPage => '当前页';

	/// zh-CN: '待超分'
	String get pendingUpscale => '待超分';

	/// zh-CN: '超分失败'
	String get upscaleFailedState => '超分失败';

	/// zh-CN: '无需超分'
	String get noUpscaleNeeded => '无需超分';

	/// zh-CN: '已超分'
	String get upscaledState => '已超分';

	/// zh-CN: '已生成'
	String get generatedState => '已生成';

	/// zh-CN: '超分中'
	String get upscalingState => '超分中';

	/// zh-CN: '排队中'
	String get queuedState => '排队中';

	/// zh-CN: '原图对比'
	String get originalCompareChip => '原图对比';

	/// zh-CN: '超分关'
	String get upscaleOff => '超分关';

	/// zh-CN: '不支持'
	String get notSupported => '不支持';

	/// zh-CN: '无需处理'
	String get noProcessingNeeded => '无需处理';

	/// zh-CN: '降噪失败'
	String get denoiseFailed => '降噪失败';

	/// zh-CN: '增强失败'
	String get enhanceFailed => '增强失败';

	/// zh-CN: '待降噪'
	String get pendingDenoise => '待降噪';

	/// zh-CN: '待增强'
	String get pendingEnhance => '待增强';

	/// zh-CN: '已降噪'
	String get denoisedDone => '已降噪';

	/// zh-CN: '已增强'
	String get enhancedDone => '已增强';

	/// zh-CN: '降噪中'
	String get denoising => '降噪中';

	/// zh-CN: '增强中'
	String get enhancing => '增强中';

	/// zh-CN: '超分'
	String get upscaleShort => '超分';

	/// zh-CN: 'JPEG 降噪'
	String get jpegDenoise => 'JPEG 降噪';

	/// zh-CN: '降噪+超分'
	String get denoisePlusUpscale => '降噪+超分';

	/// zh-CN: '$page 还没开始$process$hint'
	String tooltipIdle({required Object page, required Object process, required Object hint}) => '${page} 还没开始${process}${hint}';

	/// zh-CN: '$page $process 失败，继续显示原图$hint'
	String tooltipFailed({required Object page, required Object process, required Object hint}) => '${page} ${process} 失败，继续显示原图${hint}';

	/// zh-CN: '$page 无需处理$hint'
	String tooltipSkipped({required Object page, required Object hint}) => '${page} 无需处理${hint}';

	/// zh-CN: '$page 已使用$process图片$hint，点这里对比原图'
	String tooltipApplied({required Object page, required Object process, required Object hint}) => '${page} 已使用${process}图片${hint}，点这里对比原图';

	/// zh-CN: '$page 处理后图片已生成，等待上屏$hint'
	String tooltipReady({required Object page, required Object hint}) => '${page} 处理后图片已生成，等待上屏${hint}';

	/// zh-CN: '$page $process 中…$hint'
	String tooltipRunning({required Object page, required Object process, required Object hint}) => '${page} ${process} 中…${hint}';

	/// zh-CN: '$page 已排队，等待$process$hint'
	String tooltipQueued({required Object page, required Object process, required Object hint}) => '${page} 已排队，等待${process}${hint}';

	/// zh-CN: '正在对比原图，点这里切回处理后画面$hint'
	String tooltipComparing({required Object hint}) => '正在对比原图，点这里切回处理后画面${hint}';

	/// zh-CN: '（原图 $source）'
	String sizeHintSource({required Object source}) => '（原图 ${source}）';

	/// zh-CN: '（处理后 $enhanced）'
	String sizeHintEnhanced({required Object enhanced}) => '（处理后 ${enhanced}）';

	/// zh-CN: '（原图 $source → 处理后 $enhanced）'
	String sizeHintBoth({required Object source, required Object enhanced}) => '（原图 ${source} → 处理后 ${enhanced}）';

	/// zh-CN: '第 $page 页'
	String pageNumberN({required Object page}) => '第 ${page} 页';

	/// zh-CN: '缺 $count 项权重'
	String missingWeightsCount({required Object count}) => '缺 ${count} 项权重';

	/// zh-CN: '（没有缺失项，直接过）'
	String get noMissingWeights => '（没有缺失项，直接过）';

	/// zh-CN: '适应窗口'
	String get fitWindow => '适应窗口';

	/// zh-CN: '默认启用自动裁边'
	String get autoTrimEnabledByDefault => '默认启用自动裁边';

	/// zh-CN: '高度对齐（双页高度统一）'
	String get alignHeight => '高度对齐（双页高度统一）';

	/// zh-CN: '驻留指示已关闭：放映到哪一页只能靠猜'
	String get dwellIndicatorOff => '驻留指示已关闭：放映到哪一页只能靠猜';

	/// zh-CN: '首页独立显示：开'
	String get firstPageAloneOn => '首页独立显示：开';

	/// zh-CN: '首页独立显示：关'
	String get firstPageAloneOff => '首页独立显示：关';

	/// zh-CN: '顺时针旋转 90°'
	String get rotateClockwise90 => '顺时针旋转 90°';

	/// zh-CN: '页面排序'
	String get pageSorting => '页面排序';

	/// zh-CN: '页面布局'
	String get pageLayout => '页面布局';

	/// zh-CN: '页序'
	String get pageOrder => '页序';

	/// zh-CN: '限制每一侧最多裁掉的比例；0% 等同于保留完整页面'
	String get trimSideLimitHint => '限制每一侧最多裁掉的比例；0% 等同于保留完整页面';

	/// zh-CN: '降噪高级设置'
	String get denoiseAdvancedSettings => '降噪高级设置';

	/// zh-CN: '降噪分块大小'
	String get denoiseBlockSize => '降噪分块大小';

	/// zh-CN: '降噪'
	String get denoiseShort => '降噪';

	/// zh-CN: '阈值'
	String get thresholdLabel => '阈值';

	/// zh-CN: '阅读器设置里开始下载权重：'
	String get startWeightsInReaderSettings => '阅读器设置里开始下载权重：';

	/// zh-CN: '阅读器两侧是否保留适度安全边距'
	String get readerSafeMarginBothSides => '阅读器两侧是否保留适度安全边距';

	/// zh-CN: '间隔'
	String get intervalLabel => '间隔';

	/// zh-CN: '锁止'
	String get lockLoupe => '锁止';

	/// zh-CN: '铺满整个窗口'
	String get fillWholeWindow => '铺满整个窗口';

	/// zh-CN: '重置缩放、旋转与宽页策略（保留单双页与阅读方向）'
	String get resetViewTransform => '重置缩放、旋转与宽页策略（保留单双页与阅读方向）';

	/// zh-CN: '逆时针旋转 90°'
	String get rotateCounterclockwise90 => '逆时针旋转 90°';

	/// zh-CN: '适应高度'
	String get fitHeight => '适应高度';

	/// zh-CN: '适应宽度'
	String get fitWidth => '适应宽度';

	/// zh-CN: '这一页还没加载出来，稍等一下再译'
	String get pageNotLoadedYet => '这一页还没加载出来，稍等一下再译';

	/// zh-CN: '读取设置…'
	String get loadingSettings => '读取设置…';

	/// zh-CN: '译文已经生成并注入，正被「对比原图」挡着：切回超分就显示译文'
	String get translationHiddenByCompare => '译文已经生成并注入，正被「对比原图」挡着：切回超分就显示译文';

	/// zh-CN: '触发'
	String get trigger => '触发';

	/// zh-CN: '裁边高级设置'
	String get trimAdvancedSettings => '裁边高级设置';

	/// zh-CN: '自动：按指针自己的类型选 —— 鼠标/触控板跟随悬停，手指与触屏笔按住才出窗口（不看平台，触屏笔记本与外接鼠标都判得对）'
	String get pointerTypeAuto => '自动：按指针自己的类型选 —— 鼠标/触控板跟随悬停，手指与触屏笔按住才出窗口（不看平台，触屏笔记本与外接鼠标都判得对）';

	/// zh-CN: '自动译'
	String get autoTranslateShort => '自动译';

	/// zh-CN: '自动旋转'
	String get autoRotate => '自动旋转';

	/// zh-CN: '自动分割横向页：开'
	String get autoSplitLandscapeOn => '自动分割横向页：开';

	/// zh-CN: '自动分割横向页：关'
	String get autoSplitLandscapeOff => '自动分割横向页：关';

	/// zh-CN: '背景检测容差'
	String get backgroundTolerance => '背景检测容差';

	/// zh-CN: '翻页自动翻译已开启'
	String get autoTranslateEnabled => '翻页自动翻译已开启';

	/// zh-CN: '缩放模式'
	String get zoomMode => '缩放模式';

	/// zh-CN: '编辑本章的手动顺序'
	String get editManualOrder => '编辑本章的手动顺序';

	/// zh-CN: '纵向页左旋'
	String get rotatePortraitLeft => '纵向页左旋';

	/// zh-CN: '纵向页右旋'
	String get rotatePortraitRight => '纵向页右旋';

	/// zh-CN: '章'
	String get chapterShort => '章';

	/// zh-CN: '立即下载'
	String get downloadNow => '立即下载';

	/// zh-CN: '确认要重置进度并重新下载本漫画吗？'
	String get confirmResetAndRedownload => '确认要重置进度并重新下载本漫画吗？';

	/// zh-CN: '短按重置为 100%；按住可输入百分比'
	String get zoomShortReset => '短按重置为 100%；按住可输入百分比';

	/// zh-CN: '留白'
	String get marginWhitespace => '留白';

	/// zh-CN: '现在没有打开的书 —— 开一本之后这一颗才能给它单独设'
	String get noBookOpenYet => '现在没有打开的书 —— 开一本之后这一颗才能给它单独设';

	/// zh-CN: '版式工具'
	String get layoutTools => '版式工具';

	/// zh-CN: '滚屏'
	String get autoScroll => '滚屏';

	/// zh-CN: '清除本章的手动顺序'
	String get clearManualOrder => '清除本章的手动顺序';

	/// zh-CN: '消除双页之间的拼接缝隙'
	String get removeTwoPageSeam => '消除双页之间的拼接缝隙';

	/// zh-CN: '正在后台下载超分模型...'
	String get downloadingUpscaleInBackground => '正在后台下载超分模型...';

	/// zh-CN: '横屏'
	String get landscape => '横屏';

	/// zh-CN: '横向页左旋'
	String get rotateLandscapeLeft => '横向页左旋';

	/// zh-CN: '横向页右旋'
	String get rotateLandscapeRight => '横向页右旋';

	/// zh-CN: '格式'
	String get formatLabel => '格式';

	/// zh-CN: '条漫（上下滚动）每一拍推进多少屏：只作用于条漫，横翻按整页走'
	String get webtoonStepScreens => '条漫（上下滚动）每一拍推进多少屏：只作用于条漫，横翻按整页走';

	/// zh-CN: '条漫只裁左右，保留上下接缝。满版或检测不可靠的页面保留原样。'
	String get webtoonTrimSidesOnly => '条漫只裁左右，保留上下接缝。满版或检测不可靠的页面保留原样。';

	/// zh-CN: '权重'
	String get weights => '权重';

	/// zh-CN: '本章没有手动顺序可清除'
	String get noManualOrderHere => '本章没有手动顺序可清除';

	/// zh-CN: '本书：图像处理'
	String get bookImageProcessing => '本书：图像处理';

	/// zh-CN: '本书：启用 AI 超分辨率'
	String get bookEnableAiUpscale => '本书：启用 AI 超分辨率';

	/// zh-CN: '本书已开启超分（后续取图在取图层处理）'
	String get bookUpscaleOnFetch => '本书已开启超分（后续取图在取图层处理）';

	/// zh-CN: '本书已启用 AI 超分'
	String get bookAiUpscaleOn => '本书已启用 AI 超分';

	/// zh-CN: '本书已单独开启裁边 · 全局为关闭'
	String get bookTrimOnOverride => '本书已单独开启裁边 · 全局为关闭';

	/// zh-CN: '本书已单独关闭裁边 · 全局为开启，当前阅读不会裁边'
	String get bookTrimOffOverride => '本书已单独关闭裁边 · 全局为开启，当前阅读不会裁边';

	/// zh-CN: '本书已关闭超分（其它书仍按全局设置）'
	String get bookUpscaleOff => '本书已关闭超分（其它书仍按全局设置）';

	/// zh-CN: '本书已关闭 AI 超分（其它书仍按全局设置）'
	String get bookAiUpscaleOff => '本书已关闭 AI 超分（其它书仍按全局设置）';

	/// zh-CN: '本书启用 JPEG 降噪'
	String get bookEnableJpegDenoise => '本书启用 JPEG 降噪';

	/// zh-CN: '未锁止：指针一离开画面、手指一抬，窗口就收掉；锁止后窗口留在原地，可以先拖到别处再对焦点'
	String get loupeUnlockedFollows => '未锁止：指针一离开画面、手指一抬，窗口就收掉；锁止后窗口留在原地，可以先拖到别处再对焦点';

	/// zh-CN: '未下载'
	String get notDownloaded => '未下载';

	/// zh-CN: '暂停 / 继续自动滚屏'
	String get pauseResumeAutoScroll => '暂停 / 继续自动滚屏';

	/// zh-CN: '日志'
	String get logLabel => '日志';

	/// zh-CN: '无对齐（保持原始比例）'
	String get alignNone => '无对齐（保持原始比例）';

	/// zh-CN: '旋转设置'
	String get rotationSettings => '旋转设置';

	/// zh-CN: '文件大小'
	String get fileSize => '文件大小';

	/// zh-CN: '文件名自然序（page2 排在 page10 前）'
	String get pageOrderNatural => '文件名自然序（page2 排在 page10 前）';

	/// zh-CN: '文件'
	String get fileLabel => '文件';

	/// zh-CN: '放映未开启：点击开始放映'
	String get slideshowOffTapStart => '放映未开启：点击开始放映';

	/// zh-CN: '放映时在画面上显示「第几页 / 是否暂停」'
	String get slideshowDwellIndicator => '放映时在画面上显示「第几页 / 是否暂停」';

	/// zh-CN: '放映已开启但没在计时：点击继续'
	String get slideshowOnButIdle => '放映已开启但没在计时：点击继续';

	/// zh-CN: '放映已到本章末尾并停止'
	String get slideshowStoppedAtEnd => '放映已到本章末尾并停止';

	/// zh-CN: '放映中，点击暂停'
	String get slideshowPlayingTapPause => '放映中，点击暂停';

	/// zh-CN: '放映中'
	String get slideshowPlaying => '放映中';

	/// zh-CN: '放完'
	String get slideshowFinished => '放完';

	/// zh-CN: '放大镜：把指针那一小块像素原样放大到旁边的窗口里（检网点与端部细节）'
	String get loupeTooltip => '放大镜：把指针那一小块像素原样放大到旁边的窗口里（检网点与端部细节）';

	/// zh-CN: '放大镜已开：把指针那一小块像素原样放大到旁边的窗口里'
	String get loupeEnabled => '放大镜已开：把指针那一小块像素原样放大到旁边的窗口里';

	/// zh-CN: '放大镜'
	String get loupe => '放大镜';

	/// zh-CN: '放到章末就翻进下一章；没有下一章时停住'
	String get slideshowAdvanceChapter => '放到章末就翻进下一章；没有下一章时停住';

	/// zh-CN: '放到章末就回到第一页，一直放'
	String get slideshowLoopInChapter => '放到章末就回到第一页，一直放';

	/// zh-CN: '放到本章最后一页就停住，并关掉放映'
	String get slideshowStopAtChapterEnd => '放到本章最后一页就停住，并关掉放映';

	/// zh-CN: '推理'
	String get inference => '推理';

	/// zh-CN: '按需嵌字翻译与端侧 OCR'
	String get onDemandTranslateOcr => '按需嵌字翻译与端侧 OCR';

	/// zh-CN: '按文件头识别。PNG、WebP 等页面保留原样'
	String get detectByFileHeader => '按文件头识别。PNG、WebP 等页面保留原样';

	/// zh-CN: '拖动调整显示顺序；应用后画面仍停在当前这一页'
	String get dragReorderStaysOnPage => '拖动调整显示顺序；应用后画面仍停在当前这一页';

	/// zh-CN: '打开本章页面列表并拖出顺序（以当前顺序为起点）'
	String get openChapterListToDrag => '打开本章页面列表并拖出顺序（以当前顺序为起点）';

	/// zh-CN: '打开在线或本地漫画后可单独设置'
	String get perBookAfterOpening => '打开在线或本地漫画后可单独设置';

	/// zh-CN: '手指：按住才出窗口，抬手即收（配锁止可拖窗口移动）'
	String get touchHoldToShow => '手指：按住才出窗口，抬手即收（配锁止可拖窗口移动）';

	/// zh-CN: '手动顺序（在页面列表里拖）'
	String get manualOrderDragList => '手动顺序（在页面列表里拖）';

	/// zh-CN: '手动缩放'
	String get manualZoom => '手动缩放';

	/// zh-CN: '所有漫画默认启用降噪'
	String get denoiseDefaultForAll => '所有漫画默认启用降噪';

	/// zh-CN: '所有书的默认，现在关着；打开后没有单独设置的书都会跟着开'
	String get allBooksDefaultCurrentlyOff => '所有书的默认，现在关着；打开后没有单独设置的书都会跟着开';

	/// zh-CN: '所有书的默认（与设置页那条同一条）'
	String get allBooksDefaultShared => '所有书的默认（与设置页那条同一条）';

	/// zh-CN: '悬停：只跟随鼠标，指针离开画面即收'
	String get hoverFollowsMouse => '悬停：只跟随鼠标，指针离开画面即收';

	/// zh-CN: '悬停滚动'
	String get hoverScroll => '悬停滚动';

	/// zh-CN: '恢复默认参数'
	String get restoreDefaultParams => '恢复默认参数';

	/// zh-CN: '恢复保守默认值'
	String get restoreConservativeDefaults => '恢复保守默认值';

	/// zh-CN: '当前设备尚未下载 mImage ONNX 超分模型（约 5.4 MB），是否立即下载并启用？'
	String get mimageModelMissingPrompt => '当前设备尚未下载 mImage ONNX 超分模型（约 5.4 MB），是否立即下载并启用？';

	/// zh-CN: '当前没有可读取的图片信息'
	String get noImageInfoAvailable => '当前没有可读取的图片信息';

	/// zh-CN: '当前平台暂无 RealPLKSR 推理后端'
	String get noRealPlksrBackendHere => '当前平台暂无 RealPLKSR 推理后端';

	/// zh-CN: '当前已开启平滑翻页动画'
	String get pageAnimationOn => '当前已开启平滑翻页动画';

	/// zh-CN: '当前已关闭翻页动画'
	String get pageAnimationOff => '当前已关闭翻页动画';

	/// zh-CN: '当前图片'
	String get currentImage => '当前图片';

	/// zh-CN: '当前使用端侧离线翻译引擎，无需网络即可生成译文页'
	String get translateOnDeviceNow => '当前使用端侧离线翻译引擎，无需网络即可生成译文页';

	/// zh-CN: '当前使用云端 API 端点翻译，自动擦除原气泡并回填译文'
	String get translateCloudEndpointNow => '当前使用云端 API 端点翻译，自动擦除原气泡并回填译文';

	/// zh-CN: '强制'
	String get force => '强制';

	/// zh-CN: '引擎'
	String get engine => '引擎';

	/// zh-CN: '开启自动滚屏'
	String get enableAutoScroll => '开启自动滚屏';

	/// zh-CN: '开启本书超分'
	String get enableBookUpscale => '开启本书超分';

	/// zh-CN: '幻灯片放映'
	String get slideshow => '幻灯片放映';

	/// zh-CN: '已锁止：指针离开画面、手指抬起后窗口仍留着，拖窗口本身可以移动它；双击窗口可取消锁止'
	String get loupeLockedOn => '已锁止：指针离开画面、手指抬起后窗口仍留着，拖窗口本身可以移动它；双击窗口可取消锁止';

	/// zh-CN: '已重新加入下载队列'
	String get requeuedToDownload => '已重新加入下载队列';

	/// zh-CN: '已禁用'
	String get alreadyDisabled => '已禁用';

	/// zh-CN: '已清除本章的手动顺序'
	String get manualOrderClearedDone => '已清除本章的手动顺序';

	/// zh-CN: '已暂停，点击继续放映（不改设置）'
	String get slideshowPausedTapResume => '已暂停，点击继续放映（不改设置）';

	/// zh-CN: '已开启自动滚屏'
	String get autoScrollEnabled => '已开启自动滚屏';

	/// zh-CN: '已开启 · 白边和黑边自动检测'
	String get trimOnAutoDetect => '已开启 · 白边和黑边自动检测';

	/// zh-CN: '已开启 · RealPLKSR 1×'
	String get denoiseOnRealPlksr => '已开启 · RealPLKSR 1×';

	/// zh-CN: '已切换为原图对比'
	String get switchedToOriginalCompare => '已切换为原图对比';

	/// zh-CN: '已切回处理后画面'
	String get switchedBackToProcessed => '已切回处理后画面';

	/// zh-CN: '已关闭 · 显示完整页面'
	String get trimOffFullPage => '已关闭 · 显示完整页面';

	/// zh-CN: '已关闭 · 原图保持不变'
	String get trimOffOriginalKept => '已关闭 · 原图保持不变';

	/// zh-CN: '居左适应窗口'
	String get fitWindowLeft => '居左适应窗口';

	/// zh-CN: '居右适应窗口'
	String get fitWindowRight => '居右适应窗口';

	/// zh-CN: '对比原图'
	String get compareOriginal => '对比原图';

	/// zh-CN: '宽页策略'
	String get widePagePolicy => '宽页策略';

	/// zh-CN: '宽度对齐（双页宽度统一）'
	String get alignWidth => '宽度对齐（双页宽度统一）';

	/// zh-CN: '安全留边'
	String get safeMargin => '安全留边';

	/// zh-CN: '处理状态'
	String get processingStatus => '处理状态';

	/// zh-CN: '增大可容忍纸张底色和轻微噪点；浅色细节较多时使用较小值'
	String get bgToleranceHint => '增大可容忍纸张底色和轻微噪点；浅色细节较多时使用较小值';

	/// zh-CN: '在线图源：超分在取图/解码层发生，这颗是本书的开关（没有逐页状态）'
	String get onlineUpscaleAtFetchLayer => '在线图源：超分在取图/解码层发生，这颗是本书的开关（没有逐页状态）';

	/// zh-CN: '在线和本地漫画共用；阅读时放大内容区域'
	String get sharedUpscaleEnlarge => '在线和本地漫画共用；阅读时放大内容区域';

	/// zh-CN: '在线和本地漫画共用；保持原分辨率，降噪后再超分'
	String get sharedDenoiseThenUpscale => '在线和本地漫画共用；保持原分辨率，降噪后再超分';

	/// zh-CN: '在检测内容周围额外保留空间，保护文字、页码和线条'
	String get trimSafeMarginKeeps => '在检测内容周围额外保留空间，保护文字、页码和线条';

	/// zh-CN: '图源顺序（插件/归档给的顺序）'
	String get pageOrderSource => '图源顺序（插件/归档给的顺序）';

	/// zh-CN: '图像处理'
	String get imageProcessing => '图像处理';

	/// zh-CN: '回读'
	String get readback => '回读';

	/// zh-CN: '后端'
	String get backend => '后端';

	/// zh-CN: '只影响这本书；模型未下载，开启时会先问一句'
	String get onlyThisBookAskFirst => '只影响这本书；模型未下载，开启时会先问一句';

	/// zh-CN: '只影响这本书，其它书仍按全局设置'
	String get onlyThisBookGlobalOthers => '只影响这本书，其它书仍按全局设置';

	/// zh-CN: '只影响当前漫画；超分由它自己的开关决定'
	String get onlyThisComicUpscaleOwn => '只影响当前漫画；超分由它自己的开关决定';

	/// zh-CN: '双页独立'
	String get twoPagesIndependent => '双页独立';

	/// zh-CN: '双页模式（点击切为单页）'
	String get twoPageModeTap => '双页模式（点击切为单页）';

	/// zh-CN: '双页'
	String get twoPages => '双页';

	/// zh-CN: '原始大小'
	String get originalSize => '原始大小';

	/// zh-CN: '原图对比中'
	String get comparingOriginal => '原图对比中';

	/// zh-CN: '单页模式（点击切为双页）'
	String get singlePageModeTap => '单页模式（点击切为双页）';

	/// zh-CN: '单页'
	String get singlePage => '单页';

	/// zh-CN: '单边裁切上限'
	String get trimSideLimit => '单边裁切上限';

	/// zh-CN: '动画页面不参与处理。模型效果强度固定；原图、降噪和超分结果分别缓存。'
	String get animatedNotProcessed => '动画页面不参与处理。模型效果强度固定；原图、降噪和超分结果分别缓存。';

	/// zh-CN: '动画'
	String get animated => '动画';

	/// zh-CN: '切换阅读滤镜与护眼遮罩'
	String get toggleReaderFilter => '切换阅读滤镜与护眼遮罩';

	/// zh-CN: '分辨率'
	String get resolution => '分辨率';

	/// zh-CN: '分块'
	String get blockLabel => '分块';

	/// zh-CN: '关闭自动滚屏'
	String get disableAutoScroll => '关闭自动滚屏';

	/// zh-CN: '关闭自动旋转'
	String get disableAutoRotate => '关闭自动旋转';

	/// zh-CN: '关闭本书超分'
	String get disableBookUpscale => '关闭本书超分';

	/// zh-CN: '全本'
	String get wholeBook => '全本';

	/// zh-CN: '全景模式'
	String get panoramaMode => '全景模式';

	/// zh-CN: '倒序（本章页表整个反过来）'
	String get pageOrderReversed => '倒序（本章页表整个反过来）';

	/// zh-CN: '倍率'
	String get scaleLabel => '倍率';

	/// zh-CN: '以下尚未接进本仓'
	String get notWiredBelow => '以下尚未接进本仓';

	/// zh-CN: '仅处理 JPEG 页面'
	String get jpegPagesOnly => '仅处理 JPEG 页面';

	/// zh-CN: '临时查看原图，关闭后恢复处理结果'
	String get peekOriginalBriefly => '临时查看原图，关闭后恢复处理结果';

	/// zh-CN: '临时切回原图，关闭后恢复处理结果'
	String get peekBackToOriginal => '临时切回原图，关闭后恢复处理结果';

	/// zh-CN: '与超分独立。较小的分块降低推理内存占用；固定输入模型按模型尺寸处理'
	String get denoiseBlockIndependentHint => '与超分独立。较小的分块降低推理内存占用；固定输入模型按模型尺寸处理';

	/// zh-CN: '不修改原图；降噪在超分之前运行'
	String get denoiseOriginalSafeBefore => '不修改原图；降噪在超分之前运行';

	/// zh-CN: '不修改原图；单本开关仍可在阅读设置覆盖'
	String get denoiseOriginalSafeBookOverride => '不修改原图；单本开关仍可在阅读设置覆盖';

	/// zh-CN: '下载偏好'
	String get downloadPreference => '下载偏好';

	/// zh-CN: '下载 AI 超分模型'
	String get downloadAiUpscaleModel => '下载 AI 超分模型';

	/// zh-CN: '一律左旋'
	String get rotateAlwaysLeft => '一律左旋';

	/// zh-CN: '一律右旋'
	String get rotateAlwaysRight => '一律右旋';

	/// zh-CN: 'OCR 权重就绪'
	String get ocrWeightsReady => 'OCR 权重就绪';

	/// zh-CN: 'NeoView 视口感应交互示意'
	String get neoviewViewportDemo => 'NeoView 视口感应交互示意';

	/// zh-CN: 'JPEG 降噪模型未安装'
	String get denoiseModelMissing => 'JPEG 降噪模型未安装';

	/// zh-CN: 'AI 超分辨率'
	String get aiSuperResolution => 'AI 超分辨率';

	/// zh-CN: '下载管理'
	String get downloadManage => '下载管理';

	/// zh-CN: '开始下载'
	String get startDownload => '开始下载';

	/// zh-CN: '暂停下载'
	String get pauseDownload => '暂停下载';

	/// zh-CN: '继续下载'
	String get resumeDownload => '继续下载';

	/// zh-CN: '重新下载'
	String get restartDownload => '重新下载';

	/// zh-CN: '删除下载'
	String get deleteDownload => '删除下载';

	/// zh-CN: '重试失败部分'
	String get retryFailedParts => '重试失败部分';

	/// zh-CN: '仅重新下载未完成或失败的章节与图片'
	String get retryFailedPartsSubtitle => '仅重新下载未完成或失败的章节与图片';

	/// zh-CN: '增量补全（推荐）'
	String get restartDownloadSmart => '增量补全（推荐）';

	/// zh-CN: '检测本地已下载内容，仅下载缺失或失败的图片'
	String get restartDownloadSmartDesc => '检测本地已下载内容，仅下载缺失或失败的图片';

	/// zh-CN: '全量重下'
	String get restartDownloadFull => '全量重下';

	/// zh-CN: '重置全部章节进度，从头完整下载'
	String get restartDownloadFullDesc => '重置全部章节进度，从头完整下载';

	/// zh-CN: '选图提取'
	String get pickAndExtract => '选图提取';

	/// zh-CN: '挑选特定图片导出或保存'
	String get pickAndExtractSubtitle => '挑选特定图片导出或保存';

	/// zh-CN: '保存至相册'
	String get saveToAlbum => '保存至相册';

	/// zh-CN: '导出至文件夹'
	String get saveToDirectory => '导出至文件夹';

	/// zh-CN: '导出为 ZIP'
	String get exportZip => '导出为 ZIP';

	/// zh-CN: '下载选中项'
	String get downloadSelected => '下载选中项';

	/// zh-CN: '全选'
	String get selectAll => '全选';

	/// zh-CN: '取消全选'
	String get deselectAll => '取消全选';

	/// zh-CN: '反选'
	String get invertSelection => '反选';

	/// zh-CN: '范围选择'
	String get rangeSelect => '范围选择';

	/// zh-CN: '输入页码范围，例如: 1-5, 8, 12'
	String get rangeSelectPrompt => '输入页码范围，例如: 1-5, 8, 12';

	/// zh-CN: '已选 $selected / $total 页'
	String selectedCount({required Object selected, required Object total}) => '已选 ${selected} / ${total} 页';

	/// zh-CN: '正在处理中: $current / $total'
	String extractingProgress({required Object current, required Object total}) => '正在处理中: ${current} / ${total}';

	/// zh-CN: '提取完成'
	String get extractSuccess => '提取完成';

	/// zh-CN: '提取失败: $error'
	String extractFailed({required Object error}) => '提取失败: ${error}';

	/// zh-CN: '查看全部下载任务'
	String get viewAllTasks => '查看全部下载任务';

	/// zh-CN: '正在下载'
	String get downloadStatusDownloading => '正在下载';

	/// zh-CN: '已暂停'
	String get downloadStatusPaused => '已暂停';

	/// zh-CN: '已完成'
	String get downloadStatusCompleted => '已完成';

	/// zh-CN: '下载出错'
	String get downloadStatusFailed => '下载出错';

	/// zh-CN: '等待中'
	String get downloadStatusQueued => '等待中';

	/// zh-CN: '删除下载'
	String get confirmDeleteDownloadTitle => '删除下载';

	/// zh-CN: '确认删除该漫画的下载任务及本地文件吗？'
	String get confirmDeleteDownload => '确认删除该漫画的下载任务及本地文件吗？';

	/// zh-CN: '已开始下载本漫画'
	String get downloadStartedToast => '已开始下载本漫画';

	/// zh-CN: '已自动添加至收藏'
	String get autoCollectedToast => '已自动添加至收藏';

	/// zh-CN: '边看边下载'
	String get readWhileDownloading => '边看边下载';

	/// zh-CN: '阅读时自动将已看内容保存到本地下载目录'
	String get readWhileDownloadingSubtitle => '阅读时自动将已看内容保存到本地下载目录';

	/// zh-CN: '翻页模式'
	String get pageMode => '翻页模式';

	/// zh-CN: '全屏模式'
	String get fullscreen => '全屏模式';

	/// zh-CN: '左手模式'
	String get leftHandMode => '左手模式';

	/// zh-CN: '右手模式'
	String get rightHandMode => '右手模式';

	/// zh-CN: '反转左右方向键'
	String get reverseHorizontalPageTurn => '反转左右方向键';

	/// zh-CN: '交换左右方向键的翻页方向，适合从右到左的日漫'
	String get reverseHorizontalPageTurnSubtitle => '交换左右方向键的翻页方向，适合从右到左的日漫';

	/// zh-CN: '条漫点击翻动'
	String get webtoonTapPageTurn => '条漫点击翻动';

	/// zh-CN: '允许点击上下翻动'
	String get enableWebtoonTapPageTurn => '允许点击上下翻动';

	/// zh-CN: '条漫模式下点击上方/下方区域翻动，中央区域仍用于打开操作栏'
	String get webtoonTapPageTurnSubtitle => '条漫模式下点击上方/下方区域翻动，中央区域仍用于打开操作栏';

	/// zh-CN: '阅读模式'
	String get readingMode => '阅读模式';

	/// zh-CN: '启用本漫画设置'
	String get perComicReadMode => '启用本漫画设置';

	/// zh-CN: '仅当前漫画生效'
	String get perComicReadModeSubtitle => '仅当前漫画生效';

	/// zh-CN: '跟随全局'
	String get perComicFollowGlobal => '跟随全局';

	/// zh-CN: '全局为'
	String get perComicGlobalIs => '全局为';

	/// zh-CN: '本漫'
	String get perComicThisComic => '本漫';

	/// zh-CN: '信息项显示'
	String get infoDisplay => '信息项显示';

	/// zh-CN: '页数'
	String get pageNumber => '页数';

	/// zh-CN: '显示当前页/总页数'
	String get pageNumberSubtitle => '显示当前页/总页数';

	/// zh-CN: '网络状态'
	String get networkStatus => '网络状态';

	/// zh-CN: 'Linux 下可能不准确'
	String get networkStatusSubtitle => 'Linux 下可能不准确';

	/// zh-CN: '电量'
	String get battery => '电量';

	/// zh-CN: '时间'
	String get time => '时间';

	/// zh-CN: '顶部'
	String get verticalPositionTop => '顶部';

	/// zh-CN: '底部'
	String get verticalPositionBottom => '底部';

	/// zh-CN: '左侧'
	String get horizontalPositionLeft => '左侧';

	/// zh-CN: '居中'
	String get horizontalPositionCenter => '居中';

	/// zh-CN: '右侧'
	String get horizontalPositionRight => '右侧';

	/// zh-CN: '从左到右'
	String get readingDirectionLtr => '从左到右';

	/// zh-CN: '从右到左'
	String get readingDirectionRtl => '从右到左';

	/// zh-CN: '从上到下'
	String get readingDirectionVertical => '从上到下';

	/// zh-CN: '条漫'
	String get webtoon => '条漫';

	/// zh-CN: '单页式（横向翻页）'
	String get singlePageRow => '单页式（横向翻页）';

	/// zh-CN: '左开模式 · 下一页在左'
	String get readingDirectionLeftOpen => '左开模式 · 下一页在左';

	/// zh-CN: '右开模式 · 下一页在右'
	String get readingDirectionRightOpen => '右开模式 · 下一页在右';

	/// zh-CN: '阅读方向'
	String get readingDirectionToggle => '阅读方向';

	/// zh-CN: '当前左开（下一页在左）· 点按切换为右开'
	String get readingDirectionToggleLeftOpen => '当前左开（下一页在左）· 点按切换为右开';

	/// zh-CN: '当前右开（下一页在右）· 点按切换为左开'
	String get readingDirectionToggleRightOpen => '当前右开（下一页在右）· 点按切换为左开';

	/// zh-CN: '条漫模式没有左右翻页方向'
	String get readingDirectionToggleDisabled => '条漫模式没有左右翻页方向';

	/// zh-CN: '顶栏显示阅读方向切换'
	String get readingDirectionToggleSetting => '顶栏显示阅读方向切换';

	/// zh-CN: '翻页预览'
	String get swipePreview => '翻页预览';

	/// zh-CN: '翻页时两侧直接显示画面，不再先用大字页码占位（每页多解一张视口宽度的位图）'
	String get swipePreviewSubtitle => '翻页时两侧直接显示画面，不再先用大字页码占位（每页多解一张视口宽度的位图）';

	/// zh-CN: '双页阅读'
	String get doublePage => '双页阅读';

	/// zh-CN: '在当前阅读模式中启用双页并排'
	String get doublePageSubtitle => '在当前阅读模式中启用双页并排';

	/// zh-CN: '双页无缝'
	String get doublePageSeamless => '双页无缝';

	/// zh-CN: '左右各占一半宽度，按图片比例独立显示并消除中间留白'
	String get doublePageSeamlessSubtitle => '左右各占一半宽度，按图片比例独立显示并消除中间留白';

	/// zh-CN: '首页留白'
	String get doublePageLeadingBlank => '首页留白';

	/// zh-CN: '在每章最前插入一页空白，使配对整体错一位'
	String get doublePageLeadingBlankSubtitle => '在每章最前插入一页空白，使配对整体错一位';

	/// zh-CN: '横长页左右分割'
	String get splitLandscapePages => '横长页左右分割';

	/// zh-CN: '自动将跨页横长图切分为左右两半阅读'
	String get splitLandscapePagesSubtitle => '自动将跨页横长图切分为左右两半阅读';

	/// zh-CN: '分割阅读顺序'
	String get landscapeSplitDirection => '分割阅读顺序';

	/// zh-CN: '跟随阅读方向'
	String get splitDirectionAuto => '跟随阅读方向';

	/// zh-CN: '左起（左→右）'
	String get splitDirectionLtr => '左起（左→右）';

	/// zh-CN: '右起（右→左）'
	String get splitDirectionRtl => '右起（右→左）';

	/// zh-CN: '悬停唤出'
	String get hoverReveal => '悬停唤出';

	/// zh-CN: '边缘悬停唤出控制栏'
	String get hoverRevealEnabled => '边缘悬停唤出控制栏';

	/// zh-CN: '鼠标移至屏幕顶部或底部边缘时自动浮现对应工具栏（参考 NeoView）'
	String get hoverRevealEnabledSubtitle => '鼠标移至屏幕顶部或底部边缘时自动浮现对应工具栏（参考 NeoView）';

	/// zh-CN: '底部缩略图条'
	String get thumbnailStrip => '底部缩略图条';

	/// zh-CN: '在控制栏展开每页缩略图，与进度条并成同一块面板；换书、换章、重启后保持'
	String get thumbnailStripSubtitle => '在控制栏展开每页缩略图，与进度条并成同一块面板；换书、换章、重启后保持';

	/// zh-CN: '透明顶栏'
	String get transparentTopBar => '透明顶栏';

	/// zh-CN: '顶栏不再用玻璃材质，改为一层半透明蒙层，画面从底下透出来（参考 JHenTai）'
	String get transparentTopBarSubtitle => '顶栏不再用玻璃材质，改为一层半透明蒙层，画面从底下透出来（参考 JHenTai）';

	/// zh-CN: '顶栏蒙层不透明度'
	String get transparentTopBarOpacity => '顶栏蒙层不透明度';

	/// zh-CN: '展开缩略图'
	String get thumbnailStripExpand => '展开缩略图';

	/// zh-CN: '收起缩略图'
	String get thumbnailStripCollapse => '收起缩略图';

	/// zh-CN: '缩略图按原图比例显示'
	String get thumbnailStripOriginalAspectRatio => '缩略图按原图比例显示';

	/// zh-CN: '关闭时统一竖屏显示，开启后按每张图片的比例完整显示'
	String get thumbnailStripOriginalAspectRatioSubtitle => '关闭时统一竖屏显示，开启后按每张图片的比例完整显示';

	/// zh-CN: '当前'
	String get thumbnailStripCurrent => '当前';

	/// zh-CN: '跳转到第 $page 页'
	String thumbnailStripJumpToPage({required Object page}) => '跳转到第 ${page} 页';

	/// zh-CN: '顶部边缘唤出顶栏'
	String get hoverRevealTop => '顶部边缘唤出顶栏';

	/// zh-CN: '底部边缘唤出底栏'
	String get hoverRevealBottom => '底部边缘唤出底栏';

	/// zh-CN: '顶部唤出感应区高度'
	String get hoverTriggerAreaTop => '顶部唤出感应区高度';

	/// zh-CN: '底部唤出感应区高度'
	String get hoverTriggerAreaBottom => '底部唤出感应区高度';

	/// zh-CN: '离开后自动收回延时'
	String get hoverHideDelay => '离开后自动收回延时';

	/// zh-CN: '显示边缘感应提示线'
	String get hoverShowVisualIndicator => '显示边缘感应提示线';

	/// zh-CN: '在触发区显示微弱的指示线，便于直观感知范围'
	String get hoverShowVisualIndicatorSubtitle => '在触发区显示微弱的指示线，便于直观感知范围';

	/// zh-CN: '唤出感应区示意（NeoView 风格）'
	String get hoverAreaPreview => '唤出感应区示意（NeoView 风格）';

	/// zh-CN: '顶部感应区：{height}px'
	String get hoverAreaTopHint => '顶部感应区：{height}px';

	/// zh-CN: '底部感应区：{height}px'
	String get hoverAreaBottomHint => '底部感应区：{height}px';

	/// zh-CN: '钉住顶栏（不再自动收起）'
	String get pinTopBar => '钉住顶栏（不再自动收起）';

	/// zh-CN: '取消钉住顶栏'
	String get unpinTopBar => '取消钉住顶栏';

	/// zh-CN: '钉住底栏（不再自动收起）'
	String get pinBottomBar => '钉住底栏（不再自动收起）';

	/// zh-CN: '取消钉住底栏'
	String get unpinBottomBar => '取消钉住底栏';

	/// zh-CN: '横屏阅读'
	String get landscapeReader => '横屏阅读';

	/// zh-CN: '阅读时切换为横屏，离开后恢复原来的方向'
	String get landscapeReaderSubtitle => '阅读时切换为横屏，离开后恢复原来的方向';

	/// zh-CN: '系统模式'
	String get themeMode => '系统模式';

	/// zh-CN: '自动阅读'
	String get autoRead => '自动阅读';

	/// zh-CN: '开启后自动滚动'
	String get autoReadSubtitle => '开启后自动滚动';

	/// zh-CN: '隐藏暂停按钮'
	String get autoReadHidePauseButton => '隐藏暂停按钮';

	/// zh-CN: '自动阅读继续运行，但不显示阅读页上的暂停/播放按钮'
	String get autoReadHidePauseButtonSubtitle => '自动阅读继续运行，但不显示阅读页上的暂停/播放按钮';

	/// zh-CN: '平滑滚动'
	String get autoReadSmooth => '平滑滚动';

	/// zh-CN: '条漫模式下连续匀速滚动，关闭则按间隔分段跳转'
	String get autoReadSmoothSubtitle => '条漫模式下连续匀速滚动，关闭则按间隔分段跳转';

	/// zh-CN: '条漫滚动距离'
	String get webtoonScrollDistance => '条漫滚动距离';

	/// zh-CN: '条漫滚动间隔'
	String get webtoonScrollInterval => '条漫滚动间隔';

	/// zh-CN: '单页式滚动间隔'
	String get singlePageScrollInterval => '单页式滚动间隔';

	/// zh-CN: '预加载'
	String get preload => '预加载';

	/// zh-CN: '预加载图片数量'
	String get preloadImageCount => '预加载图片数量';

	/// zh-CN: '提前下载当前阅读位置之后的图片'
	String get preloadImageCountSubtitle => '提前下载当前阅读位置之后的图片';

	/// zh-CN: '预加载章节数量'
	String get preloadChapterCount => '预加载章节数量';

	/// zh-CN: '提前加载后续章节信息'
	String get preloadChapterCountSubtitle => '提前加载后续章节信息';

	/// zh-CN: '阅读背景'
	String get background => '阅读背景';

	/// zh-CN: '自动'
	String get auto => '自动';

	/// zh-CN: '黑色'
	String get black => '黑色';

	/// zh-CN: '白色'
	String get white => '白色';

	/// zh-CN: '灰色'
	String get grey => '灰色';

	/// zh-CN: '自适应取色'
	String get adaptive => '自适应取色';

	/// zh-CN: '边缘渐变'
	String get adaptiveEdge => '边缘渐变';

	/// zh-CN: '背景压暗'
	String get ambientDim => '背景压暗';

	/// zh-CN: '把取自画面的颜色压暗后再铺成背景，越大越不刺眼；仅在本地漫画生效'
	String get ambientDimSubtitle => '把取自画面的颜色压暗后再铺成背景，越大越不刺眼；仅在本地漫画生效';

	/// zh-CN: '阅读体验'
	String get readingExperience => '阅读体验';

	/// zh-CN: '连续翻页速度'
	String get keyboardPageTurnSpeed => '连续翻页速度';

	/// zh-CN: '横向阅读时，按下立即翻一页，持续按住翻页键后按此速度连续翻页。动画自动适配速度，松手后只完成当前页；双页模式每次翻一个画面。'
	String get keyboardPageTurnSpeedSubtitle => '横向阅读时，按下立即翻一页，持续按住翻页键后按此速度连续翻页。动画自动适配速度，松手后只完成当前页；双页模式每次翻一个画面。';

	/// zh-CN: '页/秒'
	String get pagesPerSecond => '页/秒';

	/// zh-CN: '长按翻页高级选项'
	String get keyboardPageTurnAdvanced => '长按翻页高级选项';

	/// zh-CN: '长按启动延迟'
	String get keyboardPageTurnHoldDelay => '长按启动延迟';

	/// zh-CN: '按住多久后开始连续翻页。仅影响启动等待，持续翻页速度由上面的页/秒决定。'
	String get keyboardPageTurnHoldDelaySubtitle => '按住多久后开始连续翻页。仅影响启动等待，持续翻页速度由上面的页/秒决定。';

	/// zh-CN: '关闭翻页动画'
	String get disableAnimation => '关闭翻页动画';

	/// zh-CN: '关闭整页翻页动画，小幅滚动动画不受影响'
	String get disableAnimationSubtitle => '关闭整页翻页动画，小幅滚动动画不受影响';

	/// zh-CN: '阅读滤镜（仅深色模式）'
	String get readFilter => '阅读滤镜（仅深色模式）';

	/// zh-CN: '仅在阅读界面生效，可降低夜间阅读亮度'
	String get readFilterSubtitle => '仅在阅读界面生效，可降低夜间阅读亮度';

	/// zh-CN: '滤镜强度'
	String get filterIntensity => '滤镜强度';

	/// zh-CN: '墨水屏优化（仅横向）'
	String get einkOptimization => '墨水屏优化（仅横向）';

	/// zh-CN: '翻页后先白屏再显示图片'
	String get einkOptimizationSubtitle => '翻页后先白屏再显示图片';

	/// zh-CN: '白屏时长'
	String get einkDelay => '白屏时长';

	/// zh-CN: '两侧留白'
	String get sidePadding => '两侧留白';

	/// zh-CN: '自定义左右留白比例'
	String get sidePaddingSubtitle => '自定义左右留白比例';

	/// zh-CN: '每侧留白比例'
	String get sidePaddingPercent => '每侧留白比例';

	/// zh-CN: '默认关闭，可按需开启'
	String get batterySubtitle => '默认关闭，可按需开启';

	/// zh-CN: '显示当前时间'
	String get timeSubtitle => '显示当前时间';

	/// zh-CN: '信息条位置'
	String get infoBarPosition => '信息条位置';

	/// zh-CN: '显示在状态栏'
	String get showInStatusBar => '显示在状态栏';

	/// zh-CN: '开启后，顶部信息条会进入系统状态栏区域'
	String get showInStatusBarSubtitle => '开启后，顶部信息条会进入系统状态栏区域';

	/// zh-CN: '边缘间距'
	String get edgePadding => '边缘间距';

	/// zh-CN: '信息条样式'
	String get infoBarStyle => '信息条样式';

	/// zh-CN: '背景透明度'
	String get backgroundOpacity => '背景透明度';

	/// zh-CN: '字体大小'
	String get fontSize => '字体大小';

	/// zh-CN: '当前已全部关闭，阅读页中的信息条会完全隐藏。'
	String get allHiddenNotice => '当前已全部关闭，阅读页中的信息条会完全隐藏。';

	/// zh-CN: '横向在中间时，边缘间距不会生效。'
	String get edgePaddingDisabled => '横向在中间时，边缘间距不会生效。';

	/// zh-CN: '底部进度条'
	String get bottomProgressBar => '底部进度条';

	/// zh-CN: '在画面底边画一条常驻细条表示翻页进度。它不随上下栏收起，与左下角信息条各开各的、互不影响'
	String get bottomProgressBarSubtitle => '在画面底边画一条常驻细条表示翻页进度。它不随上下栏收起，与左下角信息条各开各的、互不影响';

	/// zh-CN: '进度条荧光'
	String get bottomProgressBarGlow => '进度条荧光';

	/// zh-CN: '给已经走过的这一段加一圈光晕'
	String get bottomProgressBarGlowSubtitle => '给已经走过的这一段加一圈光晕';

	/// zh-CN: '阅读设置'
	String get settings => '阅读设置';

	/// zh-CN: '上一章'
	String get previousChapter => '上一章';

	/// zh-CN: '下一章'
	String get nextChapter => '下一章';

	/// zh-CN: '返回首页'
	String get backToHome => '返回首页';

	/// zh-CN: '跳转'
	String get jumpToChapterTitle => '跳转';

	/// zh-CN: '是否要跳转到$chapter？'
	String jumpToChapterMessage({required Object chapter}) => '是否要跳转到${chapter}？';

	/// zh-CN: '选择章节'
	String get selectChapter => '选择章节';

	/// zh-CN: '全屏（f11）'
	String get enterFullscreen => '全屏（f11）';

	/// zh-CN: '退出全屏'
	String get exitFullscreen => '退出全屏';

	/// zh-CN: '章节过渡中'
	String get chapterTransition => '章节过渡中';

	/// zh-CN: '继续翻页加载'
	String get transitionSwipeToLoad => '继续翻页加载';

	/// zh-CN: '加载完成'
	String get transitionLoaded => '加载完成';

	/// zh-CN: '加载失败，点击重试'
	String get transitionLoadFailedRetry => '加载失败，点击重试';

	/// zh-CN: '继续下拉到上一章'
	String get pullDownToPrevChapter => '继续下拉到上一章';

	/// zh-CN: '松手跳转到上一章'
	String get releaseToJumpPrevChapter => '松手跳转到上一章';

	/// zh-CN: '松手加载到上一章'
	String get releaseToLoadPrevChapter => '松手加载到上一章';

	/// zh-CN: '继续上拉到下一章'
	String get pullUpToNextChapter => '继续上拉到下一章';

	/// zh-CN: '松手跳转到下一章'
	String get releaseToJumpNextChapter => '松手跳转到下一章';

	/// zh-CN: '松手加载到下一章'
	String get releaseToLoadNextChapter => '松手加载到下一章';

	/// zh-CN: '章节未下载'
	String get chapterNotDownloaded => '章节未下载';

	/// zh-CN: '$result 加载失败'
	String loadFailedWithResult({required Object result}) => '${result}\n加载失败';

	/// zh-CN: '章节 $order'
	String chapterOrder({required Object order}) => '章节 ${order}';

	/// zh-CN: '双击操作'
	String get doubleTapAction => '双击操作';

	/// zh-CN: '双击缩放'
	String get doubleTapZoom => '双击缩放';

	/// zh-CN: '双击图片可在缩放和还原之间切换'
	String get doubleTapZoomSubtitle => '双击图片可在缩放和还原之间切换';

	/// zh-CN: '双击打开操作栏'
	String get doubleTapOpenMenu => '双击打开操作栏';

	/// zh-CN: '双击页面打开操作栏（与双击缩放互斥）'
	String get doubleTapOpenMenuSubtitle => '双击页面打开操作栏（与双击缩放互斥）';

	/// zh-CN: '点击唤出上下栏'
	String get centerTapBar => '点击唤出上下栏';

	/// zh-CN: '点击中间唤出/收起上下栏'
	String get centerTapToggleBars => '点击中间唤出/收起上下栏';

	/// zh-CN: '关闭后单击阅读区不再显隐上下栏（条漫模式下「点哪儿都算中间」也一并关闭），改用桌面端边缘悬停或双击打开操作栏唤出'
	String get centerTapToggleBarsSubtitle => '关闭后单击阅读区不再显隐上下栏（条漫模式下「点哪儿都算中间」也一并关闭），改用桌面端边缘悬停或双击打开操作栏唤出';

	/// zh-CN: '音量键翻页'
	String get volumeKeyPageTurn => '音量键翻页';

	/// zh-CN: '启用音量键翻页'
	String get enableVolumeKeyPageTurn => '启用音量键翻页';

	/// zh-CN: '开启后可用音量键上下翻页/滑动'
	String get volumeKeyPageTurnSubtitle => '开启后可用音量键上下翻页/滑动';

	/// zh-CN: '% 屏高'
	String get screenHeightPercent => '% 屏高';

	/// zh-CN: 'ms'
	String get milliseconds => 'ms';

	/// zh-CN: '%'
	String get percent => '%';

	/// zh-CN: 'px'
	String get pixels => 'px';

	/// zh-CN: '手势与悬停'
	String get gesture => '手势与悬停';

	/// zh-CN: '信息条'
	String get infoBar => '信息条';

	/// zh-CN: '阅读'
	String get tabRead => '阅读';

	/// zh-CN: '手势'
	String get tabGesture => '手势';

	/// zh-CN: '界面'
	String get tabScreen => '界面';

	/// zh-CN: '画面'
	String get tabPicture => '画面';

	/// zh-CN: '翻译'
	String get tabTranslate => '翻译';

	/// zh-CN: '上下栏与边距'
	String get chromeSection => '上下栏与边距';

	/// zh-CN: '画面处理'
	String get tuningSection => '画面处理';

	/// zh-CN: '自动裁边'
	String get autoTrimMargins => '自动裁边';

	/// zh-CN: '检测每页内容区并放大显示，不修改原图'
	String get autoTrimMarginsSubtitle => '检测每页内容区并放大显示，不修改原图';

	/// zh-CN: '暂停自动阅读'
	String get pauseAutoRead => '暂停自动阅读';

	/// zh-CN: '继续自动阅读'
	String get resumeAutoRead => '继续自动阅读';

	/// zh-CN: '$error 加载失败，点击重试'
	String imageLoadFailedRetry({required Object error}) => '${error}\n加载失败，点击重试';

	/// zh-CN: '图片已保存至: $path'
	String imageSavedTo({required Object path}) => '图片已保存至: ${path}';

	/// zh-CN: '图片已保存到相册！'
	String get imageSavedToAlbum => '图片已保存到相册！';

	/// zh-CN: '图片保存失败！'
	String get imageSaveFailed => '图片保存失败！';

	/// zh-CN: '保存失败: 请在系统设置中授予相册访问权限'
	String get saveImagePermissionDenied => '保存失败: 请在系统设置中授予相册访问权限';

	/// zh-CN: '保存失败: $error'
	String imageSaveFailedWithError({required Object error}) => '保存失败: ${error}';

	/// zh-CN: '松手执行 · 中心或 Esc 取消'
	String get radialMenuHint => '松手执行 · 中心或 Esc 取消';

	/// zh-CN: '移动以选择'
	String get radialMenuHintMove => '移动以选择';

	/// zh-CN: '松手执行'
	String get radialMenuHintRelease => '松手执行';

	/// zh-CN: '松手切换轮盘'
	String get radialMenuHintSwitch => '松手切换轮盘';

	/// zh-CN: '从左到右'
	String get singlePageLtr => '从左到右';

	/// zh-CN: '从右到左'
	String get singlePageRtl => '从右到左';
}

// Path: plugin
class Translations$plugin$zh_CN {
	Translations$plugin$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: 'getInfoJson 格式错误'
	String get getInfoJsonBadFormat => 'getInfoJson 格式错误';

	/// zh-CN: 'getInfo 返回格式错误'
	String get getInfoBadFormat => 'getInfo 返回格式错误';

	/// zh-CN: '插件返回格式错误'
	String get badResponseFormat => '插件返回格式错误';

	/// zh-CN: '高级能力加载中...'
	String get advancedCapabilityLoading => '高级能力加载中...';

	/// zh-CN: '插件商店'
	String get store => '插件商店';

	/// zh-CN: '搜索插件名称或作者...'
	String get searchHint => '搜索插件名称或作者...';

	/// zh-CN: '本地安装'
	String get localInstall => '本地安装';

	/// zh-CN: '网络安装'
	String get networkInstall => '网络安装';

	/// zh-CN: '云端组件'
	String get cloudComponents => '云端组件';

	/// zh-CN: '该来源当前不可用，请先在 设置 → 内容与网络 中开启「完整来源列表」'
	String get restrictedSourceBlocked => '该来源当前不可用，请先在 设置 → 内容与网络 中开启「完整来源列表」';

	/// zh-CN: '已隐藏 $count 个来源'
	String restrictedSourcesHidden({required Object count}) => '已隐藏 ${count} 个来源';

	/// zh-CN: '请在网页中完成登录，宿主会自动同步 Cookie'
	String get loginSuccess => '请在网页中完成登录，宿主会自动同步 Cookie';

	/// zh-CN: '当前平台不支持外部 Chromium 自动登录回退'
	String get chromiumFallbackUnsupported => '当前平台不支持外部 Chromium 自动登录回退';

	/// zh-CN: '内置 WebView 登录受限，正在切换外部浏览器...'
	String get switchingToExternalBrowser => '内置 WebView 登录受限，正在切换外部浏览器...';

	/// zh-CN: '未检测到 Chromium 浏览器，请先安装 Chrome'
	String get chromiumNotFound => '未检测到 Chromium 浏览器，请先安装 Chrome';

	/// zh-CN: '已切换到 $browser，登录完成后会自动同步 Cookie'
	String browserSwitched({required Object browser}) => '已切换到 ${browser}，登录完成后会自动同步 Cookie';

	/// zh-CN: '无效链接: $url'
	String invalidLink({required Object url}) => '无效链接: ${url}';

	/// zh-CN: '无法打开链接: $url'
	String cannotOpenLink({required Object url}) => '无法打开链接: ${url}';

	/// zh-CN: '读取本地插件失败: $error'
	String readLocalPluginFailed({required Object error}) => '读取本地插件失败: ${error}';

	/// zh-CN: '不支持的本地文件类型，仅支持 .js / .cjs / .br 文件：$fileName'
	String unsupportedLocalFileType({required Object fileName}) => '不支持的本地文件类型，仅支持 .js / .cjs / .br 文件：${fileName}';

	/// zh-CN: '从网络添加插件'
	String get addFromNetwork => '从网络添加插件';

	/// zh-CN: 'URL 不能为空'
	String get urlCannotBeEmpty => 'URL 不能为空';

	/// zh-CN: '开始安装'
	String get startInstall => '开始安装';

	/// zh-CN: '$name 设置'
	String pluginSettingsTitle({required Object name}) => '${name} 设置';

	/// zh-CN: '插件调试配置已更新'
	String get debugConfigUpdated => '插件调试配置已更新';

	/// zh-CN: '删除插件'
	String get deletePlugin => '删除插件';

	/// zh-CN: '确认删除该插件？此操作将删除插件及其相关数据。'
	String get confirmDeletePlugin => '确认删除该插件？此操作将删除插件及其相关数据。';

	/// zh-CN: '删除失败: $error'
	String deleteFailed({required Object error}) => '删除失败: ${error}';

	/// zh-CN: '插件已删除'
	String get pluginDeleted => '插件已删除';

	/// zh-CN: '执行失败: $error'
	String executeFailed({required Object error}) => '执行失败: ${error}';

	/// zh-CN: '彻底删除插件，并删除相关数据'
	String get deletePluginSubtitle => '彻底删除插件，并删除相关数据';

	/// zh-CN: '调试模式'
	String get debugMode => '调试模式';

	/// zh-CN: '调试地址'
	String get debugAddress => '调试地址';

	/// zh-CN: '账号登录'
	String get accountLogin => '账号登录';

	/// zh-CN: '前往登录'
	String get accountLoginSubtitle => '前往登录';

	/// zh-CN: '插件详情'
	String get pluginDetail => '插件详情';

	/// zh-CN: '查看插件介绍与主页'
	String get pluginDetailSubtitle => '查看插件介绍与主页';

	/// zh-CN: '插件设置'
	String get pluginSettings => '插件设置';

	/// zh-CN: '暂无用户信息'
	String get noUserInfo => '暂无用户信息';

	/// zh-CN: '操作'
	String get operations => '操作';

	/// zh-CN: '插件管理'
	String get management => '插件管理';

	/// zh-CN: '已安装'
	String get installed => '已安装';

	/// zh-CN: '未安装'
	String get notInstalled => '未安装';

	/// zh-CN: '更新'
	String get update => '更新';

	/// zh-CN: '安装'
	String get install => '安装';

	/// zh-CN: '卸载'
	String get uninstall => '卸载';

	/// zh-CN: '作者'
	String get author => '作者';

	/// zh-CN: '版本'
	String get version => '版本';

	/// zh-CN: '描述'
	String get description => '描述';

	/// zh-CN: '仓库'
	String get repo => '仓库';

	/// zh-CN: '主页'
	String get homepage => '主页';

	/// zh-CN: 'GitHub 仓库'
	String get githubRepo => 'GitHub 仓库';

	/// zh-CN: '下载'
	String get download => '下载';

	/// zh-CN: '下载更新'
	String get downloadUpdate => '下载更新';

	/// zh-CN: '暂无云端组件'
	String get noCloudPlugins => '暂无云端组件';

	/// zh-CN: '没有匹配的插件'
	String get noMatchingPlugins => '没有匹配的插件';

	/// zh-CN: '请输入插件脚本 URL'
	String get networkInstallHint => '请输入插件脚本 URL';

	/// zh-CN: '云端组件列表加载失败: $error'
	String cloudPluginsLoadFailed({required Object error}) => '云端组件列表加载失败: ${error}';

	/// zh-CN: '正在下载并安装 $name...'
	String installingFromCloud({required Object name}) => '正在下载并安装 ${name}...';

	/// zh-CN: '正在安装本地插件...'
	String get installingFromLocal => '正在安装本地插件...';

	/// zh-CN: '正在下载网络插件...'
	String get installingFromNetwork => '正在下载网络插件...';

	/// zh-CN: '云端下载失败: $error'
	String cloudDownloadFailed({required Object error}) => '云端下载失败: ${error}';

	/// zh-CN: '网络下载插件失败: $error'
	String networkDownloadFailed({required Object error}) => '网络下载插件失败: ${error}';

	/// zh-CN: '远程插件文件不存在（404），可能已被删除或版本已更新，请稍后重试或检查更新地址'
	String get remoteAssetNotFound => '远程插件文件不存在（404），可能已被删除或版本已更新，请稍后重试或检查更新地址';

	/// zh-CN: 'GitHub 访问受限（疑似 IP 被限流），请稍后重试或切换网络；若插件确实不存在也会显示 404'
	String get githubRateLimited => 'GitHub 访问受限（疑似 IP 被限流），请稍后重试或切换网络；若插件确实不存在也会显示 404';

	/// zh-CN: '远端返回了网页而非插件文件，通常是远程文件不存在或链接已失效，请检查插件仓库的更新地址'
	String get remoteReturnedWebPage => '远端返回了网页而非插件文件，通常是远程文件不存在或链接已失效，请检查插件仓库的更新地址';

	/// zh-CN: '远端返回内容为空，请稍后重试或检查更新地址'
	String get remoteEmptyResponse => '远端返回内容为空，请稍后重试或检查更新地址';

	/// zh-CN: '远端拒绝访问（HTTP $status），请检查网络或稍后重试'
	String remoteAccessDenied({required Object status}) => '远端拒绝访问（HTTP ${status}），请检查网络或稍后重试';

	/// zh-CN: '远端服务器异常（HTTP $status），请稍后重试'
	String remoteServerError({required Object status}) => '远端服务器异常（HTTP ${status}），请稍后重试';

	/// zh-CN: '远端请求失败（HTTP $status），请稍后重试'
	String remoteHttpError({required Object status}) => '远端请求失败（HTTP ${status}），请稍后重试';

	/// zh-CN: '下载到的文件不是有效的插件脚本（疑似网页或错误页），请检查远程文件是否存在后再试'
	String get downloadedScriptInvalid => '下载到的文件不是有效的插件脚本（疑似网页或错误页），请检查远程文件是否存在后再试';

	/// zh-CN: '下载到的插件文件已损坏或解压失败，请稍后重试'
	String get downloadedScriptCorrupted => '下载到的插件文件已损坏或解压失败，请稍后重试';

	/// zh-CN: '网络不稳定，下载失败，请检查网络后重试'
	String get networkUnstableRetry => '网络不稳定，下载失败，请检查网络后重试';

	/// zh-CN: '云端 $version'
	String cloudVersion({required Object version}) => '云端 ${version}';

	/// zh-CN: '本地 $version'
	String localVersion({required Object version}) => '本地 ${version}';

	/// zh-CN: '$name 登录'
	String loginTitle({required Object name}) => '${name} 登录';

	/// zh-CN: '登录 Cookie 已同步'
	String get cookieSynced => '登录 Cookie 已同步';

	/// zh-CN: '执行成功'
	String get executeSuccess => '执行成功';

	/// zh-CN: '用户信息'
	String get userInfoTitle => '用户信息';

	/// zh-CN: '用户信息加载失败'
	String get userInfoLoadFailed => '用户信息加载失败';

	/// zh-CN: '未命名操作'
	String get unnamedAction => '未命名操作';

	/// zh-CN: '插件设置加载中...'
	String get pluginSettingsLoading => '插件设置加载中...';

	/// zh-CN: '插件设置加载失败'
	String get pluginSettingsLoadFailed => '插件设置加载失败';

	/// zh-CN: '动作不可执行: 缺少 fnPath'
	String get actionNotExecutable => '动作不可执行: 缺少 fnPath';

	/// zh-CN: '已保存'
	String get saved => '已保存';

	/// zh-CN: '关闭'
	String get close => '关闭';

	/// zh-CN: '同步'
	String get sync => '同步';

	/// zh-CN: '通过 npm / updateUrl 检查并更新插件'
	String get syncSubtitle => '通过 npm / updateUrl 检查并更新插件';

	/// zh-CN: '正在同步插件...'
	String get syncing => '正在同步插件...';

	/// zh-CN: '同步成功'
	String get syncSuccess => '同步成功';

	/// zh-CN: '同步失败: $error'
	String syncFailed({required Object error}) => '同步失败: ${error}';

	/// zh-CN: '通过网络 URL 或本地文件手动重装当前插件'
	String get updateSubtitle => '通过网络 URL 或本地文件手动重装当前插件';

	/// zh-CN: '从网络安装'
	String get updateFromNetwork => '从网络安装';

	/// zh-CN: '从本地安装'
	String get updateFromLocal => '从本地安装';

	/// zh-CN: '选择安装方式'
	String get updateChooseSource => '选择安装方式';

	/// zh-CN: '正在更新插件...'
	String get updating => '正在更新插件...';

	/// zh-CN: '更新成功'
	String get updateSuccess => '更新成功';

	/// zh-CN: '更新失败: $error'
	String updateFailed({required Object error}) => '更新失败: ${error}';

	/// zh-CN: '插件 id 不一致，无法安装'
	String get uuidMismatch => '插件 id 不一致，无法安装';

	/// zh-CN: '当前版本 $version'
	String currentVersion({required Object version}) => '当前版本 ${version}';

	/// zh-CN: '已是最新版本'
	String get alreadyLatest => '已是最新版本';
}

// Path: gestureLock
class Translations$gestureLock$zh_CN {
	Translations$gestureLock$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '手势解锁'
	String get gestureTitle => '手势解锁';

	/// zh-CN: '请绘制手势密码'
	String get gestureHint => '请绘制手势密码';

	/// zh-CN: '输入 PIN'
	String get pinTitle => '输入 PIN';

	/// zh-CN: '请输入重置 PIN'
	String get pinHint => '请输入重置 PIN';

	/// zh-CN: '至少连接 4 个点'
	String get atLeast4Points => '至少连接 4 个点';

	/// zh-CN: '请再次绘制以确认'
	String get confirmGesture => '请再次绘制以确认';

	/// zh-CN: '两次绘制不一致'
	String get gestureNotMatch => '两次绘制不一致';

	/// zh-CN: '设置成功'
	String get setSuccess => '设置成功';

	/// zh-CN: '忘记密码'
	String get forgotPassword => '忘记密码';

	/// zh-CN: '手势密码不正确，请重试'
	String get incorrectPassword => '手势密码不正确，请重试';

	/// zh-CN: '重置 PIN'
	String get resetPin => '重置 PIN';

	/// zh-CN: 'PIN'
	String get pin => 'PIN';

	/// zh-CN: 'PIN 可用于重置手势密码，遗忘手势密码与 PIN 后将无法进入软件，请妥善保管 Pin'
	String get pinDescription => 'PIN 可用于重置手势密码，遗忘手势密码与 PIN 后将无法进入软件，请妥善保管 Pin';

	/// zh-CN: 'PIN 需至少 4 位数字'
	String get pinMinLength => 'PIN 需至少 4 位数字';

	/// zh-CN: '两次输入的 PIN 不一致'
	String get pinNotMatch => '两次输入的 PIN 不一致';

	/// zh-CN: 'PIN 不正确，请重试'
	String get pinIncorrect => 'PIN 不正确，请重试';

	/// zh-CN: '应用已锁定'
	String get appLocked => '应用已锁定';

	/// zh-CN: '请先完成手势验证'
	String get verifyToUnlock => '请先完成手势验证';

	/// zh-CN: '重置手势密码'
	String get resetGesturePassword => '重置手势密码';

	/// zh-CN: '请输入设置时保存的重置 PIN'
	String get resetPinHint => '请输入设置时保存的重置 PIN';

	/// zh-CN: '密码已清空，请重新设置'
	String get passwordCleared => '密码已清空，请重新设置';

	/// zh-CN: '请连接至少 4 个点'
	String get setupHintFirst => '请连接至少 4 个点';

	/// zh-CN: '请再次绘制相同手势'
	String get setupHintConfirm => '请再次绘制相同手势';

	/// zh-CN: '至少连接 4 个点'
	String get setupErrorMinPoints => '至少连接 4 个点';

	/// zh-CN: '两次手势不一致，请重新设置'
	String get setupErrorMismatch => '两次手势不一致，请重新设置';

	/// zh-CN: '至少 4 位数字'
	String get pinHintMinDigits => '至少 4 位数字';
}

// Path: appBootstrap
class Translations$appBootstrap$zh_CN {
	Translations$appBootstrap$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '初始化中....'
	String get initializing => '初始化中....';

	/// zh-CN: '请验证手势密码'
	String get verifyGesture => '请验证手势密码';

	/// zh-CN: 'PIN 验证未通过'
	String get pinVerifyFailed => 'PIN 验证未通过';

	/// zh-CN: '已取消解锁'
	String get unlockCancelled => '已取消解锁';

	/// zh-CN: '验证成功，正在进入应用'
	String get enteringApp => '验证成功，正在进入应用';
}

// Path: comments
class Translations$comments$zh_CN {
	Translations$comments$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '重试'
	String get retry => '重试';

	/// zh-CN: '暂无评论'
	String get noComments => '暂无评论';

	/// zh-CN: '加载更多'
	String get loadMore => '加载更多';

	/// zh-CN: '收起回复'
	String get collapseReplies => '收起回复';

	/// zh-CN: '$count 条回复'
	String replyCount({required Object count}) => '${count} 条回复';

	/// zh-CN: '暂无子评论'
	String get noReplies => '暂无子评论';

	/// zh-CN: '加载更多回复'
	String get loadMoreReplies => '加载更多回复';

	/// zh-CN: '发表评论'
	String get postComment => '发表评论';

	/// zh-CN: '输入评论内容'
	String get postCommentHint => '输入评论内容';

	/// zh-CN: '回复评论'
	String get postReply => '回复评论';

	/// zh-CN: '输入回复内容'
	String get postReplyHint => '输入回复内容';

	/// zh-CN: '取消'
	String get cancel => '取消';

	/// zh-CN: '确认'
	String get confirm => '确认';

	/// zh-CN: '发布成功'
	String get postSuccess => '发布成功';

	/// zh-CN: '发布失败: $error'
	String postFailed({required Object error}) => '发布失败: ${error}';

	/// zh-CN: '匿名用户'
	String get anonymous => '匿名用户';
}

// Path: cache
class Translations$cache$zh_CN {
	Translations$cache$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '缓存设置'
	String get title => '缓存设置';

	/// zh-CN: '当前缓存'
	String get currentCache => '当前缓存';

	/// zh-CN: '清理缓存'
	String get clearCache => '清理缓存';

	/// zh-CN: '确定要清理所有缓存文件吗？此操作不可撤销。'
	String get clearCacheConfirm => '确定要清理所有缓存文件吗？此操作不可撤销。';

	/// zh-CN: '缓存已清理'
	String get cleared => '缓存已清理';

	/// zh-CN: '清理失败'
	String get clearFailed => '清理失败';

	/// zh-CN: '缓存大小'
	String get cacheSize => '缓存大小';

	/// zh-CN: '重新计算'
	String get recalculate => '重新计算';

	/// zh-CN: '手动清理缓存'
	String get manualClear => '手动清理缓存';

	/// zh-CN: '立即删除所有缓存文件'
	String get manualClearSubtitle => '立即删除所有缓存文件';

	/// zh-CN: '清理'
	String get clear => '清理';

	/// zh-CN: '缓存限制'
	String get cacheLimit => '缓存限制';

	/// zh-CN: '缓存上限'
	String get sizeLimit => '缓存上限';

	/// zh-CN: '达到上限后将自动清理旧缓存'
	String get sizeLimitSubtitle => '达到上限后将自动清理旧缓存';

	/// zh-CN: '自动清理缓存'
	String get autoClean => '自动清理缓存';

	/// zh-CN: '关闭后将不再自动清理任何缓存'
	String get autoCleanSubtitle => '关闭后将不再自动清理任何缓存';

	/// zh-CN: '计算中...'
	String get calculating => '计算中...';

	/// zh-CN: '计算失败'
	String get calculateFailed => '计算失败';
}

// Path: dataBackup
class Translations$dataBackup$zh_CN {
	Translations$dataBackup$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '本地导入/导出'
	String get title => '本地导入/导出';

	/// zh-CN: '导出'
	String get exportSection => '导出';

	/// zh-CN: '导入'
	String get importSection => '导入';

	/// zh-CN: '包含下载的漫画'
	String get includeDownloads => '包含下载的漫画';

	/// zh-CN: '导出时一并打包已下载的漫画文件'
	String get includeDownloadsSubtitle => '导出时一并打包已下载的漫画文件';

	/// zh-CN: '导出数据'
	String get exportData => '导出数据';

	/// zh-CN: '将设置与数据打包为 zip'
	String get exportDataSubtitle => '将设置与数据打包为 zip';

	/// zh-CN: '导入数据'
	String get importData => '导入数据';

	/// zh-CN: '从 zip 文件恢复数据'
	String get importDataSubtitle => '从 zip 文件恢复数据';

	/// zh-CN: '选择导出目录失败'
	String get selectExportDirFailed => '选择导出目录失败';

	/// zh-CN: '正在导出，请耐心等待…'
	String get exporting => '正在导出，请耐心等待…';

	/// zh-CN: '导出成功'
	String get exportSuccess => '导出成功';

	/// zh-CN: '已保存到：$path'
	String savedTo({required Object path}) => '已保存到：${path}';

	/// zh-CN: '请在弹出的分享面板中选择「存储到文件」以保存备份。'
	String get exportShareHint => '请在弹出的分享面板中选择「存储到文件」以保存备份。';

	/// zh-CN: '导出失败'
	String get exportFailed => '导出失败';

	/// zh-CN: '正在处理备份文件…'
	String get processingBackup => '正在处理备份文件…';

	/// zh-CN: '选择备份文件失败'
	String get selectBackupFailed => '选择备份文件失败';

	/// zh-CN: '正在读取备份信息…'
	String get readingBackup => '正在读取备份信息…';

	/// zh-CN: '读取备份失败'
	String get readBackupFailed => '读取备份失败';

	/// zh-CN: '正在导入，请稍后…'
	String get importing => '正在导入，请稍后…';

	/// zh-CN: '导入失败'
	String get importFailed => '导入失败';

	/// zh-CN: '导入数据'
	String get importTitle => '导入数据';

	/// zh-CN: '导入将覆盖备份中的设置与应用数据；本机路径、代理、应用锁及同步配置会保留。是否继续？'
	String get importConfirm => '导入将覆盖备份中的设置与应用数据；本机路径、代理、应用锁及同步配置会保留。是否继续？';

	/// zh-CN: '该备份包含下载的漫画文件，导入时会先删除本机现有的下载文件。'
	String get includesDownloadsWarning => '该备份包含下载的漫画文件，导入时会先删除本机现有的下载文件。';

	/// zh-CN: '版本不一致，数据导入可能会出问题，是否继续？'
	String get versionMismatch => '版本不一致，数据导入可能会出问题，是否继续？';

	/// zh-CN: '导出数据版本：$version'
	String exportedVersion({required Object version}) => '导出数据版本：${version}';

	/// zh-CN: '当前应用版本：$version'
	String currentVersion({required Object version}) => '当前应用版本：${version}';

	/// zh-CN: '继续'
	String get kContinue => '继续';

	/// zh-CN: '导入成功'
	String get importSuccess => '导入成功';

	/// zh-CN: '数据导入成功，请重启应用以生效。'
	String get restartPrompt => '数据导入成功，请重启应用以生效。';
}

// Path: webdavSync
class Translations$webdavSync$zh_CN {
	Translations$webdavSync$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '云同步配置'
	String get title => '云同步配置';

	/// zh-CN: '$service 同步配置'
	String serviceTitle({required Object service}) => '${service} 同步配置';

	/// zh-CN: '请先在设置里选择同步服务，再回到这里填写配置。'
	String get noneTip => '请先在设置里选择同步服务，再回到这里填写配置。';

	/// zh-CN: '删除配置'
	String get deleteConfig => '删除配置';

	/// zh-CN: '测试连接并保存'
	String get testAndSave => '测试连接并保存';

	/// zh-CN: '常见问题'
	String get faq => '常见问题';

	/// zh-CN: 'WebDAV 地址'
	String get webdavHost => 'WebDAV 地址';

	/// zh-CN: '账号'
	String get username => '账号';

	/// zh-CN: '密码'
	String get password => '密码';

	/// zh-CN: '服务地址(Endpoint)'
	String get s3Endpoint => '服务地址(Endpoint)';

	/// zh-CN: '如: s3.amazonaws.com'
	String get s3EndpointHint => '如: s3.amazonaws.com';

	/// zh-CN: 'Access Key'
	String get s3AccessKey => 'Access Key';

	/// zh-CN: 'Secret Key'
	String get s3SecretKey => 'Secret Key';

	/// zh-CN: '存储桶(Bucket)的名字'
	String get s3Bucket => '存储桶(Bucket)的名字';

	/// zh-CN: '区域(Region)（可选）'
	String get s3Region => '区域(Region)（可选）';

	/// zh-CN: '端口（可选）'
	String get s3Port => '端口（可选）';

	/// zh-CN: '使用 HTTPS/SSL'
	String get useSsl => '使用 HTTPS/SSL';

	/// zh-CN: '路径风格 (Path-Style)'
	String get pathStyle => '路径风格 (Path-Style)';

	/// zh-CN: '自建 MinIO 通常需要开启此选项'
	String get pathStyleSubtitle => '自建 MinIO 通常需要开启此选项';

	/// zh-CN: '正在连接 WebDAV 服务器...'
	String get connectingWebdav => '正在连接 WebDAV 服务器...';

	/// zh-CN: 'WebDAV连接成功，已保存设置。'
	String get webdavConnected => 'WebDAV连接成功，已保存设置。';

	/// zh-CN: '连接失败，请检查网络连接或WebDAV地址是否正确。 $error'
	String webdavConnectFailed({required Object error}) => '连接失败，请检查网络连接或WebDAV地址是否正确。\n${error}';

	/// zh-CN: '端口格式不正确，请输入 0-65535 的数字。'
	String get invalidPort => '端口格式不正确，请输入 0-65535 的数字。';

	/// zh-CN: '正在连接 S3 服务...'
	String get connectingS3 => '正在连接 S3 服务...';

	/// zh-CN: 'S3 连接成功，已保存设置。'
	String get s3Connected => 'S3 连接成功，已保存设置。';

	/// zh-CN: '连接失败，请检查 S3 配置是否正确。 $error'
	String s3ConnectFailed({required Object error}) => '连接失败，请检查 S3 配置是否正确。\n${error}';

	/// zh-CN: '关闭'
	String get close => '关闭';

	/// zh-CN: '成功'
	String get success => '成功';

	/// zh-CN: '错误'
	String get error => '错误';

	/// zh-CN: '### 可以同步哪些内容？ - 目前同步哔咔历史记录、禁漫收藏和禁漫历史。 ### WebDAV 如何配置？ - 填写 WebDAV 地址、账号、密码，点击测试连接并保存即可。 ### S3 如何配置？ - Endpoint 示例：`s3.amazonaws.com`、`s3.filebase.com`、`play.min.io`。 - 如果是自建 MinIO，可填写自定义端口，必要时关闭 SSL。 ### 自动同步间隔是多久？ - 每 5 分钟自动同步一次。 ### 如何手动触发一次同步？ - 在同步配置页测试连接并保存后会触发一次同步。 - 或在设置里切换一次自动同步开关。'
	String get faqMarkdown => '### 可以同步哪些内容？\n- 目前同步哔咔历史记录、禁漫收藏和禁漫历史。\n\n### WebDAV 如何配置？\n- 填写 WebDAV 地址、账号、密码，点击测试连接并保存即可。\n\n### S3 如何配置？\n- Endpoint 示例：`s3.amazonaws.com`、`s3.filebase.com`、`play.min.io`。\n- 如果是自建 MinIO，可填写自定义端口，必要时关闭 SSL。\n\n### 自动同步间隔是多久？\n- 每 5 分钟自动同步一次。\n\n### 如何手动触发一次同步？\n- 在同步配置页测试连接并保存后会触发一次同步。\n- 或在设置里切换一次自动同步开关。';
}

// Path: ocr
class Translations$ocr$zh_CN {
	Translations$ocr$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '漫画翻译（成品页）'
	String get title => '漫画翻译（成品页）';

	/// zh-CN: '翻译端点'
	String get endpointSection => '翻译端点';

	/// zh-CN: '接口地址'
	String get baseUrl => '接口地址';

	/// zh-CN: 'https://api.deepseek.com/v1 或 http://127.0.0.1:11434/v1'
	String get baseUrlHint => 'https://api.deepseek.com/v1 或 http://127.0.0.1:11434/v1';

	/// zh-CN: '未配置'
	String get baseUrlNone => '未配置';

	/// zh-CN: '模型名'
	String get model => '模型名';

	/// zh-CN: '例如 deepseek-chat、qwen2.5:14b'
	String get modelHint => '例如 deepseek-chat、qwen2.5:14b';

	/// zh-CN: 'API Key'
	String get apiKey => 'API Key';

	/// zh-CN: '只存本机设置，不进导出文件；本机 Ollama 可留空'
	String get apiKeySubtitle => '只存本机设置，不进导出文件；本机 Ollama 可留空';

	/// zh-CN: '目标语言'
	String get targetLanguage => '目标语言';

	/// zh-CN: '术语表'
	String get glossary => '术语表';

	/// zh-CN: '每行一条「原文=译文」；改动会让已生成的成品页重译'
	String get glossarySubtitle => '每行一条「原文=译文」；改动会让已生成的成品页重译';

	/// zh-CN: 'トカゲ=石龙子'
	String get glossaryHint => 'トカゲ=石龙子';

	/// zh-CN: '已保存'
	String get saved => '已保存';

	/// zh-CN: '还缺接口地址或模型名'
	String get notConfigured => '还缺接口地址或模型名';

	/// zh-CN: '推理后端'
	String get epSection => '推理后端';

	/// zh-CN: '推理后端'
	String get ep => '推理后端';

	/// zh-CN: '实测这两个模型在 CoreML 上更慢，默认走 CPU'
	String get epSubtitle => '实测这两个模型在 CoreML 上更慢，默认走 CPU';

	/// zh-CN: '本机各段：检测 $detect · 识别 $recognize · 擦字 $inpaint'
	String epPlan({required Object detect, required Object recognize, required Object inpaint}) => '本机各段：检测 ${detect} · 识别 ${recognize} · 擦字 ${inpaint}';

	/// zh-CN: '本平台构建里没有 $ep —— 选了会在开始分析时报错，不会静默退回 CPU'
	String epPlanUnsupported({required Object ep}) => '本平台构建里没有 ${ep} —— 选了会在开始分析时报错，不会静默退回 CPU';

	/// zh-CN: '成品页显示'
	String get displaySection => '成品页显示';

	/// zh-CN: '显示方式'
	String get displayChoice => '显示方式';

	/// zh-CN: '换档只影响之后按「译」的页；已经生成的那一页要重按一次，才会按新档重做（一页十几秒）。'
	String get displayChoiceSubtitle => '换档只影响之后按「译」的页；已经生成的那一页要重按一次，才会按新档重做（一页十几秒）。';

	/// zh-CN: '烘焙成图（会压掉这一页的超分）'
	String get displayBaked => '烘焙成图（会压掉这一页的超分）';

	/// zh-CN: '叠层显示（中文盖在擦字底图上）'
	String get displayOverlay => '叠层显示（中文盖在擦字底图上）';

	/// zh-CN: '叠层只把中文盖在底图上，不改底图像素；但这一页要用擦干净的字底当底图，所以它会替自己占一次增强图轨 —— 这一页的超分为它让路。「每个气泡采到自己的平色就不必擦」那条捷径今天没走过：8 页真页 121 框可填 0 框（数字见 ADR-0018 §4）。'
	String get displayOverlayHint => '叠层只把中文盖在底图上，不改底图像素；但这一页要用擦干净的字底当底图，所以它会替自己占一次增强图轨 —— 这一页的超分为它让路。「每个气泡采到自己的平色就不必擦」那条捷径今天没走过：8 页真页 121 框可填 0 框（数字见 ADR-0018 §4）。';

	/// zh-CN: '模型权重'
	String get modelSection => '模型权重';

	/// zh-CN: '权重已就绪（$count 个文件）'
	String weightsReady({required Object count}) => '权重已就绪（${count} 个文件）';

	/// zh-CN: '缺少：$missing'
	String weightsMissing({required Object missing}) => '缺少：${missing}';

	/// zh-CN: '下载权重'
	String get download => '下载权重';

	/// zh-CN: '下载中'
	String get downloading => '下载中';

	/// zh-CN: '权重下载完成'
	String get downloadDone => '权重下载完成';

	/// zh-CN: '权重下载失败'
	String get downloadFailed => '权重下载失败';

	/// zh-CN: '成品页缓存'
	String get cacheSection => '成品页缓存';

	/// zh-CN: '已生成 $count 张成品页'
	String cacheCount({required Object count}) => '已生成 ${count} 张成品页';

	/// zh-CN: '还没有生成过成品页'
	String get cacheEmpty => '还没有生成过成品页';

	/// zh-CN: '清空成品页缓存'
	String get clearCache => '清空成品页缓存';

	/// zh-CN: '换模型或换字体后用；不会动原图'
	String get clearCacheSubtitle => '换模型或换字体后用；不会动原图';

	/// zh-CN: '已清空成品页缓存'
	String get cacheCleared => '已清空成品页缓存';

	/// zh-CN: '诊断'
	String get logSection => '诊断';

	/// zh-CN: '翻译日志'
	String get viewLog => '翻译日志';

	/// zh-CN: '每一页的六道关各记一行：端点、推理（含各段实际生效 EP）、翻译请求、回填排版、落盘、注入核对。'
	String get logHint => '每一页的六道关各记一行：端点、推理（含各段实际生效 EP）、翻译请求、回填排版、落盘、注入核对。';

	/// zh-CN: '漫画翻译日志'
	String get logDialogTitle => '漫画翻译日志';

	/// zh-CN: '尚无翻译日志。在阅读器里按「译」，或去「设置 → 调试 → OCR 成品页冒烟」跑一遍，这里就会有记录。'
	String get logEmpty => '尚无翻译日志。在阅读器里按「译」，或去「设置 → 调试 → OCR 成品页冒烟」跑一遍，这里就会有记录。';

	/// zh-CN: '复制日志'
	String get copyLog => '复制日志';

	/// zh-CN: '翻译日志已复制'
	String get logCopied => '翻译日志已复制';

	/// zh-CN: '打开日志位置'
	String get openLogLocation => '打开日志位置';

	/// zh-CN: '在阅读器工具条上按「译」，只切换当前这一页'
	String get readerHint => '在阅读器工具条上按「译」，只切换当前这一页';

	/// zh-CN: '译'
	String get chipOff => '译';

	/// zh-CN: '译文页'
	String get chipOn => '译文页';

	/// zh-CN: '译文页 · 叠层'
	String get chipOnOverlay => '译文页 · 叠层';

	/// zh-CN: '生成中'
	String get building => '生成中';

	/// zh-CN: '译文失败'
	String get failedShort => '译文失败';

	/// zh-CN: '这一页正在生成译文，稍等'
	String get busyToast => '这一页正在生成译文，稍等';

	/// zh-CN: '权重还没下全，去设置里下载'
	String get needWeights => '权重还没下全，去设置里下载';

	/// zh-CN: '译文引擎'
	String get engine => '译文引擎';

	/// zh-CN: '选「API 端点」按 token 计费/要网络；选「Apple 系统翻译」走端侧，免费离线'
	String get engineSubtitle => '选「API 端点」按 token 计费/要网络；选「Apple 系统翻译」走端侧，免费离线';

	/// zh-CN: '翻到新的一页自动译'
	String get autoTranslatePage => '翻到新的一页自动译';

	/// zh-CN: '一张成品页要十几秒，开着等于往后每页都得等。关掉只管之后的页，已经生成的译文页留着。'
	String get autoTranslatePageSubtitle => '一张成品页要十几秒，开着等于往后每页都得等。关掉只管之后的页，已经生成的译文页留着。';

	/// zh-CN: '语言包已装，直接生效（整页 15 块实测约 300 ms）'
	String get engineAppleInstalled => '语言包已装，直接生效（整页 15 块实测约 300 ms）';

	/// zh-CN: '还没装 ja → 目标语言 的翻译语言包。系统里没有 app 能替你下载的 API —— 请到「系统设置 › 通用 › 语言与地区」里装好再回来'
	String get engineAppleMissing => '还没装 ja → 目标语言 的翻译语言包。系统里没有 app 能替你下载的 API —— 请到「系统设置 › 通用 › 语言与地区」里装好再回来';

	/// zh-CN: '系统不认识这个语言对，换目标语言或改用端点'
	String get engineAppleUnsupportedPair => '系统不认识这个语言对，换目标语言或改用端点';

	/// zh-CN: '这台机器上没有系统翻译这条路（仅 macOS 15+ / iOS 18+）'
	String get engineAppleUnavailable => '这台机器上没有系统翻译这条路（仅 macOS 15+ / iOS 18+）';

	/// zh-CN: '系统翻译没有术语表接口：这一档下术语表不生效，专名会按通用译法翻'
	String get glossaryIgnoredOnApple => '系统翻译没有术语表接口：这一档下术语表不生效，专名会按通用译法翻';

	/// zh-CN: '这一档要本机先起服务，例如：llama-server -m Hy-MT2-1.8B-Q4_K_M.gguf --device MTL0 -ngl 99 --port 8080 端点填 http://127.0.0.1:8080/v1，模型名与 --model 一致。术语表会走它原生的 Terminology 模式生效。 实测 1.8B 就够（约 158 ms/条、一页约 2.4 s）：术语表把 ヤモリ/危機契約 这类错逐条修对了，7B 并不更好且大 4 倍。macOS 上 --device 必须写 MTL0 —— 不写会静默走 CPU，实测慢 4.8 倍。'
	String get engineHunyuanHint => '这一档要本机先起服务，例如：llama-server -m Hy-MT2-1.8B-Q4_K_M.gguf --device MTL0 -ngl 99 --port 8080\n端点填 http://127.0.0.1:8080/v1，模型名与 --model 一致。术语表会走它原生的 Terminology 模式生效。\n实测 1.8B 就够（约 158 ms/条、一页约 2.4 s）：术语表把 ヤモリ/危機契約 这类错逐条修对了，7B 并不更好且大 4 倍。macOS 上 --device 必须写 MTL0 —— 不写会静默走 CPU，实测慢 4.8 倍。';
}

// Path: realSr
class Translations$realSr$zh_CN {
	Translations$realSr$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '尚无超分产物，已打开超分缓存目录：$dir'
	String openedUpscaleCache({required Object dir}) => '尚无超分产物，已打开超分缓存目录：${dir}';

	/// zh-CN: '已打开最近产物的所在位置：$output'
	String openedRecentLocation({required Object output}) => '已打开最近产物的所在位置：${output}';

	/// zh-CN: '打开文件夹失败：$error'
	String openFolderFailed({required Object error}) => '打开文件夹失败：${error}';

	/// zh-CN: '当前平台无法打开文件夹：$dir'
	String openFolderUnsupported({required Object dir}) => '当前平台无法打开文件夹：${dir}';

	/// zh-CN: 'Real-ESRGAN x4plus · 照片/CG'
	String get coremlModelPhoto => 'Real-ESRGAN x4plus · 照片/CG';

	/// zh-CN: 'mImage ONNX 推理失败：$error'
	String mimageInferenceFailed({required Object error}) => 'mImage ONNX 推理失败：${error}';

	/// zh-CN: '模型不可用：$engine，请先在超分设置中下载模型。'
	String modelUnavailableHint({required Object engine}) => '模型不可用：${engine}，请先在超分设置中下载模型。';

	/// zh-CN: '压缩包缺少 mImage ONNX 模型 $file'
	String archiveMissingOnnx({required Object file}) => '压缩包缺少 mImage ONNX 模型 ${file}';

	/// zh-CN: '压缩包内容不符合当前引擎要求: $missing'
	String archiveContentMismatch({required Object missing}) => '压缩包内容不符合当前引擎要求: ${missing}';

	/// zh-CN: '文件名与当前模型不匹配: 期望 $expected, 实际 $actual'
	String modelFileNameMismatch({required Object expected, required Object actual}) => '文件名与当前模型不匹配: 期望 ${expected}, 实际 ${actual}';

	/// zh-CN: '缺少 mImage ONNX 模型 $file，请在设置中下载'
	String missingOnnxDownload({required Object file}) => '缺少 mImage ONNX 模型 ${file}，请在设置中下载';

	/// zh-CN: 'JSON 格式无效: $error'
	String importJsonInvalid({required Object error}) => 'JSON 格式无效: ${error}';

	/// zh-CN: '复制日志'
	String get copyLog => '复制日志';

	/// zh-CN: '分块：内容块 $contentSize×$contentSize，模型输入 $blockSize×$blockSize（含 $shrink px 反射边距），由模型固定'
	String blockInfoDetail({required Object contentSize, required Object blockSize, required Object shrink}) => '分块：内容块 ${contentSize}×${contentSize}，模型输入 ${blockSize}×${blockSize}（含 ${shrink} px 反射边距），由模型固定';

	/// zh-CN: '删除 $name？需要时可以重新下载。'
	String deleteModelConfirmNamed({required Object name}) => '删除 ${name}？需要时可以重新下载。';

	/// zh-CN: '操作失败：$error'
	String actionFailedDetail({required Object error}) => '操作失败：${error}';

	/// zh-CN: '成功导入 $count 条条件'
	String importConditionSuccess({required Object count}) => '成功导入 ${count} 条条件';

	/// zh-CN: '尚无超分日志。启用超分后，推理和替换过程会记录在这里。'
	String get logEmptyText => '尚无超分日志。启用超分后，推理和替换过程会记录在这里。';

	/// zh-CN: '超分日志已复制'
	String get upscaleLogCopied => '超分日志已复制';

	/// zh-CN: '展开编辑器'
	String get expandEditor => '展开编辑器';

	/// zh-CN: '收起编辑器'
	String get collapseEditor => '收起编辑器';

	/// zh-CN: '条件列表（共 $total 条，启用 $enabled 条）'
	String conditionListSummary({required Object total, required Object enabled}) => '条件列表（共 ${total} 条，启用 ${enabled} 条）';

	/// zh-CN: '需先在上方启用【自动超分】，条件超分才能在阅读与预加载时生效。'
	String get conditionNeedsAutoUpscale => '需先在上方启用【自动超分】，条件超分才能在阅读与预加载时生效。';

	/// zh-CN: '按图片尺寸、路径正则及元数据规则分派超分动作与跳过判定'
	String get conditionUpscaleSubtitle => '按图片尺寸、路径正则及元数据规则分派超分动作与跳过判定';

	/// zh-CN: '条件超分 (neo)'
	String get conditionUpscaleTitle => '条件超分 (neo)';

	/// zh-CN: '高级超分选项 (预超分 / 日志)'
	String get advancedOptionsTitle => '高级超分选项 (预超分 / 日志)';

	/// zh-CN: '调用 waifu2x / Real-CUGAN 的 ncnn-vulkan 可执行文件；模式、倍率、并发与分块在「图片超分」设置页下方调整。'
	String get ncnnCliDesc => '调用 waifu2x / Real-CUGAN 的 ncnn-vulkan 可执行文件；模式、倍率、并发与分块在「图片超分」设置页下方调整。';

	/// zh-CN: 'Swift 直接调用 Apple CoreML，复用已加载模型。'
	String get coremlDesc => 'Swift 直接调用 Apple CoreML，复用已加载模型。';

	/// zh-CN: '原生 $x×'
	String nativeScaleLabel({required Object x}) => '原生 ${x}×';

	/// zh-CN: 'Real-CUGAN · 质量优先'
	String get modeCuganQuality => 'Real-CUGAN · 质量优先';

	/// zh-CN: 'waifu2x · 速度优先'
	String get modeWaifuFast => 'waifu2x · 速度优先';

	/// zh-CN: 'Rossi 原生模型'
	String get nativeModel => 'Rossi 原生模型';

	/// zh-CN: '切换后当前页自动重新处理，两套模型选择分别保留。'
	String get engineSwitchHint => '切换后当前页自动重新处理，两套模型选择分别保留。';

	/// zh-CN: '硬件加速'
	String get hardwareAcceleration => '硬件加速';

	/// zh-CN: '超分引擎'
	String get upscaleEngine => '超分引擎';

	/// zh-CN: '一次处理一页，避免争抢内存；都设为 0 可关闭预超分。'
	String get preUpscaleHint => '一次处理一页，避免争抢内存；都设为 0 可关闭预超分。';

	/// zh-CN: '$n 页'
	String pageCount({required Object n}) => '${n} 页';

	/// zh-CN: '预超分（当前页优先）'
	String get preUpscaleCurrentFirst => '预超分（当前页优先）';

	/// zh-CN: '启用 TTA 增强'
	String get enableTta => '启用 TTA 增强';

	/// zh-CN: '写入结果缓存'
	String get writeResultCache => '写入结果缓存';

	/// zh-CN: '启用分块 Tile'
	String get enableTile => '启用分块 Tile';

	/// zh-CN: '命中此条件时：执行超分'
	String get actionUpscaleHit => '命中此条件时：执行超分';

	/// zh-CN: '命中此条件时：跳过超分（不处理）'
	String get actionSkipHit => '命中此条件时：跳过超分（不处理）';

	/// zh-CN: '触发动作 (Action)'
	String get actionSectionTitle => '触发动作 (Action)';

	/// zh-CN: '排除预超分队列'
	String get excludePreUpscale => '排除预超分队列';

	/// zh-CN: '匹配归档内部路径'
	String get matchArchivePath => '匹配归档内部路径';

	/// zh-CN: '或'
	String get regexExampleOr => '或';

	/// zh-CN: '例: '
	String get regexExamplePrefix => '例: ';

	/// zh-CN: '尺寸与规则匹配 (Match)'
	String get matchSectionTitle => '尺寸与规则匹配 (Match)';

	/// zh-CN: '启用此条件'
	String get enableThisCondition => '启用此条件';

	/// zh-CN: '已启用'
	String get conditionEnabledBadge => '已启用';

	/// zh-CN: '导入成功（$imported 条），跳过 $skipped 条不兼容项'
	String importSuccessSkipped({required Object imported, required Object skipped}) => '导入成功（${imported} 条），跳过 ${skipped} 条不兼容项';

	/// zh-CN: '导入内容不能为空'
	String get importContentEmpty => '导入内容不能为空';

	/// zh-CN: '[ { "name": "示例条件", ... } ]'
	String get importJsonSample => '[\n  {\n    "name": "示例条件",\n    ...\n  }\n]';

	/// zh-CN: '请粘贴导出的 JSON 数组或备份对象文本：'
	String get pasteExportedJson => '请粘贴导出的 JSON 数组或备份对象文本：';

	/// zh-CN: '已复制条件 JSON 到剪贴板'
	String get conditionJsonCopied => '已复制条件 JSON 到剪贴板';

	/// zh-CN: '已恢复默认条件'
	String get conditionsRestored => '已恢复默认条件';

	/// zh-CN: '至少保留一条超分条件'
	String get keepAtLeastOneCondition => '至少保留一条超分条件';

	/// zh-CN: '$name 副本'
	String conditionCopy({required Object name}) => '${name} 副本';

	/// zh-CN: '本地导入请选择上方文件名对应的 mImage ONNX 模型。切换后当前页会重新生成超分图。'
	String get importLocalHint => '本地导入请选择上方文件名对应的 mImage ONNX 模型。切换后当前页会重新生成超分图。';

	/// zh-CN: '当前模型未安装，下载或导入后才能使用'
	String get modelNotInstalled => '当前模型未安装，下载或导入后才能使用';

	/// zh-CN: '当前模型已安装'
	String get modelInstalled => '当前模型已安装';

	/// zh-CN: '运行时：$runtime'
	String modelRuntime({required Object runtime}) => '运行时：${runtime}';

	/// zh-CN: '降噪：由模型固定，不支持单独调节强度'
	String get modelDenoiseFixed => '降噪：由模型固定，不支持单独调节强度';

	/// zh-CN: '降噪：Real-CUGAN 保守修复，强度由模型固定'
	String get modelDenoiseCugan => '降噪：Real-CUGAN 保守修复，强度由模型固定';

	/// zh-CN: '倍率：原生 $scale×（由模型决定）'
	String modelScaleNote({required Object scale}) => '倍率：原生 ${scale}×（由模型决定）';

	/// zh-CN: '没有正在阅读的页面，以下为内置示例；打开漫画后再展开可看到当前页的实际效果。'
	String get exampleBuiltinHint => '没有正在阅读的页面，以下为内置示例；打开漫画后再展开可看到当前页的实际效果。';

	/// zh-CN: '$title示例。$before与$after对比。点击查看大图。$description'
	String exampleSemantics({required Object title, required Object before, required Object after, required Object description}) => '${title}示例。${before}与${after}对比。点击查看大图。${description}';

	/// zh-CN: '$title（示例）'
	String exampleTitleSuffix({required Object title}) => '${title}（示例）';

	/// zh-CN: '来自当前正在阅读的页面，关闭预览后立即释放。'
	String get exampleLiveSource => '来自当前正在阅读的页面，关闭预览后立即释放。';

	/// zh-CN: '$before（保持原样）'
	String beforeUnchanged({required Object before}) => '${before}（保持原样）';

	/// zh-CN: '$before（阴影为裁剪部分）'
	String beforeTrimmedShadow({required Object before}) => '${before}（阴影为裁剪部分）';

	/// zh-CN: '正在读取当前页的裁边结果…'
	String get loadingTrimResult => '正在读取当前页的裁边结果…';

	/// zh-CN: '正在读取当前页的降噪结果…'
	String get loadingDenoiseResult => '正在读取当前页的降噪结果…';

	/// zh-CN: '当前页的图片还没有准备好，翻页或稍后再试'
	String get exampleImageNotReadyRetry => '当前页的图片还没有准备好，翻页或稍后再试';

	/// zh-CN: '预览失败：$error'
	String previewFailed({required Object error}) => '预览失败：${error}';

	/// zh-CN: '降噪后'
	String get afterDenoise => '降噪后';

	/// zh-CN: '裁剪后'
	String get afterTrim => '裁剪后';

	/// zh-CN: '同一 JPEG 局部经 RealPLKSR 1× 实际处理，分辨率保持不变。效果随原图而变化。'
	String get exampleDenoiseDesc => '同一 JPEG 局部经 RealPLKSR 1× 实际处理，分辨率保持不变。效果随原图而变化。';

	/// zh-CN: '去掉四周余白，让漫画内容更大。示意图不随参数变化。'
	String get exampleTrimDesc => '去掉四周余白，让漫画内容更大。示意图不随参数变化。';

	/// zh-CN: '降噪预览'
	String get exampleDenoiseTitle => '降噪预览';

	/// zh-CN: '裁边预览'
	String get exampleTrimTitle => '裁边预览';

	/// zh-CN: '来自 mImageViewer · CC BY 4.0 首次使用需下载；大小与 SHA-256 校验通过后安装。'
	String get denoiseAttribution => '来自 mImageViewer · CC BY 4.0\n首次使用需下载；大小与 SHA-256 校验通过后安装。';

	/// zh-CN: '重试下载'
	String get retryDownload => '重试下载';

	/// zh-CN: '模型下载进度'
	String get denoiseProgressTooltip => '模型下载进度';

	/// zh-CN: '校验模型完整性'
	String get denoiseVerifyTooltip => '校验模型完整性';

	/// zh-CN: 'RealPLKSR · JPEG 降噪 · 1×'
	String get denoiseSubtitle => 'RealPLKSR · JPEG 降噪 · 1×';

	/// zh-CN: '更新失败 · 已安装的模型仍可使用'
	String get denoiseUpdateFailed => '更新失败 · 已安装的模型仍可使用';

	/// zh-CN: '模型已安装 · $size'
	String denoiseInstalled({required Object size}) => '模型已安装 · ${size}';

	/// zh-CN: '正在校验模型'
	String get denoiseVerifying => '正在校验模型';

	/// zh-CN: '模型未安装'
	String get denoiseMissing => '模型未安装';

	/// zh-CN: '正在检查模型'
	String get denoiseChecking => '正在检查模型';

	/// zh-CN: '模型不完整'
	String get modelIncomplete => '模型不完整';

	/// zh-CN: '模型下载完成'
	String get modelDownloadDone => '模型下载完成';

	/// zh-CN: '当前平台不支持手动导入超分模型'
	String get manualImportUnsupported => '当前平台不支持手动导入超分模型';

	/// zh-CN: '缺少模型目录（models-pro / models-se 等）'
	String get missingModelDirs => '缺少模型目录（models-pro / models-se 等）';

	/// zh-CN: '缺少 waifu2x / Real-CUGAN 可执行文件'
	String get missingExecutable => '缺少 waifu2x / Real-CUGAN 可执行文件';

	/// zh-CN: '缺少模型文件 $file'
	String missingModelFile({required Object file}) => '缺少模型文件 ${file}';

	/// zh-CN: '缺少模型目录 $dir'
	String missingModelDir({required Object dir}) => '缺少模型目录 ${dir}';

	/// zh-CN: '缺少 mImage ONNX 模型 $file'
	String missingOnnxModel({required Object file}) => '缺少 mImage ONNX 模型 ${file}';

	/// zh-CN: '当前增强结果暂时无法读取，无法显示对比'
	String get previewEnhancedUnreadable => '当前增强结果暂时无法读取，无法显示对比';

	/// zh-CN: '当前图片未应用降噪 · 当前画面仍为原图'
	String get previewDenoiseOriginal => '当前图片未应用降噪 · 当前画面仍为原图';

	/// zh-CN: '当前图片已应用降噪处理 · 对比阅读器正在显示的增强结果'
	String get previewDenoiseCompare => '当前图片已应用降噪处理 · 对比阅读器正在显示的增强结果';

	/// zh-CN: '当前图片尚未应用降噪 · $phase'
	String previewDenoisePending({required Object phase}) => '当前图片尚未应用降噪 · ${phase}';

	/// zh-CN: '当前图片已应用 JPEG 降噪 · RealPLKSR 1×'
	String get previewDenoiseApplied => '当前图片已应用 JPEG 降噪 · RealPLKSR 1×';

	/// zh-CN: '当前图片已应用降噪及超分 · 对比已上屏的增强结果'
	String get previewBothApplied => '当前图片已应用降噪及超分 · 对比已上屏的增强结果';

	/// zh-CN: '当前图片未被降噪 · 此漫画的降噪开关未开启'
	String get previewDenoiseOff => '当前图片未被降噪 · 此漫画的降噪开关未开启';

	/// zh-CN: '当前图片未被降噪 · 仅处理 JPEG 页面，此页保持原样'
	String get previewDenoiseJpegOnly => '当前图片未被降噪 · 仅处理 JPEG 页面，此页保持原样';

	/// zh-CN: '左 $left · 上 $top · 右 $right · 下 $bottom'
	String trimInsets({required Object left, required Object top, required Object right, required Object bottom}) => '左 ${left} · 上 ${top} · 右 ${right} · 下 ${bottom}';

	/// zh-CN: '当前图片已应用显示裁边 · $summary'
	String previewTrimApplied({required Object summary}) => '当前图片已应用显示裁边 · ${summary}';

	/// zh-CN: '当前图片未被裁剪 · 无需裁边，保持原样'
	String get previewTrimNotNeeded => '当前图片未被裁剪 · 无需裁边，保持原样';

	/// zh-CN: '当前图片尚未完成裁边检测 · 等待读取结果'
	String get previewTrimPending => '当前图片尚未完成裁边检测 · 等待读取结果';

	/// zh-CN: '当前图片未被裁剪 · 分割半页保持原样'
	String get previewTrimSplitPage => '当前图片未被裁剪 · 分割半页保持原样';

	/// zh-CN: '当前图片未被裁剪 · 此漫画的裁边开关未开启'
	String get previewTrimOff => '当前图片未被裁剪 · 此漫画的裁边开关未开启';

	/// zh-CN: '遇到崩溃可设置较小值；「自动」按模型推荐分块，模型声明固定输入尺寸时以模型为准'
	String get tileSizeHint => '遇到崩溃可设置较小值；「自动」按模型推荐分块，模型声明固定输入尺寸时以模型为准';

	/// zh-CN: '条件 $index'
	String conditionN({required Object index}) => '条件 ${index}';

	/// zh-CN: '第 $index 项解析失败: $error'
	String importItemFailed({required Object index, required Object error}) => '第 ${index} 项解析失败: ${error}';

	/// zh-CN: '跳过第 $index 项：数据不是对象'
	String importSkipNotObject({required Object index}) => '跳过第 ${index} 项：数据不是对象';

	/// zh-CN: '默认条件'
	String get defaultCondition => '默认条件';

	/// zh-CN: '桌面 NCNN（waifu2x / Real-CUGAN）'
	String get engineDesktopNcnn => '桌面 NCNN（waifu2x / Real-CUGAN）';

	/// zh-CN: 'Rossi 原生 CoreML'
	String get engineNativeCoreML => 'Rossi 原生 CoreML';

	/// zh-CN: '高速通用（Real-ESR General 4x）'
	String get modelFast => '高速通用（Real-ESR General 4x）';

	/// zh-CN: '照片/CG（Real-ESRGAN 4x）'
	String get modelPhoto => '照片/CG（Real-ESRGAN 4x）';

	/// zh-CN: '插画/动画（Real-ESRGAN Anime 6B 4x）'
	String get modelAnime => '插画/动画（Real-ESRGAN Anime 6B 4x）';

	/// zh-CN: '漫画（Real-CUGAN 4x）'
	String get modelComic => '漫画（Real-CUGAN 4x）';

	/// zh-CN: '先降噪再超分'
	String get modeDenoiseThenUpscale => '先降噪再超分';

	/// zh-CN: '仅超分'
	String get modeUpscaleOnly => '仅超分';

	/// zh-CN: '仅 JPEG 降噪'
	String get modeDenoiseOnly => '仅 JPEG 降噪';

	/// zh-CN: '原图'
	String get modeOriginal => '原图';

	/// zh-CN: '删除条件'
	String get deleteCondition => '删除条件';

	/// zh-CN: '下移优先级'
	String get lowerPriority => '下移优先级';

	/// zh-CN: '上移优先级'
	String get raisePriority => '上移优先级';

	/// zh-CN: '添加条件'
	String get addCondition => '添加条件';

	/// zh-CN: '定位最近生成的超分图；尚未生成时打开超分缓存目录。'
	String get openImageFolderHint => '定位最近生成的超分图；尚未生成时打开超分缓存目录。';

	/// zh-CN: '打开图片文件夹'
	String get openImageFolder => '打开图片文件夹';

	/// zh-CN: '查看超分日志'
	String get viewUpscaleLog => '查看超分日志';

	/// zh-CN: '超分日志'
	String get upscaleLog => '超分日志';

	/// zh-CN: '下载 Rossi 原生模型'
	String get downloadNativeModel => '下载 Rossi 原生模型';

	/// zh-CN: '之前页：'
	String get pagesBefore => '之前页：';

	/// zh-CN: '后续页：'
	String get pagesAfter => '后续页：';

	/// zh-CN: '分块大小：'
	String get blockSizeLabel => '分块大小：';

	/// zh-CN: '输出倍率：'
	String get outputScaleLabel => '输出倍率：';

	/// zh-CN: '图片路径正则 (imagePathRegex)'
	String get imagePathRegex => '图片路径正则 (imagePathRegex)';

	/// zh-CN: '书籍路径正则 (bookPathRegex)'
	String get bookPathRegex => '书籍路径正则 (bookPathRegex)';

	/// zh-CN: '任一满足 (OR)'
	String get matchAnyOr => '任一满足 (OR)';

	/// zh-CN: '全部满足 (AND)'
	String get matchAllAnd => '全部满足 (AND)';

	/// zh-CN: '尺寸匹配逻辑：'
	String get sizeMatchLogic => '尺寸匹配逻辑：';

	/// zh-CN: '最大像素 (MPx)'
	String get maxPixelsMpx => '最大像素 (MPx)';

	/// zh-CN: '最小像素 (MPx)'
	String get minPixelsMpx => '最小像素 (MPx)';

	/// zh-CN: '最大高度 (px)'
	String get maxHeightPx => '最大高度 (px)';

	/// zh-CN: '最小高度 (px)'
	String get minHeightPx => '最小高度 (px)';

	/// zh-CN: '最大宽度 (px)'
	String get maxWidthPx => '最大宽度 (px)';

	/// zh-CN: '最小宽度 (px)'
	String get minWidthPx => '最小宽度 (px)';

	/// zh-CN: '条件名称'
	String get conditionName => '条件名称';

	/// zh-CN: '应用导入'
	String get applyImport => '应用导入';

	/// zh-CN: '导入条件超分配置'
	String get importConditions => '导入条件超分配置';

	/// zh-CN: '复制到剪贴板'
	String get copyToClipboard => '复制到剪贴板';

	/// zh-CN: '导出条件超分配置 (JSON)'
	String get exportConditions => '导出条件超分配置 (JSON)';

	/// zh-CN: '确定将所有条件恢复为出厂默认设置吗？现有规则将被清除。'
	String get resetConditionsContent => '确定将所有条件恢复为出厂默认设置吗？现有规则将被清除。';

	/// zh-CN: '重置条件超分'
	String get resetConditions => '重置条件超分';

	/// zh-CN: '浏览器下载'
	String get downloadInBrowser => '浏览器下载';

	/// zh-CN: '导入本地 ONNX'
	String get importLocalOnnx => '导入本地 ONNX';

	/// zh-CN: '删除当前模型'
	String get deleteCurrentModel => '删除当前模型';

	/// zh-CN: '重新下载当前模型'
	String get redownloadCurrentModel => '重新下载当前模型';

	/// zh-CN: '下载当前模型'
	String get downloadCurrentModel => '下载当前模型';

	/// zh-CN: '自定义超分模型'
	String get customModel => '自定义超分模型';

	/// zh-CN: 'ONNX 模型'
	String get onnxModel => 'ONNX 模型';

	/// zh-CN: '默认收起，展开后才会加载图片'
	String get exampleCollapsedHint => '默认收起，展开后才会加载图片';

	/// zh-CN: '当前页的图片还没有准备好'
	String get exampleImageNotReady => '当前页的图片还没有准备好';

	/// zh-CN: '关闭示例'
	String get closeExample => '关闭示例';

	/// zh-CN: '移除模型'
	String get removeModel => '移除模型';

	/// zh-CN: '尚未生成'
	String get noOutputYet => '尚未生成';

	/// zh-CN: 'Rossi 超分日志（本次运行）'
	String get logWindowTitle => 'Rossi 超分日志（本次运行）';

	/// zh-CN: '超分'
	String get logCategory => '超分';

	/// zh-CN: '桌面 NCNN 模型的实际倍率设置'
	String get outputScaleSubtitle => '桌面 NCNN 模型的实际倍率设置';

	/// zh-CN: '输出倍率'
	String get outputScale => '输出倍率';

	/// zh-CN: '未命名条件'
	String get unnamedCondition => '未命名条件';

	/// zh-CN: '图片超分（实验性）'
	String get title => '图片超分（实验性）';

	/// zh-CN: '不限制'
	String get unlimited => '不限制';

	/// zh-CN: '模型下载失败'
	String get modelDownloadFailed => '模型下载失败';

	/// zh-CN: '通用'
	String get generalSection => '通用';

	/// zh-CN: '自动超分'
	String get autoUpscaleSection => '自动超分';

	/// zh-CN: '自动超分'
	String get autoUpscale => '自动超分';

	/// zh-CN: '模型未下载，开启后无法自动超分'
	String get autoUpscaleSubtitleUnavailable => '模型未下载，开启后无法自动超分';

	/// zh-CN: '下载或加载图片时自动调用超分'
	String get autoUpscaleSubtitleAvailable => '下载或加载图片时自动调用超分';

	/// zh-CN: '超分条件'
	String get conditionSection => '超分条件';

	/// zh-CN: '分辨率阈值'
	String get resolutionThreshold => '分辨率阈值';

	/// zh-CN: '仅当图片宽度小于该值时才自动超分'
	String get resolutionThresholdSubtitle => '仅当图片宽度小于该值时才自动超分';

	/// zh-CN: '性能'
	String get performanceSection => '性能';

	/// zh-CN: '并发数量'
	String get concurrency => '并发数量';

	/// zh-CN: '高端显卡可适当提高，移动设备或性能较低时不建议设置高于1的并发量'
	String get concurrencySubtitle => '高端显卡可适当提高，移动设备或性能较低时不建议设置高于1的并发量';

	/// zh-CN: '分块大小'
	String get tileSize => '分块大小';

	/// zh-CN: '遇到崩溃可设置较小值，0为不分块，桌面端可尝试设置为0'
	String get tileSizeSubtitle => '遇到崩溃可设置较小值，0为不分块，桌面端可尝试设置为0';

	/// zh-CN: '模型'
	String get modelSection => '模型';

	/// zh-CN: '模型'
	String get model => '模型';

	/// zh-CN: '切换模型族会重置对应的变体选项'
	String get modelSubtitle => '切换模型族会重置对应的变体选项';

	/// zh-CN: '降噪级别'
	String get noiseLevel => '降噪级别';

	/// zh-CN: '该选项随所选模型变化'
	String get noiseLevelSubtitle => '该选项随所选模型变化';

	/// zh-CN: '分块信息'
	String get blockInfo => '分块信息';

	/// zh-CN: 'blockSize 是模型输入尺寸，包含反射边距； 内容块 = blockSize - 2×shrinkSize，才是真正拼接输出的区域。'
	String get blockInfoTooltip => 'blockSize 是模型输入尺寸，包含反射边距；\n内容块 = blockSize - 2×shrinkSize，才是真正拼接输出的区域。';

	/// zh-CN: '内容块 $contentSize×$contentSize，模型输入 $blockSize×$blockSize（含 ${shrinkSize}px 反射边距）'
	String blockInfoFormat({required Object contentSize, required Object blockSize, required Object shrinkSize}) => '内容块 ${contentSize}×${contentSize}，模型输入 ${blockSize}×${blockSize}（含 ${shrinkSize}px 反射边距）';

	/// zh-CN: 'Android 超分'
	String get androidSuperResolution => 'Android 超分';

	/// zh-CN: '当前使用 waifu2x upconv 动漫模型，2 倍放大'
	String get androidSuperResolutionSubtitle => '当前使用 waifu2x upconv 动漫模型，2 倍放大';

	/// zh-CN: '超分引擎'
	String get androidEngine => '超分引擎';

	/// zh-CN: 'Android 上选择超分推理后端'
	String get androidEngineSubtitle => 'Android 上选择超分推理后端';

	/// zh-CN: 'Vulkan（waifu2x CLI）'
	String get androidEngineVulkan => 'Vulkan（waifu2x CLI）';

	/// zh-CN: 'ncnn + Vulkan GPU，兼容所有 Android 设备'
	String get androidEngineVulkanSubtitle => 'ncnn + Vulkan GPU，兼容所有 Android 设备';

	/// zh-CN: 'NPU（Qualcomm QNN）'
	String get androidEngineQnnNpu => 'NPU（Qualcomm QNN）';

	/// zh-CN: 'Hexagon HTP NPU 推理，骁龙 8 系专属（实验阶段）'
	String get androidEngineQnnNpuSubtitle => 'Hexagon HTP NPU 推理，骁龙 8 系专属（实验阶段）';

	/// zh-CN: 'NPU 后端处于实验阶段：失败时保留原图并显示原因，不会静默退回 Vulkan'
	String get androidEngineQnnExperimental => 'NPU 后端处于实验阶段：失败时保留原图并显示原因，不会静默退回 Vulkan';

	/// zh-CN: 'NPU 模型'
	String get qnnModel => 'NPU 模型';

	/// zh-CN: 'Real-CUGAN FP16 模型，2 倍放大'
	String get qnnModelSubtitle => 'Real-CUGAN FP16 模型，2 倍放大';

	/// zh-CN: 'Real-CUGAN SE 2×（无降噪）'
	String get qnnModelSeX2NoDenoise => 'Real-CUGAN SE 2×（无降噪）';

	/// zh-CN: 'Real-CUGAN Pro 2×（降噪 3 档）'
	String get qnnModelProX2Denoise3x => 'Real-CUGAN Pro 2×（降噪 3 档）';

	/// zh-CN: '正在检测 NPU…'
	String get qnnProbing => '正在检测 NPU…';

	/// zh-CN: '检测到 Qualcomm HTP $arch，NPU 可用'
	String qnnSupported({required Object arch}) => '检测到 Qualcomm HTP ${arch}，NPU 可用';

	/// zh-CN: '首次使用会在设备上编译模型上下文（约 1-2 秒）并缓存'
	String get qnnSupportedSubtitle => '首次使用会在设备上编译模型上下文（约 1-2 秒）并缓存';

	/// zh-CN: '此设备的 NPU 不可用'
	String get qnnUnsupported => '此设备的 NPU 不可用';

	/// zh-CN: '未检测到受支持的 Qualcomm HTP 运行时（或本包为不含 NPU 支持的构建）'
	String get qnnUnsupportedSubtitle => '未检测到受支持的 Qualcomm HTP 运行时（或本包为不含 NPU 支持的构建）';

	/// zh-CN: '检测到 HTP $arch，但本包未收录该架构的运行库'
	String qnnUnsupportedArchSubtitle({required Object arch}) => '检测到 HTP ${arch}，但本包未收录该架构的运行库';

	/// zh-CN: '上下文未准备'
	String get qnnIdle => '上下文未准备';

	/// zh-CN: '下载模型后点「准备」编译 NPU 上下文；阅读时也会自动准备'
	String get qnnIdleSubtitle => '下载模型后点「准备」编译 NPU 上下文；阅读时也会自动准备';

	/// zh-CN: '正在编译 NPU 上下文…'
	String get qnnPreparing => '正在编译 NPU 上下文…';

	/// zh-CN: 'NPU 上下文已就绪'
	String get qnnReady => 'NPU 上下文已就绪';

	/// zh-CN: 'NPU 上下文准备失败'
	String get qnnFailed => 'NPU 上下文准备失败';

	/// zh-CN: '准备'
	String get qnnPrepare => '准备';

	/// zh-CN: '重试'
	String get qnnRetry => '重试';

	/// zh-CN: '缺少 NPU 模型文件 $file'
	String missingQnnModel({required Object file}) => '缺少 NPU 模型文件 ${file}';

	/// zh-CN: '缺少 NPU 模型清单 manifest.json'
	String get missingQnnManifest => '缺少 NPU 模型清单 manifest.json';

	/// zh-CN: '超分策略'
	String get desktopStrategy => '超分策略';

	/// zh-CN: '效率优先使用 waifu2x，质量优先使用 Real-CUGAN'
	String get desktopStrategySubtitle => '效率优先使用 waifu2x，质量优先使用 Real-CUGAN';

	/// zh-CN: '降噪级别'
	String get desktopNoiseLevel => '降噪级别';

	/// zh-CN: '保守适合普通漫画，降噪级别越高涂抹感越强'
	String get desktopNoiseLevelSubtitle => '保守适合普通漫画，降噪级别越高涂抹感越强';

	/// zh-CN: '模型管理'
	String get modelManagementSection => '模型管理';

	/// zh-CN: '正在下载模型'
	String get downloadingModel => '正在下载模型';

	/// zh-CN: '模型已就绪'
	String get modelReady => '模型已就绪';

	/// zh-CN: '重新下载'
	String get redownload => '重新下载';

	/// zh-CN: '删除模型'
	String get deleteModel => '删除模型';

	/// zh-CN: '确定要删除已下载的超分模型吗？删除后需要重新下载才能使用。'
	String get deleteModelConfirm => '确定要删除已下载的超分模型吗？删除后需要重新下载才能使用。';

	/// zh-CN: '模型已删除'
	String get modelDeleted => '模型已删除';

	/// zh-CN: '模型删除失败'
	String get modelDeleteFailed => '模型删除失败';

	/// zh-CN: '模型未下载'
	String get modelNotDownloaded => '模型未下载';

	/// zh-CN: '使用超分前需要先下载模型'
	String get modelNotDownloadedSubtitle => '使用超分前需要先下载模型';

	/// zh-CN: '下载模型'
	String get downloadModel => '下载模型';

	/// zh-CN: '手动下载模型'
	String get manualDownload => '手动下载模型';

	/// zh-CN: '当前平台不支持手动下载超分模型'
	String get manualDownloadUnsupported => '当前平台不支持手动下载超分模型';

	/// zh-CN: '打开链接'
	String get openDownloadUrl => '打开链接';

	/// zh-CN: '打开链接失败'
	String get openDownloadUrlFailed => '打开链接失败';

	/// zh-CN: '导入模型压缩包'
	String get importModel => '导入模型压缩包';

	/// zh-CN: '选择手动下载的 7z 压缩包，导入时会校验格式与模型内容'
	String get importModelSubtitle => '选择手动下载的 7z 压缩包，导入时会校验格式与模型内容';

	/// zh-CN: '选择文件'
	String get importModelAction => '选择文件';

	/// zh-CN: '模型导入成功'
	String get modelImportSuccess => '模型导入成功';

	/// zh-CN: '模型导入失败'
	String get modelImportFailed => '模型导入失败';

	/// zh-CN: '效率优先'
	String get modeEfficiency => '效率优先';

	/// zh-CN: '质量优先'
	String get modeQuality => '质量优先';

	/// zh-CN: '保守'
	String get noiseConservative => '保守';

	/// zh-CN: '无降噪'
	String get noise0 => '无降噪';

	/// zh-CN: '降噪 1'
	String get noise1 => '降噪 1';

	/// zh-CN: '降噪 2'
	String get noise2 => '降噪 2';

	/// zh-CN: '降噪 3'
	String get noise3 => '降噪 3';

	/// zh-CN: 'waifu2x upconv 动漫'
	String get variantWaifu2xAnime => 'waifu2x upconv 动漫';

	/// zh-CN: 'Real-CUGAN 降噪 $noise'
	String variantRealCuganDenoise({required Object noise}) => 'Real-CUGAN 降噪 ${noise}';

	/// zh-CN: '速度优先 (waifu2x)'
	String get coremlSpeed => '速度优先 (waifu2x)';

	/// zh-CN: '质量优先 (Real-CUGAN)'
	String get coremlQuality => '质量优先 (Real-CUGAN)';

	/// zh-CN: '降噪 0'
	String get coremlNoise0 => '降噪 0';

	/// zh-CN: '无降噪'
	String get coremlNoDenoise => '无降噪';

	/// zh-CN: '输入图片绝对路径或 asset 路径'
	String get coremlInputHint => '输入图片绝对路径或 asset 路径';

	/// zh-CN: '开始超分'
	String get coremlStartUpscale => '开始超分';

	/// zh-CN: '请填写输入图片路径'
	String get coremlStatusFillInput => '请填写输入图片路径';

	/// zh-CN: '当前模型族没有可用的模型文件'
	String get coremlStatusNoModelFile => '当前模型族没有可用的模型文件';

	/// zh-CN: '正在准备资源...'
	String get coremlStatusPreparing => '正在准备资源...';

	/// zh-CN: '正在超分...'
	String get coremlStatusUpscaling => '正在超分...';

	/// zh-CN: '完成 $outputPath size: $size bytes'
	String coremlStatusDone({required Object outputPath, required Object size}) => '完成\n${outputPath}\nsize: ${size} bytes';

	/// zh-CN: '失败: $error'
	String coremlStatusFailed({required Object error}) => '失败: ${error}';

	/// zh-CN: '模型选项（降噪级别）'
	String get coremlModelOption => '模型选项（降噪级别）';

	/// zh-CN: '通用选项（放大倍率）'
	String get coremlGeneralOption => '通用选项（放大倍率）';

	/// zh-CN: '分块信息'
	String get coremlTileInfo => '分块信息';
}

// Path: about
class Translations$about$zh_CN {
	Translations$about$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '关于应用'
	String get title => '关于应用';

	/// zh-CN: '版本号: $version'
	String version({required Object version}) => '版本号: ${version}';

	/// zh-CN: '加载中...'
	String get loading => '加载中...';

	/// zh-CN: '获取失败'
	String get fetchFailed => '获取失败';

	/// zh-CN: '网络错误'
	String get networkError => '网络错误';

	/// zh-CN: '跨平台漫画阅读器'
	String get tagline => '跨平台漫画阅读器';

	/// zh-CN: '项目地址'
	String get projectAddress => '项目地址';

	/// zh-CN: '喜欢这个项目吗？点个star支持一下吧！'
	String get projectAddressDesc => '喜欢这个项目吗？点个star支持一下吧！';

	/// zh-CN: '前往 GitHub 仓库 (HibernalGlow/rossi) ⭐'
	String get projectLink => '前往 GitHub 仓库 (HibernalGlow/rossi) ⭐';

	/// zh-CN: '反馈与建议'
	String get feedback => '反馈与建议';

	/// zh-CN: '发现BUG或者有新的点子？'
	String get feedbackDesc => '发现BUG或者有新的点子？';

	/// zh-CN: '在 GitHub Issues 中提出'
	String get feedbackLink => '在 GitHub Issues 中提出';

	/// zh-CN: '上游致谢'
	String get upstream => '上游致谢';

	/// zh-CN: 'Rossi 在 Breeze 的基础上继续开发，感谢上游作者与社区。'
	String get upstreamDesc => 'Rossi 在 Breeze 的基础上继续开发，感谢上游作者与社区。';

	/// zh-CN: '前往上游仓库 (deretame/Breeze)'
	String get upstreamLink => '前往上游仓库 (deretame/Breeze)';

	/// zh-CN: '本项目以 Mozilla Public License 2.0 授权发布。'
	String get licenseDesc => '本项目以 Mozilla Public License 2.0 授权发布。';

	/// zh-CN: '查看完整许可文本'
	String get licenseLink => '查看完整许可文本';

	/// zh-CN: '贡献者'
	String get contributors => '贡献者';

	/// zh-CN: '$count人'
	String contributorsCount({required Object count}) => '${count}人';

	/// zh-CN: '$login ($count 次提交)'
	String contributionsTooltip({required Object login, required Object count}) => '${login} (${count} 次提交)';

	/// zh-CN: '免责声明'
	String get disclaimer => '免责声明';

	/// zh-CN: '开源项目免责声明'
	String get disclaimerTitle => '开源项目免责声明';

	/// zh-CN: '1. 项目性质与声明'
	String get disclaimerItem1Title => '1. 项目性质与声明';

	/// zh-CN: '本项目为开源软件，由社区贡献者共同开发与维护。项目以"原样"形式提供，开发者不对项目的功能完整性、稳定性、安全性或适用性作出任何明示或暗示的担保。'
	String get disclaimerItem1Content => '本项目为开源软件，由社区贡献者共同开发与维护。项目以"原样"形式提供，开发者不对项目的功能完整性、稳定性、安全性或适用性作出任何明示或暗示的担保。';

	/// zh-CN: '2. 责任限制'
	String get disclaimerItem2Title => '2. 责任限制';

	/// zh-CN: '开发者对因使用、修改或分发本项目（包括但不限于直接使用、二次开发或集成至其他项目）而导致的任何直接、间接、特殊、附带或后果性损害不承担任何责任。这些损害可能包括但不限于数据丢失、设备损坏、业务中断、利润损失或其他经济损失。'
	String get disclaimerItem2Content => '开发者对因使用、修改或分发本项目（包括但不限于直接使用、二次开发或集成至其他项目）而导致的任何直接、间接、特殊、附带或后果性损害不承担任何责任。这些损害可能包括但不限于数据丢失、设备损坏、业务中断、利润损失或其他经济损失。';

	/// zh-CN: '3. 用户责任'
	String get disclaimerItem3Title => '3. 用户责任';

	/// zh-CN: '用户在使用本项目时，应自行评估其适用性并承担所有风险。用户须确保其使用行为符合所在国家或地区的法律法规及道德规范。开发者不对用户因违反法律法规或不当使用本项目而导致的任何后果负责。'
	String get disclaimerItem3Content => '用户在使用本项目时，应自行评估其适用性并承担所有风险。用户须确保其使用行为符合所在国家或地区的法律法规及道德规范。开发者不对用户因违反法律法规或不当使用本项目而导致的任何后果负责。';

	/// zh-CN: '4. 第三方依赖与资源'
	String get disclaimerItem4Title => '4. 第三方依赖与资源';

	/// zh-CN: '本项目可能依赖或引用第三方库、工具、服务或其他资源。开发者不对这些第三方资源的内容、功能、安全性或合法性负责。用户应自行评估并承担使用第三方资源的风险。'
	String get disclaimerItem4Content => '本项目可能依赖或引用第三方库、工具、服务或其他资源。开发者不对这些第三方资源的内容、功能、安全性或合法性负责。用户应自行评估并承担使用第三方资源的风险。';

	/// zh-CN: '5. 无担保声明'
	String get disclaimerItem5Title => '5. 无担保声明';

	/// zh-CN: '开发者明确声明不对本项目提供任何形式的担保，包括但不限于：适销性担保；特定用途适用性担保；不侵犯第三方权利担保；无错误或无中断运行担保。'
	String get disclaimerItem5Content => '开发者明确声明不对本项目提供任何形式的担保，包括但不限于：适销性担保；特定用途适用性担保；不侵犯第三方权利担保；无错误或无中断运行担保。';

	/// zh-CN: '6. 项目修改与终止'
	String get disclaimerItem6Title => '6. 项目修改与终止';

	/// zh-CN: '开发者保留随时修改、暂停或终止本项目的权利，且无需提前通知用户。开发者不对因项目修改、暂停或终止而导致的任何后果负责。'
	String get disclaimerItem6Content => '开发者保留随时修改、暂停或终止本项目的权利，且无需提前通知用户。开发者不对因项目修改、暂停或终止而导致的任何后果负责。';

	/// zh-CN: '7. 贡献者责任'
	String get disclaimerItem7Title => '7. 贡献者责任';

	/// zh-CN: '外部贡献者的行为仅代表其个人立场，不代表项目维护者的观点或立场。项目维护者对贡献者的行为及其贡献内容不承担责任。'
	String get disclaimerItem7Content => '外部贡献者的行为仅代表其个人立场，不代表项目维护者的观点或立场。项目维护者对贡献者的行为及其贡献内容不承担责任。';

	/// zh-CN: '8. 法律合规性'
	String get disclaimerItem8Title => '8. 法律合规性';

	/// zh-CN: '用户在使用本项目时，应确保其行为符合所在国家或地区的法律法规。开发者不对用户因违反法律法规而导致的任何后果负责。'
	String get disclaimerItem8Content => '用户在使用本项目时，应确保其行为符合所在国家或地区的法律法规。开发者不对用户因违反法律法规而导致的任何后果负责。';

	/// zh-CN: '重要提示'
	String get disclaimerImportant => '重要提示';

	/// zh-CN: '在使用本项目之前，请仔细阅读并理解本免责声明。如果您不同意本声明的任何条款，请立即停止使用本项目。继续使用本项目即表示您已阅读、理解并同意本免责声明的全部内容。'
	String get disclaimerImportantContent => '在使用本项目之前，请仔细阅读并理解本免责声明。如果您不同意本声明的任何条款，请立即停止使用本项目。继续使用本项目即表示您已阅读、理解并同意本免责声明的全部内容。';

	/// zh-CN: '检查更新'
	String get checkUpdate => '检查更新';

	/// zh-CN: '已是最新版本'
	String get alreadyLatest => '已是最新版本';

	/// zh-CN: '发现新版本'
	String get updateAvailable => '发现新版本';

	/// zh-CN: '开源许可'
	String get license => '开源许可';

	/// zh-CN: '隐私政策'
	String get privacy => '隐私政策';
}

// Path: oldHome
class Translations$oldHome$zh_CN {
	Translations$oldHome$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '首页'
	String get title => '首页';

	/// zh-CN: '搜索'
	String get search => '搜索';

	/// zh-CN: '热搜'
	String get hotSearch => '热搜';

	/// zh-CN: '导航'
	String get navigation => '导航';

	/// zh-CN: '推荐'
	String get recommend => '推荐';

	/// zh-CN: '最新'
	String get latest => '最新';

	/// zh-CN: '云收藏'
	String get cloudFavorite => '云收藏';

	/// zh-CN: '列表'
	String get list => '列表';

	/// zh-CN: '功能'
	String get function => '功能';

	/// zh-CN: '关闭'
	String get close => '关闭';

	/// zh-CN: '加载失败，请重试。'
	String get loadFailedRetry => '加载失败，请重试。';

	/// zh-CN: '加载 $title 失败 $error'
	String loadSectionFailed({required Object title, required Object error}) => '加载 ${title} 失败\n${error}';

	/// zh-CN: '暂无内容'
	String get empty => '暂无内容';

	/// zh-CN: '加载更多失败，点击重试'
	String get loadMoreFailed => '加载更多失败，点击重试';

	/// zh-CN: '点击加载更多'
	String get loadMore => '点击加载更多';

	/// zh-CN: '没有更多了'
	String get noMore => '没有更多了';
}

// Path: more
class Translations$more$zh_CN {
	Translations$more$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '常用'
	String get common => '常用';

	/// zh-CN: '其他'
	String get others => '其他';

	/// zh-CN: '下载任务'
	String get downloadTasks => '下载任务';

	/// zh-CN: '同步'
	String get sync => '同步';

	/// zh-CN: '追更'
	String get comicFollow => '追更';

	/// zh-CN: '更新日志'
	String get changelog => '更新日志';
}

// Path: search
class Translations$search$zh_CN {
	Translations$search$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '搜索'
	String get title => '搜索';

	/// zh-CN: '搜索...'
	String get searchHint => '搜索...';

	/// zh-CN: '选择漫画源'
	String get selectSource => '选择漫画源';

	/// zh-CN: '当前插件不支持高级搜索'
	String get advancedSearchNotSupported => '当前插件不支持高级搜索';

	/// zh-CN: '高级搜索选项'
	String get advancedSearchOptions => '高级搜索选项';

	/// zh-CN: '未选择'
	String get notSelected => '未选择';

	/// zh-CN: '已选择 $count 项'
	String selectedCount({required Object count}) => '已选择 ${count} 项';

	/// zh-CN: '搜索历史'
	String get history => '搜索历史';

	/// zh-CN: '清空历史'
	String get clearHistory => '清空历史';

	/// zh-CN: '当前：最近搜索在前'
	String get newestFirst => '当前：最近搜索在前';

	/// zh-CN: '当前：最早搜索在前'
	String get oldestFirst => '当前：最早搜索在前';

	/// zh-CN: '时间倒序'
	String get descending => '时间倒序';

	/// zh-CN: '时间正序'
	String get ascending => '时间正序';

	/// zh-CN: '暂无搜索记录'
	String get noHistory => '暂无搜索记录';

	/// zh-CN: '已按插件分时间线，点击合并成一条'
	String get groupByPluginTooltipOn => '已按插件分时间线，点击合并成一条';

	/// zh-CN: '全部堆在一条时间线上，点击按插件分组'
	String get groupByPluginTooltipOff => '全部堆在一条时间线上，点击按插件分组';

	/// zh-CN: '聚合搜索'
	String get historyGroupAggregate => '聚合搜索';

	/// zh-CN: '未分类'
	String get historyGroupUncategorized => '未分类';

	/// zh-CN: '🔍 搜索技巧'
	String get tipsTitle => '🔍 搜索技巧';

	/// zh-CN: '精准搜索（同时满足）'
	String get exactSearchTitle => '精准搜索（同时满足）';

	/// zh-CN: '全彩(空格)+人妻'
	String get exactSearchExample => '全彩(空格)+人妻';

	/// zh-CN: '显示同时包含这两个标签的结果'
	String get exactSearchDesc => '显示同时包含这两个标签的结果';

	/// zh-CN: '排除搜索（不要某类）'
	String get excludeSearchTitle => '排除搜索（不要某类）';

	/// zh-CN: '全彩(空格)-人妻'
	String get excludeSearchExample => '全彩(空格)-人妻';

	/// zh-CN: '显示"全彩"但排除含"人妻"的结果'
	String get excludeSearchDesc => '显示"全彩"但排除含"人妻"的结果';

	/// zh-CN: '模糊搜索（包含任一）'
	String get fuzzySearchTitle => '模糊搜索（包含任一）';

	/// zh-CN: '全彩(空格)人妻'
	String get fuzzySearchExample => '全彩(空格)人妻';

	/// zh-CN: '显示包含任意一个关键词的结果'
	String get fuzzySearchDesc => '显示包含任意一个关键词的结果';

	/// zh-CN: '选择分类'
	String get selectCategory => '选择分类';

	/// zh-CN: '数据来源'
	String get dataSource => '数据来源';

	/// zh-CN: '排序方式'
	String get sortBy => '排序方式';

	/// zh-CN: '从新到旧'
	String get newestToOldest => '从新到旧';

	/// zh-CN: '从旧到新'
	String get oldestToNewest => '从旧到新';

	/// zh-CN: '最多点赞'
	String get mostLikes => '最多点赞';

	/// zh-CN: '最多观看'
	String get mostViews => '最多观看';

	/// zh-CN: '选择漫画源'
	String get selectSourceTooltip => '选择漫画源';

	/// zh-CN: '有结果'
	String get hasResults => '有结果';

	/// zh-CN: '显示错误'
	String get showErrors => '显示错误';

	/// zh-CN: '$count 条'
	String resultCount({required Object count}) => '${count} 条';

	/// zh-CN: '无结果'
	String get noResults => '无结果';

	/// zh-CN: '$source 加载失败'
	String loadFailedForSource({required Object source}) => '${source} 加载失败';
}

// Path: discover
class Translations$discover$zh_CN {
	Translations$discover$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '发现'
	String get title => '发现';

	/// zh-CN: '搜索'
	String get search => '搜索';

	/// zh-CN: '设置'
	String get settings => '设置';

	/// zh-CN: '插件管理'
	String get pluginManagement => '插件管理';

	/// zh-CN: '自定义插件顺序'
	String get customOrder => '自定义插件顺序';

	/// zh-CN: '恢复默认顺序'
	String get resetOrder => '恢复默认顺序';

	/// zh-CN: '暂无可用插件，去插件商店安装一个吧~'
	String get noPlugins => '暂无可用插件，去插件商店安装一个吧~';

	/// zh-CN: '插件商店'
	String get pluginStore => '插件商店';

	/// zh-CN: '浏览安装'
	String get browseInstall => '浏览安装';

	/// zh-CN: '暂无可用插件，无法搜索'
	String get noPluginForSearch => '暂无可用插件，无法搜索';

	/// zh-CN: '插件信息加载失败: $error'
	String pluginInfoLoadFailed({required Object error}) => '插件信息加载失败: ${error}';

	/// zh-CN: '插件能力'
	String get pluginCapability => '插件能力';

	/// zh-CN: '已关闭'
	String get disabled => '已关闭';

	/// zh-CN: '未命名'
	String get unnamed => '未命名';

	/// zh-CN: '插件启用失败: $error'
	String pluginEnableFailed({required Object error}) => '插件启用失败: ${error}';

	/// zh-CN: '插件关闭失败: $error'
	String pluginCloseFailed({required Object error}) => '插件关闭失败: ${error}';

	/// zh-CN: '插件调试加载失败，已回退数据库: $error'
	String pluginDebugLoadFailed({required Object error}) => '插件调试加载失败，已回退数据库: ${error}';

	/// zh-CN: '关闭标签'
	String get closeTab => '关闭标签';

	/// zh-CN: '标签显示'
	String get tabDisplay => '标签显示';

	/// zh-CN: '显示插件图标'
	String get tabShowIcon => '显示插件图标';

	/// zh-CN: '显示插件名缩写'
	String get tabShowPluginShort => '显示插件名缩写';

	/// zh-CN: '双击关闭标签'
	String get tabDoubleClickClose => '双击关闭标签';

	/// zh-CN: '封面页签'
	String get tabCoverMode => '封面页签';

	/// zh-CN: '把页签显示成书封，并在封面上叠加信息'
	String get tabCoverModeDesc => '把页签显示成书封，并在封面上叠加信息';

	/// zh-CN: '网页'
	String get webPage => '网页';

	/// zh-CN: '详情'
	String get comicDetail => '详情';
}

// Path: searchResult
class Translations$searchResult$zh_CN {
	Translations$searchResult$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '输入页数'
	String get enterPageNumber => '输入页数';

	/// zh-CN: '请输入数字'
	String get pleaseEnterNumber => '请输入数字';

	/// zh-CN: '返回顶部'
	String get returnToTop => '返回顶部';

	/// zh-CN: '跳转页面'
	String get jumpToPage => '跳转页面';

	/// zh-CN: '跳转'
	String get jump => '跳转';

	/// zh-CN: '点击重试'
	String get retry => '点击重试';
}

// Path: comicList
class Translations$comicList$zh_CN {
	Translations$comicList$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '浏览菜单'
	String get browseMenu => '浏览菜单';

	/// zh-CN: '第 $page 页'
	String currentPage({required Object page}) => '第 ${page} 页';

	/// zh-CN: '第 $page / $total 页'
	String pageOfTotal({required Object page, required Object total}) => '第 ${page} / ${total} 页';

	/// zh-CN: '快速跳页'
	String get jumpToPage => '快速跳页';

	/// zh-CN: '目标页码'
	String get pageInput => '目标页码';

	/// zh-CN: '请输入大于 0 的整数'
	String get invalidPage => '请输入大于 0 的整数';

	/// zh-CN: '页码不能超过 $total'
	String pageOutOfRange({required Object total}) => '页码不能超过 ${total}';

	/// zh-CN: '恢复上次浏览位置'
	String get restorePosition => '恢复上次浏览位置';

	/// zh-CN: '上次看到第 $page 页'
	String restorePage({required Object page}) => '上次看到第 ${page} 页';

	/// zh-CN: '还没有浏览记录'
	String get noSavedPosition => '还没有浏览记录';

	/// zh-CN: '滚动后自动保存位置'
	String get positionSavedAutomatically => '滚动后自动保存位置';

	/// zh-CN: '上一页'
	String get previousPage => '上一页';

	/// zh-CN: '下一页'
	String get nextPage => '下一页';

	/// zh-CN: '漢化'
	String get chineseLocalized => '漢化';

	/// zh-CN: '下载时间'
	String get downloadedAtLabel => '下载时间';

	/// zh-CN: '喜欢的画师'
	String get likedArtists => '喜欢的画师';

	/// zh-CN: '喜欢的 tag'
	String get likedTags => '喜欢的 tag';

	/// zh-CN: '漫画列表'
	String get defaultTitle => '漫画列表';

	/// zh-CN: '缺少插件来源，无法加载列表'
	String get missingSource => '缺少插件来源，无法加载列表';

	/// zh-CN: '重新加载'
	String get reload => '重新加载';

	/// zh-CN: '加载失败，请重试。'
	String get loadFailedRetry => '加载失败，请重试。';

	/// zh-CN: '啥都没有'
	String get nothingHere => '啥都没有';

	/// zh-CN: '筛选'
	String get filter => '筛选';

	/// zh-CN: '子分类'
	String get subCategory => '子分类';

	/// zh-CN: '第$level级分类'
	String levelCategory({required Object level}) => '第${level}级分类';

	/// zh-CN: '缺少列表请求配置'
	String get missingListConfig => '缺少列表请求配置';

	/// zh-CN: '列表请求缺少 fnPath'
	String get missingFnPath => '列表请求缺少 fnPath';
}

// Path: comicEntry
class Translations$comicEntry$zh_CN {
	Translations$comicEntry$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '看到第 $page 页'
	String seenAtPage({required Object page}) => '看到第 ${page} 页';

	/// zh-CN: '更新: $time'
	String updatedAt({required Object time}) => '更新: ${time}';

	/// zh-CN: '完结'
	String get finished => '完结';

	/// zh-CN: '连载中'
	String get ongoing => '连载中';

	/// zh-CN: '喜欢 $count'
	String likes({required Object count}) => '喜欢 ${count}';

	/// zh-CN: '浏览 $count'
	String views({required Object count}) => '浏览 ${count}';

	/// zh-CN: '删除收藏'
	String get deleteFavorite => '删除收藏';

	/// zh-CN: '确定要删除（$title）的收藏记录吗？'
	String deleteFavoriteConfirm({required Object title}) => '确定要删除（${title}）的收藏记录吗？';

	/// zh-CN: '删除历史记录'
	String get deleteHistory => '删除历史记录';

	/// zh-CN: '确定要删除（$title）的历史记录吗？'
	String deleteHistoryConfirm({required Object title}) => '确定要删除（${title}）的历史记录吗？';

	/// zh-CN: '删除下载记录'
	String get deleteDownload => '删除下载记录';

	/// zh-CN: '确定要删除（$title）的下载记录及文件吗？'
	String deleteDownloadConfirm({required Object title}) => '确定要删除（${title}）的下载记录及文件吗？';

	/// zh-CN: '删除失败'
	String get deleteFailed => '删除失败';

	/// zh-CN: '汉化'
	String get translationBadgeTranslated => '汉化';

	/// zh-CN: '中文'
	String get translationBadgeChinese => '中文';

	/// zh-CN: '生肉'
	String get translationBadgeRaw => '生肉';

	/// zh-CN: '未读'
	String get unread => '未读';

	/// zh-CN: '$label · 标签命中「$keyword」'
	String translationTooltipTag({required Object label, required Object keyword}) => '${label} · 标签命中「${keyword}」';

	/// zh-CN: '$label · 标题命中「$keyword」'
	String translationTooltipTitle({required Object label, required Object keyword}) => '${label} · 标题命中「${keyword}」';

	/// zh-CN: '继续阅读'
	String get resumeRead => '继续阅读';

	/// zh-CN: '无法开始阅读，请稍后重试'
	String get readFailed => '无法开始阅读，请稍后重试';
}

// Path: comicFollow
class Translations$comicFollow$zh_CN {
	Translations$comicFollow$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '追更'
	String get title => '追更';

	/// zh-CN: '加载失败：$result'
	String loadFailed({required Object result}) => '加载失败：${result}';

	/// zh-CN: '暂无追更漫画'
	String get empty => '暂无追更漫画';

	/// zh-CN: '在漫画详情页点击追更按钮即可加入'
	String get emptyHint => '在漫画详情页点击追更按钮即可加入';

	/// zh-CN: '取消追更'
	String get unfollow => '取消追更';

	/// zh-CN: '确定不再追更《$title》吗？'
	String unfollowConfirm({required Object title}) => '确定不再追更《${title}》吗？';

	/// zh-CN: '已取消追更'
	String get unfollowed => '已取消追更';

	/// zh-CN: '全部'
	String get all => '全部';

	/// zh-CN: '已更新未看'
	String get unread => '已更新未看';

	/// zh-CN: '排序'
	String get sort => '排序';

	/// zh-CN: '最后阅读'
	String get lastRead => '最后阅读';

	/// zh-CN: '最近检测'
	String get lastUpdate => '最近检测';

	/// zh-CN: '检测时间：$time'
	String checkTime({required Object time}) => '检测时间：${time}';

	/// zh-CN: '尚未阅读'
	String get notRead => '尚未阅读';

	/// zh-CN: '看到：$chapter'
	String lastReadChapter({required Object chapter}) => '看到：${chapter}';

	/// zh-CN: '最新：$count 话 / $chapter'
	String latestChapter({required Object count, required Object chapter}) => '最新：${count} 话 / ${chapter}';

	/// zh-CN: '暂无已更新未看内容'
	String get noUnread => '暂无已更新未看内容';

	/// zh-CN: '显示全部'
	String get showAll => '显示全部';

	/// zh-CN: '最新章节获取失败'
	String get latestChapterFailed => '最新章节获取失败';

	/// zh-CN: '新增 $diff 话，共 $total 话'
	String newChapters({required Object diff, required Object total}) => '新增 ${diff} 话，共 ${total} 话';

	/// zh-CN: '新增 $diff 话未阅读，共 $total 话'
	String newUnreadChapters({required Object diff, required Object total}) => '新增 ${diff} 话未阅读，共 ${total} 话';

	/// zh-CN: '最新 $count 话'
	String latestCount({required Object count}) => '最新 ${count} 话';

	/// zh-CN: '获取失败'
	String get fetchFailed => '获取失败';

	/// zh-CN: '新增 $diff 话'
	String newChaptersShort({required Object diff}) => '新增 ${diff} 话';

	/// zh-CN: '新增 $diff 话未阅读'
	String newUnreadChaptersShort({required Object diff}) => '新增 ${diff} 话未阅读';

	/// zh-CN: '更新'
	String get update => '更新';

	/// zh-CN: '重试'
	String get retry => '重试';

	/// zh-CN: '已看 $read / 共 $total 话'
	String readProgress({required Object read, required Object total}) => '已看 ${read} / 共 ${total} 话';

	/// zh-CN: '共 $total 话'
	String readProgressUnknown({required Object total}) => '共 ${total} 话';

	/// zh-CN: '刚刚检测'
	String get updatedJustNow => '刚刚检测';

	/// zh-CN: '$minutes 分钟前检测'
	String updatedMinutesAgo({required Object minutes}) => '${minutes} 分钟前检测';

	/// zh-CN: '$hours 小时前检测'
	String updatedHoursAgo({required Object hours}) => '${hours} 小时前检测';

	/// zh-CN: '$days 天前检测'
	String updatedDaysAgo({required Object days}) => '${days} 天前检测';

	/// zh-CN: '$minutes 分钟前读过'
	String lastReadMinutesAgo({required Object minutes}) => '${minutes} 分钟前读过';

	/// zh-CN: '$hours 小时前读过'
	String lastReadHoursAgo({required Object hours}) => '${hours} 小时前读过';

	/// zh-CN: '$days 天前读过'
	String lastReadDaysAgo({required Object days}) => '${days} 天前读过';

	/// zh-CN: '检测失败，点击重试'
	String get checkFailedTapRetry => '检测失败，点击重试';

	/// zh-CN: '$count 话未读'
	String unreadCountBadge({required Object count}) => '${count} 话未读';

	/// zh-CN: '全部标为已读'
	String get markAllReadHint => '全部标为已读';

	/// zh-CN: '已全部标为已读'
	String get markAllReadDone => '已全部标为已读';

	/// zh-CN: '漫画更新提醒'
	String get updateChannelName => '漫画更新提醒';

	/// zh-CN: '追更漫画检测到新章节时推送'
	String get updateChannelDesc => '追更漫画检测到新章节时推送';

	/// zh-CN: '追更更新'
	String get updateTitle => '追更更新';

	/// zh-CN: '有 1 部漫画更新'
	String get updatedComicsSingle => '有 1 部漫画更新';

	/// zh-CN: '有 $count 部漫画更新'
	String updatedComicsMultiple({required Object count}) => '有 ${count} 部漫画更新';

	/// zh-CN: '有 $count 部追更漫画更新了'
	String updateBodyMultiple({required Object count}) => '有 ${count} 部追更漫画更新了';

	/// zh-CN: '有 1 部追更漫画更新了'
	String get updateBodySingle => '有 1 部追更漫画更新了';
}

// Path: changelog
class Translations$changelog$zh_CN {
	Translations$changelog$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '更新日志'
	String get title => '更新日志';

	/// zh-CN: '加载失败'
	String get loadFailed => '加载失败';

	/// zh-CN: '加载失败: $error'
	String loadFailedWithError({required Object error}) => '加载失败: ${error}';

	/// zh-CN: '无法打开链接: $url'
	String cannotOpenLink({required Object url}) => '无法打开链接: ${url}';

	/// zh-CN: '加载失败，请检查网络'
	String get checkNetwork => '加载失败，请检查网络';

	/// zh-CN: '重试'
	String get retry => '重试';

	/// zh-CN: '暂无更新日志'
	String get empty => '暂无更新日志';

	/// zh-CN: '发布于 $date'
	String publishedAt({required Object date}) => '发布于 ${date}';

	/// zh-CN: '在浏览器中查看'
	String get viewInBrowser => '在浏览器中查看';

	/// zh-CN: '附件下载'
	String get attachments => '附件下载';
}

// Path: webview
class Translations$webview$zh_CN {
	Translations$webview$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '网页'
	String get title => '网页';

	/// zh-CN: '无法打开链接: $uri'
	String cannotOpenLink({required Object uri}) => '无法打开链接: ${uri}';

	/// zh-CN: '链接无效，无法打开网页'
	String get invalidLink => '链接无效，无法打开网页';

	/// zh-CN: '(空链接)'
	String get emptyLink => '(空链接)';

	/// zh-CN: '网页加载失败'
	String get loadFailed => '网页加载失败';

	/// zh-CN: '重试'
	String get retry => '重试';

	/// zh-CN: '外部浏览器打开'
	String get openInExternalBrowser => '外部浏览器打开';

	/// zh-CN: 'WebView 窗口已关闭'
	String get windowClosed => 'WebView 窗口已关闭';

	/// zh-CN: '网页已在独立窗口中打开'
	String get openedInExternalWindow => '网页已在独立窗口中打开';

	/// zh-CN: '返回'
	String get back => '返回';

	/// zh-CN: '关闭 WebView 窗口'
	String get closeWindow => '关闭 WebView 窗口';

	/// zh-CN: '加载失败（$error）'
	String loadError({required Object error}) => '加载失败（${error}）';

	/// zh-CN: '服务器返回异常状态码：$statusCode'
	String httpErrorStatus({required Object statusCode}) => '服务器返回异常状态码：${statusCode}';
}

// Path: oldRanking
class Translations$oldRanking$zh_CN {
	Translations$oldRanking$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '哔咔排行榜'
	String get bikaRanking => '哔咔排行榜';

	/// zh-CN: '禁漫排行榜'
	String get jmRanking => '禁漫排行榜';

	/// zh-CN: '切换'
	String get switchSource => '切换';
}

// Path: login
class Translations$login$zh_CN {
	Translations$login$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '登录'
	String get title => '登录';

	/// zh-CN: '缺少插件标识，无法打开登录页'
	String get missingPluginId => '缺少插件标识，无法打开登录页';

	/// zh-CN: '登录配置加载失败: $error'
	String loadConfigFailed({required Object error}) => '登录配置加载失败: ${error}';

	/// zh-CN: '插件返回的登录字段不足'
	String get insufficientFields => '插件返回的登录字段不足';

	/// zh-CN: '用户名或密码错误，请重新输入'
	String get invalidCredentials => '用户名或密码错误，请重新输入';

	/// zh-CN: '登录配置未就绪，请稍后重试'
	String get configNotReady => '登录配置未就绪，请稍后重试';

	/// zh-CN: '正在登录，请耐心等待...'
	String get loggingIn => '正在登录，请耐心等待...';

	/// zh-CN: '登录成功'
	String get loginSuccess => '登录成功';

	/// zh-CN: '登录失败'
	String get loginFailed => '登录失败';

	/// zh-CN: '登录'
	String get loginButton => '登录';

	/// zh-CN: '重试'
	String get retry => '重试';

	/// zh-CN: '请填写 $label'
	String requiredFieldEmpty({required Object label}) => '请填写 ${label}';

	/// zh-CN: '该插件暂未适配新版登录页，请前往插件设置中填写账号信息'
	String get loginNotSupported => '该插件暂未适配新版登录页，请前往插件设置中填写账号信息';

	/// zh-CN: '看不清？点击刷新'
	String get captchaTapToRefresh => '看不清？点击刷新';

	/// zh-CN: '验证码加载中...'
	String get captchaLoading => '验证码加载中...';

	/// zh-CN: '验证码加载失败，点击重试'
	String get captchaLoadFailed => '验证码加载失败，点击重试';
}

// Path: fontSetting
class Translations$fontSetting$zh_CN {
	Translations$fontSetting$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '字体设置'
	String get title => '字体设置';

	/// zh-CN: '清空'
	String get clear => '清空';

	/// zh-CN: '选一个默认字体即可应用到全局；需要微调个别字重时再单独覆盖。'
	String get hint => '选一个默认字体即可应用到全局；需要微调个别字重时再单独覆盖。';

	/// zh-CN: '系统默认'
	String get modeSystem => '系统默认';

	/// zh-CN: '使用应用默认字体栈，无需任何操作。'
	String get modeSystemHint => '使用应用默认字体栈，无需任何操作。';

	/// zh-CN: '系统已装字体'
	String get modeFamily => '系统已装字体';

	/// zh-CN: '输入系统里已安装字体的家族名（如 LXGW WenKai）直接引用，未命中时回退系统默认；桌面端最可靠。'
	String get modeFamilyHint => '输入系统里已安装字体的家族名（如 LXGW WenKai）直接引用，未命中时回退系统默认；桌面端最可靠。';

	/// zh-CN: '字体文件'
	String get modeFile => '字体文件';

	/// zh-CN: '整个应用共用这一个文件，粗体等字重由系统模拟。'
	String get modeFileHint => '整个应用共用这一个文件，粗体等字重由系统模拟。';

	/// zh-CN: '选择字体家族'
	String get familyPickPrompt => '选择字体家族';

	/// zh-CN: '选择系统字体'
	String get familyPickerTitle => '选择系统字体';

	/// zh-CN: '搜索字体家族…'
	String get familySearchHint => '搜索字体家族…';

	/// zh-CN: '使用「$name」'
	String familyManualUse({required Object name}) => '使用「${name}」';

	/// zh-CN: '没有匹配的字体'
	String get familyEmpty => '没有匹配的字体';

	/// zh-CN: '正在读取系统字体…'
	String get familyLoading => '正在读取系统字体…';

	/// zh-CN: '默认字体'
	String get defaultFont => '默认字体';

	/// zh-CN: '整个应用共用这一个文件，粗体等字重由系统模拟。'
	String get defaultFontHint => '整个应用共用这一个文件，粗体等字重由系统模拟。';

	/// zh-CN: '字重覆盖'
	String get overrides => '字重覆盖';

	/// zh-CN: '可选：为个别字重指定不同文件，未覆盖的字重使用最接近的已配置字体。'
	String get overridesHint => '可选：为个别字重指定不同文件，未覆盖的字重使用最接近的已配置字体。';

	/// zh-CN: '字体加载失败'
	String get loadFailed => '字体加载失败';

	/// zh-CN: '已清除'
	String get cleared => '已清除';

	/// zh-CN: '已保存'
	String get saved => '已保存';

	/// zh-CN: '已清空'
	String get allCleared => '已清空';

	/// zh-CN: '未选择文件'
	String get noFileSelected => '未选择文件';

	/// zh-CN: '清除'
	String get clearFile => '清除';

	/// zh-CN: '选择文件'
	String get selectFile => '选择文件';

	/// zh-CN: 'Innovation in China 中国智造，慧及全球 0123456789'
	String get sampleText => 'Innovation in China 中国智造，慧及全球 0123456789';
}

// Path: download
class Translations$download$zh_CN {
	Translations$download$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '下载任务'
	String get title => '下载任务';

	/// zh-CN: '开始下载'
	String get startDownload => '开始下载';

	/// zh-CN: '请选择要下载的章节'
	String get selectChaptersPrompt => '请选择要下载的章节';

	/// zh-CN: '已选 $selected / 共 $total 章'
	String selectedCount({required Object selected, required Object total}) => '已选 ${selected} / 共 ${total} 章';

	/// zh-CN: '本地已有 $count 章'
	String downloadedCount({required Object count}) => '本地已有 ${count} 章';

	/// zh-CN: '跳过已下载'
	String get skipDownloaded => '跳过已下载';

	/// zh-CN: '本地已有 $count 章，已跳过'
	String skippedAlreadyDownloaded({required Object count}) => '本地已有 ${count} 章，已跳过';

	/// zh-CN: '开始下载 $started 章，跳过 $skipped 章（本地已有）'
	String startedWithSkipped({required Object started, required Object skipped}) => '开始下载 ${started} 章，跳过 ${skipped} 章（本地已有）';

	/// zh-CN: '下载这本漫画'
	String get optionsTitle => '下载这本漫画';

	/// zh-CN: '下载整本'
	String get optionWholeBook => '下载整本';

	/// zh-CN: '全部 $count 章'
	String optionWholeBookCounted({required Object count}) => '全部 ${count} 章';

	/// zh-CN: '全部章节'
	String get optionWholeBookPlain => '全部章节';

	/// zh-CN: '下载最近 $count 章'
	String optionLatest({required Object count}) => '下载最近 ${count} 章';

	/// zh-CN: '按章节序号取最新的几章'
	String get optionLatestSubtitle => '按章节序号取最新的几章';

	/// zh-CN: '手动选章节'
	String get optionPicker => '手动选章节';

	/// zh-CN: '逐章勾选，也可全选'
	String get optionPickerPlain => '逐章勾选，也可全选';

	/// zh-CN: '「整本」与「最近 N 章」会自动跳过本地已有的章节'
	String get optionSkipHint => '「整本」与「最近 N 章」会自动跳过本地已有的章节';

	/// zh-CN: '全部'
	String get filterAll => '全部';

	/// zh-CN: '当前筛选没有任务'
	String get filterNoMatches => '当前筛选没有任务';

	/// zh-CN: '还剩 $count 章'
	String overviewRemaining({required Object count}) => '还剩 ${count} 章';

	/// zh-CN: '已下 $done/$total 页'
	String overviewPages({required Object done, required Object total}) => '已下 ${done}/${total} 页';

	/// zh-CN: '失败 $count 章'
	String overviewFailed({required Object count}) => '失败 ${count} 章';

	/// zh-CN: '全部漫画'
	String get comicScopeAll => '全部漫画';

	/// zh-CN: '$name（$count 章）'
	String comicScopeCounted({required Object name, required Object count}) => '${name}（${count} 章）';

	/// zh-CN: '下载任务已启动'
	String get taskStarted => '下载任务已启动';

	/// zh-CN: '下载任务启动失败，$error'
	String taskStartFailed({required Object error}) => '下载任务启动失败，${error}';

	/// zh-CN: '暂无下载任务'
	String get noTasks => '暂无下载任务';

	/// zh-CN: '正在下载'
	String get downloading => '正在下载';

	/// zh-CN: '等待中 ($count)'
	String pending({required Object count}) => '等待中 (${count})';

	/// zh-CN: '失败 ($count)'
	String failedTasks({required Object count}) => '失败 (${count})';

	/// zh-CN: '已暂停 ($count)'
	String pausedTasks({required Object count}) => '已暂停 (${count})';

	/// zh-CN: '优先下载'
	String get pinTask => '优先下载';

	/// zh-CN: '取消优先'
	String get unpinTask => '取消优先';

	/// zh-CN: '已排到队首'
	String get taskPinned => '已排到队首';

	/// zh-CN: '已取消优先'
	String get taskUnpinned => '已取消优先';

	/// zh-CN: '已删除任务'
	String get taskDeleted => '已删除任务';

	/// zh-CN: '删除当前章节后，会删除下载记录，是否确认删除？'
	String get deleteLastChapterContent => '删除当前章节后，会删除下载记录，是否确认删除？';

	/// zh-CN: '取消任务'
	String get cancelTask => '取消任务';

	/// zh-CN: '确定要取消下载 $comicName 吗？'
	String cancelTaskConfirm({required Object comicName}) => '确定要取消下载 ${comicName} 吗？';

	/// zh-CN: '已暂停'
	String get paused => '已暂停';

	/// zh-CN: '已完成'
	String get completed => '已完成';

	/// zh-CN: '失败'
	String get failed => '失败';

	/// zh-CN: '全部开始'
	String get startAll => '全部开始';

	/// zh-CN: '全部暂停'
	String get pauseAll => '全部暂停';

	/// zh-CN: '全部取消'
	String get cancelAll => '全部取消';

	/// zh-CN: '确定要取消全部 $count 个下载任务吗？已下载的章节图片会一并删除。'
	String cancelAllConfirm({required Object count}) => '确定要取消全部 ${count} 个下载任务吗？已下载的章节图片会一并删除。';

	/// zh-CN: '清除已完成'
	String get clearCompleted => '清除已完成';

	/// zh-CN: '紧凑视图'
	String get viewModeCompact => '紧凑视图';

	/// zh-CN: '完整视图'
	String get viewModeComfortable => '完整视图';

	/// zh-CN: '获取漫画信息中...'
	String get statusFetchingComicInfo => '获取漫画信息中...';

	/// zh-CN: '下载封面中...'
	String get statusDownloadingCover => '下载封面中...';

	/// zh-CN: '获取章节信息中...'
	String get statusFetchingChapterInfo => '获取章节信息中...';

	/// zh-CN: '获取章节信息中... ($completed/$total, $percent%)'
	String statusFetchingChapterInfoProgress({required Object completed, required Object total, required Object percent}) => '获取章节信息中... (${completed}/${total}, ${percent}%)';

	/// zh-CN: '当前章节下载进度: $percent%'
	String statusDownloadProgress({required Object percent}) => '当前章节下载进度: ${percent}%';

	/// zh-CN: '当前章节下载进度: 100%'
	String get statusDownloadProgressComplete => '当前章节下载进度: 100%';

	/// zh-CN: '已下载 $completed/$total 页'
	String progressPages({required Object completed, required Object total}) => '已下载 ${completed}/${total} 页';

	/// zh-CN: '已下载 $completed/$total 页 · $speed'
	String progressPagesWithSpeed({required Object completed, required Object total, required Object speed}) => '已下载 ${completed}/${total} 页 · ${speed}';

	/// zh-CN: '同时下载 $count 个任务 · $message'
	String parallelTaskProgress({required Object count, required Object message}) => '同时下载 ${count} 个任务 · ${message}';

	/// zh-CN: '下载设置'
	String get settingsTitle => '下载设置';

	/// zh-CN: '$chapters 章 · 每章 $images 图 · 间隔 $delayMs ms'
	String settingsValueSummary({required Object chapters, required Object images, required Object delayMs}) => '${chapters} 章 · 每章 ${images} 图 · 间隔 ${delayMs} ms';

	/// zh-CN: '当前最多同时请求 $count 张图（同时下载章节数 × 单章节图片并发）'
	String settingsBudgetHint({required Object count}) => '当前最多同时请求 ${count} 张图（同时下载章节数 × 单章节图片并发）';

	/// zh-CN: '已离线漫画'
	String get offlineTitle => '已离线漫画';

	/// zh-CN: '还没有已下载的漫画'
	String get offlineEmpty => '还没有已下载的漫画';

	/// zh-CN: '统计占用'
	String get offlineMeasureSize => '统计占用';

	/// zh-CN: '统计中…'
	String get offlineMeasuring => '统计中…';

	/// zh-CN: '共 $size'
	String offlineTotalSize({required Object size}) => '共 ${size}';

	/// zh-CN: '已下 $completed/$total 章'
	String offlineChapterCount({required Object completed, required Object total}) => '已下 ${completed}/${total} 章';

	/// zh-CN: '已下 $count 章'
	String offlineChapterCountOnly({required Object count}) => '已下 ${count} 章';

	/// zh-CN: '漫画进度: $completedChapters/$totalChapters 章，当前章节: $currentChapterCompletedImages/$currentChapterTotalImages 页'
	String statusComicProgress({required Object completedChapters, required Object totalChapters, required Object currentChapterCompletedImages, required Object currentChapterTotalImages}) => '漫画进度: ${completedChapters}/${totalChapters} 章，当前章节: ${currentChapterCompletedImages}/${currentChapterTotalImages} 页';

	/// zh-CN: '漫画进度: $completedChapters/$totalChapters 章'
	String statusComicProgressChaptersOnly({required Object completedChapters, required Object totalChapters}) => '漫画进度: ${completedChapters}/${totalChapters} 章';

	/// zh-CN: '开始下载...'
	String get statusStartDownload => '开始下载...';

	/// zh-CN: '等待中'
	String get statusWaiting => '等待中';

	/// zh-CN: '取消中...'
	String get statusCancelling => '取消中...';

	/// zh-CN: '网络异常，将在 $seconds 秒后自动重试 ($attempt/$max)...'
	String statusAutoRetrying({required Object seconds, required Object attempt, required Object max}) => '网络异常，将在 ${seconds} 秒后自动重试 (${attempt}/${max})...';

	/// zh-CN: '触发源站风控节流，正在冷却休眠中...'
	String get statusThrottling => '触发源站风控节流，正在冷却休眠中...';

	/// zh-CN: '重试失败项'
	String get retryFailedParts => '重试失败项';

	/// zh-CN: '$comicName 下载完成'
	String toastDownloadComplete({required Object comicName}) => '${comicName} 下载完成';

	/// zh-CN: '$comicName 下载失败 $error'
	String toastDownloadFailed({required Object comicName, required Object error}) => '${comicName} 下载失败 ${error}';

	/// zh-CN: '$comicName 任务已存在'
	String toastTaskAlreadyExists({required Object comicName}) => '${comicName} 任务已存在';

	/// zh-CN: '下载完成'
	String get notificationCompleteTitle => '下载完成';

	/// zh-CN: '下载失败'
	String get notificationFailedTitle => '下载失败';
}

// Path: foregroundTask
class Translations$foregroundTask$zh_CN {
	Translations$foregroundTask$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '前台任务'
	String get channelName => '前台任务';

	/// zh-CN: '用于下载保活与后台保活，保持应用在后台继续运行'
	String get channelDescription => '用于下载保活与后台保活，保持应用在后台继续运行';

	/// zh-CN: '等待下载任务中...'
	String get waitingForTask => '等待下载任务中...';

	/// zh-CN: '正在保持后台运行'
	String get keepAliveRunning => '正在保持后台运行';

	/// zh-CN: '取消'
	String get cancel => '取消';

	/// zh-CN: '需要通知权限来启动前台任务，请在系统弹窗中允许通知权限'
	String get notificationPermissionRequired => '需要通知权限来启动前台任务，请在系统弹窗中允许通知权限';

	/// zh-CN: '无法启动前台任务：请先在系统设置中开启通知权限'
	String get cannotStartWithoutPermission => '无法启动前台任务：请先在系统设置中开启通知权限';

	/// zh-CN: '前台服务启动失败: $error'
	String startFailed({required Object error}) => '前台服务启动失败: ${error}';
}

// Path: notification
class Translations$notification$zh_CN {
	Translations$notification$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '请开启通知权限'
	String get permissionRequired => '请开启通知权限';

	/// zh-CN: '请在系统设置中开启通知权限'
	String get macPermissionRequired => '请在系统设置中开启通知权限';
}

// Path: update
class Translations$update$zh_CN {
	Translations$update$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '发现新版本'
	String get newVersion => '发现新版本';

	/// zh-CN: '前往GitHub'
	String get goToGitHub => '前往GitHub';

	/// zh-CN: '下载安装'
	String get downloadInstall => '下载安装';

	/// zh-CN: '下载失败，请稍后再试！'
	String get apkDownloadFailed => '下载失败，请稍后再试！';

	/// zh-CN: '请授予安装应用权限！'
	String get installPermissionRequired => '请授予安装应用权限！';

	/// zh-CN: '未知'
	String get unknownArch => '未知';
}

// Path: dialog
class Translations$dialog$zh_CN {
	Translations$dialog$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '隐藏到托盘或关闭程序'
	String get hideOrClose => '隐藏到托盘或关闭程序';

	/// zh-CN: '记住我的选择'
	String get rememberChoice => '记住我的选择';
}

// Path: shelfMenu
class Translations$shelfMenu$zh_CN {
	Translations$shelfMenu$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '打开'
	String get open => '打开';

	/// zh-CN: '继续阅读'
	String get resumeReading => '继续阅读';

	/// zh-CN: '在文件管理新页签打开'
	String get openInFileManagerTab => '在文件管理新页签打开';

	/// zh-CN: '复制标题'
	String get copyTitle => '复制标题';

	/// zh-CN: '复制链接'
	String get copyLink => '复制链接';

	/// zh-CN: '收藏'
	String get addFavorite => '收藏';

	/// zh-CN: '已在收藏中'
	String get alreadyFavorite => '已在收藏中';

	/// zh-CN: '取消收藏'
	String get removeFavorite => '取消收藏';

	/// zh-CN: '从历史记录移除'
	String get removeHistory => '从历史记录移除';

	/// zh-CN: '已复制标题「$title」'
	String copiedTitle({required Object title}) => '已复制标题「${title}」';

	/// zh-CN: '已复制链接「$link」'
	String copiedLink({required Object link}) => '已复制链接「${link}」';

	/// zh-CN: '已在文件管理新页签打开'
	String get fileManagerTabOpened => '已在文件管理新页签打开';

	/// zh-CN: '文件管理面板还没准备好，稍后再试'
	String get fileManagerTabUnavailable => '文件管理面板还没准备好，稍后再试';

	/// zh-CN: '这条漫画没有本地目录，无法在文件管理里打开'
	String get fileManagerTabNoLocalPath => '这条漫画没有本地目录，无法在文件管理里打开';

	/// zh-CN: '已收藏「$title」'
	String favoriteAdded({required Object title}) => '已收藏「${title}」';

	/// zh-CN: '已取消收藏「$title」'
	String favoriteRemoved({required Object title}) => '已取消收藏「${title}」';

	/// zh-CN: '已从历史记录移除「$title」'
	String historyRemoved({required Object title}) => '已从历史记录移除「${title}」';

	/// zh-CN: '取消收藏？'
	String get removeFavoriteConfirmTitle => '取消收藏？';

	/// zh-CN: '「$title」将从收藏库移除，源文件与阅读记录不受影响。'
	String removeFavoriteConfirmBody({required Object title}) => '「${title}」将从收藏库移除，源文件与阅读记录不受影响。';

	/// zh-CN: '移除历史记录？'
	String get removeHistoryConfirmTitle => '移除历史记录？';

	/// zh-CN: '「$title」将从阅读历史中移除，源文件不会被删除。'
	String removeHistoryConfirmBody({required Object title}) => '「${title}」将从阅读历史中移除，源文件不会被删除。';
}

// Path: video
class Translations$video$zh_CN {
	Translations$video$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '播放'
	String get play => '播放';

	/// zh-CN: '暂停'
	String get pause => '暂停';

	/// zh-CN: '后退 10 秒'
	String get backward => '后退 10 秒';

	/// zh-CN: '前进 10 秒'
	String get forward => '前进 10 秒';

	/// zh-CN: '循环：接下一页'
	String get loop => '循环：接下一页';

	/// zh-CN: '循环：本页重复'
	String get loopSingle => '循环：本页重复';

	/// zh-CN: '循环：关闭'
	String get loopOff => '循环：关闭';

	/// zh-CN: '倍速'
	String get speed => '倍速';

	/// zh-CN: '音量'
	String get volume => '音量';

	/// zh-CN: '已静音'
	String get muted => '已静音';

	/// zh-CN: '字幕'
	String get subtitles => '字幕';

	/// zh-CN: '关闭字幕'
	String get subtitleOff => '关闭字幕';

	/// zh-CN: '音轨'
	String get audio => '音轨';

	/// zh-CN: '关闭音轨'
	String get audioOff => '关闭音轨';

	/// zh-CN: '滤镜'
	String get filters => '滤镜';

	/// zh-CN: '重置滤镜'
	String get resetFilters => '重置滤镜';

	/// zh-CN: '亮度'
	String get brightness => '亮度';

	/// zh-CN: '对比度'
	String get contrast => '对比度';

	/// zh-CN: '饱和度'
	String get saturation => '饱和度';

	/// zh-CN: 'A-B 循环'
	String get abLoop => 'A-B 循环';

	/// zh-CN: '清除 A-B'
	String get abClear => '清除 A-B';

	/// zh-CN: '截图'
	String get screenshot => '截图';

	/// zh-CN: '只听声音'
	String get audioOnly => '只听声音';

	/// zh-CN: '快进档（翻页改成跳转）'
	String get seekMode => '快进档（翻页改成跳转）';

	/// zh-CN: '全屏'
	String get fullscreen => '全屏';

	/// zh-CN: '钉住控制条'
	String get pin => '钉住控制条';

	/// zh-CN: '信息'
	String get info => '信息';

	/// zh-CN: '下一帧'
	String get frameStepForward => '下一帧';

	/// zh-CN: '上一帧'
	String get frameStepBackward => '上一帧';

	/// zh-CN: '画中画'
	String get pip => '画中画';

	/// zh-CN: '视频播放'
	String get settingsSection => '视频播放';

	/// zh-CN: '自动播放'
	String get autoPlay => '自动播放';

	/// zh-CN: '翻到视频页就开始播放'
	String get autoPlayDesc => '翻到视频页就开始播放';

	/// zh-CN: '硬件解码'
	String get hwDecode => '硬件解码';

	/// zh-CN: '关闭可排查花屏与绿屏，代价是 CPU 占用上升'
	String get hwDecodeDesc => '关闭可排查花屏与绿屏，代价是 CPU 占用上升';

	/// zh-CN: '去隔行'
	String get deinterlace => '去隔行';

	/// zh-CN: '老录像带 / DVD 抓取源有横向梳状纹时打开'
	String get deinterlaceDesc => '老录像带 / DVD 抓取源有横向梳状纹时打开';

	/// zh-CN: '视频控制条融入底栏'
	String get integrateBottomBar => '视频控制条融入底栏';

	/// zh-CN: '将播放进度和视频控制整合进阅读底栏，随底栏一起呼出和收起'
	String get integrateBottomBarDesc => '将播放进度和视频控制整合进阅读底栏，随底栏一起呼出和收起';

	/// zh-CN: '控制条常显，不再在播放几秒后自动收起'
	String get pinDesc => '控制条常显，不再在播放几秒后自动收起';

	/// zh-CN: '动图当视频播'
	String get animatedVideo => '动图当视频播';

	/// zh-CN: '把 GIF / APNG 交给视频控制器，获得暂停、逐帧与进度拖动'
	String get animatedVideoDesc => '把 GIF / APNG 交给视频控制器，获得暂停、逐帧与进度拖动';

	/// zh-CN: '控制条自动隐藏'
	String get autoHide => '控制条自动隐藏';

	/// zh-CN: '倍速上限'
	String get maxRate => '倍速上限';

	/// zh-CN: '默认音量'
	String get defaultVolume => '默认音量';

	/// zh-CN: '自定义视频后缀'
	String get aliases => '自定义视频后缀';

	/// zh-CN: '未设置'
	String get aliasesEmpty => '未设置';

	/// zh-CN: '逗号分隔，例如：myvid, cbr-video'
	String get aliasesHint => '逗号分隔，例如：myvid, cbr-video';

	/// zh-CN: '输入后按逗号分隔；小写、最多 128 条、每条最长 16 字符'
	String get aliasesDialogHint => '输入后按逗号分隔；小写、最多 128 条、每条最长 16 字符';

	/// zh-CN: '媒体格式'
	String get mediaSection => '媒体格式';

	/// zh-CN: '图片格式表'
	String get imageFormats => '图片格式表';

	/// zh-CN: '视频格式表'
	String get videoFormats => '视频格式表';

	/// zh-CN: '填了就整体替换内置表，没列进来的后缀会连一页都不算；留空才用内置表'
	String get formatsHint => '填了就整体替换内置表，没列进来的后缀会连一页都不算；留空才用内置表';

	/// zh-CN: '字号'
	String get subSize => '字号';

	/// zh-CN: '底色'
	String get subBg => '底色';

	/// zh-CN: '底部位置'
	String get subBottom => '底部位置';

	/// zh-CN: '大号黄色'
	String get subLargeYellow => '大号黄色';

	/// zh-CN: '重置'
	String get reset => '重置';

	/// zh-CN: '时长'
	String get duration => '时长';

	/// zh-CN: '当前'
	String get position => '当前';

	/// zh-CN: '尺寸'
	String get size => '尺寸';

	/// zh-CN: '显示宽高比'
	String get dar => '显示宽高比';

	/// zh-CN: '帧率'
	String get fps => '帧率';

	/// zh-CN: '码率'
	String get bitrate => '码率';

	/// zh-CN: '视频编码'
	String get videoCodec => '视频编码';

	/// zh-CN: '音频编码'
	String get audioCodec => '音频编码';

	/// zh-CN: '音画漂移'
	String get avDrift => '音画漂移';

	/// zh-CN: '循环'
	String get loopMode => '循环';

	/// zh-CN: '倍速'
	String get playbackRate => '倍速';

	/// zh-CN: 'A-B'
	String get abRange => 'A-B';

	/// zh-CN: '外挂字幕'
	String get sidecarSubtitles => '外挂字幕';

	/// zh-CN: '—'
	String get notAvailable => '—';

	/// zh-CN: '这个视频条目取不到字节'
	String get noBytes => '这个视频条目取不到字节';

	/// zh-CN: '这一页播不了'
	String get cannotPlay => '这一页播不了';

	/// zh-CN: '动画化关键字'
	String get animatedKeywords => '动画化关键字';

	/// zh-CN: '逗号分隔，例如：[#dyna], [#动]'
	String get animatedKeywordsHint => '逗号分隔，例如：[#dyna], [#动]';

	/// zh-CN: '旋转'
	String get rotation => '旋转';
}

// Path: bindingEditor
class Translations$bindingEditor$zh_CN {
	Translations$bindingEditor$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '任意区域'
	String get anyArea => '任意区域';

	/// zh-CN: '旧操作绑定迁移失败，原配置已保留。可导出原文检查，或导入有效配置后重试。'
	String get migrationFailed => '旧操作绑定迁移失败，原配置已保留。可导出原文检查，或导入有效配置后重试。';

	/// zh-CN: '翻页'
	String get groupNavigation => '翻页';

	/// zh-CN: '画面'
	String get groupView => '画面';

	/// zh-CN: '界面'
	String get groupInterface => '界面';

	/// zh-CN: '播放'
	String get videoPlayback => '播放';

	/// zh-CN: '声音'
	String get videoAudio => '声音';

	/// zh-CN: '画面与字幕'
	String get videoDisplay => '画面与字幕';

	/// zh-CN: '全部'
	String get allActions => '全部';

	/// zh-CN: '已绑定'
	String get boundOnly => '已绑定';

	/// zh-CN: '未绑定'
	String get unassigned => '未绑定';

	/// zh-CN: '空格'
	String get spaceKey => '空格';

	/// zh-CN: '搜索全部动作或按键'
	String get searchAll => '搜索全部动作或按键';

	/// zh-CN: '已停用'
	String get disabled => '已停用';

	/// zh-CN: '另有 $count 条绑定'
	String moreBindings({required Object count}) => '另有 ${count} 条绑定';

	/// zh-CN: '搜索动作、分类、上下文或输入'
	String get search => '搜索动作、分类、上下文或输入';

	/// zh-CN: '全部分类'
	String get allCategories => '全部分类';

	/// zh-CN: '全部上下文'
	String get allContexts => '全部上下文';

	/// zh-CN: '没有匹配的动作'
	String get noResults => '没有匹配的动作';

	/// zh-CN: '添加绑定'
	String get addBinding => '添加绑定';

	/// zh-CN: '暂无绑定，添加一种输入开始配置'
	String get noBindings => '暂无绑定，添加一种输入开始配置';

	/// zh-CN: '输入设备'
	String get device => '输入设备';

	/// zh-CN: '上下文'
	String get context => '上下文';

	/// zh-CN: '忽略重复输入'
	String get ignoreRepeat => '忽略重复输入';

	/// zh-CN: '后续动作'
	String get followUps => '后续动作';

	/// zh-CN: '添加'
	String get add => '添加';

	/// zh-CN: '复制到'
	String get copyTo => '复制到';

	/// zh-CN: '绑定冲突'
	String get conflict => '绑定冲突';

	/// zh-CN: '同一上下文内的输入重复，请修改或停用其中一条。修正后自动保存。'
	String get conflictHint => '同一上下文内的输入重复，请修改或停用其中一条。修正后自动保存。';

	/// zh-CN: '已自动保存'
	String get saved => '已自动保存';

	/// zh-CN: '等待保存'
	String get pending => '等待保存';

	/// zh-CN: '配置未保存，请检查输入内容'
	String get invalid => '配置未保存，请检查输入内容';

	/// zh-CN: '录制'
	String get record => '录制';

	/// zh-CN: '在此区域操作，确认后应用录制结果。Esc 可取消；点击下方取消按钮可以录入 Esc。'
	String get recordHint => '在此区域操作，确认后应用录制结果。Esc 可取消；点击下方取消按钮可以录入 Esc。';

	/// zh-CN: '等待输入…'
	String get recordWaiting => '等待输入…';

	/// zh-CN: '键盘代码'
	String get keyCode => '键盘代码';

	/// zh-CN: '触发方式'
	String get trigger => '触发方式';

	/// zh-CN: '按下'
	String get down => '按下';

	/// zh-CN: '长按'
	String get hold => '长按';

	/// zh-CN: '释放时触发'
	String get instant => '释放时触发';

	/// zh-CN: '单击'
	String get click => '单击';

	/// zh-CN: '双击'
	String get doubleClick => '双击';

	/// zh-CN: '按下'
	String get press => '按下';

	/// zh-CN: '长按时长（毫秒）'
	String get duration => '长按时长（毫秒）';

	/// zh-CN: '移动容差（像素）'
	String get tolerance => '移动容差（像素）';

	/// zh-CN: '鼠标按钮'
	String get button => '鼠标按钮';

	/// zh-CN: '左键'
	String get leftButton => '左键';

	/// zh-CN: '中键'
	String get middleButton => '中键';

	/// zh-CN: '右键'
	String get rightButton => '右键';

	/// zh-CN: '后退键'
	String get backButton => '后退键';

	/// zh-CN: '前进键'
	String get forwardButton => '前进键';

	/// zh-CN: '向上'
	String get up => '向上';

	/// zh-CN: '向下'
	String get downDirection => '向下';

	/// zh-CN: '向左'
	String get left => '向左';

	/// zh-CN: '向右'
	String get right => '向右';

	/// zh-CN: '左滑'
	String get swipeLeft => '左滑';

	/// zh-CN: '右滑'
	String get swipeRight => '右滑';

	/// zh-CN: '上滑'
	String get swipeUp => '上滑';

	/// zh-CN: '下滑'
	String get swipeDown => '下滑';

	/// zh-CN: '点击'
	String get tap => '点击';

	/// zh-CN: '长按'
	String get longPress => '长按';

	/// zh-CN: '手指数'
	String get fingers => '手指数';

	/// zh-CN: '触控手势'
	String get gesture => '触控手势';

	/// zh-CN: '轨迹方向序列'
	String get directions => '轨迹方向序列';

	/// zh-CN: '移除最后方向'
	String get undoDirection => '移除最后方向';

	/// zh-CN: '手柄按钮编号'
	String get gamepadButton => '手柄按钮编号';

	/// zh-CN: '手柄配置可编辑和导入导出；当前平台尚未接入手柄事件。'
	String get gamepadHint => '手柄配置可编辑和导入导出；当前平台尚未接入手柄事件。';

	/// zh-CN: '此输入由轮盘或系统命令管理'
	String get managedInput => '此输入由轮盘或系统命令管理';

	/// zh-CN: '九宫格区域'
	String get area => '九宫格区域';

	/// zh-CN: '左上'
	String get topLeft => '左上';

	/// zh-CN: '中上'
	String get topCenter => '中上';

	/// zh-CN: '右上'
	String get topRight => '右上';

	/// zh-CN: '左中'
	String get middleLeft => '左中';

	/// zh-CN: '中心'
	String get middleCenter => '中心';

	/// zh-CN: '右中'
	String get middleRight => '右中';

	/// zh-CN: '左下'
	String get bottomLeft => '左下';

	/// zh-CN: '中下'
	String get bottomCenter => '中下';

	/// zh-CN: '右下'
	String get bottomRight => '右下';

	/// zh-CN: '键盘'
	String get keyboard => '键盘';

	/// zh-CN: '鼠标'
	String get mouse => '鼠标';

	/// zh-CN: '鼠标轨迹'
	String get mouseGesture => '鼠标轨迹';

	/// zh-CN: '滚轮'
	String get wheel => '滚轮';

	/// zh-CN: '触控'
	String get touch => '触控';

	/// zh-CN: '手柄'
	String get gamepad => '手柄';

	/// zh-CN: '轮盘'
	String get radial => '轮盘';

	/// zh-CN: '系统命令'
	String get command => '系统命令';

	/// zh-CN: '全局'
	String get global => '全局';

	/// zh-CN: '阅读器'
	String get reader => '阅读器';

	/// zh-CN: '视频'
	String get video => '视频';

	/// zh-CN: '面板'
	String get panel => '面板';

	/// zh-CN: '界面栏'
	String get shell => '界面栏';

	/// zh-CN: '编辑器'
	String get editor => '编辑器';

	/// zh-CN: '对话框'
	String get modal => '对话框';

	/// zh-CN: '上移'
	String get moveUp => '上移';

	/// zh-CN: '下移'
	String get moveDown => '下移';

	/// zh-CN: '收起绑定'
	String get collapse => '收起绑定';

	/// zh-CN: '展开绑定'
	String get expand => '展开绑定';

	/// zh-CN: '动作'
	String get actions => '动作';

	/// zh-CN: '动作列表'
	String get actionList => '动作列表';

	/// zh-CN: '绑定详情'
	String get bindingDetails => '绑定详情';

	/// zh-CN: '绑定'
	String get bindings => '绑定';

	/// zh-CN: '恢复默认'
	String get restore => '恢复默认';

	/// zh-CN: '清除筛选'
	String get resetFilters => '清除筛选';
}

// Path: plat
class Translations$plat$zh_CN {
	Translations$plat$zh_CN.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh-CN: '在上方打开'
	String get openAbove => '在上方打开';

	/// zh-CN: '在下方打开'
	String get openBelow => '在下方打开';

	/// zh-CN: '在左侧打开'
	String get openLeft => '在左侧打开';

	/// zh-CN: '在右侧打开'
	String get openRight => '在右侧打开';

	/// zh-CN: '关闭标签'
	String get closeTab => '关闭标签';
}

/// The flat map containing all translations for locale <zh-CN>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'workspace.laneTapExpandHint' => ({required Object title}) => '${title} (点击展开泳道)',
			'workspace.laneTapCollapseHint' => ({required Object title}) => '${title}（点按收起泳道）',
			'workspace.laneDragHint' => ({required Object title}) => '${title} （按住可拖动重排泳道）',
			'workspace.laneSortHint' => ({required Object title}) => '${title}（在泳道菜单中选择“编辑布局”可排序）',
			'workspace.allowedRange' => ({required Object min, required Object max}) => '允许 ${min}–${max}',
			'workspace.dockToName' => ({required Object label}) => '停靠${label}',
			'workspace.laneWidthPx' => ({required Object px}) => '泳道宽度：${px} px',
			'workspace.dockToLabel' => ({required Object label}) => '停靠到${label}',
			'workspace.slotCount' => ({required Object count}) => '${count} 格',
			'workspace.columnsPerRow' => ({required Object columns}) => '当前每行 ${columns} 格',
			'workspace.imagesCountBadge' => ({required Object n}) => '${n} 图',
			'workspace.highestPage' => ({required Object value}) => '最高 ${value}',
			'workspace.worksCount' => ({required Object n}) => '${n} 部',
			'workspace.sharePercent' => ({required Object v}) => '占 ${v}%',
			'workspace.heatLegendLow' => '少',
			'workspace.periodDetailLine' => ({required Object label, required Object count, required Object hours}) => '${label} · ${count} 条\n${hours}',
			'workspace.restoreNamed' => ({required Object title}) => '恢复「${title}」',
			'workspace.fullWidthFullHeight' => '全宽并撑满高度',
			'workspace.resizePreview' => ({required Object w, required Object h}) => '${w} × ${h} · 松开保存',
			'workspace.portSkippedLines' => ({required Object lines}) => '跳过的条目：\n${lines}',
			'workspace.streakNowDays' => ({required Object n}) => '当前 ${n} 天',
			'workspace.mostlyAt' => ({required Object period}) => '多在${period}',
			'workspace.monthsAgo' => ({required Object months}) => '${months} 个月前',
			'workspace.artbookCount' => ({required Object n}) => '${n} 部画册',
			'workspace.seenAtPage' => ({required Object pageNum}) => '看到 P.${pageNum}',
			'workspace.sourceMixItem' => ({required Object count, required Object percent}) => '${count} 条 · ${percent}%',
			'workspace.sourceMixHeader' => ({required Object n}) => '样本记录 · ${n} 个来源',
			'workspace.streakPointLine' => ({required Object date, required Object value}) => '${date}：连续 ${value} 天',
			'workspace.streakDaysLine' => ({required Object label, required Object value}) => '${label}：${value} 天',
			'workspace.insightHeaderExpand' => ({required Object label, required Object position, required Object total, required Object title}) => '${label} · ${position}/${total} · 展开${title}',
			'workspace.heatCellLine' => ({required Object weekday, required Object hour, required Object count}) => '${weekday} ${hour} · ${count} 条记录',
			'workspace.heatPeakLabel' => ({required Object weekday, required Object hour}) => '高峰 · ${weekday} ${hour}',
			'workspace.heatPeakShort' => ({required Object weekday, required Object hour}) => '高峰 ${weekday} ${hour}',
			'workspace.compactHeatmapExpandHours' => ({required Object day, required Object hours}) => '${day} · 每格 ${hours} 小时 · 展开阅读热力',
			'workspace.hoursPerCell' => ({required Object hours}) => '${hours} 小时/格',
			'workspace.compactHeatmapExpand' => ({required Object day}) => '${day} · 展开阅读热力',
			'workspace.busiestPeriodLabel' => ({required Object period}) => '${period}记录最多',
			'workspace.weekdayRecordLine' => ({required Object day, required Object count}) => '周${day}：${count} 条记录',
			'workspace.busiestWeekdayLabel' => ({required Object day}) => '周${day}最活跃',
			'workspace.selectedLastReadLines' => ({required Object key, required Object count}) => '${key} · ${count} 条最后阅读记录',
			'workspace.dayRecordLine' => ({required Object key, required Object count}) => '${key}：${count} 条记录',
			'workspace.activeDaysCount' => ({required Object n}) => '${n} 天活跃',
			'workspace.collapseNamed' => ({required Object title}) => '折叠${title}',
			'workspace.insertTarget' => ({required Object name}) => '插入至：${name}',
			'workspace.activeSwitchCount' => ({required Object activeCount}) => '${activeCount} 项开启',
			'workspace.switchToastActiveOf3' => ({required Object activeCount}) => '已开 ${activeCount} / 3 项',
			'workspace.peakAllocated' => ({required Object value}) => '峰值 ${value}',
			'workspace.failedWith' => ({required Object error}) => '失败 · ${error}',
			'workspace.registeredCount' => ({required Object n}) => '共 ${n} 个在册',
			'workspace.readyOfTotal' => ({required Object ready, required Object total}) => '${ready} / ${total} 就绪',
			'workspace.sourceCountLabel' => ({required Object n}) => '${n} 个图源',
			'workspace.fileKindLabel' => ({required Object kind}) => '${kind} 文件',
			'workspace.passthroughDepthLabel' => ({required Object value}) => '穿透深度：${value}',
			'workspace.contentLayoutLabel' => ({required Object value}) => '内容布局：${value}',
			'workspace.sortFieldLabel' => ({required Object value}) => '排序：${value}',
			'workspace.entryStyleLabel' => ({required Object value}) => '条目样式：${value}',
			'workspace.filterTypeLabel' => ({required Object value}) => '类型：${value}',
			'workspace.depthLimitLabel' => ({required Object n}) => '层数 ≤${n}',
			'workspace.notSearchedBelow' => ({required Object n}) => '第 ${n} 层以下未搜',
			'workspace.searchScanned' => ({required Object n}) => '已看 ${n}',
			'workspace.searchHits' => ({required Object n}) => '命中 ${n}',
			'workspace.tenThousandRecords' => ({required Object v}) => '${v} 万条',
			'workspace.slowScanNote' => ({required Object label}) => '${label} · 慢盘上要几十秒，结果扫完一次给出',
			'workspace.recursiveSearchScanned' => ({required Object scanned}) => '正在递归搜索 · 已扫 ${scanned}',
			'workspace.restoreTabTitle' => ({required Object title}) => '恢复页签：${title}',
			'workspace.selectedCount' => ({required Object n}) => '已选 ${n} 项',
			'workspace.filteringBy' => ({required Object query}) => '筛选: ${query}',
			'workspace.pageN' => ({required Object n}) => '页面 ${n}',
			'workspace.openLocalComicFailed' => ({required Object error}) => '打开本地漫画出错: ${error}',
			'workspace.daysAgo' => ({required Object days}) => '${days} 天前',
			'workspace.childCount' => ({required Object n}) => '${n} 项',
			'workspace.noMatchThisLevelSuggest' => ({required Object query}) => '当前这一层没有匹配「${query}」的条目，可用上面的「在子目录里搜」往下找',
			'workspace.noMatchInSubdirs' => ({required Object query}) => '子目录里没有匹配「${query}」的条目',
			'workspace.tasksCount' => ({required Object n}) => '${n} 个',
			'workspace.booksCount' => ({required Object n}) => '${n} 本',
			'workspace.builtinWord' => '内置',
			'workspace.onlineSourceFrom' => ({required Object from}) => '在线图源 · ${from}',
			'workspace.pagesRemaining' => ({required Object n}) => '还剩 ${n} 页',
			'workspace.currentOfTotalPages' => ({required Object total}) => '当前页 · 共 ${total} 页',
			'workspace.dateMD' => ({required Object month, required Object day}) => '${month}月${day}日',
			'workspace.dateYMD' => ({required Object year, required Object month, required Object day}) => '${year}年${month}月${day}日',
			'workspace.heatmapCell' => ({required Object weekday, required Object range, required Object count}) => '${weekday} ${range}：${count} 条记录',
			'workspace.theseCountItems' => ({required Object count}) => '这 ${count} 项',
			'workspace.duplicateInFileCount' => ({required Object n}) => '文件内重复 ${n} 条',
			'workspace.keptLocalCount' => ({required Object n}) => '保留本地 ${n} 条',
			'workspace.progressUpdatedCount' => ({required Object n}) => '更新进度 ${n} 条',
			'workspace.skippedCount' => ({required Object n}) => '跳过 ${n} 条',
			'workspace.alreadyPresentCount' => ({required Object n}) => '已存在 ${n} 条',
			'workspace.revivedCount' => ({required Object n}) => '复活 ${n} 条',
			'workspace.addedCount' => ({required Object n}) => '新增 ${n} 条',
			'workspace.keyMismatch' => ({required Object expected}) => 'uniqueKey 与 source:comicId 不一致，应为 ${expected}',
			'workspace.itemNumber' => ({required Object n}) => '第 ${n} 条',
			'workspace.unsupportedFormatVersion' => ({required Object version}) => '不支持的格式版本 ${version}',
			'workspace.invalidJson' => ({required Object error}) => '不是合法的 JSON：${error}',
			'workspace.portImportFailed' => ({required Object label, required Object error}) => '导入${label}失败：${error}',
			'workspace.portFileUnreadable' => ({required Object error}) => '读不了这个文件：${error}',
			'workspace.portExportFailed' => ({required Object label, required Object error}) => '导出${label}失败：${error}',
			'workspace.portExportDone' => ({required Object count, required Object label, required Object target}) => '已导出 ${count} 条${label}\n${target}',
			'workspace.portListEmpty' => ({required Object label}) => '${label}还是空的，没有可导出的内容',
			'workspace.opFirstFailure' => ({required Object summary, required Object failure}) => '${summary}　首个失败原因：${failure}',
			'workspace.pickPasteTarget' => ({required Object verb, required Object subject}) => '${verb}${subject}，选个目录粘贴',
			'workspace.movedToTrashSystem' => ({required Object subject, required Object hint}) => '已把${subject}移到回收站，${hint}（在系统废纸篓里）',
			'workspace.movedToTrash' => ({required Object subject, required Object hint}) => '已把${subject}移到回收站，${hint}',
			'workspace.cannotOpenFileManager' => ({required Object error}) => '打不开文件管理器：${error}',
			'workspace.pathsCopied' => ({required Object count}) => '已复制 ${count} 条路径',
			'workspace.deleteConfirmSubject' => ({required Object subject, required Object outcome}) => '${subject}将被删除。${outcome}。',
			'workspace.deleteForeverWarning' => ({required Object subject}) => '${subject}将被永久删除，不进入回收站，也无法撤销。',
			'workspace.loadingShort' => '正在加载',
			'workspace.readingHubTitle' => '阅读中枢',
			'workspace.chapterIdLabel' => '章节 ID',
			'workspace.portraitFormat' => '竖幅',
			'workspace.peep' => '窥视',
			'workspace.topTags' => '高频标签',
			'workspace.libraryLabel' => '馆藏',
			'workspace.preloadPath' => '预加载路径',
			'workspace.preloadStatus' => '预加载状态',
			'workspace.topBarIsThatRow' => '顶栏 = 退出 / 书名 / 切模式 / 重置布局那一行',
			'workspace.pagePath' => '页面路径',
			'workspace.pageTemplateBookVars' => '页面模板同样可以使用 {{book.*}} 变量；点击任一变量胶囊可直接插入。',
			'workspace.pageTitleTemplate' => '页面标题模板',
			'workspace.pageFileName' => '页面文件名',
			'workspace.pageToastTemplate' => '页面提示模板',
			'workspace.pageDescriptionTemplate' => '页面描述模板',
			'workspace.pageNavigation' => '页面导航',
			'workspace.pageListNotReady' => '页表未就绪',
			'workspace.pageListTotal' => '页表总量',
			'workspace.pageList' => '页表',
			'workspace.pageNumber' => '页码',
			'workspace.pageUrl' => '页地址',
			'workspace.pagesModified' => '页修改',
			'workspace.audioLabel' => '音频',
			'workspace.areaBasis' => '面积依据',
			'workspace.panelBarFloating' => '面板栏：悬浮',
			'workspace.panelBarHint' => '面板栏（拖动换边或转悬浮，右键或长按设置）',
			'workspace.hideLaneWidthBadge' => '隐藏泳道宽度徽标',
			'workspace.hideWorkspaceTopBar' => '隐藏工作台顶栏',
			'workspace.refreshPerPageNoGuessing' => '随翻页刷新；量不到的项不猜',
			'workspace.randomRoam' => '随机漫游',
			'workspace.randomLabel' => '随机',
			'workspace.matchRelativePath' => '除条目名外，连同它在搜索根之下的相对路径一起匹配',
			'workspace.confineToLane' => '限制在泳道内',
			'workspace.confineToThisLane' => '限制在本泳道',
			'workspace.readingProgressPercent' => '阅读进度（%）',
			'workspace.readingProgressLabel' => '阅读进度',
			'workspace.readingHeat' => '阅读热力',
			'workspace.readingFilter' => '阅读滤镜',
			'workspace.readingInsights' => '阅读洞察',
			'workspace.readingOverview' => '阅读概览',
			'workspace.readingSources' => '阅读来源',
			'workspace.readingPeriods' => '阅读时段',
			'workspace.readingWorkhole' => '阅读工作孔',
			'workspace.readerLaneIdle' => '阅读器泳道空闲中',
			'workspace.readerEn' => '阅读器 (Reader)',
			'workspace.readingHistoryEn' => '阅读历史 (History)',
			'workspace.readingHistory' => '阅读历史',
			'workspace.readingToastOverlay' => '阅读切换悬浮提示',
			'workspace.readingLabel' => '阅读中',
			'workspace.longPressDragReorder' => '长按拖动排序 / 换泳道',
			'workspace.imageHeaderUnmeasured' => '量不到图头',
			'workspace.resetLayoutHint' => '重置布局（不影响当前正在读的这一本）',
			'workspace.renameBookmarkList' => '重命名书签列表',
			'workspace.renameDeleteList' => '重命名 / 删除当前列表',
			'workspace.booksQueued' => '部在队列',
			'workspace.layoutFitsPanel' => '适合当前面板的布局与尺寸',
			'workspace.exitSoloEn' => '退出独占 (Exit Solo)',
			'workspace.exitSolo' => '退出独占',
			'workspace.exitTimeline' => '退出时间线',
			'workspace.exitSearchToFolder' => '退出搜索结果，回到这个页签自己的目录',
			'workspace.exitWorkspaceHint' => '退出工作台（Esc 亦可）',
			'workspace.exitWorkspace' => '退出工作台',
			'workspace.exitMultiselect' => '退出多选',
			'workspace.restoreSwipeAfterExit' => '退出后恢复横移切面板',
			'workspace.streakReading' => '连续阅读',
			'workspace.streakDays' => '连续天数',
			'workspace.streakLabel' => '连续',
			'workspace.runningTasks' => '进行中任务',
			'workspace.progressLabel' => '进度',
			'workspace.enterFolder' => '进入文件夹',
			'workspace.thisIsSwitchToastPreview' => '这是一条切换提示的预览',
			'workspace.allCardsCollapsed' => '这个面板里的卡片都被收起来了',
			'workspace.noFileManagerOnPlatform' => '这个平台没有可调用的文件管理器',
			'workspace.listHasNoBookmarks' => '这个列表里还没有书签',
			'workspace.itemNeedsLocalArchive' => '这一项要落到本地归档才有量具',
			'workspace.thisItem' => '这一项',
			'workspace.thisWall' => '这一墙',
			'workspace.noPluginsInstalled' => '还没有安装任何插件',
			'workspace.noBookmarksYet' => '还没有书签，去详情页点收藏吧',
			'workspace.last7ReadingTrend' => '近 7 日阅读趋势',
			'workspace.last7Records' => '近 7 日记录',
			'workspace.last7Days' => '近 7 日',
			'workspace.last3Days' => '近 3 天',
			'workspace.last28Records' => '近 28 日记录',
			'workspace.last28Active' => '近 28 日活跃',
			'workspace.last28NoRecords' => '近 28 日暂无记录',
			'workspace.last28Days' => '近 28 日',
			'workspace.boundaryToastText' => '边界提示文案',
			'workspace.carrierDistribution' => '载体分布',
			'workspace.carrierLabel' => '载体',
			'workspace.goToFolder' => '转到目录',
			'workspace.jumpBar' => '跳转栏',
			'workspace.pathActions' => '路径操作',
			'workspace.pathLabel' => '路径',
			'workspace.aggregateSourceSearch' => '跨图源聚合搜索',
			'workspace.trendLabel' => '趋势',
			'workspace.upscaleStage' => '超分阶段',
			'workspace.upscaleSwitch' => '超分开关',
			'workspace.afterUpscale' => '超分后',
			'workspace.resourceWorkhole' => '资源工作孔',
			'workspace.debugSource' => '调试源',
			'workspace.toastAtChapterEnd' => '读到章节末尾继续翻页时提醒',
			'workspace.detailedInformation' => '详细信息',
			'workspace.detailedLabel' => '详细',
			'workspace.laneMoreEditLayout' => '该泳道 (More) · 编辑布局',
			'workspace.visits' => '访问',
			'workspace.settingsAndTools' => '设置与工具',
			'workspace.triggerCondition' => '触发条件',
			'workspace.triggersAllOff' => '触发全关',
			'workspace.decodeBufferPlusCache' => '解码缓冲 + 图片缓存',
			'workspace.viewModeNotInTimeline' => '视图模式（时间线下不适用）',
			'workspace.viewModeLabel' => '视图模式',
			'workspace.seeDetailsBelow' => '见下方明细',
			'workspace.decorativeShapes' => '装饰图形',
			'workspace.installNewSource' => '装新图源',
			'workspace.fetching' => '获取中…',
			'workspace.freeThumbnails' => '自由缩略图',
			'workspace.customLayout' => '自定义布局',
			'workspace.pageTurnToast' => '翻页提示',
			'workspace.pageToastShowsNumber' => '翻页或跳页时实时反馈页码',
			'workspace.pageAnimation' => '翻页动画',
			'workspace.jpTranslated' => '翻訳',
			'workspace.networkImageCached' => '网络图片 · 下载后走图片缓存',
			'workspace.missingTitle' => '缺少标题',
			'workspace.missingSourceOrComicId' => '缺少 source 或 comicId',
			'workspace.thumbnailsLabel' => '缩略图',
			'workspace.editPath' => '编辑路径',
			'workspace.editLongPressHints' => '编辑时长按页签排序、跨泳道移动，或长按栏头图标重排泳道',
			'workspace.editLayout' => '编辑布局',
			'workspace.encodedFormat' => '编码格式',
			'workspace.encodedSize' => '编码大小',
			'workspace.weightBlendsEverything' => '综合内容数量、最近使用与阅读状态。',
			'workspace.resumeLastReading' => '继续上次阅读',
			'workspace.counting' => '统计中',
			'workspace.textureReady' => '纹理就绪',
			'workspace.texture' => '纹理',
			'workspace.compactList' => '紧凑列表',
			'workspace.pasteIntoItem' => '粘贴到这一项',
			'workspace.pasteHere' => '粘贴到当前目录',
			'workspace.lengthDistribution' => '篇幅分布',
			'workspace.lengthLabel' => '篇幅',
			'workspace.emphasiseReading' => '突出正在阅读的内容。',
			'workspace.emphasiseRecent' => '突出最近使用的内容。',
			'workspace.passthroughMode' => '穿透模式',
			'workspace.gapFill' => '空隙填充',
			'workspace.gapComponentsTitle' => '空隙与组件',
			'workspace.gapComponentsDescription' => '随机图形与小组件同在一处调整：先选总口径，再逐项开关；每一项都能直接看到实际样子。',
			'workspace.gapPreviewLabel' => '预览',
			'workspace.gapEnableAll' => '全部开启',
			'workspace.gapDisableAll' => '全部关闭',
			'workspace.gapShapesSection' => '随机图形',
			'workspace.gapWidgetsSection' => '小组件',
			'workspace.gapShapeBlob' => '有机团',
			'workspace.gapShapeBurst' => '星芒',
			'workspace.gapShapeClover' => '四叶草',
			'workspace.gapShapeGem' => '宝石',
			'workspace.gapShapeArch' => '拱门',
			'workspace.gapShapeFlower' => '花形',
			'workspace.gapShapeRing' => '圆环',
			'workspace.gapShapeWave' => '波纹',
			'workspace.gapCompletion' => '收官进度',
			'workspace.gapHeatmap' => '阅读热力',
			'workspace.gapWeekday' => '星期节律',
			'workspace.gapSpan' => '收藏跨度',
			'workspace.gapUnread' => '待读存量',
			'workspace.gapMilestone' => '下一里程碑',
			'workspace.gapAverageProgress' => '平均进度',
			'workspace.gapFinishedBooks' => '读完',
			'workspace.gapUnreadBooks' => '未读',
			'workspace.gapHeatWindow' => '近 8 周',
			'workspace.gapWeekdayRhythm' => '星期分布',
			'workspace.gapSpanDaysLabel' => '天跨度',
			'workspace.gapSpanEarliest' => '最早',
			'workspace.gapUnreadPool' => '待开始',
			'workspace.gapMilestoneHint' => '还差',
			'workspace.gapComponentCount' => ({required Object on, required Object total}) => '${on} / ${total} 开启',
			'workspace.gapMinSize' => ({required Object w, required Object h}) => '最小 ${w} × ${h}',
			'workspace.gapResetDefaults' => '恢复默认',
			'workspace.wallTabSize' => '尺寸',
			'workspace.wallTabLayout' => '布局',
			'workspace.wallTabComponents' => '组件',
			'workspace.wallTabCover' => '封面',
			'workspace.wallTabWeights' => '权重',
			'workspace.idleState' => '空闲',
			'workspace.moveToTrashNoUndo' => '移到回收站（无法撤销）',
			'workspace.moveToTrash' => '移到回收站',
			'workspace.folderPath' => '目录路径',
			'workspace.folderLabel' => '目录',
			'workspace.imageTuning' => '画面调节',
			'workspace.aspectComposition' => '画幅构成',
			'workspace.aspectFormat' => '画幅',
			'workspace.fillWithExpressiveShapes' => '用随机的 Expressive 轮廓与图标补满空隙。',
			'workspace.soloThisLaneEn' => '独占该栏 (Solo 聚焦)',
			'workspace.soloThisLane' => '独占该栏',
			'workspace.statusLabel' => '状态',
			'workspace.clickToCollapse' => '点击折叠',
			'workspace.clickToExpand' => '点击展开',
			'workspace.tapCover' => '点击封面',
			'workspace.clickToFill' => '点击填入',
			'workspace.comicArchive' => '漫画归档',
			'workspace.comicIdLabel' => '漫画 ID',
			'workspace.chineseLocalized' => '漢化',
			'workspace.renderPath' => '渲染路径',
			'workspace.clearSearchAndCollapse' => '清除搜索并收起',
			'workspace.lateNight' => '深夜',
			'workspace.activePeak' => '活跃峰值',
			'workspace.activeDays' => '活跃天数',
			'workspace.activeState' => '活跃',
			'workspace.noEntriesAfterFilter' => '没有符合搜索或类型筛选的条目',
			'workspace.noEntries' => '没有条目',
			'workspace.noEnabledSource' => '没有已启用的图源',
			'workspace.nothingToDisplay' => '没有可显示的条目',
			'workspace.noMatchingPages' => '没有匹配的页面',
			'workspace.noMatchingHistory' => '没有匹配的阅读记录',
			'workspace.noMatchingBookmarks' => '没有匹配的书签',
			'workspace.immersiveWorkhole' => '沉浸工作孔',
			'workspace.deleteForeverQuestion' => '永久删除？',
			'workspace.deleteForever' => '永久删除',
			'workspace.weeklyReadingRhythm' => '每周阅读节奏',
			'workspace.everyFieldIsMeasured' => '每一项都来自记账字段，不来自「我调过所以应该好了」',
			'workspace.normalState' => '正常',
			'workspace.recursiveSearchPending' => '正在递归搜索，结果扫完一次给出…',
			'workspace.recursiveSearching' => '正在递归搜索…',
			'workspace.followingProgress' => '正在跟随阅读进度',
			'workspace.editingLayoutFinishInMenu' => '正在编辑布局 · 菜单内完成编辑',
			'workspace.countingReadingHistory' => '正在统计阅读历史',
			'workspace.bannerLabel' => '横幅',
			'workspace.rootPath' => '根路径',
			'workspace.areaByAspectRatio' => '根据原图横竖比例分配卡片空间。',
			'workspace.longestSampleDays' => '样本最长 · 天',
			'workspace.longestSample' => '样本最长',
			'workspace.theWidthBadgeNextToHeader' => '栏头标题右边那颗「400px」',
			'workspace.titleLabel' => '标题',
			'workspace.sourceKey' => '来源键',
			'workspace.sourceType' => '来源类型',
			'workspace.sourceComposition' => '来源构成',
			'workspace.sourceBreakdown' => '来源拆分',
			'workspace.sourceModifiedAt' => '来源修改于',
			'workspace.sourceLabel' => '来源',
			'workspace.entryCount' => '条目数',
			'workspace.itemsUpdated' => '条有更新',
			'workspace.itemsContent' => '条内容',
			'workspace.chapterDonePreparingNext' => '本话已读完 · 准备下一话',
			'workspace.platformUnsupported' => '本平台不支持',
			'workspace.localComicsEn' => '本地漫画 (Local Manga)',
			'workspace.localComics' => '本地漫画',
			'workspace.localWorks' => '本地作品',
			'workspace.localLabel' => '本地',
			'workspace.lastPageToast' => '末页提示',
			'workspace.notTurnedOn' => '未开启',
			'workspace.notEnabled' => '未启用',
			'workspace.serverLabel' => '服务器',
			'workspace.maxThirtyTwoLevels' => '最多 32 层',
			'workspace.lastPageToastText' => '最后一页提示文案',
			'workspace.noReadingHistory' => '暂无阅读历史',
			'workspace.noRecordsYet' => '暂无记录',
			'workspace.noHeatRecords' => '暂无热力记录',
			'workspace.noEnabledPlugins' => '暂无启用的插件',
			'workspace.noVisitHistory' => '暂无历史访问记录',
			'workspace.normalOneWideTwoSlots' => '普通卡占 1 格，宽卡占 2 格',
			'workspace.eveningNight' => '晚间',
			'workspace.eveningLabel' => '晚上',
			'workspace.showHiddenFiles' => '显示隐藏文件',
			'workspace.showTarget' => '显示目标',
			'workspace.showQuickSwitchBar' => '显示快速切换栏',
			'workspace.showWorkspaceTopBar' => '显示工作台顶栏',
			'workspace.showSubFileNames' => '显示子文件名',
			'workspace.timeInformation' => '时间信息',
			'workspace.timePeriod' => '时段',
			'workspace.earlyFavourites' => '早期收藏',
			'workspace.cannotUndo' => '无法撤销',
			'workspace.noAnimation' => '无动画',
			'workspace.squareFormat' => '方幅',
			'workspace.newTab' => '新建页签',
			'workspace.newBookmarkList' => '新建书签列表',
			'workspace.newName' => '新名称',
			'workspace.fileManagement' => '文件管理',
			'workspace.fileBrowsing' => '文件浏览',
			'workspace.fileOperations' => '文件操作（复制 / 移动 / 删除）',
			'workspace.foldersFirst' => '文件夹优先',
			'workspace.fileNameLabel' => '文件名',
			'workspace.weightBiggerWins' => '数值越大越突出；0 关闭该项。多项命中时取最高权重。',
			'workspace.switchToFloating' => '改为悬浮',
			'workspace.collapseSearch' => '收起搜索',
			'workspace.collapseChildren' => '收起子项',
			'workspace.collapseSubfolders' => '收起子文件夹',
			'workspace.collapseInformation' => '收起信息',
			'workspace.favouriteTime' => '收藏时间',
			'workspace.favouriteList' => '收藏夹',
			'workspace.localOpenSupportDesc' => '支持 zip, cbz, 文件夹、PDF 及图片打包归档。Rust 侧快速解压并直入 D3D12/Metal 合成链。',
			'workspace.undoLastStep' => '撤销上一步',
			'workspace.summaryLabel' => '摘要',
			'workspace.searchSpaceExclude' => '搜索（空格分词，-排除）',
			'workspace.searchPageOrFileName' => '搜索页码或文件名...',
			'workspace.searchField' => '搜索栏',
			'workspace.searchTitleAuthorSource' => '搜索标题 / 作者 / 来源',
			'workspace.pluginRunState' => '插件运行状态',
			'workspace.pluginMarket' => '插件市场',
			'workspace.controlPanel' => '控制面板',
			'workspace.takeOver' => '接管',
			'workspace.keepReading' => '接着看',
			'workspace.sortingTimelineFixed' => '排序（时间线固定按时间排）',
			'workspace.sortMode' => '排序模式',
			'workspace.emphasiseByTagWeights' => '按自定义标签权重突出内容。',
			'workspace.areaByDiskUsage' => '按文件占用空间分配展示面积。',
			'workspace.timelineByDay' => '按天看时间线',
			'workspace.dragTitleToReorder' => '按住标题拖动排序',
			'workspace.bookmarkListDesc' => '按主题整理书签。创建后可以把书签移动到这个列表。',
			'workspace.dragResizeWorkhole' => '拖动调整工作孔尺寸',
			'workspace.dragToResize' => '拖动调整大小',
			'workspace.collapseToBarEn' => '折叠为紧凑条 (Collapse)',
			'workspace.collapseToBar' => '折叠为紧凑条',
			'workspace.saveSearchAsTab' => '把这次搜索结果另存一个页签',
			'workspace.setHomeHere' => '把当前目录设为主页',
			'workspace.openReader' => '打开阅读器',
			'workspace.openLocal' => '打开本地',
			'workspace.toastOnOpenOrSwitch' => '打开或切到另一本漫画时弹出',
			'workspace.openWorkhole' => '打开工作孔',
			'workspace.showPageNavWhenOpen' => '打开书本后显示页面导航',
			'workspace.showFileTimesWhenOpen' => '打开书本后显示文件时间',
			'workspace.showCurrentPageWhenOpen' => '打开书本后显示当前页信息',
			'workspace.showStorageWhenOpen' => '打开书本后显示存储信息',
			'workspace.showPresentPrefetchWhenOpen' => '打开书本后显示呈现与预取状态',
			'workspace.showBookInfoWhenOpen' => '打开一本书后显示书籍信息',
			'workspace.imFeelingLucky' => '手气不错',
			'workspace.restoreDefaultSize' => '恢复默认尺寸',
			'workspace.readerLaneSoloHint' => '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；点栏顶的独占按钮可让它瞬间撑满视口。',
			'workspace.footnoteSampleStreakDays' => '样本内有记录的连续日期 · 不代表完整阅读日志',
			'workspace.footnoteSampleStreak' => '样本内连续日期 · 不代表完整阅读日志',
			'workspace.footnotePeriod28' => '近 28 日 · 按最后阅读的本地时间分布',
			'workspace.footnoteWeekday28' => '近 28 日 · 按星期汇总最后阅读记录',
			'workspace.footnoteLast500' => '最近 500 本漫画的最后阅读记录 · 不代表总次数或阅读时长',
			'workspace.searchDepthTooltip' => ({required Object depths, required Object detail}) => '点按切换递归层数（${depths} 层）。${detail}',
			'workspace.shortSat' => '六',
			'workspace.shortFri' => '五',
			'workspace.shortThu' => '四',
			'workspace.shortWed' => '三',
			'workspace.shortTue' => '二',
			'workspace.shortMon' => '一',
			'workspace.shortSun' => '日',
			'workspace.restoreDefaultWidth' => '恢复默认宽度',
			'workspace.restorePanelBarPosition' => '恢复面板栏默认位置',
			'workspace.restoreCollapsedCards' => '恢复被收起的卡片',
			'workspace.restoreClosedTabs' => '恢复已关闭页签',
			'workspace.totalPagesLabel' => '总页数',
			'workspace.toContinue' => '待续',
			'workspace.queueStackCards' => '待看叠卡',
			'workspace.currentPageCost' => '当前页耗时',
			'workspace.currentPageNumber' => '当前页码',
			'workspace.currentPageFile' => '当前页文件',
			'workspace.currentPageSize' => '当前页大小',
			'workspace.currentPageModifiedAt' => '当前页修改于',
			'workspace.currentPageHandoffMs' => '当前页交页耗时 (ms)',
			'workspace.currentStreakDays' => '当前连续 · 天',
			'workspace.currentStreak' => '当前连续',
			'workspace.noHitThisLevel' => '当前这一层没有命中；开着「含子目录」再搜一次（整库遍历在慢盘上要几十秒）',
			'workspace.folderNoMedia' => '当前目录没有可浏览的漫画或媒体文件',
			'workspace.folderNoChildren' => '当前文件夹没有可显示的子项',
			'workspace.folderNotInSnapshot' => '当前搜索或目录快照未包含此文件夹。可进入文件夹查看内部内容。',
			'workspace.archiveLabel' => '归档',
			'workspace.onComparingOriginal' => '开着（原图对比中）',
			'workspace.switchedOn' => '开着',
			'workspace.fieldsFillOnOpen' => '开书后这几格会当场填上，量不到的留 —',
			'workspace.linking' => '建链中',
			'workspace.avgPagesPerBook' => '平均页/话数',
			'workspace.regularWidth' => '常规宽度',
			'workspace.commonTags' => '常见标签',
			'workspace.topCreators' => '常看创作者',
			'workspace.market' => '市场',
			'workspace.limitReached' => '已达上限',
			'workspace.isLastPage' => '已经是最后一页',
			'workspace.searchHistoryCleared' => '已清空搜索历史',
			'workspace.followProgressPaused' => '已暂停跟随阅读进度',
			'workspace.fileManagerOpened' => '已打开文件管理器',
			'workspace.gpuReadyState' => '已就绪',
			'workspace.pathCopied' => '已复制路径',
			'workspace.copied' => '已复制',
			'workspace.pagesPresented' => '已呈现页数',
			'workspace.cutDone' => '已剪切',
			'workspace.writtenToCacheShare' => '已写入缓存，请在分享面板里保存',
			'workspace.aborted' => '已中止',
			'workspace.workholeSize' => '工作孔尺寸',
			'workspace.peakDay' => '峰值日',
			'workspace.peakValue' => '峰值',
			'workspace.expandLane' => '展开泳道',
			'workspace.polledEvery3s' => '展开时每 3 秒取一次',
			'workspace.expandChildren' => '展开子项',
			'workspace.expandSubfolders' => '展开子文件夹',
			'workspace.expandInformation' => '展开信息',
			'workspace.expandLabel' => '展开',
			'workspace.displayWallSettings' => '展墙设置 · 长按开关展墙',
			'workspace.displayWallCustom' => '展墙自定义',
			'workspace.displayWall' => '展墙',
			'workspace.searchDepthCostHint' => '层数越大越慢：一次整库遍历在慢盘上要几十秒；太浅会漏掉更深的目录',
			'workspace.readyWaiting' => '就绪等待',
			'workspace.readyState' => '就绪',
			'workspace.dustyReread' => '尘封重温',
			'workspace.widgetsOnceThenShapes' => '小组件每面墙各出现一次，其余空隙用随机图形补。',
			'workspace.coverGrid' => '封面网格',
			'workspace.coverCollage' => '封面拼贴',
			'workspace.coverList' => '封面列表',
			'workspace.coverLabel' => '封面',
			'workspace.exportAsJson' => '导出为 JSON',
			'workspace.importExport' => '导入 / 导出',
			_ => null,
		} ?? switch (path) {
			'workspace.cardWidthAutoColumns' => '宽度为目标尺寸，列数随面板可用空间自动调整。宽卡占两格，可与普通卡并排。',
			'workspace.finishEditing' => '完成编辑',
			'workspace.finishLayout' => '完成布局',
			'workspace.storageInformation' => '存储信息',
			'workspace.saveAsTab' => '存为页签',
			'workspace.subFilesShowAll' => '子文件：显示全部',
			'workspace.subFilesShowOne' => '子文件：显示一个',
			'workspace.daysWithRecords' => '天有记录',
			'workspace.sizeCompare' => '大小对比',
			'workspace.sizeLabel' => '大小',
			'workspace.multiColumnLanes' => '多列泳道',
			'workspace.searchAnyToken' => '多个词元之间取并集（默认全部都要命中）',
			'workspace.multiOutlinedSelected' => '多 · 描边为选中项',
			'workspace.duplicateTab' => '复制页签',
			'workspace.copyPath' => '复制路径',
			'workspace.copyPosition' => '复制位置',
			'workspace.einkRefresh' => '墨水屏刷屏',
			'workspace.basedOnLast500' => '基于最近 500 本漫画的最后阅读记录',
			'workspace.readingProgress' => '在读进度',
			'workspace.currentlyReading' => '在读',
			'workspace.onlineSourceNoFileTime' => '在线图源没有本地文件时间',
			'workspace.onlineSourceNoArchive' => '在线图源没有归档',
			'workspace.onlineSource' => '在线图源',
			'workspace.onlineLabel' => '在线',
			'workspace.openInNewTab' => '在新页签打开',
			'workspace.readerLaneReadsHint' => '在左侧书架或右侧发现里点开任意一本，都会读在这条泳道里；',
			'workspace.searchSubdirs' => '在子目录里搜',
			'workspace.gallery' => '图集',
			'workspace.imageSize' => '图片尺寸',
			'workspace.imagesLabel' => '图片',
			'workspace.sourceLocalAggregate' => '图源本地聚合',
			'workspace.sourceExtensions' => '图源扩展',
			'workspace.sourceShortcuts' => '图源快捷入口',
			'workspace.imageSourcesEn' => '图源与扩展 (Extensions)',
			'workspace.imageSources' => '图源与扩展',
			'workspace.sourcesToolsOcr' => '图源 · 工具 · OCR',
			'workspace.imageProcessingStage' => '图像处理阶段',
			'workspace.imageInformation' => '图像信息',
			'workspace.pinTab' => '固定页签',
			'workspace.pinHere' => '固定到当前位置',
			'workspace.backToFolder' => '回到目录',
			'workspace.backHome' => '回到主页',
			'workspace.backToLaneHeaderDefault' => '回到「挂进栏头」这个默认形态',
			'workspace.heatmapFourRowsHint' => '四行连续日期 · 描边为选中日 · 颜色越强，记录越多',
			'workspace.weekdaySun' => '周日',
			'workspace.weekdaySat' => '周六',
			'workspace.weekdayFri' => '周五',
			'workspace.weekdayThu' => '周四',
			'workspace.weekdayWed' => '周三',
			'workspace.weekdayTue' => '周二',
			'workspace.weekdayMon' => '周一',
			'workspace.presenter' => '呈现器',
			'workspace.includeSubdirStats' => '含子目录统计',
			'workspace.includeSubdirs' => '含子目录',
			'workspace.recursiveSearchHint' => '向下递归搜索，层数上限由 Rust 侧夹紧',
			'workspace.back' => '后退',
			'workspace.searchSyntaxHint' => '名称与路径 · 空格分词 · -排除 · “短语”',
			'workspace.nameLabel' => '名称',
			'workspace.undoable' => '可以撤销',
			'workspace.onlyThisPanelDetailsBelow' => '只调整当前面板。封面右下角的详情按钮始终向下展开。',
			'workspace.onlyFittingWidgetsRepeat' => '只插入尺寸相符的汇总小组件，同一款可以重复。',
			'workspace.mergeOnlyHistoryDetail' => '只合并：一条历史都不会删除；本地进度比文件里更新的，保留本地。',
			'workspace.mergeOnlyHistory' => '只合并，不会删除或覆盖已有的记录。',
			'workspace.mergeOnlyBookmarks' => '只合并，不会删除或覆盖已有的书签。',
			'workspace.changesLabel' => '变更',
			'workspace.discoverToolsEn' => '发现与工具 (Tools)',
			'workspace.switchToWorkholeEn' => '切换为沉浸工作孔 (Workhole)',
			'workspace.switchToSwimlaneEn' => '切换为多列泳道 (Swimlane)',
			'workspace.closeSidebarEn' => '关闭边栏 (Close)',
			'workspace.closeCurrentComicFull' => '关闭当前漫画（回到空态）',
			'workspace.closeCurrentComicPlain' => '关闭当前漫画 (回到空态)',
			'workspace.favoritesEn' => '书签 (Favorites)',
			'workspace.bookshelfEn' => '书架 (Bookshelf)',
			'workspace.downloadsOfflineEn' => '下载与离线 (Downloads)',
			'workspace.topEntriesStillWork' => '上面三颗入口仍然可用：装一个图源后这里会一格一个列出来',
			'workspace.widgetsPlusShapes' => '组件 + 图形',
			'workspace.miniWidgets' => '小组件',
			'workspace.randomShapes' => '随机图形',
			'workspace.openDetailsPage' => '打开详情页',
			'workspace.expandDetailsBelow' => '向下展开详情',
			'workspace.weightBalanced' => '综合',
			'workspace.readingStatus' => '阅读状态',
			'workspace.recentlyUsed' => '最近使用',
			'workspace.followSort' => '跟随排序',
			'workspace.yesterday' => '昨天',
			'workspace.cancelPathEdit' => '取消路径编辑',
			'workspace.unpin' => '取消固定',
			'workspace.discoverTools' => '发现与工具',
			'workspace.doubleTapResetLaneWidth' => '双击重置该栏宽度　·　右键打开该泳道的菜单',
			'workspace.installOrImportPlugin' => '去「插件市场」装一个图源，或导入本地插件包',
			'workspace.originalRatio' => '原图比例',
			'workspace.historyFile' => '历史记录文件',
			'workspace.historyData' => '历史数据',
			'workspace.volume' => '卷',
			'workspace.cardHeight' => '卡片高度',
			'workspace.cardSpacing' => '卡片间距',
			'workspace.cardLayout' => '卡片布局',
			'workspace.cardWidth' => '卡片宽度',
			'workspace.cardPosition' => '卡片位置',
			'workspace.occupiedSize' => '占用体积',
			'workspace.matchPath' => '匹配路径',
			'workspace.loadingState' => '加载中',
			'workspace.cut' => '剪切',
			'workspace.forward' => '前进',
			'workspace.last7DaysRecords' => '前 7 日记录',
			'workspace.refreshCurrentFolder' => '刷新当前目录',
			'workspace.toastOnLastPage' => '到达最后一页时显示提示',
			'workspace.reachedLastPage' => '到底啦 ~ 没有更多页面',
			'workspace.deleteQuestion' => '删除？',
			'workspace.creating' => '创建中',
			'workspace.create' => '创建',
			'workspace.creator' => '创作者',
			'workspace.listName' => '列表名称',
			'workspace.toastOnPageSwitch' => '切换页面时显示提示',
			'workspace.switchToastTest' => '切换提示测试',
			'workspace.switchToast' => '切换提示',
			'workspace.toastOnBookSwitch' => '切换书籍时显示提示',
			'workspace.switchToWorkhole' => '切换为沉浸工作孔',
			'workspace.switchToSwimlane' => '切换为多列泳道',
			'workspace.switchDescending' => '切换为降序',
			'workspace.switchAscending' => '切换为升序',
			'workspace.bookSwitchToast' => '切书提示',
			'workspace.internalThumbnails' => '内部缩略图',
			'workspace.builtin' => '内置',
			'workspace.moreContentMoreArea' => '内容数量越多，展示面积越大。',
			'workspace.contentCount' => '内容数量',
			'workspace.contentSections' => '内容分区',
			'workspace.otherMedia' => '其他媒体',
			'workspace.closeTab' => '关闭页签',
			'workspace.closeSidebar' => '关闭边栏',
			'workspace.closePassthroughMode' => '关闭穿透模式',
			'workspace.closeCurrentComic' => '关闭当前漫画',
			'workspace.closeWorkhole' => '关闭工作孔',
			'workspace.closeTabsLeft' => '关闭左侧页签',
			'workspace.closeTabsRight' => '关闭右侧页签',
			'workspace.closeOtherTabs' => '关闭其他页签',
			'workspace.turnedOff' => '关着',
			'workspace.manageAll' => '全部管理',
			'workspace.allHealthy' => '全部正常',
			'workspace.allImageSources' => '全部图源',
			'workspace.closeAllTabs' => '全部关闭',
			'workspace.fullWidth' => '全宽',
			'workspace.allowLeaveLane' => '允许移出泳道',
			'workspace.pixelSize' => '像素尺寸',
			'workspace.serendipity' => '偶遇',
			'workspace.favouriteTagWeight' => '偏好标签权重',
			'workspace.favouriteTags' => '偏好标签',
			'workspace.modifiedTime' => '修改时间',
			'workspace.modifiedDate' => '修改日期',
			'workspace.modify' => '修改',
			'workspace.egBookPath' => '例如：路径：{{book.path}}',
			'workspace.egPageIndex' => '例如：第 {{page.indexDisplay}} 页',
			'workspace.egLastPage' => '例如：已经是最后一页',
			'workspace.egSwitchedToBook' => '例如：已切换到 {{book.displayName}}',
			'workspace.egPageName' => '例如：{{page.name}}',
			'workspace.sizeVolume' => '体积',
			'workspace.toastStyleInSettings' => '位置与外观在「设置 → 提示样式」里调整。',
			'workspace.emphasiseTopSorted' => '优先突出当前排序靠前的内容。',
			'workspace.anyToken' => '任一词元',
			'workspace.collapseFromPanel' => '从该面板收起',
			'workspace.newFromThisTab' => '从此页签新建',
			'workspace.pickComicFolderFromDisk' => '从本地磁盘选择漫画文件夹',
			'workspace.importFromJson' => '从 JSON 导入',
			'workspace.today' => '今天',
			'workspace.desktopOnly' => '仅桌面',
			'workspace.bookPathLocalOnly' => '书籍路径（本地来源才有值）',
			'workspace.bookTitleTemplate' => '书籍标题模板',
			'workspace.bookDisplayName' => '书籍显示名',
			'workspace.bookToastTemplate' => '书籍提示模板',
			'workspace.bookDescriptionTemplate' => '书籍描述模板',
			'workspace.bookInformation' => '书籍信息',
			'workspace.bookmarkFile' => '书签文件',
			'workspace.bookmarkData' => '书签数据',
			'workspace.bookmarks' => '书签',
			'workspace.bookshelfUpstream' => '书架（上游原版）',
			'workspace.bookshelfAggregateCard' => '书架聚合卡片',
			'workspace.shelfFavoriteFiles' => '书架 · 收藏 · 文件',
			'workspace.bookshelfTab' => '书架',
			'workspace.bookTitle' => '书名',
			'workspace.homeNotSetYet' => '主页：还没设置 · 单击把当前目录设为主页',
			'workspace.homeCurrentManageHint' => '主页（当前）· 右键/长按管理',
			'workspace.homeSetTo' => '主页已设为',
			'workspace.homeManageHint' => '主页 · 右键/长按管理',
			'workspace.heroVisual' => '主视觉',
			'workspace.mainOccupancy' => '主要占用',
			'workspace.temporarySort' => '临时排序（不记住本目录）',
			'workspace.abortRecursiveSearch' => '中止递归搜索（保留已找到的结果）',
			'workspace.samePathAsHeaderDoubleClick' => '与双击栏头标题同一条路',
			'workspace.samePathAsBackKey' => '与 Esc、系统返回键同一条路',
			'workspace.keepGapIrregularOutline' => '不规则轮廓之间保留空白。',
			'workspace.notAnObject' => '不是对象',
			'workspace.asymmetric' => '不对称',
			'workspace.noFill' => '不填充',
			'workspace.downloadTaskList' => '下载任务列表',
			'workspace.downloadsOffline' => '下载与离线',
			'workspace.bothWeeksNoRecord' => '两周均无记录',
			'workspace.earlyAfternoon' => '午后',
			'workspace.noon' => '午',
			'workspace.earlyMorning' => '凌晨',
			'workspace.afternoon' => '下午',
			'workspace.morning' => '上午',
			'workspace.parentDirectory' => '上一级',
			'workspace.prevWindowNoRecord' => '上一窗口无记录',
			'workspace.nextSegment' => '下一段',
			'workspace.prevSegment' => '上一段',
			'workspace.noCreationTimeField' => 'dart:io 没有创建时间，只报量得到的这几项',
			'workspace.rustMemoryPollHint' => 'Rust 内存只在展开时取，收起不轮询',
			'workspace.rustMemory' => 'Rust 内存',
			'workspace.gpuZeroCopyEngine' => 'GPU 零拷贝直通引擎',
			'workspace.gpuLinking' => 'GPU 建链中',
			'workspace.gpuReady' => 'GPU 就绪',
			'workspace.gpuSharedTexture' => 'GPU 共享纹理',
			'workspace.cpuDecodeFallback' => 'CPU 解码兜底',
			'workspace.cpuDecodePreload' => 'CPU 解码 / 图片缓存预加载',
			'workspace.compressedArchive' => '压缩归档',
			'workspace.archiveZip' => 'ZIP 归档',
			'workspace.archiveTar' => 'TAR 归档',
			'workspace.archiveRar' => 'RAR 归档',
			'workspace.archiveCbz' => 'CBZ 归档',
			'workspace.archiveCbr' => 'CBR 归档',
			'workspace.archive7z' => '7Z 归档',
			'appName' => 'Rossi',
			'common.nameNoSlash' => '名称不能包含 / 或 \\',
			'common.startupStage' => ({required Object stage}) => '阶段: ${stage}',
			'common.appStartupFailed' => '应用启动失败',
			'common.openLocalComicRossi' => '打开本地漫画（Rossi 原版阅读器 + GPU 零拷贝）',
			'common.neoViewWorkspace' => '泳道/工作孔工作台 (NeoView Workspace)',
			'common.openWithRossi' => '用 Rossi 打开',
			'common.showInExplorer' => '在资源管理器中显示',
			'common.showInFinder' => '在访达中显示',
			'common.showInFileManager' => '在文件管理器中显示',
			'common.revealInFileManagerFolder' => '在文件管理器中打开所在目录',
			'common.deleteListLabel' => '删除列表',
			'common.pleaseEnterName' => '请输入名称',
			'common.ok' => '确定',
			'common.cancel' => '取消',
			'common.save' => '保存',
			'common.delete' => '删除',
			'common.edit' => '编辑',
			'common.rename' => '重命名',
			'common.add' => '添加',
			'common.create' => '新建',
			'common.refresh' => '刷新',
			'common.loading' => '加载中...',
			'common.loadingFailed' => '加载失败',
			'common.retry' => '重试',
			'common.reload' => '重新加载',
			'common.confirm' => '确认',
			'common.close' => '关闭',
			'common.back' => '返回',
			'common.help' => '帮助',
			'common.gotIt' => '知道了',
			'common.underConstruction' => '施工中',
			'common.comingSoon' => '在写了，在写了',
			'common.root' => '根目录',
			'common.remove' => '移除',
			'common.overwrite' => '覆盖',
			'common.cancelled' => '已取消',
			'common.search' => '搜索',
			'common.clear' => '清空',
			'common.copy' => '复制',
			'common.paste' => '粘贴',
			'common.share' => '分享',
			'common.open' => '打开',
			'common.download' => '下载',
			'common.upload' => '上传',
			'common.import' => '导入',
			'common.export' => '导出',
			'common.success' => '成功',
			'common.failed' => '失败',
			'common.error' => '错误',
			'common.warning' => '警告',
			'common.info' => '提示',
			'common.unknown' => '未知',
			'common.empty' => '暂无数据',
			'common.all' => '全部',
			'common.none' => '无',
			'common.default_' => '默认',
			'common.custom' => '自定义',
			'common.enabled' => '已开启',
			'common.disabled' => '已关闭',
			'common.followSystem' => '跟随系统',
			'common.lightMode' => '浅色模式',
			'common.darkMode' => '深色模式',
			'common.system' => '系统',
			'common.apply' => '应用',
			'common.reset' => '重置',
			'common.next' => '下一步',
			'common.previous' => '上一步',
			'common.done' => '完成',
			'common.select' => '选择',
			'common.selected' => '已选择',
			'common.deselect' => '取消选择',
			'common.selectAll' => '全选',
			'common.yes' => '是',
			'common.no' => '否',
			'common.on' => '开',
			'common.off' => '关',
			'common.more' => '更多',
			'common.detail' => '详情',
			'common.settingSaved' => '设置已保存',
			'common.restartToTakeEffect' => '设置成功，重启生效',
			'error.generic' => '出错了',
			'error.network' => '网络错误',
			'error.downloadFailed' => '下载失败',
			'error.importFailed' => ({required Object error}) => '导入失败: ${error}',
			'error.loadFailed' => '加载失败',
			'error.saveFailed' => '保存失败',
			'error.permissionDenied' => '权限被拒绝',
			'error.notFound' => '未找到',
			'error.unsupportedPlatform' => '当前平台不支持此功能',
			'error.missingPluginSource' => ({required Object action}) => '缺少插件来源，无法${action}',
			'error.operationFailed' => '操作失败',
			'error.executionFailed' => '执行失败',
			'navigation.home' => '首页',
			'navigation.rank' => '排行',
			'navigation.bookshelf' => '书架',
			'navigation.discover' => '发现',
			'navigation.more' => '更多',
			'navigation.syncSuccess' => '同步成功！',
			'navigation.autoSyncSuccess' => '自动同步成功！',
			'navigation.syncFailed' => '同步失败',
			'navigation.autoSyncFailed' => '自动同步失败',
			'navigation.syncFailedMessage' => ({required Object error}) => '请检查网络连接或稍后再试。\n${error}',
			'navigation.loginExpired' => '登录过期，请重新登录',
			'navigation.needLoginTitle' => '需要登录',
			'navigation.goLogin' => '去登录',
			'navigation.sidebarCollapse' => '收起侧栏',
			'navigation.sidebarExpand' => '展开侧栏',
			'navigation.navigationChrome' => '导航栏',
			'navigation.sidebarEnabled' => 'Arc 风格侧栏',
			'navigation.sidebarEnabledSubtitle' => '桌面与平板用左侧侧栏导航；关掉回到改造前的旧侧栏',
			'navigation.sidebarExpanded' => '侧栏展开',
			'navigation.sidebarExpandedSubtitle' => '展开时每条带文案，收起时只有图标；侧栏顶部那颗按钮随时可切',
			'navigation.dockEnabled' => '悬浮 Dock 栏',
			'navigation.dockEnabledSubtitle' => '窄屏用底部悬浮胶囊导航；关掉回到改造前的底部导航栏',
			'navigation.autoNarrowMobileLayout' => '窄屏自动切移动端布局',
			'navigation.autoNarrowMobileLayoutSubtitle' => '窗口窄于下面的阈值时从侧栏切到底部 Dock（桌面小窗、平板分屏）',
			'navigation.narrowNavigationWidth' => '窄屏阈值',
			'navigation.narrowNavigationWidthSubtitle' => '窗口宽度（逻辑像素）小于这个值就算窄屏',
			'navigation.narrowNavigationWidthReset' => ({required Object value}) => '恢复默认（${value}）',
			'navigation.moreActions' => '更多动作',
			'navigation.customize' => '自定义导航',
			'navigation.customizeTitle' => '自定义导航栏',
			'navigation.customizeHint' => '两段各自拖拽排序、自由添加 / 隐藏；动作行上的箭头在「主区」与「底部快捷区」之间搬',
			'navigation.customizeMainSection' => '主区',
			'navigation.customizeActionsSection' => '底部快捷区',
			'navigation.customizeActionsHint' => '侧栏底部那一排 / Dock 尾部溢出菜单里的入口，只放动作',
			'navigation.customizeDesktopTab' => '桌面侧栏',
			'navigation.customizeMobileTab' => '移动端 Dock',
			'navigation.customizeReset' => '恢复默认',
			'navigation.customizeDone' => '完成',
			'navigation.customizeAvailable' => '待添加项目',
			'navigation.customizeHide' => '隐藏',
			'navigation.customizeActionTag' => '动作',
			'navigation.customizeMoveToMain' => '移到主区',
			'navigation.customizeMoveToActions' => '移到底部快捷区',
			'navigation.workspace' => '工作台',
			'navigation.openLocalComic' => '打开本地漫画',
			'navigation.gpuPresent' => 'GPU 上屏',
			'settings.allLanePanelsHidden' => '这条泳道里的面板都已隐藏 ——\n可在「全局设置 → 泳道面板看板」中开启需要显示的面板。',
			'settings.localTreeArchiveSize' => ({required Object size}) => '漫画归档 · ${size}',
			'settings.localTreeOpenThisFolder' => '直接打开此文件夹',
			'settings.localTreeEmpty' => '当前目录下没有发现子文件夹或漫画文件',
			'settings.localTreeReadFailed' => ({required Object error}) => '读取失败: ${error}',
			'settings.localTreeOpenFolder' => '打开当前文件夹',
			'settings.localTreeTitle' => '本地文件树浏览 (mImageViewer 核心)',
			'settings.debugNoRustDiagnostics' => 'native 侧没有返回 Rust 侧诊断（DLL 与桥的版本可能不匹配）。',
			'settings.debugBrowse' => '浏览...',
			'settings.debugLocalSourceGroup' => '本地来源（散图文件夹 / .cbz / .cbr）',
			'settings.debugRefreshStats' => '刷新统计',
			'settings.tabSideRight' => '竖向（右侧）',
			'settings.tabSideLeft' => '竖向（左侧）',
			'settings.tabSideTop' => '横向（顶栏）',
			'settings.tabPolicyTriggering' => '继承触发页签',
			'settings.tabPolicyRecent' => '继承最近使用的页签',
			'settings.tabPolicyDefaults' => '使用预设默认值',
			'settings.dragToLaneEnd' => '拖拽面板到此追加至末尾',
			'settings.dropToLaneEnd' => '松手放到此泳道末尾',
			'settings.moveToLeftLane' => '移至左泳道',
			'settings.moveToRightLane' => '移至右泳道',
			'settings.kanbanRank' => ({required Object n}) => '顺位 #${n}',
			'settings.kanbanShowPanel' => '在面板栏中显示此面板',
			'settings.kanbanHideCompletely' => '从面板栏彻底隐藏（不留隐藏图标）',
			'settings.kanbanReaderLaneDesc' => '此泳道专用于承载正在阅读的漫画页面。可通过上方泳道顺序条或本列右上角箭头，将阅读器调整到左侧、居中或右侧位置。',
			'settings.kanbanReaderCanvasTitle' => '漫画阅读器主画布',
			'settings.kanbanVisibleHidden' => ({required Object visible, required Object hidden}) => '显示 ${visible} 个 · 隐藏 ${hidden} 个',
			'settings.kanbanAllVisible' => ({required Object count}) => '共 ${count} 个面板（全部显示）',
			'settings.kanbanReaderLaneTitle' => '阅读器主视图泳道',
			'settings.kanbanLaneIndex' => ({required Object n}) => '第 ${n} 栏',
			'settings.kanbanLaneOrderTitle' => '泳道顺序（可左右拖拽或点击箭头调整位置）',
			'settings.kanbanHiddenPanels' => ({required Object count}) => '已彻底隐藏 ${count} 个面板',
			'settings.kanbanVisiblePanels' => ({required Object count}) => '显示中 ${count} 个面板',
			'settings.kanbanLaneOrder' => ({required Object order}) => '泳道顺序：${order}',
			'settings.kanbanDragHint' => '拖拽或点击按钮即可调整泳道顺序、各泳道内面板顺序及显示/隐藏状态。隐藏后的面板将从面板栏彻底移除，不再显示隐藏图标。',
			'settings.rightLane' => '右泳道',
			'settings.leftLane' => '左泳道',
			'settings.swimlanePanelKanbanConfigTitle' => '泳道面板看板配置',
			'settings.revealZonePointerHint' => '本机没有悬停指针：这几块唤出区要鼠标贴住边缘才会生效。触屏上请在 Reader 独占时点左右两侧的窄轨来切换泳道。',
			'settings.laneCustomDelayMs' => '本泳道自定义 · 毫秒',
			'settings.inheritedGlobalDelay' => ({required Object ms}) => '继承全局：${ms} 毫秒',
			'settings.fmViewColumns' => '分栏视图',
			'settings.fmViewTree' => '树形视图',
			'settings.fmViewContent' => '内容视图',
			'settings.fmDefaultContentLayout' => '默认内容布局',
			'settings.fmDefaultEntryStyle' => '默认条目样式',
			'settings.fmTabPolicyHint' => '“最近使用”跟随当前活跃页签；“触发页签”跟随发起动作的页签。只继承浏览与搜索选项，查询、结果、历史和选中项各自独立。首次打开没有继承来源时使用预设。',
			'settings.fmTabPolicySource' => '选项来源',
			'settings.favoriteTagExampleHint' => 'school_lolita | 学校萝莉 | School Lolita\nloli',
			'settings.noMatchingArtist' => '未找到匹配的画师',
			'settings.favoriteArtistExampleHint' => '武田弘光\n[circle (artist)]\n水龙敬',
			'settings.confirmResetPin' => '确认重置 PIN',
			'settings.defaultHoverDelaySubtitle' => '泳道未单独设置延时时使用此值',
			'settings.defaultHoverDelay' => '默认悬停定位延迟',
			'settings.enterWorkspaceSubtitle' => '按下面选好的呈现打开；退出用系统返回键',
			'settings.enterWorkspace' => '进入工作台',
			'settings.kanbanLaneMoveRight' => '泳道右移',
			'settings.kanbanLaneMoveLeft' => '泳道左移',
			'settings.kanbanPanelMoveDown' => '下移面板',
			'settings.kanbanPanelMoveUp' => '上移面板',
			'settings.kanbanLaneDefaultHidden' => '默认隐藏',
			'settings.kanbanLanePinned' => '固定泳道',
			'settings.kanbanFullyHidden' => '已彻底隐藏',
			'settings.kanbanVisible' => '显示中',
			'settings.kanbanRestoreDefault' => '恢复默认排布',
			'settings.swimlanePanelKanbanDesc' => '使用看板调整泳道顺序、各泳道上面板的顺序以及显示与彻底隐藏',
			'settings.laneHoverDelayInherit' => '恢复继承全局延迟',
			'settings.laneHoverDelay' => '悬停定位延迟',
			'settings.laneHoverRevealSubtitle' => '停留后自动移动工作台，让本泳道完整显示',
			'settings.laneHoverReveal' => '悬停后完整显示',
			'settings.laneKeyboardFollowsMouseSubtitle' => '鼠标进入本泳道后，将键盘操作交给本泳道',
			'settings.laneKeyboardFollowsMouse' => '键盘目标跟随鼠标',
			'settings.laneInteraction' => '泳道交互',
			'settings.swimlanePanelKanbanSubtitle' => '泳道顺序 · 各泳道面板排序 · 面板显示与彻底隐藏',
			'settings.swimlanePanelKanban' => '泳道与面板看板',
			'settings.fmNewTabPresetHint' => '预设默认值仅在“使用预设默认值”时采用；默认递归范围沿用下方搜索设置。复制与恢复已关闭页签保留原有设置。',
			'settings.fmNewTabShowInternal' => '默认显示内部条目',
			'settings.fmNewTabShowHidden' => '默认显示隐藏项',
			'settings.fmNewTabPassthrough' => '默认启用穿透',
			'settings.fmNewTabStartup' => '新页签启动选项',
			'settings.importFileTxtJsonEmm' => '导入文件 (TXT/JSON/EMM setting.json)',
			'settings.searchArtistHint' => '搜索画师...',
			'settings.importFileTxtJson' => '导入文件 (TXT/JSON)',
			'settings.debugGpuPresentSubtitle' => 'Rust 解码 → wgpu → GPU 拷贝 → 共享纹理，像素不过桥',
			'settings.debugGpuPresent' => 'GPU 上屏（D3D12 共享纹理）',
			'settings.debugOcrSmokeSubtitle' => '选一张页 → 检测/识别/擦字/翻译/回填，逐段看耗时与产物',
			'settings.debugOcrSmoke' => 'OCR 成品页冒烟',
			'settings.debugLocalSourceSubtitle' => '散图文件夹 / CBZ / CBR 直读，含逐页耗时与拒绝类别',
			'settings.debugLocalSource' => '本地来源读取（判据 A）',
			'settings.setResetPin' => '设置重置 PIN',
			'settings.overviewSubtitle' => '让 Rossi 更合你的习惯',
			'settings.searchCategories' => '搜索设置分类',
			'settings.noMatchingCategories' => '没有匹配的分类，请尝试其他关键词',
			'settings.personalizationGroup' => '外观与反馈',
			'settings.readingGroup' => '阅读与画面',
			'settings.libraryGroup' => '文件、书架与数据',
			'settings.applicationGroup' => '应用与操作',
			'settings.windowGroup' => '窗口',
			'settings.syncDestinationsSubtitle' => '同步服务 · 云端备份',
			'settings.title' => '设置',
			'settings.globalTitle' => '设置',
			'settings.appearance' => '外观与显示',
			'settings.theme' => '主题模式',
			'settings.themeSubtitle' => '选择策略，切换明暗主题',
			'settings.themeColor' => '主题颜色',
			'settings.tweakcnTitle' => '导入 Tweakcn 主题',
			'settings.tweakcnSubtitle' => '粘贴 tweakcn 复制的 CSS 变量，或 shadcn registry 的 JSON',
			'settings.tweakcnHint' => ':root {\n  --background: oklch(1 0 0);\n  --primary: oklch(0.628 0.258 29.2);\n}',
			'settings.tweakcnImport' => '导入',
			'settings.tweakcnNameField' => '主题名（可留空）',
			'settings.tweakcnPickHint' => '点一行即切为当前主题',
			'settings.tweakcnEntryMeta' => ({required Object count, required Object radius}) => '${count} 个 token · 圆角 ${radius}',
			'settings.tweakcnDelete' => '删除该主题',
			'settings.tweakcnEnabled' => '启用导入的主题',
			'settings.tweakcnApplied' => ({required Object count, required Object radius}) => '已导入 ${count} 个颜色 token · 圆角 ${radius}',
			'settings.tweakcnNoRadius' => '沿用默认',
			'settings.tweakcnFailedEmpty' => '内容为空',
			'settings.tweakcnFailedJson' => '不是能识别的 JSON',
			'settings.tweakcnFailedNoColors' => '没有解析出任何颜色 token',
			'settings.tweakcnSkipped' => ({required Object keys}) => '以下 token 读不出颜色，已跳过：${keys}',
			'settings.tweakcnFallbackRoles' => ({required Object roles}) => '主题没给这些必需 token，已自动补值：${roles}',
			'settings.themeColorSubtitle' => '选择主色，统一应用视觉',
			'settings.language' => '语言',
			'settings.languageSubtitle' => '切换应用显示语言',
			'settings.followSystemLanguage' => '跟随系统',
			'settings.languageZhCn' => '简体中文 (zh_CN)',
			'settings.languageEnUs' => 'English (en_US)',
			'settings.languageChangedRestartHint' => '语言设置已保存，重启应用后全部生效',
			'settings.dynamicColor' => '动态取色',
			'settings.dynamicColorSubtitle' => '开启后自动提取内容主色',
			'settings.fontSettings' => '字体设置',
			'settings.fontSettingsSubtitle' => '自定义显示字体',
			'settings.amoled' => '纯黑模式',
			'settings.amoledSubtitle' => '开启后使用纯黑背景，适配 AMOLED',
			'settings.notchAdaptation' => '异形屏适配',
			'settings.notchAdaptationSubtitle' => '开启后预留安全区，避免内容遮挡',
			'settings.transparentDesktopTitleBar' => '透明标题栏',
			'settings.transparentDesktopTitleBarSubtitle' => '标题栏不再画底色，与页面背景连成一体（文字与窗口按钮可能因画面颜色而不易看清）；仅桌面端',
			'settings.transparentTitleBarRow' => '独立行',
			'settings.transparentTitleBarRowSubtitle' => '标题栏仍占一行，只是不带底色；内容从它下面开始（默认）',
			'settings.transparentTitleBarOverlay' => '融合浮层',
			'settings.transparentTitleBarOverlaySubtitle' => '内容顶到窗口顶部，标题栏浮在画面之上',
			'settings.toastStyle' => '提示样式',
			'settings.toastStyleSubtitle' => '设置应用内提示条的位置、时长与大小',
			'settings.toastSectionLayout' => '位置与尺寸',
			'settings.toastSectionAppearance' => '外观与行为',
			'settings.toastSectionBehavior' => '时长与动效',
			'settings.toastSectionStyle' => '显示效果',
			'settings.toastPosition' => '位置',
			'settings.toastPositionSubtitle' => '提示条停靠在屏幕的哪个角',
			'settings.toastPositionTopLeft' => '左上',
			'settings.toastPositionTopCenter' => '顶部居中',
			_ => null,
		} ?? switch (path) {
			'settings.toastPositionTopRight' => '右上',
			'settings.toastPositionMiddleLeft' => '左侧居中',
			'settings.toastPositionCenter' => '屏幕居中',
			'settings.toastPositionMiddleRight' => '右侧居中',
			'settings.toastPositionBottomLeft' => '左下',
			'settings.toastPositionBottomCenter' => '底部居中',
			'settings.toastPositionBottomRight' => '右下',
			'settings.toastEdgePadding' => '边缘留白',
			'settings.toastEdgePaddingSubtitle' => '提示条与屏幕边缘的距离',
			'settings.toastMaxWidth' => '最大宽度',
			'settings.toastMaxWidthSubtitle' => '提示条宽度上限，窄屏还会再被屏幕宽度收一次',
			'settings.toastMaxVisible' => '同屏条数',
			'settings.toastMaxVisibleSubtitle' => '屏幕上最多同时堆叠几条，多出来的挤掉最旧的一条',
			'settings.toastDuration' => '自动关闭时长',
			'settings.toastDurationSubtitle' => '拖到最左边为常驻，只由关闭按钮收起',
			'settings.toastDurationPermanent' => '常驻',
			'settings.toastOpacity' => '不透明度',
			'settings.toastOpacitySubtitle' => '整条提示（含文字）的不透明度',
			'settings.toastAnimation' => '进出场动画',
			'settings.toastAnimationSubtitle' => '提示出现与消失的动画时长',
			'settings.toastLiquidGlass' => '液态玻璃',
			'settings.toastLiquidGlassSubtitle' => '开启后提示条使用模糊半透明背景',
			'settings.toastShowProgressBar' => '显示进度条',
			'settings.toastShowProgressBarSubtitle' => '在底部显示一条随剩余时间收缩的细线',
			'settings.toastShowIcon' => '显示类型图标',
			'settings.toastShowIconSubtitle' => '在提示条左侧显示成功/错误等图标',
			'settings.toastShowCloseButton' => '显示关闭按钮',
			'settings.toastShowCloseButtonSubtitle' => '常驻提示会始终显示关闭按钮',
			'settings.toastPreview' => '显示测试提示',
			'settings.toastPreviewTitle' => '提示样式预览',
			'settings.toastPreviewLongMessage' => '这是一条用于预览的提示：长文本会自动换行，不会再被截断、也不会弹成对话框。',
			'settings.toastReset' => '恢复默认提示样式',
			'settings.toastResetDone' => '已恢复默认提示样式',
			'settings.contentAndNetwork' => '内容与网络',
			'settings.content' => '内容',
			'settings.fullSourceList' => '完整来源列表',
			'settings.fullSourceListSubtitle' => '关闭时，部分来源不会出现在发现页、搜索与插件商店；开启后显示全部来源',
			'settings.network' => '网络',
			'settings.maskedKeywords' => '屏蔽关键词',
			'settings.maskedKeywordsSubtitle' => '添加关键词，过滤不想看到的内容（仅搜索生效）',
			'settings.maskedKeywordsEmpty' => '暂无屏蔽词',
			'settings.maskedKeywordsInputHint' => '输入新关键词...',
			'settings.favoriteArtistHighlight' => '喜欢画师高亮',
			'settings.favoriteArtistHighlightSubtitle' => '在漫画卡片和详情页醒目标记喜欢的画师',
			'settings.cardBadges' => '卡片角标',
			'settings.cardDownloadBadge' => '下载角标',
			'settings.cardDownloadBadgeSubtitle' => '封面右上角显示下载按钮，点一下直接下载整本',
			'settings.cardTranslationBadge' => '语言角标',
			'settings.cardTranslationBadgeSubtitle' => '按标签识别「汉化 / 中文 / 生肉」并标记在封面左上角',
			'settings.cardReadButton' => '阅读按钮',
			'settings.cardReadButtonSubtitle' => '封面正中显示阅读按钮，点一下直接起读（有进度就续读），不必先进详情页',
			'settings.cardUnreadIndicator' => '未读标识',
			'settings.cardUnreadIndicatorSubtitle' => '下载后还没读过的书，在封面右上角的下载角标下方显示标识',
			'settings.cardUnreadIndicatorStyle' => '未读标识样式',
			'settings.cardUnreadIndicatorStyleSubtitle' => '三档辨识度递增、占的封面面积也递增，按观感自己挑',
			'settings.cardUnreadIndicatorStyleDot' => '圆点',
			'settings.cardUnreadIndicatorStyleDisc' => '圆片',
			'settings.cardUnreadIndicatorStyleLabel' => '文字',
			'settings.cardInteraction' => '卡片交互',
			'settings.shelfCardContextMenu' => '收藏 / 历史卡片右键菜单',
			'settings.shelfCardContextMenuSubtitle' => '右键条目弹出操作菜单（触摸端长按）；含打开、在文件管理新页签打开、复制标题与链接、收藏、移除',
			'settings.favoriteArtistManagement' => '喜欢画师管理',
			'settings.favoriteArtistManagementSubtitle' => ({required Object count}) => '已添加 ${count} 位画师',
			'settings.favoriteArtistManagementSubtitleEmpty' => '暂未添加画师',
			'settings.favoriteArtistInputHint' => '输入画师名称...',
			'settings.favoriteArtistAdd' => '添加',
			'settings.favoriteArtistBatchImport' => '批量导入/编辑',
			'settings.favoriteArtistBatchImportHint' => '每行输入一位画师或逗号分隔；[社团 (画师)] 会原样保留，两个名字都参与匹配',
			'settings.favoriteArtistImportSuccess' => ({required Object count}) => '已更新画师列表（共 ${count} 位）',
			'settings.favoriteArtistClear' => '清空全部',
			'settings.favoriteArtistClearConfirm' => '确定要清空所有喜欢的画师吗？',
			'settings.favoriteArtistCircleMode' => '社团名匹配',
			'settings.favoriteArtistCircleModeSubtitle' => '标题或标签里的社团名算不算命中喜欢画师',
			'settings.favoriteArtistCircleOff' => '不认社团名',
			'settings.favoriteArtistCircleFallback' => '仅在没有画师名时',
			'settings.favoriteArtistCircleIndependent' => '独立命中（画师优先）',
			'settings.favoriteArtistBadge' => '喜欢画师',
			'settings.addToFavoriteArtist' => '设为喜欢画师',
			'settings.removeFromFavoriteArtist' => '取消喜欢画师',
			'settings.addedToFavoriteArtist' => ({required Object name}) => '已添加到喜欢画师: ${name}',
			'settings.removedFromFavoriteArtist' => ({required Object name}) => '已从喜欢画师移除: ${name}',
			'settings.favoriteTagHighlight' => '收藏 tag 高亮',
			'settings.favoriteTagHighlightSubtitle' => '在漫画卡片和详情页醒目标记收藏的 tag',
			'settings.favoriteTagManagement' => '收藏 tag 管理',
			'settings.favoriteTagManagementSubtitle' => ({required Object count}) => '已添加 ${count} 个 tag',
			'settings.favoriteTagManagementSubtitleEmpty' => '暂未添加 tag',
			'settings.favoriteTagInputHint' => '输入 tag 名称...',
			'settings.favoriteTagAdd' => '收藏',
			'settings.favoriteTagSearchHint' => '搜索 tag...',
			'settings.favoriteTagNotFound' => '未找到匹配的 tag',
			'settings.favoriteTagBatchImport' => '批量导入/编辑',
			'settings.favoriteTagBatchImportHint' => '每行一个 tag；别名用 | 分隔，用于适配各站点的写法，例如 school_lolita | 学校萝莉 | School Lolita',
			'settings.favoriteTagImportSuccess' => ({required Object count}) => '已更新收藏 tag（共 ${count} 个）',
			'settings.favoriteTagClear' => '清空全部',
			'settings.favoriteTagClearConfirm' => '确定要清空所有收藏 tag 吗？',
			'settings.favoriteTagBadge' => '收藏 Tag',
			'settings.favoriteTagAliasSection' => '别名',
			'settings.favoriteTagAliasEmpty' => '未设置别名',
			'settings.favoriteTagAliasAdd' => '添加别名',
			'settings.favoriteTagAliasInputHint' => '该 tag 在某个站点里的写法...',
			'settings.favoriteTagAliasHint' => '别名用于适配不同图源对同一个 tag 的不同拼法；大小写、全半角和下划线的差异已经自动归一，不必再登记。',
			'settings.favoriteTagAdded' => ({required Object name}) => '已收藏 tag: ${name}',
			'settings.favoriteTagRemoved' => ({required Object name}) => '已取消收藏 tag: ${name}',
			'settings.favoriteTagAlreadyAdded' => ({required Object name}) => '已经收藏过这个 tag: ${name}',
			'settings.favoriteTagAliasAdded' => ({required Object name}) => '已添加别名: ${name}',
			'settings.favoriteTagAliasRemoved' => ({required Object name}) => '已移除别名: ${name}',
			'settings.favoriteTagAliasDuplicate' => '这个别名已经存在了',
			'settings.addToFavoriteTag' => '收藏此 tag',
			'settings.removeFromFavoriteTag' => '取消收藏此 tag',
			'settings.cardFavoriteTagBadge' => '收藏 tag 角标',
			'settings.cardFavoriteTagBadgeSubtitle' => '命中收藏 tag 时在封面左上角显示角标',
			'settings.chineseConvert' => '简繁转换',
			'settings.chineseConvertSubtitle' => '将漫画标题、简介、章节、评论等转为简体或繁体',
			'settings.chineseConvertOff' => '关闭',
			'settings.chineseConvertSimplified' => '简体中文',
			'settings.chineseConvertTraditional' => '繁体中文',
			'settings.proxy' => '代理',
			'settings.proxySubtitle' => '配置代理地址',
			'settings.proxyEnabledSubtitle' => '开启后网络请求将经过代理',
			'settings.proxyAddress' => '代理地址',
			'settings.proxyHint' => '请输入代理地址（HTTP / SOCKS5）',
			'settings.proxyCurrent' => ({required Object currentProxy}) => '当前代理：${currentProxy}',
			'settings.proxyType' => '代理类型',
			'settings.proxyTypeSubtitle' => '选择代理协议',
			'settings.proxyTypeHttp' => 'HTTP',
			'settings.proxyTypeSocks5' => 'SOCKS5',
			'settings.updateAccelerate' => '更新下载加速',
			'settings.updateAccelerateSubtitle' => '开启后优先使用代理加速 GitHub 更新链接',
			'settings.retryDownloadUntilSuccess' => '下载失败后持续重试',
			'settings.retryDownloadUntilSuccessSubtitle' => '下载失败时持续重试直到成功；返回 404 或空数据时停止重试',
			'settings.downloadSettings' => '下载设置',
			'settings.downloadConcurrency' => '下载并发数',
			'settings.downloadConcurrencySubtitle' => '同时下载图片的线程数，若经常遇到风控或限流建议设为 2~3',
			'settings.downloadTaskConcurrency' => '同时下载章节数',
			'settings.downloadTaskConcurrencySubtitle' => '同时下载几个章节；1 = 逐个下载，遇到风控或验证码时调小',
			'settings.downloadDelay' => '单图下载延时',
			'settings.downloadDelaySubtitle' => '每次图片请求之间的节流间隔，可有效规避源站风控 (429)',
			'settings.downloadAutoRetryCount' => '失败自动重试次数',
			'settings.downloadAutoRetryCountSubtitle' => '任务遇到网络偶发异常时自动退避重试的上限次数',
			'settings.sync' => '同步',
			'settings.syncConfig' => '同步配置',
			'settings.syncConfigSubtitle' => '进入页面，配置地址与鉴权信息',
			'settings.syncService' => '同步服务',
			'settings.syncServiceSubtitle' => '选择服务，统一管理同步策略',
			'settings.syncServiceNone' => '不启用',
			'settings.syncServiceWebdav' => 'WebDAV',
			'settings.syncServiceS3' => 'S3',
			'settings.autoSync' => '自动同步',
			'settings.autoSyncSubtitle' => '开启后在后台定期同步配置',
			'settings.notifyPersonalize' => '提示个性化',
			'settings.notifyPersonalizeSubtitle' => '决定哪些后台提示会打扰你；你主动操作的回应始终会显示',
			'settings.notifySummaryMasterOff' => '后台提示总闸已关',
			'settings.notifySummaryAllOn' => '后台提示全部会响',
			'settings.notifySummaryOffCount' => ({required Object count}) => '已静音 ${count} 项',
			'settings.notifySectionAmbient' => '后台自动提示',
			'settings.notifyMaster' => '自动提示',
			'settings.notifyMasterHint' => '总闸。关掉后下面这些全部静默；按钮的操作反馈不受影响',
			'settings.notifyMasterOffNote' => '总闸已关：下面这些值给你留着，但现在一律不响。',
			'settings.notifySectionOutside' => '这两类不归这张表管',
			'settings.notifySystemChannelNote' => '系统通知栏那一路（下载完成、追更）由系统管，要关去系统设置里关，这里关不掉它',
			'settings.notifyMergedSuffix' => ({required Object count}) => '（另有 ${count} 次同类提示）',
			'settings.notifyTopicAction' => '操作反馈',
			'settings.notifyTopicActionHint' => '点了按钮之后的回应，永远会显示，否则读起来像按钮坏了',
			'settings.notifyTopicReaderSwitch' => '阅读器切换提示',
			'settings.notifyTopicReaderSwitchHint' => '切书 / 翻页 / 触到最后一页那三条开关，在工作台的「切换提示」卡片里',
			'settings.notifyTopicSyncAutoSuccess' => '自动同步完成',
			'settings.notifyTopicSyncAutoSuccessHint' => '每 5 分钟一次的定期同步；同一句话 10 分钟内最多响一次',
			'settings.notifyTopicSyncAutoFailure' => '自动同步失败',
			'settings.notifyTopicSyncAutoFailureHint' => '配错或断网时过去每 5 分钟敲一次且关不掉；现在同一类错误 10 分钟合并成一条',
			'settings.notifyTopicDownloadComplete' => '下载完成',
			'settings.notifyTopicDownloadCompleteHint' => '每完成一本报一次；同一本的重复回调 60 秒内合并',
			'settings.notifyTopicDownloadFailed' => '下载失败',
			'settings.notifyTopicDownloadFailedHint' => '报错文案不同算不同的事，不互相合并',
			'settings.notifyTopicFollowUpdate' => '追更更新',
			'settings.notifyTopicFollowUpdateHint' => '启动后那一次自动检查；手动刷新追更算操作反馈，不会被静音',
			'settings.notifyTopicPluginMessage' => '插件脚本报信',
			'settings.notifyTopicPluginMessageHint' => '图源插件自己调出来的提示；脚本能在循环里连发，同一句话 3 秒内合并',
			'settings.notifyTopicIntentOpen' => '外部打开',
			'settings.notifyTopicIntentOpenHint' => '从系统右键菜单或链接调起时的落点提示',
			'settings.notifyTopicSystemPermission' => '通知权限',
			'settings.notifyTopicSystemPermissionHint' => '启动时申请系统通知权限被拒的那条提示',
			'settings.syncSettings' => '同步设置',
			'settings.syncSettingsSubtitle' => '开启后使用云端设置覆盖本地设置',
			'settings.syncPlugins' => '同步插件',
			'settings.syncPluginsSubtitle' => '开启后同步插件配置与安装状态',
			'settings.manualSyncSection' => '手动同步',
			'settings.uploadToCloud' => '上传到云端',
			'settings.uploadToCloudSubtitle' => '以本机数据为准，覆盖云端',
			'settings.downloadFromCloud' => '从云端同步到本机',
			'settings.downloadFromCloudSubtitle' => '以云端数据为准，应用到本机',
			'settings.manualUpload' => '立即上传',
			'settings.manualDownload' => '立即同步',
			'settings.manualUploadSuccess' => '已上传到云端',
			'settings.manualDownloadSuccess' => '已从云端同步到本机',
			'settings.manualSyncFailed' => '手动同步失败',
			'settings.appBehavior' => '应用行为',
			'settings.splashPage' => '开屏页',
			'settings.splashPageSubtitle' => '选择启动页，打开应用直达目标',
			'settings.startWithWorkspace' => '工作台',
			'settings.workspaceSleepCoveredUi' => '工作台盖住首页时休眠',
			'settings.workspaceSleepCoveredUiSubtitle' => '进工作台后释放底下列表的图片内存，退回时重新加载',
			'settings.panelTabRightClickHide' => '右键面板图标收起该面板',
			'settings.panelTabRightClickHideSubtitle' => '关掉后，泳道面板栏上的图标只负责切换面板，右键与长按不再收起面板。收起是静默的：图标会直接从面板栏消失，面板栏上没有恢复入口，误触后要回「泳道与面板看板」才能找回。',
			'settings.skipUpdateCheck' => '跳过更新检查',
			'settings.skipUpdateCheckSubtitle' => '本构建是 fork 版本，启动时不再请求上游最新版本，也不再弹出更新提示',
			'settings.desktopCloseBehavior' => '关闭行为',
			'settings.desktopCloseBehaviorSubtitle' => '选择点击关闭按钮时的行为',
			'settings.desktopCloseAsk' => '询问',
			'settings.desktopCloseHide' => '隐藏到托盘',
			'settings.desktopCloseClose' => '直接关闭',
			'settings.showMainWindow' => '显示主界面',
			'settings.exitApp' => '退出',
			'settings.appLock' => '应用锁',
			'settings.appLockSubtitle' => '开启后进入应用需要验证',
			'settings.autoFollowOnCollect' => '收藏自动追更',
			'settings.autoFollowOnCollectSubtitle' => '开启后收藏漫画时将自动加入追更列表',
			'settings.autoFavoriteOnDownload' => '下载自动收藏',
			'settings.autoFavoriteOnDownloadSubtitle' => '开启后下载漫画时将自动加入本地收藏',
			'settings.writeDownloadMetadataFile' => '下载写入元数据文件',
			'settings.writeDownloadMetadataFileSubtitle' => '下载完成后在漫画目录写入 original_comic_info.json 与 processed_comic_info.json，便于其他工具识别与再次导入',
			'settings.promptDownloadOptions' => '下载时询问选项',
			'settings.promptDownloadOptionsSubtitle' => '点下载时先选「整本 / 最近章节 / 挑选章节」；关闭后直接下载全部章节',
			'settings.leftHandMode' => '左手优化',
			'settings.leftHandModeSubtitle' => '开启后将悬浮按钮等操作按钮移到屏幕左侧',
			'settings.clickCoverToStartReading' => '点击封面开始阅读',
			'settings.clickCoverToStartReadingSubtitle' => '在漫画详情页点击封面直接开始阅读',
			'settings.searchHistoryGroupBySource' => '搜索历史按插件分时间线',
			'settings.searchHistoryGroupBySourceSubtitle' => '开启后每个图源各自一条搜索时间线，不再全部堆在一起；「聚合搜索」是跨全部插件搜出来的，「未分类」是这次改造之前留下的老记录，归属已经丢了',
			'settings.comicInfoInlineReadButton' => '详情页内置阅读按钮',
			'settings.comicInfoInlineReadButtonSubtitle' => '桌面端在操作行里「下载」旁边放一个阅读按钮，并撤掉右下角的悬浮按钮',
			'settings.comicInfoRailLiquidGlass' => '详情页操作栏液态玻璃',
			'settings.comicInfoRailLiquidGlassSubtitle' => '桌面端左右两颗悬浮胶囊改用液态玻璃材质；关掉则换成不透明实底加描边',
			'settings.androidKeepAlive' => '后台保活',
			'settings.androidKeepAliveSubtitle' => '开启后通过前台服务尽量保持应用在后台运行，会显示常驻通知',
			'settings.backPressExit' => '返回键退出',
			'settings.backPressExitSubtitle' => '开启后在首页按返回键将退出应用，关闭则仅返回首页',
			'settings.bookshelf' => '书架设置',
			'settings.bookshelfSubtitle' => '书架首页、记忆排序',
			'settings.bookshelfHomePage' => '书架首页',
			'settings.bookshelfHomePageSubtitle' => '选择书架默认展示的标签',
			'settings.bookshelfRememberFavoriteSort' => '收藏记忆排序',
			'settings.bookshelfRememberFavoriteSortSubtitle' => '开启后，收藏页会记住你最后一次选择的排序',
			'settings.bookshelfRememberHistorySort' => '历史记忆排序',
			'settings.bookshelfRememberHistorySortSubtitle' => '开启后，历史页会记住你最后一次选择的排序',
			'settings.bookshelfRememberDownloadSort' => '下载记忆排序',
			'settings.bookshelfRememberDownloadSortSubtitle' => '开启后，下载页会记住你最后一次选择的排序',
			'settings.customExportPath' => '自定义导出路径',
			'settings.exportIncludeCover' => '导出包含封面图',
			'settings.exportIncludeCoverSubtitle' => '打开后，导出的文件夹或 zip 里会额外带一张封面图（导出时要现场再取一次封面）。默认关：产物里只有该导的页和两份信息 JSON，封面仍按 JSON 里的地址在线显示',
			'settings.detailLayout' => '详情布局',
			'settings.detailLayoutSubtitle' => '开启后漫画列表显示为横排详情样式，含作者与分类信息',
			'settings.reverseChapters' => '章节倒序',
			'settings.reverseChaptersSubtitle' => '开启后漫画详情页章节默认倒序显示',
			'settings.storage' => '存储',
			'settings.cache' => '缓存',
			'settings.clearCache' => '清理缓存',
			'settings.clearCacheConfirm' => '确定要清理所有缓存文件吗？此操作不可撤销。',
			'settings.calculatingCache' => '计算中...',
			'settings.calculateCacheFailed' => '计算失败',
			'settings.dataBackup' => '本地导入/导出',
			'settings.dataBackupSubtitle' => '通过 ZIP 在移动端与桌面端迁移设置和数据，保留本机专属配置',
			'settings.includeDownloaded' => '包含下载的漫画',
			'settings.exportData' => '导出数据',
			'settings.importData' => '导入数据',
			'settings.imageProcessing' => '图片处理',
			'settings.realSr' => '图片超分（实验性）',
			'settings.ocr' => '漫画翻译（成品页）',
			'settings.ocrSubtitle' => '试验性功能，需下载权重与配置翻译端点',
			'settings.realSrSubtitle' => '试验性功能，可能不稳定',
			'settings.eink' => '墨水屏',
			'settings.einkSubtitle' => '翻页动画 · 整屏刷新 · 加载',
			'settings.einkPageTitle' => '墨水屏适配',
			'settings.einkDetected' => '已识别为墨水屏设备',
			'settings.einkNotDetected' => '未识别到墨水屏设备，可手动开启',
			'settings.einkEnabled' => '启用墨水屏模式',
			'settings.einkEnabledSubtitle' => '去除动画，并让屏幕定期整屏刷新',
			'settings.einkSectionAnimation' => '动画与过渡',
			'settings.einkNoRouteTransition' => '去除页面切换动画',
			'settings.einkNoRouteTransitionSubtitle' => '进入和退出页面直接出图，不做滑动淡入',
			'settings.einkNoScrollBounce' => '去除滚动回弹',
			'settings.einkNoScrollBounceSubtitle' => '长图模式拖到边界直接停住',
			'settings.einkSectionLoading' => '加载',
			'settings.einkSectionRefresh' => '刷新',
			'settings.einkRefreshMode' => '整屏刷新方式',
			'settings.einkRefreshNone' => '不刷新',
			'settings.einkRefreshWhite' => '白屏刷',
			'settings.einkRefreshFull' => '黑白全刷',
			'settings.einkRefreshHint' => '整屏刷新会闪一次白或黑白，用来清掉上一页残影。',
			'settings.einkRefreshNow' => '立即整屏刷新',
			'settings.einkRefreshDone' => '已完成整屏刷新',
			'settings.einkAutoRefreshTurns' => '每翻 N 页自动整屏刷新',
			'settings.einkAutoRefreshOff' => '不自动刷新',
			'settings.einkShowRefreshButton' => '显示刷新按钮',
			'settings.einkShowRefreshButtonSubtitle' => '阅读页角落常驻，随时手动整屏刷新',
			'settings.einkNoSpinner' => '加载时不转圈',
			'settings.einkNoSpinnerSubtitle' => '转圈动画会让墨水屏反复局刷并留下残影',
			'settings.autoRealSr' => '自动超分',
			'settings.resolutionThreshold' => '分辨率阈值',
			'settings.debug' => '调试',
			'settings.logAddress' => '日志转发地址',
			'settings.logAddressSubtitle' => '配置后实时转发日志到指定地址',
			'settings.memoryDebug' => '内存调试',
			'settings.memoryDebugSubtitle' => '开启后在界面显示内存占用信息',
			'settings.blockRustHttpRequests' => '拦截 Rust HTTP 请求',
			'settings.blockRustHttpRequestsSubtitle' => '开启后 Rust 端所有 HTTP 请求都会直接失败，不会发送到网络',
			'settings.showLayoutOverflowStripes' => '显示布局溢出条纹',
			'settings.showLayoutOverflowStripesSubtitle' => '关闭后不画黄黑斜纹、也不上报溢出错误；只覆盖本项目的布局，Flutter 自带控件要 profile 构建才看不到条纹',
			'settings.forceEnableImpeller' => '强制启用 Impeller',
			'settings.forceEnableImpellerSubtitle' => 'Android 实验性渲染后端',
			'settings.colorPreview' => '整点颜色看看',
			'settings.colorPreviewSubtitle' => '打开调色页，快速预览主题色',
			'settings.qjsRuntimeDebug' => 'QJS 运行时调试',
			'settings.qjsRuntimeDebugSubtitle' => '手动输入运行时 ID，抓取调试快照',
			'settings.qjsRuntimeSnapshot' => '调试快照',
			'settings.qjsRuntimeIdLabel' => '运行时 ID',
			'settings.qjsRuntimeIdHint' => '例如 0a0e5858-a467-4702-994a-79e608a4589d',
			'settings.qjsRuntimeCapture' => '抓取快照',
			'settings.qjsRuntimeCapturing' => '抓取中',
			'settings.qjsRuntimeCopyOutput' => '复制输出',
			'settings.qjsRuntimeNoOutput' => '暂无输出',
			'settings.qjsRuntimeFillId' => '请先输入运行时 ID',
			'settings.qjsRuntimeCapturedAt' => ({required Object dateTime}) => '已抓取 ${dateTime}',
			'settings.qjsRuntimeCaptureFailed' => ({required Object error}) => '抓取失败: ${error}',
			'settings.qjsRuntimeNoCopyContent' => '当前没有可复制的内容',
			'settings.qjsRuntimeCopied' => '已复制到剪贴板',
			'settings.colorPreviewVariableFont' => 'Variable Font 测试',
			'settings.colorPreviewFontLoaded' => ({required Object path}) => '已加载: ${path}',
			'settings.colorPreviewNoFont' => '还没加载字体，先试推荐样本或者手动选一个 TTF/OTF 文件。',
			'settings.colorPreviewLoadRecommended' => '加载推荐样本',
			'settings.colorPreviewSelectFont' => '选择字体文件',
			'settings.colorPreviewByWeight' => '按 fontWeight 渲染',
			'settings.colorPreviewByVariableAxis' => '按 variable axis 渲染',
			'settings.colorPreviewSystemDefault' => '系统默认字体对照',
			'settings.colorPreviewLoadingFont' => '正在加载字体...',
			'settings.colorPreviewLoadSuccess' => '加载成功，可以直接对比不同字重。',
			'settings.colorPreviewLoadFailed' => ({required Object error}) => '加载失败: ${error}',
			'settings.colorRed' => '红色',
			'settings.colorPink' => '粉色',
			'settings.colorPurple' => '紫色',
			'settings.colorDeepPurple' => '深紫色',
			'settings.colorIndigo' => '靛蓝色',
			'settings.colorBlue' => '蓝色',
			'settings.colorLightBlue' => '浅蓝色',
			'settings.colorCyan' => '青色',
			'settings.colorTeal' => '水鸭色',
			'settings.colorGreen' => '绿色',
			'settings.colorLightGreen' => '浅绿色',
			'settings.colorLime' => '酸橙色',
			'settings.colorYellow' => '黄色',
			'settings.colorAmber' => '琥珀色',
			'settings.colorOrange' => '橙色',
			'settings.colorDeepOrange' => '深橙色',
			'settings.colorBrown' => '棕色',
			'settings.colorGrey' => '灰色',
			'settings.colorBlueGrey' => '蓝灰色',
			'settings.colorMaskRed' => '面具红',
			'settings.colorPresets' => '预设颜色',
			'settings.coremlDebug' => 'CoreML 超分调试',
			'settings.coremlDebugSubtitle' => '使用绝对路径模型测试 CoreML 超分',
			'settings.aboutAndMore' => '关于与更多',
			'settings.changelog' => '更新日志',
			'settings.changelogSubtitle' => '查看各个版本的更新记录',
			'settings.aboutApp' => '关于应用',
			'settings.aboutAppSubtitle' => '关于 Rossi 的详细信息',
			'settings.pluginManagement' => '插件管理',
			'settings.debugMode' => '调试模式',
			'settings.debugAddress' => '调试地址',
			'settings.notSet' => '未设置',
			'settings.fileManager' => '文件管理器',
			'settings.fileManagerSubtitle' => '本地文件浏览的主页、工具栏与视图记忆',
			'settings.fileManagerSectionHome' => '主页',
			'settings.fileManagerHomeEnabled' => '启用主页键',
			'settings.fileManagerHomeEnabledSubtitle' => '关闭后文件管理器工具栏不再显示主页键',
			'settings.fileManagerHomePath' => '主页目录',
			'settings.fileManagerHomePathSubtitle' => '主页键跳到哪个目录',
			'settings.fileManagerHomePathEmpty' => '未设置',
			'settings.fileManagerHomePathPick' => '选择目录',
			'settings.fileManagerHomePathClear' => '清除主页',
			'settings.fileManagerHomePathCleared' => '已清除主页',
			'settings.fileManagerHomePathStale' => '该目录已不存在，请重新选择',
			'settings.fileManagerHomePathUnsupported' => '当前平台不支持选择目录',
			'settings.fileManagerOpenHomeOnStart' => '启动时默认打开主页',
			'settings.fileManagerOpenHomeOnStartSubtitle' => '文件管理器打开时直接落在主页目录；该目录已不存在时回退到就近还在的目录',
			'settings.fileManagerSectionToolbar' => '工具栏',
			'settings.breadcrumbStyle' => '面包屑样式',
			'settings.breadcrumbRestrained' => '克制型',
			'settings.breadcrumbRestrainedHint' => '规整圆角与轻量强调，适合日常浏览',
			'settings.breadcrumbExpressive' => '强表现型',
			'settings.breadcrumbExpressiveHint' => '柔和起伏与异形端点，突出当前目录',
			'settings.breadcrumbAncestors' => '展开上级路径',
			'settings.fileManagerSectionView' => '浏览视图',
			'settings.fileManagerRememberViewState' => '记住每个目录的视图与排序',
			'settings.fileManagerRememberViewStateSubtitle' => '每个目录各自记住视图、排序与筛选；关闭后浏览照常，只是不再记忆',
			'settings.fileManagerWrapGridTitle' => '封面网格完整显示文件名',
			'settings.fileManagerWrapGridTitleSubtitle' => '封面网格里的文件名按词换行，最多铺 6 行；格子的总高度不变，行数多了就把封面挤小。关闭时截成 2 行加省略号。两种状态下，鼠标停在整格上都会浮出完整文件名',
			'settings.fileManagerSectionSearch' => '搜索',
			'settings.fileManagerSearchSubfoldersDefault' => '默认连子目录一起搜',
			'settings.fileManagerSearchSubfoldersDefaultSubtitle' => '新建页签起手就开着「含子目录」。整库遍历在慢盘上实测要几十秒，所以默认只搜当前这一层；开着这条就不必每次去点那颗开关',
			'settings.fileManagerSectionTabs' => '页签',
			'settings.fileManagerRestoreTabs' => '自动恢复上次打开的页签',
			'settings.fileManagerRestoreTabsSubtitle' => '文件管理器打开时把上次那批页签摆回来。两个以上页签才记，而且只记目录（后退历史与搜索结果不记）；目录已经没了就落在就近还在的父目录。上次开着两个以上页签时，这条比「启动时默认打开主页」优先',
			'settings.fileManagerSectionFileOps' => '文件操作',
			'settings.fileManagerFileOperations' => '允许修改文件',
			'settings.fileManagerFileOperationsSubtitle' => '复制、移动、重命名、新建与删除。关闭后右键菜单、多选与操作条都会消失，文件管理器回到只看不改',
			'settings.fileManagerHomePathSet' => '主页已更新',
			'settings.shellIntegration' => '系统集成',
			'settings.shellIntegrationContextMenu' => '在右键菜单显示「用 Rossi 打开」',
			'settings.shellIntegrationContextMenuSubtitle' => '写当前用户的注册表（HKCU），不需要管理员权限；选中文件、选中文件夹、文件夹空白处三处都会出现。应用已经在运行时暂时不会把新目录递进来，要先开一个新 Rossi 窗口。',
			'settings.shellIntegrationRegistered' => '已加入右键菜单',
			'settings.shellIntegrationUnregistered' => '已从右键菜单移除',
			'settings.shellIntegrationStalePath' => '菜单项指向的已经不是当前这个 Rossi，关掉再打开一次即可修正',
			'settings.shellIntegrationRepair' => '修正指向',
			'settings.shellIntegrationMacHint' => 'macOS 的「打开方式 → Rossi」由应用包声明的文档类型决定，一直可用、没有开关；这颗开关只管 Windows。',
			'settings.openIntentMissing' => ({required Object path}) => '这个路径已经不在了：${path}',
			'settings.openIntentMultiSkipped' => ({required Object count}) => '一次只打开第一项，其余 ${count} 项已忽略',
			'settings.operationBinding' => '操作绑定',
			'settings.operationBindingEntrySubtitle' => '按键、点击分区与绑定包',
			'settings.operationBindingSubtitle' => '按键与点击对应哪个动作，由这张表决定。保存即刻生效，不需要重启。',
			'settings.operationBindingSectionSwitch' => '生效方式',
			'settings.operationBindingRuntime' => '用绑定表解析按键与点击',
			'settings.operationBindingRuntimeSubtitle' => '关掉后回到内置的固定键位（方向键、WASD、小键盘与 F11），下面的编辑不影响阅读。',
			'settings.operationBindingInvertWheel' => '滚轮按手推的方向翻页',
			'settings.operationBindingInvertWheelSubtitle' => '开启后：向上滚=上一页、向下滚=下一页（按手的动作算）。macOS 的系统「自然滚动」已经把滚动增量翻过一次，所以 Mac 上默认开启；关掉则按内容移动的方向算。录制按键与关掉绑定表时的旧规则用同一套判定。',
			'settings.operationBindingSectionKeyboard' => '键盘',
			'settings.operationBindingSectionTap' => '点击分区',
			'settings.operationBindingTapSubtitle' => '阅读区只分「左半 / 正中 / 右半」三档：上下两排与中排同一动作。',
			'settings.operationBindingAreaMiddleLeft' => '左半屏',
			'settings.operationBindingAreaMiddleCenter' => '正中',
			'settings.operationBindingAreaMiddleRight' => '右半屏',
			'settings.operationBindingUnbound' => '未绑定',
			'settings.operationBindingSectionBundle' => '绑定包',
			'settings.operationBindingImport' => '导入 JSON',
			'settings.operationBindingImportSubtitle' => '导入绑定包，支持 bindings 对象或数组；保留全部输入类型、上下文和后续动作。',
			'settings.operationBindingImportConfirm' => '载入',
			'settings.operationBindingImportLoaded' => ({required Object count}) => '已载入 ${count} 条绑定，保存后生效',
			'settings.operationBindingExport' => '导出 JSON',
			'settings.operationBindingExportSubtitle' => '复制当前正在编辑的整张表。',
			'settings.operationBindingCopy' => '复制',
			'settings.operationBindingCopied' => '绑定表已复制到剪贴板',
			'settings.operationBindingJsonHint' => '保存前会先做校验与冲突检查；导入的内容只有按下保存才会写入。',
			'settings.operationBindingSave' => '保存',
			'settings.operationBindingSaved' => '绑定表已保存，即刻生效',
			'settings.operationBindingDiscard' => '放弃修改',
			'settings.operationBindingDiscarded' => '已放弃未保存的修改',
			'settings.operationBindingDirtyHint' => '有未保存的修改。',
			'settings.operationBindingRestoreFactory' => '恢复出厂预设',
			'settings.operationBindingRestoreFactorySubtitle' => '恢复 Neo 默认的九宫格、滚轮、键盘和鼠标绑定，并重置轮盘。现有自定义绑定将被替换。',
			'settings.operationBindingAddKey' => '添加按键',
			'settings.operationBindingNoKeys' => '未绑定按键',
			'settings.operationBindingUnimplemented' => '本仓还没有这个动作的执行体',
			'settings.operationBindingRecordTitle' => '按下要绑定的键',
			'settings.operationBindingRecordHint' => '同时按住 Ctrl / Alt / Shift / Win 可以绑定组合键；按 Esc 取消。',
			'settings.operationBindingRecordUnsupported' => ({required Object label}) => '「${label}」没有平台无关的键名，无法绑定',
			'settings.operationBindingConflictTitle' => '存在冲突的绑定',
			'settings.operationBindingConflictBody' => '同一个输入只能有一条生效绑定。请删掉或停用其中一条，再保存。',
			'settings.operationBindingInvalidTable' => '这份绑定表读不懂，已拒绝保存',
			'settings.operationBindingCategoryNavigation' => '导航',
			'settings.operationBindingCategoryZoom' => '缩放',
			'settings.operationBindingCategoryView' => '视图',
			'settings.operationBindingCategorySession' => '会话',
			'settings.operationBindingActionNextPage' => '下一页',
			'settings.operationBindingActionPreviousPage' => '上一页',
			'settings.operationBindingActionFirstPage' => '第一页',
			'settings.operationBindingActionLastPage' => '最后一页',
			'settings.operationBindingActionPageLeft' => '向左翻页',
			'settings.operationBindingActionPageRight' => '向右翻页',
			'settings.operationBindingActionFullscreen' => '全屏',
			'settings.operationBindingActionToggleDirection' => '阅读方向切换',
			'settings.operationBindingActionBookMode' => '书籍模式',
			'settings.operationBindingActionResetView' => '重置视图',
			'settings.operationBindingActionToggleBars' => '唤出/收起上下栏',
			'settings.operationBindingActionOpenSettings' => '打开设置',
			'settings.operationBindingActionZoomIn' => '放大',
			'settings.operationBindingActionZoomOut' => '缩小',
			'settings.operationBindingActionFitWindow' => '适应窗口',
			'settings.operationBindingActionActualSize' => '实际大小',
			'settings.operationBindingActionRotateClockwise' => '旋转',
			'settings.operationBindingActionRotate180' => '旋转180度',
			'settings.operationBindingBoundAction' => '绑定的动作',
			'settings.operationBindingDisabledRow' => '已停用（不参与冲突判定）',
			'settings.operationBindingRemove' => '删除这条绑定',
			'settings.workspaceLayout' => '布局',
			'settings.workspaceLayoutSubtitle' => '默认启动视图 · 泳道焦点与独占 · 悬停唤出区',
			'settings.laneAndLayout' => '泳道与布局',
			'settings.defaultStartupView' => '默认启动视图',
			'settings.startupViewEdges' => '工作孔',
			'settings.startupViewSwimlane' => '泳道',
			'settings.startupViewHint' => '下次打开工作台时走哪条呈现。两种呈现共用同一份记账，切换不会重开当前这一本。',
			'settings.laneFocusSolo' => '泳道焦点与独占',
			'settings.laneFocusSoloSubtitle' => '控制主泳道独占、切换栏和边缘调阅的响应时机。',
			'settings.autoFocusReaderOnOpen' => '点阅读时跳到阅读器泳道',
			'settings.autoFocusReaderOnOpenSubtitle' => '点「阅读」（详情页那颗、封面上那颗都算，是同一个动作）时把视口和交互交给中央阅读器泳道。关掉后书照样开进那条泳道，但条带一动不动 —— 你可以继续在原来那条泳道里翻，想读的时候自己点过去。',
			'settings.readerSoloOnFocus' => 'Reader 聚焦时自动独占',
			'settings.readerSoloOnFocusSubtitle' => '把交互交给 Reader 时顺带独占整条可用宽，不必再点一次栏头的独占按钮。',
			'settings.showLaneNavigatorInSolo' => 'Reader 独占时显示泳道切换栏',
			'settings.showLaneNavigatorInSoloSubtitle' => '其余泳道收成紧凑轨留在条带里，点一条就把交互交给它；关掉则只剩 Reader，靠左右唤出区调回别的泳道。',
			'settings.manualScrollEnabled' => '允许手动横向滚动',
			'settings.manualScrollEnabledSubtitle' => '关掉之后条带仍会按激活与揭示自己滚到该看的位置，只是不再响应自己伸手的拖动与滚轮。',
			'settings.blockManualScrollInReaderFullscreen' => '阅读器全屏时禁止横向拖动泳道',
			'settings.blockManualScrollInReaderFullscreenSubtitle' => '全屏时横向手势只用于翻页，不再把整条泳道条带拽动（那会连阅读器一起拖动）。关掉后全屏与平时一样可拖。',
			'settings.laneHeaderChrome' => '泳道栏头',
			'settings.laneHeaderChromeSubtitle' => '栏头这一行画什么。只影响栏头本身，不动泳道里的内容。',
			'settings.showLaneWidthBadge' => '显示泳道宽度徽标',
			'settings.showLaneWidthBadgeSubtitle' => '在泳道标题右边画一颗当前宽度（如「400px」）。默认不画 —— 改宽度用栏头右键菜单里的「常规宽度」；不画时那一段宽度是还给标题与页签条的。',
			'settings.panelTabSortMode' => '面板页签条排序模式',
			'settings.panelTabSortModeSubtitle' => '开启后长按页签可拖动排序、拖到另一条泳道换位；关闭时按住页签横移就是切换面板（选中态随手指滑动）。',
			'settings.edgeRevealDelay' => '左右泳道展开延迟',
			'settings.readerHoverFocusDelay' => 'Reader 悬停重新聚焦延迟',
			'settings.readerHoverFocusEnable' => '启用 Reader 悬停重新聚焦',
			'settings.revealFocusesLane' => '呼出泳道后自动聚焦',
			'settings.revealFocusesLaneSubtitle' => '指针在视口左右边缘停够久，就把交互一并交给被揭示的泳道，不必再点一下；Reader 仍留一条窄缝，点它即可回到独占。关掉后揭示只是「看清楚」，离开一会儿自动收回 Reader。',
			'settings.panelLaneHoverFocus' => '面板泳道悬停聚焦',
			_ => null,
		} ?? switch (path) {
			'settings.panelLaneHoverFocusSubtitle' => '指针停在左/右泳道里够久也把它激活，与 Reader 共用上面那段延迟。折叠成紧凑轨的泳道不参与，免得读数时扫过去就跳焦点。',
			'settings.delayRangeHint' => '驻留多久才触发，单位毫秒。三套延时各自独立，改一个不会连带改坏另一个。',
			'settings.hoverRevealZones' => '悬停唤出区',
			'settings.hoverRevealZonesSubtitle' => '在画布上拖出矩形，决定指针停在哪儿会把对应内容调出来。',
			'settings.hoverRevealZonesHint' => '左右两条管泳道揭示，上管工作台顶栏，下管阅读器底栏。拖拽画框，选中后拖四角微调。',
			'settings.revealEdgeLeft' => '左侧',
			'settings.revealEdgeRight' => '右侧',
			'settings.revealEdgeTop' => '上栏',
			'settings.revealEdgeBottom' => '下栏',
			'settings.revealLinkHorizontal' => '左右联动',
			'settings.revealLinkVertical' => '上下联动',
			'settings.revealReset' => '重置悬停唤出区',
			'settings.revealFieldX' => 'X',
			'settings.revealFieldY' => 'Y',
			'settings.revealFieldWidth' => '宽',
			'settings.revealFieldHeight' => '高',
			'settings.revealZoneResetDone' => '已恢复出厂唤出区',
			'settings.operationBindingTabKeyboard' => '快捷键',
			'settings.operationBindingTabRadial' => '轮盘',
			'settings.operationBindingActionOpenRadial' => '唤出轮盘',
			'settings.operationBindingActionConfirmRadial' => '确认轮盘选项',
			'settings.operationBindingActionToggleLibrary' => '切换书库',
			'settings.operationBindingRadialEnable' => '启用轮盘',
			'settings.operationBindingRadialEnableSubtitle' => '关掉之后轮盘不再响应，槽位绑定原样保留',
			'settings.operationBindingRadialActiveWheel' => '默认轮盘',
			'settings.operationBindingRadialLayerUnit' => ({required Object count}) => '${count} 层',
			'settings.operationBindingRadialNew' => '新轮盘',
			'settings.operationBindingRadialDelete' => '删除轮盘',
			'settings.operationBindingRadialPreview' => '预览',
			'settings.operationBindingRadialReset' => '重置槽位',
			'settings.operationBindingRadialResetSubtitle' => '只重写这个轮盘的出厂槽位，你自绑的其它输入不动',
			'settings.operationBindingRadialHint' => ({required Object layers}) => '已启用 · ${layers} 层 · 点空格添加，点已有槽编辑',
			'settings.operationBindingRadialHintDisabled' => '已停用 · 阅读时不会唤出轮盘',
			'settings.operationBindingRadialAppearance' => '外观与几何',
			'settings.operationBindingRadialGeometrySummary' => ({required Object radius, required Object inner, required Object variant}) => 'r${radius} · 内${inner} · ${variant}',
			'settings.operationBindingRadialRadius' => '轮盘尺寸',
			'settings.operationBindingRadialInnerRadius' => '内半径（中心空洞）',
			'settings.operationBindingRadialSectors' => '每层格数',
			'settings.operationBindingRadialSlots' => '槽位',
			'settings.operationBindingRadialSlotsSubtitle' => '点击轮盘空槽或已有槽',
			'settings.operationBindingRadialName' => '轮盘名',
			'settings.operationBindingRadialSlotLabel' => ({required Object layer, required Object sector}) => '第 ${layer} 层 · 第 ${sector} 格',
			'settings.operationBindingRadialEmptySlot' => '空槽',
			'settings.operationBindingRadialUnbindSlot' => '解绑这一格',
			'settings.operationBindingRadialMaxMenus' => ({required Object max}) => '最多 ${max} 个轮盘',
			'settings.operationBindingRadialDeleteConfirm' => ({required Object name}) => '删除轮盘「${name}」？它的槽位绑定会一并移除。',
			'settings.operationBindingRadialDeleteLast' => '至少要留一个轮盘',
			'settings.operationBindingRadialInvalid' => '轮盘配置不合法，已拒绝保存',
			'settings.operationBindingRadialResetDone' => '已重置这个轮盘的出厂槽位',
			'settings.operationBindingRadialNewName' => ({required Object index}) => '轮盘 ${index}',
			'settings.operationBindingRadialEmptyWheel' => '新轮盘是空的：槽位需要你一格一格绑',
			'settings.operationBindingCategoryRadial' => '轮盘',
			'settings.operationBindingRadialItemKind' => '类型',
			'settings.operationBindingRadialKindAction' => '执行动作',
			'settings.operationBindingRadialKindMove' => '跳转轮盘',
			'settings.operationBindingRadialTargetWheel' => '目标轮盘',
			'settings.operationBindingRadialIcon' => '图标',
			'settings.operationBindingRadialIconAuto' => '按操作自动匹配',
			'settings.operationBindingRadialLabel' => '显示文字',
			'settings.operationBindingRadialSlotIndex' => '槽位',
			'settings.operationBindingRadialItemEnabled' => '启用这一格',
			'settings.operationBindingRadialMoveUp' => '前移',
			'settings.operationBindingRadialMoveDown' => '后移',
			'settings.operationBindingRadialDeleteItem' => '删除这一格',
			'settings.operationBindingRadialStartAngle' => '旋转角度',
			'settings.operationBindingRadialSweepAngle' => '扫过角',
			'settings.operationBindingRadialVariant' => '样式',
			'settings.operationBindingRadialVariantSlice' => '圆角按钮',
			'settings.operationBindingRadialVariantBubble' => '圆形按钮',
			'settings.operationBindingRadialLayerN' => ({required Object n}) => '第 ${n} 层',
			'settings.operationBindingRadialSelectedSlot' => '选中的槽位',
			'settings.operationBindingRadialPickHint' => '点轮盘上的一格来选它；空格会画成 +',
			'settings.operationBindingRadialEmptySlotRow' => '（空格）',
			'settings.operationBindingRadialActionLabel' => '动作',
			'settings.includeDownloadedSubtitle' => '导出时一并打包已下载的漫画文件',
			'bookshelf.collectedWorks' => '藏书',
			'bookshelf.readingNow' => '正在阅读',
			'bookshelf.unreadWorks' => '未读作品',
			'bookshelf.createFolderHint' => '把相关漫画放在一起，方便下次找到。',
			'bookshelf.title' => '书架',
			'bookshelf.favorite' => '收藏',
			'bookshelf.history' => '历史',
			'bookshelf.download' => '下载',
			'bookshelf.filter' => '筛选',
			'bookshelf.searchList' => '搜索列表',
			'bookshelf.newFolder' => '新建文件夹',
			'bookshelf.manage' => '管理',
			'bookshelf.importComic' => '导入漫画',
			'bookshelf.folderHint' => '书架说明',
			'bookshelf.removeFromFolder' => '移出文件夹',
			'bookshelf.deleteFavorite' => '删除收藏',
			'bookshelf.deleteHistory' => '删除历史记录',
			'bookshelf.deleteDownload' => '删除下载记录',
			'bookshelf.confirmDeleteSelected' => ({required Object count}) => '确定要删除选中的 ${count} 条记录吗？',
			'bookshelf.deletedRecords' => ({required Object count}) => '已删除 ${count} 条记录',
			'bookshelf.noFilterSource' => '暂无可筛选的插件来源',
			'bookshelf.sort' => '排序',
			'bookshelf.sortDesc' => '时间(晚→早)',
			'bookshelf.sortAsc' => '时间(早→晚)',
			'bookshelf.viewSortDesc' => '观看时间(晚→早)',
			'bookshelf.viewSortAsc' => '观看时间(早→晚)',
			'bookshelf.source' => '漫画源',
			'bookshelf.deselectAll' => '取消全选',
			'bookshelf.renameFolder' => '重命名收藏夹',
			'bookshelf.createFolder' => '新建收藏夹',
			'bookshelf.multiSelect' => '多选',
			'bookshelf.copyTo' => '复制到',
			'bookshelf.batchExport' => '批量导出',
			'bookshelf.batchDeleteFailed' => '批量删除失败',
			'bookshelf.deleteSelected' => '删除选中',
			'bookshelf.cancel' => '取消选择',
			'bookshelf.selectedCount' => ({required Object count}) => '已选择 ${count} 项',
			'bookshelf.folderComicCount' => ({required Object count}) => '${count} 本',
			'bookshelf.selectTargetFolder' => '选择目标文件夹（可多选）',
			'bookshelf.confirmDeleteFolderTitle' => '确认删除',
			'bookshelf.confirmDeleteFolderContent' => '确定要删除该文件夹吗？文件夹内的内容会被递归删除。',
			'bookshelf.confirmRemoveComicTitle' => '从文件夹移除',
			'bookshelf.confirmRemoveComicContent' => ({required Object title}) => '确定要从当前文件夹移除《${title}》吗？',
			'bookshelf.importComicZipOnly' => '开始导入漫画（仅支持 zip）',
			'bookshelf.importStarted' => '开始导入漫画（仅支持 zip）',
			'bookshelf.importCompleted' => ({required Object title}) => '导入完成：${title}',
			'bookshelf.comicExists' => '漫画已存在',
			'bookshelf.confirmOverwriteImport' => ({required Object title}) => '《${title}》已经存在于下载列表中，是否覆盖导入？',
			'bookshelf.noExportableComics' => '选中的项目中没有可导出的漫画',
			'bookshelf.batchExportCompleted' => ({required Object success, required Object total}) => '批量导出完成：${success}/${total}',
			'bookshelf.batchExportDeleted' => ({required Object count}) => '已删除 ${count} 本的本地下载',
			'bookshelf.batchExportKeptIncomplete' => ({required Object count}) => '${count} 本有页没能打包，已保留它们的本地下载',
			'bookshelf.batchExportFailed' => ({required Object error}) => '批量导出失败: ${error}',
			'bookshelf.confirmDeleteSelectedTitle' => '确认删除',
			'bookshelf.confirmDeleteSelectedContent' => '确定要删除选中的文件夹和漫画吗？文件夹会递归删除。',
			'bookshelf.cancelSelect' => '取消选择',
			'bookshelf.selectAll' => '全选',
			'bookshelf.moveTo' => '移动到',
			'bookshelf.addToFolder' => '加入文件夹',
			'bookshelf.folderName' => '文件夹名称',
			'bookshelf.helpContent' => '• 收藏和书架是联动的：收藏一本漫画，它会出现在书架里；只有把这本漫画从所有收藏文件夹里都删除，才会自动取消收藏。\n• 在漫画详情页“取消收藏”，会一次性从所有收藏文件夹里移除这本漫画。\n• 下载也是一样：只有把一本漫画从所有下载文件夹里都删除，才会自动删除它的下载文件。',
			'bookshelf.folderCreated' => '文件夹创建成功',
			'bookshelf.noComic' => '还没有漫画',
			'bookshelf.noHistory' => '还没有阅读记录',
			'bookshelf.noDownload' => '还没有下载记录',
			'bookshelf.nothingHere' => '啥都没有',
			'bookshelf.deleteAllDownloadRecordsAndFiles' => '删除所有下载记录及其文件',
			'bookshelf.clearHistoryRecords' => '清空历史记录',
			'bookshelf.confirmDeleteAllDownloadsContent' => '确定要删除所有下载记录及其文件吗？此操作不可恢复！',
			'bookshelf.confirmClearHistoryContent' => '确定要清空历史记录吗？此操作不可恢复！',
			'bookshelf.allDownloadRecordsAndFilesDeleted' => '所有下载记录及其文件已删除',
			'bookshelf.historyRecordsCleared' => '历史记录已清空',
			'bookshelf.batchExportTitle' => '选择导出方式',
			'bookshelf.batchExportSubtitle' => '请选择批量导出为压缩包或文件夹',
			'bookshelf.importCancelled' => '已取消导入',
			'bookshelf.importEpisodeFallback' => ({required Object index}) => '第${index}集',
			'bookshelf.importMissingJson' => '导入目录缺少必要的 JSON 文件',
			'bookshelf.importVersionUnsupported' => '该版本无法导入，请使用较新的软件版本导出后导入',
			'bookshelf.importMissingSource' => '该导出文件缺少来源信息，请使用新版软件重新导出后再导入',
			'bookshelf.importMissingComicId' => '无法获取漫画 ID',
			'bookshelf.importNoComicDir' => '未在压缩包中找到可导入的漫画目录',
			'bookshelf.importMultipleComicDirs' => '压缩包中包含多个漫画目录，请每次只导入一本',
			'bookshelf.importComicExistsUncovered' => ({required Object title}) => '漫画《${title}》已存在，未覆盖导入',
			'bookshelf.folderNameEmpty' => '文件夹名称不能为空',
			'bookshelf.folderNameSlash' => '文件夹名称不能包含 /',
			'bookshelf.folderNameExists' => '当前路径下已存在同名文件夹',
			'bookshelf.targetFolderNameExists' => ({required Object name}) => '目标位置已存在同名文件夹：${name}',
			'bookshelf.cannotMoveFolderToSelf' => '不能将文件夹移动到自身',
			'bookshelf.cannotMoveParentToChild' => '不能将父文件夹移动到子文件夹中',
			'bookshelf.cannotCopyFolderToSelfOrChild' => '不能复制文件夹到自身或其子路径下',
			'bookshelf.moveFoldersOnlyOneTarget' => '移动文件夹时只能选择一个目标文件夹',
			'bookshelf.confirmDeleteSelectedFavorites' => ({required Object count}) => '确定要删除选中的 ${count} 条收藏记录吗？',
			'bookshelf.confirmDeleteSelectedHistory' => ({required Object count}) => '确定要删除选中的 ${count} 条历史记录吗？',
			'bookshelf.confirmDeleteSelectedDownloads' => ({required Object count}) => '确定要删除选中的 ${count} 条下载记录及文件吗？',
			'comicInfo.chapterCount' => ({required Object count}) => '章节 · ${count}',
			'comicInfo.pageClosedFavoriteCancelled' => '页面已关闭，收藏操作已取消',
			'comicInfo.previewLoadFailed' => '预览加载失败',
			'comicInfo.showMoreChapters' => '显示更多章节',
			'comicInfo.noChaptersYet' => '暂无章节',
			'comicInfo.reverseOrderLabel' => '倒序',
			'comicInfo.restoreForwardOrder' => '恢复正序',
			'comicInfo.imagePreview' => '画面预览',
			'comicInfo.collapseDetails' => '收起详情',
			'comicInfo.workTools' => '作品工具',
			'comicInfo.refreshInformation' => '刷新信息',
			'comicInfo.cloudFavoriteIncomplete' => '云端收藏操作未完成',
			'comicInfo.follow' => '加入追更',
			'comicInfo.unfollow' => '不再追更',
			'comicInfo.exportComic' => '导出漫画',
			'comicInfo.cloudCollect' => '云收藏',
			'comicInfo.cloudCollected' => '已云收藏',
			'comicInfo.cloudCollectDisabled' => '该插件暂不支持此功能',
			'comicInfo.collectingToCloud' => '收藏到云端中...',
			'comicInfo.removingCloudCollection' => '取消云收藏中...',
			'comicInfo.cloudCollectSuccess' => '云收藏成功',
			'comicInfo.cloudUncollectSuccess' => '已取消云收藏',
			'comicInfo.cloudCollectIncomplete' => '云收藏操作未完成',
			'comicInfo.discontinued' => '此漫画已下架',
			'comicInfo.likes' => ({required Object count}) => '点赞 ${count}',
			'comicInfo.comments' => ({required Object count}) => '评论 ${count}',
			'comicInfo.collected' => '已收藏',
			'comicInfo.collect' => '收藏',
			'comicInfo.download' => '下载',
			'comicInfo.markRead' => '标记已读',
			'comicInfo.markUnread' => '标记未读',
			'comicInfo.markThroughRead' => '标记至此为已读',
			'comicInfo.clearReadMark' => '清除标记',
			'comicInfo.readStateMenu' => '阅读状态',
			'comicInfo.readStateMenuHint' => '标记只记录你的人为判决，不改动阅读进度，也不影响「继续阅读」的定位。',
			'comicInfo.markReadDone' => ({required Object count}) => '已标记 ${count} 话为已读',
			'comicInfo.markUnreadDone' => ({required Object count}) => '已标记 ${count} 话为未读',
			'comicInfo.markThroughReadDone' => ({required Object count}) => '已把此前 ${count} 话标记为已读',
			'comicInfo.readStateUnread' => '未读',
			'comicInfo.readStateInferred' => '读到过',
			'comicInfo.readStateManualRead' => '已标记已读',
			'comicInfo.readStateManualUnread' => '已标记未读',
			'comicInfo.downloadForbidden' => '该插件暂不支持此功能',
			'comicInfo.addedToCollection' => '已添加收藏',
			'comicInfo.removedFromCollection' => '已取消收藏',
			'comicInfo.confirmUncollectTitle' => '确认取消收藏',
			'comicInfo.confirmUncollectContent' => '此项操作会删除该漫画在所有文件夹的记录，是否确认删除？',
			'comicInfo.commentForbidden' => '该插件暂不支持此功能',
			'comicInfo.commentForbiddenTitle' => '禁止评论',
			'comicInfo.back' => '返回',
			'comicInfo.exportTitle' => '选择导出方式',
			'comicInfo.exportSubtitle' => '请选择将漫画导出为压缩包还是文件夹：',
			'comicInfo.folder' => '文件夹',
			'comicInfo.zip' => '压缩包',
			'comicInfo.exportSuccess' => '导出成功',
			'comicInfo.detailsNotLoaded' => '当前详情尚未加载完成',
			'comicInfo.followed' => '已加入追更',
			'comicInfo.unfollowed' => '已取消追更',
			'comicInfo.confirmUnfollowTitle' => '取消追更',
			'comicInfo.confirmUnfollowContent' => ({required Object title}) => '确定不再追更《${title}》吗？',
			'comicInfo.noChapters' => '暂无章节信息',
			'comicInfo.chapterList' => '章节目录',
			'comicInfo.preview' => '预览',
			'comicInfo.episodeCount' => ({required Object count}) => '${count} 话',
			'comicInfo.episodeFallback' => ({required Object index}) => '${index}',
			'comicInfo.episodeLabel' => ({required Object index}) => '${index}',
			'comicInfo.groupEpisodeCount' => ({required Object count}) => '${count} 话',
			'comicInfo.untitledGroup' => '未分组',
			'comicInfo.downloadGroup' => '下载本组',
			'comicInfo.author' => '作者',
			'comicInfo.tags' => '标签',
			'comicInfo.works' => '作品',
			'comicInfo.views' => ({required Object count}) => '浏览：${count}',
			'comicInfo.updateTime' => ({required Object time}) => '更新时间：${time}',
			'comicInfo.startRead' => '开始阅读',
			'comicInfo.continueRead' => '继续阅读',
			'comicInfo.lastRead' => '上次读到',
			'comicInfo.chapters' => '章节',
			'comicInfo.related' => '相关推荐',
			'comicInfo.description' => '简介',
			'comicInfo.collapse' => '收起',
			'comicInfo.expandFullText' => '展开全文',
			'comicInfo.readHistory' => '阅读记录',
			'comicInfo.copied' => ({required Object label}) => '已复制：${label}',
			'comicInfo.copiedToClipboard' => ({required Object name}) => '已将 ${name} 复制到剪贴板',
			'comicInfo.openOnSource' => '在原站打开',
			'comicInfo.liking' => '点赞中...',
			'comicInfo.unliking' => '取消点赞中...',
			'comicInfo.likeSuccess' => '点赞成功',
			'comicInfo.unlikeSuccess' => '已取消点赞',
			'comicInfo.likeDisabled' => '该插件暂不支持此功能',
			'comicInfo.localCollectFailed' => ({required Object error}) => '本地收藏失败: ${error}',
			'comicInfo.likeFailed' => ({required Object error}) => '点赞失败: ${error}',
			'comicInfo.loadFailedWithError' => ({required Object error}) => '${error}\n加载失败，请重试。',
			'comicInfo.exportPermissionDenied' => '未授予所有文件访问权限，导出已取消',
			'comicInfo.exportFailedWithError' => ({required Object error}) => '导出失败，请重试。\n${error}',
			'comicInfo.exportDirectory' => ({required Object displayPath}) => '导出目录：${displayPath}',
			'comicInfo.exportPathTooLong' => '导出目录路径过长，无法创建有效的导出结构',
			'comicInfo.zipExportPathTooLong' => '指定的 zip 导出路径超出系统路径长度限制',
			'comicInfo.downloadPathTooLong' => '下载目录路径过长，无法创建有效的 zip 文件路径',
			'comicInfo.uniqueFileNameTooLong' => '无法为章节创建不重复的文件名：超出路径长度限制',
			'comicInfo.exportFolderComplete' => ({required Object title}) => '漫画${title}导出为文件夹完成',
			'comicInfo.exportZipComplete' => ({required Object title}) => '漫画${title}导出为 zip 完成',
			'comicInfo.exportComicNotFound' => ({required Object comicId}) => '未找到可导出的下载漫画: ${comicId}',
			'comicInfo.exportDeleteAfter' => '导出成功后删除本地下载',
			'comicInfo.exportDeleteAfterSubtitle' => '只有全部页面都进了归档、文件确实写完，才会删除。任一条件不满足就保留本地下载，并说明原因。',
			'comicInfo.exportedAndDeleted' => ({required Object title}) => '已导出并删除本地下载：${title}',
			'comicInfo.exportDeleteSkippedIncomplete' => ({required Object count, required Object chapters}) => '有 ${count} 页没能打包进导出文件（${chapters}），已保留本地下载',
			'comicInfo.exportDeleteSkippedEmpty' => '本地没有任何可导出的页面，已保留本地下载',
			'comicInfo.exportDeleteSkippedArtifact' => '导出文件没通过完整性校验，已保留本地下载',
			'comicInfo.exportDeleteSkippedInsideRoot' => '导出位置就在下载目录里面，删下去会连导出一起删掉，已保留本地下载',
			'comicInfo.exportDeleteFailed' => ({required Object error}) => '导出完成，但删除本地下载失败：${error}',
			'comicInfo.pluginInvalidFavorited' => '插件未返回有效 favorited 状态',
			'comicInfo.pluginInvalidLiked' => '插件未返回有效 liked 状态',
			'comicInfo.addToCustomFolder' => '添加到自定义收藏夹',
			'comicInfo.addedToFolder' => ({required Object name}) => '已添加到收藏夹: ${name}',
			'comicInfo.skipAdd' => '跳过/不添加',
			'comicInfo.confirmAdd' => '确定添加',
			'comicInfo.resolveComicIdFailed' => ({required Object type}) => '无法解析阅读 comicId: ${type}',
			'comicInfo.resolveEpsCountFailed' => ({required Object type}) => '无法解析阅读章节数: ${type}',
			'comicInfo.collectToCloud' => '收藏到云端',
			'comicInfo.collectToLocal' => '收藏到本地',
			'comicInfo.removeCloudCollection' => '取消云端收藏',
			'comicInfo.removeLocalCollection' => '取消本地收藏',
			'reader.switchBookFailed' => ({required Object error}) => '切换书籍失败：${error}',
			'reader.pageDecodeFailed' => ({required Object n}) => '第 ${n} 页没能解出来',
			'reader.cannotOpenPath' => ({required Object path}) => '打不开：${path}',
			'reader.aiJpegDenoise' => 'AI JPEG 降噪',
			'reader.noMatchingOfflineComics' => '没有匹配的已离线漫画',
			'reader.searchOfflineComics' => '搜索已离线漫画',
			'reader.stateNotDownloadedAsk' => '未下载（开启时会先问一句）',
			'reader.stateDownloaded' => '已下载',
			'reader.stateOff' => '未开启',
			'reader.stateOn' => '已开启',
			'reader.cannotOpenLocalComic' => ({required Object error}) => '无法打开本地漫画: ${error}',
			'reader.cachedPages' => ({required Object count}) => '已缓存 ${count} 页',
			'reader.targetLanguageLabel' => ({required Object lang}) => '目标 ${lang}',
			'reader.bottomRevealPx' => ({required Object px}) => '底部唤出 (${px}px)',
			'reader.topRevealPx' => ({required Object px}) => '顶部唤出 (${px}px)',
			'reader.sourcePageOf' => ({required Object index, required Object total}) => '源第 ${index} / ${total} 页',
			'reader.manualPageOrderFor' => ({required Object name}) => '手动页序 · ${name}',
			'reader.tapToSwitchMode' => ({required Object from, required Object to}) => '${from}（点击切为${to}）',
			'reader.modelState' => ({required Object state}) => '模型：${state}',
			'reader.modelDownloadFailed' => ({required Object error}) => '下载模型失败: ${error}',
			'reader.activeThreshold' => ({required Object value}) => '生效阈值：${value}',
			'reader.globalDefaultState' => ({required Object state}) => '全局（所有书默认）：${state}',
			'reader.thisBookState' => ({required Object state}) => '本书：${state}',
			'reader.upscaleChipTail' => ({required Object tooltip}) => '${tooltip}\n点击切换；按住暂看原图；右侧电源只影响本书',
			'reader.notWiredIntoReader' => ({required Object name}) => '${name} 还没接进本仓的阅读器',
			'reader.notImplementedYet' => ({required Object name}) => '${name}（本仓尚未实现）',
			'reader.oneScreenPercent' => ({required Object percent}) => '一屏 ${percent}%',
			'reader.slideshowDwellHint' => ({required Object step, required Object min, required Object max}) => '每一页停多久：一步 ${step}，${min}~${max} 之间',
			'reader.manualRotationDeg' => ({required Object deg}) => '手动旋转 ${deg}°',
			'reader.loupeSizeRange' => ({required Object min, required Object max}) => '窗口边长，逻辑像素（${min}~${max}，一次 20）',
			'reader.loupeZoomRange' => ({required Object min, required Object max}) => '放大倍率（${min}%~${max}%，一档 25%，400% 起一档翻倍）',
			'reader.intervalSeconds' => ({required Object seconds}) => '间隔 ${seconds}s',
			'reader.tapToExpandPanel' => ({required Object label}) => '${label}（点击展开面板）',
			'reader.zoomModeValue' => ({required Object mode}) => '缩放模式：${mode}',
			'reader.imageProcessingOffReaderHint' => '图像处理已关闭，可在阅读设置中打开开关',
			'reader.gpuTextureUnsupported' => '当前平台不支持 GPU 纹理处理',
			'reader.thisPage' => '当前页',
			'reader.pendingUpscale' => '待超分',
			'reader.upscaleFailedState' => '超分失败',
			'reader.noUpscaleNeeded' => '无需超分',
			'reader.upscaledState' => '已超分',
			'reader.generatedState' => '已生成',
			'reader.upscalingState' => '超分中',
			'reader.queuedState' => '排队中',
			'reader.originalCompareChip' => '原图对比',
			'reader.upscaleOff' => '超分关',
			'reader.notSupported' => '不支持',
			'reader.noProcessingNeeded' => '无需处理',
			'reader.denoiseFailed' => '降噪失败',
			'reader.enhanceFailed' => '增强失败',
			'reader.pendingDenoise' => '待降噪',
			'reader.pendingEnhance' => '待增强',
			'reader.denoisedDone' => '已降噪',
			'reader.enhancedDone' => '已增强',
			'reader.denoising' => '降噪中',
			'reader.enhancing' => '增强中',
			'reader.upscaleShort' => '超分',
			'reader.jpegDenoise' => 'JPEG 降噪',
			'reader.denoisePlusUpscale' => '降噪+超分',
			'reader.tooltipIdle' => ({required Object page, required Object process, required Object hint}) => '${page} 还没开始${process}${hint}',
			'reader.tooltipFailed' => ({required Object page, required Object process, required Object hint}) => '${page} ${process} 失败，继续显示原图${hint}',
			'reader.tooltipSkipped' => ({required Object page, required Object hint}) => '${page} 无需处理${hint}',
			'reader.tooltipApplied' => ({required Object page, required Object process, required Object hint}) => '${page} 已使用${process}图片${hint}，点这里对比原图',
			'reader.tooltipReady' => ({required Object page, required Object hint}) => '${page} 处理后图片已生成，等待上屏${hint}',
			'reader.tooltipRunning' => ({required Object page, required Object process, required Object hint}) => '${page} ${process} 中…${hint}',
			'reader.tooltipQueued' => ({required Object page, required Object process, required Object hint}) => '${page} 已排队，等待${process}${hint}',
			'reader.tooltipComparing' => ({required Object hint}) => '正在对比原图，点这里切回处理后画面${hint}',
			'reader.sizeHintSource' => ({required Object source}) => '（原图 ${source}）',
			'reader.sizeHintEnhanced' => ({required Object enhanced}) => '（处理后 ${enhanced}）',
			'reader.sizeHintBoth' => ({required Object source, required Object enhanced}) => '（原图 ${source} → 处理后 ${enhanced}）',
			'reader.pageNumberN' => ({required Object page}) => '第 ${page} 页',
			'reader.missingWeightsCount' => ({required Object count}) => '缺 ${count} 项权重',
			'reader.noMissingWeights' => '（没有缺失项，直接过）',
			'reader.fitWindow' => '适应窗口',
			'reader.autoTrimEnabledByDefault' => '默认启用自动裁边',
			'reader.alignHeight' => '高度对齐（双页高度统一）',
			'reader.dwellIndicatorOff' => '驻留指示已关闭：放映到哪一页只能靠猜',
			'reader.firstPageAloneOn' => '首页独立显示：开',
			'reader.firstPageAloneOff' => '首页独立显示：关',
			'reader.rotateClockwise90' => '顺时针旋转 90°',
			'reader.pageSorting' => '页面排序',
			'reader.pageLayout' => '页面布局',
			'reader.pageOrder' => '页序',
			'reader.trimSideLimitHint' => '限制每一侧最多裁掉的比例；0% 等同于保留完整页面',
			'reader.denoiseAdvancedSettings' => '降噪高级设置',
			'reader.denoiseBlockSize' => '降噪分块大小',
			'reader.denoiseShort' => '降噪',
			'reader.thresholdLabel' => '阈值',
			'reader.startWeightsInReaderSettings' => '阅读器设置里开始下载权重：',
			'reader.readerSafeMarginBothSides' => '阅读器两侧是否保留适度安全边距',
			'reader.intervalLabel' => '间隔',
			'reader.lockLoupe' => '锁止',
			'reader.fillWholeWindow' => '铺满整个窗口',
			'reader.resetViewTransform' => '重置缩放、旋转与宽页策略（保留单双页与阅读方向）',
			'reader.rotateCounterclockwise90' => '逆时针旋转 90°',
			'reader.fitHeight' => '适应高度',
			'reader.fitWidth' => '适应宽度',
			'reader.pageNotLoadedYet' => '这一页还没加载出来，稍等一下再译',
			'reader.loadingSettings' => '读取设置…',
			'reader.translationHiddenByCompare' => '译文已经生成并注入，正被「对比原图」挡着：切回超分就显示译文',
			'reader.trigger' => '触发',
			'reader.trimAdvancedSettings' => '裁边高级设置',
			'reader.pointerTypeAuto' => '自动：按指针自己的类型选 —— 鼠标/触控板跟随悬停，手指与触屏笔按住才出窗口（不看平台，触屏笔记本与外接鼠标都判得对）',
			'reader.autoTranslateShort' => '自动译',
			'reader.autoRotate' => '自动旋转',
			'reader.autoSplitLandscapeOn' => '自动分割横向页：开',
			'reader.autoSplitLandscapeOff' => '自动分割横向页：关',
			'reader.backgroundTolerance' => '背景检测容差',
			'reader.autoTranslateEnabled' => '翻页自动翻译已开启',
			'reader.zoomMode' => '缩放模式',
			'reader.editManualOrder' => '编辑本章的手动顺序',
			'reader.rotatePortraitLeft' => '纵向页左旋',
			'reader.rotatePortraitRight' => '纵向页右旋',
			'reader.chapterShort' => '章',
			'reader.downloadNow' => '立即下载',
			'reader.confirmResetAndRedownload' => '确认要重置进度并重新下载本漫画吗？',
			'reader.zoomShortReset' => '短按重置为 100%；按住可输入百分比',
			'reader.marginWhitespace' => '留白',
			'reader.noBookOpenYet' => '现在没有打开的书 —— 开一本之后这一颗才能给它单独设',
			'reader.layoutTools' => '版式工具',
			'reader.autoScroll' => '滚屏',
			'reader.clearManualOrder' => '清除本章的手动顺序',
			'reader.removeTwoPageSeam' => '消除双页之间的拼接缝隙',
			'reader.downloadingUpscaleInBackground' => '正在后台下载超分模型...',
			'reader.landscape' => '横屏',
			'reader.rotateLandscapeLeft' => '横向页左旋',
			'reader.rotateLandscapeRight' => '横向页右旋',
			'reader.formatLabel' => '格式',
			'reader.webtoonStepScreens' => '条漫（上下滚动）每一拍推进多少屏：只作用于条漫，横翻按整页走',
			'reader.webtoonTrimSidesOnly' => '条漫只裁左右，保留上下接缝。满版或检测不可靠的页面保留原样。',
			'reader.weights' => '权重',
			'reader.noManualOrderHere' => '本章没有手动顺序可清除',
			'reader.bookImageProcessing' => '本书：图像处理',
			'reader.bookEnableAiUpscale' => '本书：启用 AI 超分辨率',
			'reader.bookUpscaleOnFetch' => '本书已开启超分（后续取图在取图层处理）',
			'reader.bookAiUpscaleOn' => '本书已启用 AI 超分',
			'reader.bookTrimOnOverride' => '本书已单独开启裁边 · 全局为关闭',
			'reader.bookTrimOffOverride' => '本书已单独关闭裁边 · 全局为开启，当前阅读不会裁边',
			'reader.bookUpscaleOff' => '本书已关闭超分（其它书仍按全局设置）',
			'reader.bookAiUpscaleOff' => '本书已关闭 AI 超分（其它书仍按全局设置）',
			'reader.bookEnableJpegDenoise' => '本书启用 JPEG 降噪',
			'reader.loupeUnlockedFollows' => '未锁止：指针一离开画面、手指一抬，窗口就收掉；锁止后窗口留在原地，可以先拖到别处再对焦点',
			'reader.notDownloaded' => '未下载',
			'reader.pauseResumeAutoScroll' => '暂停 / 继续自动滚屏',
			'reader.logLabel' => '日志',
			'reader.alignNone' => '无对齐（保持原始比例）',
			'reader.rotationSettings' => '旋转设置',
			'reader.fileSize' => '文件大小',
			'reader.pageOrderNatural' => '文件名自然序（page2 排在 page10 前）',
			'reader.fileLabel' => '文件',
			'reader.slideshowOffTapStart' => '放映未开启：点击开始放映',
			'reader.slideshowDwellIndicator' => '放映时在画面上显示「第几页 / 是否暂停」',
			'reader.slideshowOnButIdle' => '放映已开启但没在计时：点击继续',
			'reader.slideshowStoppedAtEnd' => '放映已到本章末尾并停止',
			'reader.slideshowPlayingTapPause' => '放映中，点击暂停',
			'reader.slideshowPlaying' => '放映中',
			'reader.slideshowFinished' => '放完',
			'reader.loupeTooltip' => '放大镜：把指针那一小块像素原样放大到旁边的窗口里（检网点与端部细节）',
			'reader.loupeEnabled' => '放大镜已开：把指针那一小块像素原样放大到旁边的窗口里',
			'reader.loupe' => '放大镜',
			'reader.slideshowAdvanceChapter' => '放到章末就翻进下一章；没有下一章时停住',
			'reader.slideshowLoopInChapter' => '放到章末就回到第一页，一直放',
			'reader.slideshowStopAtChapterEnd' => '放到本章最后一页就停住，并关掉放映',
			'reader.inference' => '推理',
			'reader.onDemandTranslateOcr' => '按需嵌字翻译与端侧 OCR',
			'reader.detectByFileHeader' => '按文件头识别。PNG、WebP 等页面保留原样',
			'reader.dragReorderStaysOnPage' => '拖动调整显示顺序；应用后画面仍停在当前这一页',
			'reader.openChapterListToDrag' => '打开本章页面列表并拖出顺序（以当前顺序为起点）',
			'reader.perBookAfterOpening' => '打开在线或本地漫画后可单独设置',
			'reader.touchHoldToShow' => '手指：按住才出窗口，抬手即收（配锁止可拖窗口移动）',
			'reader.manualOrderDragList' => '手动顺序（在页面列表里拖）',
			'reader.manualZoom' => '手动缩放',
			'reader.denoiseDefaultForAll' => '所有漫画默认启用降噪',
			'reader.allBooksDefaultCurrentlyOff' => '所有书的默认，现在关着；打开后没有单独设置的书都会跟着开',
			'reader.allBooksDefaultShared' => '所有书的默认（与设置页那条同一条）',
			'reader.hoverFollowsMouse' => '悬停：只跟随鼠标，指针离开画面即收',
			'reader.hoverScroll' => '悬停滚动',
			'reader.restoreDefaultParams' => '恢复默认参数',
			'reader.restoreConservativeDefaults' => '恢复保守默认值',
			'reader.mimageModelMissingPrompt' => '当前设备尚未下载 mImage ONNX 超分模型（约 5.4 MB），是否立即下载并启用？',
			'reader.noImageInfoAvailable' => '当前没有可读取的图片信息',
			'reader.noRealPlksrBackendHere' => '当前平台暂无 RealPLKSR 推理后端',
			'reader.pageAnimationOn' => '当前已开启平滑翻页动画',
			'reader.pageAnimationOff' => '当前已关闭翻页动画',
			'reader.currentImage' => '当前图片',
			'reader.translateOnDeviceNow' => '当前使用端侧离线翻译引擎，无需网络即可生成译文页',
			'reader.translateCloudEndpointNow' => '当前使用云端 API 端点翻译，自动擦除原气泡并回填译文',
			'reader.force' => '强制',
			'reader.engine' => '引擎',
			'reader.enableAutoScroll' => '开启自动滚屏',
			'reader.enableBookUpscale' => '开启本书超分',
			'reader.slideshow' => '幻灯片放映',
			'reader.loupeLockedOn' => '已锁止：指针离开画面、手指抬起后窗口仍留着，拖窗口本身可以移动它；双击窗口可取消锁止',
			'reader.requeuedToDownload' => '已重新加入下载队列',
			'reader.alreadyDisabled' => '已禁用',
			'reader.manualOrderClearedDone' => '已清除本章的手动顺序',
			'reader.slideshowPausedTapResume' => '已暂停，点击继续放映（不改设置）',
			'reader.autoScrollEnabled' => '已开启自动滚屏',
			'reader.trimOnAutoDetect' => '已开启 · 白边和黑边自动检测',
			'reader.denoiseOnRealPlksr' => '已开启 · RealPLKSR 1×',
			'reader.switchedToOriginalCompare' => '已切换为原图对比',
			'reader.switchedBackToProcessed' => '已切回处理后画面',
			'reader.trimOffFullPage' => '已关闭 · 显示完整页面',
			'reader.trimOffOriginalKept' => '已关闭 · 原图保持不变',
			'reader.fitWindowLeft' => '居左适应窗口',
			'reader.fitWindowRight' => '居右适应窗口',
			'reader.compareOriginal' => '对比原图',
			'reader.widePagePolicy' => '宽页策略',
			'reader.alignWidth' => '宽度对齐（双页宽度统一）',
			'reader.safeMargin' => '安全留边',
			'reader.processingStatus' => '处理状态',
			'reader.bgToleranceHint' => '增大可容忍纸张底色和轻微噪点；浅色细节较多时使用较小值',
			'reader.onlineUpscaleAtFetchLayer' => '在线图源：超分在取图/解码层发生，这颗是本书的开关（没有逐页状态）',
			'reader.sharedUpscaleEnlarge' => '在线和本地漫画共用；阅读时放大内容区域',
			'reader.sharedDenoiseThenUpscale' => '在线和本地漫画共用；保持原分辨率，降噪后再超分',
			'reader.trimSafeMarginKeeps' => '在检测内容周围额外保留空间，保护文字、页码和线条',
			'reader.pageOrderSource' => '图源顺序（插件/归档给的顺序）',
			'reader.imageProcessing' => '图像处理',
			'reader.readback' => '回读',
			_ => null,
		} ?? switch (path) {
			'reader.backend' => '后端',
			'reader.onlyThisBookAskFirst' => '只影响这本书；模型未下载，开启时会先问一句',
			'reader.onlyThisBookGlobalOthers' => '只影响这本书，其它书仍按全局设置',
			'reader.onlyThisComicUpscaleOwn' => '只影响当前漫画；超分由它自己的开关决定',
			'reader.twoPagesIndependent' => '双页独立',
			'reader.twoPageModeTap' => '双页模式（点击切为单页）',
			'reader.twoPages' => '双页',
			'reader.originalSize' => '原始大小',
			'reader.comparingOriginal' => '原图对比中',
			'reader.singlePageModeTap' => '单页模式（点击切为双页）',
			'reader.singlePage' => '单页',
			'reader.trimSideLimit' => '单边裁切上限',
			'reader.animatedNotProcessed' => '动画页面不参与处理。模型效果强度固定；原图、降噪和超分结果分别缓存。',
			'reader.animated' => '动画',
			'reader.toggleReaderFilter' => '切换阅读滤镜与护眼遮罩',
			'reader.resolution' => '分辨率',
			'reader.blockLabel' => '分块',
			'reader.disableAutoScroll' => '关闭自动滚屏',
			'reader.disableAutoRotate' => '关闭自动旋转',
			'reader.disableBookUpscale' => '关闭本书超分',
			'reader.wholeBook' => '全本',
			'reader.panoramaMode' => '全景模式',
			'reader.pageOrderReversed' => '倒序（本章页表整个反过来）',
			'reader.scaleLabel' => '倍率',
			'reader.notWiredBelow' => '以下尚未接进本仓',
			'reader.jpegPagesOnly' => '仅处理 JPEG 页面',
			'reader.peekOriginalBriefly' => '临时查看原图，关闭后恢复处理结果',
			'reader.peekBackToOriginal' => '临时切回原图，关闭后恢复处理结果',
			'reader.denoiseBlockIndependentHint' => '与超分独立。较小的分块降低推理内存占用；固定输入模型按模型尺寸处理',
			'reader.denoiseOriginalSafeBefore' => '不修改原图；降噪在超分之前运行',
			'reader.denoiseOriginalSafeBookOverride' => '不修改原图；单本开关仍可在阅读设置覆盖',
			'reader.downloadPreference' => '下载偏好',
			'reader.downloadAiUpscaleModel' => '下载 AI 超分模型',
			'reader.rotateAlwaysLeft' => '一律左旋',
			'reader.rotateAlwaysRight' => '一律右旋',
			'reader.ocrWeightsReady' => 'OCR 权重就绪',
			'reader.neoviewViewportDemo' => 'NeoView 视口感应交互示意',
			'reader.denoiseModelMissing' => 'JPEG 降噪模型未安装',
			'reader.aiSuperResolution' => 'AI 超分辨率',
			'reader.downloadManage' => '下载管理',
			'reader.startDownload' => '开始下载',
			'reader.pauseDownload' => '暂停下载',
			'reader.resumeDownload' => '继续下载',
			'reader.restartDownload' => '重新下载',
			'reader.deleteDownload' => '删除下载',
			'reader.retryFailedParts' => '重试失败部分',
			'reader.retryFailedPartsSubtitle' => '仅重新下载未完成或失败的章节与图片',
			'reader.restartDownloadSmart' => '增量补全（推荐）',
			'reader.restartDownloadSmartDesc' => '检测本地已下载内容，仅下载缺失或失败的图片',
			'reader.restartDownloadFull' => '全量重下',
			'reader.restartDownloadFullDesc' => '重置全部章节进度，从头完整下载',
			'reader.pickAndExtract' => '选图提取',
			'reader.pickAndExtractSubtitle' => '挑选特定图片导出或保存',
			'reader.saveToAlbum' => '保存至相册',
			'reader.saveToDirectory' => '导出至文件夹',
			'reader.exportZip' => '导出为 ZIP',
			'reader.downloadSelected' => '下载选中项',
			'reader.selectAll' => '全选',
			'reader.deselectAll' => '取消全选',
			'reader.invertSelection' => '反选',
			'reader.rangeSelect' => '范围选择',
			'reader.rangeSelectPrompt' => '输入页码范围，例如: 1-5, 8, 12',
			'reader.selectedCount' => ({required Object selected, required Object total}) => '已选 ${selected} / ${total} 页',
			'reader.extractingProgress' => ({required Object current, required Object total}) => '正在处理中: ${current} / ${total}',
			'reader.extractSuccess' => '提取完成',
			'reader.extractFailed' => ({required Object error}) => '提取失败: ${error}',
			'reader.viewAllTasks' => '查看全部下载任务',
			'reader.downloadStatusDownloading' => '正在下载',
			'reader.downloadStatusPaused' => '已暂停',
			'reader.downloadStatusCompleted' => '已完成',
			'reader.downloadStatusFailed' => '下载出错',
			'reader.downloadStatusQueued' => '等待中',
			'reader.confirmDeleteDownloadTitle' => '删除下载',
			'reader.confirmDeleteDownload' => '确认删除该漫画的下载任务及本地文件吗？',
			'reader.downloadStartedToast' => '已开始下载本漫画',
			'reader.autoCollectedToast' => '已自动添加至收藏',
			'reader.readWhileDownloading' => '边看边下载',
			'reader.readWhileDownloadingSubtitle' => '阅读时自动将已看内容保存到本地下载目录',
			'reader.pageMode' => '翻页模式',
			'reader.fullscreen' => '全屏模式',
			'reader.leftHandMode' => '左手模式',
			'reader.rightHandMode' => '右手模式',
			'reader.reverseHorizontalPageTurn' => '反转左右方向键',
			'reader.reverseHorizontalPageTurnSubtitle' => '交换左右方向键的翻页方向，适合从右到左的日漫',
			'reader.webtoonTapPageTurn' => '条漫点击翻动',
			'reader.enableWebtoonTapPageTurn' => '允许点击上下翻动',
			'reader.webtoonTapPageTurnSubtitle' => '条漫模式下点击上方/下方区域翻动，中央区域仍用于打开操作栏',
			'reader.readingMode' => '阅读模式',
			'reader.perComicReadMode' => '启用本漫画设置',
			'reader.perComicReadModeSubtitle' => '仅当前漫画生效',
			'reader.perComicFollowGlobal' => '跟随全局',
			'reader.perComicGlobalIs' => '全局为',
			'reader.perComicThisComic' => '本漫',
			'reader.infoDisplay' => '信息项显示',
			'reader.pageNumber' => '页数',
			'reader.pageNumberSubtitle' => '显示当前页/总页数',
			'reader.networkStatus' => '网络状态',
			'reader.networkStatusSubtitle' => 'Linux 下可能不准确',
			'reader.battery' => '电量',
			'reader.time' => '时间',
			'reader.verticalPositionTop' => '顶部',
			'reader.verticalPositionBottom' => '底部',
			'reader.horizontalPositionLeft' => '左侧',
			'reader.horizontalPositionCenter' => '居中',
			'reader.horizontalPositionRight' => '右侧',
			'reader.readingDirectionLtr' => '从左到右',
			'reader.readingDirectionRtl' => '从右到左',
			'reader.readingDirectionVertical' => '从上到下',
			'reader.webtoon' => '条漫',
			'reader.singlePageRow' => '单页式（横向翻页）',
			'reader.readingDirectionLeftOpen' => '左开模式 · 下一页在左',
			'reader.readingDirectionRightOpen' => '右开模式 · 下一页在右',
			'reader.readingDirectionToggle' => '阅读方向',
			'reader.readingDirectionToggleLeftOpen' => '当前左开（下一页在左）· 点按切换为右开',
			'reader.readingDirectionToggleRightOpen' => '当前右开（下一页在右）· 点按切换为左开',
			'reader.readingDirectionToggleDisabled' => '条漫模式没有左右翻页方向',
			'reader.readingDirectionToggleSetting' => '顶栏显示阅读方向切换',
			'reader.swipePreview' => '翻页预览',
			'reader.swipePreviewSubtitle' => '翻页时两侧直接显示画面，不再先用大字页码占位（每页多解一张视口宽度的位图）',
			'reader.doublePage' => '双页阅读',
			'reader.doublePageSubtitle' => '在当前阅读模式中启用双页并排',
			'reader.doublePageSeamless' => '双页无缝',
			'reader.doublePageSeamlessSubtitle' => '左右各占一半宽度，按图片比例独立显示并消除中间留白',
			'reader.doublePageLeadingBlank' => '首页留白',
			'reader.doublePageLeadingBlankSubtitle' => '在每章最前插入一页空白，使配对整体错一位',
			'reader.splitLandscapePages' => '横长页左右分割',
			'reader.splitLandscapePagesSubtitle' => '自动将跨页横长图切分为左右两半阅读',
			'reader.landscapeSplitDirection' => '分割阅读顺序',
			'reader.splitDirectionAuto' => '跟随阅读方向',
			'reader.splitDirectionLtr' => '左起（左→右）',
			'reader.splitDirectionRtl' => '右起（右→左）',
			'reader.hoverReveal' => '悬停唤出',
			'reader.hoverRevealEnabled' => '边缘悬停唤出控制栏',
			'reader.hoverRevealEnabledSubtitle' => '鼠标移至屏幕顶部或底部边缘时自动浮现对应工具栏（参考 NeoView）',
			'reader.thumbnailStrip' => '底部缩略图条',
			'reader.thumbnailStripSubtitle' => '在控制栏展开每页缩略图，与进度条并成同一块面板；换书、换章、重启后保持',
			'reader.transparentTopBar' => '透明顶栏',
			'reader.transparentTopBarSubtitle' => '顶栏不再用玻璃材质，改为一层半透明蒙层，画面从底下透出来（参考 JHenTai）',
			'reader.transparentTopBarOpacity' => '顶栏蒙层不透明度',
			'reader.thumbnailStripExpand' => '展开缩略图',
			'reader.thumbnailStripCollapse' => '收起缩略图',
			'reader.thumbnailStripOriginalAspectRatio' => '缩略图按原图比例显示',
			'reader.thumbnailStripOriginalAspectRatioSubtitle' => '关闭时统一竖屏显示，开启后按每张图片的比例完整显示',
			'reader.thumbnailStripCurrent' => '当前',
			'reader.thumbnailStripJumpToPage' => ({required Object page}) => '跳转到第 ${page} 页',
			'reader.hoverRevealTop' => '顶部边缘唤出顶栏',
			'reader.hoverRevealBottom' => '底部边缘唤出底栏',
			'reader.hoverTriggerAreaTop' => '顶部唤出感应区高度',
			'reader.hoverTriggerAreaBottom' => '底部唤出感应区高度',
			'reader.hoverHideDelay' => '离开后自动收回延时',
			'reader.hoverShowVisualIndicator' => '显示边缘感应提示线',
			'reader.hoverShowVisualIndicatorSubtitle' => '在触发区显示微弱的指示线，便于直观感知范围',
			'reader.hoverAreaPreview' => '唤出感应区示意（NeoView 风格）',
			'reader.hoverAreaTopHint' => '顶部感应区：{height}px',
			'reader.hoverAreaBottomHint' => '底部感应区：{height}px',
			'reader.pinTopBar' => '钉住顶栏（不再自动收起）',
			'reader.unpinTopBar' => '取消钉住顶栏',
			'reader.pinBottomBar' => '钉住底栏（不再自动收起）',
			'reader.unpinBottomBar' => '取消钉住底栏',
			'reader.landscapeReader' => '横屏阅读',
			'reader.landscapeReaderSubtitle' => '阅读时切换为横屏，离开后恢复原来的方向',
			'reader.themeMode' => '系统模式',
			'reader.autoRead' => '自动阅读',
			'reader.autoReadSubtitle' => '开启后自动滚动',
			'reader.autoReadHidePauseButton' => '隐藏暂停按钮',
			'reader.autoReadHidePauseButtonSubtitle' => '自动阅读继续运行，但不显示阅读页上的暂停/播放按钮',
			'reader.autoReadSmooth' => '平滑滚动',
			'reader.autoReadSmoothSubtitle' => '条漫模式下连续匀速滚动，关闭则按间隔分段跳转',
			'reader.webtoonScrollDistance' => '条漫滚动距离',
			'reader.webtoonScrollInterval' => '条漫滚动间隔',
			'reader.singlePageScrollInterval' => '单页式滚动间隔',
			'reader.preload' => '预加载',
			'reader.preloadImageCount' => '预加载图片数量',
			'reader.preloadImageCountSubtitle' => '提前下载当前阅读位置之后的图片',
			'reader.preloadChapterCount' => '预加载章节数量',
			'reader.preloadChapterCountSubtitle' => '提前加载后续章节信息',
			'reader.background' => '阅读背景',
			'reader.auto' => '自动',
			'reader.black' => '黑色',
			'reader.white' => '白色',
			'reader.grey' => '灰色',
			'reader.adaptive' => '自适应取色',
			'reader.adaptiveEdge' => '边缘渐变',
			'reader.ambientDim' => '背景压暗',
			'reader.ambientDimSubtitle' => '把取自画面的颜色压暗后再铺成背景，越大越不刺眼；仅在本地漫画生效',
			'reader.readingExperience' => '阅读体验',
			'reader.keyboardPageTurnSpeed' => '连续翻页速度',
			'reader.keyboardPageTurnSpeedSubtitle' => '横向阅读时，按下立即翻一页，持续按住翻页键后按此速度连续翻页。动画自动适配速度，松手后只完成当前页；双页模式每次翻一个画面。',
			'reader.pagesPerSecond' => '页/秒',
			'reader.keyboardPageTurnAdvanced' => '长按翻页高级选项',
			'reader.keyboardPageTurnHoldDelay' => '长按启动延迟',
			'reader.keyboardPageTurnHoldDelaySubtitle' => '按住多久后开始连续翻页。仅影响启动等待，持续翻页速度由上面的页/秒决定。',
			'reader.disableAnimation' => '关闭翻页动画',
			'reader.disableAnimationSubtitle' => '关闭整页翻页动画，小幅滚动动画不受影响',
			'reader.readFilter' => '阅读滤镜（仅深色模式）',
			'reader.readFilterSubtitle' => '仅在阅读界面生效，可降低夜间阅读亮度',
			'reader.filterIntensity' => '滤镜强度',
			'reader.einkOptimization' => '墨水屏优化（仅横向）',
			'reader.einkOptimizationSubtitle' => '翻页后先白屏再显示图片',
			'reader.einkDelay' => '白屏时长',
			'reader.sidePadding' => '两侧留白',
			'reader.sidePaddingSubtitle' => '自定义左右留白比例',
			'reader.sidePaddingPercent' => '每侧留白比例',
			'reader.batterySubtitle' => '默认关闭，可按需开启',
			'reader.timeSubtitle' => '显示当前时间',
			'reader.infoBarPosition' => '信息条位置',
			'reader.showInStatusBar' => '显示在状态栏',
			'reader.showInStatusBarSubtitle' => '开启后，顶部信息条会进入系统状态栏区域',
			'reader.edgePadding' => '边缘间距',
			'reader.infoBarStyle' => '信息条样式',
			'reader.backgroundOpacity' => '背景透明度',
			'reader.fontSize' => '字体大小',
			'reader.allHiddenNotice' => '当前已全部关闭，阅读页中的信息条会完全隐藏。',
			'reader.edgePaddingDisabled' => '横向在中间时，边缘间距不会生效。',
			'reader.bottomProgressBar' => '底部进度条',
			'reader.bottomProgressBarSubtitle' => '在画面底边画一条常驻细条表示翻页进度。它不随上下栏收起，与左下角信息条各开各的、互不影响',
			'reader.bottomProgressBarGlow' => '进度条荧光',
			'reader.bottomProgressBarGlowSubtitle' => '给已经走过的这一段加一圈光晕',
			'reader.settings' => '阅读设置',
			'reader.previousChapter' => '上一章',
			'reader.nextChapter' => '下一章',
			'reader.backToHome' => '返回首页',
			'reader.jumpToChapterTitle' => '跳转',
			'reader.jumpToChapterMessage' => ({required Object chapter}) => '是否要跳转到${chapter}？',
			'reader.selectChapter' => '选择章节',
			'reader.enterFullscreen' => '全屏（f11）',
			'reader.exitFullscreen' => '退出全屏',
			'reader.chapterTransition' => '章节过渡中',
			'reader.transitionSwipeToLoad' => '继续翻页加载',
			'reader.transitionLoaded' => '加载完成',
			'reader.transitionLoadFailedRetry' => '加载失败，点击重试',
			'reader.pullDownToPrevChapter' => '继续下拉到上一章',
			'reader.releaseToJumpPrevChapter' => '松手跳转到上一章',
			'reader.releaseToLoadPrevChapter' => '松手加载到上一章',
			'reader.pullUpToNextChapter' => '继续上拉到下一章',
			'reader.releaseToJumpNextChapter' => '松手跳转到下一章',
			'reader.releaseToLoadNextChapter' => '松手加载到下一章',
			'reader.chapterNotDownloaded' => '章节未下载',
			'reader.loadFailedWithResult' => ({required Object result}) => '${result}\n加载失败',
			'reader.chapterOrder' => ({required Object order}) => '章节 ${order}',
			'reader.doubleTapAction' => '双击操作',
			'reader.doubleTapZoom' => '双击缩放',
			'reader.doubleTapZoomSubtitle' => '双击图片可在缩放和还原之间切换',
			'reader.doubleTapOpenMenu' => '双击打开操作栏',
			'reader.doubleTapOpenMenuSubtitle' => '双击页面打开操作栏（与双击缩放互斥）',
			'reader.centerTapBar' => '点击唤出上下栏',
			'reader.centerTapToggleBars' => '点击中间唤出/收起上下栏',
			'reader.centerTapToggleBarsSubtitle' => '关闭后单击阅读区不再显隐上下栏（条漫模式下「点哪儿都算中间」也一并关闭），改用桌面端边缘悬停或双击打开操作栏唤出',
			'reader.volumeKeyPageTurn' => '音量键翻页',
			'reader.enableVolumeKeyPageTurn' => '启用音量键翻页',
			'reader.volumeKeyPageTurnSubtitle' => '开启后可用音量键上下翻页/滑动',
			'reader.screenHeightPercent' => '% 屏高',
			'reader.milliseconds' => 'ms',
			'reader.percent' => '%',
			'reader.pixels' => 'px',
			'reader.gesture' => '手势与悬停',
			'reader.infoBar' => '信息条',
			'reader.tabRead' => '阅读',
			'reader.tabGesture' => '手势',
			'reader.tabScreen' => '界面',
			'reader.tabPicture' => '画面',
			'reader.tabTranslate' => '翻译',
			'reader.chromeSection' => '上下栏与边距',
			'reader.tuningSection' => '画面处理',
			'reader.autoTrimMargins' => '自动裁边',
			'reader.autoTrimMarginsSubtitle' => '检测每页内容区并放大显示，不修改原图',
			'reader.pauseAutoRead' => '暂停自动阅读',
			'reader.resumeAutoRead' => '继续自动阅读',
			'reader.imageLoadFailedRetry' => ({required Object error}) => '${error}\n加载失败，点击重试',
			'reader.imageSavedTo' => ({required Object path}) => '图片已保存至: ${path}',
			'reader.imageSavedToAlbum' => '图片已保存到相册！',
			'reader.imageSaveFailed' => '图片保存失败！',
			'reader.saveImagePermissionDenied' => '保存失败: 请在系统设置中授予相册访问权限',
			'reader.imageSaveFailedWithError' => ({required Object error}) => '保存失败: ${error}',
			'reader.radialMenuHint' => '松手执行 · 中心或 Esc 取消',
			'reader.radialMenuHintMove' => '移动以选择',
			'reader.radialMenuHintRelease' => '松手执行',
			'reader.radialMenuHintSwitch' => '松手切换轮盘',
			'reader.singlePageLtr' => '从左到右',
			'reader.singlePageRtl' => '从右到左',
			'plugin.getInfoJsonBadFormat' => 'getInfoJson 格式错误',
			'plugin.getInfoBadFormat' => 'getInfo 返回格式错误',
			'plugin.badResponseFormat' => '插件返回格式错误',
			'plugin.advancedCapabilityLoading' => '高级能力加载中...',
			'plugin.store' => '插件商店',
			'plugin.searchHint' => '搜索插件名称或作者...',
			'plugin.localInstall' => '本地安装',
			'plugin.networkInstall' => '网络安装',
			'plugin.cloudComponents' => '云端组件',
			'plugin.restrictedSourceBlocked' => '该来源当前不可用，请先在 设置 → 内容与网络 中开启「完整来源列表」',
			'plugin.restrictedSourcesHidden' => ({required Object count}) => '已隐藏 ${count} 个来源',
			'plugin.loginSuccess' => '请在网页中完成登录，宿主会自动同步 Cookie',
			'plugin.chromiumFallbackUnsupported' => '当前平台不支持外部 Chromium 自动登录回退',
			'plugin.switchingToExternalBrowser' => '内置 WebView 登录受限，正在切换外部浏览器...',
			'plugin.chromiumNotFound' => '未检测到 Chromium 浏览器，请先安装 Chrome',
			'plugin.browserSwitched' => ({required Object browser}) => '已切换到 ${browser}，登录完成后会自动同步 Cookie',
			'plugin.invalidLink' => ({required Object url}) => '无效链接: ${url}',
			'plugin.cannotOpenLink' => ({required Object url}) => '无法打开链接: ${url}',
			'plugin.readLocalPluginFailed' => ({required Object error}) => '读取本地插件失败: ${error}',
			'plugin.unsupportedLocalFileType' => ({required Object fileName}) => '不支持的本地文件类型，仅支持 .js / .cjs / .br 文件：${fileName}',
			'plugin.addFromNetwork' => '从网络添加插件',
			'plugin.urlCannotBeEmpty' => 'URL 不能为空',
			'plugin.startInstall' => '开始安装',
			'plugin.pluginSettingsTitle' => ({required Object name}) => '${name} 设置',
			'plugin.debugConfigUpdated' => '插件调试配置已更新',
			'plugin.deletePlugin' => '删除插件',
			'plugin.confirmDeletePlugin' => '确认删除该插件？此操作将删除插件及其相关数据。',
			'plugin.deleteFailed' => ({required Object error}) => '删除失败: ${error}',
			'plugin.pluginDeleted' => '插件已删除',
			'plugin.executeFailed' => ({required Object error}) => '执行失败: ${error}',
			'plugin.deletePluginSubtitle' => '彻底删除插件，并删除相关数据',
			'plugin.debugMode' => '调试模式',
			'plugin.debugAddress' => '调试地址',
			'plugin.accountLogin' => '账号登录',
			'plugin.accountLoginSubtitle' => '前往登录',
			'plugin.pluginDetail' => '插件详情',
			'plugin.pluginDetailSubtitle' => '查看插件介绍与主页',
			'plugin.pluginSettings' => '插件设置',
			'plugin.noUserInfo' => '暂无用户信息',
			'plugin.operations' => '操作',
			'plugin.management' => '插件管理',
			'plugin.installed' => '已安装',
			'plugin.notInstalled' => '未安装',
			'plugin.update' => '更新',
			'plugin.install' => '安装',
			'plugin.uninstall' => '卸载',
			'plugin.author' => '作者',
			'plugin.version' => '版本',
			'plugin.description' => '描述',
			'plugin.repo' => '仓库',
			'plugin.homepage' => '主页',
			'plugin.githubRepo' => 'GitHub 仓库',
			'plugin.download' => '下载',
			'plugin.downloadUpdate' => '下载更新',
			'plugin.noCloudPlugins' => '暂无云端组件',
			'plugin.noMatchingPlugins' => '没有匹配的插件',
			'plugin.networkInstallHint' => '请输入插件脚本 URL',
			'plugin.cloudPluginsLoadFailed' => ({required Object error}) => '云端组件列表加载失败: ${error}',
			'plugin.installingFromCloud' => ({required Object name}) => '正在下载并安装 ${name}...',
			'plugin.installingFromLocal' => '正在安装本地插件...',
			'plugin.installingFromNetwork' => '正在下载网络插件...',
			'plugin.cloudDownloadFailed' => ({required Object error}) => '云端下载失败: ${error}',
			'plugin.networkDownloadFailed' => ({required Object error}) => '网络下载插件失败: ${error}',
			'plugin.remoteAssetNotFound' => '远程插件文件不存在（404），可能已被删除或版本已更新，请稍后重试或检查更新地址',
			'plugin.githubRateLimited' => 'GitHub 访问受限（疑似 IP 被限流），请稍后重试或切换网络；若插件确实不存在也会显示 404',
			'plugin.remoteReturnedWebPage' => '远端返回了网页而非插件文件，通常是远程文件不存在或链接已失效，请检查插件仓库的更新地址',
			'plugin.remoteEmptyResponse' => '远端返回内容为空，请稍后重试或检查更新地址',
			'plugin.remoteAccessDenied' => ({required Object status}) => '远端拒绝访问（HTTP ${status}），请检查网络或稍后重试',
			'plugin.remoteServerError' => ({required Object status}) => '远端服务器异常（HTTP ${status}），请稍后重试',
			'plugin.remoteHttpError' => ({required Object status}) => '远端请求失败（HTTP ${status}），请稍后重试',
			'plugin.downloadedScriptInvalid' => '下载到的文件不是有效的插件脚本（疑似网页或错误页），请检查远程文件是否存在后再试',
			'plugin.downloadedScriptCorrupted' => '下载到的插件文件已损坏或解压失败，请稍后重试',
			'plugin.networkUnstableRetry' => '网络不稳定，下载失败，请检查网络后重试',
			'plugin.cloudVersion' => ({required Object version}) => '云端 ${version}',
			'plugin.localVersion' => ({required Object version}) => '本地 ${version}',
			'plugin.loginTitle' => ({required Object name}) => '${name} 登录',
			'plugin.cookieSynced' => '登录 Cookie 已同步',
			'plugin.executeSuccess' => '执行成功',
			'plugin.userInfoTitle' => '用户信息',
			'plugin.userInfoLoadFailed' => '用户信息加载失败',
			'plugin.unnamedAction' => '未命名操作',
			'plugin.pluginSettingsLoading' => '插件设置加载中...',
			'plugin.pluginSettingsLoadFailed' => '插件设置加载失败',
			'plugin.actionNotExecutable' => '动作不可执行: 缺少 fnPath',
			'plugin.saved' => '已保存',
			'plugin.close' => '关闭',
			'plugin.sync' => '同步',
			'plugin.syncSubtitle' => '通过 npm / updateUrl 检查并更新插件',
			'plugin.syncing' => '正在同步插件...',
			'plugin.syncSuccess' => '同步成功',
			'plugin.syncFailed' => ({required Object error}) => '同步失败: ${error}',
			'plugin.updateSubtitle' => '通过网络 URL 或本地文件手动重装当前插件',
			'plugin.updateFromNetwork' => '从网络安装',
			'plugin.updateFromLocal' => '从本地安装',
			'plugin.updateChooseSource' => '选择安装方式',
			'plugin.updating' => '正在更新插件...',
			'plugin.updateSuccess' => '更新成功',
			'plugin.updateFailed' => ({required Object error}) => '更新失败: ${error}',
			'plugin.uuidMismatch' => '插件 id 不一致，无法安装',
			'plugin.currentVersion' => ({required Object version}) => '当前版本 ${version}',
			'plugin.alreadyLatest' => '已是最新版本',
			'gestureLock.gestureTitle' => '手势解锁',
			'gestureLock.gestureHint' => '请绘制手势密码',
			'gestureLock.pinTitle' => '输入 PIN',
			'gestureLock.pinHint' => '请输入重置 PIN',
			'gestureLock.atLeast4Points' => '至少连接 4 个点',
			'gestureLock.confirmGesture' => '请再次绘制以确认',
			'gestureLock.gestureNotMatch' => '两次绘制不一致',
			'gestureLock.setSuccess' => '设置成功',
			'gestureLock.forgotPassword' => '忘记密码',
			'gestureLock.incorrectPassword' => '手势密码不正确，请重试',
			'gestureLock.resetPin' => '重置 PIN',
			'gestureLock.pin' => 'PIN',
			'gestureLock.pinDescription' => 'PIN 可用于重置手势密码，遗忘手势密码与 PIN 后将无法进入软件，请妥善保管 Pin',
			'gestureLock.pinMinLength' => 'PIN 需至少 4 位数字',
			'gestureLock.pinNotMatch' => '两次输入的 PIN 不一致',
			'gestureLock.pinIncorrect' => 'PIN 不正确，请重试',
			'gestureLock.appLocked' => '应用已锁定',
			'gestureLock.verifyToUnlock' => '请先完成手势验证',
			'gestureLock.resetGesturePassword' => '重置手势密码',
			'gestureLock.resetPinHint' => '请输入设置时保存的重置 PIN',
			'gestureLock.passwordCleared' => '密码已清空，请重新设置',
			'gestureLock.setupHintFirst' => '请连接至少 4 个点',
			'gestureLock.setupHintConfirm' => '请再次绘制相同手势',
			'gestureLock.setupErrorMinPoints' => '至少连接 4 个点',
			'gestureLock.setupErrorMismatch' => '两次手势不一致，请重新设置',
			'gestureLock.pinHintMinDigits' => '至少 4 位数字',
			'appBootstrap.initializing' => '初始化中....',
			'appBootstrap.verifyGesture' => '请验证手势密码',
			'appBootstrap.pinVerifyFailed' => 'PIN 验证未通过',
			'appBootstrap.unlockCancelled' => '已取消解锁',
			'appBootstrap.enteringApp' => '验证成功，正在进入应用',
			'comments.retry' => '重试',
			'comments.noComments' => '暂无评论',
			'comments.loadMore' => '加载更多',
			'comments.collapseReplies' => '收起回复',
			'comments.replyCount' => ({required Object count}) => '${count} 条回复',
			'comments.noReplies' => '暂无子评论',
			'comments.loadMoreReplies' => '加载更多回复',
			'comments.postComment' => '发表评论',
			'comments.postCommentHint' => '输入评论内容',
			'comments.postReply' => '回复评论',
			'comments.postReplyHint' => '输入回复内容',
			'comments.cancel' => '取消',
			'comments.confirm' => '确认',
			'comments.postSuccess' => '发布成功',
			'comments.postFailed' => ({required Object error}) => '发布失败: ${error}',
			'comments.anonymous' => '匿名用户',
			'cache.title' => '缓存设置',
			'cache.currentCache' => '当前缓存',
			'cache.clearCache' => '清理缓存',
			'cache.clearCacheConfirm' => '确定要清理所有缓存文件吗？此操作不可撤销。',
			'cache.cleared' => '缓存已清理',
			'cache.clearFailed' => '清理失败',
			'cache.cacheSize' => '缓存大小',
			'cache.recalculate' => '重新计算',
			'cache.manualClear' => '手动清理缓存',
			'cache.manualClearSubtitle' => '立即删除所有缓存文件',
			'cache.clear' => '清理',
			'cache.cacheLimit' => '缓存限制',
			'cache.sizeLimit' => '缓存上限',
			'cache.sizeLimitSubtitle' => '达到上限后将自动清理旧缓存',
			'cache.autoClean' => '自动清理缓存',
			'cache.autoCleanSubtitle' => '关闭后将不再自动清理任何缓存',
			'cache.calculating' => '计算中...',
			'cache.calculateFailed' => '计算失败',
			'dataBackup.title' => '本地导入/导出',
			'dataBackup.exportSection' => '导出',
			'dataBackup.importSection' => '导入',
			'dataBackup.includeDownloads' => '包含下载的漫画',
			'dataBackup.includeDownloadsSubtitle' => '导出时一并打包已下载的漫画文件',
			'dataBackup.exportData' => '导出数据',
			'dataBackup.exportDataSubtitle' => '将设置与数据打包为 zip',
			'dataBackup.importData' => '导入数据',
			'dataBackup.importDataSubtitle' => '从 zip 文件恢复数据',
			'dataBackup.selectExportDirFailed' => '选择导出目录失败',
			'dataBackup.exporting' => '正在导出，请耐心等待…',
			'dataBackup.exportSuccess' => '导出成功',
			'dataBackup.savedTo' => ({required Object path}) => '已保存到：${path}',
			'dataBackup.exportShareHint' => '请在弹出的分享面板中选择「存储到文件」以保存备份。',
			'dataBackup.exportFailed' => '导出失败',
			'dataBackup.processingBackup' => '正在处理备份文件…',
			'dataBackup.selectBackupFailed' => '选择备份文件失败',
			'dataBackup.readingBackup' => '正在读取备份信息…',
			'dataBackup.readBackupFailed' => '读取备份失败',
			'dataBackup.importing' => '正在导入，请稍后…',
			'dataBackup.importFailed' => '导入失败',
			'dataBackup.importTitle' => '导入数据',
			'dataBackup.importConfirm' => '导入将覆盖备份中的设置与应用数据；本机路径、代理、应用锁及同步配置会保留。是否继续？',
			'dataBackup.includesDownloadsWarning' => '该备份包含下载的漫画文件，导入时会先删除本机现有的下载文件。',
			'dataBackup.versionMismatch' => '版本不一致，数据导入可能会出问题，是否继续？',
			'dataBackup.exportedVersion' => ({required Object version}) => '导出数据版本：${version}',
			'dataBackup.currentVersion' => ({required Object version}) => '当前应用版本：${version}',
			'dataBackup.kContinue' => '继续',
			'dataBackup.importSuccess' => '导入成功',
			'dataBackup.restartPrompt' => '数据导入成功，请重启应用以生效。',
			'webdavSync.title' => '云同步配置',
			'webdavSync.serviceTitle' => ({required Object service}) => '${service} 同步配置',
			'webdavSync.noneTip' => '请先在设置里选择同步服务，再回到这里填写配置。',
			'webdavSync.deleteConfig' => '删除配置',
			'webdavSync.testAndSave' => '测试连接并保存',
			'webdavSync.faq' => '常见问题',
			'webdavSync.webdavHost' => 'WebDAV 地址',
			'webdavSync.username' => '账号',
			'webdavSync.password' => '密码',
			'webdavSync.s3Endpoint' => '服务地址(Endpoint)',
			'webdavSync.s3EndpointHint' => '如: s3.amazonaws.com',
			'webdavSync.s3AccessKey' => 'Access Key',
			'webdavSync.s3SecretKey' => 'Secret Key',
			'webdavSync.s3Bucket' => '存储桶(Bucket)的名字',
			'webdavSync.s3Region' => '区域(Region)（可选）',
			'webdavSync.s3Port' => '端口（可选）',
			'webdavSync.useSsl' => '使用 HTTPS/SSL',
			'webdavSync.pathStyle' => '路径风格 (Path-Style)',
			'webdavSync.pathStyleSubtitle' => '自建 MinIO 通常需要开启此选项',
			'webdavSync.connectingWebdav' => '正在连接 WebDAV 服务器...',
			'webdavSync.webdavConnected' => 'WebDAV连接成功，已保存设置。',
			'webdavSync.webdavConnectFailed' => ({required Object error}) => '连接失败，请检查网络连接或WebDAV地址是否正确。\n${error}',
			'webdavSync.invalidPort' => '端口格式不正确，请输入 0-65535 的数字。',
			'webdavSync.connectingS3' => '正在连接 S3 服务...',
			'webdavSync.s3Connected' => 'S3 连接成功，已保存设置。',
			'webdavSync.s3ConnectFailed' => ({required Object error}) => '连接失败，请检查 S3 配置是否正确。\n${error}',
			'webdavSync.close' => '关闭',
			'webdavSync.success' => '成功',
			'webdavSync.error' => '错误',
			'webdavSync.faqMarkdown' => '### 可以同步哪些内容？\n- 目前同步哔咔历史记录、禁漫收藏和禁漫历史。\n\n### WebDAV 如何配置？\n- 填写 WebDAV 地址、账号、密码，点击测试连接并保存即可。\n\n### S3 如何配置？\n- Endpoint 示例：`s3.amazonaws.com`、`s3.filebase.com`、`play.min.io`。\n- 如果是自建 MinIO，可填写自定义端口，必要时关闭 SSL。\n\n### 自动同步间隔是多久？\n- 每 5 分钟自动同步一次。\n\n### 如何手动触发一次同步？\n- 在同步配置页测试连接并保存后会触发一次同步。\n- 或在设置里切换一次自动同步开关。',
			'ocr.title' => '漫画翻译（成品页）',
			'ocr.endpointSection' => '翻译端点',
			'ocr.baseUrl' => '接口地址',
			'ocr.baseUrlHint' => 'https://api.deepseek.com/v1 或 http://127.0.0.1:11434/v1',
			'ocr.baseUrlNone' => '未配置',
			'ocr.model' => '模型名',
			_ => null,
		} ?? switch (path) {
			'ocr.modelHint' => '例如 deepseek-chat、qwen2.5:14b',
			'ocr.apiKey' => 'API Key',
			'ocr.apiKeySubtitle' => '只存本机设置，不进导出文件；本机 Ollama 可留空',
			'ocr.targetLanguage' => '目标语言',
			'ocr.glossary' => '术语表',
			'ocr.glossarySubtitle' => '每行一条「原文=译文」；改动会让已生成的成品页重译',
			'ocr.glossaryHint' => 'トカゲ=石龙子',
			'ocr.saved' => '已保存',
			'ocr.notConfigured' => '还缺接口地址或模型名',
			'ocr.epSection' => '推理后端',
			'ocr.ep' => '推理后端',
			'ocr.epSubtitle' => '实测这两个模型在 CoreML 上更慢，默认走 CPU',
			'ocr.epPlan' => ({required Object detect, required Object recognize, required Object inpaint}) => '本机各段：检测 ${detect} · 识别 ${recognize} · 擦字 ${inpaint}',
			'ocr.epPlanUnsupported' => ({required Object ep}) => '本平台构建里没有 ${ep} —— 选了会在开始分析时报错，不会静默退回 CPU',
			'ocr.displaySection' => '成品页显示',
			'ocr.displayChoice' => '显示方式',
			'ocr.displayChoiceSubtitle' => '换档只影响之后按「译」的页；已经生成的那一页要重按一次，才会按新档重做（一页十几秒）。',
			'ocr.displayBaked' => '烘焙成图（会压掉这一页的超分）',
			'ocr.displayOverlay' => '叠层显示（中文盖在擦字底图上）',
			'ocr.displayOverlayHint' => '叠层只把中文盖在底图上，不改底图像素；但这一页要用擦干净的字底当底图，所以它会替自己占一次增强图轨 —— 这一页的超分为它让路。「每个气泡采到自己的平色就不必擦」那条捷径今天没走过：8 页真页 121 框可填 0 框（数字见 ADR-0018 §4）。',
			'ocr.modelSection' => '模型权重',
			'ocr.weightsReady' => ({required Object count}) => '权重已就绪（${count} 个文件）',
			'ocr.weightsMissing' => ({required Object missing}) => '缺少：${missing}',
			'ocr.download' => '下载权重',
			'ocr.downloading' => '下载中',
			'ocr.downloadDone' => '权重下载完成',
			'ocr.downloadFailed' => '权重下载失败',
			'ocr.cacheSection' => '成品页缓存',
			'ocr.cacheCount' => ({required Object count}) => '已生成 ${count} 张成品页',
			'ocr.cacheEmpty' => '还没有生成过成品页',
			'ocr.clearCache' => '清空成品页缓存',
			'ocr.clearCacheSubtitle' => '换模型或换字体后用；不会动原图',
			'ocr.cacheCleared' => '已清空成品页缓存',
			'ocr.logSection' => '诊断',
			'ocr.viewLog' => '翻译日志',
			'ocr.logHint' => '每一页的六道关各记一行：端点、推理（含各段实际生效 EP）、翻译请求、回填排版、落盘、注入核对。',
			'ocr.logDialogTitle' => '漫画翻译日志',
			'ocr.logEmpty' => '尚无翻译日志。在阅读器里按「译」，或去「设置 → 调试 → OCR 成品页冒烟」跑一遍，这里就会有记录。',
			'ocr.copyLog' => '复制日志',
			'ocr.logCopied' => '翻译日志已复制',
			'ocr.openLogLocation' => '打开日志位置',
			'ocr.readerHint' => '在阅读器工具条上按「译」，只切换当前这一页',
			'ocr.chipOff' => '译',
			'ocr.chipOn' => '译文页',
			'ocr.chipOnOverlay' => '译文页 · 叠层',
			'ocr.building' => '生成中',
			'ocr.failedShort' => '译文失败',
			'ocr.busyToast' => '这一页正在生成译文，稍等',
			'ocr.needWeights' => '权重还没下全，去设置里下载',
			'ocr.engine' => '译文引擎',
			'ocr.engineSubtitle' => '选「API 端点」按 token 计费/要网络；选「Apple 系统翻译」走端侧，免费离线',
			'ocr.autoTranslatePage' => '翻到新的一页自动译',
			'ocr.autoTranslatePageSubtitle' => '一张成品页要十几秒，开着等于往后每页都得等。关掉只管之后的页，已经生成的译文页留着。',
			'ocr.engineAppleInstalled' => '语言包已装，直接生效（整页 15 块实测约 300 ms）',
			'ocr.engineAppleMissing' => '还没装 ja → 目标语言 的翻译语言包。系统里没有 app 能替你下载的 API —— 请到「系统设置 › 通用 › 语言与地区」里装好再回来',
			'ocr.engineAppleUnsupportedPair' => '系统不认识这个语言对，换目标语言或改用端点',
			'ocr.engineAppleUnavailable' => '这台机器上没有系统翻译这条路（仅 macOS 15+ / iOS 18+）',
			'ocr.glossaryIgnoredOnApple' => '系统翻译没有术语表接口：这一档下术语表不生效，专名会按通用译法翻',
			'ocr.engineHunyuanHint' => '这一档要本机先起服务，例如：llama-server -m Hy-MT2-1.8B-Q4_K_M.gguf --device MTL0 -ngl 99 --port 8080\n端点填 http://127.0.0.1:8080/v1，模型名与 --model 一致。术语表会走它原生的 Terminology 模式生效。\n实测 1.8B 就够（约 158 ms/条、一页约 2.4 s）：术语表把 ヤモリ/危機契約 这类错逐条修对了，7B 并不更好且大 4 倍。macOS 上 --device 必须写 MTL0 —— 不写会静默走 CPU，实测慢 4.8 倍。',
			'realSr.openedUpscaleCache' => ({required Object dir}) => '尚无超分产物，已打开超分缓存目录：${dir}',
			'realSr.openedRecentLocation' => ({required Object output}) => '已打开最近产物的所在位置：${output}',
			'realSr.openFolderFailed' => ({required Object error}) => '打开文件夹失败：${error}',
			'realSr.openFolderUnsupported' => ({required Object dir}) => '当前平台无法打开文件夹：${dir}',
			'realSr.coremlModelPhoto' => 'Real-ESRGAN x4plus · 照片/CG',
			'realSr.mimageInferenceFailed' => ({required Object error}) => 'mImage ONNX 推理失败：${error}',
			'realSr.modelUnavailableHint' => ({required Object engine}) => '模型不可用：${engine}，请先在超分设置中下载模型。',
			'realSr.archiveMissingOnnx' => ({required Object file}) => '压缩包缺少 mImage ONNX 模型 ${file}',
			'realSr.archiveContentMismatch' => ({required Object missing}) => '压缩包内容不符合当前引擎要求: ${missing}',
			'realSr.modelFileNameMismatch' => ({required Object expected, required Object actual}) => '文件名与当前模型不匹配: 期望 ${expected}, 实际 ${actual}',
			'realSr.missingOnnxDownload' => ({required Object file}) => '缺少 mImage ONNX 模型 ${file}，请在设置中下载',
			'realSr.importJsonInvalid' => ({required Object error}) => 'JSON 格式无效: ${error}',
			'realSr.copyLog' => '复制日志',
			'realSr.blockInfoDetail' => ({required Object contentSize, required Object blockSize, required Object shrink}) => '分块：内容块 ${contentSize}×${contentSize}，模型输入 ${blockSize}×${blockSize}（含 ${shrink} px 反射边距），由模型固定',
			'realSr.deleteModelConfirmNamed' => ({required Object name}) => '删除 ${name}？需要时可以重新下载。',
			'realSr.actionFailedDetail' => ({required Object error}) => '操作失败：${error}',
			'realSr.importConditionSuccess' => ({required Object count}) => '成功导入 ${count} 条条件',
			'realSr.logEmptyText' => '尚无超分日志。启用超分后，推理和替换过程会记录在这里。',
			'realSr.upscaleLogCopied' => '超分日志已复制',
			'realSr.expandEditor' => '展开编辑器',
			'realSr.collapseEditor' => '收起编辑器',
			'realSr.conditionListSummary' => ({required Object total, required Object enabled}) => '条件列表（共 ${total} 条，启用 ${enabled} 条）',
			'realSr.conditionNeedsAutoUpscale' => '需先在上方启用【自动超分】，条件超分才能在阅读与预加载时生效。',
			'realSr.conditionUpscaleSubtitle' => '按图片尺寸、路径正则及元数据规则分派超分动作与跳过判定',
			'realSr.conditionUpscaleTitle' => '条件超分 (neo)',
			'realSr.advancedOptionsTitle' => '高级超分选项 (预超分 / 日志)',
			'realSr.ncnnCliDesc' => '调用 waifu2x / Real-CUGAN 的 ncnn-vulkan 可执行文件；模式、倍率、并发与分块在「图片超分」设置页下方调整。',
			'realSr.coremlDesc' => 'Swift 直接调用 Apple CoreML，复用已加载模型。',
			'realSr.nativeScaleLabel' => ({required Object x}) => '原生 ${x}×',
			'realSr.modeCuganQuality' => 'Real-CUGAN · 质量优先',
			'realSr.modeWaifuFast' => 'waifu2x · 速度优先',
			'realSr.nativeModel' => 'Rossi 原生模型',
			'realSr.engineSwitchHint' => '切换后当前页自动重新处理，两套模型选择分别保留。',
			'realSr.hardwareAcceleration' => '硬件加速',
			'realSr.upscaleEngine' => '超分引擎',
			'realSr.preUpscaleHint' => '一次处理一页，避免争抢内存；都设为 0 可关闭预超分。',
			'realSr.pageCount' => ({required Object n}) => '${n} 页',
			'realSr.preUpscaleCurrentFirst' => '预超分（当前页优先）',
			'realSr.enableTta' => '启用 TTA 增强',
			'realSr.writeResultCache' => '写入结果缓存',
			'realSr.enableTile' => '启用分块 Tile',
			'realSr.actionUpscaleHit' => '命中此条件时：执行超分',
			'realSr.actionSkipHit' => '命中此条件时：跳过超分（不处理）',
			'realSr.actionSectionTitle' => '触发动作 (Action)',
			'realSr.excludePreUpscale' => '排除预超分队列',
			'realSr.matchArchivePath' => '匹配归档内部路径',
			'realSr.regexExampleOr' => '或',
			'realSr.regexExamplePrefix' => '例: ',
			'realSr.matchSectionTitle' => '尺寸与规则匹配 (Match)',
			'realSr.enableThisCondition' => '启用此条件',
			'realSr.conditionEnabledBadge' => '已启用',
			'realSr.importSuccessSkipped' => ({required Object imported, required Object skipped}) => '导入成功（${imported} 条），跳过 ${skipped} 条不兼容项',
			'realSr.importContentEmpty' => '导入内容不能为空',
			'realSr.importJsonSample' => '[\n  {\n    "name": "示例条件",\n    ...\n  }\n]',
			'realSr.pasteExportedJson' => '请粘贴导出的 JSON 数组或备份对象文本：',
			'realSr.conditionJsonCopied' => '已复制条件 JSON 到剪贴板',
			'realSr.conditionsRestored' => '已恢复默认条件',
			'realSr.keepAtLeastOneCondition' => '至少保留一条超分条件',
			'realSr.conditionCopy' => ({required Object name}) => '${name} 副本',
			'realSr.importLocalHint' => '本地导入请选择上方文件名对应的 mImage ONNX 模型。切换后当前页会重新生成超分图。',
			'realSr.modelNotInstalled' => '当前模型未安装，下载或导入后才能使用',
			'realSr.modelInstalled' => '当前模型已安装',
			'realSr.modelRuntime' => ({required Object runtime}) => '运行时：${runtime}',
			'realSr.modelDenoiseFixed' => '降噪：由模型固定，不支持单独调节强度',
			'realSr.modelDenoiseCugan' => '降噪：Real-CUGAN 保守修复，强度由模型固定',
			'realSr.modelScaleNote' => ({required Object scale}) => '倍率：原生 ${scale}×（由模型决定）',
			'realSr.exampleBuiltinHint' => '没有正在阅读的页面，以下为内置示例；打开漫画后再展开可看到当前页的实际效果。',
			'realSr.exampleSemantics' => ({required Object title, required Object before, required Object after, required Object description}) => '${title}示例。${before}与${after}对比。点击查看大图。${description}',
			'realSr.exampleTitleSuffix' => ({required Object title}) => '${title}（示例）',
			'realSr.exampleLiveSource' => '来自当前正在阅读的页面，关闭预览后立即释放。',
			'realSr.beforeUnchanged' => ({required Object before}) => '${before}（保持原样）',
			'realSr.beforeTrimmedShadow' => ({required Object before}) => '${before}（阴影为裁剪部分）',
			'realSr.loadingTrimResult' => '正在读取当前页的裁边结果…',
			'realSr.loadingDenoiseResult' => '正在读取当前页的降噪结果…',
			'realSr.exampleImageNotReadyRetry' => '当前页的图片还没有准备好，翻页或稍后再试',
			'realSr.previewFailed' => ({required Object error}) => '预览失败：${error}',
			'realSr.afterDenoise' => '降噪后',
			'realSr.afterTrim' => '裁剪后',
			'realSr.exampleDenoiseDesc' => '同一 JPEG 局部经 RealPLKSR 1× 实际处理，分辨率保持不变。效果随原图而变化。',
			'realSr.exampleTrimDesc' => '去掉四周余白，让漫画内容更大。示意图不随参数变化。',
			'realSr.exampleDenoiseTitle' => '降噪预览',
			'realSr.exampleTrimTitle' => '裁边预览',
			'realSr.denoiseAttribution' => '来自 mImageViewer · CC BY 4.0\n首次使用需下载；大小与 SHA-256 校验通过后安装。',
			'realSr.retryDownload' => '重试下载',
			'realSr.denoiseProgressTooltip' => '模型下载进度',
			'realSr.denoiseVerifyTooltip' => '校验模型完整性',
			'realSr.denoiseSubtitle' => 'RealPLKSR · JPEG 降噪 · 1×',
			'realSr.denoiseUpdateFailed' => '更新失败 · 已安装的模型仍可使用',
			'realSr.denoiseInstalled' => ({required Object size}) => '模型已安装 · ${size}',
			'realSr.denoiseVerifying' => '正在校验模型',
			'realSr.denoiseMissing' => '模型未安装',
			'realSr.denoiseChecking' => '正在检查模型',
			'realSr.modelIncomplete' => '模型不完整',
			'realSr.modelDownloadDone' => '模型下载完成',
			'realSr.manualImportUnsupported' => '当前平台不支持手动导入超分模型',
			'realSr.missingModelDirs' => '缺少模型目录（models-pro / models-se 等）',
			'realSr.missingExecutable' => '缺少 waifu2x / Real-CUGAN 可执行文件',
			'realSr.missingModelFile' => ({required Object file}) => '缺少模型文件 ${file}',
			'realSr.missingModelDir' => ({required Object dir}) => '缺少模型目录 ${dir}',
			'realSr.missingOnnxModel' => ({required Object file}) => '缺少 mImage ONNX 模型 ${file}',
			'realSr.previewEnhancedUnreadable' => '当前增强结果暂时无法读取，无法显示对比',
			'realSr.previewDenoiseOriginal' => '当前图片未应用降噪 · 当前画面仍为原图',
			'realSr.previewDenoiseCompare' => '当前图片已应用降噪处理 · 对比阅读器正在显示的增强结果',
			'realSr.previewDenoisePending' => ({required Object phase}) => '当前图片尚未应用降噪 · ${phase}',
			'realSr.previewDenoiseApplied' => '当前图片已应用 JPEG 降噪 · RealPLKSR 1×',
			'realSr.previewBothApplied' => '当前图片已应用降噪及超分 · 对比已上屏的增强结果',
			'realSr.previewDenoiseOff' => '当前图片未被降噪 · 此漫画的降噪开关未开启',
			'realSr.previewDenoiseJpegOnly' => '当前图片未被降噪 · 仅处理 JPEG 页面，此页保持原样',
			'realSr.trimInsets' => ({required Object left, required Object top, required Object right, required Object bottom}) => '左 ${left} · 上 ${top} · 右 ${right} · 下 ${bottom}',
			'realSr.previewTrimApplied' => ({required Object summary}) => '当前图片已应用显示裁边 · ${summary}',
			'realSr.previewTrimNotNeeded' => '当前图片未被裁剪 · 无需裁边，保持原样',
			'realSr.previewTrimPending' => '当前图片尚未完成裁边检测 · 等待读取结果',
			'realSr.previewTrimSplitPage' => '当前图片未被裁剪 · 分割半页保持原样',
			'realSr.previewTrimOff' => '当前图片未被裁剪 · 此漫画的裁边开关未开启',
			'realSr.tileSizeHint' => '遇到崩溃可设置较小值；「自动」按模型推荐分块，模型声明固定输入尺寸时以模型为准',
			'realSr.conditionN' => ({required Object index}) => '条件 ${index}',
			'realSr.importItemFailed' => ({required Object index, required Object error}) => '第 ${index} 项解析失败: ${error}',
			'realSr.importSkipNotObject' => ({required Object index}) => '跳过第 ${index} 项：数据不是对象',
			'realSr.defaultCondition' => '默认条件',
			'realSr.engineDesktopNcnn' => '桌面 NCNN（waifu2x / Real-CUGAN）',
			'realSr.engineNativeCoreML' => 'Rossi 原生 CoreML',
			'realSr.modelFast' => '高速通用（Real-ESR General 4x）',
			'realSr.modelPhoto' => '照片/CG（Real-ESRGAN 4x）',
			'realSr.modelAnime' => '插画/动画（Real-ESRGAN Anime 6B 4x）',
			'realSr.modelComic' => '漫画（Real-CUGAN 4x）',
			'realSr.modeDenoiseThenUpscale' => '先降噪再超分',
			'realSr.modeUpscaleOnly' => '仅超分',
			'realSr.modeDenoiseOnly' => '仅 JPEG 降噪',
			'realSr.modeOriginal' => '原图',
			'realSr.deleteCondition' => '删除条件',
			'realSr.lowerPriority' => '下移优先级',
			'realSr.raisePriority' => '上移优先级',
			'realSr.addCondition' => '添加条件',
			'realSr.openImageFolderHint' => '定位最近生成的超分图；尚未生成时打开超分缓存目录。',
			'realSr.openImageFolder' => '打开图片文件夹',
			'realSr.viewUpscaleLog' => '查看超分日志',
			'realSr.upscaleLog' => '超分日志',
			'realSr.downloadNativeModel' => '下载 Rossi 原生模型',
			'realSr.pagesBefore' => '之前页：',
			'realSr.pagesAfter' => '后续页：',
			'realSr.blockSizeLabel' => '分块大小：',
			'realSr.outputScaleLabel' => '输出倍率：',
			'realSr.imagePathRegex' => '图片路径正则 (imagePathRegex)',
			'realSr.bookPathRegex' => '书籍路径正则 (bookPathRegex)',
			'realSr.matchAnyOr' => '任一满足 (OR)',
			'realSr.matchAllAnd' => '全部满足 (AND)',
			'realSr.sizeMatchLogic' => '尺寸匹配逻辑：',
			'realSr.maxPixelsMpx' => '最大像素 (MPx)',
			'realSr.minPixelsMpx' => '最小像素 (MPx)',
			'realSr.maxHeightPx' => '最大高度 (px)',
			'realSr.minHeightPx' => '最小高度 (px)',
			'realSr.maxWidthPx' => '最大宽度 (px)',
			'realSr.minWidthPx' => '最小宽度 (px)',
			'realSr.conditionName' => '条件名称',
			'realSr.applyImport' => '应用导入',
			'realSr.importConditions' => '导入条件超分配置',
			'realSr.copyToClipboard' => '复制到剪贴板',
			'realSr.exportConditions' => '导出条件超分配置 (JSON)',
			'realSr.resetConditionsContent' => '确定将所有条件恢复为出厂默认设置吗？现有规则将被清除。',
			'realSr.resetConditions' => '重置条件超分',
			'realSr.downloadInBrowser' => '浏览器下载',
			'realSr.importLocalOnnx' => '导入本地 ONNX',
			'realSr.deleteCurrentModel' => '删除当前模型',
			'realSr.redownloadCurrentModel' => '重新下载当前模型',
			'realSr.downloadCurrentModel' => '下载当前模型',
			'realSr.customModel' => '自定义超分模型',
			'realSr.onnxModel' => 'ONNX 模型',
			'realSr.exampleCollapsedHint' => '默认收起，展开后才会加载图片',
			'realSr.exampleImageNotReady' => '当前页的图片还没有准备好',
			'realSr.closeExample' => '关闭示例',
			'realSr.removeModel' => '移除模型',
			'realSr.noOutputYet' => '尚未生成',
			'realSr.logWindowTitle' => 'Rossi 超分日志（本次运行）',
			'realSr.logCategory' => '超分',
			'realSr.outputScaleSubtitle' => '桌面 NCNN 模型的实际倍率设置',
			'realSr.outputScale' => '输出倍率',
			'realSr.unnamedCondition' => '未命名条件',
			'realSr.title' => '图片超分（实验性）',
			'realSr.unlimited' => '不限制',
			'realSr.modelDownloadFailed' => '模型下载失败',
			'realSr.generalSection' => '通用',
			'realSr.autoUpscaleSection' => '自动超分',
			'realSr.autoUpscale' => '自动超分',
			'realSr.autoUpscaleSubtitleUnavailable' => '模型未下载，开启后无法自动超分',
			'realSr.autoUpscaleSubtitleAvailable' => '下载或加载图片时自动调用超分',
			'realSr.conditionSection' => '超分条件',
			'realSr.resolutionThreshold' => '分辨率阈值',
			'realSr.resolutionThresholdSubtitle' => '仅当图片宽度小于该值时才自动超分',
			'realSr.performanceSection' => '性能',
			'realSr.concurrency' => '并发数量',
			'realSr.concurrencySubtitle' => '高端显卡可适当提高，移动设备或性能较低时不建议设置高于1的并发量',
			'realSr.tileSize' => '分块大小',
			'realSr.tileSizeSubtitle' => '遇到崩溃可设置较小值，0为不分块，桌面端可尝试设置为0',
			'realSr.modelSection' => '模型',
			'realSr.model' => '模型',
			'realSr.modelSubtitle' => '切换模型族会重置对应的变体选项',
			'realSr.noiseLevel' => '降噪级别',
			'realSr.noiseLevelSubtitle' => '该选项随所选模型变化',
			'realSr.blockInfo' => '分块信息',
			'realSr.blockInfoTooltip' => 'blockSize 是模型输入尺寸，包含反射边距；\n内容块 = blockSize - 2×shrinkSize，才是真正拼接输出的区域。',
			'realSr.blockInfoFormat' => ({required Object contentSize, required Object blockSize, required Object shrinkSize}) => '内容块 ${contentSize}×${contentSize}，模型输入 ${blockSize}×${blockSize}（含 ${shrinkSize}px 反射边距）',
			'realSr.androidSuperResolution' => 'Android 超分',
			'realSr.androidSuperResolutionSubtitle' => '当前使用 waifu2x upconv 动漫模型，2 倍放大',
			'realSr.androidEngine' => '超分引擎',
			'realSr.androidEngineSubtitle' => 'Android 上选择超分推理后端',
			'realSr.androidEngineVulkan' => 'Vulkan（waifu2x CLI）',
			'realSr.androidEngineVulkanSubtitle' => 'ncnn + Vulkan GPU，兼容所有 Android 设备',
			'realSr.androidEngineQnnNpu' => 'NPU（Qualcomm QNN）',
			'realSr.androidEngineQnnNpuSubtitle' => 'Hexagon HTP NPU 推理，骁龙 8 系专属（实验阶段）',
			'realSr.androidEngineQnnExperimental' => 'NPU 后端处于实验阶段：失败时保留原图并显示原因，不会静默退回 Vulkan',
			'realSr.qnnModel' => 'NPU 模型',
			'realSr.qnnModelSubtitle' => 'Real-CUGAN FP16 模型，2 倍放大',
			'realSr.qnnModelSeX2NoDenoise' => 'Real-CUGAN SE 2×（无降噪）',
			'realSr.qnnModelProX2Denoise3x' => 'Real-CUGAN Pro 2×（降噪 3 档）',
			'realSr.qnnProbing' => '正在检测 NPU…',
			'realSr.qnnSupported' => ({required Object arch}) => '检测到 Qualcomm HTP ${arch}，NPU 可用',
			'realSr.qnnSupportedSubtitle' => '首次使用会在设备上编译模型上下文（约 1-2 秒）并缓存',
			'realSr.qnnUnsupported' => '此设备的 NPU 不可用',
			'realSr.qnnUnsupportedSubtitle' => '未检测到受支持的 Qualcomm HTP 运行时（或本包为不含 NPU 支持的构建）',
			'realSr.qnnUnsupportedArchSubtitle' => ({required Object arch}) => '检测到 HTP ${arch}，但本包未收录该架构的运行库',
			'realSr.qnnIdle' => '上下文未准备',
			'realSr.qnnIdleSubtitle' => '下载模型后点「准备」编译 NPU 上下文；阅读时也会自动准备',
			'realSr.qnnPreparing' => '正在编译 NPU 上下文…',
			'realSr.qnnReady' => 'NPU 上下文已就绪',
			'realSr.qnnFailed' => 'NPU 上下文准备失败',
			'realSr.qnnPrepare' => '准备',
			'realSr.qnnRetry' => '重试',
			'realSr.missingQnnModel' => ({required Object file}) => '缺少 NPU 模型文件 ${file}',
			'realSr.missingQnnManifest' => '缺少 NPU 模型清单 manifest.json',
			'realSr.desktopStrategy' => '超分策略',
			'realSr.desktopStrategySubtitle' => '效率优先使用 waifu2x，质量优先使用 Real-CUGAN',
			'realSr.desktopNoiseLevel' => '降噪级别',
			'realSr.desktopNoiseLevelSubtitle' => '保守适合普通漫画，降噪级别越高涂抹感越强',
			'realSr.modelManagementSection' => '模型管理',
			'realSr.downloadingModel' => '正在下载模型',
			'realSr.modelReady' => '模型已就绪',
			'realSr.redownload' => '重新下载',
			'realSr.deleteModel' => '删除模型',
			'realSr.deleteModelConfirm' => '确定要删除已下载的超分模型吗？删除后需要重新下载才能使用。',
			'realSr.modelDeleted' => '模型已删除',
			'realSr.modelDeleteFailed' => '模型删除失败',
			'realSr.modelNotDownloaded' => '模型未下载',
			'realSr.modelNotDownloadedSubtitle' => '使用超分前需要先下载模型',
			'realSr.downloadModel' => '下载模型',
			'realSr.manualDownload' => '手动下载模型',
			'realSr.manualDownloadUnsupported' => '当前平台不支持手动下载超分模型',
			'realSr.openDownloadUrl' => '打开链接',
			'realSr.openDownloadUrlFailed' => '打开链接失败',
			'realSr.importModel' => '导入模型压缩包',
			'realSr.importModelSubtitle' => '选择手动下载的 7z 压缩包，导入时会校验格式与模型内容',
			'realSr.importModelAction' => '选择文件',
			'realSr.modelImportSuccess' => '模型导入成功',
			'realSr.modelImportFailed' => '模型导入失败',
			'realSr.modeEfficiency' => '效率优先',
			'realSr.modeQuality' => '质量优先',
			'realSr.noiseConservative' => '保守',
			'realSr.noise0' => '无降噪',
			'realSr.noise1' => '降噪 1',
			'realSr.noise2' => '降噪 2',
			'realSr.noise3' => '降噪 3',
			'realSr.variantWaifu2xAnime' => 'waifu2x upconv 动漫',
			'realSr.variantRealCuganDenoise' => ({required Object noise}) => 'Real-CUGAN 降噪 ${noise}',
			'realSr.coremlSpeed' => '速度优先 (waifu2x)',
			'realSr.coremlQuality' => '质量优先 (Real-CUGAN)',
			'realSr.coremlNoise0' => '降噪 0',
			'realSr.coremlNoDenoise' => '无降噪',
			'realSr.coremlInputHint' => '输入图片绝对路径或 asset 路径',
			'realSr.coremlStartUpscale' => '开始超分',
			'realSr.coremlStatusFillInput' => '请填写输入图片路径',
			'realSr.coremlStatusNoModelFile' => '当前模型族没有可用的模型文件',
			'realSr.coremlStatusPreparing' => '正在准备资源...',
			'realSr.coremlStatusUpscaling' => '正在超分...',
			'realSr.coremlStatusDone' => ({required Object outputPath, required Object size}) => '完成\n${outputPath}\nsize: ${size} bytes',
			'realSr.coremlStatusFailed' => ({required Object error}) => '失败: ${error}',
			'realSr.coremlModelOption' => '模型选项（降噪级别）',
			'realSr.coremlGeneralOption' => '通用选项（放大倍率）',
			'realSr.coremlTileInfo' => '分块信息',
			'about.title' => '关于应用',
			'about.version' => ({required Object version}) => '版本号: ${version}',
			'about.loading' => '加载中...',
			'about.fetchFailed' => '获取失败',
			'about.networkError' => '网络错误',
			'about.tagline' => '跨平台漫画阅读器',
			'about.projectAddress' => '项目地址',
			'about.projectAddressDesc' => '喜欢这个项目吗？点个star支持一下吧！',
			'about.projectLink' => '前往 GitHub 仓库 (HibernalGlow/rossi) ⭐',
			'about.feedback' => '反馈与建议',
			'about.feedbackDesc' => '发现BUG或者有新的点子？',
			'about.feedbackLink' => '在 GitHub Issues 中提出',
			'about.upstream' => '上游致谢',
			'about.upstreamDesc' => 'Rossi 在 Breeze 的基础上继续开发，感谢上游作者与社区。',
			'about.upstreamLink' => '前往上游仓库 (deretame/Breeze)',
			'about.licenseDesc' => '本项目以 Mozilla Public License 2.0 授权发布。',
			'about.licenseLink' => '查看完整许可文本',
			'about.contributors' => '贡献者',
			'about.contributorsCount' => ({required Object count}) => '${count}人',
			'about.contributionsTooltip' => ({required Object login, required Object count}) => '${login} (${count} 次提交)',
			'about.disclaimer' => '免责声明',
			'about.disclaimerTitle' => '开源项目免责声明',
			'about.disclaimerItem1Title' => '1. 项目性质与声明',
			'about.disclaimerItem1Content' => '本项目为开源软件，由社区贡献者共同开发与维护。项目以"原样"形式提供，开发者不对项目的功能完整性、稳定性、安全性或适用性作出任何明示或暗示的担保。',
			'about.disclaimerItem2Title' => '2. 责任限制',
			'about.disclaimerItem2Content' => '开发者对因使用、修改或分发本项目（包括但不限于直接使用、二次开发或集成至其他项目）而导致的任何直接、间接、特殊、附带或后果性损害不承担任何责任。这些损害可能包括但不限于数据丢失、设备损坏、业务中断、利润损失或其他经济损失。',
			'about.disclaimerItem3Title' => '3. 用户责任',
			'about.disclaimerItem3Content' => '用户在使用本项目时，应自行评估其适用性并承担所有风险。用户须确保其使用行为符合所在国家或地区的法律法规及道德规范。开发者不对用户因违反法律法规或不当使用本项目而导致的任何后果负责。',
			'about.disclaimerItem4Title' => '4. 第三方依赖与资源',
			'about.disclaimerItem4Content' => '本项目可能依赖或引用第三方库、工具、服务或其他资源。开发者不对这些第三方资源的内容、功能、安全性或合法性负责。用户应自行评估并承担使用第三方资源的风险。',
			'about.disclaimerItem5Title' => '5. 无担保声明',
			'about.disclaimerItem5Content' => '开发者明确声明不对本项目提供任何形式的担保，包括但不限于：适销性担保；特定用途适用性担保；不侵犯第三方权利担保；无错误或无中断运行担保。',
			'about.disclaimerItem6Title' => '6. 项目修改与终止',
			'about.disclaimerItem6Content' => '开发者保留随时修改、暂停或终止本项目的权利，且无需提前通知用户。开发者不对因项目修改、暂停或终止而导致的任何后果负责。',
			'about.disclaimerItem7Title' => '7. 贡献者责任',
			'about.disclaimerItem7Content' => '外部贡献者的行为仅代表其个人立场，不代表项目维护者的观点或立场。项目维护者对贡献者的行为及其贡献内容不承担责任。',
			'about.disclaimerItem8Title' => '8. 法律合规性',
			'about.disclaimerItem8Content' => '用户在使用本项目时，应确保其行为符合所在国家或地区的法律法规。开发者不对用户因违反法律法规而导致的任何后果负责。',
			'about.disclaimerImportant' => '重要提示',
			'about.disclaimerImportantContent' => '在使用本项目之前，请仔细阅读并理解本免责声明。如果您不同意本声明的任何条款，请立即停止使用本项目。继续使用本项目即表示您已阅读、理解并同意本免责声明的全部内容。',
			'about.checkUpdate' => '检查更新',
			'about.alreadyLatest' => '已是最新版本',
			'about.updateAvailable' => '发现新版本',
			'about.license' => '开源许可',
			'about.privacy' => '隐私政策',
			'oldHome.title' => '首页',
			'oldHome.search' => '搜索',
			'oldHome.hotSearch' => '热搜',
			'oldHome.navigation' => '导航',
			'oldHome.recommend' => '推荐',
			'oldHome.latest' => '最新',
			'oldHome.cloudFavorite' => '云收藏',
			'oldHome.list' => '列表',
			'oldHome.function' => '功能',
			'oldHome.close' => '关闭',
			'oldHome.loadFailedRetry' => '加载失败，请重试。',
			'oldHome.loadSectionFailed' => ({required Object title, required Object error}) => '加载 ${title} 失败\n${error}',
			'oldHome.empty' => '暂无内容',
			'oldHome.loadMoreFailed' => '加载更多失败，点击重试',
			'oldHome.loadMore' => '点击加载更多',
			'oldHome.noMore' => '没有更多了',
			'more.common' => '常用',
			'more.others' => '其他',
			'more.downloadTasks' => '下载任务',
			'more.sync' => '同步',
			'more.comicFollow' => '追更',
			'more.changelog' => '更新日志',
			'search.title' => '搜索',
			'search.searchHint' => '搜索...',
			'search.selectSource' => '选择漫画源',
			'search.advancedSearchNotSupported' => '当前插件不支持高级搜索',
			'search.advancedSearchOptions' => '高级搜索选项',
			'search.notSelected' => '未选择',
			'search.selectedCount' => ({required Object count}) => '已选择 ${count} 项',
			'search.history' => '搜索历史',
			'search.clearHistory' => '清空历史',
			'search.newestFirst' => '当前：最近搜索在前',
			'search.oldestFirst' => '当前：最早搜索在前',
			'search.descending' => '时间倒序',
			'search.ascending' => '时间正序',
			'search.noHistory' => '暂无搜索记录',
			'search.groupByPluginTooltipOn' => '已按插件分时间线，点击合并成一条',
			'search.groupByPluginTooltipOff' => '全部堆在一条时间线上，点击按插件分组',
			'search.historyGroupAggregate' => '聚合搜索',
			'search.historyGroupUncategorized' => '未分类',
			'search.tipsTitle' => '🔍 搜索技巧',
			'search.exactSearchTitle' => '精准搜索（同时满足）',
			'search.exactSearchExample' => '全彩(空格)+人妻',
			'search.exactSearchDesc' => '显示同时包含这两个标签的结果',
			'search.excludeSearchTitle' => '排除搜索（不要某类）',
			'search.excludeSearchExample' => '全彩(空格)-人妻',
			'search.excludeSearchDesc' => '显示"全彩"但排除含"人妻"的结果',
			'search.fuzzySearchTitle' => '模糊搜索（包含任一）',
			'search.fuzzySearchExample' => '全彩(空格)人妻',
			'search.fuzzySearchDesc' => '显示包含任意一个关键词的结果',
			'search.selectCategory' => '选择分类',
			'search.dataSource' => '数据来源',
			'search.sortBy' => '排序方式',
			'search.newestToOldest' => '从新到旧',
			'search.oldestToNewest' => '从旧到新',
			'search.mostLikes' => '最多点赞',
			'search.mostViews' => '最多观看',
			'search.selectSourceTooltip' => '选择漫画源',
			'search.hasResults' => '有结果',
			'search.showErrors' => '显示错误',
			'search.resultCount' => ({required Object count}) => '${count} 条',
			'search.noResults' => '无结果',
			'search.loadFailedForSource' => ({required Object source}) => '${source} 加载失败',
			'discover.title' => '发现',
			'discover.search' => '搜索',
			'discover.settings' => '设置',
			'discover.pluginManagement' => '插件管理',
			'discover.customOrder' => '自定义插件顺序',
			'discover.resetOrder' => '恢复默认顺序',
			'discover.noPlugins' => '暂无可用插件，去插件商店安装一个吧~',
			'discover.pluginStore' => '插件商店',
			'discover.browseInstall' => '浏览安装',
			'discover.noPluginForSearch' => '暂无可用插件，无法搜索',
			'discover.pluginInfoLoadFailed' => ({required Object error}) => '插件信息加载失败: ${error}',
			'discover.pluginCapability' => '插件能力',
			'discover.disabled' => '已关闭',
			'discover.unnamed' => '未命名',
			'discover.pluginEnableFailed' => ({required Object error}) => '插件启用失败: ${error}',
			'discover.pluginCloseFailed' => ({required Object error}) => '插件关闭失败: ${error}',
			'discover.pluginDebugLoadFailed' => ({required Object error}) => '插件调试加载失败，已回退数据库: ${error}',
			'discover.closeTab' => '关闭标签',
			'discover.tabDisplay' => '标签显示',
			'discover.tabShowIcon' => '显示插件图标',
			'discover.tabShowPluginShort' => '显示插件名缩写',
			'discover.tabDoubleClickClose' => '双击关闭标签',
			'discover.tabCoverMode' => '封面页签',
			'discover.tabCoverModeDesc' => '把页签显示成书封，并在封面上叠加信息',
			'discover.webPage' => '网页',
			'discover.comicDetail' => '详情',
			'searchResult.enterPageNumber' => '输入页数',
			'searchResult.pleaseEnterNumber' => '请输入数字',
			'searchResult.returnToTop' => '返回顶部',
			'searchResult.jumpToPage' => '跳转页面',
			'searchResult.jump' => '跳转',
			'searchResult.retry' => '点击重试',
			'comicList.browseMenu' => '浏览菜单',
			'comicList.currentPage' => ({required Object page}) => '第 ${page} 页',
			'comicList.pageOfTotal' => ({required Object page, required Object total}) => '第 ${page} / ${total} 页',
			'comicList.jumpToPage' => '快速跳页',
			'comicList.pageInput' => '目标页码',
			'comicList.invalidPage' => '请输入大于 0 的整数',
			'comicList.pageOutOfRange' => ({required Object total}) => '页码不能超过 ${total}',
			'comicList.restorePosition' => '恢复上次浏览位置',
			'comicList.restorePage' => ({required Object page}) => '上次看到第 ${page} 页',
			'comicList.noSavedPosition' => '还没有浏览记录',
			'comicList.positionSavedAutomatically' => '滚动后自动保存位置',
			'comicList.previousPage' => '上一页',
			'comicList.nextPage' => '下一页',
			'comicList.chineseLocalized' => '漢化',
			'comicList.downloadedAtLabel' => '下载时间',
			'comicList.likedArtists' => '喜欢的画师',
			'comicList.likedTags' => '喜欢的 tag',
			'comicList.defaultTitle' => '漫画列表',
			'comicList.missingSource' => '缺少插件来源，无法加载列表',
			'comicList.reload' => '重新加载',
			'comicList.loadFailedRetry' => '加载失败，请重试。',
			'comicList.nothingHere' => '啥都没有',
			'comicList.filter' => '筛选',
			'comicList.subCategory' => '子分类',
			'comicList.levelCategory' => ({required Object level}) => '第${level}级分类',
			'comicList.missingListConfig' => '缺少列表请求配置',
			'comicList.missingFnPath' => '列表请求缺少 fnPath',
			'comicEntry.seenAtPage' => ({required Object page}) => '看到第 ${page} 页',
			'comicEntry.updatedAt' => ({required Object time}) => '更新: ${time}',
			'comicEntry.finished' => '完结',
			'comicEntry.ongoing' => '连载中',
			'comicEntry.likes' => ({required Object count}) => '喜欢 ${count}',
			'comicEntry.views' => ({required Object count}) => '浏览 ${count}',
			'comicEntry.deleteFavorite' => '删除收藏',
			'comicEntry.deleteFavoriteConfirm' => ({required Object title}) => '确定要删除（${title}）的收藏记录吗？',
			'comicEntry.deleteHistory' => '删除历史记录',
			_ => null,
		} ?? switch (path) {
			'comicEntry.deleteHistoryConfirm' => ({required Object title}) => '确定要删除（${title}）的历史记录吗？',
			'comicEntry.deleteDownload' => '删除下载记录',
			'comicEntry.deleteDownloadConfirm' => ({required Object title}) => '确定要删除（${title}）的下载记录及文件吗？',
			'comicEntry.deleteFailed' => '删除失败',
			'comicEntry.translationBadgeTranslated' => '汉化',
			'comicEntry.translationBadgeChinese' => '中文',
			'comicEntry.translationBadgeRaw' => '生肉',
			'comicEntry.unread' => '未读',
			'comicEntry.translationTooltipTag' => ({required Object label, required Object keyword}) => '${label} · 标签命中「${keyword}」',
			'comicEntry.translationTooltipTitle' => ({required Object label, required Object keyword}) => '${label} · 标题命中「${keyword}」',
			'comicEntry.resumeRead' => '继续阅读',
			'comicEntry.readFailed' => '无法开始阅读，请稍后重试',
			'comicFollow.title' => '追更',
			'comicFollow.loadFailed' => ({required Object result}) => '加载失败：${result}',
			'comicFollow.empty' => '暂无追更漫画',
			'comicFollow.emptyHint' => '在漫画详情页点击追更按钮即可加入',
			'comicFollow.unfollow' => '取消追更',
			'comicFollow.unfollowConfirm' => ({required Object title}) => '确定不再追更《${title}》吗？',
			'comicFollow.unfollowed' => '已取消追更',
			'comicFollow.all' => '全部',
			'comicFollow.unread' => '已更新未看',
			'comicFollow.sort' => '排序',
			'comicFollow.lastRead' => '最后阅读',
			'comicFollow.lastUpdate' => '最近检测',
			'comicFollow.checkTime' => ({required Object time}) => '检测时间：${time}',
			'comicFollow.notRead' => '尚未阅读',
			'comicFollow.lastReadChapter' => ({required Object chapter}) => '看到：${chapter}',
			'comicFollow.latestChapter' => ({required Object count, required Object chapter}) => '最新：${count} 话 / ${chapter}',
			'comicFollow.noUnread' => '暂无已更新未看内容',
			'comicFollow.showAll' => '显示全部',
			'comicFollow.latestChapterFailed' => '最新章节获取失败',
			'comicFollow.newChapters' => ({required Object diff, required Object total}) => '新增 ${diff} 话，共 ${total} 话',
			'comicFollow.newUnreadChapters' => ({required Object diff, required Object total}) => '新增 ${diff} 话未阅读，共 ${total} 话',
			'comicFollow.latestCount' => ({required Object count}) => '最新 ${count} 话',
			'comicFollow.fetchFailed' => '获取失败',
			'comicFollow.newChaptersShort' => ({required Object diff}) => '新增 ${diff} 话',
			'comicFollow.newUnreadChaptersShort' => ({required Object diff}) => '新增 ${diff} 话未阅读',
			'comicFollow.update' => '更新',
			'comicFollow.retry' => '重试',
			'comicFollow.readProgress' => ({required Object read, required Object total}) => '已看 ${read} / 共 ${total} 话',
			'comicFollow.readProgressUnknown' => ({required Object total}) => '共 ${total} 话',
			'comicFollow.updatedJustNow' => '刚刚检测',
			'comicFollow.updatedMinutesAgo' => ({required Object minutes}) => '${minutes} 分钟前检测',
			'comicFollow.updatedHoursAgo' => ({required Object hours}) => '${hours} 小时前检测',
			'comicFollow.updatedDaysAgo' => ({required Object days}) => '${days} 天前检测',
			'comicFollow.lastReadMinutesAgo' => ({required Object minutes}) => '${minutes} 分钟前读过',
			'comicFollow.lastReadHoursAgo' => ({required Object hours}) => '${hours} 小时前读过',
			'comicFollow.lastReadDaysAgo' => ({required Object days}) => '${days} 天前读过',
			'comicFollow.checkFailedTapRetry' => '检测失败，点击重试',
			'comicFollow.unreadCountBadge' => ({required Object count}) => '${count} 话未读',
			'comicFollow.markAllReadHint' => '全部标为已读',
			'comicFollow.markAllReadDone' => '已全部标为已读',
			'comicFollow.updateChannelName' => '漫画更新提醒',
			'comicFollow.updateChannelDesc' => '追更漫画检测到新章节时推送',
			'comicFollow.updateTitle' => '追更更新',
			'comicFollow.updatedComicsSingle' => '有 1 部漫画更新',
			'comicFollow.updatedComicsMultiple' => ({required Object count}) => '有 ${count} 部漫画更新',
			'comicFollow.updateBodyMultiple' => ({required Object count}) => '有 ${count} 部追更漫画更新了',
			'comicFollow.updateBodySingle' => '有 1 部追更漫画更新了',
			'changelog.title' => '更新日志',
			'changelog.loadFailed' => '加载失败',
			'changelog.loadFailedWithError' => ({required Object error}) => '加载失败: ${error}',
			'changelog.cannotOpenLink' => ({required Object url}) => '无法打开链接: ${url}',
			'changelog.checkNetwork' => '加载失败，请检查网络',
			'changelog.retry' => '重试',
			'changelog.empty' => '暂无更新日志',
			'changelog.publishedAt' => ({required Object date}) => '发布于 ${date}',
			'changelog.viewInBrowser' => '在浏览器中查看',
			'changelog.attachments' => '附件下载',
			'webview.title' => '网页',
			'webview.cannotOpenLink' => ({required Object uri}) => '无法打开链接: ${uri}',
			'webview.invalidLink' => '链接无效，无法打开网页',
			'webview.emptyLink' => '(空链接)',
			'webview.loadFailed' => '网页加载失败',
			'webview.retry' => '重试',
			'webview.openInExternalBrowser' => '外部浏览器打开',
			'webview.windowClosed' => 'WebView 窗口已关闭',
			'webview.openedInExternalWindow' => '网页已在独立窗口中打开',
			'webview.back' => '返回',
			'webview.closeWindow' => '关闭 WebView 窗口',
			'webview.loadError' => ({required Object error}) => '加载失败（${error}）',
			'webview.httpErrorStatus' => ({required Object statusCode}) => '服务器返回异常状态码：${statusCode}',
			'oldRanking.bikaRanking' => '哔咔排行榜',
			'oldRanking.jmRanking' => '禁漫排行榜',
			'oldRanking.switchSource' => '切换',
			'login.title' => '登录',
			'login.missingPluginId' => '缺少插件标识，无法打开登录页',
			'login.loadConfigFailed' => ({required Object error}) => '登录配置加载失败: ${error}',
			'login.insufficientFields' => '插件返回的登录字段不足',
			'login.invalidCredentials' => '用户名或密码错误，请重新输入',
			'login.configNotReady' => '登录配置未就绪，请稍后重试',
			'login.loggingIn' => '正在登录，请耐心等待...',
			'login.loginSuccess' => '登录成功',
			'login.loginFailed' => '登录失败',
			'login.loginButton' => '登录',
			'login.retry' => '重试',
			'login.requiredFieldEmpty' => ({required Object label}) => '请填写 ${label}',
			'login.loginNotSupported' => '该插件暂未适配新版登录页，请前往插件设置中填写账号信息',
			'login.captchaTapToRefresh' => '看不清？点击刷新',
			'login.captchaLoading' => '验证码加载中...',
			'login.captchaLoadFailed' => '验证码加载失败，点击重试',
			'fontSetting.title' => '字体设置',
			'fontSetting.clear' => '清空',
			'fontSetting.hint' => '选一个默认字体即可应用到全局；需要微调个别字重时再单独覆盖。',
			'fontSetting.modeSystem' => '系统默认',
			'fontSetting.modeSystemHint' => '使用应用默认字体栈，无需任何操作。',
			'fontSetting.modeFamily' => '系统已装字体',
			'fontSetting.modeFamilyHint' => '输入系统里已安装字体的家族名（如 LXGW WenKai）直接引用，未命中时回退系统默认；桌面端最可靠。',
			'fontSetting.modeFile' => '字体文件',
			'fontSetting.modeFileHint' => '整个应用共用这一个文件，粗体等字重由系统模拟。',
			'fontSetting.familyPickPrompt' => '选择字体家族',
			'fontSetting.familyPickerTitle' => '选择系统字体',
			'fontSetting.familySearchHint' => '搜索字体家族…',
			'fontSetting.familyManualUse' => ({required Object name}) => '使用「${name}」',
			'fontSetting.familyEmpty' => '没有匹配的字体',
			'fontSetting.familyLoading' => '正在读取系统字体…',
			'fontSetting.defaultFont' => '默认字体',
			'fontSetting.defaultFontHint' => '整个应用共用这一个文件，粗体等字重由系统模拟。',
			'fontSetting.overrides' => '字重覆盖',
			'fontSetting.overridesHint' => '可选：为个别字重指定不同文件，未覆盖的字重使用最接近的已配置字体。',
			'fontSetting.loadFailed' => '字体加载失败',
			'fontSetting.cleared' => '已清除',
			'fontSetting.saved' => '已保存',
			'fontSetting.allCleared' => '已清空',
			'fontSetting.noFileSelected' => '未选择文件',
			'fontSetting.clearFile' => '清除',
			'fontSetting.selectFile' => '选择文件',
			'fontSetting.sampleText' => 'Innovation in China 中国智造，慧及全球 0123456789',
			'download.title' => '下载任务',
			'download.startDownload' => '开始下载',
			'download.selectChaptersPrompt' => '请选择要下载的章节',
			'download.selectedCount' => ({required Object selected, required Object total}) => '已选 ${selected} / 共 ${total} 章',
			'download.downloadedCount' => ({required Object count}) => '本地已有 ${count} 章',
			'download.skipDownloaded' => '跳过已下载',
			'download.skippedAlreadyDownloaded' => ({required Object count}) => '本地已有 ${count} 章，已跳过',
			'download.startedWithSkipped' => ({required Object started, required Object skipped}) => '开始下载 ${started} 章，跳过 ${skipped} 章（本地已有）',
			'download.optionsTitle' => '下载这本漫画',
			'download.optionWholeBook' => '下载整本',
			'download.optionWholeBookCounted' => ({required Object count}) => '全部 ${count} 章',
			'download.optionWholeBookPlain' => '全部章节',
			'download.optionLatest' => ({required Object count}) => '下载最近 ${count} 章',
			'download.optionLatestSubtitle' => '按章节序号取最新的几章',
			'download.optionPicker' => '手动选章节',
			'download.optionPickerPlain' => '逐章勾选，也可全选',
			'download.optionSkipHint' => '「整本」与「最近 N 章」会自动跳过本地已有的章节',
			'download.filterAll' => '全部',
			'download.filterNoMatches' => '当前筛选没有任务',
			'download.overviewRemaining' => ({required Object count}) => '还剩 ${count} 章',
			'download.overviewPages' => ({required Object done, required Object total}) => '已下 ${done}/${total} 页',
			'download.overviewFailed' => ({required Object count}) => '失败 ${count} 章',
			'download.comicScopeAll' => '全部漫画',
			'download.comicScopeCounted' => ({required Object name, required Object count}) => '${name}（${count} 章）',
			'download.taskStarted' => '下载任务已启动',
			'download.taskStartFailed' => ({required Object error}) => '下载任务启动失败，${error}',
			'download.noTasks' => '暂无下载任务',
			'download.downloading' => '正在下载',
			'download.pending' => ({required Object count}) => '等待中 (${count})',
			'download.failedTasks' => ({required Object count}) => '失败 (${count})',
			'download.pausedTasks' => ({required Object count}) => '已暂停 (${count})',
			'download.pinTask' => '优先下载',
			'download.unpinTask' => '取消优先',
			'download.taskPinned' => '已排到队首',
			'download.taskUnpinned' => '已取消优先',
			'download.taskDeleted' => '已删除任务',
			'download.deleteLastChapterContent' => '删除当前章节后，会删除下载记录，是否确认删除？',
			'download.cancelTask' => '取消任务',
			'download.cancelTaskConfirm' => ({required Object comicName}) => '确定要取消下载 ${comicName} 吗？',
			'download.paused' => '已暂停',
			'download.completed' => '已完成',
			'download.failed' => '失败',
			'download.startAll' => '全部开始',
			'download.pauseAll' => '全部暂停',
			'download.cancelAll' => '全部取消',
			'download.cancelAllConfirm' => ({required Object count}) => '确定要取消全部 ${count} 个下载任务吗？已下载的章节图片会一并删除。',
			'download.clearCompleted' => '清除已完成',
			'download.viewModeCompact' => '紧凑视图',
			'download.viewModeComfortable' => '完整视图',
			'download.statusFetchingComicInfo' => '获取漫画信息中...',
			'download.statusDownloadingCover' => '下载封面中...',
			'download.statusFetchingChapterInfo' => '获取章节信息中...',
			'download.statusFetchingChapterInfoProgress' => ({required Object completed, required Object total, required Object percent}) => '获取章节信息中... (${completed}/${total}, ${percent}%)',
			'download.statusDownloadProgress' => ({required Object percent}) => '当前章节下载进度: ${percent}%',
			'download.statusDownloadProgressComplete' => '当前章节下载进度: 100%',
			'download.progressPages' => ({required Object completed, required Object total}) => '已下载 ${completed}/${total} 页',
			'download.progressPagesWithSpeed' => ({required Object completed, required Object total, required Object speed}) => '已下载 ${completed}/${total} 页 · ${speed}',
			'download.parallelTaskProgress' => ({required Object count, required Object message}) => '同时下载 ${count} 个任务 · ${message}',
			'download.settingsTitle' => '下载设置',
			'download.settingsValueSummary' => ({required Object chapters, required Object images, required Object delayMs}) => '${chapters} 章 · 每章 ${images} 图 · 间隔 ${delayMs} ms',
			'download.settingsBudgetHint' => ({required Object count}) => '当前最多同时请求 ${count} 张图（同时下载章节数 × 单章节图片并发）',
			'download.offlineTitle' => '已离线漫画',
			'download.offlineEmpty' => '还没有已下载的漫画',
			'download.offlineMeasureSize' => '统计占用',
			'download.offlineMeasuring' => '统计中…',
			'download.offlineTotalSize' => ({required Object size}) => '共 ${size}',
			'download.offlineChapterCount' => ({required Object completed, required Object total}) => '已下 ${completed}/${total} 章',
			'download.offlineChapterCountOnly' => ({required Object count}) => '已下 ${count} 章',
			'download.statusComicProgress' => ({required Object completedChapters, required Object totalChapters, required Object currentChapterCompletedImages, required Object currentChapterTotalImages}) => '漫画进度: ${completedChapters}/${totalChapters} 章，当前章节: ${currentChapterCompletedImages}/${currentChapterTotalImages} 页',
			'download.statusComicProgressChaptersOnly' => ({required Object completedChapters, required Object totalChapters}) => '漫画进度: ${completedChapters}/${totalChapters} 章',
			'download.statusStartDownload' => '开始下载...',
			'download.statusWaiting' => '等待中',
			'download.statusCancelling' => '取消中...',
			'download.statusAutoRetrying' => ({required Object seconds, required Object attempt, required Object max}) => '网络异常，将在 ${seconds} 秒后自动重试 (${attempt}/${max})...',
			'download.statusThrottling' => '触发源站风控节流，正在冷却休眠中...',
			'download.retryFailedParts' => '重试失败项',
			'download.toastDownloadComplete' => ({required Object comicName}) => '${comicName} 下载完成',
			'download.toastDownloadFailed' => ({required Object comicName, required Object error}) => '${comicName} 下载失败 ${error}',
			'download.toastTaskAlreadyExists' => ({required Object comicName}) => '${comicName} 任务已存在',
			'download.notificationCompleteTitle' => '下载完成',
			'download.notificationFailedTitle' => '下载失败',
			'foregroundTask.channelName' => '前台任务',
			'foregroundTask.channelDescription' => '用于下载保活与后台保活，保持应用在后台继续运行',
			'foregroundTask.waitingForTask' => '等待下载任务中...',
			'foregroundTask.keepAliveRunning' => '正在保持后台运行',
			'foregroundTask.cancel' => '取消',
			'foregroundTask.notificationPermissionRequired' => '需要通知权限来启动前台任务，请在系统弹窗中允许通知权限',
			'foregroundTask.cannotStartWithoutPermission' => '无法启动前台任务：请先在系统设置中开启通知权限',
			'foregroundTask.startFailed' => ({required Object error}) => '前台服务启动失败: ${error}',
			'notification.permissionRequired' => '请开启通知权限',
			'notification.macPermissionRequired' => '请在系统设置中开启通知权限',
			'update.newVersion' => '发现新版本',
			'update.goToGitHub' => '前往GitHub',
			'update.downloadInstall' => '下载安装',
			'update.apkDownloadFailed' => '下载失败，请稍后再试！',
			'update.installPermissionRequired' => '请授予安装应用权限！',
			'update.unknownArch' => '未知',
			'dialog.hideOrClose' => '隐藏到托盘或关闭程序',
			'dialog.rememberChoice' => '记住我的选择',
			'shelfMenu.open' => '打开',
			'shelfMenu.resumeReading' => '继续阅读',
			'shelfMenu.openInFileManagerTab' => '在文件管理新页签打开',
			'shelfMenu.copyTitle' => '复制标题',
			'shelfMenu.copyLink' => '复制链接',
			'shelfMenu.addFavorite' => '收藏',
			'shelfMenu.alreadyFavorite' => '已在收藏中',
			'shelfMenu.removeFavorite' => '取消收藏',
			'shelfMenu.removeHistory' => '从历史记录移除',
			'shelfMenu.copiedTitle' => ({required Object title}) => '已复制标题「${title}」',
			'shelfMenu.copiedLink' => ({required Object link}) => '已复制链接「${link}」',
			'shelfMenu.fileManagerTabOpened' => '已在文件管理新页签打开',
			'shelfMenu.fileManagerTabUnavailable' => '文件管理面板还没准备好，稍后再试',
			'shelfMenu.fileManagerTabNoLocalPath' => '这条漫画没有本地目录，无法在文件管理里打开',
			'shelfMenu.favoriteAdded' => ({required Object title}) => '已收藏「${title}」',
			'shelfMenu.favoriteRemoved' => ({required Object title}) => '已取消收藏「${title}」',
			'shelfMenu.historyRemoved' => ({required Object title}) => '已从历史记录移除「${title}」',
			'shelfMenu.removeFavoriteConfirmTitle' => '取消收藏？',
			'shelfMenu.removeFavoriteConfirmBody' => ({required Object title}) => '「${title}」将从收藏库移除，源文件与阅读记录不受影响。',
			'shelfMenu.removeHistoryConfirmTitle' => '移除历史记录？',
			'shelfMenu.removeHistoryConfirmBody' => ({required Object title}) => '「${title}」将从阅读历史中移除，源文件不会被删除。',
			'video.play' => '播放',
			'video.pause' => '暂停',
			'video.backward' => '后退 10 秒',
			'video.forward' => '前进 10 秒',
			'video.loop' => '循环：接下一页',
			'video.loopSingle' => '循环：本页重复',
			'video.loopOff' => '循环：关闭',
			'video.speed' => '倍速',
			'video.volume' => '音量',
			'video.muted' => '已静音',
			'video.subtitles' => '字幕',
			'video.subtitleOff' => '关闭字幕',
			'video.audio' => '音轨',
			'video.audioOff' => '关闭音轨',
			'video.filters' => '滤镜',
			'video.resetFilters' => '重置滤镜',
			'video.brightness' => '亮度',
			'video.contrast' => '对比度',
			'video.saturation' => '饱和度',
			'video.abLoop' => 'A-B 循环',
			'video.abClear' => '清除 A-B',
			'video.screenshot' => '截图',
			'video.audioOnly' => '只听声音',
			'video.seekMode' => '快进档（翻页改成跳转）',
			'video.fullscreen' => '全屏',
			'video.pin' => '钉住控制条',
			'video.info' => '信息',
			'video.frameStepForward' => '下一帧',
			'video.frameStepBackward' => '上一帧',
			'video.pip' => '画中画',
			'video.settingsSection' => '视频播放',
			'video.autoPlay' => '自动播放',
			'video.autoPlayDesc' => '翻到视频页就开始播放',
			'video.hwDecode' => '硬件解码',
			'video.hwDecodeDesc' => '关闭可排查花屏与绿屏，代价是 CPU 占用上升',
			'video.deinterlace' => '去隔行',
			'video.deinterlaceDesc' => '老录像带 / DVD 抓取源有横向梳状纹时打开',
			'video.integrateBottomBar' => '视频控制条融入底栏',
			'video.integrateBottomBarDesc' => '将播放进度和视频控制整合进阅读底栏，随底栏一起呼出和收起',
			'video.pinDesc' => '控制条常显，不再在播放几秒后自动收起',
			'video.animatedVideo' => '动图当视频播',
			'video.animatedVideoDesc' => '把 GIF / APNG 交给视频控制器，获得暂停、逐帧与进度拖动',
			'video.autoHide' => '控制条自动隐藏',
			'video.maxRate' => '倍速上限',
			'video.defaultVolume' => '默认音量',
			'video.aliases' => '自定义视频后缀',
			'video.aliasesEmpty' => '未设置',
			'video.aliasesHint' => '逗号分隔，例如：myvid, cbr-video',
			'video.aliasesDialogHint' => '输入后按逗号分隔；小写、最多 128 条、每条最长 16 字符',
			'video.mediaSection' => '媒体格式',
			'video.imageFormats' => '图片格式表',
			'video.videoFormats' => '视频格式表',
			'video.formatsHint' => '填了就整体替换内置表，没列进来的后缀会连一页都不算；留空才用内置表',
			'video.subSize' => '字号',
			'video.subBg' => '底色',
			'video.subBottom' => '底部位置',
			'video.subLargeYellow' => '大号黄色',
			'video.reset' => '重置',
			'video.duration' => '时长',
			'video.position' => '当前',
			'video.size' => '尺寸',
			'video.dar' => '显示宽高比',
			'video.fps' => '帧率',
			'video.bitrate' => '码率',
			'video.videoCodec' => '视频编码',
			'video.audioCodec' => '音频编码',
			'video.avDrift' => '音画漂移',
			'video.loopMode' => '循环',
			'video.playbackRate' => '倍速',
			'video.abRange' => 'A-B',
			'video.sidecarSubtitles' => '外挂字幕',
			'video.notAvailable' => '—',
			'video.noBytes' => '这个视频条目取不到字节',
			'video.cannotPlay' => '这一页播不了',
			'video.animatedKeywords' => '动画化关键字',
			'video.animatedKeywordsHint' => '逗号分隔，例如：[#dyna], [#动]',
			'video.rotation' => '旋转',
			'bindingEditor.anyArea' => '任意区域',
			'bindingEditor.migrationFailed' => '旧操作绑定迁移失败，原配置已保留。可导出原文检查，或导入有效配置后重试。',
			'bindingEditor.groupNavigation' => '翻页',
			'bindingEditor.groupView' => '画面',
			'bindingEditor.groupInterface' => '界面',
			'bindingEditor.videoPlayback' => '播放',
			'bindingEditor.videoAudio' => '声音',
			'bindingEditor.videoDisplay' => '画面与字幕',
			'bindingEditor.allActions' => '全部',
			'bindingEditor.boundOnly' => '已绑定',
			'bindingEditor.unassigned' => '未绑定',
			'bindingEditor.spaceKey' => '空格',
			'bindingEditor.searchAll' => '搜索全部动作或按键',
			'bindingEditor.disabled' => '已停用',
			'bindingEditor.moreBindings' => ({required Object count}) => '另有 ${count} 条绑定',
			'bindingEditor.search' => '搜索动作、分类、上下文或输入',
			'bindingEditor.allCategories' => '全部分类',
			'bindingEditor.allContexts' => '全部上下文',
			'bindingEditor.noResults' => '没有匹配的动作',
			'bindingEditor.addBinding' => '添加绑定',
			'bindingEditor.noBindings' => '暂无绑定，添加一种输入开始配置',
			'bindingEditor.device' => '输入设备',
			'bindingEditor.context' => '上下文',
			'bindingEditor.ignoreRepeat' => '忽略重复输入',
			'bindingEditor.followUps' => '后续动作',
			'bindingEditor.add' => '添加',
			'bindingEditor.copyTo' => '复制到',
			'bindingEditor.conflict' => '绑定冲突',
			'bindingEditor.conflictHint' => '同一上下文内的输入重复，请修改或停用其中一条。修正后自动保存。',
			'bindingEditor.saved' => '已自动保存',
			'bindingEditor.pending' => '等待保存',
			'bindingEditor.invalid' => '配置未保存，请检查输入内容',
			'bindingEditor.record' => '录制',
			'bindingEditor.recordHint' => '在此区域操作，确认后应用录制结果。Esc 可取消；点击下方取消按钮可以录入 Esc。',
			'bindingEditor.recordWaiting' => '等待输入…',
			'bindingEditor.keyCode' => '键盘代码',
			'bindingEditor.trigger' => '触发方式',
			'bindingEditor.down' => '按下',
			'bindingEditor.hold' => '长按',
			'bindingEditor.instant' => '释放时触发',
			'bindingEditor.click' => '单击',
			'bindingEditor.doubleClick' => '双击',
			'bindingEditor.press' => '按下',
			'bindingEditor.duration' => '长按时长（毫秒）',
			'bindingEditor.tolerance' => '移动容差（像素）',
			'bindingEditor.button' => '鼠标按钮',
			'bindingEditor.leftButton' => '左键',
			'bindingEditor.middleButton' => '中键',
			'bindingEditor.rightButton' => '右键',
			'bindingEditor.backButton' => '后退键',
			'bindingEditor.forwardButton' => '前进键',
			'bindingEditor.up' => '向上',
			'bindingEditor.downDirection' => '向下',
			'bindingEditor.left' => '向左',
			'bindingEditor.right' => '向右',
			'bindingEditor.swipeLeft' => '左滑',
			'bindingEditor.swipeRight' => '右滑',
			'bindingEditor.swipeUp' => '上滑',
			'bindingEditor.swipeDown' => '下滑',
			'bindingEditor.tap' => '点击',
			'bindingEditor.longPress' => '长按',
			'bindingEditor.fingers' => '手指数',
			'bindingEditor.gesture' => '触控手势',
			'bindingEditor.directions' => '轨迹方向序列',
			'bindingEditor.undoDirection' => '移除最后方向',
			'bindingEditor.gamepadButton' => '手柄按钮编号',
			'bindingEditor.gamepadHint' => '手柄配置可编辑和导入导出；当前平台尚未接入手柄事件。',
			'bindingEditor.managedInput' => '此输入由轮盘或系统命令管理',
			'bindingEditor.area' => '九宫格区域',
			'bindingEditor.topLeft' => '左上',
			'bindingEditor.topCenter' => '中上',
			'bindingEditor.topRight' => '右上',
			'bindingEditor.middleLeft' => '左中',
			'bindingEditor.middleCenter' => '中心',
			'bindingEditor.middleRight' => '右中',
			'bindingEditor.bottomLeft' => '左下',
			'bindingEditor.bottomCenter' => '中下',
			'bindingEditor.bottomRight' => '右下',
			'bindingEditor.keyboard' => '键盘',
			'bindingEditor.mouse' => '鼠标',
			'bindingEditor.mouseGesture' => '鼠标轨迹',
			'bindingEditor.wheel' => '滚轮',
			'bindingEditor.touch' => '触控',
			'bindingEditor.gamepad' => '手柄',
			'bindingEditor.radial' => '轮盘',
			'bindingEditor.command' => '系统命令',
			'bindingEditor.global' => '全局',
			'bindingEditor.reader' => '阅读器',
			'bindingEditor.video' => '视频',
			'bindingEditor.panel' => '面板',
			'bindingEditor.shell' => '界面栏',
			'bindingEditor.editor' => '编辑器',
			'bindingEditor.modal' => '对话框',
			'bindingEditor.moveUp' => '上移',
			'bindingEditor.moveDown' => '下移',
			'bindingEditor.collapse' => '收起绑定',
			'bindingEditor.expand' => '展开绑定',
			'bindingEditor.actions' => '动作',
			'bindingEditor.actionList' => '动作列表',
			'bindingEditor.bindingDetails' => '绑定详情',
			'bindingEditor.bindings' => '绑定',
			'bindingEditor.restore' => '恢复默认',
			'bindingEditor.resetFilters' => '清除筛选',
			'plat.openAbove' => '在上方打开',
			'plat.openBelow' => '在下方打开',
			'plat.openLeft' => '在左侧打开',
			'plat.openRight' => '在右侧打开',
			'plat.closeTab' => '关闭标签',
			_ => null,
		};
	}
}
