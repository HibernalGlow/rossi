///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsEnUs extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEnUs({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.enUs,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en-US>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsEnUs _root = this; // ignore: unused_field

	@override 
	TranslationsEnUs $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEnUs(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$workspace$en_US workspace = _Translations$workspace$en_US._(_root);
	@override String get appName => 'Rossi';
	@override late final _Translations$common$en_US common = _Translations$common$en_US._(_root);
	@override late final _Translations$error$en_US error = _Translations$error$en_US._(_root);
	@override late final _Translations$navigation$en_US navigation = _Translations$navigation$en_US._(_root);
	@override late final _Translations$settings$en_US settings = _Translations$settings$en_US._(_root);
	@override late final _Translations$bookshelf$en_US bookshelf = _Translations$bookshelf$en_US._(_root);
	@override late final _Translations$comicInfo$en_US comicInfo = _Translations$comicInfo$en_US._(_root);
	@override late final _Translations$reader$en_US reader = _Translations$reader$en_US._(_root);
	@override late final _Translations$plugin$en_US plugin = _Translations$plugin$en_US._(_root);
	@override late final _Translations$gestureLock$en_US gestureLock = _Translations$gestureLock$en_US._(_root);
	@override late final _Translations$appBootstrap$en_US appBootstrap = _Translations$appBootstrap$en_US._(_root);
	@override late final _Translations$comments$en_US comments = _Translations$comments$en_US._(_root);
	@override late final _Translations$cache$en_US cache = _Translations$cache$en_US._(_root);
	@override late final _Translations$dataBackup$en_US dataBackup = _Translations$dataBackup$en_US._(_root);
	@override late final _Translations$webdavSync$en_US webdavSync = _Translations$webdavSync$en_US._(_root);
	@override late final _Translations$ocr$en_US ocr = _Translations$ocr$en_US._(_root);
	@override late final _Translations$realSr$en_US realSr = _Translations$realSr$en_US._(_root);
	@override late final _Translations$about$en_US about = _Translations$about$en_US._(_root);
	@override late final _Translations$oldHome$en_US oldHome = _Translations$oldHome$en_US._(_root);
	@override late final _Translations$more$en_US more = _Translations$more$en_US._(_root);
	@override late final _Translations$search$en_US search = _Translations$search$en_US._(_root);
	@override late final _Translations$discover$en_US discover = _Translations$discover$en_US._(_root);
	@override late final _Translations$searchResult$en_US searchResult = _Translations$searchResult$en_US._(_root);
	@override late final _Translations$comicList$en_US comicList = _Translations$comicList$en_US._(_root);
	@override late final _Translations$comicEntry$en_US comicEntry = _Translations$comicEntry$en_US._(_root);
	@override late final _Translations$comicFollow$en_US comicFollow = _Translations$comicFollow$en_US._(_root);
	@override late final _Translations$changelog$en_US changelog = _Translations$changelog$en_US._(_root);
	@override late final _Translations$webview$en_US webview = _Translations$webview$en_US._(_root);
	@override late final _Translations$oldRanking$en_US oldRanking = _Translations$oldRanking$en_US._(_root);
	@override late final _Translations$login$en_US login = _Translations$login$en_US._(_root);
	@override late final _Translations$fontSetting$en_US fontSetting = _Translations$fontSetting$en_US._(_root);
	@override late final _Translations$download$en_US download = _Translations$download$en_US._(_root);
	@override late final _Translations$foregroundTask$en_US foregroundTask = _Translations$foregroundTask$en_US._(_root);
	@override late final _Translations$notification$en_US notification = _Translations$notification$en_US._(_root);
	@override late final _Translations$update$en_US update = _Translations$update$en_US._(_root);
	@override late final _Translations$dialog$en_US dialog = _Translations$dialog$en_US._(_root);
	@override late final _Translations$shelfMenu$en_US shelfMenu = _Translations$shelfMenu$en_US._(_root);
	@override late final _Translations$video$en_US video = _Translations$video$en_US._(_root);
	@override late final _Translations$bindingEditor$en_US bindingEditor = _Translations$bindingEditor$en_US._(_root);
	@override late final _Translations$plat$en_US plat = _Translations$plat$en_US._(_root);
}

// Path: workspace
class _Translations$workspace$en_US extends Translations$workspace$zh_CN {
	_Translations$workspace$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String laneTapExpandHint({required Object title}) => '${title} (tap to expand the lane)';
	@override String laneTapCollapseHint({required Object title}) => '${title} (tap to collapse the lane)';
	@override String laneDragHint({required Object title}) => '${title} — press and hold to drag lanes into a new order';
	@override String laneSortHint({required Object title}) => '${title} (pick “Edit layout” in the lane menu to reorder)';
	@override String allowedRange({required Object min, required Object max}) => 'Allowed ${min}–${max}';
	@override String dockToName({required Object label}) => 'Dock: ${label}';
	@override String laneWidthPx({required Object px}) => 'Lane width: ${px} px';
	@override String dockToLabel({required Object label}) => 'Dock to ${label}';
	@override String slotCount({required Object count}) => '${count} slots';
	@override String columnsPerRow({required Object columns}) => '${columns} slots per row now';
	@override String imagesCountBadge({required Object n}) => '${n} images';
	@override String highestPage({required Object value}) => 'Highest: ${value}';
	@override String worksCount({required Object n}) => '${n} works';
	@override String sharePercent({required Object v}) => '${v}% of the total';
	@override String get heatLegendLow => 'Low';
	@override String periodDetailLine({required Object label, required Object count, required Object hours}) => '${label} · ${count} records\n${hours}';
	@override String restoreNamed({required Object title}) => 'Restore “${title}”';
	@override String get fullWidthFullHeight => 'Full width and full height';
	@override String resizePreview({required Object w, required Object h}) => '${w} × ${h} · release to save';
	@override String portSkippedLines({required Object lines}) => 'Skipped entries:\n${lines}';
	@override String streakNowDays({required Object n}) => 'Current streak: ${n} days';
	@override String mostlyAt({required Object period}) => 'Mostly ${period}';
	@override String monthsAgo({required Object months}) => '${months} months ago';
	@override String artbookCount({required Object n}) => '${n} art books';
	@override String seenAtPage({required Object pageNum}) => 'Seen at p.${pageNum}';
	@override String sourceMixItem({required Object count, required Object percent}) => '${count} records · ${percent}%';
	@override String sourceMixHeader({required Object n}) => 'Sample records · ${n} sources';
	@override String streakPointLine({required Object date, required Object value}) => '${date}: ${value} days in a row';
	@override String streakDaysLine({required Object label, required Object value}) => '${label}: ${value} days';
	@override String insightHeaderExpand({required Object label, required Object position, required Object total, required Object title}) => '${label} · ${position}/${total} · expand ${title}';
	@override String heatCellLine({required Object weekday, required Object hour, required Object count}) => '${weekday} ${hour} · ${count} records';
	@override String heatPeakLabel({required Object weekday, required Object hour}) => 'Peak · ${weekday} ${hour}';
	@override String heatPeakShort({required Object weekday, required Object hour}) => 'Peak ${weekday} ${hour}';
	@override String compactHeatmapExpandHours({required Object day, required Object hours}) => '${day} · ${hours} h per cell · expand the reading heatmap';
	@override String hoursPerCell({required Object hours}) => '${hours} h per cell';
	@override String compactHeatmapExpand({required Object day}) => '${day} · expand the reading heatmap';
	@override String busiestPeriodLabel({required Object period}) => 'Most records in ${period}';
	@override String weekdayRecordLine({required Object day, required Object count}) => '${day}: ${count} records';
	@override String busiestWeekdayLabel({required Object day}) => 'Busiest on ${day}';
	@override String selectedLastReadLines({required Object key, required Object count}) => '${key} · ${count} last-read records';
	@override String dayRecordLine({required Object key, required Object count}) => '${key}: ${count} records';
	@override String activeDaysCount({required Object n}) => '${n} active days';
	@override String collapseNamed({required Object title}) => 'Collapse ${title}';
	@override String insertTarget({required Object name}) => 'Insert into: ${name}';
	@override String activeSwitchCount({required Object activeCount}) => '${activeCount} switches on';
	@override String switchToastActiveOf3({required Object activeCount}) => '${activeCount} of 3 switches on';
	@override String peakAllocated({required Object value}) => 'Peak ${value}';
	@override String failedWith({required Object error}) => 'Failed · ${error}';
	@override String registeredCount({required Object n}) => '${n} registered in total';
	@override String readyOfTotal({required Object ready, required Object total}) => '${ready} of ${total} ready';
	@override String sourceCountLabel({required Object n}) => '${n} sources';
	@override String fileKindLabel({required Object kind}) => '${kind} file';
	@override String passthroughDepthLabel({required Object value}) => 'Passthrough depth: ${value}';
	@override String contentLayoutLabel({required Object value}) => 'Content layout: ${value}';
	@override String sortFieldLabel({required Object value}) => 'Sort: ${value}';
	@override String entryStyleLabel({required Object value}) => 'Entry style: ${value}';
	@override String filterTypeLabel({required Object value}) => 'Type: ${value}';
	@override String depthLimitLabel({required Object n}) => 'Depth ≤${n}';
	@override String notSearchedBelow({required Object n}) => 'Below level ${n} not searched';
	@override String searchScanned({required Object n}) => '${n} scanned';
	@override String searchHits({required Object n}) => '${n} hits';
	@override String tenThousandRecords({required Object v}) => '${v}×10k records';
	@override String slowScanNote({required Object label}) => '${label} · tens of seconds on a slow disk; results appear after one pass';
	@override String recursiveSearchScanned({required Object scanned}) => 'Searching recursively · scanned ${scanned}';
	@override String restoreTabTitle({required Object title}) => 'Restore tab: ${title}';
	@override String selectedCount({required Object n}) => '${n} selected';
	@override String filteringBy({required Object query}) => 'Filter: ${query}';
	@override String pageN({required Object n}) => 'Page ${n}';
	@override String openLocalComicFailed({required Object error}) => 'Error opening the local comic: ${error}';
	@override String daysAgo({required Object days}) => '${days} days ago';
	@override String childCount({required Object n}) => '${n} items';
	@override String noMatchThisLevelSuggest({required Object query}) => 'Nothing at this level matches “${query}”; use “search subfolders” above to look deeper';
	@override String noMatchInSubdirs({required Object query}) => 'No entries in subfolders match “${query}”';
	@override String tasksCount({required Object n}) => '${n} tasks';
	@override String booksCount({required Object n}) => '${n} books';
	@override String get builtinWord => 'Built-in';
	@override String onlineSourceFrom({required Object from}) => 'Online source · ${from}';
	@override String pagesRemaining({required Object n}) => '${n} pages left';
	@override String currentOfTotalPages({required Object total}) => 'Current page · ${total} pages';
	@override String dateMD({required Object month, required Object day}) => '${month}/${day}';
	@override String dateYMD({required Object year, required Object month, required Object day}) => '${year}-${month}-${day}';
	@override String heatmapCell({required Object weekday, required Object range, required Object count}) => '${weekday} ${range}: ${count} records';
	@override String theseCountItems({required Object count}) => 'these ${count} items';
	@override String duplicateInFileCount({required Object n}) => '${n} duplicated inside the file';
	@override String keptLocalCount({required Object n}) => '${n} kept from this device';
	@override String progressUpdatedCount({required Object n}) => '${n} progress entries updated';
	@override String skippedCount({required Object n}) => '${n} skipped';
	@override String alreadyPresentCount({required Object n}) => '${n} already present';
	@override String revivedCount({required Object n}) => '${n} revived';
	@override String addedCount({required Object n}) => '${n} added';
	@override String keyMismatch({required Object expected}) => 'uniqueKey doesn\'t match source:comicId; expected ${expected}';
	@override String itemNumber({required Object n}) => 'Entry #${n}';
	@override String unsupportedFormatVersion({required Object version}) => 'Unsupported format version ${version}';
	@override String invalidJson({required Object error}) => 'Not valid JSON: ${error}';
	@override String portImportFailed({required Object label, required Object error}) => 'Importing ${label} failed: ${error}';
	@override String portFileUnreadable({required Object error}) => 'Can\'t read this file: ${error}';
	@override String portExportFailed({required Object label, required Object error}) => 'Exporting ${label} failed: ${error}';
	@override String portExportDone({required Object count, required Object label, required Object target}) => 'Exported ${count} ${label} entries\n${target}';
	@override String portListEmpty({required Object label}) => '${label} is still empty — there is nothing to export';
	@override String opFirstFailure({required Object summary, required Object failure}) => '${summary} — first failure reason: ${failure}';
	@override String pickPasteTarget({required Object verb, required Object subject}) => '${verb}${subject} — pick a folder to paste into';
	@override String movedToTrashSystem({required Object subject, required Object hint}) => 'Moved ${subject} to the trash, ${hint} (in the system trash)';
	@override String movedToTrash({required Object subject, required Object hint}) => 'Moved ${subject} to the trash, ${hint}';
	@override String cannotOpenFileManager({required Object error}) => 'Can\'t open the file manager: ${error}';
	@override String pathsCopied({required Object count}) => 'Copied ${count} paths';
	@override String deleteConfirmSubject({required Object subject, required Object outcome}) => '${subject} will be deleted. ${outcome}.';
	@override String deleteForeverWarning({required Object subject}) => '${subject} will be deleted permanently — not sent to the trash and can\'t be undone.';
	@override String get loadingShort => 'Loading';
	@override String get readingHubTitle => 'Reading hub';
	@override String get chapterIdLabel => 'Chapter ID';
	@override String get portraitFormat => 'Portrait';
	@override String get peep => 'Peek';
	@override String get topTags => 'Top tags';
	@override String get libraryLabel => 'Library';
	@override String get preloadPath => 'Preload path';
	@override String get preloadStatus => 'Preload status';
	@override String get topBarIsThatRow => 'The top bar is the row with exit / title / mode switch / reset layout';
	@override String get pagePath => 'Page path';
	@override String get pageTemplateBookVars => 'Page templates can also use {{book.*}} variables; tap any variable chip to insert it.';
	@override String get pageTitleTemplate => 'Page title template';
	@override String get pageFileName => 'Page file name';
	@override String get pageToastTemplate => 'Page toast template';
	@override String get pageDescriptionTemplate => 'Page description template';
	@override String get pageNavigation => 'Page navigation';
	@override String get pageListNotReady => 'Page list not ready';
	@override String get pageListTotal => 'Page-list total';
	@override String get pageList => 'Page list';
	@override String get pageNumber => 'Page number';
	@override String get pageUrl => 'Page URL';
	@override String get pagesModified => 'pages modified';
	@override String get audioLabel => 'Audio';
	@override String get areaBasis => 'Area basis';
	@override String get panelBarFloating => 'Panel bar: floating';
	@override String get panelBarHint => 'Panel bar (drag to another edge or make it floating; right-click or long-press for settings)';
	@override String get hideLaneWidthBadge => 'Hide the lane width badge';
	@override String get hideWorkspaceTopBar => 'Hide the workspace top bar';
	@override String get refreshPerPageNoGuessing => 'Refreshes per page; anything unmeasured stays a guess-free blank';
	@override String get randomRoam => 'Random browse';
	@override String get randomLabel => 'Random';
	@override String get matchRelativePath => 'Matches the relative path under the search root as well as the entry name';
	@override String get confineToLane => 'Confine to the lane';
	@override String get confineToThisLane => 'Confine to this lane';
	@override String get readingProgressPercent => 'Reading progress (%)';
	@override String get readingProgressLabel => 'Reading progress';
	@override String get readingHeat => 'Reading heat';
	@override String get readingFilter => 'Reading filter';
	@override String get readingInsights => 'Reading insights';
	@override String get workspaceHome => 'Workspace';
	@override String get continueReading => 'Continue reading';
	@override String get todayReading => 'Today';
	@override String get longestStreak => 'Longest streak';
	@override String get readingSources => 'Reading sources';
	@override String get dayUnit => 'days';
	@override String get visitUnit => 'visits';
	@override String get sourceUnit => 'sources';
	@override String get pageUnit => 'pages';
	@override String get openDetail => 'Details';
	@override String get noReadingYet => 'No reading history yet — pick one from the bookshelf';
	@override String get mobileCardMissing => 'Card not found';
	@override String get mobileCardUnsupported => 'This card is unavailable on this device';
	@override String get infoSheetEntry => 'Comic info';
	@override String get readingOverview => 'Reading overview';
	@override String get readingPeriods => 'Reading time of day';
	@override String get readingWorkhole => 'Reading workhole';
	@override String get readerLaneIdle => 'The reader lane is idle';
	@override String get readerEn => 'Reader';
	@override String get readingHistoryEn => 'History';
	@override String get readingHistory => 'Reading history';
	@override String get readingToastOverlay => 'Reading switch overlay toast';
	@override String get readingLabel => 'Reading';
	@override String get longPressDragReorder => 'Long-press and drag to reorder or change lane';
	@override String get imageHeaderUnmeasured => 'Can\'t read the image header';
	@override String get resetLayoutHint => 'Reset the layout (doesn\'t affect the book you\'re reading)';
	@override String get renameBookmarkList => 'Rename bookmark list';
	@override String get renameDeleteList => 'Rename / delete this list';
	@override String get booksQueued => 'books queued';
	@override String get layoutFitsPanel => 'Layout and sizes that suit the current panel';
	@override String get exitSoloEn => 'Exit solo';
	@override String get exitSolo => 'Exit solo';
	@override String get exitTimeline => 'Exit the timeline';
	@override String get exitSearchToFolder => 'Leave the search results and return to this tab\'s own folder';
	@override String get exitWorkspaceHint => 'Exit the workspace (Esc works too)';
	@override String get exitWorkspace => 'Exit the workspace';
	@override String get exitMultiselect => 'Exit multi-select';
	@override String get restoreSwipeAfterExit => 'Restores horizontal swiping between panels when it exits';
	@override String get streakReading => 'Reading streak';
	@override String get streakDays => 'Streak days';
	@override String get streakLabel => 'Streak';
	@override String get runningTasks => 'Running tasks';
	@override String get progressLabel => 'Progress';
	@override String get enterFolder => 'Enter the folder';
	@override String get thisIsSwitchToastPreview => 'This is a switch-toast preview';
	@override String get allCardsCollapsed => 'Every card in this panel is collapsed';
	@override String get noFileManagerOnPlatform => 'This platform has no file manager to invoke';
	@override String get listHasNoBookmarks => 'This list has no bookmarks yet';
	@override String get itemNeedsLocalArchive => 'This item needs to be a local archive before it can be measured';
	@override String get thisItem => 'this item';
	@override String get thisWall => 'this wall';
	@override String get noPluginsInstalled => 'No plugins installed yet';
	@override String get noBookmarksYet => 'No bookmarks yet — add one from the details page';
	@override String get last7ReadingTrend => 'Reading trend (7 days)';
	@override String get last7Records => 'Records (7 days)';
	@override String get last7Days => 'Last 7 days';
	@override String get last3Days => 'Last 3 days';
	@override String get last28Records => 'Records (28 days)';
	@override String get last28Active => 'Active days (28)';
	@override String get last28NoRecords => 'No records in the last 28 days';
	@override String get last28Days => 'Last 28 days';
	@override String get boundaryToastText => 'Boundary toast text';
	@override String get carrierDistribution => 'Medium distribution';
	@override String get carrierLabel => 'Medium';
	@override String get goToFolder => 'Go to the folder';
	@override String get jumpBar => 'Jump bar';
	@override String get pathActions => 'Path actions';
	@override String get pathLabel => 'Path';
	@override String get aggregateSourceSearch => 'Aggregate search across sources';
	@override String get trendLabel => 'Trend';
	@override String get upscaleStage => 'Upscale stage';
	@override String get upscaleSwitch => 'Upscale switch';
	@override String get afterUpscale => 'After upscaling';
	@override String get resourceWorkhole => 'Resource workhole';
	@override String get debugSource => 'Debug source';
	@override String get toastAtChapterEnd => 'Remind when turning past the end of a chapter';
	@override String get detailedInformation => 'Details';
	@override String get detailedLabel => 'Detailed';
	@override String get laneMoreEditLayout => 'This lane · edit layout';
	@override String get visits => 'Visits';
	@override String get settingsAndTools => 'Settings and tools';
	@override String get triggerCondition => 'Trigger condition';
	@override String get triggersAllOff => 'All triggers off';
	@override String get decodeBufferPlusCache => 'Decode buffer + image cache';
	@override String get viewModeNotInTimeline => 'View mode (not available in the timeline)';
	@override String get viewModeLabel => 'View mode';
	@override String get seeDetailsBelow => 'See the details below';
	@override String get decorativeShapes => 'Decorative shapes';
	@override String get installNewSource => 'Install a new source';
	@override String get fetching => 'Fetching…';
	@override String get freeThumbnails => 'Free thumbnails';
	@override String get customLayout => 'Custom layout';
	@override String get pageTurnToast => 'Page-turn toast';
	@override String get pageToastShowsNumber => 'Shows the page number live when turning or jumping';
	@override String get pageAnimation => 'Page-turn animation';
	@override String get jpTranslated => 'Translated';
	@override String get networkImageCached => 'Network image · downloaded then served from the image cache';
	@override String get missingTitle => 'Missing title';
	@override String get missingSourceOrComicId => 'Missing source or comicId';
	@override String get thumbnailsLabel => 'Thumbnails';
	@override String get editPath => 'Edit path';
	@override String get editLongPressHints => 'While editing, long-press a tab to reorder or move it across lanes, or long-press the header icon to reorder lanes';
	@override String get editLayout => 'Edit layout';
	@override String get encodedFormat => 'Encoded format';
	@override String get encodedSize => 'Encoded size';
	@override String get weightBlendsEverything => 'Blends content count, recent use and reading status.';
	@override String get resumeLastReading => 'Resume the last reading';
	@override String get counting => 'Counting';
	@override String get textureReady => 'Texture ready';
	@override String get texture => 'Texture';
	@override String get compactList => 'Compact list';
	@override String get pasteIntoItem => 'Paste into this item';
	@override String get pasteHere => 'Paste into this folder';
	@override String get lengthDistribution => 'Length distribution';
	@override String get lengthLabel => 'Length';
	@override String get emphasiseReading => 'Emphasises what you are reading.';
	@override String get emphasiseRecent => 'Emphasises recently used content.';
	@override String get passthroughMode => 'Passthrough mode';
	@override String get gapFill => 'Gap fill';
	@override String get gapComponentsTitle => 'Gaps & components';
	@override String get gapComponentsDescription => 'Random shapes and mini widgets in one place: pick an overall mode, then toggle each item — every item previews what it looks like.';
	@override String get gapPreviewLabel => 'Preview';
	@override String get gapEnableAll => 'Enable all';
	@override String get gapDisableAll => 'Disable all';
	@override String get gapShapesSection => 'Random shapes';
	@override String get gapWidgetsSection => 'Mini widgets';
	@override String get gapShapeBlob => 'Blob';
	@override String get gapShapeBurst => 'Burst';
	@override String get gapShapeClover => 'Clover';
	@override String get gapShapeGem => 'Gem';
	@override String get gapShapeArch => 'Arch';
	@override String get gapShapeFlower => 'Flower';
	@override String get gapShapeRing => 'Ring';
	@override String get gapShapeWave => 'Wave';
	@override String get gapCompletion => 'Completion';
	@override String get gapHeatmap => 'Reading heat';
	@override String get gapWeekday => 'Weekday rhythm';
	@override String get gapSpan => 'Collection span';
	@override String get gapUnread => 'Unread pool';
	@override String get gapMilestone => 'Next milestone';
	@override String get gapAverageProgress => 'average progress';
	@override String get gapFinishedBooks => 'finished';
	@override String get gapUnreadBooks => 'unread';
	@override String get gapHeatWindow => 'Last 8 weeks';
	@override String get gapWeekdayRhythm => 'Weekday split';
	@override String get gapSpanDaysLabel => 'days span';
	@override String get gapSpanEarliest => 'since';
	@override String get gapUnreadPool => 'not started';
	@override String get gapMilestoneHint => 'to go';
	@override String gapComponentCount({required Object on, required Object total}) => '${on} / ${total} on';
	@override String gapMinSize({required Object w, required Object h}) => 'min ${w} × ${h}';
	@override String get gapResetDefaults => 'Reset to defaults';
	@override String get wallTabSize => 'Size';
	@override String get wallTabLayout => 'Layout';
	@override String get wallTabComponents => 'Components';
	@override String get wallTabCover => 'Cover';
	@override String get wallTabWeights => 'Weights';
	@override String get idleState => 'Idle';
	@override String get moveToTrashNoUndo => 'Move to trash (can\'t be undone)';
	@override String get moveToTrash => 'Move to trash';
	@override String get folderPath => 'Folder path';
	@override String get folderLabel => 'Folder';
	@override String get imageTuning => 'Image tuning';
	@override String get aspectComposition => 'Aspect mix';
	@override String get aspectFormat => 'Aspect';
	@override String get fillWithExpressiveShapes => 'Fills the gaps with random Expressive outlines and icons.';
	@override String get soloThisLaneEn => 'Solo';
	@override String get soloThisLane => 'Make this lane solo';
	@override String get statusLabel => 'Status';
	@override String get clickToCollapse => 'Tap to collapse';
	@override String get clickToExpand => 'Tap to expand';
	@override String get tapCover => 'Tap the cover';
	@override String get clickToFill => 'Tap to fill';
	@override String get comicArchive => 'Comic archive';
	@override String get comicIdLabel => 'Comic ID';
	@override String get chineseLocalized => 'CN-localised';
	@override String get renderPath => 'Render path';
	@override String get clearSearchAndCollapse => 'Clear the search and collapse';
	@override String get lateNight => 'Late night';
	@override String get activePeak => 'Active peak';
	@override String get activeDays => 'Active days';
	@override String get activeState => 'Active';
	@override String get noEntriesAfterFilter => 'No entries match the search or type filter';
	@override String get noEntries => 'No entries';
	@override String get noEnabledSource => 'No enabled image source';
	@override String get nothingToDisplay => 'Nothing to display';
	@override String get noMatchingPages => 'No matching pages';
	@override String get noMatchingHistory => 'No matching reading records';
	@override String get noMatchingBookmarks => 'No matching bookmarks';
	@override String get immersiveWorkhole => 'Immersive workhole';
	@override String get deleteForeverQuestion => 'Delete permanently?';
	@override String get deleteForever => 'Delete permanently';
	@override String get weeklyReadingRhythm => 'Weekly reading rhythm';
	@override String get everyFieldIsMeasured => 'Every value comes from a recorded field, not from "I tweaked it so it must be fine"';
	@override String get normalState => 'Normal';
	@override String get recursiveSearchPending => 'Searching recursively; results appear after one pass…';
	@override String get recursiveSearching => 'Searching recursively…';
	@override String get followingProgress => 'Following the reading progress';
	@override String get editingLayoutFinishInMenu => 'Editing the layout · finish in the menu';
	@override String get countingReadingHistory => 'Counting reading history';
	@override String get bannerLabel => 'Banner';
	@override String get rootPath => 'Root path';
	@override String get areaByAspectRatio => 'Allocates card space by the source aspect ratio.';
	@override String get longestSampleDays => 'Longest in sample · days';
	@override String get longestSample => 'Longest in sample';
	@override String get theWidthBadgeNextToHeader => 'The "400px" badge to the right of the lane header';
	@override String get titleLabel => 'Title';
	@override String get sourceKey => 'Source key';
	@override String get sourceType => 'Source type';
	@override String get sourceComposition => 'Source mix';
	@override String get sourceBreakdown => 'Source breakdown';
	@override String get sourceModifiedAt => 'Source modified';
	@override String get sourceLabel => 'Source';
	@override String get entryCount => 'Entries';
	@override String get itemsUpdated => 'items updated';
	@override String get itemsContent => 'items';
	@override String get chapterDonePreparingNext => 'This chapter is finished · preparing the next one';
	@override String get platformUnsupported => 'Not supported on this platform';
	@override String get localComicsEn => 'Local Manga';
	@override String get localComics => 'Local comics';
	@override String get localWorks => 'Local works';
	@override String get localLabel => 'Local';
	@override String get lastPageToast => 'Last-page toast';
	@override String get notTurnedOn => 'Off';
	@override String get notEnabled => 'Not enabled';
	@override String get serverLabel => 'Server';
	@override String get maxThirtyTwoLevels => 'At most 32 levels';
	@override String get lastPageToastText => 'Last-page toast text';
	@override String get noReadingHistory => 'No reading history yet';
	@override String get noRecordsYet => 'No records yet';
	@override String get noHeatRecords => 'No heat records yet';
	@override String get noEnabledPlugins => 'No enabled plugins yet';
	@override String get noVisitHistory => 'No visit history yet';
	@override String get normalOneWideTwoSlots => 'Normal cards take 1 slot, wide cards 2';
	@override String get eveningNight => 'Night';
	@override String get eveningLabel => 'Evening';
	@override String get showHiddenFiles => 'Show hidden files';
	@override String get showTarget => 'Show target';
	@override String get showQuickSwitchBar => 'Show the quick-switch bar';
	@override String get showWorkspaceTopBar => 'Show the workspace top bar';
	@override String get showSubFileNames => 'Show sub-file names';
	@override String get timeInformation => 'Time information';
	@override String get timePeriod => 'Time of day';
	@override String get earlyFavourites => 'Early favourites';
	@override String get cannotUndo => 'Can\'t be undone';
	@override String get noAnimation => 'No animation';
	@override String get squareFormat => 'Square';
	@override String get newTab => 'New tab';
	@override String get newBookmarkList => 'New bookmark list';
	@override String get newName => 'New name';
	@override String get fileManagement => 'File manager';
	@override String get fileBrowsing => 'File browsing';
	@override String get fileOperations => 'File operations (copy / move / delete)';
	@override String get foldersFirst => 'Folders first';
	@override String get fileNameLabel => 'File name';
	@override String get weightBiggerWins => 'Larger values stand out more; 0 disables it. When several match, the highest weight wins.';
	@override String get switchToFloating => 'Switch to floating';
	@override String get collapseSearch => 'Collapse search';
	@override String get collapseChildren => 'Collapse children';
	@override String get collapseSubfolders => 'Collapse subfolders';
	@override String get collapseInformation => 'Collapse info';
	@override String get favouriteTime => 'Favourited at';
	@override String get favouriteList => 'Favourites';
	@override String get localOpenSupportDesc => 'Supports zip, cbz, folders, PDFs and image archives. Rust unpacks quickly and feeds the D3D12/Metal composition chain directly.';
	@override String get undoLastStep => 'Undo the last step';
	@override String get summaryLabel => 'Summary';
	@override String get searchSpaceExclude => 'Search (space-separated, - to exclude)';
	@override String get searchPageOrFileName => 'Search page number or file name...';
	@override String get searchField => 'Search bar';
	@override String get searchTitleAuthorSource => 'Search title / author / source';
	@override String get pluginRunState => 'Plugin running state';
	@override String get pluginMarket => 'Plugin market';
	@override String get controlPanel => 'Control panel';
	@override String get takeOver => 'Take over';
	@override String get keepReading => 'Continue reading';
	@override String get sortingTimelineFixed => 'Sorting (the timeline always sorts by time)';
	@override String get sortMode => 'Sort mode';
	@override String get emphasiseByTagWeights => 'Emphasises content using your custom tag weights.';
	@override String get areaByDiskUsage => 'Allocates display area by how much disk space each entry takes.';
	@override String get timelineByDay => 'Timeline by day';
	@override String get dragTitleToReorder => 'Press and hold the title to drag-reorder';
	@override String get bookmarkListDesc => 'Organise bookmarks by topic. After creating one, bookmarks can be moved into this list.';
	@override String get dragResizeWorkhole => 'Drag to resize the workhole';
	@override String get dragToResize => 'Drag to resize';
	@override String get collapseToBarEn => 'Collapse';
	@override String get collapseToBar => 'Collapse into a compact bar';
	@override String get saveSearchAsTab => 'Save these search results as a new tab';
	@override String get setHomeHere => 'Make this folder the home';
	@override String get openReader => 'Open the reader';
	@override String get openLocal => 'Open local';
	@override String get toastOnOpenOrSwitch => 'Pops when a comic is opened or switched to';
	@override String get openWorkhole => 'Open the workhole';
	@override String get showPageNavWhenOpen => 'Shows page navigation once a book is open';
	@override String get showFileTimesWhenOpen => 'Shows file times once a book is open';
	@override String get showCurrentPageWhenOpen => 'Shows current-page info once a book is open';
	@override String get showStorageWhenOpen => 'Shows storage info once a book is open';
	@override String get showPresentPrefetchWhenOpen => 'Shows presenter and prefetch status once a book is open';
	@override String get showBookInfoWhenOpen => 'Shows book info once a book is open';
	@override String get imFeelingLucky => 'I\'m feeling lucky';
	@override String get restoreDefaultSize => 'Restore the default size';
	@override String get readerLaneSoloHint => 'Anything opened from the shelf on the left or discover on the right is read in this lane; tap the solo button in the bar header to make it fill the viewport instantly.';
	@override String get footnoteSampleStreakDays => 'Consecutive days with records in the sample · not the full reading log';
	@override String get footnoteSampleStreak => 'Consecutive days within the sample · not the full reading log';
	@override String get footnotePeriod28 => 'Last 28 days · distributed by local time of the last read';
	@override String get footnoteWeekday28 => 'Last 28 days · last-reading records summed by weekday';
	@override String get footnoteLast500 => 'Last-reading records of the most recent 500 comics · not a total count or reading time';
	@override String searchDepthTooltip({required Object depths, required Object detail}) => 'Tap to cycle the recursion depth (${depths} levels). ${detail}';
	@override String get shortSat => 'Sat';
	@override String get shortFri => 'Fri';
	@override String get shortThu => 'Thu';
	@override String get shortWed => 'Wed';
	@override String get shortTue => 'Tue';
	@override String get shortMon => 'Mon';
	@override String get shortSun => 'Sun';
	@override String get restoreDefaultWidth => 'Restore the default width';
	@override String get restorePanelBarPosition => 'Restore the panel bar\'s default position';
	@override String get restoreCollapsedCards => 'Restore collapsed cards';
	@override String get restoreClosedTabs => 'Restore closed tabs';
	@override String get totalPagesLabel => 'Total pages';
	@override String get toContinue => 'To continue';
	@override String get queueStackCards => 'Queue stack';
	@override String get currentPageCost => 'Current page time';
	@override String get currentPageNumber => 'Current page number';
	@override String get currentPageFile => 'Current page file';
	@override String get currentPageSize => 'Current page size';
	@override String get currentPageModifiedAt => 'Current page modified';
	@override String get currentPageHandoffMs => 'Current page hand-off time (ms)';
	@override String get currentStreakDays => 'Current streak · days';
	@override String get currentStreak => 'Current streak';
	@override String get noHitThisLevel => 'No hits at this level; turn on "include subfolders" and search again (a full scan takes tens of seconds on a slow disk)';
	@override String get folderNoMedia => 'This folder has no browsable comics or media files';
	@override String get folderNoChildren => 'This folder has nothing to show';
	@override String get folderNotInSnapshot => 'This folder is not in the current search or folder snapshot. Enter it to see what is inside.';
	@override String get archiveLabel => 'Archive';
	@override String get onComparingOriginal => 'On (comparing with the original)';
	@override String get switchedOn => 'On';
	@override String get fieldsFillOnOpen => 'These cells fill in as soon as a book opens; anything unmeasurable stays —';
	@override String get linking => 'Linking';
	@override String get avgPagesPerBook => 'Average pages per book';
	@override String get regularWidth => 'Regular width';
	@override String get commonTags => 'Common tags';
	@override String get topCreators => 'Top creators';
	@override String get market => 'Market';
	@override String get limitReached => 'Limit reached';
	@override String get isLastPage => 'This is the last page';
	@override String get searchHistoryCleared => 'Search history cleared';
	@override String get followProgressPaused => 'Paused following the reading progress';
	@override String get fileManagerOpened => 'File manager opened';
	@override String get gpuReadyState => 'Ready';
	@override String get pathCopied => 'Path copied';
	@override String get copied => 'Copied';
	@override String get pagesPresented => 'Pages presented';
	@override String get cutDone => 'Cut';
	@override String get writtenToCacheShare => 'Written to the cache; save it from the share sheet';
	@override String get aborted => 'Aborted';
	@override String get workholeSize => 'Workhole size';
	@override String get peakDay => 'Peak day';
	@override String get peakValue => 'Peak';
	@override String get expandLane => 'Expand lane';
	@override String get polledEvery3s => 'Polled every 3 s while expanded';
	@override String get expandChildren => 'Expand children';
	@override String get expandSubfolders => 'Expand subfolders';
	@override String get expandInformation => 'Expand information';
	@override String get expandLabel => 'Expand';
	@override String get displayWallSettings => 'Display wall settings · long-press to toggle the wall';
	@override String get displayWallCustom => 'Display wall customise';
	@override String get displayWall => 'Display wall';
	@override String get searchDepthCostHint => 'More depth is slower: one full-library scan takes tens of seconds on a slow disk; too shallow misses deeper folders';
	@override String get readyWaiting => 'Ready, waiting';
	@override String get readyState => 'Ready';
	@override String get dustyReread => 'Shelf finds';
	@override String get widgetsOnceThenShapes => 'Each widget appears once per wall; the remaining gaps are filled with random shapes.';
	@override String get coverGrid => 'Cover grid';
	@override String get coverCollage => 'Cover collage';
	@override String get coverList => 'Cover list';
	@override String get coverLabel => 'Cover';
	@override String get exportAsJson => 'Export as JSON';
	@override String get importExport => 'Import / export';
	@override String get cardWidthAutoColumns => 'Width is the target size; the column count adapts to the panel. Wide cards take two slots and can sit beside normal ones.';
	@override String get finishEditing => 'Finish editing';
	@override String get finishLayout => 'Finish layout';
	@override String get storageInformation => 'Storage information';
	@override String get saveAsTab => 'Save as tab';
	@override String get subFilesShowAll => 'Sub-files: show all';
	@override String get subFilesShowOne => 'Sub-files: show one';
	@override String get daysWithRecords => 'days with records';
	@override String get sizeCompare => 'Size comparison';
	@override String get sizeLabel => 'Size';
	@override String get multiColumnLanes => 'Multi-column lanes';
	@override String get searchAnyToken => 'Union across tokens (by default every token must match)';
	@override String get multiOutlinedSelected => 'Multiple · the outline marks the selection';
	@override String get duplicateTab => 'Duplicate tab';
	@override String get copyPath => 'Copy path';
	@override String get copyPosition => 'Copy position';
	@override String get einkRefresh => 'E-ink refresh';
	@override String get basedOnLast500 => 'Based on the last-reading records of the most recent 500 comics';
	@override String get readingProgress => 'Reading progress';
	@override String get currentlyReading => 'Reading';
	@override String get onlineSourceNoFileTime => 'Online sources have no local file times';
	@override String get onlineSourceNoArchive => 'Online sources have no archive';
	@override String get onlineSource => 'Online source';
	@override String get onlineLabel => 'Online';
	@override String get openInNewTab => 'Open in a new tab';
	@override String get readerLaneReadsHint => 'Anything opened from the shelf on the left or discover on the right is read in this lane;';
	@override String get searchSubdirs => 'Search inside subfolders';
	@override String get gallery => 'Gallery';
	@override String get imageSize => 'Image size';
	@override String get imagesLabel => 'Images';
	@override String get sourceLocalAggregate => 'Local source aggregate';
	@override String get sourceExtensions => 'Source extensions';
	@override String get sourceShortcuts => 'Source shortcuts';
	@override String get imageSourcesEn => 'Extensions';
	@override String get imageSources => 'Sources and extensions';
	@override String get sourcesToolsOcr => 'Sources · Tools · OCR';
	@override String get imageProcessingStage => 'Image processing stage';
	@override String get imageInformation => 'Image information';
	@override String get pinTab => 'Pin tab';
	@override String get pinHere => 'Pin here';
	@override String get backToFolder => 'Back to the folder';
	@override String get backHome => 'Back home';
	@override String get backToLaneHeaderDefault => 'Back to the default docked-in-header form';
	@override String get heatmapFourRowsHint => 'Four consecutive weeks · the outline marks the selected day · stronger colour means more activity';
	@override String get weekdaySun => 'Sun';
	@override String get weekdaySat => 'Sat';
	@override String get weekdayFri => 'Fri';
	@override String get weekdayThu => 'Thu';
	@override String get weekdayWed => 'Wed';
	@override String get weekdayTue => 'Tue';
	@override String get weekdayMon => 'Mon';
	@override String get presenter => 'Presenter';
	@override String get includeSubdirStats => 'Include subfolder stats';
	@override String get includeSubdirs => 'Include subfolders';
	@override String get recursiveSearchHint => 'Searches downward recursively; the depth cap is clamped on the Rust side';
	@override String get back => 'Back';
	@override String get searchSyntaxHint => 'Name and path · space-separated · -exclude · "phrases"';
	@override String get nameLabel => 'Name';
	@override String get undoable => 'Can be undone';
	@override String get onlyThisPanelDetailsBelow => 'Applies to this panel only. The cover\'s details button always expands downward.';
	@override String get onlyFittingWidgetsRepeat => 'Inserts only the summary widgets that fit the gap; the same one may repeat.';
	@override String get mergeOnlyHistoryDetail => 'Merge only: no history entry is deleted; where local progress is newer than the file, local wins.';
	@override String get mergeOnlyHistory => 'Merges only — existing records are never deleted or overwritten.';
	@override String get mergeOnlyBookmarks => 'Merges only — existing bookmarks are never deleted or overwritten.';
	@override String get changesLabel => 'Changes';
	@override String get discoverToolsEn => 'Tools';
	@override String get switchToWorkholeEn => 'Workhole';
	@override String get switchToSwimlaneEn => 'Swimlane';
	@override String get closeSidebarEn => 'Close';
	@override String get closeCurrentComicFull => 'Close the current comic (back to empty)';
	@override String get closeCurrentComicPlain => 'Close the current comic (back to empty)';
	@override String get favoritesEn => 'Favourites';
	@override String get bookshelfEn => 'Bookshelf';
	@override String get downloadsOfflineEn => 'Downloads';
	@override String get topEntriesStillWork => 'The three entries above still work: install a source and each one shows here';
	@override String get widgetsPlusShapes => 'Widgets + shapes';
	@override String get miniWidgets => 'Widgets';
	@override String get randomShapes => 'Random shapes';
	@override String get openDetailsPage => 'Open the details page';
	@override String get expandDetailsBelow => 'Expand details below';
	@override String get weightBalanced => 'Balanced';
	@override String get readingStatus => 'Reading status';
	@override String get recentlyUsed => 'Recently used';
	@override String get followSort => 'Follow the sort';
	@override String get yesterday => 'Yesterday';
	@override String get cancelPathEdit => 'Cancel path editing';
	@override String get unpin => 'Unpin';
	@override String get discoverTools => 'Discover and tools';
	@override String get doubleTapResetLaneWidth => 'Double-tap resets this column\'s width · right-click opens the lane menu';
	@override String get installOrImportPlugin => 'Install a source from the plugin market, or import a local plugin package';
	@override String get originalRatio => 'Original ratio';
	@override String get historyFile => 'History file';
	@override String get historyData => 'History data';
	@override String get volume => 'Volume';
	@override String get cardHeight => 'Card height';
	@override String get cardSpacing => 'Card spacing';
	@override String get cardLayout => 'Card layout';
	@override String get cardWidth => 'Card width';
	@override String get cardPosition => 'Card position';
	@override String get occupiedSize => 'Occupied size';
	@override String get matchPath => 'Match path';
	@override String get loadingState => 'Loading';
	@override String get cut => 'Cut';
	@override String get forward => 'Forward';
	@override String get last7DaysRecords => 'Last 7 days';
	@override String get refreshCurrentFolder => 'Refresh the current folder';
	@override String get toastOnLastPage => 'Show a toast on the last page';
	@override String get reachedLastPage => 'That\'s the end — no more pages';
	@override String get deleteQuestion => 'Delete?';
	@override String get creating => 'Creating';
	@override String get create => 'Create';
	@override String get creator => 'Creator';
	@override String get listName => 'List name';
	@override String get toastOnPageSwitch => 'Show a toast when switching pages';
	@override String get switchToastTest => 'Switch toast test';
	@override String get switchToast => 'Switch toast';
	@override String get toastOnBookSwitch => 'Show a toast when switching books';
	@override String get switchToWorkhole => 'Switch to the immersive workhole';
	@override String get switchToSwimlane => 'Switch to multi-column lanes';
	@override String get switchDescending => 'Switch to descending';
	@override String get switchAscending => 'Switch to ascending';
	@override String get bookSwitchToast => 'Book-switch toast';
	@override String get internalThumbnails => 'Internal thumbnails';
	@override String get builtin => 'Built-in';
	@override String get moreContentMoreArea => 'More content means a larger share of the area.';
	@override String get contentCount => 'Content count';
	@override String get contentSections => 'Content sections';
	@override String get otherMedia => 'Other media';
	@override String get closeTab => 'Close tab';
	@override String get closeSidebar => 'Close sidebar';
	@override String get closePassthroughMode => 'Turn off passthrough mode';
	@override String get closeCurrentComic => 'Close the current comic (back to empty)';
	@override String get closeWorkhole => 'Close the workhole';
	@override String get closeTabsLeft => 'Close tabs to the left';
	@override String get closeTabsRight => 'Close tabs to the right';
	@override String get closeOtherTabs => 'Close other tabs';
	@override String get turnedOff => 'Off';
	@override String get manageAll => 'Manage all';
	@override String get allHealthy => 'All healthy';
	@override String get allImageSources => 'All image sources';
	@override String get closeAllTabs => 'Close all';
	@override String get fullWidth => 'Full width';
	@override String get allowLeaveLane => 'Allow dragging out of the lane';
	@override String get pixelSize => 'Pixel size';
	@override String get serendipity => 'Serendipity';
	@override String get favouriteTagWeight => 'Favourite tag weight';
	@override String get favouriteTags => 'Favourite tags';
	@override String get modifiedTime => 'Modified time';
	@override String get modifiedDate => 'Modified date';
	@override String get modify => 'Modify';
	@override String get egBookPath => 'e.g. Path: {{book.path}}';
	@override String get egPageIndex => 'e.g. Page {{page.indexDisplay}}';
	@override String get egLastPage => 'e.g. This is the last page';
	@override String get egSwitchedToBook => 'e.g. Switched to {{book.displayName}}';
	@override String get egPageName => 'e.g. {{page.name}}';
	@override String get sizeVolume => 'Size';
	@override String get toastStyleInSettings => 'Position and look are set under Settings → Toast style.';
	@override String get emphasiseTopSorted => 'Emphasises whatever sorts to the top.';
	@override String get anyToken => 'Any token';
	@override String get collapseFromPanel => 'Collapse from this panel';
	@override String get newFromThisTab => 'New from this tab';
	@override String get pickComicFolderFromDisk => 'Choose a comic folder on disk';
	@override String get importFromJson => 'Import from JSON';
	@override String get today => 'Today';
	@override String get desktopOnly => 'Desktop only';
	@override String get bookPathLocalOnly => 'Book path (only set for local sources)';
	@override String get bookTitleTemplate => 'Book title template';
	@override String get bookDisplayName => 'Book display name';
	@override String get bookToastTemplate => 'Book toast template';
	@override String get bookDescriptionTemplate => 'Book description template';
	@override String get bookInformation => 'Book information';
	@override String get bookmarkFile => 'Bookmark file';
	@override String get bookmarkData => 'Bookmark data';
	@override String get bookmarks => 'Bookmarks';
	@override String get bookshelfUpstream => 'Bookshelf (upstream original)';
	@override String get bookshelfAggregateCard => 'Bookshelf aggregate card';
	@override String get shelfFavoriteFiles => 'Shelf · Favourites · Files';
	@override String get bookshelfTab => 'Bookshelf';
	@override String get bookTitle => 'Book title';
	@override String get homeNotSetYet => 'Home: not set · tap to make the current folder the home';
	@override String get homeCurrentManageHint => 'Home (current) · right-click or long-press to manage';
	@override String get homeSetTo => 'Home set to';
	@override String get homeManageHint => 'Home · right-click or long-press to manage';
	@override String get heroVisual => 'Hero visual';
	@override String get mainOccupancy => 'Main occupancy';
	@override String get temporarySort => 'Temporary sort (not remembered for this folder)';
	@override String get abortRecursiveSearch => 'Stop the recursive search (keep results already found)';
	@override String get samePathAsHeaderDoubleClick => 'Same path as double-tapping the lane header';
	@override String get samePathAsBackKey => 'Same path as Esc and the system back key';
	@override String get keepGapIrregularOutline => 'Keeps blank space between irregular outlines.';
	@override String get notAnObject => 'Not an object';
	@override String get asymmetric => 'Asymmetric';
	@override String get noFill => 'Do not fill';
	@override String get downloadTaskList => 'Download task list';
	@override String get downloadsOffline => 'Downloads and offline';
	@override String get bothWeeksNoRecord => 'Neither week has records';
	@override String get earlyAfternoon => 'Early afternoon';
	@override String get noon => 'Noon';
	@override String get earlyMorning => 'Early morning';
	@override String get afternoon => 'Afternoon';
	@override String get morning => 'Morning';
	@override String get parentDirectory => 'Up one level';
	@override String get prevWindowNoRecord => 'No records in the previous window';
	@override String get nextSegment => 'Next segment';
	@override String get prevSegment => 'Previous segment';
	@override String get noCreationTimeField => 'dart:io has no creation time, so only the fields that report back are shown';
	@override String get rustMemoryPollHint => 'Rust memory is only read when expanded; collapsed stops polling';
	@override String get rustMemory => 'Rust memory';
	@override String get gpuZeroCopyEngine => 'Zero-copy GPU engine';
	@override String get gpuLinking => 'Building the GPU link';
	@override String get gpuReady => 'GPU ready';
	@override String get gpuSharedTexture => 'GPU shared texture';
	@override String get cpuDecodeFallback => 'CPU decode fallback';
	@override String get cpuDecodePreload => 'CPU decode / image cache preloading';
	@override String get compressedArchive => 'Compressed archive';
	@override String get archiveZip => 'ZIP archive';
	@override String get archiveTar => 'TAR archive';
	@override String get archiveRar => 'RAR archive';
	@override String get archiveCbz => 'CBZ archive';
	@override String get archiveCbr => 'CBR archive';
	@override String get archive7z => '7Z archive';
	@override String get last12Weeks => 'Last 12 weeks';
	@override String get recentReading => 'Reading recently';
	@override String get downloadedLabel => 'Downloaded';
	@override String get bookUnit => 'books';
	@override String get todayLabel => 'today';
	@override String get yesterdayLabel => 'yesterday';
	@override String daysAgoLabel({required Object n}) => '${n} days ago';
	@override String get readingTools => 'Reading tools';
	@override String get filesBrowseSubtitle => 'Browse, search and organize local files';
	@override String get openFilesAction => 'Open';
	@override String get noMoreHistory => 'No earlier records';
	@override String get continueNextHint => 'Pick up where you left off';
	@override String get openAll => 'All';
	@override String get toolsStandaloneHint => 'Synced with reading settings';
}

// Path: common
class _Translations$common$en_US extends Translations$common$zh_CN {
	_Translations$common$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get nameNoSlash => 'The name can\'t contain / or \\';
	@override String startupStage({required Object stage}) => 'Stage: ${stage}';
	@override String get appStartupFailed => 'The app failed to start';
	@override String get openLocalComicRossi => 'Open a local comic (Rossi\'s own reader + zero-copy GPU)';
	@override String get neoViewWorkspace => 'NeoView workspace';
	@override String get openWithRossi => 'Open with Rossi';
	@override String get showInExplorer => 'Show in Explorer';
	@override String get showInFinder => 'Show in Finder';
	@override String get showInFileManager => 'Show in file manager';
	@override String get revealInFileManagerFolder => 'Open the containing folder in the file manager';
	@override String get deleteListLabel => 'Delete list';
	@override String get pleaseEnterName => 'Please enter a name';
	@override String get ok => 'OK';
	@override String get cancel => 'Cancel';
	@override String get save => 'Save';
	@override String get delete => 'Delete';
	@override String get edit => 'Edit';
	@override String get rename => 'Rename';
	@override String get add => 'Add';
	@override String get create => 'Create';
	@override String get refresh => 'Refresh';
	@override String get loading => 'Loading...';
	@override String get loadingFailed => 'Loading failed';
	@override String get retry => 'Retry';
	@override String get reload => 'Reload';
	@override String get confirm => 'Confirm';
	@override String get close => 'Close';
	@override String get back => 'Back';
	@override String get help => 'Help';
	@override String get gotIt => 'Got it';
	@override String get underConstruction => 'Under construction';
	@override String get comingSoon => 'Coming soon';
	@override String get root => 'Root';
	@override String get remove => 'Remove';
	@override String get overwrite => 'Overwrite';
	@override String get cancelled => 'Cancelled';
	@override String get search => 'Search';
	@override String get clear => 'Clear';
	@override String get copy => 'Copy';
	@override String get paste => 'Paste';
	@override String get share => 'Share';
	@override String get open => 'Open';
	@override String get download => 'Download';
	@override String get upload => 'Upload';
	@override String get import => 'Import';
	@override String get export => 'Export';
	@override String get success => 'Success';
	@override String get failed => 'Failed';
	@override String get error => 'Error';
	@override String get warning => 'Warning';
	@override String get info => 'Info';
	@override String get unknown => 'Unknown';
	@override String get empty => 'No data';
	@override String get all => 'All';
	@override String get none => 'None';
	@override String get default_ => 'Default';
	@override String get custom => 'Custom';
	@override String get enabled => 'Enabled';
	@override String get disabled => 'Disabled';
	@override String get followSystem => 'Follow system';
	@override String get lightMode => 'Light mode';
	@override String get darkMode => 'Dark mode';
	@override String get system => 'System';
	@override String get apply => 'Apply';
	@override String get reset => 'Reset';
	@override String get next => 'Next';
	@override String get previous => 'Previous';
	@override String get done => 'Done';
	@override String get select => 'Select';
	@override String get selected => 'Selected';
	@override String get deselect => 'Deselect';
	@override String get selectAll => 'Select all';
	@override String get yes => 'Yes';
	@override String get no => 'No';
	@override String get on => 'On';
	@override String get off => 'Off';
	@override String get more => 'More';
	@override String get detail => 'Details';
	@override String get settingSaved => 'Settings saved';
	@override String get restartToTakeEffect => 'Setting saved, restart to take effect';
}

// Path: error
class _Translations$error$en_US extends Translations$error$zh_CN {
	_Translations$error$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get generic => 'Something went wrong';
	@override String get network => 'Network error';
	@override String get downloadFailed => 'Download failed';
	@override String importFailed({required Object error}) => 'Import failed: ${error}';
	@override String get loadFailed => 'Loading failed';
	@override String get saveFailed => 'Save failed';
	@override String get permissionDenied => 'Permission denied';
	@override String get notFound => 'Not found';
	@override String get unsupportedPlatform => 'This feature is not supported on the current platform';
	@override String missingPluginSource({required Object action}) => 'Missing plugin source, cannot ${action}';
	@override String get operationFailed => 'Operation failed';
	@override String get executionFailed => 'Execution failed';
}

// Path: navigation
class _Translations$navigation$en_US extends Translations$navigation$zh_CN {
	_Translations$navigation$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get home => 'Home';
	@override String get rank => 'Rank';
	@override String get bookshelf => 'Bookshelf';
	@override String get discover => 'Discover';
	@override String get more => 'More';
	@override String get syncSuccess => 'Synced successfully!';
	@override String get autoSyncSuccess => 'Auto sync successful!';
	@override String get syncFailed => 'Sync failed';
	@override String get autoSyncFailed => 'Auto sync failed';
	@override String syncFailedMessage({required Object error}) => 'Please check your network connection or try again later.\n${error}';
	@override String get loginExpired => 'Login expired, please log in again';
	@override String get needLoginTitle => 'Login required';
	@override String get goLogin => 'Log in';
	@override String get sidebarCollapse => 'Collapse sidebar';
	@override String get sidebarExpand => 'Expand sidebar';
	@override String get navigationChrome => 'Navigation';
	@override String get sidebarEnabled => 'Arc-style sidebar';
	@override String get sidebarEnabledSubtitle => 'Desktop and tablet navigate from a left sidebar; turn off for the previous rail';
	@override String get sidebarExpanded => 'Sidebar expanded';
	@override String get sidebarExpandedSubtitle => 'Expanded rows carry labels, collapsed ones only icons; the button at the top of the sidebar toggles it any time';
	@override String get dockEnabled => 'Floating dock';
	@override String get dockEnabledSubtitle => 'Narrow screens get a floating pill at the foot; turn off for the previous bottom bar';
	@override String get autoNarrowMobileLayout => 'Switch to the mobile layout when narrow';
	@override String get autoNarrowMobileLayoutSubtitle => 'Below the threshold, the sidebar gives way to the bottom dock (small desktop windows, split-screen tablets)';
	@override String get narrowNavigationWidth => 'Narrow-screen threshold';
	@override String get narrowNavigationWidthSubtitle => 'A window narrower than this many logical pixels counts as narrow';
	@override String narrowNavigationWidthReset({required Object value}) => 'Reset to default (${value})';
	@override String get moreActions => 'More actions';
	@override String get customize => 'Customize navigation';
	@override String get customizeTitle => 'Customize navigation';
	@override String get customizeHint => 'Drag to reorder each section, add or hide freely; the arrow on an action moves it between the main area and the bottom shortcuts';
	@override String get dockLongPressCustomize => 'Long-press dock to customize';
	@override String get dockLongPressCustomizeSubtitle => 'Hold any destination on the dock to open navigation customization';
	@override String get dockLongPressDuration => 'Long-press duration';
	@override String get dockLongPressDurationSubtitle => 'How long to hold before it triggers (too short clashes with switching pages)';
	@override String dockLongPressDurationReset({required Object value}) => 'Reset to default (${value})';
	@override String millisecondUnit({required Object value}) => '${value} ms';
	@override String get customizeMainSection => 'Main area';
	@override String get customizeActionsSection => 'Bottom shortcuts';
	@override String get customizeActionsHint => 'Shown at the sidebar foot, or in the dock\'s overflow menu — actions only';
	@override String get customizeDesktopTab => 'Desktop sidebar';
	@override String get customizeMobileTab => 'Mobile dock';
	@override String get customizeReset => 'Reset';
	@override String get customizeDone => 'Done';
	@override String get customizeAvailable => 'Available items';
	@override String get customizeHide => 'Hide';
	@override String get customizeActionTag => 'Action';
	@override String get customizeMoveToMain => 'Move to main area';
	@override String get customizeMoveToActions => 'Move to bottom shortcuts';
	@override String get workspace => 'Workspace';
	@override String get openLocalComic => 'Open local comic';
	@override String get gpuPresent => 'GPU present';
}

// Path: settings
class _Translations$settings$en_US extends Translations$settings$zh_CN {
	_Translations$settings$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get allLanePanelsHidden => 'Every panel in this lane is hidden —\nenable the ones you need under Global settings → Lane panel kanban.';
	@override String localTreeArchiveSize({required Object size}) => 'Comic archive · ${size}';
	@override String get localTreeOpenThisFolder => 'Open this folder directly';
	@override String get localTreeEmpty => 'No subfolders or comic files in this folder';
	@override String localTreeReadFailed({required Object error}) => 'Read failed: ${error}';
	@override String get localTreeOpenFolder => 'Open this folder';
	@override String get localTreeTitle => 'Local file tree (mImageViewer core)';
	@override String get debugNoRustDiagnostics => 'The native side returned no Rust diagnostics (the DLL and the bridge may be out of sync).';
	@override String get debugBrowse => 'Browse...';
	@override String get debugLocalSourceGroup => 'Local sources (loose folders / .cbz / .cbr)';
	@override String get debugRefreshStats => 'Refresh stats';
	@override String get tabSideRight => 'Vertical (right)';
	@override String get tabSideLeft => 'Vertical (left)';
	@override String get tabSideTop => 'Horizontal (top bar)';
	@override String get tabPolicyTriggering => 'Inherit the triggering tab';
	@override String get tabPolicyRecent => 'Inherit the most recently used tab';
	@override String get tabPolicyDefaults => 'Use preset defaults';
	@override String get dragToLaneEnd => 'Drag a panel here to append it';
	@override String get dropToLaneEnd => 'Release to append to this lane';
	@override String get moveToLeftLane => 'Move to left lane';
	@override String get moveToRightLane => 'Move to right lane';
	@override String kanbanRank({required Object n}) => 'Rank #${n}';
	@override String get kanbanShowPanel => 'Show this panel in the panel bar';
	@override String get kanbanHideCompletely => 'Hide from the panel bar (leaves no hidden icon)';
	@override String get kanbanReaderLaneDesc => 'This lane is reserved for the comic page you are reading. Use the lane-order bar above or the arrows at the top-right of this column to move the reader to the left, centre or right.';
	@override String get kanbanReaderCanvasTitle => 'Comic reader main canvas';
	@override String kanbanVisibleHidden({required Object visible, required Object hidden}) => '${visible} visible · ${hidden} hidden';
	@override String kanbanAllVisible({required Object count}) => '${count} panels (all visible)';
	@override String get kanbanReaderLaneTitle => 'Reader main-view lane';
	@override String kanbanLaneIndex({required Object n}) => 'Lane ${n}';
	@override String get kanbanLaneOrderTitle => 'Lane order (drag sideways or tap the arrows to move)';
	@override String kanbanHiddenPanels({required Object count}) => '${count} panels fully hidden';
	@override String kanbanVisiblePanels({required Object count}) => '${count} panels visible';
	@override String kanbanLaneOrder({required Object order}) => 'Lane order: ${order}';
	@override String get kanbanDragHint => 'Drag or use the buttons to reorder lanes, reorder the panels within each lane, and toggle visibility. Hidden panels are removed from the panel bar entirely, with no hidden icon left behind.';
	@override String get rightLane => 'Right lane';
	@override String get leftLane => 'Left lane';
	@override String get swimlanePanelKanbanConfigTitle => 'Lane panel kanban configuration';
	@override String get revealZonePointerHint => 'This device has no hover pointer: these reveal zones only work when the mouse hugs the edge. On touch, use the narrow rails on either side of the solo Reader to switch lanes.';
	@override String get laneCustomDelayMs => 'This lane · milliseconds';
	@override String inheritedGlobalDelay({required Object ms}) => 'Inherited from global: ${ms} ms';
	@override String get fmViewColumns => 'Columns view';
	@override String get fmViewTree => 'Tree view';
	@override String get fmViewContent => 'Content view';
	@override String get fmDefaultContentLayout => 'Default content layout';
	@override String get fmDefaultEntryStyle => 'Default entry style';
	@override String get fmTabPolicyHint => '“Recent” follows the active tab; “Triggering” follows the tab that started the action. Only browsing and search options are inherited — query, results, history and selection stay separate. With no source on first open, the preset is used.';
	@override String get fmTabPolicySource => 'Policy source';
	@override String get favoriteTagExampleHint => 'school_lolita | 学校萝莉 | School Lolita\nloli';
	@override String get noMatchingArtist => 'No matching artists';
	@override String get favoriteArtistExampleHint => 'Artist name\n[Circle name (artist)]\nAnother artist';
	@override String get confirmResetPin => 'Confirm reset PIN';
	@override String get defaultHoverDelaySubtitle => 'Used when a lane has no delay of its own';
	@override String get defaultHoverDelay => 'Default hover reveal delay';
	@override String get enterWorkspaceSubtitle => 'Opens with the presentation selected below; use the system back key to exit';
	@override String get enterWorkspace => 'Enter workspace';
	@override String get workspaceNarrowMobileHost => 'Mobile workspace in narrow windows';
	@override String get workspaceNarrowMobileHostSubtitle => 'On desktop, workspace entries below the navigation narrow-width threshold open the mobile workspace. Turn off to always use the desktop lanes.';
	@override String get kanbanLaneMoveRight => 'Move lane right';
	@override String get kanbanLaneMoveLeft => 'Move lane left';
	@override String get kanbanPanelMoveDown => 'Move panel down';
	@override String get kanbanPanelMoveUp => 'Move panel up';
	@override String get kanbanLaneDefaultHidden => 'Hidden by default';
	@override String get kanbanLanePinned => 'Pinned lane';
	@override String get kanbanFullyHidden => 'Fully hidden';
	@override String get kanbanVisible => 'Visible';
	@override String get kanbanRestoreDefault => 'Restore default layout';
	@override String get swimlanePanelKanbanDesc => 'Use the kanban to reorder lanes, order the panels on each lane, and show or fully hide them';
	@override String get laneHoverDelayInherit => 'Restore the inherited global delay';
	@override String get laneHoverDelay => 'Hover reveal delay';
	@override String get laneHoverRevealSubtitle => 'After dwelling, move the workspace so this lane shows in full';
	@override String get laneHoverReveal => 'Reveal in full on hover';
	@override String get laneKeyboardFollowsMouseSubtitle => 'Once the pointer enters this lane, hand keyboard control to it';
	@override String get laneKeyboardFollowsMouse => 'Keyboard target follows the pointer';
	@override String get laneInteraction => 'Lane interaction';
	@override String get swimlanePanelKanbanSubtitle => 'Lane order · per-lane panel order · show or fully hide panels';
	@override String get swimlanePanelKanban => 'Lane & panel kanban';
	@override String get fmNewTabPresetHint => 'Preset defaults apply only when “Use preset defaults” is on; the default recursive scope follows the search settings below. Duplicating a tab or restoring a closed one keeps its own settings.';
	@override String get fmNewTabShowInternal => 'Show internal entries by default';
	@override String get fmNewTabShowHidden => 'Show hidden items by default';
	@override String get fmNewTabPassthrough => 'Passthrough by default';
	@override String get fmNewTabStartup => 'New tab startup options';
	@override String get importFileTxtJsonEmm => 'Import file (TXT/JSON/EMM setting.json)';
	@override String get searchArtistHint => 'Search artists...';
	@override String get importFileTxtJson => 'Import file (TXT/JSON)';
	@override String get debugGpuPresentSubtitle => 'Rust decode → wgpu → GPU copy → shared texture, pixels never cross the bridge';
	@override String get debugGpuPresent => 'GPU present (D3D12 shared texture)';
	@override String get debugOcrSmokeSubtitle => 'Pick a page → detect / recognise / erase / translate / refill, with per-stage timing and outputs';
	@override String get debugOcrSmoke => 'OCR finished-page smoke test';
	@override String get debugLocalSourceSubtitle => 'Direct read of loose-image folders / CBZ / CBR, with per-page timing and rejection categories';
	@override String get debugLocalSource => 'Local source reading (criterion A)';
	@override String get setResetPin => 'Set reset PIN';
	@override String get overviewSubtitle => 'Make Rossi feel like yours';
	@override String get searchCategories => 'Search settings categories';
	@override String get noMatchingCategories => 'No matching categories. Try another keyword.';
	@override String get personalizationGroup => 'Appearance & feedback';
	@override String get readingGroup => 'Reading & image';
	@override String get libraryGroup => 'Files, library & data';
	@override String get applicationGroup => 'App & controls';
	@override String get windowGroup => 'Window';
	@override String get syncDestinationsSubtitle => 'Sync service · Cloud backup';
	@override String get title => 'Settings';
	@override String get globalTitle => 'Settings';
	@override String get appearance => 'Appearance';
	@override String get theme => 'Theme mode';
	@override String get themeSubtitle => 'Choose strategy to switch light/dark theme';
	@override String get themeColor => 'Theme color';
	@override String get tweakcnTitle => 'Import Tweakcn theme';
	@override String get tweakcnSubtitle => 'Paste the CSS variables copied from tweakcn, or a shadcn registry JSON';
	@override String get tweakcnHint => ':root {\n  --background: oklch(1 0 0);\n  --primary: oklch(0.628 0.258 29.2);\n}';
	@override String get tweakcnImport => 'Import';
	@override String get tweakcnNameField => 'Theme name (optional)';
	@override String get tweakcnPickHint => 'Tap a row to make it current';
	@override String tweakcnEntryMeta({required Object count, required Object radius}) => '${count} tokens · radius ${radius}';
	@override String get tweakcnDelete => 'Delete this theme';
	@override String get tweakcnEnabled => 'Use the imported theme';
	@override String tweakcnApplied({required Object count, required Object radius}) => '${count} color tokens imported · radius ${radius}';
	@override String get tweakcnNoRadius => 'default';
	@override String get tweakcnFailedEmpty => 'Nothing to import';
	@override String get tweakcnFailedJson => 'Not recognizable JSON';
	@override String get tweakcnFailedNoColors => 'No color token could be parsed';
	@override String tweakcnSkipped({required Object keys}) => 'Skipped tokens with unreadable colors: ${keys}';
	@override String tweakcnFallbackRoles({required Object roles}) => 'Required tokens the theme omits, values substituted: ${roles}';
	@override String get themeColorSubtitle => 'Choose primary color for the app';
	@override String get language => 'Language';
	@override String get languageSubtitle => 'Change app display language';
	@override String get followSystemLanguage => 'Follow system';
	@override String get languageZhCn => '简体中文 (zh_CN)';
	@override String get languageEnUs => 'English (en_US)';
	@override String get languageChangedRestartHint => 'Language setting saved. Restart the app for changes to fully take effect.';
	@override String get dynamicColor => 'Dynamic color';
	@override String get dynamicColorSubtitle => 'Extract primary color from content automatically';
	@override String get fontSettings => 'Font settings';
	@override String get fontSettingsSubtitle => 'Customize display font';
	@override String get amoled => 'AMOLED black';
	@override String get amoledSubtitle => 'Use pure black background for AMOLED screens';
	@override String get notchAdaptation => 'Notch adaptation';
	@override String get notchAdaptationSubtitle => 'Reserve safe area to avoid content being obscured';
	@override String get transparentDesktopTitleBar => 'Transparent title bar';
	@override String get transparentDesktopTitleBarSubtitle => 'The title bar no longer paints a background and blends into the page (text and window buttons may be hard to read on light content). Desktop only';
	@override String get transparentTitleBarRow => 'Separate row';
	@override String get transparentTitleBarRowSubtitle => 'The bar keeps its own row with no background; content starts below it (default)';
	@override String get transparentTitleBarOverlay => 'Fused overlay';
	@override String get transparentTitleBarOverlaySubtitle => 'Content extends to the window top and the bar floats over it';
	@override String get toastStyle => 'Toast style';
	@override String get toastStyleSubtitle => 'Position, duration and size of in-app toasts';
	@override String get toastSectionLayout => 'Position & size';
	@override String get toastSectionAppearance => 'Appearance & behavior';
	@override String get toastSectionBehavior => 'Duration & motion';
	@override String get toastSectionStyle => 'Visuals';
	@override String get toastPosition => 'Position';
	@override String get toastPositionSubtitle => 'Which corner the toast sticks to';
	@override String get toastPositionTopLeft => 'Top left';
	@override String get toastPositionTopCenter => 'Top center';
	@override String get toastPositionTopRight => 'Top right';
	@override String get toastPositionMiddleLeft => 'Middle left';
	@override String get toastPositionCenter => 'Center';
	@override String get toastPositionMiddleRight => 'Middle right';
	@override String get toastPositionBottomLeft => 'Bottom left';
	@override String get toastPositionBottomCenter => 'Bottom center';
	@override String get toastPositionBottomRight => 'Bottom right';
	@override String get toastEdgePadding => 'Edge padding';
	@override String get toastEdgePaddingSubtitle => 'Distance between the toast and the screen edge';
	@override String get toastMaxWidth => 'Max width';
	@override String get toastMaxWidthSubtitle => 'Width limit of the toast; narrow screens clamp it further';
	@override String get toastMaxVisible => 'Visible at once';
	@override String get toastMaxVisibleSubtitle => 'How many toasts stack on screen; extra ones push out the oldest';
	@override String get toastDuration => 'Auto close';
	@override String get toastDurationSubtitle => 'Drag to the far left to keep it until closed manually';
	@override String get toastDurationPermanent => 'Persistent';
	@override String get toastOpacity => 'Opacity';
	@override String get toastOpacitySubtitle => 'Opacity of the whole toast, text included';
	@override String get toastAnimation => 'Enter/exit animation';
	@override String get toastAnimationSubtitle => 'Duration of the appear and disappear animation';
	@override String get toastLiquidGlass => 'Liquid glass';
	@override String get toastLiquidGlassSubtitle => 'Use a blurred translucent background for toasts';
	@override String get toastShowProgressBar => 'Show progress bar';
	@override String get toastShowProgressBarSubtitle => 'Show a thin line shrinking with the remaining time';
	@override String get toastShowIcon => 'Show type icon';
	@override String get toastShowIconSubtitle => 'Show a success/error icon on the left of the toast';
	@override String get toastShowCloseButton => 'Show close button';
	@override String get toastShowCloseButtonSubtitle => 'Persistent toasts always keep the close button';
	@override String get toastPreview => 'Show a test toast';
	@override String get toastPreviewTitle => 'Toast style preview';
	@override String get toastPreviewLongMessage => 'This is a preview toast: long text wraps automatically instead of being truncated or turned into a dialog.';
	@override String get toastReset => 'Reset toast style';
	@override String get toastResetDone => 'Toast style restored to defaults';
	@override String get contentAndNetwork => 'Content & Network';
	@override String get content => 'Content';
	@override String get fullSourceList => 'Full source list';
	@override String get fullSourceListSubtitle => 'When off, some sources are hidden from Discover, search and the plugin store. Turn on to show all sources';
	@override String get network => 'Network';
	@override String get maskedKeywords => 'Masked keywords';
	@override String get maskedKeywordsSubtitle => 'Add keywords to filter unwanted content (search only)';
	@override String get maskedKeywordsEmpty => 'No masked keywords';
	@override String get maskedKeywordsInputHint => 'Enter new keyword...';
	@override String get favoriteArtistHighlight => 'Highlight Favorite Artists';
	@override String get favoriteArtistHighlightSubtitle => 'Highlight comics by preferred artists on cards and detail page';
	@override String get cardBadges => 'Card Badges';
	@override String get cardDownloadBadge => 'Download Badge';
	@override String get cardDownloadBadgeSubtitle => 'Show a download button on the top-right of covers; tap it to download the whole comic';
	@override String get cardTranslationBadge => 'Language Badge';
	@override String get cardTranslationBadgeSubtitle => 'Detect translated / Chinese / raw from tags and mark the top-left of covers';
	@override String get cardReadButton => 'Read Button';
	@override String get cardReadButtonSubtitle => 'Show a read button in the middle of covers; tap it to start reading right away (resumes if there is progress) without opening the detail page';
	@override String get cardUnreadIndicator => 'Unread Indicator';
	@override String get cardUnreadIndicatorSubtitle => 'Mark comics you downloaded but never opened, under the download badge on covers';
	@override String get cardUnreadIndicatorStyle => 'Unread Indicator Style';
	@override String get cardUnreadIndicatorStyleSubtitle => 'Each step is easier to spot and covers more of the artwork';
	@override String get cardUnreadIndicatorStyleDot => 'Dot';
	@override String get cardUnreadIndicatorStyleDisc => 'Disc';
	@override String get cardUnreadIndicatorStyleLabel => 'Label';
	@override String get cardInteraction => 'Card Interaction';
	@override String get shelfCardContextMenu => 'Context Menu on Favorite / History Cards';
	@override String get shelfCardContextMenuSubtitle => 'Right-click an entry (long-press on touch) for open, open in a new file manager tab, copy, favorite and remove';
	@override String get favoriteArtistManagement => 'Favorite Artists Management';
	@override String favoriteArtistManagementSubtitle({required Object count}) => '${count} artists added';
	@override String get favoriteArtistManagementSubtitleEmpty => 'No favorite artists added';
	@override String get favoriteArtistInputHint => 'Enter artist name...';
	@override String get favoriteArtistAdd => 'Add';
	@override String get favoriteArtistBatchImport => 'Batch Import / Edit';
	@override String get favoriteArtistBatchImportHint => 'One artist per line or comma-separated; [circle (artist)] entries are kept verbatim and both names take part in matching';
	@override String favoriteArtistImportSuccess({required Object count}) => 'Updated artists list (${count} total)';
	@override String get favoriteArtistClear => 'Clear All';
	@override String get favoriteArtistClearConfirm => 'Are you sure you want to clear all favorite artists?';
	@override String get favoriteArtistCircleMode => 'Circle Name Matching';
	@override String get favoriteArtistCircleModeSubtitle => 'Whether a circle name in the title or tags counts as a hit';
	@override String get favoriteArtistCircleOff => 'Ignore circles';
	@override String get favoriteArtistCircleFallback => 'Only without artist';
	@override String get favoriteArtistCircleIndependent => 'Independent (artist first)';
	@override String get favoriteArtistBadge => 'Favorite Artist';
	@override String get addToFavoriteArtist => 'Add to Favorite Artists';
	@override String get removeFromFavoriteArtist => 'Remove from Favorite Artists';
	@override String addedToFavoriteArtist({required Object name}) => 'Added to favorite artists: ${name}';
	@override String removedFromFavoriteArtist({required Object name}) => 'Removed from favorite artists: ${name}';
	@override String get favoriteTagHighlight => 'Highlight Favorite Tags';
	@override String get favoriteTagHighlightSubtitle => 'Mark favorite tags prominently on comic cards and the detail page';
	@override String get favoriteTagManagement => 'Favorite Tags Management';
	@override String favoriteTagManagementSubtitle({required Object count}) => '${count} tags added';
	@override String get favoriteTagManagementSubtitleEmpty => 'No favorite tags added';
	@override String get favoriteTagInputHint => 'Enter tag name...';
	@override String get favoriteTagAdd => 'Favorite';
	@override String get favoriteTagSearchHint => 'Search tags...';
	@override String get favoriteTagNotFound => 'No matching tags';
	@override String get favoriteTagBatchImport => 'Batch Import / Edit';
	@override String get favoriteTagBatchImportHint => 'One tag per line; separate aliases with | to match how each site spells it, e.g. school_lolita | 学校萝莉 | School Lolita';
	@override String favoriteTagImportSuccess({required Object count}) => 'Updated favorite tags (${count} total)';
	@override String get favoriteTagClear => 'Clear All';
	@override String get favoriteTagClearConfirm => 'Are you sure you want to clear all favorite tags?';
	@override String get favoriteTagBadge => 'Favorite Tag';
	@override String get favoriteTagAliasSection => 'Aliases';
	@override String get favoriteTagAliasEmpty => 'No aliases set';
	@override String get favoriteTagAliasAdd => 'Add alias';
	@override String get favoriteTagAliasInputHint => 'How this tag is written on some site...';
	@override String get favoriteTagAliasHint => 'Aliases cover the different spellings each source uses for one tag. Case, full-width/half-width and underscore vs space are normalized automatically, so no alias is needed for those.';
	@override String favoriteTagAdded({required Object name}) => 'Favorited tag: ${name}';
	@override String favoriteTagRemoved({required Object name}) => 'Removed favorite tag: ${name}';
	@override String favoriteTagAlreadyAdded({required Object name}) => 'Already favorited: ${name}';
	@override String favoriteTagAliasAdded({required Object name}) => 'Alias added: ${name}';
	@override String favoriteTagAliasRemoved({required Object name}) => 'Alias removed: ${name}';
	@override String get favoriteTagAliasDuplicate => 'This alias already exists';
	@override String get addToFavoriteTag => 'Favorite this tag';
	@override String get removeFromFavoriteTag => 'Unfavorite this tag';
	@override String get cardFavoriteTagBadge => 'Favorite Tag Badge';
	@override String get cardFavoriteTagBadgeSubtitle => 'Show a badge on the top-left of covers that match a favorite tag';
	@override String get chineseConvert => 'Chinese conversion';
	@override String get chineseConvertSubtitle => 'Convert comic titles, descriptions, chapters and comments';
	@override String get chineseConvertOff => 'Off';
	@override String get chineseConvertSimplified => 'Simplified Chinese';
	@override String get chineseConvertTraditional => 'Traditional Chinese';
	@override String get proxy => 'Proxy';
	@override String get proxySubtitle => 'Configure proxy address';
	@override String get proxyEnabledSubtitle => 'Route network requests through a proxy when enabled';
	@override String get proxyAddress => 'Proxy address';
	@override String get proxyHint => 'Enter proxy address (HTTP / SOCKS5)';
	@override String proxyCurrent({required Object currentProxy}) => 'Current proxy: ${currentProxy}';
	@override String get proxyType => 'Proxy type';
	@override String get proxyTypeSubtitle => 'Choose proxy protocol';
	@override String get proxyTypeHttp => 'HTTP';
	@override String get proxyTypeSocks5 => 'SOCKS5';
	@override String get updateAccelerate => 'Update acceleration';
	@override String get updateAccelerateSubtitle => 'Use proxy to accelerate GitHub update links';
	@override String get retryDownloadUntilSuccess => 'Keep retrying failed downloads';
	@override String get retryDownloadUntilSuccessSubtitle => 'Retry failed downloads until they succeed; stop on 404 or empty data';
	@override String get downloadSettings => 'Download Settings';
	@override String get downloadConcurrency => 'Download Concurrency';
	@override String get downloadConcurrencySubtitle => 'Number of concurrent image download threads; reduce if facing rate limits or captcha';
	@override String get downloadTaskConcurrency => 'Concurrent Chapter Downloads';
	@override String get downloadTaskConcurrencySubtitle => 'How many chapters download at the same time; 1 = one by one. Lower it when hitting rate limits or captchas';
	@override String get downloadDelay => 'Image Request Delay';
	@override String get downloadDelaySubtitle => 'Pacing delay between image requests to prevent rate limiting (429)';
	@override String get downloadAutoRetryCount => 'Auto Retry Count';
	@override String get downloadAutoRetryCountSubtitle => 'Max automatic retry attempts when encountering transient network errors';
	@override String get sync => 'Sync';
	@override String get syncConfig => 'Sync config';
	@override String get syncConfigSubtitle => 'Enter page to configure address and auth';
	@override String get syncService => 'Sync service';
	@override String get syncServiceSubtitle => 'Choose service to manage sync strategy';
	@override String get syncServiceNone => 'Disabled';
	@override String get syncServiceWebdav => 'WebDAV';
	@override String get syncServiceS3 => 'S3';
	@override String get autoSync => 'Auto sync';
	@override String get autoSyncSubtitle => 'Sync configuration periodically in background';
	@override String get notifyPersonalize => 'Toast preferences';
	@override String get notifyPersonalizeSubtitle => 'Decide which background toasts may interrupt you; responses to your own actions always show';
	@override String get notifySummaryMasterOff => 'Background toasts are muted';
	@override String get notifySummaryAllOn => 'Every background toast rings';
	@override String notifySummaryOffCount({required Object count}) => '${count} silenced';
	@override String get notifySectionAmbient => 'Background toasts';
	@override String get notifyMaster => 'Background toasts';
	@override String get notifyMasterHint => 'Master switch. Turning it off silences everything below; button feedback is unaffected';
	@override String get notifyMasterOffNote => 'Master switch is off: the values below are kept, but nothing rings right now.';
	@override String get notifySectionOutside => 'Not covered by this table';
	@override String get notifySystemChannelNote => 'System tray notifications (download finished, new chapters) are managed by the OS — turn them off in system settings, not here';
	@override String notifyMergedSuffix({required Object count}) => ' (+${count} more of this kind)';
	@override String get notifyTopicAction => 'Action feedback';
	@override String get notifyTopicActionHint => 'The reply after you tap something. Always shown, otherwise the button reads as broken';
	@override String get notifyTopicReaderSwitch => 'Reader switch toasts';
	@override String get notifyTopicReaderSwitchHint => 'Book / page / last-page switches live on the workspace\'s "Switch toast" card';
	@override String get notifyTopicSyncAutoSuccess => 'Auto sync succeeded';
	@override String get notifyTopicSyncAutoSuccessHint => 'The periodic sync every 5 minutes; identical text is merged within 10 minutes';
	@override String get notifyTopicSyncAutoFailure => 'Auto sync failed';
	@override String get notifyTopicSyncAutoFailureHint => 'Used to knock every 5 minutes with no way to silence it; now one merged toast per 10 minutes';
	@override String get notifyTopicDownloadComplete => 'Download finished';
	@override String get notifyTopicDownloadCompleteHint => 'Once per comic; repeated callbacks for the same one merge within 60 seconds';
	@override String get notifyTopicDownloadFailed => 'Download failed';
	@override String get notifyTopicDownloadFailedHint => 'Different error texts count as different events and never merge';
	@override String get notifyTopicFollowUpdate => 'New chapters (follow list)';
	@override String get notifyTopicFollowUpdateHint => 'The automatic check after launch; manual refresh counts as action feedback and is never silenced';
	@override String get notifyTopicPluginMessage => 'Plugin script messages';
	@override String get notifyTopicPluginMessageHint => 'Toasts a source plugin raises itself; scripts can loop, so identical text merges within 3 seconds';
	@override String get notifyTopicIntentOpen => 'Opened from outside';
	@override String get notifyTopicIntentOpenHint => 'Where a system context-menu or link hand-off landed';
	@override String get notifyTopicSystemPermission => 'Notification permission';
	@override String get notifyTopicSystemPermissionHint => 'Shown when the startup request for OS notification permission was denied';
	@override String get syncSettings => 'Sync settings';
	@override String get syncSettingsSubtitle => 'Use cloud settings to override local settings';
	@override String get syncPlugins => 'Sync plugins';
	@override String get syncPluginsSubtitle => 'Sync plugin configuration and installation status';
	@override String get manualSyncSection => 'Manual sync';
	@override String get uploadToCloud => 'Upload to cloud';
	@override String get uploadToCloudSubtitle => 'Use local data as the source of truth and overwrite the cloud';
	@override String get downloadFromCloud => 'Download from cloud';
	@override String get downloadFromCloudSubtitle => 'Use cloud data as the source of truth and apply it locally';
	@override String get manualUpload => 'Upload now';
	@override String get manualDownload => 'Sync now';
	@override String get manualUploadSuccess => 'Uploaded to cloud';
	@override String get manualDownloadSuccess => 'Synced from cloud';
	@override String get manualSyncFailed => 'Manual sync failed';
	@override String get appBehavior => 'App behavior';
	@override String get splashPage => 'Startup page';
	@override String get splashPageSubtitle => 'Choose startup page to open directly';
	@override String get startWithWorkspace => 'Workspace';
	@override String get workspaceSleepCoveredUi => 'Sleep home pages while workspace is open';
	@override String get workspaceSleepCoveredUiSubtitle => 'Release image memory of covered lists; images reload when you return';
	@override String get panelTabRightClickHide => 'Hide Panel When Right-Clicking Its Icon';
	@override String get panelTabRightClickHideSubtitle => 'When off, the icons on a lane\'s panel bar only switch panels - right-click and long-press no longer hide one. Hiding is silent: the icon disappears from the bar and there is no restore entry there, so a mis-click means going back to the "Lanes & Panels" board to bring it back.';
	@override String get skipUpdateCheck => 'Skip update check';
	@override String get skipUpdateCheckSubtitle => 'This build is a fork: it won\'t query the upstream release on startup and won\'t show update prompts';
	@override String get desktopCloseBehavior => 'Close behavior';
	@override String get desktopCloseBehaviorSubtitle => 'Choose behavior when clicking close button';
	@override String get desktopCloseAsk => 'Ask';
	@override String get desktopCloseHide => 'Hide to tray';
	@override String get desktopCloseClose => 'Close directly';
	@override String get showMainWindow => 'Show main window';
	@override String get exitApp => 'Exit';
	@override String get appLock => 'App lock';
	@override String get appLockSubtitle => 'Require verification when entering the app';
	@override String get autoFollowOnCollect => 'Auto-follow on collect';
	@override String get autoFollowOnCollectSubtitle => 'Automatically add comics to the follow list when favorited';
	@override String get autoFavoriteOnDownload => 'Auto-favorite on download';
	@override String get autoFavoriteOnDownloadSubtitle => 'Automatically add comics to favorites when downloading';
	@override String get writeDownloadMetadataFile => 'Write metadata file on download';
	@override String get writeDownloadMetadataFileSubtitle => 'After a download finishes, write original_comic_info.json and processed_comic_info.json into the comic folder so other tools can read or re-import it';
	@override String get promptDownloadOptions => 'Prompt for download options';
	@override String get promptDownloadOptionsSubtitle => 'Show options (whole book / latest chapters / picker) when clicking download; when disabled, downloads all chapters directly';
	@override String get leftHandMode => 'Left-hand mode';
	@override String get leftHandModeSubtitle => 'Move floating action buttons and other controls to the left side';
	@override String get clickCoverToStartReading => 'Tap cover to start reading';
	@override String get clickCoverToStartReadingSubtitle => 'Tap the cover on the comic info page to start reading directly';
	@override String get searchHistoryGroupBySource => 'Split search history by plugin';
	@override String get searchHistoryGroupBySourceSubtitle => 'When on, every source gets its own search timeline instead of one mixed pile. "Aggregate search" holds cross-plugin queries; "Uncategorized" holds records saved before this feature, whose source is gone';
	@override String get comicInfoInlineReadButton => 'Read button in comic info page';
	@override String get comicInfoInlineReadButtonSubtitle => 'On desktop, put a read button next to Download in the action row and drop the floating read button at the bottom-right';
	@override String get comicInfoRailLiquidGlass => 'Liquid glass for the action rail';
	@override String get comicInfoRailLiquidGlassSubtitle => 'Render the floating capsules on the left and right of the comic info page with liquid glass; turn off for an opaque surface with an outline';
	@override String get androidKeepAlive => 'Keep alive';
	@override String get androidKeepAliveSubtitle => 'Use a foreground service to keep the app running in the background; shows a persistent notification';
	@override String get backPressExit => 'Exit on back';
	@override String get backPressExitSubtitle => 'When enabled, pressing back on the home page exits the app; when disabled, it only returns to the home page';
	@override String get bookshelf => 'Bookshelf';
	@override String get bookshelfSubtitle => 'Home tab & remember sort';
	@override String get bookshelfHomePage => 'Bookshelf home';
	@override String get bookshelfHomePageSubtitle => 'Choose the default tab';
	@override String get bookshelfRememberFavoriteSort => 'Remember favorite sort';
	@override String get bookshelfRememberFavoriteSortSubtitle => 'Remember the last sort choice for favorites';
	@override String get bookshelfRememberHistorySort => 'Remember history sort';
	@override String get bookshelfRememberHistorySortSubtitle => 'Remember the last sort choice for history';
	@override String get bookshelfRememberDownloadSort => 'Remember download sort';
	@override String get bookshelfRememberDownloadSortSubtitle => 'Remember the last sort choice for downloads';
	@override String get customExportPath => 'Custom export path';
	@override String get exportIncludeCover => 'Include cover image in export';
	@override String get exportIncludeCoverSubtitle => 'When on, the exported folder or zip also carries a cover image, fetched again at export time. Off by default: the artifact holds the pages plus the two info JSON files, and the cover is still shown online from the URL in that JSON';
	@override String get detailLayout => 'Detail layout';
	@override String get detailLayoutSubtitle => 'Show comic lists as horizontal detail rows with author and category info';
	@override String get reverseChapters => 'Reverse chapters';
	@override String get reverseChaptersSubtitle => 'Show chapters in reverse order by default on the detail page';
	@override String get storage => 'Storage';
	@override String get cache => 'Cache';
	@override String get clearCache => 'Clear cache';
	@override String get clearCacheConfirm => 'Are you sure you want to clear all cache files? This action cannot be undone.';
	@override String get calculatingCache => 'Calculating...';
	@override String get calculateCacheFailed => 'Calculate failed';
	@override String get dataBackup => 'Local Import/Export';
	@override String get dataBackupSubtitle => 'Transfer settings and data between mobile and desktop using ZIP; keep device-specific settings';
	@override String get includeDownloaded => 'Include downloaded comics';
	@override String get includeDownloadedSubtitle => 'Pack downloaded comic files when exporting';
	@override String get exportData => 'Export data';
	@override String get importData => 'Import data';
	@override String get imageProcessing => 'Image processing';
	@override String get realSr => 'Image Super-Resolution (Experimental)';
	@override String get ocr => 'Manga Translation (Finished Pages)';
	@override String get ocrSubtitle => 'Experimental; needs model download and a translation endpoint';
	@override String get realSrSubtitle => 'Experimental feature, may be unstable';
	@override String get eink => 'E-ink';
	@override String get einkSubtitle => 'Page-turn animation · full refresh · loading';
	@override String get einkPageTitle => 'E-ink adaptation';
	@override String get einkDetected => 'Detected as an e-ink device';
	@override String get einkNotDetected => 'No e-ink device detected, you can enable it manually';
	@override String get einkEnabled => 'Enable e-ink mode';
	@override String get einkEnabledSubtitle => 'Remove animations and refresh the whole screen periodically';
	@override String get einkSectionAnimation => 'Animation & transitions';
	@override String get einkNoRouteTransition => 'Remove page transition animation';
	@override String get einkNoRouteTransitionSubtitle => 'Show pages instantly instead of sliding and fading';
	@override String get einkNoScrollBounce => 'Remove scroll overscroll';
	@override String get einkNoScrollBounceSubtitle => 'Stop at the edge instead of bouncing in webtoon mode';
	@override String get einkSectionLoading => 'Loading';
	@override String get einkSectionRefresh => 'Refresh';
	@override String get einkRefreshMode => 'Full-screen refresh';
	@override String get einkRefreshNone => 'Disabled';
	@override String get einkRefreshWhite => 'White flash';
	@override String get einkRefreshFull => 'Black & white flash';
	@override String get einkRefreshHint => 'A full refresh flashes white or black-and-white to clear the ghost of the previous page.';
	@override String get einkRefreshNow => 'Refresh now';
	@override String get einkRefreshDone => 'Screen refreshed';
	@override String get einkAutoRefreshTurns => 'Auto refresh every N pages';
	@override String get einkAutoRefreshOff => 'Never';
	@override String get einkShowRefreshButton => 'Show refresh button';
	@override String get einkShowRefreshButtonSubtitle => 'Keep a manual full refresh in a reader corner';
	@override String get einkNoSpinner => 'No loading spinner';
	@override String get einkNoSpinnerSubtitle => 'A spinning indicator forces the panel to keep doing partial refreshes';
	@override String get autoRealSr => 'Auto super-resolution';
	@override String get resolutionThreshold => 'Resolution threshold';
	@override String get debug => 'Debug';
	@override String get logAddress => 'Log forward address';
	@override String get logAddressSubtitle => 'Forward logs to specified address in real time';
	@override String get memoryDebug => 'Memory debug';
	@override String get memoryDebugSubtitle => 'Show memory usage on interface';
	@override String get blockRustHttpRequests => 'Block Rust HTTP requests';
	@override String get blockRustHttpRequestsSubtitle => 'All Rust HTTP requests fail immediately without being sent';
	@override String get showLayoutOverflowStripes => 'Show layout overflow stripes';
	@override String get showLayoutOverflowStripesSubtitle => 'When off, the yellow-black stripes and the overflow error reports are suppressed for our own layouts. Flutter has no global switch: other widgets only lose the stripes in a profile build';
	@override String get forceEnableImpeller => 'Force enable Impeller';
	@override String get forceEnableImpellerSubtitle => 'Android experimental rendering backend';
	@override String get colorPreview => 'Color preview';
	@override String get colorPreviewSubtitle => 'Open color picker page for quick preview';
	@override String get qjsRuntimeDebug => 'QJS runtime debug';
	@override String get qjsRuntimeDebugSubtitle => 'Enter runtime ID to capture debug snapshot';
	@override String get qjsRuntimeSnapshot => 'Debug snapshot';
	@override String get qjsRuntimeIdLabel => 'Runtime ID';
	@override String get qjsRuntimeIdHint => 'e.g. 0a0e5858-a467-4702-994a-79e608a4589d';
	@override String get qjsRuntimeCapture => 'Capture snapshot';
	@override String get qjsRuntimeCapturing => 'Capturing...';
	@override String get qjsRuntimeCopyOutput => 'Copy output';
	@override String get qjsRuntimeNoOutput => 'No output yet';
	@override String get qjsRuntimeFillId => 'Please enter a runtime ID first';
	@override String qjsRuntimeCapturedAt({required Object dateTime}) => 'Captured at ${dateTime}';
	@override String qjsRuntimeCaptureFailed({required Object error}) => 'Capture failed: ${error}';
	@override String get qjsRuntimeNoCopyContent => 'No content to copy';
	@override String get qjsRuntimeCopied => 'Copied to clipboard';
	@override String get colorPreviewVariableFont => 'Variable Font test';
	@override String colorPreviewFontLoaded({required Object path}) => 'Loaded: ${path}';
	@override String get colorPreviewNoFont => 'No font loaded. Try the recommended sample or pick a TTF/OTF file.';
	@override String get colorPreviewLoadRecommended => 'Load recommended sample';
	@override String get colorPreviewSelectFont => 'Select font file';
	@override String get colorPreviewByWeight => 'Render by fontWeight';
	@override String get colorPreviewByVariableAxis => 'Render by variable axis';
	@override String get colorPreviewSystemDefault => 'System default font reference';
	@override String get colorPreviewLoadingFont => 'Loading font...';
	@override String get colorPreviewLoadSuccess => 'Font loaded. Compare different weights.';
	@override String colorPreviewLoadFailed({required Object error}) => 'Font load failed: ${error}';
	@override String get colorRed => 'Red';
	@override String get colorPink => 'Pink';
	@override String get colorPurple => 'Purple';
	@override String get colorDeepPurple => 'Deep purple';
	@override String get colorIndigo => 'Indigo';
	@override String get colorBlue => 'Blue';
	@override String get colorLightBlue => 'Light blue';
	@override String get colorCyan => 'Cyan';
	@override String get colorTeal => 'Teal';
	@override String get colorGreen => 'Green';
	@override String get colorLightGreen => 'Light green';
	@override String get colorLime => 'Lime';
	@override String get colorYellow => 'Yellow';
	@override String get colorAmber => 'Amber';
	@override String get colorOrange => 'Orange';
	@override String get colorDeepOrange => 'Deep orange';
	@override String get colorBrown => 'Brown';
	@override String get colorGrey => 'Grey';
	@override String get colorBlueGrey => 'Blue grey';
	@override String get colorMaskRed => 'Mask red';
	@override String get colorPresets => 'Preset colors';
	@override String get coremlDebug => 'CoreML upscale debug';
	@override String get coremlDebugSubtitle => 'Test CoreML upscale with absolute path model';
	@override String get aboutAndMore => 'About & More';
	@override String get changelog => 'Changelog';
	@override String get changelogSubtitle => 'View update records for each version';
	@override String get aboutApp => 'About app';
	@override String get aboutAppSubtitle => 'Detailed information about Rossi';
	@override String get pluginManagement => 'Plugin management';
	@override String get debugMode => 'Debug mode';
	@override String get debugAddress => 'Debug address';
	@override String get notSet => 'Not set';
	@override String get fileManager => 'File manager';
	@override String get fileManagerSubtitle => 'Home folder, toolbar and view memory for local browsing';
	@override String get fileManagerSectionHome => 'Home';
	@override String get fileManagerHomeEnabled => 'Enable home button';
	@override String get fileManagerHomeEnabledSubtitle => 'When off, the file manager toolbar hides the home button';
	@override String get fileManagerHomePath => 'Home folder';
	@override String get fileManagerHomePathSubtitle => 'Where the home button jumps to';
	@override String get fileManagerHomePathEmpty => 'Not set';
	@override String get fileManagerHomePathPick => 'Choose folder';
	@override String get fileManagerHomePathClear => 'Clear home';
	@override String get fileManagerHomePathCleared => 'Home cleared';
	@override String get fileManagerHomePathStale => 'That folder no longer exists, pick another one';
	@override String get fileManagerHomePathUnsupported => 'Choosing a folder is not supported on this platform';
	@override String get fileManagerOpenHomeOnStart => 'Open the home folder on start';
	@override String get fileManagerOpenHomeOnStartSubtitle => 'The file manager starts in the home folder. Falls back to the nearest folder that still exists when that path is gone';
	@override String get fileManagerSectionToolbar => 'Toolbar';
	@override String get breadcrumbStyle => 'Breadcrumb style';
	@override String get breadcrumbRestrained => 'Restrained';
	@override String get breadcrumbRestrainedHint => 'Rounded track and subtle emphasis for everyday browsing';
	@override String get breadcrumbExpressive => 'Expressive';
	@override String get breadcrumbExpressiveHint => 'Organic contours and shaped endpoints highlight the current folder';
	@override String get breadcrumbAncestors => 'Show parent folders';
	@override String get fileManagerSectionView => 'Browsing view';
	@override String get fileManagerRememberViewState => 'Remember view and sort per folder';
	@override String get fileManagerRememberViewStateSubtitle => 'Each folder keeps its own view mode, sort and filter. When off, browsing works as usual but nothing is remembered';
	@override String get fileManagerWrapGridTitle => 'Wrap file names in cover grid';
	@override String get fileManagerWrapGridTitleSubtitle => 'In the cover grid, file names wrap onto up to 6 lines. The tile keeps its height, so more lines squeeze the cover. When off, names are cut to 2 lines with an ellipsis. Either way, hovering anywhere on the tile reveals the full name';
	@override String get fileManagerSectionSearch => 'Search';
	@override String get fileManagerSearchSubfoldersDefault => 'Include subfolders by default';
	@override String get fileManagerSearchSubfoldersDefaultSubtitle => 'New tabs start with subfolder search switched on. A whole-library scan takes tens of seconds on a slow drive, so the default stays the current folder; turn this on to skip clicking the chip every time';
	@override String get fileManagerSectionTabs => 'Tabs';
	@override String get fileManagerRestoreTabs => 'Restore the tabs from last time';
	@override String get fileManagerRestoreTabsSubtitle => 'Puts last session\'s tabs back when the file manager opens. Only recorded from two tabs up, and only the folders - no back history, no search results. A folder that is gone falls back to the nearest parent that still exists. When the last session had two or more tabs, this wins over \'Open the home folder on start\'';
	@override String get fileManagerSectionFileOps => 'File operations';
	@override String get fileManagerFileOperations => 'Allow modifying files';
	@override String get fileManagerFileOperationsSubtitle => 'Copy, move, rename, create and delete. When off, the context menu, multi-select and the action bar all disappear and the file manager goes back to read-only';
	@override String get fileManagerHomePathSet => 'Home updated';
	@override String get shellIntegration => 'System integration';
	@override String get shellIntegrationContextMenu => 'Show “Open with Rossi” in the context menu';
	@override String get shellIntegrationContextMenuSubtitle => 'Writes to the current user\'s registry (HKCU), no administrator needed. The entry appears on files, on folders and on a folder\'s background. While Rossi is already running a new folder is not handed to it yet - open a second window instead.';
	@override String get shellIntegrationRegistered => 'Added to the context menu';
	@override String get shellIntegrationUnregistered => 'Removed from the context menu';
	@override String get shellIntegrationStalePath => 'The menu entry points at a different Rossi build; switch it off and on again to fix it';
	@override String get shellIntegrationRepair => 'Repair path';
	@override String get shellIntegrationMacHint => 'On macOS “Open With ‣ Rossi” comes from the document types the app bundle declares - always available, no switch. This toggle only affects Windows.';
	@override String openIntentMissing({required Object path}) => 'This path no longer exists: ${path}';
	@override String openIntentMultiSkipped({required Object count}) => 'Only the first item opens; ${count} others were skipped';
	@override String get operationBinding => 'Operation bindings';
	@override String get operationBindingEntrySubtitle => 'Keys, tap zones and binding bundles';
	@override String get operationBindingSubtitle => 'This table decides which action a key or a click triggers. Saving takes effect immediately, no restart needed.';
	@override String get operationBindingSectionSwitch => 'How bindings apply';
	@override String get operationBindingRuntime => 'Resolve keys and taps through the binding table';
	@override String get operationBindingRuntimeSubtitle => 'When off, the reader falls back to the built-in fixed keys (arrows, WASD, numpad and F11), and the edits below do not affect reading.';
	@override String get operationBindingInvertWheel => 'Wheel follows the hand, not the content';
	@override String get operationBindingInvertWheelSubtitle => 'When on: roll up = previous page, roll down = next page, named after how your hand moves. macOS already inverts scroll deltas for natural scrolling, so this is on by default there; when off, direction follows content movement. Recording bindings and the legacy fallback use the same rule.';
	@override String get operationBindingSectionKeyboard => 'Keyboard';
	@override String get operationBindingSectionTap => 'Tap zones';
	@override String get operationBindingTapSubtitle => 'The reader only tells three zones apart: left half, center cell, right half. The top and bottom rows behave like the middle one.';
	@override String get operationBindingAreaMiddleLeft => 'Left half';
	@override String get operationBindingAreaMiddleCenter => 'Center';
	@override String get operationBindingAreaMiddleRight => 'Right half';
	@override String get operationBindingBoundAction => 'Bound action';
	@override String get operationBindingUnbound => 'Unbound';
	@override String get operationBindingSectionBundle => 'Binding bundle';
	@override String get operationBindingImport => 'Import JSON';
	@override String get operationBindingImportSubtitle => 'Import a bindings object or array, preserving every input type, context and action sequence.';
	@override String get operationBindingImportConfirm => 'Load';
	@override String operationBindingImportLoaded({required Object count}) => 'Loaded ${count} bindings — save to apply them';
	@override String get operationBindingExport => 'Export JSON';
	@override String get operationBindingExportSubtitle => 'Copy the whole table you are editing.';
	@override String get operationBindingCopy => 'Copy';
	@override String get operationBindingCopied => 'Binding table copied to clipboard';
	@override String get operationBindingJsonHint => 'Validation and conflict checks run before saving. Imported text is written only once you press Save.';
	@override String get operationBindingSave => 'Save';
	@override String get operationBindingSaved => 'Binding table saved — effective immediately';
	@override String get operationBindingDiscard => 'Discard';
	@override String get operationBindingDiscarded => 'Unsaved changes discarded';
	@override String get operationBindingDirtyHint => 'You have unsaved changes.';
	@override String get operationBindingRestoreFactory => 'Restore factory presets';
	@override String get operationBindingRestoreFactorySubtitle => 'Restore Neo\'s default grid, wheel, keyboard and mouse bindings, and reset the radial menu. Existing custom bindings will be replaced.';
	@override String get operationBindingAddKey => 'Add key';
	@override String get operationBindingNoKeys => 'No keys bound';
	@override String get operationBindingDisabledRow => 'Disabled (does not count as a conflict)';
	@override String get operationBindingRemove => 'Delete this binding';
	@override String get operationBindingUnimplemented => 'This action has no executor in this build yet';
	@override String get operationBindingRecordTitle => 'Press the key to bind';
	@override String get operationBindingRecordHint => 'Hold Ctrl / Alt / Shift / Win to bind a chord. Press Esc to cancel.';
	@override String operationBindingRecordUnsupported({required Object label}) => 'No platform-neutral key name for ${label}, so it cannot be bound';
	@override String get operationBindingConflictTitle => 'Conflicting bindings';
	@override String get operationBindingConflictBody => 'One input may have only one enabled binding. Remove or disable one of them, then save again.';
	@override String get operationBindingInvalidTable => 'This binding table could not be parsed, so the save was refused';
	@override String get operationBindingCategoryNavigation => 'Navigation';
	@override String get operationBindingCategoryZoom => 'Zoom';
	@override String get operationBindingCategoryView => 'View';
	@override String get operationBindingCategorySession => 'Session';
	@override String get operationBindingActionNextPage => 'Next page';
	@override String get operationBindingActionPreviousPage => 'Previous page';
	@override String get operationBindingActionFirstPage => 'First page';
	@override String get operationBindingActionLastPage => 'Last page';
	@override String get operationBindingActionPageLeft => 'Page left';
	@override String get operationBindingActionPageRight => 'Page right';
	@override String get operationBindingActionFullscreen => 'Fullscreen';
	@override String get operationBindingActionToggleDirection => 'Toggle reading direction';
	@override String get operationBindingActionBookMode => 'Book mode';
	@override String get operationBindingActionResetView => 'Reset view';
	@override String get operationBindingActionToggleBars => 'Show or hide the bars';
	@override String get operationBindingActionOpenSettings => 'Open settings';
	@override String get operationBindingActionZoomIn => 'Zoom in';
	@override String get operationBindingActionZoomOut => 'Zoom out';
	@override String get operationBindingActionFitWindow => 'Fit to window';
	@override String get operationBindingActionActualSize => 'Actual size';
	@override String get operationBindingActionRotateClockwise => 'Rotate clockwise';
	@override String get operationBindingActionRotate180 => 'Rotate 180 degrees';
	@override String get workspaceLayout => 'Layout';
	@override String get workspaceLayoutSubtitle => 'Startup view · lane focus & solo · hover reveal zones';
	@override String get laneAndLayout => 'Lanes & Layout';
	@override String get defaultStartupView => 'Default startup view';
	@override String get startupViewEdges => 'Workhole';
	@override String get startupViewSwimlane => 'Swimlane';
	@override String get startupViewHint => 'Which presentation the workspace opens with. Both share one set of records, so switching never reopens the current book.';
	@override String get laneFocusSolo => 'Lane focus & solo';
	@override String get laneFocusSoloSubtitle => 'Controls when the main lane takes over, the switcher rail and edge reveal respond.';
	@override String get autoFocusReaderOnOpen => 'Jump to the reader lane on read';
	@override String get autoFocusReaderOnOpenSubtitle => 'Tapping "Read" (on the cover or in the comic info page — the same action) hands the viewport and interaction to the central reader lane. When off, the book still opens in that lane but the strip does not move: keep browsing the lane you were in, and click over to the reader when you want it.';
	@override String get readerSoloOnFocus => 'Auto-solo Reader on focus';
	@override String get readerSoloOnFocusSubtitle => 'Handing interaction to Reader also lets it take the full available width, without clicking the solo button again.';
	@override String get showLaneNavigatorInSolo => 'Show lane switcher while Reader is solo';
	@override String get showLaneNavigatorInSoloSubtitle => 'Other lanes stay in the strip as compact rails you can click; turn it off and only Reader remains, with other lanes brought back by the side reveal zones.';
	@override String get manualScrollEnabled => 'Allow manual horizontal scroll';
	@override String get manualScrollEnabledSubtitle => 'When off the strip still scrolls itself to the active or revealed lane; only your own drags and the wheel are ignored.';
	@override String get blockManualScrollInReaderFullscreen => 'Block horizontal lane dragging in fullscreen';
	@override String get blockManualScrollInReaderFullscreenSubtitle => 'While the Reader is fullscreen, horizontal gestures only turn pages and no longer pan the swimlane strip (which drags the Reader along). Turn it off to keep dragging available, same as usual.';
	@override String get laneHeaderChrome => 'Lane header';
	@override String get laneHeaderChromeSubtitle => 'What the lane header row draws. Only the header itself — nothing inside the lane changes.';
	@override String get showLaneWidthBadge => 'Show lane width badge';
	@override String get showLaneWidthBadgeSubtitle => 'Draws the current width as a "400px" badge next to the lane title. Off by default — set the width from the lane menu\'s "Lane width" field; while off, that width goes back to the title and tab strip.';
	@override String get panelTabSortMode => 'Panel tab sort mode';
	@override String get panelTabSortModeSubtitle => 'When on, long-press a tab to drag it to reorder or move it to another lane; when off, dragging across the strip switches panels and the selection follows your finger.';
	@override String get edgeRevealDelay => 'Side lane reveal delay';
	@override String get readerHoverFocusDelay => 'Reader hover refocus delay';
	@override String get readerHoverFocusEnable => 'Enable Reader hover refocus';
	@override String get revealFocusesLane => 'Focus lane after edge reveal';
	@override String get revealFocusesLaneSubtitle => 'Once the pointer has dwelled at the left or right edge long enough, the revealed lane also takes over interaction — no extra click. Reader keeps a narrow sliver, so one click returns to solo. When off, a reveal is only a peek and folds back to Reader after a while.';
	@override String get panelLaneHoverFocus => 'Hover focus for panel lanes';
	@override String get panelLaneHoverFocusSubtitle => 'Dwelling inside the left or right lane activates it too, sharing the delay above. Lanes collapsed to a rail are excluded, so brushing past them while reading won\'t steal focus.';
	@override String get delayRangeHint => 'Dwell time in milliseconds before it fires. The three delays are independent — changing one never drags another along.';
	@override String get hoverRevealZones => 'Hover reveal zones';
	@override String get hoverRevealZonesSubtitle => 'Drag rectangles on the canvas to decide where the pointer brings content up.';
	@override String get hoverRevealZonesHint => 'Left and right drive lane reveal, top drives the workspace chrome, bottom drives the reader\'s bottom bar. Drag to draw, then drag the corners to fine-tune.';
	@override String get revealEdgeLeft => 'Left';
	@override String get revealEdgeRight => 'Right';
	@override String get revealEdgeTop => 'Top';
	@override String get revealEdgeBottom => 'Bottom';
	@override String get revealLinkHorizontal => 'Link L/R';
	@override String get revealLinkVertical => 'Link T/B';
	@override String get revealReset => 'Reset reveal zones';
	@override String get revealFieldX => 'X';
	@override String get revealFieldY => 'Y';
	@override String get revealFieldWidth => 'W';
	@override String get revealFieldHeight => 'H';
	@override String get revealZoneResetDone => 'Reveal zones restored to defaults';
	@override String get operationBindingTabKeyboard => 'Shortcuts';
	@override String get operationBindingTabRadial => 'Radial menu';
	@override String get operationBindingActionOpenRadial => 'Open radial menu';
	@override String get operationBindingActionConfirmRadial => 'Confirm radial selection';
	@override String get operationBindingActionToggleLibrary => 'Toggle library';
	@override String get operationBindingRadialEnable => 'Enable radial menu';
	@override String get operationBindingRadialEnableSubtitle => 'When off the wheel never opens; slot bindings are kept';
	@override String get operationBindingRadialActiveWheel => 'Default wheel';
	@override String operationBindingRadialLayerUnit({required Object count}) => '${count} layers';
	@override String get operationBindingRadialNew => 'New wheel';
	@override String get operationBindingRadialDelete => 'Delete wheel';
	@override String get operationBindingRadialPreview => 'Preview';
	@override String get operationBindingRadialReset => 'Reset slots';
	@override String get operationBindingRadialResetSubtitle => 'Rewrites only this wheel\'s factory slots; your own bindings stay';
	@override String operationBindingRadialHint({required Object layers}) => 'On · ${layers} layers · tap an empty slot to add, a filled one to edit';
	@override String get operationBindingRadialHintDisabled => 'Off · the wheel will not open while reading';
	@override String get operationBindingRadialAppearance => 'Appearance & geometry';
	@override String operationBindingRadialGeometrySummary({required Object radius, required Object inner, required Object variant}) => 'r${radius} · inner ${inner} · ${variant}';
	@override String get operationBindingRadialRadius => 'Wheel size';
	@override String get operationBindingRadialInnerRadius => 'Inner radius (hole)';
	@override String get operationBindingRadialSectors => 'Sectors per layer';
	@override String get operationBindingRadialSlots => 'Slots';
	@override String get operationBindingRadialSlotsSubtitle => 'Tap an empty or filled slot on the wheel';
	@override String get operationBindingRadialName => 'Wheel name';
	@override String operationBindingRadialSlotLabel({required Object layer, required Object sector}) => 'Layer ${layer} · slot ${sector}';
	@override String get operationBindingRadialEmptySlot => 'Empty slot';
	@override String get operationBindingRadialUnbindSlot => 'Unbind this slot';
	@override String operationBindingRadialMaxMenus({required Object max}) => 'Up to ${max} wheels';
	@override String operationBindingRadialDeleteConfirm({required Object name}) => 'Delete wheel "${name}"? Its slot bindings are removed too.';
	@override String get operationBindingRadialDeleteLast => 'At least one wheel must stay';
	@override String get operationBindingRadialInvalid => 'The wheel layout is invalid, saving was refused';
	@override String get operationBindingRadialResetDone => 'Factory slots restored';
	@override String operationBindingRadialNewName({required Object index}) => 'Wheel ${index}';
	@override String get operationBindingRadialEmptyWheel => 'A new wheel is empty: bind its slot by slot';
	@override String get operationBindingCategoryRadial => 'Radial';
	@override String get operationBindingRadialItemKind => 'Kind';
	@override String get operationBindingRadialKindAction => 'Run action';
	@override String get operationBindingRadialKindMove => 'Jump to wheel';
	@override String get operationBindingRadialTargetWheel => 'Target wheel';
	@override String get operationBindingRadialIcon => 'Icon';
	@override String get operationBindingRadialIconAuto => 'Match action automatically';
	@override String get operationBindingRadialLabel => 'Label';
	@override String get operationBindingRadialSlotIndex => 'Slot';
	@override String get operationBindingRadialItemEnabled => 'This slot is enabled';
	@override String get operationBindingRadialMoveUp => 'Move earlier';
	@override String get operationBindingRadialMoveDown => 'Move later';
	@override String get operationBindingRadialDeleteItem => 'Delete this slot';
	@override String get operationBindingRadialStartAngle => 'Rotation';
	@override String get operationBindingRadialSweepAngle => 'Sweep angle';
	@override String get operationBindingRadialVariant => 'Style';
	@override String get operationBindingRadialVariantSlice => 'Rounded buttons';
	@override String get operationBindingRadialVariantBubble => 'Round buttons';
	@override String operationBindingRadialLayerN({required Object n}) => 'Layer ${n}';
	@override String get operationBindingRadialSelectedSlot => 'Selected slot';
	@override String get operationBindingRadialPickHint => 'Tap a sector on the wheel to pick it; empty ones show +';
	@override String get operationBindingRadialEmptySlotRow => '(empty)';
	@override String get operationBindingRadialActionLabel => 'Action';
}

// Path: bookshelf
class _Translations$bookshelf$en_US extends Translations$bookshelf$zh_CN {
	_Translations$bookshelf$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get collectedWorks => 'Collected';
	@override String get readingNow => 'Reading';
	@override String get unreadWorks => 'Unread';
	@override String get createFolderHint => 'Groups related comics together so you can find them again later.';
	@override String get title => 'Bookshelf';
	@override String get favorite => 'Favorites';
	@override String get history => 'History';
	@override String get download => 'Downloads';
	@override String get filter => 'Filter';
	@override String get searchList => 'Search list';
	@override String get newFolder => 'New folder';
	@override String get manage => 'Manage';
	@override String get importComic => 'Import comic';
	@override String get folderHint => 'Bookshelf hints';
	@override String get removeFromFolder => 'Remove from folder';
	@override String get deleteFavorite => 'Remove favorite';
	@override String get deleteHistory => 'Delete history';
	@override String get deleteDownload => 'Delete download record';
	@override String confirmDeleteSelected({required Object count}) => 'Are you sure you want to delete the selected ${count} records?';
	@override String deletedRecords({required Object count}) => 'Deleted ${count} records';
	@override String get noFilterSource => 'No filterable plugin sources';
	@override String get sort => 'Sort';
	@override String get sortDesc => 'Time (newest first)';
	@override String get sortAsc => 'Time (oldest first)';
	@override String get viewSortDesc => 'View time (newest first)';
	@override String get viewSortAsc => 'View time (oldest first)';
	@override String get source => 'Comic source';
	@override String get deselectAll => 'Deselect all';
	@override String get renameFolder => 'Rename folder';
	@override String get createFolder => 'Create folder';
	@override String get multiSelect => 'Multi-select';
	@override String get copyTo => 'Copy to';
	@override String get batchExport => 'Batch export';
	@override String get batchDeleteFailed => 'Batch delete failed';
	@override String get deleteSelected => 'Delete selected';
	@override String get cancel => 'Cancel selection';
	@override String selectedCount({required Object count}) => 'Selected ${count} items';
	@override String folderComicCount({required Object count}) => '${count} items';
	@override String get selectTargetFolder => 'Select target folders (multiple)';
	@override String get confirmDeleteFolderTitle => 'Confirm delete';
	@override String get confirmDeleteFolderContent => 'Delete this folder? Contents will be deleted recursively.';
	@override String get confirmRemoveComicTitle => 'Remove from folder';
	@override String confirmRemoveComicContent({required Object title}) => 'Remove "${title}" from current folder?';
	@override String get importComicZipOnly => 'Importing comics (zip only)';
	@override String get importStarted => 'Importing comics (zip only)';
	@override String importCompleted({required Object title}) => 'Import completed: ${title}';
	@override String get comicExists => 'Comic already exists';
	@override String confirmOverwriteImport({required Object title}) => '${title} already exists in download list. Overwrite?';
	@override String get noExportableComics => 'No exportable comics in selection';
	@override String batchExportCompleted({required Object success, required Object total}) => 'Batch export completed: ${success}/${total}';
	@override String batchExportDeleted({required Object count}) => 'Deleted local downloads for ${count} comic(s)';
	@override String batchExportKeptIncomplete({required Object count}) => '${count} comic(s) had pages missing from the export; their local downloads were kept';
	@override String batchExportFailed({required Object error}) => 'Batch export failed: ${error}';
	@override String get confirmDeleteSelectedTitle => 'Confirm delete';
	@override String get confirmDeleteSelectedContent => 'Delete selected folders and comics? Folders will be deleted recursively.';
	@override String get cancelSelect => 'Cancel selection';
	@override String get selectAll => 'Select all';
	@override String get moveTo => 'Move to';
	@override String get addToFolder => 'Add to folder';
	@override String get folderName => 'Folder name';
	@override String get helpContent => '• Favorites and bookshelf are linked: favoriting a comic adds it to the bookshelf; only removing it from all favorite folders unfavorites it.\n• On comic detail page, unfavorite removes it from all favorite folders at once.\n• Same for downloads: only removing a comic from all download folders deletes its downloaded files.';
	@override String get folderCreated => 'Folder created';
	@override String get noComic => 'No comics yet';
	@override String get noHistory => 'No reading history yet';
	@override String get noDownload => 'No downloads yet';
	@override String get nothingHere => 'Nothing here';
	@override String get deleteAllDownloadRecordsAndFiles => 'Delete all download records and files';
	@override String get clearHistoryRecords => 'Clear history records';
	@override String get confirmDeleteAllDownloadsContent => 'Delete all download records and their files? This action cannot be undone!';
	@override String get confirmClearHistoryContent => 'Clear all history records? This action cannot be undone!';
	@override String get allDownloadRecordsAndFilesDeleted => 'All download records and files deleted';
	@override String get historyRecordsCleared => 'History records cleared';
	@override String get batchExportTitle => 'Choose export method';
	@override String get batchExportSubtitle => 'Please choose batch export as zip or folder';
	@override String get importCancelled => 'Import cancelled';
	@override String importEpisodeFallback({required Object index}) => 'Ep. ${index}';
	@override String get importMissingJson => 'Import directory is missing required JSON files';
	@override String get importVersionUnsupported => 'This version cannot be imported, please export with a newer app version';
	@override String get importMissingSource => 'Export file is missing source info, please re-export with a newer app version';
	@override String get importMissingComicId => 'Cannot get comic ID';
	@override String get importNoComicDir => 'No importable comic directory found in the archive';
	@override String get importMultipleComicDirs => 'Archive contains multiple comic directories, please import one at a time';
	@override String importComicExistsUncovered({required Object title}) => 'Comic "${title}" already exists, import skipped';
	@override String get folderNameEmpty => 'Folder name cannot be empty';
	@override String get folderNameSlash => 'Folder name cannot contain /';
	@override String get folderNameExists => 'A folder with the same name already exists in this path';
	@override String targetFolderNameExists({required Object name}) => 'A folder with the same name already exists at target: ${name}';
	@override String get cannotMoveFolderToSelf => 'Cannot move a folder into itself';
	@override String get cannotMoveParentToChild => 'Cannot move a parent folder into its subfolder';
	@override String get cannotCopyFolderToSelfOrChild => 'Cannot copy a folder into itself or its subfolders';
	@override String get moveFoldersOnlyOneTarget => 'Only one target folder can be selected when moving folders';
	@override String confirmDeleteSelectedFavorites({required Object count}) => 'Delete selected ${count} favorite records?';
	@override String confirmDeleteSelectedHistory({required Object count}) => 'Delete selected ${count} history records?';
	@override String confirmDeleteSelectedDownloads({required Object count}) => 'Delete selected ${count} download records and files?';
}

// Path: comicInfo
class _Translations$comicInfo$en_US extends Translations$comicInfo$zh_CN {
	_Translations$comicInfo$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String chapterCount({required Object count}) => 'Chapters · ${count}';
	@override String get pageClosedFavoriteCancelled => 'The page closed; the favourite action was cancelled';
	@override String get previewLoadFailed => 'Preview failed to load';
	@override String get showMoreChapters => 'Show more chapters';
	@override String get noChaptersYet => 'No chapters yet';
	@override String get reverseOrderLabel => 'Reverse';
	@override String get restoreForwardOrder => 'Restore forward order';
	@override String get imagePreview => 'Image preview';
	@override String get collapseDetails => 'Collapse details';
	@override String get workTools => 'Work tools';
	@override String get refreshInformation => 'Refresh info';
	@override String get cloudFavoriteIncomplete => 'The cloud favourite operation didn\'t finish';
	@override String get follow => 'Follow updates';
	@override String get unfollow => 'Unfollow';
	@override String get exportComic => 'Export comic';
	@override String get cloudCollect => 'Cloud collect';
	@override String get cloudCollected => 'Cloud collected';
	@override String get cloudCollectDisabled => 'This plugin does not support this feature';
	@override String get collectingToCloud => 'Adding to cloud collection...';
	@override String get removingCloudCollection => 'Removing cloud collection...';
	@override String get cloudCollectSuccess => 'Added to cloud collection';
	@override String get cloudUncollectSuccess => 'Removed from cloud collection';
	@override String get cloudCollectIncomplete => 'Cloud collection operation incomplete';
	@override String get discontinued => 'This comic is discontinued';
	@override String likes({required Object count}) => 'Likes ${count}';
	@override String comments({required Object count}) => 'Comments ${count}';
	@override String get collected => 'Collected';
	@override String get collect => 'Collect';
	@override String get download => 'Download';
	@override String get markRead => 'Mark as read';
	@override String get markUnread => 'Mark as unread';
	@override String get markThroughRead => 'Mark up to here as read';
	@override String get clearReadMark => 'Clear mark';
	@override String get readStateMenu => 'Reading state';
	@override String get readStateMenuHint => 'Marks only record your own judgement. They never change reading progress or where “Continue reading” takes you.';
	@override String markReadDone({required Object count}) => 'Marked ${count} chapters as read';
	@override String markUnreadDone({required Object count}) => 'Marked ${count} chapters as unread';
	@override String markThroughReadDone({required Object count}) => 'Marked ${count} earlier chapters as read';
	@override String get readStateUnread => 'Unread';
	@override String get readStateInferred => 'Read before';
	@override String get readStateManualRead => 'Marked read';
	@override String get readStateManualUnread => 'Marked unread';
	@override String get downloadForbidden => 'This plugin does not support this feature';
	@override String get addedToCollection => 'Added to collection';
	@override String get removedFromCollection => 'Removed from collection';
	@override String get confirmUncollectTitle => 'Remove collection';
	@override String get confirmUncollectContent => 'This will delete the comic from all folders. Continue?';
	@override String get commentForbidden => 'This plugin does not support this feature';
	@override String get commentForbiddenTitle => 'Comments disabled';
	@override String get back => 'Back';
	@override String get exportTitle => 'Choose export format';
	@override String get exportSubtitle => 'Export as folder or zip archive:';
	@override String get folder => 'Folder';
	@override String get zip => 'Zip archive';
	@override String get exportSuccess => 'Export successful';
	@override String get detailsNotLoaded => 'Comic details not fully loaded';
	@override String get followed => 'Following updates';
	@override String get unfollowed => 'Unfollowed';
	@override String get confirmUnfollowTitle => 'Unfollow';
	@override String confirmUnfollowContent({required Object title}) => 'Stop following "${title}"?';
	@override String get noChapters => 'No chapter information';
	@override String get chapterList => 'Chapters';
	@override String get preview => 'Preview';
	@override String episodeCount({required Object count}) => '${count} Episodes';
	@override String episodeFallback({required Object index}) => '${index}';
	@override String episodeLabel({required Object index}) => '${index}';
	@override String groupEpisodeCount({required Object count}) => '${count} Episodes';
	@override String get untitledGroup => 'Ungrouped';
	@override String get downloadGroup => 'Download group';
	@override String get author => 'Author';
	@override String get tags => 'Tags';
	@override String get works => 'Works';
	@override String views({required Object count}) => 'Views: ${count}';
	@override String updateTime({required Object time}) => 'Updated: ${time}';
	@override String get startRead => 'Start reading';
	@override String get continueRead => 'Continue reading';
	@override String get lastRead => 'Last read';
	@override String get chapters => 'Chapters';
	@override String get related => 'Related';
	@override String get description => 'Description';
	@override String get collapse => 'Collapse';
	@override String get expandFullText => 'Read more';
	@override String get readHistory => 'Reading history';
	@override String copied({required Object label}) => 'Copied: ${label}';
	@override String copiedToClipboard({required Object name}) => 'Copied ${name} to clipboard';
	@override String get openOnSource => 'Open on source';
	@override String get liking => 'Liking...';
	@override String get unliking => 'Unliking...';
	@override String get likeSuccess => 'Liked';
	@override String get unlikeSuccess => 'Unliked';
	@override String get likeDisabled => 'This plugin does not support this feature';
	@override String localCollectFailed({required Object error}) => 'Local favorite failed: ${error}';
	@override String likeFailed({required Object error}) => 'Like failed: ${error}';
	@override String loadFailedWithError({required Object error}) => '${error}\nLoading failed, please retry.';
	@override String get exportPermissionDenied => 'All files access permission not granted, export cancelled';
	@override String exportFailedWithError({required Object error}) => 'Export failed, please retry.\n${error}';
	@override String exportDirectory({required Object displayPath}) => 'Export directory: ${displayPath}';
	@override String get exportPathTooLong => 'Export directory path is too long to create a valid structure';
	@override String get zipExportPathTooLong => 'Specified zip export path exceeds system path length limit';
	@override String get downloadPathTooLong => 'Download directory path is too long to create a valid zip file path';
	@override String get uniqueFileNameTooLong => 'Cannot create a unique file name for chapter: path length limit exceeded';
	@override String exportFolderComplete({required Object title}) => 'Exported "${title}" as folder';
	@override String exportZipComplete({required Object title}) => 'Exported "${title}" as zip';
	@override String exportComicNotFound({required Object comicId}) => 'No downloadable comic found for export: ${comicId}';
	@override String get exportDeleteAfter => 'Delete local download after a successful export';
	@override String get exportDeleteAfterSubtitle => 'Only deleted once every page made it into the archive and the file is verified on disk. Otherwise the download is kept and the reason is shown.';
	@override String exportedAndDeleted({required Object title}) => 'Exported and deleted local download: ${title}';
	@override String exportDeleteSkippedIncomplete({required Object count, required Object chapters}) => '${count} page(s) did not make it into the export (${chapters}); local download kept';
	@override String get exportDeleteSkippedEmpty => 'No downloadable pages found locally; local download kept';
	@override String get exportDeleteSkippedArtifact => 'Exported file failed the integrity check; local download kept';
	@override String get exportDeleteSkippedInsideRoot => 'Export target is inside the download folder, deleting would remove the export too; local download kept';
	@override String exportDeleteFailed({required Object error}) => 'Export finished, but deleting the local download failed: ${error}';
	@override String get pluginInvalidFavorited => 'Plugin did not return a valid favorited status';
	@override String get pluginInvalidLiked => 'Plugin did not return a valid liked status';
	@override String get addToCustomFolder => 'Add to custom folder';
	@override String addedToFolder({required Object name}) => 'Added to folder: ${name}';
	@override String get skipAdd => 'Skip / Don\'t add';
	@override String get confirmAdd => 'Confirm add';
	@override String resolveComicIdFailed({required Object type}) => 'Cannot resolve comic ID for reading: ${type}';
	@override String resolveEpsCountFailed({required Object type}) => 'Cannot resolve episode count for reading: ${type}';
	@override String get collectToCloud => 'Collect to cloud';
	@override String get collectToLocal => 'Collect locally';
	@override String get removeCloudCollection => 'Remove cloud collection';
	@override String get removeLocalCollection => 'Remove local collection';
}

// Path: reader
class _Translations$reader$en_US extends Translations$reader$zh_CN {
	_Translations$reader$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String switchBookFailed({required Object error}) => 'Switching books failed: ${error}';
	@override String pageDecodeFailed({required Object n}) => 'Page ${n} could not be decoded';
	@override String cannotOpenPath({required Object path}) => 'Can\'t open: ${path}';
	@override String get aiJpegDenoise => 'AI JPEG denoise';
	@override String get noMatchingOfflineComics => 'No downloaded comics match';
	@override String get searchOfflineComics => 'Search downloaded comics';
	@override String get stateNotDownloadedAsk => 'Not downloaded (it asks first when you turn this on)';
	@override String get stateDownloaded => 'Downloaded';
	@override String get stateOff => 'Off';
	@override String get stateOn => 'On';
	@override String cannotOpenLocalComic({required Object error}) => 'Can\'t open the local comic: ${error}';
	@override String cachedPages({required Object count}) => '${count} pages cached';
	@override String targetLanguageLabel({required Object lang}) => 'Target ${lang}';
	@override String bottomRevealPx({required Object px}) => 'Bottom reveal (${px}px)';
	@override String topRevealPx({required Object px}) => 'Top reveal (${px}px)';
	@override String sourcePageOf({required Object index, required Object total}) => 'Source page ${index} of ${total}';
	@override String manualPageOrderFor({required Object name}) => 'Manual page order · ${name}';
	@override String tapToSwitchMode({required Object from, required Object to}) => '${from} (tap to switch to ${to})';
	@override String modelState({required Object state}) => 'Model: ${state}';
	@override String modelDownloadFailed({required Object error}) => 'Model download failed: ${error}';
	@override String activeThreshold({required Object value}) => 'Effective threshold: ${value}';
	@override String globalDefaultState({required Object state}) => 'Global (default for all books): ${state}';
	@override String thisBookState({required Object state}) => 'This book: ${state}';
	@override String upscaleChipTail({required Object tooltip}) => '${tooltip}\nTap to toggle; hold to peek at the original; the power button on the right affects this book only';
	@override String notWiredIntoReader({required Object name}) => '${name} isn\'t wired into this repo\'s reader yet';
	@override String notImplementedYet({required Object name}) => '${name} (not implemented in this repo yet)';
	@override String oneScreenPercent({required Object percent}) => '${percent}% of a screen';
	@override String slideshowDwellHint({required Object step, required Object min, required Object max}) => 'How long each page stays: ${step} per step, between ${min} and ${max}';
	@override String manualRotationDeg({required Object deg}) => 'Manual rotation ${deg}°';
	@override String loupeSizeRange({required Object min, required Object max}) => 'Window edge, logical pixels (${min}–${max}, 20 per step)';
	@override String loupeZoomRange({required Object min, required Object max}) => 'Magnification (${min}%–${max}%, 25% per step, doubling steps from 400%)';
	@override String intervalSeconds({required Object seconds}) => 'Interval ${seconds}s';
	@override String tapToExpandPanel({required Object label}) => '${label} (tap to open the panel)';
	@override String zoomModeValue({required Object mode}) => 'Zoom mode: ${mode}';
	@override String get imageProcessingOffReaderHint => 'Image processing is off; turn it on in the reader settings';
	@override String get gpuTextureUnsupported => 'This platform doesn\'t support GPU texture processing';
	@override String get thisPage => 'This page';
	@override String get pendingUpscale => 'Awaiting upscale';
	@override String get upscaleFailedState => 'Upscale failed';
	@override String get noUpscaleNeeded => 'No upscaling needed';
	@override String get upscaledState => 'Upscaled';
	@override String get generatedState => 'Generated';
	@override String get upscalingState => 'Upscaling';
	@override String get queuedState => 'Queued';
	@override String get originalCompareChip => 'Comparing original';
	@override String get upscaleOff => 'Upscale off';
	@override String get notSupported => 'Not supported';
	@override String get noProcessingNeeded => 'No processing needed';
	@override String get denoiseFailed => 'Denoise failed';
	@override String get enhanceFailed => 'Enhance failed';
	@override String get pendingDenoise => 'Awaiting denoise';
	@override String get pendingEnhance => 'Awaiting enhance';
	@override String get denoisedDone => 'Denoised';
	@override String get enhancedDone => 'Enhanced';
	@override String get denoising => 'Denoising';
	@override String get enhancing => 'Enhancing';
	@override String get upscaleShort => 'Upscale';
	@override String get jpegDenoise => 'JPEG denoise';
	@override String get denoisePlusUpscale => 'Denoise + upscale';
	@override String tooltipIdle({required Object page, required Object process, required Object hint}) => '${page} hasn\'t started ${process} yet${hint}';
	@override String tooltipFailed({required Object page, required Object process, required Object hint}) => '${page} · ${process} failed, still showing the original${hint}';
	@override String tooltipSkipped({required Object page, required Object hint}) => '${page} needs no processing${hint}';
	@override String tooltipApplied({required Object page, required Object process, required Object hint}) => '${page} already uses the ${process} image${hint}; tap here to compare with the original';
	@override String tooltipReady({required Object page, required Object hint}) => '${page}\'s processed image is ready, waiting to be shown${hint}';
	@override String tooltipRunning({required Object page, required Object process, required Object hint}) => '${page} · ${process}…${hint}';
	@override String tooltipQueued({required Object page, required Object process, required Object hint}) => '${page} is queued, waiting for ${process}${hint}';
	@override String tooltipComparing({required Object hint}) => 'Comparing with the original; tap here to return to the processed image${hint}';
	@override String sizeHintSource({required Object source}) => '(original ${source})';
	@override String sizeHintEnhanced({required Object enhanced}) => '(processed ${enhanced})';
	@override String sizeHintBoth({required Object source, required Object enhanced}) => '(original ${source} → processed ${enhanced})';
	@override String pageNumberN({required Object page}) => 'Page ${page}';
	@override String missingWeightsCount({required Object count}) => 'missing ${count} weights';
	@override String get noMissingWeights => '(nothing missing, proceeding as-is)';
	@override String get fitWindow => 'Fit to window';
	@override String get autoTrimEnabledByDefault => 'Enable auto-trim by default';
	@override String get alignHeight => 'Align height (two pages share one height)';
	@override String get dwellIndicatorOff => 'The dwell indicator is off; you can only guess which page is showing';
	@override String get firstPageAloneOn => 'Show the first page alone: on';
	@override String get firstPageAloneOff => 'Show the first page alone: off';
	@override String get rotateClockwise90 => 'Rotate 90° clockwise';
	@override String get pageSorting => 'Page sorting';
	@override String get pageLayout => 'Page layout';
	@override String get pageOrder => 'Page order';
	@override String get trimSideLimitHint => 'Caps how much of each side may be trimmed; 0% keeps the full page';
	@override String get denoiseAdvancedSettings => 'Advanced denoise settings';
	@override String get denoiseBlockSize => 'Denoise block size';
	@override String get denoiseShort => 'Denoise';
	@override String get thresholdLabel => 'Threshold';
	@override String get startWeightsInReaderSettings => 'Start downloading the weights in the reader settings:';
	@override String get readerSafeMarginBothSides => 'Whether the reader keeps a moderate safety margin on both sides';
	@override String get intervalLabel => 'Interval';
	@override String get lockLoupe => 'Lock';
	@override String get fillWholeWindow => 'Fill the whole window';
	@override String get resetViewTransform => 'Reset zoom, rotation and wide-page policy (keeps page mode and reading direction)';
	@override String get rotateCounterclockwise90 => 'Rotate 90° counter-clockwise';
	@override String get fitHeight => 'Fit to height';
	@override String get fitWidth => 'Fit to width';
	@override String get pageNotLoadedYet => 'This page has not loaded yet; wait a moment and translate again';
	@override String get loadingSettings => 'Loading settings…';
	@override String get translationHiddenByCompare => 'The translation is generated and injected but hidden by "compare with original"; switch back to upscaling to see it';
	@override String get trigger => 'Trigger';
	@override String get trimAdvancedSettings => 'Advanced trim settings';
	@override String get pointerTypeAuto => 'Auto: decided by the pointer itself — mouse and trackpad follow hover, finger and stylus need a press (platform-independent, so touch laptops plus an external mouse both resolve correctly)';
	@override String get autoTranslateShort => 'Auto-translate';
	@override String get autoRotate => 'Auto-rotate';
	@override String get autoSplitLandscapeOn => 'Auto-split landscape pages: on';
	@override String get autoSplitLandscapeOff => 'Auto-split landscape pages: off';
	@override String get backgroundTolerance => 'Background detection tolerance';
	@override String get autoTranslateEnabled => 'Auto-translate on page turn is enabled';
	@override String get zoomMode => 'Zoom mode';
	@override String get editManualOrder => 'Edit this chapter\'s manual order';
	@override String get rotatePortraitLeft => 'Rotate portrait pages left';
	@override String get rotatePortraitRight => 'Rotate portrait pages right';
	@override String get chapterShort => 'Chapter';
	@override String get downloadNow => 'Download now';
	@override String get confirmResetAndRedownload => 'Reset the progress and download this comic again?';
	@override String get zoomShortReset => 'Short press resets to 100%; press and hold to enter a percentage';
	@override String get marginWhitespace => 'Whitespace';
	@override String get noBookOpenYet => 'No book is open now — open one before this can be set per book';
	@override String get layoutTools => 'Layout tools';
	@override String get autoScroll => 'Auto-scroll';
	@override String get clearManualOrder => 'Clear this chapter\'s manual order';
	@override String get removeTwoPageSeam => 'Removes the seam between the two pages';
	@override String get downloadingUpscaleInBackground => 'Downloading the upscale model in the background...';
	@override String get landscape => 'Landscape';
	@override String get rotateLandscapeLeft => 'Rotate landscape pages left';
	@override String get rotateLandscapeRight => 'Rotate landscape pages right';
	@override String get formatLabel => 'Format';
	@override String get webtoonStepScreens => 'How many screens a webtoon advances per tick: webtoons only; paginated books move a whole page';
	@override String get webtoonTrimSidesOnly => 'Webtoons trim only the sides, keeping the vertical seam. Full-bleed or unreliable detections stay as-is.';
	@override String get weights => 'Weights';
	@override String get noManualOrderHere => 'This chapter has no manual order to clear';
	@override String get bookImageProcessing => 'This book: image processing';
	@override String get bookEnableAiUpscale => 'This book: enable AI super-resolution';
	@override String get bookUpscaleOnFetch => 'Upscaling is on for this book (later fetches are processed at the fetch layer)';
	@override String get bookAiUpscaleOn => 'AI upscaling is enabled for this book';
	@override String get bookTrimOnOverride => 'Trim is on for this book alone · global is off';
	@override String get bookTrimOffOverride => 'Trim is off for this book alone · global is on, so this session will not trim';
	@override String get bookUpscaleOff => 'Upscaling is off for this book (other books follow the global setting)';
	@override String get bookAiUpscaleOff => 'AI upscaling is off for this book (other books follow the global setting)';
	@override String get bookEnableJpegDenoise => 'Enable JPEG denoise for this book';
	@override String get loupeUnlockedFollows => 'Unlocked: the window closes as soon as the pointer leaves or the finger lifts; when locked it stays put, so you can drag it aside and then aim';
	@override String get notDownloaded => 'Not downloaded';
	@override String get pauseResumeAutoScroll => 'Pause / resume auto-scroll';
	@override String get logLabel => 'Log';
	@override String get alignNone => 'No alignment (keep original ratios)';
	@override String get rotationSettings => 'Rotation settings';
	@override String get fileSize => 'File size';
	@override String get pageOrderNatural => 'Natural file-name order (page2 before page10)';
	@override String get fileLabel => 'File';
	@override String get slideshowOffTapStart => 'The slideshow is off: tap to start it';
	@override String get slideshowDwellIndicator => 'Show which page is up and whether it is paused during the slideshow';
	@override String get slideshowOnButIdle => 'The slideshow is on but not ticking: tap to continue';
	@override String get slideshowStoppedAtEnd => 'The slideshow stopped at the chapter end';
	@override String get slideshowPlayingTapPause => 'Playing; tap to pause';
	@override String get slideshowPlaying => 'Playing';
	@override String get slideshowFinished => 'Finished';
	@override String get loupeTooltip => 'Loupe: magnifies a small patch of pixels under the pointer as-is into the side window (checking screentone and edge detail)';
	@override String get loupeEnabled => 'Loupe is on: a small patch of pixels under the pointer is magnified as-is into the side window';
	@override String get loupe => 'Loupe';
	@override String get slideshowAdvanceChapter => 'At chapter end, go on to the next chapter; stop when there is none';
	@override String get slideshowLoopInChapter => 'At chapter end, jump back to the first page and keep playing';
	@override String get slideshowStopAtChapterEnd => 'Stop at the last page of the chapter and turn the slideshow off';
	@override String get inference => 'Inference';
	@override String get onDemandTranslateOcr => 'On-demand inset translation and on-device OCR';
	@override String get detectByFileHeader => 'Detected by file header. PNG, WebP and similar pages stay as-is.';
	@override String get dragReorderStaysOnPage => 'Drag to change the display order; applying keeps you on the current page';
	@override String get openChapterListToDrag => 'Open this chapter\'s page list and drag to reorder (starting from the current order)';
	@override String get perBookAfterOpening => 'Set per book after opening an online or local comic';
	@override String get touchHoldToShow => 'Touch: press and hold to open the window, release to close it (with lock you can drag it)';
	@override String get manualOrderDragList => 'Manual order (drag in the page list)';
	@override String get manualZoom => 'Manual zoom';
	@override String get denoiseDefaultForAll => 'Enable denoise for all comics by default';
	@override String get allBooksDefaultCurrentlyOff => 'Default for all books, currently off; when on, every book without its own setting follows';
	@override String get allBooksDefaultShared => 'Default for all books (the same entry as in the settings page)';
	@override String get hoverFollowsMouse => 'Hover: follows the mouse only and closes when the pointer leaves the page';
	@override String get hoverScroll => 'Hover scroll';
	@override String get restoreDefaultParams => 'Restore default parameters';
	@override String get restoreConservativeDefaults => 'Restore conservative defaults';
	@override String get mimageModelMissingPrompt => 'This device has not downloaded the mImage ONNX upscale model (about 5.4 MB). Download and enable it now?';
	@override String get noImageInfoAvailable => 'No image information available to read right now';
	@override String get noRealPlksrBackendHere => 'This platform has no RealPLKSR inference backend yet';
	@override String get pageAnimationOn => 'Smooth page-turn animation is currently on';
	@override String get pageAnimationOff => 'Page-turn animation is currently off';
	@override String get currentImage => 'Current image';
	@override String get translateOnDeviceNow => 'Using an on-device offline engine right now; translated pages need no network';
	@override String get translateCloudEndpointNow => 'Translating through a cloud API endpoint right now; erases the original bubbles and fills in the translation';
	@override String get force => 'Force';
	@override String get engine => 'Engine';
	@override String get enableAutoScroll => 'Enable auto-scroll';
	@override String get enableBookUpscale => 'Turn on upscaling for this book';
	@override String get slideshow => 'Slideshow';
	@override String get loupeLockedOn => 'Locked: the window stays after the pointer leaves and the finger lifts; drag the window itself to move it; double-tap it to unlock';
	@override String get requeuedToDownload => 'Added back to the download queue';
	@override String get alreadyDisabled => 'Disabled';
	@override String get manualOrderClearedDone => 'Cleared this chapter\'s manual order';
	@override String get slideshowPausedTapResume => 'Paused; tap to resume the slideshow (settings unchanged)';
	@override String get autoScrollEnabled => 'Auto-scroll enabled';
	@override String get trimOnAutoDetect => 'On · white and black edges auto-detected';
	@override String get denoiseOnRealPlksr => 'On · RealPLKSR 1×';
	@override String get switchedToOriginalCompare => 'Switched to the original comparison';
	@override String get switchedBackToProcessed => 'Switched back to the processed image';
	@override String get trimOffFullPage => 'Off · the full page is shown';
	@override String get trimOffOriginalKept => 'Off · original left unchanged';
	@override String get fitWindowLeft => 'Fit to window, aligned left';
	@override String get fitWindowRight => 'Fit to window, aligned right';
	@override String get compareOriginal => 'Compare with the original';
	@override String get widePagePolicy => 'Wide page policy';
	@override String get alignWidth => 'Align width (two pages share one width)';
	@override String get safeMargin => 'Safe margin';
	@override String get processingStatus => 'Processing status';
	@override String get bgToleranceHint => 'Raising it tolerates paper tint and light noise; use a smaller value when pale detail is common';
	@override String get onlineUpscaleAtFetchLayer => 'Online sources: upscaling happens at the fetch/decode layer, so this is the per-book switch (no per-page state)';
	@override String get sharedUpscaleEnlarge => 'Shared by online and local comics; enlarges content while reading';
	@override String get sharedDenoiseThenUpscale => 'Shared by online and local comics; keeps resolution, denoises then upscales';
	@override String get trimSafeMarginKeeps => 'Keeps extra space around detected content to protect text, page numbers and linework';
	@override String get pageOrderSource => 'Source order (as the plugin or archive provides it)';
	@override String get imageProcessing => 'Image processing';
	@override String get readback => 'Read-back';
	@override String get backend => 'Backend';
	@override String get onlyThisBookAskFirst => 'Affects this book only; the model is not downloaded, so it asks first when you enable it';
	@override String get onlyThisBookGlobalOthers => 'Affects this book only; other books follow the global setting';
	@override String get onlyThisComicUpscaleOwn => 'Affects this comic only; upscaling has its own switch';
	@override String get twoPagesIndependent => 'Two pages independent';
	@override String get twoPageModeTap => 'Two-page mode (tap for single page)';
	@override String get twoPages => 'Two pages';
	@override String get originalSize => 'Original size';
	@override String get comparingOriginal => 'Comparing with the original';
	@override String get singlePageModeTap => 'Single page mode (tap for two pages)';
	@override String get singlePage => 'Single page';
	@override String get trimSideLimit => 'Max trim per side';
	@override String get animatedNotProcessed => 'Animated pages are not processed. Model strength is fixed; original, denoised and upscaled results are cached separately.';
	@override String get animated => 'Animated';
	@override String get toggleReaderFilter => 'Toggle the reading filter and eye-comfort overlay';
	@override String get resolution => 'Resolution';
	@override String get blockLabel => 'Blocks';
	@override String get disableAutoScroll => 'Turn off auto-scroll';
	@override String get disableAutoRotate => 'Turn off auto-rotate';
	@override String get disableBookUpscale => 'Turn off upscaling for this book';
	@override String get wholeBook => 'Whole book';
	@override String get panoramaMode => 'Panorama mode';
	@override String get pageOrderReversed => 'Reversed (the whole chapter page list flipped)';
	@override String get scaleLabel => 'Scale';
	@override String get notWiredBelow => 'Not yet wired into this repo';
	@override String get jpegPagesOnly => 'Processes JPEG pages only';
	@override String get peekOriginalBriefly => 'Briefly view the original; the processed result returns when it closes';
	@override String get peekBackToOriginal => 'Temporarily switch back to the original; the processed result returns when it closes';
	@override String get denoiseBlockIndependentHint => 'Independent of upscaling. Smaller blocks cut inference memory; fixed-input models use their own size';
	@override String get denoiseOriginalSafeBefore => 'Originals untouched; denoise runs before upscaling';
	@override String get denoiseOriginalSafeBookOverride => 'Originals untouched; the per-book switch can still override it in reader settings';
	@override String get downloadPreference => 'Download preference';
	@override String get downloadAiUpscaleModel => 'Download AI upscale model';
	@override String get rotateAlwaysLeft => 'Always rotate left';
	@override String get rotateAlwaysRight => 'Always rotate right';
	@override String get ocrWeightsReady => 'OCR weights ready';
	@override String get neoviewViewportDemo => 'NeoView viewport-aware interaction sketch';
	@override String get denoiseModelMissing => 'JPEG denoise model not installed';
	@override String get aiSuperResolution => 'AI super-resolution';
	@override String get downloadManage => 'Download Manager';
	@override String get startDownload => 'Start Download';
	@override String get pauseDownload => 'Pause Download';
	@override String get resumeDownload => 'Resume Download';
	@override String get restartDownload => 'Restart Download';
	@override String get deleteDownload => 'Delete Download';
	@override String get retryFailedParts => 'Retry Failed Parts';
	@override String get retryFailedPartsSubtitle => 'Only redownload incomplete or failed chapters and images';
	@override String get restartDownloadSmart => 'Incremental (Recommended)';
	@override String get restartDownloadSmartDesc => 'Check local downloaded files and only download missing or failed images';
	@override String get restartDownloadFull => 'Full Redownload';
	@override String get restartDownloadFullDesc => 'Reset all chapters and download everything from scratch';
	@override String get pickAndExtract => 'Pick & Extract';
	@override String get pickAndExtractSubtitle => 'Select specific images to export or save';
	@override String get saveToAlbum => 'Save to Photos';
	@override String get saveToDirectory => 'Export to Folder';
	@override String get exportZip => 'Export as ZIP';
	@override String get downloadSelected => 'Download Selected';
	@override String get selectAll => 'Select All';
	@override String get deselectAll => 'Deselect All';
	@override String get invertSelection => 'Invert Selection';
	@override String get rangeSelect => 'Range Select';
	@override String get rangeSelectPrompt => 'Enter page range, e.g. 1-5, 8, 12';
	@override String selectedCount({required Object selected, required Object total}) => 'Selected ${selected} / ${total} pages';
	@override String extractingProgress({required Object current, required Object total}) => 'Processing: ${current} / ${total}';
	@override String get extractSuccess => 'Extraction completed';
	@override String extractFailed({required Object error}) => 'Extraction failed: ${error}';
	@override String get viewAllTasks => 'View All Tasks';
	@override String get downloadStatusDownloading => 'Downloading';
	@override String get downloadStatusPaused => 'Paused';
	@override String get downloadStatusCompleted => 'Completed';
	@override String get downloadStatusFailed => 'Failed';
	@override String get downloadStatusQueued => 'Queued';
	@override String get confirmDeleteDownloadTitle => 'Delete Download';
	@override String get confirmDeleteDownload => 'Are you sure you want to delete this comic\'s download task and local files?';
	@override String get downloadStartedToast => 'Download started for this comic';
	@override String get autoCollectedToast => 'Added to collection';
	@override String get readWhileDownloading => 'Download while reading';
	@override String get readWhileDownloadingSubtitle => 'Automatically save read content to local download directory';
	@override String get pageMode => 'Page turn mode';
	@override String get fullscreen => 'Fullscreen';
	@override String get leftHandMode => 'Left-hand mode';
	@override String get rightHandMode => 'Right-hand mode';
	@override String get reverseHorizontalPageTurn => 'Reverse arrow keys';
	@override String get reverseHorizontalPageTurnSubtitle => 'Swap left/right arrow keys for page turning, useful for right-to-left manga';
	@override String get webtoonTapPageTurn => 'Webtoon tap navigation';
	@override String get enableWebtoonTapPageTurn => 'Allow tapping to turn vertically';
	@override String get webtoonTapPageTurnSubtitle => 'Tap the upper/lower area in webtoon mode; the center still opens the controls';
	@override String get readingMode => 'Reading mode';
	@override String get perComicReadMode => 'Enable per-comic settings';
	@override String get perComicReadModeSubtitle => 'Only applies to the current comic';
	@override String get perComicFollowGlobal => 'Follow global';
	@override String get perComicGlobalIs => 'Global is';
	@override String get perComicThisComic => 'This comic';
	@override String get infoDisplay => 'Info display';
	@override String get pageNumber => 'Page number';
	@override String get pageNumberSubtitle => 'Show current/total page count';
	@override String get networkStatus => 'Network status';
	@override String get networkStatusSubtitle => 'May be inaccurate on Linux';
	@override String get battery => 'Battery';
	@override String get time => 'Time';
	@override String get verticalPositionTop => 'Top';
	@override String get verticalPositionBottom => 'Bottom';
	@override String get horizontalPositionLeft => 'Left';
	@override String get horizontalPositionCenter => 'Center';
	@override String get horizontalPositionRight => 'Right';
	@override String get readingDirectionLtr => 'Left to right';
	@override String get readingDirectionRtl => 'Right to left';
	@override String get readingDirectionVertical => 'Top to bottom';
	@override String get webtoon => 'Webtoon';
	@override String get singlePageRow => 'Single page (horizontal)';
	@override String get readingDirectionLeftOpen => 'Left-opening · next page on the left';
	@override String get readingDirectionRightOpen => 'Right-opening · next page on the right';
	@override String get readingDirectionToggle => 'Reading direction';
	@override String get readingDirectionToggleLeftOpen => 'Left-opening now (next page on the left) · tap for right-opening';
	@override String get readingDirectionToggleRightOpen => 'Right-opening now (next page on the right) · tap for left-opening';
	@override String get readingDirectionToggleDisabled => 'Webtoon mode has no horizontal reading direction';
	@override String get readingDirectionToggleSetting => 'Show reading direction toggle in top bar';
	@override String get swipePreview => 'Page-turn preview';
	@override String get swipePreviewSubtitle => 'Show the actual image on both sides while turning, instead of a large page-number placeholder (decodes one extra viewport-width bitmap per page)';
	@override String get doublePage => 'Double page';
	@override String get doublePageSubtitle => 'Enable double-page spread in current reading mode';
	@override String get doublePageSeamless => 'Seamless double page';
	@override String get doublePageSeamlessSubtitle => 'Give each page half the width, preserve its aspect ratio, and remove the gap between them';
	@override String get doublePageLeadingBlank => 'Leading blank';
	@override String get doublePageLeadingBlankSubtitle => 'Insert a blank page at the start of each chapter to shift page pairing';
	@override String get splitLandscapePages => 'Split landscape pages';
	@override String get splitLandscapePagesSubtitle => 'Automatically split wide double-page images into left and right halves';
	@override String get landscapeSplitDirection => 'Split reading order';
	@override String get splitDirectionAuto => 'Follow reading direction';
	@override String get splitDirectionLtr => 'Left to right (left first)';
	@override String get splitDirectionRtl => 'Right to left (right first)';
	@override String get hoverReveal => 'Hover Reveal';
	@override String get hoverRevealEnabled => 'Edge Hover Reveal Toolbars';
	@override String get hoverRevealEnabledSubtitle => 'Automatically show toolbars when mouse moves to top or bottom edge (NeoView style)';
	@override String get thumbnailStrip => 'Bottom thumbnail strip';
	@override String get thumbnailStripSubtitle => 'Expand per-page thumbnails in the control bar, fused with the progress bar; stays on across books, chapters and restarts';
	@override String get transparentTopBar => 'Transparent top bar';
	@override String get transparentTopBarSubtitle => 'Drop the glass material for a translucent scrim so the page shows through (JHenTai style)';
	@override String get transparentTopBarOpacity => 'Top bar scrim opacity';
	@override String get thumbnailStripExpand => 'Show thumbnails';
	@override String get thumbnailStripCollapse => 'Hide thumbnails';
	@override String get thumbnailStripOriginalAspectRatio => 'Use original thumbnail proportions';
	@override String get thumbnailStripOriginalAspectRatioSubtitle => 'Off: uniform portrait thumbnails. On: show each image fully at its original proportions';
	@override String get thumbnailStripCurrent => 'Now';
	@override String thumbnailStripJumpToPage({required Object page}) => 'Jump to page ${page}';
	@override String get hoverRevealTop => 'Top Edge Reveals Header';
	@override String get hoverRevealBottom => 'Bottom Edge Reveals Footer';
	@override String get hoverTriggerAreaTop => 'Top Trigger Area Height';
	@override String get hoverTriggerAreaBottom => 'Bottom Trigger Area Height';
	@override String get hoverHideDelay => 'Auto Hide Delay on Leave';
	@override String get hoverShowVisualIndicator => 'Show Edge Sensing Indicator';
	@override String get hoverShowVisualIndicatorSubtitle => 'Display a subtle indicator line in the trigger area to preview sensing bounds';
	@override String get hoverAreaPreview => 'Trigger Area Preview (NeoView style)';
	@override String get hoverAreaTopHint => 'Top sensing area: {height}px';
	@override String get hoverAreaBottomHint => 'Bottom sensing area: {height}px';
	@override String get pinTopBar => 'Pin the top bar (stops auto-hide)';
	@override String get unpinTopBar => 'Unpin the top bar';
	@override String get pinBottomBar => 'Pin the bottom bar (stops auto-hide)';
	@override String get unpinBottomBar => 'Unpin the bottom bar';
	@override String get landscapeReader => 'Landscape reading';
	@override String get landscapeReaderSubtitle => 'Switch to landscape while reading and restore the previous direction when you leave';
	@override String get themeMode => 'Theme mode';
	@override String get autoRead => 'Auto read';
	@override String get autoReadSubtitle => 'Automatically scroll the reader';
	@override String get autoReadHidePauseButton => 'Hide pause button';
	@override String get autoReadHidePauseButtonSubtitle => 'Keep auto-read running without showing the pause/play button';
	@override String get autoReadSmooth => 'Smooth scroll';
	@override String get autoReadSmoothSubtitle => 'Continuous scroll in webtoon mode; off uses interval jumps';
	@override String get webtoonScrollDistance => 'Webtoon scroll distance';
	@override String get webtoonScrollInterval => 'Webtoon scroll interval';
	@override String get singlePageScrollInterval => 'Single page scroll interval';
	@override String get preload => 'Preload';
	@override String get preloadImageCount => 'Preloaded image count';
	@override String get preloadImageCountSubtitle => 'Download images after the current reading position in advance';
	@override String get preloadChapterCount => 'Preloaded chapter count';
	@override String get preloadChapterCountSubtitle => 'Load following chapter information in advance';
	@override String get background => 'Background';
	@override String get auto => 'Auto';
	@override String get black => 'Black';
	@override String get white => 'White';
	@override String get grey => 'Grey';
	@override String get adaptive => 'Adaptive';
	@override String get adaptiveEdge => 'Edge gradient';
	@override String get ambientDim => 'Background dimming';
	@override String get ambientDimSubtitle => 'Dim the colour sampled from the page before using it as the backdrop; higher is easier on the eyes. Local comics only';
	@override String get readingExperience => 'Reading experience';
	@override String get keyboardPageTurnSpeed => 'Continuous page turn speed';
	@override String get keyboardPageTurnSpeedSubtitle => 'In horizontal reading, pressing turns one page immediately. Holding a page turn key then repeats at this speed. Animation adapts to the speed; releasing only finishes the current turn. Each turn advances one spread in double-page mode.';
	@override String get pagesPerSecond => 'pages/s';
	@override String get keyboardPageTurnAdvanced => 'Advanced key hold options';
	@override String get keyboardPageTurnHoldDelay => 'Hold start delay';
	@override String get keyboardPageTurnHoldDelaySubtitle => 'How long to hold a key before continuous page turning starts. This only changes the initial wait; pages/s controls the continuous speed.';
	@override String get disableAnimation => 'Disable page animation';
	@override String get disableAnimationSubtitle => 'Disable full-page turn animation';
	@override String get readFilter => 'Read filter (dark mode only)';
	@override String get readFilterSubtitle => 'Only effective in reader, reduces brightness at night';
	@override String get filterIntensity => 'Filter intensity';
	@override String get einkOptimization => 'E-ink optimization (landscape)';
	@override String get einkOptimizationSubtitle => 'Show white screen before image after page turn';
	@override String get einkDelay => 'White screen duration';
	@override String get sidePadding => 'Side padding';
	@override String get sidePaddingSubtitle => 'Customize left/right padding ratio';
	@override String get sidePaddingPercent => 'Padding per side';
	@override String get batterySubtitle => 'Off by default, enable as needed';
	@override String get timeSubtitle => 'Show current time';
	@override String get infoBarPosition => 'Info bar position';
	@override String get showInStatusBar => 'Show in status bar';
	@override String get showInStatusBarSubtitle => 'Top info bar enters system status bar area';
	@override String get edgePadding => 'Edge padding';
	@override String get infoBarStyle => 'Info bar style';
	@override String get backgroundOpacity => 'Background opacity';
	@override String get fontSize => 'Font size';
	@override String get allHiddenNotice => 'All hidden, info bar will be completely hidden';
	@override String get edgePaddingDisabled => 'Edge padding has no effect when horizontally centered';
	@override String get bottomProgressBar => 'Bottom progress bar';
	@override String get bottomProgressBarSubtitle => 'Draw a thin always-on bar at the bottom edge of the page. It stays while the top/bottom bars are hidden, and is independent of the info pill';
	@override String get bottomProgressBarGlow => 'Progress bar glow';
	@override String get bottomProgressBarGlowSubtitle => 'Add a halo to the part already read';
	@override String get settings => 'Reader settings';
	@override String get previousChapter => 'Previous chapter';
	@override String get nextChapter => 'Next chapter';
	@override String get backToHome => 'Back to home';
	@override String get jumpToChapterTitle => 'Jump';
	@override String jumpToChapterMessage({required Object chapter}) => 'Jump to ${chapter}?';
	@override String get selectChapter => 'Select chapter';
	@override String get enterFullscreen => 'Fullscreen (F11)';
	@override String get exitFullscreen => 'Exit fullscreen';
	@override String get chapterTransition => 'Chapter transition';
	@override String get transitionSwipeToLoad => 'Swipe to load';
	@override String get transitionLoaded => 'Load complete';
	@override String get transitionLoadFailedRetry => 'Load failed, tap to retry';
	@override String get pullDownToPrevChapter => 'Pull down to previous chapter';
	@override String get releaseToJumpPrevChapter => 'Release to jump to previous chapter';
	@override String get releaseToLoadPrevChapter => 'Release to load previous chapter';
	@override String get pullUpToNextChapter => 'Pull up to next chapter';
	@override String get releaseToJumpNextChapter => 'Release to jump to next chapter';
	@override String get releaseToLoadNextChapter => 'Release to load next chapter';
	@override String get chapterNotDownloaded => 'Chapter not downloaded';
	@override String loadFailedWithResult({required Object result}) => '${result}\nLoad failed';
	@override String chapterOrder({required Object order}) => 'Chapter ${order}';
	@override String get doubleTapAction => 'Double-tap action';
	@override String get doubleTapZoom => 'Double-tap zoom';
	@override String get doubleTapZoomSubtitle => 'Double-tap image to toggle zoom';
	@override String get doubleTapOpenMenu => 'Double-tap to open menu';
	@override String get doubleTapOpenMenuSubtitle => 'Double-tap page to open menu (exclusive with zoom)';
	@override String get centerTapBar => 'Tap to reveal bars';
	@override String get centerTapToggleBars => 'Tap center to toggle top/bottom bars';
	@override String get centerTapToggleBarsSubtitle => 'When off, tapping the reader no longer shows or hides the top/bottom bars (in webtoon mode this covers tap-anywhere too). Reveal them with edge hover on desktop or a double tap instead.';
	@override String get volumeKeyPageTurn => 'Volume key page turn';
	@override String get enableVolumeKeyPageTurn => 'Enable volume key page turn';
	@override String get volumeKeyPageTurnSubtitle => 'Use volume keys to turn pages/scroll';
	@override String get screenHeightPercent => '% screen height';
	@override String get milliseconds => 'ms';
	@override String get percent => '%';
	@override String get pixels => 'px';
	@override String get gesture => 'Gestures & Hover';
	@override String get infoBar => 'Info Bar';
	@override String get tabRead => 'Reading';
	@override String get tabGesture => 'Gestures';
	@override String get tabScreen => 'Interface';
	@override String get tabPicture => 'Picture';
	@override String get tabTranslate => 'Translate';
	@override String get chromeSection => 'Bars & margins';
	@override String get tuningSection => 'Picture tuning';
	@override String get autoTrimMargins => 'Auto-trim margins';
	@override String get autoTrimMarginsSubtitle => 'Detect each page\'s content area and zoom to it; original pixels untouched';
	@override String get pauseAutoRead => 'Pause auto read';
	@override String get resumeAutoRead => 'Resume auto read';
	@override String imageLoadFailedRetry({required Object error}) => '${error}\nLoad failed, tap to retry';
	@override String imageSavedTo({required Object path}) => 'Image saved to: ${path}';
	@override String get imageSavedToAlbum => 'Image saved to album';
	@override String get imageSaveFailed => 'Image save failed';
	@override String get saveImagePermissionDenied => 'Save failed: please grant album access in settings';
	@override String imageSaveFailedWithError({required Object error}) => 'Save failed: ${error}';
	@override String get radialMenuHint => 'Release to run · centre or Esc to cancel';
	@override String get radialMenuHintMove => 'Move to choose';
	@override String get radialMenuHintRelease => 'Release to run';
	@override String get radialMenuHintSwitch => 'Release to switch wheel';
	@override String get singlePageLtr => 'Left to right';
	@override String get singlePageRtl => 'Right to left';
}

// Path: plugin
class _Translations$plugin$en_US extends Translations$plugin$zh_CN {
	_Translations$plugin$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get getInfoJsonBadFormat => 'getInfoJson returned malformed data';
	@override String get getInfoBadFormat => 'getInfo returned malformed data';
	@override String get badResponseFormat => 'The plugin returned a malformed response';
	@override String get advancedCapabilityLoading => 'Loading advanced capabilities...';
	@override String get store => 'Plugin Store';
	@override String get searchHint => 'Search plugin name or author...';
	@override String get localInstall => 'Local install';
	@override String get networkInstall => 'Network install';
	@override String get cloudComponents => 'Cloud components';
	@override String get restrictedSourceBlocked => 'This source is not available. Enable "Full source list" in Settings → Content & Network first';
	@override String restrictedSourcesHidden({required Object count}) => '${count} source(s) hidden';
	@override String get loginSuccess => 'Please complete login in the browser, the host will sync cookies automatically';
	@override String get chromiumFallbackUnsupported => 'External Chromium auto-login fallback is not supported on this platform';
	@override String get switchingToExternalBrowser => 'Built-in WebView login is limited, switching to external browser...';
	@override String get chromiumNotFound => 'No Chromium browser detected, please install Chrome first';
	@override String browserSwitched({required Object browser}) => 'Switched to ${browser}, cookies will be synced automatically after login';
	@override String invalidLink({required Object url}) => 'Invalid link: ${url}';
	@override String cannotOpenLink({required Object url}) => 'Cannot open link: ${url}';
	@override String readLocalPluginFailed({required Object error}) => 'Failed to read local plugin: ${error}';
	@override String unsupportedLocalFileType({required Object fileName}) => 'Unsupported local file type, only .js / .cjs / .br are supported: ${fileName}';
	@override String get addFromNetwork => 'Add plugin from network';
	@override String get urlCannotBeEmpty => 'URL cannot be empty';
	@override String get startInstall => 'Start install';
	@override String pluginSettingsTitle({required Object name}) => '${name} settings';
	@override String get debugConfigUpdated => 'Plugin debug config updated';
	@override String get deletePlugin => 'Delete plugin';
	@override String get confirmDeletePlugin => 'Delete this plugin? This will delete plugin and related data.';
	@override String deleteFailed({required Object error}) => 'Delete failed: ${error}';
	@override String get pluginDeleted => 'Plugin deleted';
	@override String executeFailed({required Object error}) => 'Execute failed: ${error}';
	@override String get deletePluginSubtitle => 'Delete plugin and related data permanently';
	@override String get debugMode => 'Debug mode';
	@override String get debugAddress => 'Debug address';
	@override String get accountLoginSubtitle => 'Go to login';
	@override String get accountLogin => 'Account login';
	@override String get pluginDetail => 'Plugin detail';
	@override String get pluginDetailSubtitle => 'View description and homepage';
	@override String get pluginSettings => 'Plugin settings';
	@override String get noUserInfo => 'No user info';
	@override String get operations => 'Operations';
	@override String get management => 'Plugin management';
	@override String get installed => 'Installed';
	@override String get notInstalled => 'Not installed';
	@override String get update => 'Update';
	@override String get install => 'Install';
	@override String get uninstall => 'Uninstall';
	@override String get author => 'Author';
	@override String get version => 'Version';
	@override String get description => 'Description';
	@override String get repo => 'Repository';
	@override String get homepage => 'Homepage';
	@override String get githubRepo => 'GitHub Repo';
	@override String get download => 'Download';
	@override String get downloadUpdate => 'Download update';
	@override String get noCloudPlugins => 'No cloud components';
	@override String get noMatchingPlugins => 'No matching plugins';
	@override String get networkInstallHint => 'Enter plugin script URL';
	@override String cloudPluginsLoadFailed({required Object error}) => 'Failed to load cloud components: ${error}';
	@override String installingFromCloud({required Object name}) => 'Downloading and installing ${name}...';
	@override String get installingFromLocal => 'Installing local plugin...';
	@override String get installingFromNetwork => 'Downloading network plugin...';
	@override String cloudDownloadFailed({required Object error}) => 'Cloud download failed: ${error}';
	@override String networkDownloadFailed({required Object error}) => 'Network plugin download failed: ${error}';
	@override String get remoteAssetNotFound => 'Remote plugin file not found (404). It may have been removed or the version updated. Please check the update URL or retry later';
	@override String get githubRateLimited => 'GitHub access is rate limited (likely IP-based). Please retry later or switch networks; a truly missing plugin still reports 404';
	@override String get remoteReturnedWebPage => 'Remote returned a web page instead of a plugin file. The remote file may be missing or the link expired. Please check the plugin update URL';
	@override String get remoteEmptyResponse => 'Remote returned empty content. Please retry later or check the update URL';
	@override String remoteAccessDenied({required Object status}) => 'Remote access denied (HTTP ${status}). Please check your network or retry later';
	@override String remoteServerError({required Object status}) => 'Remote server error (HTTP ${status}). Please retry later';
	@override String remoteHttpError({required Object status}) => 'Remote request failed (HTTP ${status}). Please retry later';
	@override String get downloadedScriptInvalid => 'Downloaded file is not a valid plugin script (looks like a web or error page). Please verify the remote file exists and retry';
	@override String get downloadedScriptCorrupted => 'Downloaded plugin file is corrupted or failed to decompress. Please retry later';
	@override String get networkUnstableRetry => 'Unstable network, download failed. Please check your connection and retry';
	@override String cloudVersion({required Object version}) => 'Cloud ${version}';
	@override String localVersion({required Object version}) => 'Local ${version}';
	@override String loginTitle({required Object name}) => '${name} Login';
	@override String get cookieSynced => 'Login cookie synced';
	@override String get executeSuccess => 'Executed successfully';
	@override String get userInfoTitle => 'User info';
	@override String get userInfoLoadFailed => 'Failed to load user info';
	@override String get unnamedAction => 'Unnamed action';
	@override String get pluginSettingsLoading => 'Loading plugin settings...';
	@override String get pluginSettingsLoadFailed => 'Failed to load plugin settings';
	@override String get actionNotExecutable => 'Action not executable: missing fnPath';
	@override String get saved => 'Saved';
	@override String get close => 'Close';
	@override String get sync => 'Sync';
	@override String get syncSubtitle => 'Check and update via npm / updateUrl';
	@override String get syncing => 'Syncing plugin...';
	@override String get syncSuccess => 'Sync successful';
	@override String syncFailed({required Object error}) => 'Sync failed: ${error}';
	@override String get updateSubtitle => 'Manually reinstall this plugin from a network URL or local file';
	@override String get updateFromNetwork => 'Install from network';
	@override String get updateFromLocal => 'Install from local';
	@override String get updateChooseSource => 'Choose install method';
	@override String get updating => 'Updating plugin...';
	@override String get updateSuccess => 'Update successful';
	@override String updateFailed({required Object error}) => 'Update failed: ${error}';
	@override String get uuidMismatch => 'Plugin id mismatch, install rejected';
	@override String currentVersion({required Object version}) => 'Current version ${version}';
	@override String get alreadyLatest => 'Already up to date';
}

// Path: gestureLock
class _Translations$gestureLock$en_US extends Translations$gestureLock$zh_CN {
	_Translations$gestureLock$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get gestureTitle => 'Gesture unlock';
	@override String get gestureHint => 'Draw gesture password';
	@override String get pinTitle => 'Enter PIN';
	@override String get pinHint => 'Enter reset PIN';
	@override String get atLeast4Points => 'Connect at least 4 points';
	@override String get confirmGesture => 'Please draw again to confirm';
	@override String get gestureNotMatch => 'The two drawings do not match';
	@override String get setSuccess => 'Set successfully';
	@override String get forgotPassword => 'Forgot password';
	@override String get incorrectPassword => 'Incorrect gesture password, please try again';
	@override String get resetPin => 'Reset PIN';
	@override String get pin => 'PIN';
	@override String get pinDescription => 'PIN can reset gesture password. If both are forgotten, you cannot enter the app. Please keep it safe.';
	@override String get pinMinLength => 'PIN must be at least 4 digits';
	@override String get pinNotMatch => 'The two PINs do not match';
	@override String get pinIncorrect => 'Incorrect PIN, please try again';
	@override String get appLocked => 'App is locked';
	@override String get verifyToUnlock => 'Please complete gesture verification';
	@override String get resetGesturePassword => 'Reset gesture password';
	@override String get resetPinHint => 'Enter the reset PIN you saved';
	@override String get passwordCleared => 'Password cleared, please set again';
	@override String get setupHintFirst => 'Please connect at least 4 points';
	@override String get setupHintConfirm => 'Please draw the same gesture again';
	@override String get setupErrorMinPoints => 'Connect at least 4 points';
	@override String get setupErrorMismatch => 'Gestures do not match, please set again';
	@override String get pinHintMinDigits => 'At least 4 digits';
}

// Path: appBootstrap
class _Translations$appBootstrap$en_US extends Translations$appBootstrap$zh_CN {
	_Translations$appBootstrap$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get initializing => 'Initializing....';
	@override String get verifyGesture => 'Please verify gesture password';
	@override String get pinVerifyFailed => 'PIN verification failed';
	@override String get unlockCancelled => 'Unlock cancelled';
	@override String get enteringApp => 'Verification successful, entering app';
}

// Path: comments
class _Translations$comments$en_US extends Translations$comments$zh_CN {
	_Translations$comments$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get retry => 'Retry';
	@override String get noComments => 'No comments yet';
	@override String get loadMore => 'Load more';
	@override String get collapseReplies => 'Collapse replies';
	@override String replyCount({required Object count}) => '${count} replies';
	@override String get noReplies => 'No replies yet';
	@override String get loadMoreReplies => 'Load more replies';
	@override String get postComment => 'Post comment';
	@override String get postCommentHint => 'Enter comment content';
	@override String get postReply => 'Reply';
	@override String get postReplyHint => 'Enter reply content';
	@override String get cancel => 'Cancel';
	@override String get confirm => 'Confirm';
	@override String get postSuccess => 'Posted successfully';
	@override String postFailed({required Object error}) => 'Failed to post: ${error}';
	@override String get anonymous => 'Anonymous';
}

// Path: cache
class _Translations$cache$en_US extends Translations$cache$zh_CN {
	_Translations$cache$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cache settings';
	@override String get currentCache => 'Current cache';
	@override String get clearCache => 'Clear cache';
	@override String get clearCacheConfirm => 'Are you sure you want to clear all cache files? This action cannot be undone.';
	@override String get cleared => 'Cache cleared';
	@override String get clearFailed => 'Clear failed';
	@override String get cacheSize => 'Cache size';
	@override String get recalculate => 'Recalculate';
	@override String get manualClear => 'Manual clear cache';
	@override String get manualClearSubtitle => 'Delete all cache files immediately';
	@override String get clear => 'Clear';
	@override String get cacheLimit => 'Cache limit';
	@override String get sizeLimit => 'Cache size limit';
	@override String get sizeLimitSubtitle => 'Old cache will be automatically cleared when the limit is reached';
	@override String get autoClean => 'Auto clean cache';
	@override String get autoCleanSubtitle => 'Automatically clean old cache when exceeding limit';
	@override String get calculating => 'Calculating...';
	@override String get calculateFailed => 'Calculate failed';
}

// Path: dataBackup
class _Translations$dataBackup$en_US extends Translations$dataBackup$zh_CN {
	_Translations$dataBackup$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Local Import/Export';
	@override String get exportSection => 'Export';
	@override String get importSection => 'Import';
	@override String get includeDownloads => 'Include downloaded comics';
	@override String get includeDownloadsSubtitle => 'Pack downloaded comic files when exporting';
	@override String get exportData => 'Export data';
	@override String get exportDataSubtitle => 'Pack settings and data into zip';
	@override String get importData => 'Import data';
	@override String get importDataSubtitle => 'Restore data from zip file';
	@override String get selectExportDirFailed => 'Failed to select export directory';
	@override String get exporting => 'Exporting, please wait…';
	@override String get exportSuccess => 'Export successful';
	@override String savedTo({required Object path}) => 'Saved to: ${path}';
	@override String get exportShareHint => 'Use the share sheet and choose "Save to Files" to keep the backup.';
	@override String get exportFailed => 'Export failed';
	@override String get processingBackup => 'Processing backup file…';
	@override String get selectBackupFailed => 'Failed to select backup file';
	@override String get readingBackup => 'Reading backup info…';
	@override String get readBackupFailed => 'Failed to read backup';
	@override String get importing => 'Importing, please wait…';
	@override String get importFailed => 'Import failed';
	@override String get importTitle => 'Import data';
	@override String get importConfirm => 'Import will replace backed-up settings and app data. Local paths, proxy, app lock and sync configuration will be kept. Continue?';
	@override String get includesDownloadsWarning => 'This backup contains downloaded comic files. Existing downloads will be deleted before import.';
	@override String get versionMismatch => 'Version mismatch. Data import may have issues. Continue?';
	@override String exportedVersion({required Object version}) => 'Exported version: ${version}';
	@override String currentVersion({required Object version}) => 'Current app version: ${version}';
	@override String get kContinue => 'Continue';
	@override String get importSuccess => 'Import successful';
	@override String get restartPrompt => 'Data imported successfully. Please restart the app to apply.';
}

// Path: webdavSync
class _Translations$webdavSync$en_US extends Translations$webdavSync$zh_CN {
	_Translations$webdavSync$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cloud Sync Config';
	@override String serviceTitle({required Object service}) => '${service} Sync Config';
	@override String get noneTip => 'Please select a sync service in Settings first, then return here to fill in the configuration.';
	@override String get deleteConfig => 'Delete Config';
	@override String get testAndSave => 'Test & Save';
	@override String get faq => 'FAQ';
	@override String get webdavHost => 'WebDAV URL';
	@override String get username => 'Username';
	@override String get password => 'Password';
	@override String get s3Endpoint => 'Endpoint';
	@override String get s3EndpointHint => 'e.g. s3.amazonaws.com';
	@override String get s3AccessKey => 'Access Key';
	@override String get s3SecretKey => 'Secret Key';
	@override String get s3Bucket => 'Bucket Name';
	@override String get s3Region => 'Region (optional)';
	@override String get s3Port => 'Port (optional)';
	@override String get useSsl => 'Use HTTPS/SSL';
	@override String get pathStyle => 'Path-Style';
	@override String get pathStyleSubtitle => 'Self-hosted MinIO usually requires this option';
	@override String get connectingWebdav => 'Connecting to WebDAV server...';
	@override String get webdavConnected => 'WebDAV connected and settings saved.';
	@override String webdavConnectFailed({required Object error}) => 'Connection failed. Please check network or WebDAV address.\n${error}';
	@override String get invalidPort => 'Invalid port. Please enter a number between 0 and 65535.';
	@override String get connectingS3 => 'Connecting to S3 service...';
	@override String get s3Connected => 'S3 connected and settings saved.';
	@override String s3ConnectFailed({required Object error}) => 'Connection failed. Please check S3 configuration.\n${error}';
	@override String get close => 'Close';
	@override String get success => 'Success';
	@override String get error => 'Error';
	@override String get faqMarkdown => '### What can be synced?\n- Currently syncs Bika history, JM favorites, and JM history.\n\n### How to configure WebDAV?\n- Fill in WebDAV URL, username, password, then tap Test & Save.\n\n### How to configure S3?\n- Endpoint examples: `s3.amazonaws.com`, `s3.filebase.com`, `play.min.io`.\n- For self-hosted MinIO, fill in a custom port and disable SSL if necessary.\n\n### How often does auto-sync run?\n- Every 5 minutes.\n\n### How to trigger a manual sync?\n- Tap Test & Save on the sync config page.\n- Or toggle the auto-sync switch in Settings.';
}

// Path: ocr
class _Translations$ocr$en_US extends Translations$ocr$zh_CN {
	_Translations$ocr$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Manga Translation (Finished Pages)';
	@override String get endpointSection => 'Translation endpoint';
	@override String get baseUrl => 'Base URL';
	@override String get baseUrlHint => 'https://api.deepseek.com/v1 or http://127.0.0.1:11434/v1';
	@override String get baseUrlNone => 'Not configured';
	@override String get model => 'Model name';
	@override String get modelHint => 'e.g. deepseek-chat, qwen2.5:14b';
	@override String get apiKey => 'API key';
	@override String get apiKeySubtitle => 'Stored locally only, never exported; leave empty for local Ollama';
	@override String get targetLanguage => 'Target language';
	@override String get glossary => 'Glossary';
	@override String get glossarySubtitle => 'One per line: source=target; changing it re-translates finished pages';
	@override String get glossaryHint => 'トカゲ=stone skink';
	@override String get saved => 'Saved';
	@override String get notConfigured => 'Base URL or model name is missing';
	@override String get epSection => 'Inference backend';
	@override String get ep => 'Inference backend';
	@override String get epSubtitle => 'Measured: both models are slower on CoreML, so CPU is the default';
	@override String epPlan({required Object detect, required Object recognize, required Object inpaint}) => 'Per stage on this machine: detect ${detect} · recognize ${recognize} · inpaint ${inpaint}';
	@override String epPlanUnsupported({required Object ep}) => 'This platform\'s build has no ${ep} — picking it fails as analysis starts; it never silently falls back to CPU';
	@override String get displaySection => 'Finished-page display';
	@override String get displayChoice => 'Display mode';
	@override String get displayChoiceSubtitle => 'Only pages translated afterwards follow the new mode; tap translate again on a page to rebuild it (a dozen seconds each).';
	@override String get displayBaked => 'Bake into the image (replaces upscaling on that page)';
	@override String get displayOverlay => 'Draw as an overlay (text on the erased base)';
	@override String get displayOverlayHint => 'Overlay only paints the text on top of the base; but the base has to be the erased one, so such a page claims the enhanced track and upscaling yields for it. The "every bubble has a flat fill, so no inpaint needed" shortcut has never fired: 0 of 121 boxes across 8 real pages (see ADR-0018 §4).';
	@override String get modelSection => 'Model weights';
	@override String weightsReady({required Object count}) => 'Weights ready (${count} files)';
	@override String weightsMissing({required Object missing}) => 'Missing: ${missing}';
	@override String get download => 'Download weights';
	@override String get downloading => 'Downloading';
	@override String get downloadDone => 'Weights downloaded';
	@override String get downloadFailed => 'Weight download failed';
	@override String get cacheSection => 'Finished-page cache';
	@override String cacheCount({required Object count}) => '${count} finished pages generated';
	@override String get cacheEmpty => 'No finished pages yet';
	@override String get clearCache => 'Clear finished-page cache';
	@override String get clearCacheSubtitle => 'Use after changing the model or the font; original images are untouched';
	@override String get cacheCleared => 'Finished-page cache cleared';
	@override String get logSection => 'Diagnostics';
	@override String get viewLog => 'Translation log';
	@override String get logHint => 'One line per gate for each page: endpoint, inference (with the EP actually used per stage), translation request, typesetting, write, presenter check.';
	@override String get logDialogTitle => 'Manga translation log';
	@override String get logEmpty => 'No translation log yet. Tap translate in the reader, or run Settings → Debug → OCR page smoke, and steps will show up here.';
	@override String get copyLog => 'Copy log';
	@override String get logCopied => 'Translation log copied';
	@override String get openLogLocation => 'Reveal log file';
	@override String get readerHint => 'Tap the translate button in the reader toolbar to switch this page only';
	@override String get chipOff => 'Translate';
	@override String get chipOn => 'Translated';
	@override String get chipOnOverlay => 'Translated · overlay';
	@override String get building => 'Working';
	@override String get failedShort => 'Failed';
	@override String get busyToast => 'This page is still being translated';
	@override String get needWeights => 'Weights are incomplete; download them in Settings';
	@override String get engine => 'Translation engine';
	@override String get engineSubtitle => 'API endpoint bills per token and needs network; Apple system translation runs on-device, free and offline';
	@override String get autoTranslatePage => 'Auto-translate each new page';
	@override String get autoTranslatePageSubtitle => 'A finished page takes 10s+, so leaving this on means waiting on every page. Turning it off only affects later pages; already built pages stay.';
	@override String get engineAppleInstalled => 'Language pack installed — active now (15 blocks measured at ~300 ms)';
	@override String get engineAppleMissing => 'The ja → target translation language pack is not installed. There is no API for an app to download it — install it in System Settings › General › Language & Region, then come back';
	@override String get engineAppleUnsupportedPair => 'The system does not know this language pair; change the target language or use an endpoint';
	@override String get engineAppleUnavailable => 'No system translation on this machine (macOS 15+ / iOS 18+ only)';
	@override String get glossaryIgnoredOnApple => 'System translation has no glossary API: in this mode the glossary is ignored and proper nouns get generic translations';
	@override String get engineHunyuanHint => 'This engine needs a local server first, e.g. llama-server -m Hy-MT2-1.8B-Q4_K_M.gguf --device MTL0 -ngl 99 --port 8080\nSet base URL to http://127.0.0.1:8080/v1 and use the same model name as --model. The glossary takes effect via its native Terminology mode.\nMeasured: 1.8B is enough (~158 ms/line, ~2.4 s/page) — the glossary fixes ヤモリ/危機契約 line by line and 7B is no better at 4x the size. On macOS --device must be MTL0, otherwise llama.cpp silently uses the CPU (4.8x slower).';
}

// Path: realSr
class _Translations$realSr$en_US extends Translations$realSr$zh_CN {
	_Translations$realSr$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String openedUpscaleCache({required Object dir}) => 'No upscale output yet; opened the upscale cache folder: ${dir}';
	@override String openedRecentLocation({required Object output}) => 'Opened the folder holding the latest output: ${output}';
	@override String openFolderFailed({required Object error}) => 'Opening the folder failed: ${error}';
	@override String openFolderUnsupported({required Object dir}) => 'This platform can\'t open folders: ${dir}';
	@override String get coremlModelPhoto => 'Real-ESRGAN x4plus · photo / CG';
	@override String mimageInferenceFailed({required Object error}) => 'mImage ONNX inference failed: ${error}';
	@override String modelUnavailableHint({required Object engine}) => 'Model unavailable: ${engine}. Download it in the upscale settings first.';
	@override String archiveMissingOnnx({required Object file}) => 'Archive is missing the mImage ONNX model ${file}';
	@override String archiveContentMismatch({required Object missing}) => 'Archive contents don\'t meet this engine\'s requirements: ${missing}';
	@override String modelFileNameMismatch({required Object expected, required Object actual}) => 'File name doesn\'t match the current model: expected ${expected}, got ${actual}';
	@override String missingOnnxDownload({required Object file}) => 'Missing mImage ONNX model ${file}; download it in the settings';
	@override String importJsonInvalid({required Object error}) => 'Invalid JSON: ${error}';
	@override String get copyLog => 'Copy log';
	@override String blockInfoDetail({required Object contentSize, required Object blockSize, required Object shrink}) => 'Tiling: content block ${contentSize}×${contentSize}, model input ${blockSize}×${blockSize} (includes ${shrink} px reflection padding); fixed by the model';
	@override String deleteModelConfirmNamed({required Object name}) => 'Delete ${name}? You can download it again if needed.';
	@override String actionFailedDetail({required Object error}) => 'Operation failed: ${error}';
	@override String importConditionSuccess({required Object count}) => 'Successfully imported ${count} conditions';
	@override String get logEmptyText => 'No upscale log yet. Once upscaling runs, inference and replacement are logged here.';
	@override String get upscaleLogCopied => 'Upscale log copied';
	@override String get expandEditor => 'Expand editor';
	@override String get collapseEditor => 'Collapse editor';
	@override String conditionListSummary({required Object total, required Object enabled}) => 'Conditions (${total}, ${enabled} enabled)';
	@override String get conditionNeedsAutoUpscale => 'Enable [Auto upscaling] above first; only then do conditions apply while reading and preloading.';
	@override String get conditionUpscaleSubtitle => 'Dispatch upscale actions and skip rules by image size, path regex and metadata';
	@override String get conditionUpscaleTitle => 'Condition upscaling (neo)';
	@override String get advancedOptionsTitle => 'Advanced upscale options (pre-upscale / log)';
	@override String get ncnnCliDesc => 'Runs the waifu2x / Real-CUGAN ncnn-vulkan executables; mode, scale, concurrency and tiling are set at the bottom of the “Image upscaling” page.';
	@override String get coremlDesc => 'Swift calls Apple CoreML directly and reuses the loaded model.';
	@override String nativeScaleLabel({required Object x}) => 'Native ${x}×';
	@override String get modeCuganQuality => 'Real-CUGAN · quality first';
	@override String get modeWaifuFast => 'waifu2x · speed first';
	@override String get nativeModel => 'Rossi native model';
	@override String get engineSwitchHint => 'Switching reprocesses the current page; each engine keeps its own model choice.';
	@override String get hardwareAcceleration => 'Hardware acceleration';
	@override String get upscaleEngine => 'Upscale engine';
	@override String get preUpscaleHint => 'One page at a time to avoid memory contention; set both to 0 to disable pre-upscaling.';
	@override String pageCount({required Object n}) => '${n} pages';
	@override String get preUpscaleCurrentFirst => 'Pre-upscale (current page first)';
	@override String get enableTta => 'Enable TTA';
	@override String get writeResultCache => 'Write results to cache';
	@override String get enableTile => 'Enable tiling (Tile)';
	@override String get actionUpscaleHit => 'When matched: run upscaling';
	@override String get actionSkipHit => 'When matched: skip upscaling (no processing)';
	@override String get actionSectionTitle => 'Trigger action (Action)';
	@override String get excludePreUpscale => 'Exclude from the pre-upscale queue';
	@override String get matchArchivePath => 'Match paths inside the archive';
	@override String get regexExampleOr => 'or';
	@override String get regexExamplePrefix => 'e.g. ';
	@override String get matchSectionTitle => 'Size and rule matching (Match)';
	@override String get enableThisCondition => 'Enable this condition';
	@override String get conditionEnabledBadge => 'Enabled';
	@override String importSuccessSkipped({required Object imported, required Object skipped}) => 'Imported ${imported} conditions, skipped ${skipped} incompatible ones';
	@override String get importContentEmpty => 'Import content cannot be empty';
	@override String get importJsonSample => '[\n  {\n    "name": "Example condition",\n    ...\n  }\n]';
	@override String get pasteExportedJson => 'Paste the exported JSON array or backup object text:';
	@override String get conditionJsonCopied => 'Condition JSON copied to clipboard';
	@override String get conditionsRestored => 'Default conditions restored';
	@override String get keepAtLeastOneCondition => 'Keep at least one upscale condition';
	@override String conditionCopy({required Object name}) => '${name} (copy)';
	@override String get importLocalHint => 'For local import, pick the mImage ONNX model matching the file name above. After switching, the current page is re-upscaled.';
	@override String get modelNotInstalled => 'Current model not installed; download or import it before use';
	@override String get modelInstalled => 'Current model installed';
	@override String modelRuntime({required Object runtime}) => 'Runtime: ${runtime}';
	@override String get modelDenoiseFixed => 'Denoise: fixed by the model, no separate strength control';
	@override String get modelDenoiseCugan => 'Denoise: Real-CUGAN conservative repair, strength fixed by the model';
	@override String modelScaleNote({required Object scale}) => 'Scale: native ${scale}× (set by the model)';
	@override String get exampleBuiltinHint => 'No page is being read, so the built-in sample is shown; open a comic and expand again to see the current page.';
	@override String exampleSemantics({required Object title, required Object before, required Object after, required Object description}) => '${title} sample. ${before} compared with ${after}. Tap to view full size. ${description}';
	@override String exampleTitleSuffix({required Object title}) => '${title} (sample)';
	@override String get exampleLiveSource => 'Taken from the page you are reading; released as soon as the preview closes.';
	@override String beforeUnchanged({required Object before}) => '${before} (kept as-is)';
	@override String beforeTrimmedShadow({required Object before}) => '${before} (shaded area is what gets trimmed)';
	@override String get loadingTrimResult => 'Reading the current page\'s trim result…';
	@override String get loadingDenoiseResult => 'Reading the current page\'s denoise result…';
	@override String get exampleImageNotReadyRetry => 'The current page image is not ready yet; turn the page or try again shortly';
	@override String previewFailed({required Object error}) => 'Preview failed: ${error}';
	@override String get afterDenoise => 'Denoised';
	@override String get afterTrim => 'Trimmed';
	@override String get exampleDenoiseDesc => 'The same JPEG crop actually processed by RealPLKSR 1×; resolution stays the same. Results vary with the source image.';
	@override String get exampleTrimDesc => 'Removes the surrounding margins so the comic fills more of the screen. The sample image does not change with the settings.';
	@override String get exampleDenoiseTitle => 'Denoise preview';
	@override String get exampleTrimTitle => 'Auto-trim preview';
	@override String get denoiseAttribution => 'From mImageViewer · CC BY 4.0\nDownloaded on first use; installed once size and SHA-256 check out.';
	@override String get retryDownload => 'Retry download';
	@override String get denoiseProgressTooltip => 'Model download progress';
	@override String get denoiseVerifyTooltip => 'Verify model integrity';
	@override String get denoiseSubtitle => 'RealPLKSR · JPEG denoise · 1×';
	@override String get denoiseUpdateFailed => 'Update failed · the installed model still works';
	@override String denoiseInstalled({required Object size}) => 'Model installed · ${size}';
	@override String get denoiseVerifying => 'Verifying model';
	@override String get denoiseMissing => 'Model not installed';
	@override String get denoiseChecking => 'Checking model';
	@override String get modelIncomplete => 'Model is incomplete';
	@override String get modelDownloadDone => 'Model download finished';
	@override String get manualImportUnsupported => 'This platform does not support manual upscale-model import';
	@override String get missingModelDirs => 'Missing model directories (models-pro / models-se etc.)';
	@override String get missingExecutable => 'Missing waifu2x / Real-CUGAN executable';
	@override String missingModelFile({required Object file}) => 'Missing model file ${file}';
	@override String missingModelDir({required Object dir}) => 'Missing model directory ${dir}';
	@override String missingOnnxModel({required Object file}) => 'Missing mImage ONNX model ${file}';
	@override String get previewEnhancedUnreadable => 'The enhanced result can\'t be read right now, so no comparison is shown';
	@override String get previewDenoiseOriginal => 'Denoise not applied · the page shown is still the original';
	@override String get previewDenoiseCompare => 'Denoise applied · compared against the enhanced page the reader shows';
	@override String previewDenoisePending({required Object phase}) => 'Denoise not applied yet · ${phase}';
	@override String get previewDenoiseApplied => 'JPEG denoise applied · RealPLKSR 1×';
	@override String get previewBothApplied => 'Denoise and upscale applied · compared against the enhanced page on screen';
	@override String get previewDenoiseOff => 'This image is not denoised · denoise is off for this comic';
	@override String get previewDenoiseJpegOnly => 'This image is not denoised · only JPEG pages are processed, this one stays as-is';
	@override String trimInsets({required Object left, required Object top, required Object right, required Object bottom}) => 'left ${left} · top ${top} · right ${right} · bottom ${bottom}';
	@override String previewTrimApplied({required Object summary}) => 'Display trim applied · ${summary}';
	@override String get previewTrimNotNeeded => 'This image is not trimmed · nothing to trim, kept as-is';
	@override String get previewTrimPending => 'Trim detection not finished · waiting for the result';
	@override String get previewTrimSplitPage => 'This image is not trimmed · split double pages stay as-is';
	@override String get previewTrimOff => 'This image is not trimmed · auto-trim is off for this comic';
	@override String get tileSizeHint => 'Lower this if it crashes; “Auto” uses the model\'s recommended block size, and a model that declares a fixed input size takes precedence';
	@override String conditionN({required Object index}) => 'Condition ${index}';
	@override String importItemFailed({required Object index, required Object error}) => 'Failed to parse item ${index}: ${error}';
	@override String importSkipNotObject({required Object index}) => 'Skipped item ${index}: entry is not an object';
	@override String get defaultCondition => 'Default condition';
	@override String get engineDesktopNcnn => 'Desktop NCNN (waifu2x / Real-CUGAN)';
	@override String get engineNativeCoreML => 'Rossi native CoreML';
	@override String get modelFast => 'Fast general (Real-ESR General 4x)';
	@override String get modelPhoto => 'Photo / CG (Real-ESRGAN 4x)';
	@override String get modelAnime => 'Illustration / anime (Real-ESRGAN Anime 6B 4x)';
	@override String get modelComic => 'Comic (Real-CUGAN 4x)';
	@override String get modeDenoiseThenUpscale => 'Denoise then upscale';
	@override String get modeUpscaleOnly => 'Upscale only';
	@override String get modeDenoiseOnly => 'JPEG denoise only';
	@override String get modeOriginal => 'Original';
	@override String get deleteCondition => 'Delete condition';
	@override String get lowerPriority => 'Lower priority';
	@override String get raisePriority => 'Raise priority';
	@override String get addCondition => 'Add condition';
	@override String get openImageFolderHint => 'Reveals the most recent upscaled image; opens the upscale cache folder when there is none yet.';
	@override String get openImageFolder => 'Open image folder';
	@override String get viewUpscaleLog => 'View upscale log';
	@override String get upscaleLog => 'Upscale log';
	@override String get downloadNativeModel => 'Download Rossi native model';
	@override String get pagesBefore => 'Pages before:';
	@override String get pagesAfter => 'Pages after:';
	@override String get blockSizeLabel => 'Block size:';
	@override String get outputScaleLabel => 'Output scale:';
	@override String get imagePathRegex => 'Image path regex (imagePathRegex)';
	@override String get bookPathRegex => 'Book path regex (bookPathRegex)';
	@override String get matchAnyOr => 'Any matches (OR)';
	@override String get matchAllAnd => 'All must match (AND)';
	@override String get sizeMatchLogic => 'Size match logic:';
	@override String get maxPixelsMpx => 'Max pixels (MPx)';
	@override String get minPixelsMpx => 'Min pixels (MPx)';
	@override String get maxHeightPx => 'Max height (px)';
	@override String get minHeightPx => 'Min height (px)';
	@override String get maxWidthPx => 'Max width (px)';
	@override String get minWidthPx => 'Min width (px)';
	@override String get conditionName => 'Condition name';
	@override String get applyImport => 'Apply import';
	@override String get importConditions => 'Import condition config';
	@override String get copyToClipboard => 'Copy to clipboard';
	@override String get exportConditions => 'Export condition config (JSON)';
	@override String get resetConditionsContent => 'Restore every condition to its factory default? Existing rules will be cleared.';
	@override String get resetConditions => 'Reset condition upscaling';
	@override String get downloadInBrowser => 'Download in browser';
	@override String get importLocalOnnx => 'Import local ONNX';
	@override String get deleteCurrentModel => 'Delete current model';
	@override String get redownloadCurrentModel => 'Re-download current model';
	@override String get downloadCurrentModel => 'Download current model';
	@override String get customModel => 'Custom upscale model';
	@override String get onnxModel => 'ONNX model';
	@override String get exampleCollapsedHint => 'Collapsed by default; the image loads once expanded';
	@override String get exampleImageNotReady => 'The current page image is not ready yet';
	@override String get closeExample => 'Close example';
	@override String get removeModel => 'Remove model';
	@override String get noOutputYet => 'not generated yet';
	@override String get logWindowTitle => 'Rossi upscale log (this run)';
	@override String get logCategory => 'Upscaling';
	@override String get outputScaleSubtitle => 'Actual scale settings for desktop NCNN models';
	@override String get outputScale => 'Output scale';
	@override String get unnamedCondition => 'Unnamed condition';
	@override String get title => 'Image Super-Resolution (Experimental)';
	@override String get unlimited => 'Unlimited';
	@override String get modelDownloadFailed => 'Model download failed';
	@override String get generalSection => 'General';
	@override String get autoUpscaleSection => 'Auto Upscale';
	@override String get autoUpscale => 'Auto Upscale';
	@override String get autoUpscaleSubtitleUnavailable => 'Model not downloaded; auto upscale will not work';
	@override String get autoUpscaleSubtitleAvailable => 'Automatically upscale when downloading or loading images';
	@override String get conditionSection => 'Condition';
	@override String get resolutionThreshold => 'Resolution Threshold';
	@override String get resolutionThresholdSubtitle => 'Only auto-upscale when image width is below this value';
	@override String get performanceSection => 'Performance';
	@override String get concurrency => 'Concurrency';
	@override String get concurrencySubtitle => 'Higher values suit high-end GPUs; mobile/low-end devices should keep it at 1';
	@override String get tileSize => 'Tile Size';
	@override String get tileSizeSubtitle => 'Set smaller if crashes occur; 0 means no tiling; desktop can try 0';
	@override String get modelSection => 'Model';
	@override String get model => 'Model';
	@override String get modelSubtitle => 'Switching model family resets variant options';
	@override String get noiseLevel => 'Denoise Level';
	@override String get noiseLevelSubtitle => 'This option varies with the selected model';
	@override String get blockInfo => 'Tile Info';
	@override String get blockInfoTooltip => 'blockSize is the model input size including reflection padding;\ncontent block = blockSize - 2×shrinkSize, which is the actual拼接 output region.';
	@override String blockInfoFormat({required Object contentSize, required Object blockSize, required Object shrinkSize}) => 'Content block ${contentSize}×${contentSize}, model input ${blockSize}×${blockSize} (with ${shrinkSize}px reflection padding)';
	@override String get androidSuperResolution => 'Android Super-Resolution';
	@override String get androidSuperResolutionSubtitle => 'Currently uses waifu2x upconv anime model, 2x upscale';
	@override String get androidEngine => 'Upscale engine';
	@override String get androidEngineSubtitle => 'Choose the Android super-resolution backend';
	@override String get androidEngineVulkan => 'Vulkan (waifu2x CLI)';
	@override String get androidEngineVulkanSubtitle => 'ncnn + Vulkan GPU, works on all Android devices';
	@override String get androidEngineQnnNpu => 'NPU (Qualcomm QNN)';
	@override String get androidEngineQnnNpuSubtitle => 'Hexagon HTP NPU inference, Snapdragon 8 series only (experimental)';
	@override String get androidEngineQnnExperimental => 'The NPU backend is experimental: failures keep the original image and surface the reason; no silent fallback to Vulkan';
	@override String get qnnModel => 'NPU model';
	@override String get qnnModelSubtitle => 'Real-CUGAN FP16 model, 2x upscale';
	@override String get qnnModelSeX2NoDenoise => 'Real-CUGAN SE 2x (no denoise)';
	@override String get qnnModelProX2Denoise3x => 'Real-CUGAN Pro 2x (denoise level 3)';
	@override String get qnnProbing => 'Detecting NPU…';
	@override String qnnSupported({required Object arch}) => 'Qualcomm HTP ${arch} detected, NPU available';
	@override String get qnnSupportedSubtitle => 'First use compiles the model context on device (~1-2 s) and caches it';
	@override String get qnnUnsupported => 'NPU unavailable on this device';
	@override String get qnnUnsupportedSubtitle => 'No supported Qualcomm HTP runtime detected (or this build ships without NPU support)';
	@override String qnnUnsupportedArchSubtitle({required Object arch}) => 'HTP ${arch} detected, but this build does not bundle its runtime libraries';
	@override String get qnnIdle => 'Context not prepared';
	@override String get qnnIdleSubtitle => 'Download the model, then tap "Prepare" to compile the NPU context; reading also prepares it automatically';
	@override String get qnnPreparing => 'Compiling NPU context…';
	@override String get qnnReady => 'NPU context ready';
	@override String get qnnFailed => 'NPU context preparation failed';
	@override String get qnnPrepare => 'Prepare';
	@override String get qnnRetry => 'Retry';
	@override String missingQnnModel({required Object file}) => 'Missing NPU model file ${file}';
	@override String get missingQnnManifest => 'Missing NPU model manifest.json';
	@override String get desktopStrategy => 'Upscale Strategy';
	@override String get desktopStrategySubtitle => 'Efficiency priority uses waifu2x; quality priority uses Real-CUGAN';
	@override String get desktopNoiseLevel => 'Denoise Level';
	@override String get desktopNoiseLevelSubtitle => 'Conservative suits normal comics; higher levels produce stronger smearing';
	@override String get modelManagementSection => 'Model Management';
	@override String get downloadingModel => 'Downloading model';
	@override String get modelReady => 'Model ready';
	@override String get redownload => 'Redownload';
	@override String get deleteModel => 'Delete Model';
	@override String get deleteModelConfirm => 'Delete the downloaded super-resolution model? You will need to download it again before use.';
	@override String get modelDeleted => 'Model deleted';
	@override String get modelDeleteFailed => 'Failed to delete model';
	@override String get modelNotDownloaded => 'Model not downloaded';
	@override String get modelNotDownloadedSubtitle => 'Download model before using super-resolution';
	@override String get downloadModel => 'Download Model';
	@override String get manualDownload => 'Manual model download';
	@override String get manualDownloadUnsupported => 'Manual model download is not supported on this platform';
	@override String get openDownloadUrl => 'Open URL';
	@override String get openDownloadUrlFailed => 'Failed to open URL';
	@override String get importModel => 'Import model archive';
	@override String get importModelSubtitle => 'Pick a manually downloaded 7z archive; the format and model content are validated before import';
	@override String get importModelAction => 'Pick file';
	@override String get modelImportSuccess => 'Model imported';
	@override String get modelImportFailed => 'Model import failed';
	@override String get modeEfficiency => 'Efficiency priority';
	@override String get modeQuality => 'Quality priority';
	@override String get noiseConservative => 'Conservative';
	@override String get noise0 => 'No denoise';
	@override String get noise1 => 'Denoise 1';
	@override String get noise2 => 'Denoise 2';
	@override String get noise3 => 'Denoise 3';
	@override String get variantWaifu2xAnime => 'waifu2x upconv anime';
	@override String variantRealCuganDenoise({required Object noise}) => 'Real-CUGAN denoise ${noise}';
	@override String get coremlSpeed => 'Speed priority (waifu2x)';
	@override String get coremlQuality => 'Quality priority (Real-CUGAN)';
	@override String get coremlNoise0 => 'Denoise 0';
	@override String get coremlNoDenoise => 'No denoise';
	@override String get coremlInputHint => 'Enter input image absolute path or asset path';
	@override String get coremlStartUpscale => 'Start upscale';
	@override String get coremlStatusFillInput => 'Please fill in the input image path';
	@override String get coremlStatusNoModelFile => 'No model files available for current family';
	@override String get coremlStatusPreparing => 'Preparing resources...';
	@override String get coremlStatusUpscaling => 'Upscaling...';
	@override String coremlStatusDone({required Object outputPath, required Object size}) => 'Done\n${outputPath}\nsize: ${size} bytes';
	@override String coremlStatusFailed({required Object error}) => 'Failed: ${error}';
	@override String get coremlModelOption => 'Model option (denoise level)';
	@override String get coremlGeneralOption => 'General option (scale)';
	@override String get coremlTileInfo => 'Tile info';
}

// Path: about
class _Translations$about$en_US extends Translations$about$zh_CN {
	_Translations$about$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'About app';
	@override String version({required Object version}) => 'Version: ${version}';
	@override String get loading => 'Loading...';
	@override String get fetchFailed => 'Failed to load';
	@override String get networkError => 'Network error';
	@override String get tagline => 'Cross-platform comic reader';
	@override String get projectAddress => 'Project';
	@override String get projectAddressDesc => 'Like this project? Give it a star on GitHub!';
	@override String get projectLink => 'Go to GitHub repo (HibernalGlow/rossi) ⭐';
	@override String get feedback => 'Feedback';
	@override String get feedbackDesc => 'Found a bug or have a new idea?';
	@override String get feedbackLink => 'Open a GitHub Issue';
	@override String get upstream => 'Upstream';
	@override String get upstreamDesc => 'Rossi continues development on top of Breeze. Thanks to the upstream author and community.';
	@override String get upstreamLink => 'Go to upstream repo (deretame/Breeze)';
	@override String get licenseDesc => 'This project is released under the Mozilla Public License 2.0.';
	@override String get licenseLink => 'Read the full license text';
	@override String get contributors => 'Contributors';
	@override String contributorsCount({required Object count}) => '${count}';
	@override String contributionsTooltip({required Object login, required Object count}) => '${login} (${count} commits)';
	@override String get disclaimer => 'Disclaimer';
	@override String get disclaimerTitle => 'Open Source Disclaimer';
	@override String get disclaimerItem1Title => '1. Nature and Statement';
	@override String get disclaimerItem1Content => 'This project is open-source software, developed and maintained jointly by community contributors. It is provided "as-is". The developer makes no express or implied warranties regarding functionality, stability, security, or fitness for purpose.';
	@override String get disclaimerItem2Title => '2. Limitation of Liability';
	@override String get disclaimerItem2Content => 'The developer shall not be liable for any direct, indirect, special, incidental, or consequential damages arising from use, modification, or distribution of this project (including but not limited to direct use, secondary development, or integration into other projects). These damages may include but are not limited to data loss, device damage, business interruption, lost profits, or other economic losses.';
	@override String get disclaimerItem3Title => '3. User Responsibility';
	@override String get disclaimerItem3Content => 'Users should evaluate suitability and assume all risks when using this project. Users must ensure their use complies with applicable laws, regulations, and ethical standards. The developer is not responsible for consequences resulting from violations of laws or misuse.';
	@override String get disclaimerItem4Title => '4. Third-Party Dependencies and Resources';
	@override String get disclaimerItem4Content => 'This project may depend on or reference third-party libraries, tools, services, or other resources. The developer is not responsible for the content, functionality, security, or legality of these third-party resources. Users should evaluate and assume risks themselves.';
	@override String get disclaimerItem5Title => '5. No Warranty';
	@override String get disclaimerItem5Content => 'The developer expressly disclaims all warranties, including but not limited to: merchantability; fitness for a particular purpose; non-infringement; and error-free or uninterrupted operation.';
	@override String get disclaimerItem6Title => '6. Modification and Termination';
	@override String get disclaimerItem6Content => 'The developer reserves the right to modify, suspend, or terminate this project at any time without prior notice. The developer is not responsible for any consequences arising from such changes.';
	@override String get disclaimerItem7Title => '7. Contributor Responsibility';
	@override String get disclaimerItem7Content => 'External contributors act in their personal capacity and do not represent the project maintainers\' views or positions. The maintainers are not responsible for contributor actions or content.';
	@override String get disclaimerItem8Title => '8. Legal Compliance';
	@override String get disclaimerItem8Content => 'Users must ensure their use complies with applicable laws and regulations. The developer is not responsible for consequences resulting from legal violations.';
	@override String get disclaimerImportant => 'Important Notice';
	@override String get disclaimerImportantContent => 'Please read and understand this disclaimer before using this project. If you do not agree with any term, stop using it immediately. Continued use constitutes acceptance of the entire disclaimer.';
	@override String get checkUpdate => 'Check update';
	@override String get alreadyLatest => 'Already latest version';
	@override String get updateAvailable => 'New version available';
	@override String get license => 'Open source licenses';
	@override String get privacy => 'Privacy policy';
}

// Path: oldHome
class _Translations$oldHome$en_US extends Translations$oldHome$zh_CN {
	_Translations$oldHome$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Home';
	@override String get search => 'Search';
	@override String get hotSearch => 'Hot Search';
	@override String get navigation => 'Navigation';
	@override String get recommend => 'Recommend';
	@override String get latest => 'Latest';
	@override String get cloudFavorite => 'Cloud Favorites';
	@override String get list => 'List';
	@override String get function => 'Function';
	@override String get close => 'Close';
	@override String get loadFailedRetry => 'Load failed, please retry.';
	@override String loadSectionFailed({required Object title, required Object error}) => 'Failed to load ${title}\n${error}';
	@override String get empty => 'No content';
	@override String get loadMoreFailed => 'Failed to load more, tap to retry';
	@override String get loadMore => 'Load more';
	@override String get noMore => 'No more';
}

// Path: more
class _Translations$more$en_US extends Translations$more$zh_CN {
	_Translations$more$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get common => 'Common';
	@override String get others => 'Others';
	@override String get downloadTasks => 'Download Tasks';
	@override String get sync => 'Sync';
	@override String get comicFollow => 'Updates';
	@override String get changelog => 'Changelog';
}

// Path: search
class _Translations$search$en_US extends Translations$search$zh_CN {
	_Translations$search$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Search';
	@override String get searchHint => 'Search...';
	@override String get selectSource => 'Select Source';
	@override String get advancedSearchNotSupported => 'Current plugin does not support advanced search';
	@override String get advancedSearchOptions => 'Advanced Search Options';
	@override String get notSelected => 'Not selected';
	@override String selectedCount({required Object count}) => '${count} selected';
	@override String get history => 'Search History';
	@override String get clearHistory => 'Clear History';
	@override String get newestFirst => 'Current: newest first';
	@override String get oldestFirst => 'Current: oldest first';
	@override String get descending => 'Newest first';
	@override String get ascending => 'Oldest first';
	@override String get noHistory => 'No search history';
	@override String get groupByPluginTooltipOn => 'Grouped by plugin. Tap to merge into one timeline';
	@override String get groupByPluginTooltipOff => 'One merged timeline. Tap to group by plugin';
	@override String get historyGroupAggregate => 'Aggregate search';
	@override String get historyGroupUncategorized => 'Uncategorized';
	@override String get tipsTitle => '🔍 Search Tips';
	@override String get exactSearchTitle => 'Exact search (AND)';
	@override String get exactSearchExample => 'colorful + married';
	@override String get exactSearchDesc => 'Show results containing both keywords';
	@override String get excludeSearchTitle => 'Exclude search';
	@override String get excludeSearchExample => 'colorful - married';
	@override String get excludeSearchDesc => 'Show \'colorful\' results excluding \'married\'';
	@override String get fuzzySearchTitle => 'Fuzzy search (OR)';
	@override String get fuzzySearchExample => 'colorful married';
	@override String get fuzzySearchDesc => 'Show results containing any keyword';
	@override String get selectCategory => 'Select Category';
	@override String get dataSource => 'Data Source';
	@override String get sortBy => 'Sort By';
	@override String get newestToOldest => 'Newest to oldest';
	@override String get oldestToNewest => 'Oldest to newest';
	@override String get mostLikes => 'Most likes';
	@override String get mostViews => 'Most views';
	@override String get selectSourceTooltip => 'Select source';
	@override String get hasResults => 'With results';
	@override String get showErrors => 'Show errors';
	@override String resultCount({required Object count}) => '${count} results';
	@override String get noResults => 'No results';
	@override String loadFailedForSource({required Object source}) => 'Failed to load ${source}';
}

// Path: discover
class _Translations$discover$en_US extends Translations$discover$zh_CN {
	_Translations$discover$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Discover';
	@override String get search => 'Search';
	@override String get settings => 'Settings';
	@override String get pluginManagement => 'Plugin Management';
	@override String get customOrder => 'Custom plugin order';
	@override String get resetOrder => 'Reset order';
	@override String get noPlugins => 'No plugins available. Go to the plugin store to install one~';
	@override String get pluginStore => 'Plugin Store';
	@override String get browseInstall => 'Browse & Install';
	@override String get noPluginForSearch => 'No plugins available, cannot search';
	@override String pluginInfoLoadFailed({required Object error}) => 'Failed to load plugin info: ${error}';
	@override String get pluginCapability => 'Plugin Capability';
	@override String get disabled => 'Disabled';
	@override String get unnamed => 'Unnamed';
	@override String pluginEnableFailed({required Object error}) => 'Failed to enable plugin: ${error}';
	@override String pluginCloseFailed({required Object error}) => 'Failed to disable plugin: ${error}';
	@override String pluginDebugLoadFailed({required Object error}) => 'Plugin debug load failed, reverted to database: ${error}';
	@override String get closeTab => 'Close tab';
	@override String get tabDisplay => 'Tab display';
	@override String get tabShowIcon => 'Show plugin icon';
	@override String get tabShowPluginShort => 'Show plugin short name';
	@override String get tabDoubleClickClose => 'Double-click to close tab';
	@override String get tabCoverMode => 'Cover tab mode';
	@override String get tabCoverModeDesc => 'Display tabs as book covers with information overlay';
	@override String get webPage => 'Web page';
	@override String get comicDetail => 'Details';
}

// Path: searchResult
class _Translations$searchResult$en_US extends Translations$searchResult$zh_CN {
	_Translations$searchResult$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get enterPageNumber => 'Enter page number';
	@override String get pleaseEnterNumber => 'Please enter a number';
	@override String get returnToTop => 'Return to top';
	@override String get jumpToPage => 'Jump to page';
	@override String get jump => 'Jump';
	@override String get retry => 'Tap to retry';
}

// Path: comicList
class _Translations$comicList$en_US extends Translations$comicList$zh_CN {
	_Translations$comicList$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get browseMenu => 'Browse menu';
	@override String currentPage({required Object page}) => 'Page ${page}';
	@override String pageOfTotal({required Object page, required Object total}) => 'Page ${page} of ${total}';
	@override String get jumpToPage => 'Jump to page';
	@override String get pageInput => 'Page number';
	@override String get invalidPage => 'Enter a positive whole number';
	@override String pageOutOfRange({required Object total}) => 'Page cannot exceed ${total}';
	@override String get restorePosition => 'Restore last position';
	@override String restorePage({required Object page}) => 'Last viewed page ${page}';
	@override String get noSavedPosition => 'No saved position yet';
	@override String get positionSavedAutomatically => 'Position is saved automatically after scrolling';
	@override String get previousPage => 'Previous page';
	@override String get nextPage => 'Next page';
	@override String get chineseLocalized => 'CN-localised';
	@override String get downloadedAtLabel => 'Downloaded at';
	@override String get likedArtists => 'Favourite artists';
	@override String get likedTags => 'Favourite tags';
	@override String get defaultTitle => 'Comic List';
	@override String get missingSource => 'Missing plugin source, cannot load list';
	@override String get reload => 'Reload';
	@override String get loadFailedRetry => 'Load failed, please retry.';
	@override String get nothingHere => 'Nothing here';
	@override String get filter => 'Filter';
	@override String get subCategory => 'Subcategory';
	@override String levelCategory({required Object level}) => 'Level ${level}';
	@override String get missingListConfig => 'Missing list request configuration';
	@override String get missingFnPath => 'List request missing fnPath';
}

// Path: comicEntry
class _Translations$comicEntry$en_US extends Translations$comicEntry$zh_CN {
	_Translations$comicEntry$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String seenAtPage({required Object page}) => 'Read up to page ${page}';
	@override String updatedAt({required Object time}) => 'Updated: ${time}';
	@override String get finished => 'Finished';
	@override String get ongoing => 'Ongoing';
	@override String likes({required Object count}) => 'Likes ${count}';
	@override String views({required Object count}) => 'Views ${count}';
	@override String get deleteFavorite => 'Delete Favorite';
	@override String deleteFavoriteConfirm({required Object title}) => 'Delete favorite record for "${title}"?';
	@override String get deleteHistory => 'Delete History';
	@override String deleteHistoryConfirm({required Object title}) => 'Delete history record for "${title}"?';
	@override String get deleteDownload => 'Delete Download';
	@override String deleteDownloadConfirm({required Object title}) => 'Delete download record and files for "${title}"?';
	@override String get deleteFailed => 'Delete failed';
	@override String get translationBadgeTranslated => 'Translated';
	@override String get translationBadgeChinese => 'Chinese';
	@override String get translationBadgeRaw => 'Raw';
	@override String get unread => 'Unread';
	@override String translationTooltipTag({required Object label, required Object keyword}) => '${label} · matched tag "${keyword}"';
	@override String translationTooltipTitle({required Object label, required Object keyword}) => '${label} · matched title "${keyword}"';
	@override String get resumeRead => 'Resume reading';
	@override String get readFailed => 'Could not start reading. Please try again later.';
}

// Path: comicFollow
class _Translations$comicFollow$en_US extends Translations$comicFollow$zh_CN {
	_Translations$comicFollow$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Updates';
	@override String loadFailed({required Object result}) => 'Load failed: ${result}';
	@override String get empty => 'No followed comics';
	@override String get emptyHint => 'Tap the follow button on a comic detail page to add it here';
	@override String get unfollow => 'Unfollow';
	@override String unfollowConfirm({required Object title}) => 'Stop following "${title}"?';
	@override String get unfollowed => 'Unfollowed';
	@override String get all => 'All';
	@override String get unread => 'Updated and unread';
	@override String get sort => 'Sort';
	@override String get lastRead => 'Last read';
	@override String get lastUpdate => 'Latest check';
	@override String checkTime({required Object time}) => 'Check time: ${time}';
	@override String get notRead => 'Not read yet';
	@override String lastReadChapter({required Object chapter}) => 'Read to: ${chapter}';
	@override String latestChapter({required Object count, required Object chapter}) => 'Latest: ${count} / ${chapter}';
	@override String get noUnread => 'No updated unread comics';
	@override String get showAll => 'Show all';
	@override String get latestChapterFailed => 'Failed to get latest chapter';
	@override String newChapters({required Object diff, required Object total}) => '${diff} new chapters, ${total} total';
	@override String newUnreadChapters({required Object diff, required Object total}) => '${diff} new unread chapters, ${total} total';
	@override String latestCount({required Object count}) => 'Latest ${count} chapters';
	@override String get fetchFailed => 'Fetch failed';
	@override String newChaptersShort({required Object diff}) => '${diff} new';
	@override String newUnreadChaptersShort({required Object diff}) => '${diff} unread';
	@override String get update => 'Update';
	@override String get retry => 'Retry';
	@override String readProgress({required Object read, required Object total}) => '${read} of ${total} read';
	@override String readProgressUnknown({required Object total}) => '${total} total';
	@override String get updatedJustNow => 'Just checked';
	@override String updatedMinutesAgo({required Object minutes}) => 'Checked ${minutes} min ago';
	@override String updatedHoursAgo({required Object hours}) => 'Checked ${hours} h ago';
	@override String updatedDaysAgo({required Object days}) => 'Checked ${days} d ago';
	@override String lastReadMinutesAgo({required Object minutes}) => 'Read ${minutes} min ago';
	@override String lastReadHoursAgo({required Object hours}) => 'Read ${hours} h ago';
	@override String lastReadDaysAgo({required Object days}) => 'Read ${days} d ago';
	@override String get checkFailedTapRetry => 'Check failed, tap to retry';
	@override String unreadCountBadge({required Object count}) => '${count} unread';
	@override String get markAllReadHint => 'Mark all as read';
	@override String get markAllReadDone => 'All marked as read';
	@override String get updateChannelName => 'Comic update reminder';
	@override String get updateChannelDesc => 'Pushed when followed comics have new chapters';
	@override String get updateTitle => 'Follow update';
	@override String get updatedComicsSingle => '1 followed comic updated';
	@override String updatedComicsMultiple({required Object count}) => '${count} followed comics updated';
	@override String updateBodyMultiple({required Object count}) => '${count} followed comics have updates';
	@override String get updateBodySingle => '1 followed comic has updates';
}

// Path: changelog
class _Translations$changelog$en_US extends Translations$changelog$zh_CN {
	_Translations$changelog$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Changelog';
	@override String get loadFailed => 'Load failed';
	@override String loadFailedWithError({required Object error}) => 'Load failed: ${error}';
	@override String cannotOpenLink({required Object url}) => 'Cannot open link: ${url}';
	@override String get checkNetwork => 'Load failed, please check network';
	@override String get retry => 'Retry';
	@override String get empty => 'No changelog';
	@override String publishedAt({required Object date}) => 'Published at ${date}';
	@override String get viewInBrowser => 'View in browser';
	@override String get attachments => 'Attachments';
}

// Path: webview
class _Translations$webview$en_US extends Translations$webview$zh_CN {
	_Translations$webview$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Webpage';
	@override String cannotOpenLink({required Object uri}) => 'Cannot open link: ${uri}';
	@override String get invalidLink => 'Invalid link, cannot open webpage';
	@override String get emptyLink => '(empty link)';
	@override String get loadFailed => 'Webpage load failed';
	@override String get retry => 'Retry';
	@override String get openInExternalBrowser => 'Open in external browser';
	@override String get windowClosed => 'WebView window closed';
	@override String get openedInExternalWindow => 'Webpage opened in external window';
	@override String get back => 'Back';
	@override String get closeWindow => 'Close WebView window';
	@override String loadError({required Object error}) => 'Load failed (${error})';
	@override String httpErrorStatus({required Object statusCode}) => 'Server returned abnormal status code: ${statusCode}';
}

// Path: oldRanking
class _Translations$oldRanking$en_US extends Translations$oldRanking$zh_CN {
	_Translations$oldRanking$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get bikaRanking => 'Bika Ranking';
	@override String get jmRanking => 'JM Ranking';
	@override String get switchSource => 'Switch';
}

// Path: login
class _Translations$login$en_US extends Translations$login$zh_CN {
	_Translations$login$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Login';
	@override String get missingPluginId => 'Missing plugin identifier, cannot open login page';
	@override String loadConfigFailed({required Object error}) => 'Failed to load login config: ${error}';
	@override String get insufficientFields => 'Plugin returned insufficient login fields';
	@override String get invalidCredentials => 'Invalid username or password, please try again';
	@override String get configNotReady => 'Login config not ready, please retry later';
	@override String get loggingIn => 'Logging in, please wait...';
	@override String get loginSuccess => 'Login successful';
	@override String get loginFailed => 'Login failed';
	@override String get loginButton => 'Login';
	@override String get retry => 'Retry';
	@override String requiredFieldEmpty({required Object label}) => 'Please fill in ${label}';
	@override String get loginNotSupported => 'This plugin doesn\'t support the new login page yet. Please fill in your account in plugin settings.';
	@override String get captchaTapToRefresh => 'Can\'t see? Tap to refresh';
	@override String get captchaLoading => 'Loading captcha...';
	@override String get captchaLoadFailed => 'Failed to load captcha, tap to retry';
}

// Path: fontSetting
class _Translations$fontSetting$en_US extends Translations$fontSetting$zh_CN {
	_Translations$fontSetting$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Font Settings';
	@override String get clear => 'Clear';
	@override String get hint => 'Pick one default font to apply everywhere; override individual weights only when needed.';
	@override String get modeSystem => 'System default';
	@override String get modeSystemHint => 'Use the app\'s default font stack — no setup needed.';
	@override String get modeFamily => 'Installed font';
	@override String get modeFamilyHint => 'Reference a font already installed in the system by family name (e.g. LXGW WenKai); falls back to system default if not found. Most reliable on desktop.';
	@override String get modeFile => 'Font file';
	@override String get modeFileHint => 'One file for the whole app; bolder weights are synthesized by the system.';
	@override String get familyPickPrompt => 'Pick a font family';
	@override String get familyPickerTitle => 'Choose a system font';
	@override String get familySearchHint => 'Search font families…';
	@override String familyManualUse({required Object name}) => 'Use "${name}"';
	@override String get familyEmpty => 'No matching fonts';
	@override String get familyLoading => 'Reading system fonts…';
	@override String get defaultFont => 'Default font';
	@override String get defaultFontHint => 'One file for the whole app; bolder weights are synthesized by the system.';
	@override String get overrides => 'Weight overrides';
	@override String get overridesHint => 'Optional: assign different files to specific weights; uncovered weights fall back to the nearest configured one.';
	@override String get loadFailed => 'Font load failed';
	@override String get cleared => 'Cleared';
	@override String get saved => 'Saved';
	@override String get allCleared => 'All cleared';
	@override String get noFileSelected => 'No file selected';
	@override String get clearFile => 'Clear';
	@override String get selectFile => 'Select File';
	@override String get sampleText => 'Innovation in China 中国智造，慧及全球 0123456789';
}

// Path: download
class _Translations$download$en_US extends Translations$download$zh_CN {
	_Translations$download$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Download tasks';
	@override String get startDownload => 'Start Download';
	@override String get selectChaptersPrompt => 'Please select chapters to download';
	@override String selectedCount({required Object selected, required Object total}) => '${selected} / ${total} chapters selected';
	@override String downloadedCount({required Object count}) => '${count} chapters already downloaded';
	@override String get skipDownloaded => 'Skip downloaded';
	@override String skippedAlreadyDownloaded({required Object count}) => 'Skipped ${count} chapters already downloaded';
	@override String startedWithSkipped({required Object started, required Object skipped}) => 'Started ${started} chapters, skipped ${skipped} already downloaded';
	@override String get optionsTitle => 'Download this comic';
	@override String get optionWholeBook => 'Whole book';
	@override String optionWholeBookCounted({required Object count}) => 'All ${count} chapters';
	@override String get optionWholeBookPlain => 'Every chapter';
	@override String optionLatest({required Object count}) => 'Latest ${count} chapters';
	@override String get optionLatestSubtitle => 'The newest chapters by chapter order';
	@override String get optionPicker => 'Pick chapters';
	@override String get optionPickerPlain => 'Tick chapters one by one';
	@override String get optionSkipHint => 'Whole book and latest-N skip chapters already on disk';
	@override String get filterAll => 'All';
	@override String get filterNoMatches => 'No tasks match this filter';
	@override String overviewRemaining({required Object count}) => '${count} chapters left';
	@override String overviewPages({required Object done, required Object total}) => '${done}/${total} pages done';
	@override String overviewFailed({required Object count}) => '${count} failed';
	@override String get comicScopeAll => 'All comics';
	@override String comicScopeCounted({required Object name, required Object count}) => '${name} (${count})';
	@override String get taskStarted => 'Download task started';
	@override String taskStartFailed({required Object error}) => 'Failed to start download task: ${error}';
	@override String get noTasks => 'No download tasks';
	@override String get downloading => 'Downloading';
	@override String pending({required Object count}) => 'Pending (${count})';
	@override String failedTasks({required Object count}) => 'Failed (${count})';
	@override String pausedTasks({required Object count}) => 'Paused (${count})';
	@override String get pinTask => 'Prioritize';
	@override String get unpinTask => 'Remove priority';
	@override String get taskPinned => 'Moved to the front of the queue';
	@override String get taskUnpinned => 'Priority removed';
	@override String get taskDeleted => 'Task deleted';
	@override String get deleteLastChapterContent => 'Deleting this chapter will also delete the download record. Continue?';
	@override String get cancelTask => 'Cancel Task';
	@override String cancelTaskConfirm({required Object comicName}) => 'Cancel download of ${comicName}?';
	@override String get paused => 'Paused';
	@override String get completed => 'Completed';
	@override String get failed => 'Failed';
	@override String get startAll => 'Start all';
	@override String get pauseAll => 'Pause all';
	@override String get cancelAll => 'Cancel all';
	@override String cancelAllConfirm({required Object count}) => 'Cancel all ${count} download tasks? Their downloaded chapter images will be deleted too.';
	@override String get clearCompleted => 'Clear completed';
	@override String get viewModeCompact => 'Compact view';
	@override String get viewModeComfortable => 'Full view';
	@override String get statusFetchingComicInfo => 'Fetching comic info...';
	@override String get statusDownloadingCover => 'Downloading cover...';
	@override String get statusFetchingChapterInfo => 'Fetching chapter info...';
	@override String statusFetchingChapterInfoProgress({required Object completed, required Object total, required Object percent}) => 'Fetching chapter info... (${completed}/${total}, ${percent}%)';
	@override String statusDownloadProgress({required Object percent}) => 'Current chapter download progress: ${percent}%';
	@override String get statusDownloadProgressComplete => 'Current chapter download progress: 100%';
	@override String progressPages({required Object completed, required Object total}) => 'Downloaded ${completed}/${total} pages';
	@override String progressPagesWithSpeed({required Object completed, required Object total, required Object speed}) => 'Downloaded ${completed}/${total} pages · ${speed}';
	@override String parallelTaskProgress({required Object count, required Object message}) => '${count} tasks downloading · ${message}';
	@override String get settingsTitle => 'Download settings';
	@override String settingsValueSummary({required Object chapters, required Object images, required Object delayMs}) => '${chapters} chapters · ${images} images each · ${delayMs} ms apart';
	@override String settingsBudgetHint({required Object count}) => 'Up to ${count} images download at once (chapters at once × images per chapter)';
	@override String get offlineTitle => 'Offline comics';
	@override String get offlineEmpty => 'Nothing downloaded yet';
	@override String get offlineMeasureSize => 'Measure size';
	@override String get offlineMeasuring => 'Measuring…';
	@override String offlineTotalSize({required Object size}) => '${size} total';
	@override String offlineChapterCount({required Object completed, required Object total}) => '${completed}/${total} chapters downloaded';
	@override String offlineChapterCountOnly({required Object count}) => '${count} chapters downloaded';
	@override String statusComicProgress({required Object completedChapters, required Object totalChapters, required Object currentChapterCompletedImages, required Object currentChapterTotalImages}) => 'Comic progress: ${completedChapters}/${totalChapters} chapters, current chapter: ${currentChapterCompletedImages}/${currentChapterTotalImages} pages';
	@override String statusComicProgressChaptersOnly({required Object completedChapters, required Object totalChapters}) => 'Comic progress: ${completedChapters}/${totalChapters} chapters';
	@override String get statusStartDownload => 'Start downloading...';
	@override String get statusWaiting => 'Waiting';
	@override String get statusCancelling => 'Cancelling...';
	@override String statusAutoRetrying({required Object seconds, required Object attempt, required Object max}) => 'Network error, retrying automatically in ${seconds} s (${attempt}/${max})...';
	@override String get statusThrottling => 'Rate limited by source, cooling down...';
	@override String get retryFailedParts => 'Retry Failed';
	@override String toastDownloadComplete({required Object comicName}) => '${comicName} download complete';
	@override String toastDownloadFailed({required Object comicName, required Object error}) => '${comicName} download failed ${error}';
	@override String toastTaskAlreadyExists({required Object comicName}) => '${comicName} task already exists';
	@override String get notificationCompleteTitle => 'Download complete';
	@override String get notificationFailedTitle => 'Download failed';
}

// Path: foregroundTask
class _Translations$foregroundTask$en_US extends Translations$foregroundTask$zh_CN {
	_Translations$foregroundTask$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get channelName => 'Foreground task';
	@override String get channelDescription => 'Keeps downloads and the app running in the background';
	@override String get waitingForTask => 'Waiting for download tasks...';
	@override String get keepAliveRunning => 'Keeping the app running in the background';
	@override String get cancel => 'Cancel';
	@override String get notificationPermissionRequired => 'Notification permission is required to start the foreground task, please allow in the system dialog';
	@override String get cannotStartWithoutPermission => 'Cannot start foreground task: please enable notification permission in system settings';
	@override String startFailed({required Object error}) => 'Foreground service start failed: ${error}';
}

// Path: notification
class _Translations$notification$en_US extends Translations$notification$zh_CN {
	_Translations$notification$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get permissionRequired => 'Please enable notification permission';
	@override String get macPermissionRequired => 'Please enable notification permission in system settings';
}

// Path: update
class _Translations$update$en_US extends Translations$update$zh_CN {
	_Translations$update$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get newVersion => 'New version available';
	@override String get goToGitHub => 'Go to GitHub';
	@override String get downloadInstall => 'Download & install';
	@override String get apkDownloadFailed => 'Download failed, please try again later';
	@override String get installPermissionRequired => 'Please grant install app permission';
	@override String get unknownArch => 'Unknown';
}

// Path: dialog
class _Translations$dialog$en_US extends Translations$dialog$zh_CN {
	_Translations$dialog$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get hideOrClose => 'Hide to tray or close app';
	@override String get rememberChoice => 'Remember my choice';
}

// Path: shelfMenu
class _Translations$shelfMenu$en_US extends Translations$shelfMenu$zh_CN {
	_Translations$shelfMenu$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get open => 'Open';
	@override String get resumeReading => 'Resume reading';
	@override String get openInFileManagerTab => 'Open in a new file manager tab';
	@override String get copyTitle => 'Copy title';
	@override String get copyLink => 'Copy link';
	@override String get addFavorite => 'Add to favorites';
	@override String get alreadyFavorite => 'Already in favorites';
	@override String get removeFavorite => 'Remove from favorites';
	@override String get removeHistory => 'Remove from history';
	@override String copiedTitle({required Object title}) => 'Copied title “${title}”';
	@override String copiedLink({required Object link}) => 'Copied link “${link}”';
	@override String get fileManagerTabOpened => 'Opened in a new file manager tab';
	@override String get fileManagerTabUnavailable => 'The file manager panel is not ready yet, try again in a moment';
	@override String get fileManagerTabNoLocalPath => 'This comic has no local folder, so it cannot be opened in the file manager';
	@override String favoriteAdded({required Object title}) => 'Added “${title}” to favorites';
	@override String favoriteRemoved({required Object title}) => 'Removed “${title}” from favorites';
	@override String historyRemoved({required Object title}) => 'Removed “${title}” from history';
	@override String get removeFavoriteConfirmTitle => 'Remove from favorites?';
	@override String removeFavoriteConfirmBody({required Object title}) => '“${title}” will be removed from your favorites. The files and the reading history are untouched.';
	@override String get removeHistoryConfirmTitle => 'Remove from history?';
	@override String removeHistoryConfirmBody({required Object title}) => '“${title}” will be removed from your reading history. The files will not be deleted.';
}

// Path: video
class _Translations$video$en_US extends Translations$video$zh_CN {
	_Translations$video$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get play => 'Play';
	@override String get pause => 'Pause';
	@override String get backward => 'Back 10 s';
	@override String get forward => 'Forward 10 s';
	@override String get loop => 'Loop: next page';
	@override String get loopSingle => 'Loop: repeat page';
	@override String get loopOff => 'Loop: off';
	@override String get speed => 'Speed';
	@override String get volume => 'Volume';
	@override String get muted => 'Muted';
	@override String get subtitles => 'Subtitles';
	@override String get subtitleOff => 'No subtitles';
	@override String get audio => 'Audio track';
	@override String get audioOff => 'Mute track';
	@override String get filters => 'Filters';
	@override String get resetFilters => 'Reset filters';
	@override String get brightness => 'Brightness';
	@override String get contrast => 'Contrast';
	@override String get saturation => 'Saturation';
	@override String get abLoop => 'A-B loop';
	@override String get abClear => 'Clear A-B';
	@override String get screenshot => 'Screenshot';
	@override String get audioOnly => 'Audio only';
	@override String get seekMode => 'Seek mode (page turns seek)';
	@override String get fullscreen => 'Fullscreen';
	@override String get pin => 'Pin controls';
	@override String get info => 'Info';
	@override String get frameStepForward => 'Next frame';
	@override String get frameStepBackward => 'Previous frame';
	@override String get pip => 'Picture in picture';
	@override String get settingsSection => 'Video playback';
	@override String get autoPlay => 'Auto play';
	@override String get autoPlayDesc => 'Start playing when a video page is reached';
	@override String get hwDecode => 'Hardware decoding';
	@override String get hwDecodeDesc => 'Turn off to work around green/torn frames, at the cost of CPU';
	@override String get deinterlace => 'Deinterlace';
	@override String get deinterlaceDesc => 'Enable for interlaced DVD / tape sources with combing';
	@override String get integrateBottomBar => 'Integrate video controls into bottom bar';
	@override String get integrateBottomBarDesc => 'Show playback progress and video controls inside the reader bottom bar';
	@override String get pinDesc => 'Keep the control bar visible instead of hiding it after a few seconds';
	@override String get animatedVideo => 'Play animated images as video';
	@override String get animatedVideoDesc => 'Hand GIF / APNG to the video controller for pause, frame stepping and scrubbing';
	@override String get autoHide => 'Auto-hide controls';
	@override String get maxRate => 'Max playback rate';
	@override String get defaultVolume => 'Default volume';
	@override String get aliases => 'Custom video extensions';
	@override String get aliasesEmpty => 'None';
	@override String get aliasesHint => 'Comma separated, e.g. myvid, cbr-video';
	@override String get aliasesDialogHint => 'Lowercase, at most 128 entries, at most 16 characters each';
	@override String get mediaSection => 'Media formats';
	@override String get imageFormats => 'Image format table';
	@override String get videoFormats => 'Video format table';
	@override String get formatsHint => 'Filling this replaces the built-in table, so suffixes you leave out stop counting as pages at all; leave it empty to keep the defaults';
	@override String get subSize => 'Font size';
	@override String get subBg => 'Background';
	@override String get subBottom => 'Bottom offset';
	@override String get subLargeYellow => 'Large yellow';
	@override String get reset => 'Reset';
	@override String get duration => 'Duration';
	@override String get position => 'Position';
	@override String get size => 'Size';
	@override String get dar => 'Display aspect';
	@override String get fps => 'Frame rate';
	@override String get bitrate => 'Bitrate';
	@override String get videoCodec => 'Video codec';
	@override String get audioCodec => 'Audio codec';
	@override String get avDrift => 'A/V drift';
	@override String get loopMode => 'Loop';
	@override String get playbackRate => 'Rate';
	@override String get abRange => 'A-B';
	@override String get sidecarSubtitles => 'External subtitles';
	@override String get notAvailable => '—';
	@override String get noBytes => 'No bytes available for this video page';
	@override String get cannotPlay => 'This page cannot be played';
	@override String get animatedKeywords => 'Motion keywords';
	@override String get animatedKeywordsHint => 'Comma separated, e.g. [#dyna], [#motion]';
	@override String get rotation => 'Rotation';
}

// Path: bindingEditor
class _Translations$bindingEditor$en_US extends Translations$bindingEditor$zh_CN {
	_Translations$bindingEditor$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get anyArea => 'Any area';
	@override String get migrationFailed => 'The old bindings could not be migrated. Your original configuration is preserved. Export it for inspection or import a valid configuration.';
	@override String get groupNavigation => 'Pages';
	@override String get groupView => 'View';
	@override String get groupInterface => 'Interface';
	@override String get videoPlayback => 'Playback';
	@override String get videoAudio => 'Audio';
	@override String get videoDisplay => 'Picture & subtitles';
	@override String get allActions => 'All';
	@override String get boundOnly => 'Assigned';
	@override String get unassigned => 'Unassigned';
	@override String get spaceKey => 'Space';
	@override String get searchAll => 'Search all actions or keys';
	@override String get disabled => 'Disabled';
	@override String moreBindings({required Object count}) => '${count} more bindings';
	@override String get search => 'Search actions, categories, contexts or inputs';
	@override String get allCategories => 'All categories';
	@override String get allContexts => 'All contexts';
	@override String get noResults => 'No matching actions';
	@override String get addBinding => 'Add binding';
	@override String get noBindings => 'No bindings. Add an input to get started.';
	@override String get device => 'Input device';
	@override String get context => 'Context';
	@override String get ignoreRepeat => 'Ignore repeated input';
	@override String get followUps => 'Follow-up actions';
	@override String get add => 'Add';
	@override String get copyTo => 'Copy to';
	@override String get conflict => 'Binding conflict';
	@override String get conflictHint => 'An input is repeated in the same context. Change or disable one binding to resume autosave.';
	@override String get saved => 'Saved automatically';
	@override String get pending => 'Waiting to save';
	@override String get invalid => 'Not saved. Check the input settings.';
	@override String get record => 'Record';
	@override String get recordHint => 'Use this area, then confirm the captured input. Escape cancels; use the cancel button to bind Escape manually.';
	@override String get recordWaiting => 'Waiting for input…';
	@override String get keyCode => 'Keyboard code';
	@override String get trigger => 'Trigger';
	@override String get down => 'Key down';
	@override String get hold => 'Hold';
	@override String get instant => 'On release';
	@override String get click => 'Click';
	@override String get doubleClick => 'Double click';
	@override String get press => 'Press';
	@override String get duration => 'Hold duration (ms)';
	@override String get tolerance => 'Movement tolerance (px)';
	@override String get button => 'Mouse button';
	@override String get leftButton => 'Left button';
	@override String get middleButton => 'Middle button';
	@override String get rightButton => 'Right button';
	@override String get backButton => 'Back button';
	@override String get forwardButton => 'Forward button';
	@override String get up => 'Up';
	@override String get downDirection => 'Down';
	@override String get left => 'Left';
	@override String get right => 'Right';
	@override String get swipeLeft => 'Swipe left';
	@override String get swipeRight => 'Swipe right';
	@override String get swipeUp => 'Swipe up';
	@override String get swipeDown => 'Swipe down';
	@override String get tap => 'Tap';
	@override String get longPress => 'Long press';
	@override String get fingers => 'Fingers';
	@override String get gesture => 'Touch gesture';
	@override String get directions => 'Gesture direction sequence';
	@override String get undoDirection => 'Remove last direction';
	@override String get gamepadButton => 'Gamepad button number';
	@override String get gamepadHint => 'Gamepad bindings can be edited and transferred; gamepad events are not connected on this platform yet.';
	@override String get managedInput => 'This input is managed by its radial menu or system command';
	@override String get area => 'View area';
	@override String get topLeft => 'Top left';
	@override String get topCenter => 'Top center';
	@override String get topRight => 'Top right';
	@override String get middleLeft => 'Middle left';
	@override String get middleCenter => 'Center';
	@override String get middleRight => 'Middle right';
	@override String get bottomLeft => 'Bottom left';
	@override String get bottomCenter => 'Bottom center';
	@override String get bottomRight => 'Bottom right';
	@override String get keyboard => 'Keyboard';
	@override String get mouse => 'Mouse';
	@override String get mouseGesture => 'Mouse gesture';
	@override String get wheel => 'Wheel';
	@override String get touch => 'Touch';
	@override String get gamepad => 'Gamepad';
	@override String get radial => 'Radial';
	@override String get command => 'Command';
	@override String get global => 'Global';
	@override String get reader => 'Reader';
	@override String get video => 'Video';
	@override String get panel => 'Panel';
	@override String get shell => 'Shell';
	@override String get editor => 'Editor';
	@override String get modal => 'Dialog';
	@override String get moveUp => 'Move up';
	@override String get moveDown => 'Move down';
	@override String get collapse => 'Collapse binding';
	@override String get expand => 'Expand binding';
	@override String get actions => 'Actions';
	@override String get actionList => 'Actions';
	@override String get bindingDetails => 'Bindings';
	@override String get bindings => 'Bindings';
	@override String get restore => 'Restore defaults';
	@override String get resetFilters => 'Clear filters';
}

// Path: plat
class _Translations$plat$en_US extends Translations$plat$zh_CN {
	_Translations$plat$en_US._(TranslationsEnUs root) : this._root = root, super.internal(root);

	final TranslationsEnUs _root; // ignore: unused_field

	// Translations
	@override String get openAbove => 'Open above';
	@override String get openBelow => 'Open below';
	@override String get openLeft => 'Open left';
	@override String get openRight => 'Open right';
	@override String get closeTab => 'Close tab';
}

/// The flat map containing all translations for locale <en-US>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEnUs {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'workspace.laneTapExpandHint' => ({required Object title}) => '${title} (tap to expand the lane)',
			'workspace.laneTapCollapseHint' => ({required Object title}) => '${title} (tap to collapse the lane)',
			'workspace.laneDragHint' => ({required Object title}) => '${title} — press and hold to drag lanes into a new order',
			'workspace.laneSortHint' => ({required Object title}) => '${title} (pick “Edit layout” in the lane menu to reorder)',
			'workspace.allowedRange' => ({required Object min, required Object max}) => 'Allowed ${min}–${max}',
			'workspace.dockToName' => ({required Object label}) => 'Dock: ${label}',
			'workspace.laneWidthPx' => ({required Object px}) => 'Lane width: ${px} px',
			'workspace.dockToLabel' => ({required Object label}) => 'Dock to ${label}',
			'workspace.slotCount' => ({required Object count}) => '${count} slots',
			'workspace.columnsPerRow' => ({required Object columns}) => '${columns} slots per row now',
			'workspace.imagesCountBadge' => ({required Object n}) => '${n} images',
			'workspace.highestPage' => ({required Object value}) => 'Highest: ${value}',
			'workspace.worksCount' => ({required Object n}) => '${n} works',
			'workspace.sharePercent' => ({required Object v}) => '${v}% of the total',
			'workspace.heatLegendLow' => 'Low',
			'workspace.periodDetailLine' => ({required Object label, required Object count, required Object hours}) => '${label} · ${count} records\n${hours}',
			'workspace.restoreNamed' => ({required Object title}) => 'Restore “${title}”',
			'workspace.fullWidthFullHeight' => 'Full width and full height',
			'workspace.resizePreview' => ({required Object w, required Object h}) => '${w} × ${h} · release to save',
			'workspace.portSkippedLines' => ({required Object lines}) => 'Skipped entries:\n${lines}',
			'workspace.streakNowDays' => ({required Object n}) => 'Current streak: ${n} days',
			'workspace.mostlyAt' => ({required Object period}) => 'Mostly ${period}',
			'workspace.monthsAgo' => ({required Object months}) => '${months} months ago',
			'workspace.artbookCount' => ({required Object n}) => '${n} art books',
			'workspace.seenAtPage' => ({required Object pageNum}) => 'Seen at p.${pageNum}',
			'workspace.sourceMixItem' => ({required Object count, required Object percent}) => '${count} records · ${percent}%',
			'workspace.sourceMixHeader' => ({required Object n}) => 'Sample records · ${n} sources',
			'workspace.streakPointLine' => ({required Object date, required Object value}) => '${date}: ${value} days in a row',
			'workspace.streakDaysLine' => ({required Object label, required Object value}) => '${label}: ${value} days',
			'workspace.insightHeaderExpand' => ({required Object label, required Object position, required Object total, required Object title}) => '${label} · ${position}/${total} · expand ${title}',
			'workspace.heatCellLine' => ({required Object weekday, required Object hour, required Object count}) => '${weekday} ${hour} · ${count} records',
			'workspace.heatPeakLabel' => ({required Object weekday, required Object hour}) => 'Peak · ${weekday} ${hour}',
			'workspace.heatPeakShort' => ({required Object weekday, required Object hour}) => 'Peak ${weekday} ${hour}',
			'workspace.compactHeatmapExpandHours' => ({required Object day, required Object hours}) => '${day} · ${hours} h per cell · expand the reading heatmap',
			'workspace.hoursPerCell' => ({required Object hours}) => '${hours} h per cell',
			'workspace.compactHeatmapExpand' => ({required Object day}) => '${day} · expand the reading heatmap',
			'workspace.busiestPeriodLabel' => ({required Object period}) => 'Most records in ${period}',
			'workspace.weekdayRecordLine' => ({required Object day, required Object count}) => '${day}: ${count} records',
			'workspace.busiestWeekdayLabel' => ({required Object day}) => 'Busiest on ${day}',
			'workspace.selectedLastReadLines' => ({required Object key, required Object count}) => '${key} · ${count} last-read records',
			'workspace.dayRecordLine' => ({required Object key, required Object count}) => '${key}: ${count} records',
			'workspace.activeDaysCount' => ({required Object n}) => '${n} active days',
			'workspace.collapseNamed' => ({required Object title}) => 'Collapse ${title}',
			'workspace.insertTarget' => ({required Object name}) => 'Insert into: ${name}',
			'workspace.activeSwitchCount' => ({required Object activeCount}) => '${activeCount} switches on',
			'workspace.switchToastActiveOf3' => ({required Object activeCount}) => '${activeCount} of 3 switches on',
			'workspace.peakAllocated' => ({required Object value}) => 'Peak ${value}',
			'workspace.failedWith' => ({required Object error}) => 'Failed · ${error}',
			'workspace.registeredCount' => ({required Object n}) => '${n} registered in total',
			'workspace.readyOfTotal' => ({required Object ready, required Object total}) => '${ready} of ${total} ready',
			'workspace.sourceCountLabel' => ({required Object n}) => '${n} sources',
			'workspace.fileKindLabel' => ({required Object kind}) => '${kind} file',
			'workspace.passthroughDepthLabel' => ({required Object value}) => 'Passthrough depth: ${value}',
			'workspace.contentLayoutLabel' => ({required Object value}) => 'Content layout: ${value}',
			'workspace.sortFieldLabel' => ({required Object value}) => 'Sort: ${value}',
			'workspace.entryStyleLabel' => ({required Object value}) => 'Entry style: ${value}',
			'workspace.filterTypeLabel' => ({required Object value}) => 'Type: ${value}',
			'workspace.depthLimitLabel' => ({required Object n}) => 'Depth ≤${n}',
			'workspace.notSearchedBelow' => ({required Object n}) => 'Below level ${n} not searched',
			'workspace.searchScanned' => ({required Object n}) => '${n} scanned',
			'workspace.searchHits' => ({required Object n}) => '${n} hits',
			'workspace.tenThousandRecords' => ({required Object v}) => '${v}×10k records',
			'workspace.slowScanNote' => ({required Object label}) => '${label} · tens of seconds on a slow disk; results appear after one pass',
			'workspace.recursiveSearchScanned' => ({required Object scanned}) => 'Searching recursively · scanned ${scanned}',
			'workspace.restoreTabTitle' => ({required Object title}) => 'Restore tab: ${title}',
			'workspace.selectedCount' => ({required Object n}) => '${n} selected',
			'workspace.filteringBy' => ({required Object query}) => 'Filter: ${query}',
			'workspace.pageN' => ({required Object n}) => 'Page ${n}',
			'workspace.openLocalComicFailed' => ({required Object error}) => 'Error opening the local comic: ${error}',
			'workspace.daysAgo' => ({required Object days}) => '${days} days ago',
			'workspace.childCount' => ({required Object n}) => '${n} items',
			'workspace.noMatchThisLevelSuggest' => ({required Object query}) => 'Nothing at this level matches “${query}”; use “search subfolders” above to look deeper',
			'workspace.noMatchInSubdirs' => ({required Object query}) => 'No entries in subfolders match “${query}”',
			'workspace.tasksCount' => ({required Object n}) => '${n} tasks',
			'workspace.booksCount' => ({required Object n}) => '${n} books',
			'workspace.builtinWord' => 'Built-in',
			'workspace.onlineSourceFrom' => ({required Object from}) => 'Online source · ${from}',
			'workspace.pagesRemaining' => ({required Object n}) => '${n} pages left',
			'workspace.currentOfTotalPages' => ({required Object total}) => 'Current page · ${total} pages',
			'workspace.dateMD' => ({required Object month, required Object day}) => '${month}/${day}',
			'workspace.dateYMD' => ({required Object year, required Object month, required Object day}) => '${year}-${month}-${day}',
			'workspace.heatmapCell' => ({required Object weekday, required Object range, required Object count}) => '${weekday} ${range}: ${count} records',
			'workspace.theseCountItems' => ({required Object count}) => 'these ${count} items',
			'workspace.duplicateInFileCount' => ({required Object n}) => '${n} duplicated inside the file',
			'workspace.keptLocalCount' => ({required Object n}) => '${n} kept from this device',
			'workspace.progressUpdatedCount' => ({required Object n}) => '${n} progress entries updated',
			'workspace.skippedCount' => ({required Object n}) => '${n} skipped',
			'workspace.alreadyPresentCount' => ({required Object n}) => '${n} already present',
			'workspace.revivedCount' => ({required Object n}) => '${n} revived',
			'workspace.addedCount' => ({required Object n}) => '${n} added',
			'workspace.keyMismatch' => ({required Object expected}) => 'uniqueKey doesn\'t match source:comicId; expected ${expected}',
			'workspace.itemNumber' => ({required Object n}) => 'Entry #${n}',
			'workspace.unsupportedFormatVersion' => ({required Object version}) => 'Unsupported format version ${version}',
			'workspace.invalidJson' => ({required Object error}) => 'Not valid JSON: ${error}',
			'workspace.portImportFailed' => ({required Object label, required Object error}) => 'Importing ${label} failed: ${error}',
			'workspace.portFileUnreadable' => ({required Object error}) => 'Can\'t read this file: ${error}',
			'workspace.portExportFailed' => ({required Object label, required Object error}) => 'Exporting ${label} failed: ${error}',
			'workspace.portExportDone' => ({required Object count, required Object label, required Object target}) => 'Exported ${count} ${label} entries\n${target}',
			'workspace.portListEmpty' => ({required Object label}) => '${label} is still empty — there is nothing to export',
			'workspace.opFirstFailure' => ({required Object summary, required Object failure}) => '${summary} — first failure reason: ${failure}',
			'workspace.pickPasteTarget' => ({required Object verb, required Object subject}) => '${verb}${subject} — pick a folder to paste into',
			'workspace.movedToTrashSystem' => ({required Object subject, required Object hint}) => 'Moved ${subject} to the trash, ${hint} (in the system trash)',
			'workspace.movedToTrash' => ({required Object subject, required Object hint}) => 'Moved ${subject} to the trash, ${hint}',
			'workspace.cannotOpenFileManager' => ({required Object error}) => 'Can\'t open the file manager: ${error}',
			'workspace.pathsCopied' => ({required Object count}) => 'Copied ${count} paths',
			'workspace.deleteConfirmSubject' => ({required Object subject, required Object outcome}) => '${subject} will be deleted. ${outcome}.',
			'workspace.deleteForeverWarning' => ({required Object subject}) => '${subject} will be deleted permanently — not sent to the trash and can\'t be undone.',
			'workspace.loadingShort' => 'Loading',
			'workspace.readingHubTitle' => 'Reading hub',
			'workspace.chapterIdLabel' => 'Chapter ID',
			'workspace.portraitFormat' => 'Portrait',
			'workspace.peep' => 'Peek',
			'workspace.topTags' => 'Top tags',
			'workspace.libraryLabel' => 'Library',
			'workspace.preloadPath' => 'Preload path',
			'workspace.preloadStatus' => 'Preload status',
			'workspace.topBarIsThatRow' => 'The top bar is the row with exit / title / mode switch / reset layout',
			'workspace.pagePath' => 'Page path',
			'workspace.pageTemplateBookVars' => 'Page templates can also use {{book.*}} variables; tap any variable chip to insert it.',
			'workspace.pageTitleTemplate' => 'Page title template',
			'workspace.pageFileName' => 'Page file name',
			'workspace.pageToastTemplate' => 'Page toast template',
			'workspace.pageDescriptionTemplate' => 'Page description template',
			'workspace.pageNavigation' => 'Page navigation',
			'workspace.pageListNotReady' => 'Page list not ready',
			'workspace.pageListTotal' => 'Page-list total',
			'workspace.pageList' => 'Page list',
			'workspace.pageNumber' => 'Page number',
			'workspace.pageUrl' => 'Page URL',
			'workspace.pagesModified' => 'pages modified',
			'workspace.audioLabel' => 'Audio',
			'workspace.areaBasis' => 'Area basis',
			'workspace.panelBarFloating' => 'Panel bar: floating',
			'workspace.panelBarHint' => 'Panel bar (drag to another edge or make it floating; right-click or long-press for settings)',
			'workspace.hideLaneWidthBadge' => 'Hide the lane width badge',
			'workspace.hideWorkspaceTopBar' => 'Hide the workspace top bar',
			'workspace.refreshPerPageNoGuessing' => 'Refreshes per page; anything unmeasured stays a guess-free blank',
			'workspace.randomRoam' => 'Random browse',
			'workspace.randomLabel' => 'Random',
			'workspace.matchRelativePath' => 'Matches the relative path under the search root as well as the entry name',
			'workspace.confineToLane' => 'Confine to the lane',
			'workspace.confineToThisLane' => 'Confine to this lane',
			'workspace.readingProgressPercent' => 'Reading progress (%)',
			'workspace.readingProgressLabel' => 'Reading progress',
			'workspace.readingHeat' => 'Reading heat',
			'workspace.readingFilter' => 'Reading filter',
			'workspace.readingInsights' => 'Reading insights',
			'workspace.workspaceHome' => 'Workspace',
			'workspace.continueReading' => 'Continue reading',
			'workspace.todayReading' => 'Today',
			'workspace.longestStreak' => 'Longest streak',
			'workspace.readingSources' => 'Reading sources',
			'workspace.dayUnit' => 'days',
			'workspace.visitUnit' => 'visits',
			'workspace.sourceUnit' => 'sources',
			'workspace.pageUnit' => 'pages',
			'workspace.openDetail' => 'Details',
			'workspace.noReadingYet' => 'No reading history yet — pick one from the bookshelf',
			'workspace.mobileCardMissing' => 'Card not found',
			'workspace.mobileCardUnsupported' => 'This card is unavailable on this device',
			'workspace.infoSheetEntry' => 'Comic info',
			'workspace.readingOverview' => 'Reading overview',
			'workspace.readingPeriods' => 'Reading time of day',
			'workspace.readingWorkhole' => 'Reading workhole',
			'workspace.readerLaneIdle' => 'The reader lane is idle',
			'workspace.readerEn' => 'Reader',
			'workspace.readingHistoryEn' => 'History',
			'workspace.readingHistory' => 'Reading history',
			'workspace.readingToastOverlay' => 'Reading switch overlay toast',
			'workspace.readingLabel' => 'Reading',
			'workspace.longPressDragReorder' => 'Long-press and drag to reorder or change lane',
			'workspace.imageHeaderUnmeasured' => 'Can\'t read the image header',
			'workspace.resetLayoutHint' => 'Reset the layout (doesn\'t affect the book you\'re reading)',
			'workspace.renameBookmarkList' => 'Rename bookmark list',
			'workspace.renameDeleteList' => 'Rename / delete this list',
			'workspace.booksQueued' => 'books queued',
			'workspace.layoutFitsPanel' => 'Layout and sizes that suit the current panel',
			'workspace.exitSoloEn' => 'Exit solo',
			'workspace.exitSolo' => 'Exit solo',
			'workspace.exitTimeline' => 'Exit the timeline',
			'workspace.exitSearchToFolder' => 'Leave the search results and return to this tab\'s own folder',
			'workspace.exitWorkspaceHint' => 'Exit the workspace (Esc works too)',
			'workspace.exitWorkspace' => 'Exit the workspace',
			'workspace.exitMultiselect' => 'Exit multi-select',
			'workspace.restoreSwipeAfterExit' => 'Restores horizontal swiping between panels when it exits',
			'workspace.streakReading' => 'Reading streak',
			'workspace.streakDays' => 'Streak days',
			'workspace.streakLabel' => 'Streak',
			'workspace.runningTasks' => 'Running tasks',
			'workspace.progressLabel' => 'Progress',
			'workspace.enterFolder' => 'Enter the folder',
			'workspace.thisIsSwitchToastPreview' => 'This is a switch-toast preview',
			'workspace.allCardsCollapsed' => 'Every card in this panel is collapsed',
			'workspace.noFileManagerOnPlatform' => 'This platform has no file manager to invoke',
			'workspace.listHasNoBookmarks' => 'This list has no bookmarks yet',
			'workspace.itemNeedsLocalArchive' => 'This item needs to be a local archive before it can be measured',
			'workspace.thisItem' => 'this item',
			'workspace.thisWall' => 'this wall',
			'workspace.noPluginsInstalled' => 'No plugins installed yet',
			'workspace.noBookmarksYet' => 'No bookmarks yet — add one from the details page',
			'workspace.last7ReadingTrend' => 'Reading trend (7 days)',
			'workspace.last7Records' => 'Records (7 days)',
			'workspace.last7Days' => 'Last 7 days',
			'workspace.last3Days' => 'Last 3 days',
			'workspace.last28Records' => 'Records (28 days)',
			'workspace.last28Active' => 'Active days (28)',
			'workspace.last28NoRecords' => 'No records in the last 28 days',
			'workspace.last28Days' => 'Last 28 days',
			'workspace.boundaryToastText' => 'Boundary toast text',
			'workspace.carrierDistribution' => 'Medium distribution',
			'workspace.carrierLabel' => 'Medium',
			'workspace.goToFolder' => 'Go to the folder',
			'workspace.jumpBar' => 'Jump bar',
			'workspace.pathActions' => 'Path actions',
			'workspace.pathLabel' => 'Path',
			'workspace.aggregateSourceSearch' => 'Aggregate search across sources',
			'workspace.trendLabel' => 'Trend',
			'workspace.upscaleStage' => 'Upscale stage',
			'workspace.upscaleSwitch' => 'Upscale switch',
			'workspace.afterUpscale' => 'After upscaling',
			'workspace.resourceWorkhole' => 'Resource workhole',
			'workspace.debugSource' => 'Debug source',
			'workspace.toastAtChapterEnd' => 'Remind when turning past the end of a chapter',
			'workspace.detailedInformation' => 'Details',
			'workspace.detailedLabel' => 'Detailed',
			'workspace.laneMoreEditLayout' => 'This lane · edit layout',
			'workspace.visits' => 'Visits',
			'workspace.settingsAndTools' => 'Settings and tools',
			'workspace.triggerCondition' => 'Trigger condition',
			'workspace.triggersAllOff' => 'All triggers off',
			'workspace.decodeBufferPlusCache' => 'Decode buffer + image cache',
			'workspace.viewModeNotInTimeline' => 'View mode (not available in the timeline)',
			'workspace.viewModeLabel' => 'View mode',
			'workspace.seeDetailsBelow' => 'See the details below',
			'workspace.decorativeShapes' => 'Decorative shapes',
			'workspace.installNewSource' => 'Install a new source',
			'workspace.fetching' => 'Fetching…',
			'workspace.freeThumbnails' => 'Free thumbnails',
			'workspace.customLayout' => 'Custom layout',
			'workspace.pageTurnToast' => 'Page-turn toast',
			'workspace.pageToastShowsNumber' => 'Shows the page number live when turning or jumping',
			'workspace.pageAnimation' => 'Page-turn animation',
			'workspace.jpTranslated' => 'Translated',
			'workspace.networkImageCached' => 'Network image · downloaded then served from the image cache',
			'workspace.missingTitle' => 'Missing title',
			'workspace.missingSourceOrComicId' => 'Missing source or comicId',
			'workspace.thumbnailsLabel' => 'Thumbnails',
			'workspace.editPath' => 'Edit path',
			'workspace.editLongPressHints' => 'While editing, long-press a tab to reorder or move it across lanes, or long-press the header icon to reorder lanes',
			'workspace.editLayout' => 'Edit layout',
			'workspace.encodedFormat' => 'Encoded format',
			'workspace.encodedSize' => 'Encoded size',
			'workspace.weightBlendsEverything' => 'Blends content count, recent use and reading status.',
			'workspace.resumeLastReading' => 'Resume the last reading',
			'workspace.counting' => 'Counting',
			'workspace.textureReady' => 'Texture ready',
			'workspace.texture' => 'Texture',
			'workspace.compactList' => 'Compact list',
			'workspace.pasteIntoItem' => 'Paste into this item',
			'workspace.pasteHere' => 'Paste into this folder',
			'workspace.lengthDistribution' => 'Length distribution',
			'workspace.lengthLabel' => 'Length',
			'workspace.emphasiseReading' => 'Emphasises what you are reading.',
			'workspace.emphasiseRecent' => 'Emphasises recently used content.',
			'workspace.passthroughMode' => 'Passthrough mode',
			'workspace.gapFill' => 'Gap fill',
			'workspace.gapComponentsTitle' => 'Gaps & components',
			'workspace.gapComponentsDescription' => 'Random shapes and mini widgets in one place: pick an overall mode, then toggle each item — every item previews what it looks like.',
			'workspace.gapPreviewLabel' => 'Preview',
			'workspace.gapEnableAll' => 'Enable all',
			'workspace.gapDisableAll' => 'Disable all',
			'workspace.gapShapesSection' => 'Random shapes',
			'workspace.gapWidgetsSection' => 'Mini widgets',
			'workspace.gapShapeBlob' => 'Blob',
			'workspace.gapShapeBurst' => 'Burst',
			'workspace.gapShapeClover' => 'Clover',
			'workspace.gapShapeGem' => 'Gem',
			'workspace.gapShapeArch' => 'Arch',
			'workspace.gapShapeFlower' => 'Flower',
			'workspace.gapShapeRing' => 'Ring',
			'workspace.gapShapeWave' => 'Wave',
			'workspace.gapCompletion' => 'Completion',
			'workspace.gapHeatmap' => 'Reading heat',
			'workspace.gapWeekday' => 'Weekday rhythm',
			'workspace.gapSpan' => 'Collection span',
			'workspace.gapUnread' => 'Unread pool',
			'workspace.gapMilestone' => 'Next milestone',
			'workspace.gapAverageProgress' => 'average progress',
			'workspace.gapFinishedBooks' => 'finished',
			'workspace.gapUnreadBooks' => 'unread',
			'workspace.gapHeatWindow' => 'Last 8 weeks',
			'workspace.gapWeekdayRhythm' => 'Weekday split',
			'workspace.gapSpanDaysLabel' => 'days span',
			'workspace.gapSpanEarliest' => 'since',
			'workspace.gapUnreadPool' => 'not started',
			'workspace.gapMilestoneHint' => 'to go',
			'workspace.gapComponentCount' => ({required Object on, required Object total}) => '${on} / ${total} on',
			'workspace.gapMinSize' => ({required Object w, required Object h}) => 'min ${w} × ${h}',
			'workspace.gapResetDefaults' => 'Reset to defaults',
			'workspace.wallTabSize' => 'Size',
			'workspace.wallTabLayout' => 'Layout',
			'workspace.wallTabComponents' => 'Components',
			'workspace.wallTabCover' => 'Cover',
			'workspace.wallTabWeights' => 'Weights',
			'workspace.idleState' => 'Idle',
			'workspace.moveToTrashNoUndo' => 'Move to trash (can\'t be undone)',
			'workspace.moveToTrash' => 'Move to trash',
			'workspace.folderPath' => 'Folder path',
			'workspace.folderLabel' => 'Folder',
			'workspace.imageTuning' => 'Image tuning',
			'workspace.aspectComposition' => 'Aspect mix',
			'workspace.aspectFormat' => 'Aspect',
			'workspace.fillWithExpressiveShapes' => 'Fills the gaps with random Expressive outlines and icons.',
			'workspace.soloThisLaneEn' => 'Solo',
			'workspace.soloThisLane' => 'Make this lane solo',
			'workspace.statusLabel' => 'Status',
			'workspace.clickToCollapse' => 'Tap to collapse',
			'workspace.clickToExpand' => 'Tap to expand',
			'workspace.tapCover' => 'Tap the cover',
			'workspace.clickToFill' => 'Tap to fill',
			'workspace.comicArchive' => 'Comic archive',
			'workspace.comicIdLabel' => 'Comic ID',
			'workspace.chineseLocalized' => 'CN-localised',
			'workspace.renderPath' => 'Render path',
			'workspace.clearSearchAndCollapse' => 'Clear the search and collapse',
			'workspace.lateNight' => 'Late night',
			'workspace.activePeak' => 'Active peak',
			'workspace.activeDays' => 'Active days',
			'workspace.activeState' => 'Active',
			'workspace.noEntriesAfterFilter' => 'No entries match the search or type filter',
			'workspace.noEntries' => 'No entries',
			'workspace.noEnabledSource' => 'No enabled image source',
			'workspace.nothingToDisplay' => 'Nothing to display',
			'workspace.noMatchingPages' => 'No matching pages',
			'workspace.noMatchingHistory' => 'No matching reading records',
			'workspace.noMatchingBookmarks' => 'No matching bookmarks',
			'workspace.immersiveWorkhole' => 'Immersive workhole',
			'workspace.deleteForeverQuestion' => 'Delete permanently?',
			'workspace.deleteForever' => 'Delete permanently',
			'workspace.weeklyReadingRhythm' => 'Weekly reading rhythm',
			'workspace.everyFieldIsMeasured' => 'Every value comes from a recorded field, not from "I tweaked it so it must be fine"',
			'workspace.normalState' => 'Normal',
			'workspace.recursiveSearchPending' => 'Searching recursively; results appear after one pass…',
			'workspace.recursiveSearching' => 'Searching recursively…',
			'workspace.followingProgress' => 'Following the reading progress',
			'workspace.editingLayoutFinishInMenu' => 'Editing the layout · finish in the menu',
			'workspace.countingReadingHistory' => 'Counting reading history',
			'workspace.bannerLabel' => 'Banner',
			'workspace.rootPath' => 'Root path',
			'workspace.areaByAspectRatio' => 'Allocates card space by the source aspect ratio.',
			'workspace.longestSampleDays' => 'Longest in sample · days',
			'workspace.longestSample' => 'Longest in sample',
			'workspace.theWidthBadgeNextToHeader' => 'The "400px" badge to the right of the lane header',
			'workspace.titleLabel' => 'Title',
			'workspace.sourceKey' => 'Source key',
			'workspace.sourceType' => 'Source type',
			'workspace.sourceComposition' => 'Source mix',
			'workspace.sourceBreakdown' => 'Source breakdown',
			'workspace.sourceModifiedAt' => 'Source modified',
			'workspace.sourceLabel' => 'Source',
			'workspace.entryCount' => 'Entries',
			'workspace.itemsUpdated' => 'items updated',
			'workspace.itemsContent' => 'items',
			'workspace.chapterDonePreparingNext' => 'This chapter is finished · preparing the next one',
			'workspace.platformUnsupported' => 'Not supported on this platform',
			'workspace.localComicsEn' => 'Local Manga',
			'workspace.localComics' => 'Local comics',
			'workspace.localWorks' => 'Local works',
			'workspace.localLabel' => 'Local',
			'workspace.lastPageToast' => 'Last-page toast',
			'workspace.notTurnedOn' => 'Off',
			'workspace.notEnabled' => 'Not enabled',
			'workspace.serverLabel' => 'Server',
			'workspace.maxThirtyTwoLevels' => 'At most 32 levels',
			'workspace.lastPageToastText' => 'Last-page toast text',
			'workspace.noReadingHistory' => 'No reading history yet',
			'workspace.noRecordsYet' => 'No records yet',
			'workspace.noHeatRecords' => 'No heat records yet',
			'workspace.noEnabledPlugins' => 'No enabled plugins yet',
			'workspace.noVisitHistory' => 'No visit history yet',
			'workspace.normalOneWideTwoSlots' => 'Normal cards take 1 slot, wide cards 2',
			'workspace.eveningNight' => 'Night',
			'workspace.eveningLabel' => 'Evening',
			'workspace.showHiddenFiles' => 'Show hidden files',
			'workspace.showTarget' => 'Show target',
			'workspace.showQuickSwitchBar' => 'Show the quick-switch bar',
			'workspace.showWorkspaceTopBar' => 'Show the workspace top bar',
			'workspace.showSubFileNames' => 'Show sub-file names',
			'workspace.timeInformation' => 'Time information',
			'workspace.timePeriod' => 'Time of day',
			'workspace.earlyFavourites' => 'Early favourites',
			'workspace.cannotUndo' => 'Can\'t be undone',
			'workspace.noAnimation' => 'No animation',
			'workspace.squareFormat' => 'Square',
			'workspace.newTab' => 'New tab',
			'workspace.newBookmarkList' => 'New bookmark list',
			'workspace.newName' => 'New name',
			'workspace.fileManagement' => 'File manager',
			'workspace.fileBrowsing' => 'File browsing',
			'workspace.fileOperations' => 'File operations (copy / move / delete)',
			'workspace.foldersFirst' => 'Folders first',
			'workspace.fileNameLabel' => 'File name',
			'workspace.weightBiggerWins' => 'Larger values stand out more; 0 disables it. When several match, the highest weight wins.',
			'workspace.switchToFloating' => 'Switch to floating',
			'workspace.collapseSearch' => 'Collapse search',
			'workspace.collapseChildren' => 'Collapse children',
			'workspace.collapseSubfolders' => 'Collapse subfolders',
			'workspace.collapseInformation' => 'Collapse info',
			'workspace.favouriteTime' => 'Favourited at',
			'workspace.favouriteList' => 'Favourites',
			'workspace.localOpenSupportDesc' => 'Supports zip, cbz, folders, PDFs and image archives. Rust unpacks quickly and feeds the D3D12/Metal composition chain directly.',
			'workspace.undoLastStep' => 'Undo the last step',
			'workspace.summaryLabel' => 'Summary',
			'workspace.searchSpaceExclude' => 'Search (space-separated, - to exclude)',
			'workspace.searchPageOrFileName' => 'Search page number or file name...',
			'workspace.searchField' => 'Search bar',
			'workspace.searchTitleAuthorSource' => 'Search title / author / source',
			'workspace.pluginRunState' => 'Plugin running state',
			'workspace.pluginMarket' => 'Plugin market',
			'workspace.controlPanel' => 'Control panel',
			'workspace.takeOver' => 'Take over',
			'workspace.keepReading' => 'Continue reading',
			'workspace.sortingTimelineFixed' => 'Sorting (the timeline always sorts by time)',
			'workspace.sortMode' => 'Sort mode',
			'workspace.emphasiseByTagWeights' => 'Emphasises content using your custom tag weights.',
			'workspace.areaByDiskUsage' => 'Allocates display area by how much disk space each entry takes.',
			'workspace.timelineByDay' => 'Timeline by day',
			'workspace.dragTitleToReorder' => 'Press and hold the title to drag-reorder',
			'workspace.bookmarkListDesc' => 'Organise bookmarks by topic. After creating one, bookmarks can be moved into this list.',
			'workspace.dragResizeWorkhole' => 'Drag to resize the workhole',
			'workspace.dragToResize' => 'Drag to resize',
			'workspace.collapseToBarEn' => 'Collapse',
			'workspace.collapseToBar' => 'Collapse into a compact bar',
			'workspace.saveSearchAsTab' => 'Save these search results as a new tab',
			'workspace.setHomeHere' => 'Make this folder the home',
			'workspace.openReader' => 'Open the reader',
			'workspace.openLocal' => 'Open local',
			'workspace.toastOnOpenOrSwitch' => 'Pops when a comic is opened or switched to',
			'workspace.openWorkhole' => 'Open the workhole',
			'workspace.showPageNavWhenOpen' => 'Shows page navigation once a book is open',
			'workspace.showFileTimesWhenOpen' => 'Shows file times once a book is open',
			'workspace.showCurrentPageWhenOpen' => 'Shows current-page info once a book is open',
			'workspace.showStorageWhenOpen' => 'Shows storage info once a book is open',
			'workspace.showPresentPrefetchWhenOpen' => 'Shows presenter and prefetch status once a book is open',
			'workspace.showBookInfoWhenOpen' => 'Shows book info once a book is open',
			'workspace.imFeelingLucky' => 'I\'m feeling lucky',
			'workspace.restoreDefaultSize' => 'Restore the default size',
			'workspace.readerLaneSoloHint' => 'Anything opened from the shelf on the left or discover on the right is read in this lane; tap the solo button in the bar header to make it fill the viewport instantly.',
			'workspace.footnoteSampleStreakDays' => 'Consecutive days with records in the sample · not the full reading log',
			'workspace.footnoteSampleStreak' => 'Consecutive days within the sample · not the full reading log',
			'workspace.footnotePeriod28' => 'Last 28 days · distributed by local time of the last read',
			'workspace.footnoteWeekday28' => 'Last 28 days · last-reading records summed by weekday',
			'workspace.footnoteLast500' => 'Last-reading records of the most recent 500 comics · not a total count or reading time',
			'workspace.searchDepthTooltip' => ({required Object depths, required Object detail}) => 'Tap to cycle the recursion depth (${depths} levels). ${detail}',
			'workspace.shortSat' => 'Sat',
			'workspace.shortFri' => 'Fri',
			'workspace.shortThu' => 'Thu',
			'workspace.shortWed' => 'Wed',
			'workspace.shortTue' => 'Tue',
			'workspace.shortMon' => 'Mon',
			'workspace.shortSun' => 'Sun',
			'workspace.restoreDefaultWidth' => 'Restore the default width',
			'workspace.restorePanelBarPosition' => 'Restore the panel bar\'s default position',
			'workspace.restoreCollapsedCards' => 'Restore collapsed cards',
			'workspace.restoreClosedTabs' => 'Restore closed tabs',
			'workspace.totalPagesLabel' => 'Total pages',
			'workspace.toContinue' => 'To continue',
			'workspace.queueStackCards' => 'Queue stack',
			'workspace.currentPageCost' => 'Current page time',
			'workspace.currentPageNumber' => 'Current page number',
			'workspace.currentPageFile' => 'Current page file',
			'workspace.currentPageSize' => 'Current page size',
			'workspace.currentPageModifiedAt' => 'Current page modified',
			'workspace.currentPageHandoffMs' => 'Current page hand-off time (ms)',
			'workspace.currentStreakDays' => 'Current streak · days',
			'workspace.currentStreak' => 'Current streak',
			'workspace.noHitThisLevel' => 'No hits at this level; turn on "include subfolders" and search again (a full scan takes tens of seconds on a slow disk)',
			'workspace.folderNoMedia' => 'This folder has no browsable comics or media files',
			'workspace.folderNoChildren' => 'This folder has nothing to show',
			'workspace.folderNotInSnapshot' => 'This folder is not in the current search or folder snapshot. Enter it to see what is inside.',
			'workspace.archiveLabel' => 'Archive',
			'workspace.onComparingOriginal' => 'On (comparing with the original)',
			'workspace.switchedOn' => 'On',
			'workspace.fieldsFillOnOpen' => 'These cells fill in as soon as a book opens; anything unmeasurable stays —',
			'workspace.linking' => 'Linking',
			'workspace.avgPagesPerBook' => 'Average pages per book',
			'workspace.regularWidth' => 'Regular width',
			'workspace.commonTags' => 'Common tags',
			'workspace.topCreators' => 'Top creators',
			'workspace.market' => 'Market',
			'workspace.limitReached' => 'Limit reached',
			'workspace.isLastPage' => 'This is the last page',
			'workspace.searchHistoryCleared' => 'Search history cleared',
			'workspace.followProgressPaused' => 'Paused following the reading progress',
			'workspace.fileManagerOpened' => 'File manager opened',
			'workspace.gpuReadyState' => 'Ready',
			'workspace.pathCopied' => 'Path copied',
			'workspace.copied' => 'Copied',
			'workspace.pagesPresented' => 'Pages presented',
			'workspace.cutDone' => 'Cut',
			'workspace.writtenToCacheShare' => 'Written to the cache; save it from the share sheet',
			'workspace.aborted' => 'Aborted',
			'workspace.workholeSize' => 'Workhole size',
			'workspace.peakDay' => 'Peak day',
			'workspace.peakValue' => 'Peak',
			'workspace.expandLane' => 'Expand lane',
			'workspace.polledEvery3s' => 'Polled every 3 s while expanded',
			'workspace.expandChildren' => 'Expand children',
			'workspace.expandSubfolders' => 'Expand subfolders',
			'workspace.expandInformation' => 'Expand information',
			'workspace.expandLabel' => 'Expand',
			'workspace.displayWallSettings' => 'Display wall settings · long-press to toggle the wall',
			_ => null,
		} ?? switch (path) {
			'workspace.displayWallCustom' => 'Display wall customise',
			'workspace.displayWall' => 'Display wall',
			'workspace.searchDepthCostHint' => 'More depth is slower: one full-library scan takes tens of seconds on a slow disk; too shallow misses deeper folders',
			'workspace.readyWaiting' => 'Ready, waiting',
			'workspace.readyState' => 'Ready',
			'workspace.dustyReread' => 'Shelf finds',
			'workspace.widgetsOnceThenShapes' => 'Each widget appears once per wall; the remaining gaps are filled with random shapes.',
			'workspace.coverGrid' => 'Cover grid',
			'workspace.coverCollage' => 'Cover collage',
			'workspace.coverList' => 'Cover list',
			'workspace.coverLabel' => 'Cover',
			'workspace.exportAsJson' => 'Export as JSON',
			'workspace.importExport' => 'Import / export',
			'workspace.cardWidthAutoColumns' => 'Width is the target size; the column count adapts to the panel. Wide cards take two slots and can sit beside normal ones.',
			'workspace.finishEditing' => 'Finish editing',
			'workspace.finishLayout' => 'Finish layout',
			'workspace.storageInformation' => 'Storage information',
			'workspace.saveAsTab' => 'Save as tab',
			'workspace.subFilesShowAll' => 'Sub-files: show all',
			'workspace.subFilesShowOne' => 'Sub-files: show one',
			'workspace.daysWithRecords' => 'days with records',
			'workspace.sizeCompare' => 'Size comparison',
			'workspace.sizeLabel' => 'Size',
			'workspace.multiColumnLanes' => 'Multi-column lanes',
			'workspace.searchAnyToken' => 'Union across tokens (by default every token must match)',
			'workspace.multiOutlinedSelected' => 'Multiple · the outline marks the selection',
			'workspace.duplicateTab' => 'Duplicate tab',
			'workspace.copyPath' => 'Copy path',
			'workspace.copyPosition' => 'Copy position',
			'workspace.einkRefresh' => 'E-ink refresh',
			'workspace.basedOnLast500' => 'Based on the last-reading records of the most recent 500 comics',
			'workspace.readingProgress' => 'Reading progress',
			'workspace.currentlyReading' => 'Reading',
			'workspace.onlineSourceNoFileTime' => 'Online sources have no local file times',
			'workspace.onlineSourceNoArchive' => 'Online sources have no archive',
			'workspace.onlineSource' => 'Online source',
			'workspace.onlineLabel' => 'Online',
			'workspace.openInNewTab' => 'Open in a new tab',
			'workspace.readerLaneReadsHint' => 'Anything opened from the shelf on the left or discover on the right is read in this lane;',
			'workspace.searchSubdirs' => 'Search inside subfolders',
			'workspace.gallery' => 'Gallery',
			'workspace.imageSize' => 'Image size',
			'workspace.imagesLabel' => 'Images',
			'workspace.sourceLocalAggregate' => 'Local source aggregate',
			'workspace.sourceExtensions' => 'Source extensions',
			'workspace.sourceShortcuts' => 'Source shortcuts',
			'workspace.imageSourcesEn' => 'Extensions',
			'workspace.imageSources' => 'Sources and extensions',
			'workspace.sourcesToolsOcr' => 'Sources · Tools · OCR',
			'workspace.imageProcessingStage' => 'Image processing stage',
			'workspace.imageInformation' => 'Image information',
			'workspace.pinTab' => 'Pin tab',
			'workspace.pinHere' => 'Pin here',
			'workspace.backToFolder' => 'Back to the folder',
			'workspace.backHome' => 'Back home',
			'workspace.backToLaneHeaderDefault' => 'Back to the default docked-in-header form',
			'workspace.heatmapFourRowsHint' => 'Four consecutive weeks · the outline marks the selected day · stronger colour means more activity',
			'workspace.weekdaySun' => 'Sun',
			'workspace.weekdaySat' => 'Sat',
			'workspace.weekdayFri' => 'Fri',
			'workspace.weekdayThu' => 'Thu',
			'workspace.weekdayWed' => 'Wed',
			'workspace.weekdayTue' => 'Tue',
			'workspace.weekdayMon' => 'Mon',
			'workspace.presenter' => 'Presenter',
			'workspace.includeSubdirStats' => 'Include subfolder stats',
			'workspace.includeSubdirs' => 'Include subfolders',
			'workspace.recursiveSearchHint' => 'Searches downward recursively; the depth cap is clamped on the Rust side',
			'workspace.back' => 'Back',
			'workspace.searchSyntaxHint' => 'Name and path · space-separated · -exclude · "phrases"',
			'workspace.nameLabel' => 'Name',
			'workspace.undoable' => 'Can be undone',
			'workspace.onlyThisPanelDetailsBelow' => 'Applies to this panel only. The cover\'s details button always expands downward.',
			'workspace.onlyFittingWidgetsRepeat' => 'Inserts only the summary widgets that fit the gap; the same one may repeat.',
			'workspace.mergeOnlyHistoryDetail' => 'Merge only: no history entry is deleted; where local progress is newer than the file, local wins.',
			'workspace.mergeOnlyHistory' => 'Merges only — existing records are never deleted or overwritten.',
			'workspace.mergeOnlyBookmarks' => 'Merges only — existing bookmarks are never deleted or overwritten.',
			'workspace.changesLabel' => 'Changes',
			'workspace.discoverToolsEn' => 'Tools',
			'workspace.switchToWorkholeEn' => 'Workhole',
			'workspace.switchToSwimlaneEn' => 'Swimlane',
			'workspace.closeSidebarEn' => 'Close',
			'workspace.closeCurrentComicFull' => 'Close the current comic (back to empty)',
			'workspace.closeCurrentComicPlain' => 'Close the current comic (back to empty)',
			'workspace.favoritesEn' => 'Favourites',
			'workspace.bookshelfEn' => 'Bookshelf',
			'workspace.downloadsOfflineEn' => 'Downloads',
			'workspace.topEntriesStillWork' => 'The three entries above still work: install a source and each one shows here',
			'workspace.widgetsPlusShapes' => 'Widgets + shapes',
			'workspace.miniWidgets' => 'Widgets',
			'workspace.randomShapes' => 'Random shapes',
			'workspace.openDetailsPage' => 'Open the details page',
			'workspace.expandDetailsBelow' => 'Expand details below',
			'workspace.weightBalanced' => 'Balanced',
			'workspace.readingStatus' => 'Reading status',
			'workspace.recentlyUsed' => 'Recently used',
			'workspace.followSort' => 'Follow the sort',
			'workspace.yesterday' => 'Yesterday',
			'workspace.cancelPathEdit' => 'Cancel path editing',
			'workspace.unpin' => 'Unpin',
			'workspace.discoverTools' => 'Discover and tools',
			'workspace.doubleTapResetLaneWidth' => 'Double-tap resets this column\'s width · right-click opens the lane menu',
			'workspace.installOrImportPlugin' => 'Install a source from the plugin market, or import a local plugin package',
			'workspace.originalRatio' => 'Original ratio',
			'workspace.historyFile' => 'History file',
			'workspace.historyData' => 'History data',
			'workspace.volume' => 'Volume',
			'workspace.cardHeight' => 'Card height',
			'workspace.cardSpacing' => 'Card spacing',
			'workspace.cardLayout' => 'Card layout',
			'workspace.cardWidth' => 'Card width',
			'workspace.cardPosition' => 'Card position',
			'workspace.occupiedSize' => 'Occupied size',
			'workspace.matchPath' => 'Match path',
			'workspace.loadingState' => 'Loading',
			'workspace.cut' => 'Cut',
			'workspace.forward' => 'Forward',
			'workspace.last7DaysRecords' => 'Last 7 days',
			'workspace.refreshCurrentFolder' => 'Refresh the current folder',
			'workspace.toastOnLastPage' => 'Show a toast on the last page',
			'workspace.reachedLastPage' => 'That\'s the end — no more pages',
			'workspace.deleteQuestion' => 'Delete?',
			'workspace.creating' => 'Creating',
			'workspace.create' => 'Create',
			'workspace.creator' => 'Creator',
			'workspace.listName' => 'List name',
			'workspace.toastOnPageSwitch' => 'Show a toast when switching pages',
			'workspace.switchToastTest' => 'Switch toast test',
			'workspace.switchToast' => 'Switch toast',
			'workspace.toastOnBookSwitch' => 'Show a toast when switching books',
			'workspace.switchToWorkhole' => 'Switch to the immersive workhole',
			'workspace.switchToSwimlane' => 'Switch to multi-column lanes',
			'workspace.switchDescending' => 'Switch to descending',
			'workspace.switchAscending' => 'Switch to ascending',
			'workspace.bookSwitchToast' => 'Book-switch toast',
			'workspace.internalThumbnails' => 'Internal thumbnails',
			'workspace.builtin' => 'Built-in',
			'workspace.moreContentMoreArea' => 'More content means a larger share of the area.',
			'workspace.contentCount' => 'Content count',
			'workspace.contentSections' => 'Content sections',
			'workspace.otherMedia' => 'Other media',
			'workspace.closeTab' => 'Close tab',
			'workspace.closeSidebar' => 'Close sidebar',
			'workspace.closePassthroughMode' => 'Turn off passthrough mode',
			'workspace.closeCurrentComic' => 'Close the current comic (back to empty)',
			'workspace.closeWorkhole' => 'Close the workhole',
			'workspace.closeTabsLeft' => 'Close tabs to the left',
			'workspace.closeTabsRight' => 'Close tabs to the right',
			'workspace.closeOtherTabs' => 'Close other tabs',
			'workspace.turnedOff' => 'Off',
			'workspace.manageAll' => 'Manage all',
			'workspace.allHealthy' => 'All healthy',
			'workspace.allImageSources' => 'All image sources',
			'workspace.closeAllTabs' => 'Close all',
			'workspace.fullWidth' => 'Full width',
			'workspace.allowLeaveLane' => 'Allow dragging out of the lane',
			'workspace.pixelSize' => 'Pixel size',
			'workspace.serendipity' => 'Serendipity',
			'workspace.favouriteTagWeight' => 'Favourite tag weight',
			'workspace.favouriteTags' => 'Favourite tags',
			'workspace.modifiedTime' => 'Modified time',
			'workspace.modifiedDate' => 'Modified date',
			'workspace.modify' => 'Modify',
			'workspace.egBookPath' => 'e.g. Path: {{book.path}}',
			'workspace.egPageIndex' => 'e.g. Page {{page.indexDisplay}}',
			'workspace.egLastPage' => 'e.g. This is the last page',
			'workspace.egSwitchedToBook' => 'e.g. Switched to {{book.displayName}}',
			'workspace.egPageName' => 'e.g. {{page.name}}',
			'workspace.sizeVolume' => 'Size',
			'workspace.toastStyleInSettings' => 'Position and look are set under Settings → Toast style.',
			'workspace.emphasiseTopSorted' => 'Emphasises whatever sorts to the top.',
			'workspace.anyToken' => 'Any token',
			'workspace.collapseFromPanel' => 'Collapse from this panel',
			'workspace.newFromThisTab' => 'New from this tab',
			'workspace.pickComicFolderFromDisk' => 'Choose a comic folder on disk',
			'workspace.importFromJson' => 'Import from JSON',
			'workspace.today' => 'Today',
			'workspace.desktopOnly' => 'Desktop only',
			'workspace.bookPathLocalOnly' => 'Book path (only set for local sources)',
			'workspace.bookTitleTemplate' => 'Book title template',
			'workspace.bookDisplayName' => 'Book display name',
			'workspace.bookToastTemplate' => 'Book toast template',
			'workspace.bookDescriptionTemplate' => 'Book description template',
			'workspace.bookInformation' => 'Book information',
			'workspace.bookmarkFile' => 'Bookmark file',
			'workspace.bookmarkData' => 'Bookmark data',
			'workspace.bookmarks' => 'Bookmarks',
			'workspace.bookshelfUpstream' => 'Bookshelf (upstream original)',
			'workspace.bookshelfAggregateCard' => 'Bookshelf aggregate card',
			'workspace.shelfFavoriteFiles' => 'Shelf · Favourites · Files',
			'workspace.bookshelfTab' => 'Bookshelf',
			'workspace.bookTitle' => 'Book title',
			'workspace.homeNotSetYet' => 'Home: not set · tap to make the current folder the home',
			'workspace.homeCurrentManageHint' => 'Home (current) · right-click or long-press to manage',
			'workspace.homeSetTo' => 'Home set to',
			'workspace.homeManageHint' => 'Home · right-click or long-press to manage',
			'workspace.heroVisual' => 'Hero visual',
			'workspace.mainOccupancy' => 'Main occupancy',
			'workspace.temporarySort' => 'Temporary sort (not remembered for this folder)',
			'workspace.abortRecursiveSearch' => 'Stop the recursive search (keep results already found)',
			'workspace.samePathAsHeaderDoubleClick' => 'Same path as double-tapping the lane header',
			'workspace.samePathAsBackKey' => 'Same path as Esc and the system back key',
			'workspace.keepGapIrregularOutline' => 'Keeps blank space between irregular outlines.',
			'workspace.notAnObject' => 'Not an object',
			'workspace.asymmetric' => 'Asymmetric',
			'workspace.noFill' => 'Do not fill',
			'workspace.downloadTaskList' => 'Download task list',
			'workspace.downloadsOffline' => 'Downloads and offline',
			'workspace.bothWeeksNoRecord' => 'Neither week has records',
			'workspace.earlyAfternoon' => 'Early afternoon',
			'workspace.noon' => 'Noon',
			'workspace.earlyMorning' => 'Early morning',
			'workspace.afternoon' => 'Afternoon',
			'workspace.morning' => 'Morning',
			'workspace.parentDirectory' => 'Up one level',
			'workspace.prevWindowNoRecord' => 'No records in the previous window',
			'workspace.nextSegment' => 'Next segment',
			'workspace.prevSegment' => 'Previous segment',
			'workspace.noCreationTimeField' => 'dart:io has no creation time, so only the fields that report back are shown',
			'workspace.rustMemoryPollHint' => 'Rust memory is only read when expanded; collapsed stops polling',
			'workspace.rustMemory' => 'Rust memory',
			'workspace.gpuZeroCopyEngine' => 'Zero-copy GPU engine',
			'workspace.gpuLinking' => 'Building the GPU link',
			'workspace.gpuReady' => 'GPU ready',
			'workspace.gpuSharedTexture' => 'GPU shared texture',
			'workspace.cpuDecodeFallback' => 'CPU decode fallback',
			'workspace.cpuDecodePreload' => 'CPU decode / image cache preloading',
			'workspace.compressedArchive' => 'Compressed archive',
			'workspace.archiveZip' => 'ZIP archive',
			'workspace.archiveTar' => 'TAR archive',
			'workspace.archiveRar' => 'RAR archive',
			'workspace.archiveCbz' => 'CBZ archive',
			'workspace.archiveCbr' => 'CBR archive',
			'workspace.archive7z' => '7Z archive',
			'workspace.last12Weeks' => 'Last 12 weeks',
			'workspace.recentReading' => 'Reading recently',
			'workspace.downloadedLabel' => 'Downloaded',
			'workspace.bookUnit' => 'books',
			'workspace.todayLabel' => 'today',
			'workspace.yesterdayLabel' => 'yesterday',
			'workspace.daysAgoLabel' => ({required Object n}) => '${n} days ago',
			'workspace.readingTools' => 'Reading tools',
			'workspace.filesBrowseSubtitle' => 'Browse, search and organize local files',
			'workspace.openFilesAction' => 'Open',
			'workspace.noMoreHistory' => 'No earlier records',
			'workspace.continueNextHint' => 'Pick up where you left off',
			'workspace.openAll' => 'All',
			'workspace.toolsStandaloneHint' => 'Synced with reading settings',
			'appName' => 'Rossi',
			'common.nameNoSlash' => 'The name can\'t contain / or \\',
			'common.startupStage' => ({required Object stage}) => 'Stage: ${stage}',
			'common.appStartupFailed' => 'The app failed to start',
			'common.openLocalComicRossi' => 'Open a local comic (Rossi\'s own reader + zero-copy GPU)',
			'common.neoViewWorkspace' => 'NeoView workspace',
			'common.openWithRossi' => 'Open with Rossi',
			'common.showInExplorer' => 'Show in Explorer',
			'common.showInFinder' => 'Show in Finder',
			'common.showInFileManager' => 'Show in file manager',
			'common.revealInFileManagerFolder' => 'Open the containing folder in the file manager',
			'common.deleteListLabel' => 'Delete list',
			'common.pleaseEnterName' => 'Please enter a name',
			'common.ok' => 'OK',
			'common.cancel' => 'Cancel',
			'common.save' => 'Save',
			'common.delete' => 'Delete',
			'common.edit' => 'Edit',
			'common.rename' => 'Rename',
			'common.add' => 'Add',
			'common.create' => 'Create',
			'common.refresh' => 'Refresh',
			'common.loading' => 'Loading...',
			'common.loadingFailed' => 'Loading failed',
			'common.retry' => 'Retry',
			'common.reload' => 'Reload',
			'common.confirm' => 'Confirm',
			'common.close' => 'Close',
			'common.back' => 'Back',
			'common.help' => 'Help',
			'common.gotIt' => 'Got it',
			'common.underConstruction' => 'Under construction',
			'common.comingSoon' => 'Coming soon',
			'common.root' => 'Root',
			'common.remove' => 'Remove',
			'common.overwrite' => 'Overwrite',
			'common.cancelled' => 'Cancelled',
			'common.search' => 'Search',
			'common.clear' => 'Clear',
			'common.copy' => 'Copy',
			'common.paste' => 'Paste',
			'common.share' => 'Share',
			'common.open' => 'Open',
			'common.download' => 'Download',
			'common.upload' => 'Upload',
			'common.import' => 'Import',
			'common.export' => 'Export',
			'common.success' => 'Success',
			'common.failed' => 'Failed',
			'common.error' => 'Error',
			'common.warning' => 'Warning',
			'common.info' => 'Info',
			'common.unknown' => 'Unknown',
			'common.empty' => 'No data',
			'common.all' => 'All',
			'common.none' => 'None',
			'common.default_' => 'Default',
			'common.custom' => 'Custom',
			'common.enabled' => 'Enabled',
			'common.disabled' => 'Disabled',
			'common.followSystem' => 'Follow system',
			'common.lightMode' => 'Light mode',
			'common.darkMode' => 'Dark mode',
			'common.system' => 'System',
			'common.apply' => 'Apply',
			'common.reset' => 'Reset',
			'common.next' => 'Next',
			'common.previous' => 'Previous',
			'common.done' => 'Done',
			'common.select' => 'Select',
			'common.selected' => 'Selected',
			'common.deselect' => 'Deselect',
			'common.selectAll' => 'Select all',
			'common.yes' => 'Yes',
			'common.no' => 'No',
			'common.on' => 'On',
			'common.off' => 'Off',
			'common.more' => 'More',
			'common.detail' => 'Details',
			'common.settingSaved' => 'Settings saved',
			'common.restartToTakeEffect' => 'Setting saved, restart to take effect',
			'error.generic' => 'Something went wrong',
			'error.network' => 'Network error',
			'error.downloadFailed' => 'Download failed',
			'error.importFailed' => ({required Object error}) => 'Import failed: ${error}',
			'error.loadFailed' => 'Loading failed',
			'error.saveFailed' => 'Save failed',
			'error.permissionDenied' => 'Permission denied',
			'error.notFound' => 'Not found',
			'error.unsupportedPlatform' => 'This feature is not supported on the current platform',
			'error.missingPluginSource' => ({required Object action}) => 'Missing plugin source, cannot ${action}',
			'error.operationFailed' => 'Operation failed',
			'error.executionFailed' => 'Execution failed',
			'navigation.home' => 'Home',
			'navigation.rank' => 'Rank',
			'navigation.bookshelf' => 'Bookshelf',
			'navigation.discover' => 'Discover',
			'navigation.more' => 'More',
			'navigation.syncSuccess' => 'Synced successfully!',
			'navigation.autoSyncSuccess' => 'Auto sync successful!',
			'navigation.syncFailed' => 'Sync failed',
			'navigation.autoSyncFailed' => 'Auto sync failed',
			'navigation.syncFailedMessage' => ({required Object error}) => 'Please check your network connection or try again later.\n${error}',
			'navigation.loginExpired' => 'Login expired, please log in again',
			'navigation.needLoginTitle' => 'Login required',
			'navigation.goLogin' => 'Log in',
			'navigation.sidebarCollapse' => 'Collapse sidebar',
			'navigation.sidebarExpand' => 'Expand sidebar',
			'navigation.navigationChrome' => 'Navigation',
			'navigation.sidebarEnabled' => 'Arc-style sidebar',
			'navigation.sidebarEnabledSubtitle' => 'Desktop and tablet navigate from a left sidebar; turn off for the previous rail',
			'navigation.sidebarExpanded' => 'Sidebar expanded',
			'navigation.sidebarExpandedSubtitle' => 'Expanded rows carry labels, collapsed ones only icons; the button at the top of the sidebar toggles it any time',
			'navigation.dockEnabled' => 'Floating dock',
			'navigation.dockEnabledSubtitle' => 'Narrow screens get a floating pill at the foot; turn off for the previous bottom bar',
			'navigation.autoNarrowMobileLayout' => 'Switch to the mobile layout when narrow',
			'navigation.autoNarrowMobileLayoutSubtitle' => 'Below the threshold, the sidebar gives way to the bottom dock (small desktop windows, split-screen tablets)',
			'navigation.narrowNavigationWidth' => 'Narrow-screen threshold',
			'navigation.narrowNavigationWidthSubtitle' => 'A window narrower than this many logical pixels counts as narrow',
			'navigation.narrowNavigationWidthReset' => ({required Object value}) => 'Reset to default (${value})',
			'navigation.moreActions' => 'More actions',
			'navigation.customize' => 'Customize navigation',
			'navigation.customizeTitle' => 'Customize navigation',
			'navigation.customizeHint' => 'Drag to reorder each section, add or hide freely; the arrow on an action moves it between the main area and the bottom shortcuts',
			'navigation.dockLongPressCustomize' => 'Long-press dock to customize',
			'navigation.dockLongPressCustomizeSubtitle' => 'Hold any destination on the dock to open navigation customization',
			'navigation.dockLongPressDuration' => 'Long-press duration',
			'navigation.dockLongPressDurationSubtitle' => 'How long to hold before it triggers (too short clashes with switching pages)',
			'navigation.dockLongPressDurationReset' => ({required Object value}) => 'Reset to default (${value})',
			'navigation.millisecondUnit' => ({required Object value}) => '${value} ms',
			'navigation.customizeMainSection' => 'Main area',
			'navigation.customizeActionsSection' => 'Bottom shortcuts',
			'navigation.customizeActionsHint' => 'Shown at the sidebar foot, or in the dock\'s overflow menu — actions only',
			'navigation.customizeDesktopTab' => 'Desktop sidebar',
			'navigation.customizeMobileTab' => 'Mobile dock',
			'navigation.customizeReset' => 'Reset',
			'navigation.customizeDone' => 'Done',
			'navigation.customizeAvailable' => 'Available items',
			'navigation.customizeHide' => 'Hide',
			'navigation.customizeActionTag' => 'Action',
			'navigation.customizeMoveToMain' => 'Move to main area',
			'navigation.customizeMoveToActions' => 'Move to bottom shortcuts',
			'navigation.workspace' => 'Workspace',
			'navigation.openLocalComic' => 'Open local comic',
			'navigation.gpuPresent' => 'GPU present',
			'settings.allLanePanelsHidden' => 'Every panel in this lane is hidden —\nenable the ones you need under Global settings → Lane panel kanban.',
			'settings.localTreeArchiveSize' => ({required Object size}) => 'Comic archive · ${size}',
			'settings.localTreeOpenThisFolder' => 'Open this folder directly',
			'settings.localTreeEmpty' => 'No subfolders or comic files in this folder',
			'settings.localTreeReadFailed' => ({required Object error}) => 'Read failed: ${error}',
			'settings.localTreeOpenFolder' => 'Open this folder',
			'settings.localTreeTitle' => 'Local file tree (mImageViewer core)',
			'settings.debugNoRustDiagnostics' => 'The native side returned no Rust diagnostics (the DLL and the bridge may be out of sync).',
			'settings.debugBrowse' => 'Browse...',
			'settings.debugLocalSourceGroup' => 'Local sources (loose folders / .cbz / .cbr)',
			'settings.debugRefreshStats' => 'Refresh stats',
			'settings.tabSideRight' => 'Vertical (right)',
			'settings.tabSideLeft' => 'Vertical (left)',
			'settings.tabSideTop' => 'Horizontal (top bar)',
			'settings.tabPolicyTriggering' => 'Inherit the triggering tab',
			'settings.tabPolicyRecent' => 'Inherit the most recently used tab',
			'settings.tabPolicyDefaults' => 'Use preset defaults',
			'settings.dragToLaneEnd' => 'Drag a panel here to append it',
			'settings.dropToLaneEnd' => 'Release to append to this lane',
			'settings.moveToLeftLane' => 'Move to left lane',
			'settings.moveToRightLane' => 'Move to right lane',
			'settings.kanbanRank' => ({required Object n}) => 'Rank #${n}',
			'settings.kanbanShowPanel' => 'Show this panel in the panel bar',
			'settings.kanbanHideCompletely' => 'Hide from the panel bar (leaves no hidden icon)',
			'settings.kanbanReaderLaneDesc' => 'This lane is reserved for the comic page you are reading. Use the lane-order bar above or the arrows at the top-right of this column to move the reader to the left, centre or right.',
			'settings.kanbanReaderCanvasTitle' => 'Comic reader main canvas',
			'settings.kanbanVisibleHidden' => ({required Object visible, required Object hidden}) => '${visible} visible · ${hidden} hidden',
			'settings.kanbanAllVisible' => ({required Object count}) => '${count} panels (all visible)',
			'settings.kanbanReaderLaneTitle' => 'Reader main-view lane',
			'settings.kanbanLaneIndex' => ({required Object n}) => 'Lane ${n}',
			'settings.kanbanLaneOrderTitle' => 'Lane order (drag sideways or tap the arrows to move)',
			'settings.kanbanHiddenPanels' => ({required Object count}) => '${count} panels fully hidden',
			'settings.kanbanVisiblePanels' => ({required Object count}) => '${count} panels visible',
			'settings.kanbanLaneOrder' => ({required Object order}) => 'Lane order: ${order}',
			'settings.kanbanDragHint' => 'Drag or use the buttons to reorder lanes, reorder the panels within each lane, and toggle visibility. Hidden panels are removed from the panel bar entirely, with no hidden icon left behind.',
			'settings.rightLane' => 'Right lane',
			'settings.leftLane' => 'Left lane',
			'settings.swimlanePanelKanbanConfigTitle' => 'Lane panel kanban configuration',
			'settings.revealZonePointerHint' => 'This device has no hover pointer: these reveal zones only work when the mouse hugs the edge. On touch, use the narrow rails on either side of the solo Reader to switch lanes.',
			'settings.laneCustomDelayMs' => 'This lane · milliseconds',
			'settings.inheritedGlobalDelay' => ({required Object ms}) => 'Inherited from global: ${ms} ms',
			'settings.fmViewColumns' => 'Columns view',
			'settings.fmViewTree' => 'Tree view',
			'settings.fmViewContent' => 'Content view',
			'settings.fmDefaultContentLayout' => 'Default content layout',
			'settings.fmDefaultEntryStyle' => 'Default entry style',
			'settings.fmTabPolicyHint' => '“Recent” follows the active tab; “Triggering” follows the tab that started the action. Only browsing and search options are inherited — query, results, history and selection stay separate. With no source on first open, the preset is used.',
			'settings.fmTabPolicySource' => 'Policy source',
			'settings.favoriteTagExampleHint' => 'school_lolita | 学校萝莉 | School Lolita\nloli',
			'settings.noMatchingArtist' => 'No matching artists',
			'settings.favoriteArtistExampleHint' => 'Artist name\n[Circle name (artist)]\nAnother artist',
			'settings.confirmResetPin' => 'Confirm reset PIN',
			'settings.defaultHoverDelaySubtitle' => 'Used when a lane has no delay of its own',
			'settings.defaultHoverDelay' => 'Default hover reveal delay',
			'settings.enterWorkspaceSubtitle' => 'Opens with the presentation selected below; use the system back key to exit',
			'settings.enterWorkspace' => 'Enter workspace',
			'settings.workspaceNarrowMobileHost' => 'Mobile workspace in narrow windows',
			'settings.workspaceNarrowMobileHostSubtitle' => 'On desktop, workspace entries below the navigation narrow-width threshold open the mobile workspace. Turn off to always use the desktop lanes.',
			'settings.kanbanLaneMoveRight' => 'Move lane right',
			'settings.kanbanLaneMoveLeft' => 'Move lane left',
			'settings.kanbanPanelMoveDown' => 'Move panel down',
			'settings.kanbanPanelMoveUp' => 'Move panel up',
			'settings.kanbanLaneDefaultHidden' => 'Hidden by default',
			'settings.kanbanLanePinned' => 'Pinned lane',
			'settings.kanbanFullyHidden' => 'Fully hidden',
			'settings.kanbanVisible' => 'Visible',
			'settings.kanbanRestoreDefault' => 'Restore default layout',
			'settings.swimlanePanelKanbanDesc' => 'Use the kanban to reorder lanes, order the panels on each lane, and show or fully hide them',
			'settings.laneHoverDelayInherit' => 'Restore the inherited global delay',
			'settings.laneHoverDelay' => 'Hover reveal delay',
			'settings.laneHoverRevealSubtitle' => 'After dwelling, move the workspace so this lane shows in full',
			'settings.laneHoverReveal' => 'Reveal in full on hover',
			'settings.laneKeyboardFollowsMouseSubtitle' => 'Once the pointer enters this lane, hand keyboard control to it',
			'settings.laneKeyboardFollowsMouse' => 'Keyboard target follows the pointer',
			'settings.laneInteraction' => 'Lane interaction',
			'settings.swimlanePanelKanbanSubtitle' => 'Lane order · per-lane panel order · show or fully hide panels',
			'settings.swimlanePanelKanban' => 'Lane & panel kanban',
			'settings.fmNewTabPresetHint' => 'Preset defaults apply only when “Use preset defaults” is on; the default recursive scope follows the search settings below. Duplicating a tab or restoring a closed one keeps its own settings.',
			'settings.fmNewTabShowInternal' => 'Show internal entries by default',
			'settings.fmNewTabShowHidden' => 'Show hidden items by default',
			'settings.fmNewTabPassthrough' => 'Passthrough by default',
			'settings.fmNewTabStartup' => 'New tab startup options',
			'settings.importFileTxtJsonEmm' => 'Import file (TXT/JSON/EMM setting.json)',
			'settings.searchArtistHint' => 'Search artists...',
			'settings.importFileTxtJson' => 'Import file (TXT/JSON)',
			'settings.debugGpuPresentSubtitle' => 'Rust decode → wgpu → GPU copy → shared texture, pixels never cross the bridge',
			'settings.debugGpuPresent' => 'GPU present (D3D12 shared texture)',
			'settings.debugOcrSmokeSubtitle' => 'Pick a page → detect / recognise / erase / translate / refill, with per-stage timing and outputs',
			'settings.debugOcrSmoke' => 'OCR finished-page smoke test',
			'settings.debugLocalSourceSubtitle' => 'Direct read of loose-image folders / CBZ / CBR, with per-page timing and rejection categories',
			'settings.debugLocalSource' => 'Local source reading (criterion A)',
			'settings.setResetPin' => 'Set reset PIN',
			'settings.overviewSubtitle' => 'Make Rossi feel like yours',
			'settings.searchCategories' => 'Search settings categories',
			'settings.noMatchingCategories' => 'No matching categories. Try another keyword.',
			'settings.personalizationGroup' => 'Appearance & feedback',
			'settings.readingGroup' => 'Reading & image',
			'settings.libraryGroup' => 'Files, library & data',
			'settings.applicationGroup' => 'App & controls',
			'settings.windowGroup' => 'Window',
			'settings.syncDestinationsSubtitle' => 'Sync service · Cloud backup',
			'settings.title' => 'Settings',
			'settings.globalTitle' => 'Settings',
			'settings.appearance' => 'Appearance',
			'settings.theme' => 'Theme mode',
			'settings.themeSubtitle' => 'Choose strategy to switch light/dark theme',
			'settings.themeColor' => 'Theme color',
			'settings.tweakcnTitle' => 'Import Tweakcn theme',
			'settings.tweakcnSubtitle' => 'Paste the CSS variables copied from tweakcn, or a shadcn registry JSON',
			'settings.tweakcnHint' => ':root {\n  --background: oklch(1 0 0);\n  --primary: oklch(0.628 0.258 29.2);\n}',
			'settings.tweakcnImport' => 'Import',
			'settings.tweakcnNameField' => 'Theme name (optional)',
			'settings.tweakcnPickHint' => 'Tap a row to make it current',
			'settings.tweakcnEntryMeta' => ({required Object count, required Object radius}) => '${count} tokens · radius ${radius}',
			'settings.tweakcnDelete' => 'Delete this theme',
			'settings.tweakcnEnabled' => 'Use the imported theme',
			'settings.tweakcnApplied' => ({required Object count, required Object radius}) => '${count} color tokens imported · radius ${radius}',
			'settings.tweakcnNoRadius' => 'default',
			'settings.tweakcnFailedEmpty' => 'Nothing to import',
			_ => null,
		} ?? switch (path) {
			'settings.tweakcnFailedJson' => 'Not recognizable JSON',
			'settings.tweakcnFailedNoColors' => 'No color token could be parsed',
			'settings.tweakcnSkipped' => ({required Object keys}) => 'Skipped tokens with unreadable colors: ${keys}',
			'settings.tweakcnFallbackRoles' => ({required Object roles}) => 'Required tokens the theme omits, values substituted: ${roles}',
			'settings.themeColorSubtitle' => 'Choose primary color for the app',
			'settings.language' => 'Language',
			'settings.languageSubtitle' => 'Change app display language',
			'settings.followSystemLanguage' => 'Follow system',
			'settings.languageZhCn' => '简体中文 (zh_CN)',
			'settings.languageEnUs' => 'English (en_US)',
			'settings.languageChangedRestartHint' => 'Language setting saved. Restart the app for changes to fully take effect.',
			'settings.dynamicColor' => 'Dynamic color',
			'settings.dynamicColorSubtitle' => 'Extract primary color from content automatically',
			'settings.fontSettings' => 'Font settings',
			'settings.fontSettingsSubtitle' => 'Customize display font',
			'settings.amoled' => 'AMOLED black',
			'settings.amoledSubtitle' => 'Use pure black background for AMOLED screens',
			'settings.notchAdaptation' => 'Notch adaptation',
			'settings.notchAdaptationSubtitle' => 'Reserve safe area to avoid content being obscured',
			'settings.transparentDesktopTitleBar' => 'Transparent title bar',
			'settings.transparentDesktopTitleBarSubtitle' => 'The title bar no longer paints a background and blends into the page (text and window buttons may be hard to read on light content). Desktop only',
			'settings.transparentTitleBarRow' => 'Separate row',
			'settings.transparentTitleBarRowSubtitle' => 'The bar keeps its own row with no background; content starts below it (default)',
			'settings.transparentTitleBarOverlay' => 'Fused overlay',
			'settings.transparentTitleBarOverlaySubtitle' => 'Content extends to the window top and the bar floats over it',
			'settings.toastStyle' => 'Toast style',
			'settings.toastStyleSubtitle' => 'Position, duration and size of in-app toasts',
			'settings.toastSectionLayout' => 'Position & size',
			'settings.toastSectionAppearance' => 'Appearance & behavior',
			'settings.toastSectionBehavior' => 'Duration & motion',
			'settings.toastSectionStyle' => 'Visuals',
			'settings.toastPosition' => 'Position',
			'settings.toastPositionSubtitle' => 'Which corner the toast sticks to',
			'settings.toastPositionTopLeft' => 'Top left',
			'settings.toastPositionTopCenter' => 'Top center',
			'settings.toastPositionTopRight' => 'Top right',
			'settings.toastPositionMiddleLeft' => 'Middle left',
			'settings.toastPositionCenter' => 'Center',
			'settings.toastPositionMiddleRight' => 'Middle right',
			'settings.toastPositionBottomLeft' => 'Bottom left',
			'settings.toastPositionBottomCenter' => 'Bottom center',
			'settings.toastPositionBottomRight' => 'Bottom right',
			'settings.toastEdgePadding' => 'Edge padding',
			'settings.toastEdgePaddingSubtitle' => 'Distance between the toast and the screen edge',
			'settings.toastMaxWidth' => 'Max width',
			'settings.toastMaxWidthSubtitle' => 'Width limit of the toast; narrow screens clamp it further',
			'settings.toastMaxVisible' => 'Visible at once',
			'settings.toastMaxVisibleSubtitle' => 'How many toasts stack on screen; extra ones push out the oldest',
			'settings.toastDuration' => 'Auto close',
			'settings.toastDurationSubtitle' => 'Drag to the far left to keep it until closed manually',
			'settings.toastDurationPermanent' => 'Persistent',
			'settings.toastOpacity' => 'Opacity',
			'settings.toastOpacitySubtitle' => 'Opacity of the whole toast, text included',
			'settings.toastAnimation' => 'Enter/exit animation',
			'settings.toastAnimationSubtitle' => 'Duration of the appear and disappear animation',
			'settings.toastLiquidGlass' => 'Liquid glass',
			'settings.toastLiquidGlassSubtitle' => 'Use a blurred translucent background for toasts',
			'settings.toastShowProgressBar' => 'Show progress bar',
			'settings.toastShowProgressBarSubtitle' => 'Show a thin line shrinking with the remaining time',
			'settings.toastShowIcon' => 'Show type icon',
			'settings.toastShowIconSubtitle' => 'Show a success/error icon on the left of the toast',
			'settings.toastShowCloseButton' => 'Show close button',
			'settings.toastShowCloseButtonSubtitle' => 'Persistent toasts always keep the close button',
			'settings.toastPreview' => 'Show a test toast',
			'settings.toastPreviewTitle' => 'Toast style preview',
			'settings.toastPreviewLongMessage' => 'This is a preview toast: long text wraps automatically instead of being truncated or turned into a dialog.',
			'settings.toastReset' => 'Reset toast style',
			'settings.toastResetDone' => 'Toast style restored to defaults',
			'settings.contentAndNetwork' => 'Content & Network',
			'settings.content' => 'Content',
			'settings.fullSourceList' => 'Full source list',
			'settings.fullSourceListSubtitle' => 'When off, some sources are hidden from Discover, search and the plugin store. Turn on to show all sources',
			'settings.network' => 'Network',
			'settings.maskedKeywords' => 'Masked keywords',
			'settings.maskedKeywordsSubtitle' => 'Add keywords to filter unwanted content (search only)',
			'settings.maskedKeywordsEmpty' => 'No masked keywords',
			'settings.maskedKeywordsInputHint' => 'Enter new keyword...',
			'settings.favoriteArtistHighlight' => 'Highlight Favorite Artists',
			'settings.favoriteArtistHighlightSubtitle' => 'Highlight comics by preferred artists on cards and detail page',
			'settings.cardBadges' => 'Card Badges',
			'settings.cardDownloadBadge' => 'Download Badge',
			'settings.cardDownloadBadgeSubtitle' => 'Show a download button on the top-right of covers; tap it to download the whole comic',
			'settings.cardTranslationBadge' => 'Language Badge',
			'settings.cardTranslationBadgeSubtitle' => 'Detect translated / Chinese / raw from tags and mark the top-left of covers',
			'settings.cardReadButton' => 'Read Button',
			'settings.cardReadButtonSubtitle' => 'Show a read button in the middle of covers; tap it to start reading right away (resumes if there is progress) without opening the detail page',
			'settings.cardUnreadIndicator' => 'Unread Indicator',
			'settings.cardUnreadIndicatorSubtitle' => 'Mark comics you downloaded but never opened, under the download badge on covers',
			'settings.cardUnreadIndicatorStyle' => 'Unread Indicator Style',
			'settings.cardUnreadIndicatorStyleSubtitle' => 'Each step is easier to spot and covers more of the artwork',
			'settings.cardUnreadIndicatorStyleDot' => 'Dot',
			'settings.cardUnreadIndicatorStyleDisc' => 'Disc',
			'settings.cardUnreadIndicatorStyleLabel' => 'Label',
			'settings.cardInteraction' => 'Card Interaction',
			'settings.shelfCardContextMenu' => 'Context Menu on Favorite / History Cards',
			'settings.shelfCardContextMenuSubtitle' => 'Right-click an entry (long-press on touch) for open, open in a new file manager tab, copy, favorite and remove',
			'settings.favoriteArtistManagement' => 'Favorite Artists Management',
			'settings.favoriteArtistManagementSubtitle' => ({required Object count}) => '${count} artists added',
			'settings.favoriteArtistManagementSubtitleEmpty' => 'No favorite artists added',
			'settings.favoriteArtistInputHint' => 'Enter artist name...',
			'settings.favoriteArtistAdd' => 'Add',
			'settings.favoriteArtistBatchImport' => 'Batch Import / Edit',
			'settings.favoriteArtistBatchImportHint' => 'One artist per line or comma-separated; [circle (artist)] entries are kept verbatim and both names take part in matching',
			'settings.favoriteArtistImportSuccess' => ({required Object count}) => 'Updated artists list (${count} total)',
			'settings.favoriteArtistClear' => 'Clear All',
			'settings.favoriteArtistClearConfirm' => 'Are you sure you want to clear all favorite artists?',
			'settings.favoriteArtistCircleMode' => 'Circle Name Matching',
			'settings.favoriteArtistCircleModeSubtitle' => 'Whether a circle name in the title or tags counts as a hit',
			'settings.favoriteArtistCircleOff' => 'Ignore circles',
			'settings.favoriteArtistCircleFallback' => 'Only without artist',
			'settings.favoriteArtistCircleIndependent' => 'Independent (artist first)',
			'settings.favoriteArtistBadge' => 'Favorite Artist',
			'settings.addToFavoriteArtist' => 'Add to Favorite Artists',
			'settings.removeFromFavoriteArtist' => 'Remove from Favorite Artists',
			'settings.addedToFavoriteArtist' => ({required Object name}) => 'Added to favorite artists: ${name}',
			'settings.removedFromFavoriteArtist' => ({required Object name}) => 'Removed from favorite artists: ${name}',
			'settings.favoriteTagHighlight' => 'Highlight Favorite Tags',
			'settings.favoriteTagHighlightSubtitle' => 'Mark favorite tags prominently on comic cards and the detail page',
			'settings.favoriteTagManagement' => 'Favorite Tags Management',
			'settings.favoriteTagManagementSubtitle' => ({required Object count}) => '${count} tags added',
			'settings.favoriteTagManagementSubtitleEmpty' => 'No favorite tags added',
			'settings.favoriteTagInputHint' => 'Enter tag name...',
			'settings.favoriteTagAdd' => 'Favorite',
			'settings.favoriteTagSearchHint' => 'Search tags...',
			'settings.favoriteTagNotFound' => 'No matching tags',
			'settings.favoriteTagBatchImport' => 'Batch Import / Edit',
			'settings.favoriteTagBatchImportHint' => 'One tag per line; separate aliases with | to match how each site spells it, e.g. school_lolita | 学校萝莉 | School Lolita',
			'settings.favoriteTagImportSuccess' => ({required Object count}) => 'Updated favorite tags (${count} total)',
			'settings.favoriteTagClear' => 'Clear All',
			'settings.favoriteTagClearConfirm' => 'Are you sure you want to clear all favorite tags?',
			'settings.favoriteTagBadge' => 'Favorite Tag',
			'settings.favoriteTagAliasSection' => 'Aliases',
			'settings.favoriteTagAliasEmpty' => 'No aliases set',
			'settings.favoriteTagAliasAdd' => 'Add alias',
			'settings.favoriteTagAliasInputHint' => 'How this tag is written on some site...',
			'settings.favoriteTagAliasHint' => 'Aliases cover the different spellings each source uses for one tag. Case, full-width/half-width and underscore vs space are normalized automatically, so no alias is needed for those.',
			'settings.favoriteTagAdded' => ({required Object name}) => 'Favorited tag: ${name}',
			'settings.favoriteTagRemoved' => ({required Object name}) => 'Removed favorite tag: ${name}',
			'settings.favoriteTagAlreadyAdded' => ({required Object name}) => 'Already favorited: ${name}',
			'settings.favoriteTagAliasAdded' => ({required Object name}) => 'Alias added: ${name}',
			'settings.favoriteTagAliasRemoved' => ({required Object name}) => 'Alias removed: ${name}',
			'settings.favoriteTagAliasDuplicate' => 'This alias already exists',
			'settings.addToFavoriteTag' => 'Favorite this tag',
			'settings.removeFromFavoriteTag' => 'Unfavorite this tag',
			'settings.cardFavoriteTagBadge' => 'Favorite Tag Badge',
			'settings.cardFavoriteTagBadgeSubtitle' => 'Show a badge on the top-left of covers that match a favorite tag',
			'settings.chineseConvert' => 'Chinese conversion',
			'settings.chineseConvertSubtitle' => 'Convert comic titles, descriptions, chapters and comments',
			'settings.chineseConvertOff' => 'Off',
			'settings.chineseConvertSimplified' => 'Simplified Chinese',
			'settings.chineseConvertTraditional' => 'Traditional Chinese',
			'settings.proxy' => 'Proxy',
			'settings.proxySubtitle' => 'Configure proxy address',
			'settings.proxyEnabledSubtitle' => 'Route network requests through a proxy when enabled',
			'settings.proxyAddress' => 'Proxy address',
			'settings.proxyHint' => 'Enter proxy address (HTTP / SOCKS5)',
			'settings.proxyCurrent' => ({required Object currentProxy}) => 'Current proxy: ${currentProxy}',
			'settings.proxyType' => 'Proxy type',
			'settings.proxyTypeSubtitle' => 'Choose proxy protocol',
			'settings.proxyTypeHttp' => 'HTTP',
			'settings.proxyTypeSocks5' => 'SOCKS5',
			'settings.updateAccelerate' => 'Update acceleration',
			'settings.updateAccelerateSubtitle' => 'Use proxy to accelerate GitHub update links',
			'settings.retryDownloadUntilSuccess' => 'Keep retrying failed downloads',
			'settings.retryDownloadUntilSuccessSubtitle' => 'Retry failed downloads until they succeed; stop on 404 or empty data',
			'settings.downloadSettings' => 'Download Settings',
			'settings.downloadConcurrency' => 'Download Concurrency',
			'settings.downloadConcurrencySubtitle' => 'Number of concurrent image download threads; reduce if facing rate limits or captcha',
			'settings.downloadTaskConcurrency' => 'Concurrent Chapter Downloads',
			'settings.downloadTaskConcurrencySubtitle' => 'How many chapters download at the same time; 1 = one by one. Lower it when hitting rate limits or captchas',
			'settings.downloadDelay' => 'Image Request Delay',
			'settings.downloadDelaySubtitle' => 'Pacing delay between image requests to prevent rate limiting (429)',
			'settings.downloadAutoRetryCount' => 'Auto Retry Count',
			'settings.downloadAutoRetryCountSubtitle' => 'Max automatic retry attempts when encountering transient network errors',
			'settings.sync' => 'Sync',
			'settings.syncConfig' => 'Sync config',
			'settings.syncConfigSubtitle' => 'Enter page to configure address and auth',
			'settings.syncService' => 'Sync service',
			'settings.syncServiceSubtitle' => 'Choose service to manage sync strategy',
			'settings.syncServiceNone' => 'Disabled',
			'settings.syncServiceWebdav' => 'WebDAV',
			'settings.syncServiceS3' => 'S3',
			'settings.autoSync' => 'Auto sync',
			'settings.autoSyncSubtitle' => 'Sync configuration periodically in background',
			'settings.notifyPersonalize' => 'Toast preferences',
			'settings.notifyPersonalizeSubtitle' => 'Decide which background toasts may interrupt you; responses to your own actions always show',
			'settings.notifySummaryMasterOff' => 'Background toasts are muted',
			'settings.notifySummaryAllOn' => 'Every background toast rings',
			'settings.notifySummaryOffCount' => ({required Object count}) => '${count} silenced',
			'settings.notifySectionAmbient' => 'Background toasts',
			'settings.notifyMaster' => 'Background toasts',
			'settings.notifyMasterHint' => 'Master switch. Turning it off silences everything below; button feedback is unaffected',
			'settings.notifyMasterOffNote' => 'Master switch is off: the values below are kept, but nothing rings right now.',
			'settings.notifySectionOutside' => 'Not covered by this table',
			'settings.notifySystemChannelNote' => 'System tray notifications (download finished, new chapters) are managed by the OS — turn them off in system settings, not here',
			'settings.notifyMergedSuffix' => ({required Object count}) => ' (+${count} more of this kind)',
			'settings.notifyTopicAction' => 'Action feedback',
			'settings.notifyTopicActionHint' => 'The reply after you tap something. Always shown, otherwise the button reads as broken',
			'settings.notifyTopicReaderSwitch' => 'Reader switch toasts',
			'settings.notifyTopicReaderSwitchHint' => 'Book / page / last-page switches live on the workspace\'s "Switch toast" card',
			'settings.notifyTopicSyncAutoSuccess' => 'Auto sync succeeded',
			'settings.notifyTopicSyncAutoSuccessHint' => 'The periodic sync every 5 minutes; identical text is merged within 10 minutes',
			'settings.notifyTopicSyncAutoFailure' => 'Auto sync failed',
			'settings.notifyTopicSyncAutoFailureHint' => 'Used to knock every 5 minutes with no way to silence it; now one merged toast per 10 minutes',
			'settings.notifyTopicDownloadComplete' => 'Download finished',
			'settings.notifyTopicDownloadCompleteHint' => 'Once per comic; repeated callbacks for the same one merge within 60 seconds',
			'settings.notifyTopicDownloadFailed' => 'Download failed',
			'settings.notifyTopicDownloadFailedHint' => 'Different error texts count as different events and never merge',
			'settings.notifyTopicFollowUpdate' => 'New chapters (follow list)',
			'settings.notifyTopicFollowUpdateHint' => 'The automatic check after launch; manual refresh counts as action feedback and is never silenced',
			'settings.notifyTopicPluginMessage' => 'Plugin script messages',
			'settings.notifyTopicPluginMessageHint' => 'Toasts a source plugin raises itself; scripts can loop, so identical text merges within 3 seconds',
			'settings.notifyTopicIntentOpen' => 'Opened from outside',
			'settings.notifyTopicIntentOpenHint' => 'Where a system context-menu or link hand-off landed',
			'settings.notifyTopicSystemPermission' => 'Notification permission',
			'settings.notifyTopicSystemPermissionHint' => 'Shown when the startup request for OS notification permission was denied',
			'settings.syncSettings' => 'Sync settings',
			'settings.syncSettingsSubtitle' => 'Use cloud settings to override local settings',
			'settings.syncPlugins' => 'Sync plugins',
			'settings.syncPluginsSubtitle' => 'Sync plugin configuration and installation status',
			'settings.manualSyncSection' => 'Manual sync',
			'settings.uploadToCloud' => 'Upload to cloud',
			'settings.uploadToCloudSubtitle' => 'Use local data as the source of truth and overwrite the cloud',
			'settings.downloadFromCloud' => 'Download from cloud',
			'settings.downloadFromCloudSubtitle' => 'Use cloud data as the source of truth and apply it locally',
			'settings.manualUpload' => 'Upload now',
			'settings.manualDownload' => 'Sync now',
			'settings.manualUploadSuccess' => 'Uploaded to cloud',
			'settings.manualDownloadSuccess' => 'Synced from cloud',
			'settings.manualSyncFailed' => 'Manual sync failed',
			'settings.appBehavior' => 'App behavior',
			'settings.splashPage' => 'Startup page',
			'settings.splashPageSubtitle' => 'Choose startup page to open directly',
			'settings.startWithWorkspace' => 'Workspace',
			'settings.workspaceSleepCoveredUi' => 'Sleep home pages while workspace is open',
			'settings.workspaceSleepCoveredUiSubtitle' => 'Release image memory of covered lists; images reload when you return',
			'settings.panelTabRightClickHide' => 'Hide Panel When Right-Clicking Its Icon',
			'settings.panelTabRightClickHideSubtitle' => 'When off, the icons on a lane\'s panel bar only switch panels - right-click and long-press no longer hide one. Hiding is silent: the icon disappears from the bar and there is no restore entry there, so a mis-click means going back to the "Lanes & Panels" board to bring it back.',
			'settings.skipUpdateCheck' => 'Skip update check',
			'settings.skipUpdateCheckSubtitle' => 'This build is a fork: it won\'t query the upstream release on startup and won\'t show update prompts',
			'settings.desktopCloseBehavior' => 'Close behavior',
			'settings.desktopCloseBehaviorSubtitle' => 'Choose behavior when clicking close button',
			'settings.desktopCloseAsk' => 'Ask',
			'settings.desktopCloseHide' => 'Hide to tray',
			'settings.desktopCloseClose' => 'Close directly',
			'settings.showMainWindow' => 'Show main window',
			'settings.exitApp' => 'Exit',
			'settings.appLock' => 'App lock',
			'settings.appLockSubtitle' => 'Require verification when entering the app',
			'settings.autoFollowOnCollect' => 'Auto-follow on collect',
			'settings.autoFollowOnCollectSubtitle' => 'Automatically add comics to the follow list when favorited',
			'settings.autoFavoriteOnDownload' => 'Auto-favorite on download',
			'settings.autoFavoriteOnDownloadSubtitle' => 'Automatically add comics to favorites when downloading',
			'settings.writeDownloadMetadataFile' => 'Write metadata file on download',
			'settings.writeDownloadMetadataFileSubtitle' => 'After a download finishes, write original_comic_info.json and processed_comic_info.json into the comic folder so other tools can read or re-import it',
			'settings.promptDownloadOptions' => 'Prompt for download options',
			'settings.promptDownloadOptionsSubtitle' => 'Show options (whole book / latest chapters / picker) when clicking download; when disabled, downloads all chapters directly',
			'settings.leftHandMode' => 'Left-hand mode',
			'settings.leftHandModeSubtitle' => 'Move floating action buttons and other controls to the left side',
			'settings.clickCoverToStartReading' => 'Tap cover to start reading',
			'settings.clickCoverToStartReadingSubtitle' => 'Tap the cover on the comic info page to start reading directly',
			'settings.searchHistoryGroupBySource' => 'Split search history by plugin',
			'settings.searchHistoryGroupBySourceSubtitle' => 'When on, every source gets its own search timeline instead of one mixed pile. "Aggregate search" holds cross-plugin queries; "Uncategorized" holds records saved before this feature, whose source is gone',
			'settings.comicInfoInlineReadButton' => 'Read button in comic info page',
			'settings.comicInfoInlineReadButtonSubtitle' => 'On desktop, put a read button next to Download in the action row and drop the floating read button at the bottom-right',
			'settings.comicInfoRailLiquidGlass' => 'Liquid glass for the action rail',
			'settings.comicInfoRailLiquidGlassSubtitle' => 'Render the floating capsules on the left and right of the comic info page with liquid glass; turn off for an opaque surface with an outline',
			'settings.androidKeepAlive' => 'Keep alive',
			'settings.androidKeepAliveSubtitle' => 'Use a foreground service to keep the app running in the background; shows a persistent notification',
			'settings.backPressExit' => 'Exit on back',
			'settings.backPressExitSubtitle' => 'When enabled, pressing back on the home page exits the app; when disabled, it only returns to the home page',
			'settings.bookshelf' => 'Bookshelf',
			'settings.bookshelfSubtitle' => 'Home tab & remember sort',
			'settings.bookshelfHomePage' => 'Bookshelf home',
			'settings.bookshelfHomePageSubtitle' => 'Choose the default tab',
			'settings.bookshelfRememberFavoriteSort' => 'Remember favorite sort',
			'settings.bookshelfRememberFavoriteSortSubtitle' => 'Remember the last sort choice for favorites',
			'settings.bookshelfRememberHistorySort' => 'Remember history sort',
			'settings.bookshelfRememberHistorySortSubtitle' => 'Remember the last sort choice for history',
			'settings.bookshelfRememberDownloadSort' => 'Remember download sort',
			'settings.bookshelfRememberDownloadSortSubtitle' => 'Remember the last sort choice for downloads',
			'settings.customExportPath' => 'Custom export path',
			'settings.exportIncludeCover' => 'Include cover image in export',
			'settings.exportIncludeCoverSubtitle' => 'When on, the exported folder or zip also carries a cover image, fetched again at export time. Off by default: the artifact holds the pages plus the two info JSON files, and the cover is still shown online from the URL in that JSON',
			'settings.detailLayout' => 'Detail layout',
			'settings.detailLayoutSubtitle' => 'Show comic lists as horizontal detail rows with author and category info',
			'settings.reverseChapters' => 'Reverse chapters',
			'settings.reverseChaptersSubtitle' => 'Show chapters in reverse order by default on the detail page',
			'settings.storage' => 'Storage',
			'settings.cache' => 'Cache',
			'settings.clearCache' => 'Clear cache',
			'settings.clearCacheConfirm' => 'Are you sure you want to clear all cache files? This action cannot be undone.',
			'settings.calculatingCache' => 'Calculating...',
			'settings.calculateCacheFailed' => 'Calculate failed',
			'settings.dataBackup' => 'Local Import/Export',
			'settings.dataBackupSubtitle' => 'Transfer settings and data between mobile and desktop using ZIP; keep device-specific settings',
			'settings.includeDownloaded' => 'Include downloaded comics',
			'settings.includeDownloadedSubtitle' => 'Pack downloaded comic files when exporting',
			'settings.exportData' => 'Export data',
			'settings.importData' => 'Import data',
			'settings.imageProcessing' => 'Image processing',
			'settings.realSr' => 'Image Super-Resolution (Experimental)',
			'settings.ocr' => 'Manga Translation (Finished Pages)',
			'settings.ocrSubtitle' => 'Experimental; needs model download and a translation endpoint',
			'settings.realSrSubtitle' => 'Experimental feature, may be unstable',
			'settings.eink' => 'E-ink',
			'settings.einkSubtitle' => 'Page-turn animation · full refresh · loading',
			'settings.einkPageTitle' => 'E-ink adaptation',
			'settings.einkDetected' => 'Detected as an e-ink device',
			'settings.einkNotDetected' => 'No e-ink device detected, you can enable it manually',
			'settings.einkEnabled' => 'Enable e-ink mode',
			'settings.einkEnabledSubtitle' => 'Remove animations and refresh the whole screen periodically',
			'settings.einkSectionAnimation' => 'Animation & transitions',
			'settings.einkNoRouteTransition' => 'Remove page transition animation',
			'settings.einkNoRouteTransitionSubtitle' => 'Show pages instantly instead of sliding and fading',
			'settings.einkNoScrollBounce' => 'Remove scroll overscroll',
			'settings.einkNoScrollBounceSubtitle' => 'Stop at the edge instead of bouncing in webtoon mode',
			'settings.einkSectionLoading' => 'Loading',
			'settings.einkSectionRefresh' => 'Refresh',
			'settings.einkRefreshMode' => 'Full-screen refresh',
			'settings.einkRefreshNone' => 'Disabled',
			'settings.einkRefreshWhite' => 'White flash',
			'settings.einkRefreshFull' => 'Black & white flash',
			'settings.einkRefreshHint' => 'A full refresh flashes white or black-and-white to clear the ghost of the previous page.',
			'settings.einkRefreshNow' => 'Refresh now',
			'settings.einkRefreshDone' => 'Screen refreshed',
			'settings.einkAutoRefreshTurns' => 'Auto refresh every N pages',
			'settings.einkAutoRefreshOff' => 'Never',
			'settings.einkShowRefreshButton' => 'Show refresh button',
			'settings.einkShowRefreshButtonSubtitle' => 'Keep a manual full refresh in a reader corner',
			'settings.einkNoSpinner' => 'No loading spinner',
			'settings.einkNoSpinnerSubtitle' => 'A spinning indicator forces the panel to keep doing partial refreshes',
			'settings.autoRealSr' => 'Auto super-resolution',
			'settings.resolutionThreshold' => 'Resolution threshold',
			'settings.debug' => 'Debug',
			'settings.logAddress' => 'Log forward address',
			'settings.logAddressSubtitle' => 'Forward logs to specified address in real time',
			'settings.memoryDebug' => 'Memory debug',
			'settings.memoryDebugSubtitle' => 'Show memory usage on interface',
			'settings.blockRustHttpRequests' => 'Block Rust HTTP requests',
			'settings.blockRustHttpRequestsSubtitle' => 'All Rust HTTP requests fail immediately without being sent',
			'settings.showLayoutOverflowStripes' => 'Show layout overflow stripes',
			'settings.showLayoutOverflowStripesSubtitle' => 'When off, the yellow-black stripes and the overflow error reports are suppressed for our own layouts. Flutter has no global switch: other widgets only lose the stripes in a profile build',
			'settings.forceEnableImpeller' => 'Force enable Impeller',
			'settings.forceEnableImpellerSubtitle' => 'Android experimental rendering backend',
			'settings.colorPreview' => 'Color preview',
			'settings.colorPreviewSubtitle' => 'Open color picker page for quick preview',
			'settings.qjsRuntimeDebug' => 'QJS runtime debug',
			'settings.qjsRuntimeDebugSubtitle' => 'Enter runtime ID to capture debug snapshot',
			'settings.qjsRuntimeSnapshot' => 'Debug snapshot',
			'settings.qjsRuntimeIdLabel' => 'Runtime ID',
			'settings.qjsRuntimeIdHint' => 'e.g. 0a0e5858-a467-4702-994a-79e608a4589d',
			'settings.qjsRuntimeCapture' => 'Capture snapshot',
			'settings.qjsRuntimeCapturing' => 'Capturing...',
			'settings.qjsRuntimeCopyOutput' => 'Copy output',
			'settings.qjsRuntimeNoOutput' => 'No output yet',
			'settings.qjsRuntimeFillId' => 'Please enter a runtime ID first',
			'settings.qjsRuntimeCapturedAt' => ({required Object dateTime}) => 'Captured at ${dateTime}',
			'settings.qjsRuntimeCaptureFailed' => ({required Object error}) => 'Capture failed: ${error}',
			'settings.qjsRuntimeNoCopyContent' => 'No content to copy',
			'settings.qjsRuntimeCopied' => 'Copied to clipboard',
			'settings.colorPreviewVariableFont' => 'Variable Font test',
			'settings.colorPreviewFontLoaded' => ({required Object path}) => 'Loaded: ${path}',
			'settings.colorPreviewNoFont' => 'No font loaded. Try the recommended sample or pick a TTF/OTF file.',
			'settings.colorPreviewLoadRecommended' => 'Load recommended sample',
			'settings.colorPreviewSelectFont' => 'Select font file',
			'settings.colorPreviewByWeight' => 'Render by fontWeight',
			'settings.colorPreviewByVariableAxis' => 'Render by variable axis',
			'settings.colorPreviewSystemDefault' => 'System default font reference',
			'settings.colorPreviewLoadingFont' => 'Loading font...',
			'settings.colorPreviewLoadSuccess' => 'Font loaded. Compare different weights.',
			'settings.colorPreviewLoadFailed' => ({required Object error}) => 'Font load failed: ${error}',
			'settings.colorRed' => 'Red',
			'settings.colorPink' => 'Pink',
			'settings.colorPurple' => 'Purple',
			'settings.colorDeepPurple' => 'Deep purple',
			'settings.colorIndigo' => 'Indigo',
			'settings.colorBlue' => 'Blue',
			'settings.colorLightBlue' => 'Light blue',
			'settings.colorCyan' => 'Cyan',
			'settings.colorTeal' => 'Teal',
			'settings.colorGreen' => 'Green',
			'settings.colorLightGreen' => 'Light green',
			'settings.colorLime' => 'Lime',
			'settings.colorYellow' => 'Yellow',
			'settings.colorAmber' => 'Amber',
			'settings.colorOrange' => 'Orange',
			'settings.colorDeepOrange' => 'Deep orange',
			'settings.colorBrown' => 'Brown',
			'settings.colorGrey' => 'Grey',
			'settings.colorBlueGrey' => 'Blue grey',
			'settings.colorMaskRed' => 'Mask red',
			'settings.colorPresets' => 'Preset colors',
			'settings.coremlDebug' => 'CoreML upscale debug',
			'settings.coremlDebugSubtitle' => 'Test CoreML upscale with absolute path model',
			'settings.aboutAndMore' => 'About & More',
			'settings.changelog' => 'Changelog',
			'settings.changelogSubtitle' => 'View update records for each version',
			'settings.aboutApp' => 'About app',
			'settings.aboutAppSubtitle' => 'Detailed information about Rossi',
			'settings.pluginManagement' => 'Plugin management',
			'settings.debugMode' => 'Debug mode',
			'settings.debugAddress' => 'Debug address',
			'settings.notSet' => 'Not set',
			'settings.fileManager' => 'File manager',
			'settings.fileManagerSubtitle' => 'Home folder, toolbar and view memory for local browsing',
			'settings.fileManagerSectionHome' => 'Home',
			'settings.fileManagerHomeEnabled' => 'Enable home button',
			'settings.fileManagerHomeEnabledSubtitle' => 'When off, the file manager toolbar hides the home button',
			'settings.fileManagerHomePath' => 'Home folder',
			'settings.fileManagerHomePathSubtitle' => 'Where the home button jumps to',
			'settings.fileManagerHomePathEmpty' => 'Not set',
			'settings.fileManagerHomePathPick' => 'Choose folder',
			'settings.fileManagerHomePathClear' => 'Clear home',
			'settings.fileManagerHomePathCleared' => 'Home cleared',
			'settings.fileManagerHomePathStale' => 'That folder no longer exists, pick another one',
			'settings.fileManagerHomePathUnsupported' => 'Choosing a folder is not supported on this platform',
			'settings.fileManagerOpenHomeOnStart' => 'Open the home folder on start',
			'settings.fileManagerOpenHomeOnStartSubtitle' => 'The file manager starts in the home folder. Falls back to the nearest folder that still exists when that path is gone',
			'settings.fileManagerSectionToolbar' => 'Toolbar',
			'settings.breadcrumbStyle' => 'Breadcrumb style',
			'settings.breadcrumbRestrained' => 'Restrained',
			'settings.breadcrumbRestrainedHint' => 'Rounded track and subtle emphasis for everyday browsing',
			'settings.breadcrumbExpressive' => 'Expressive',
			'settings.breadcrumbExpressiveHint' => 'Organic contours and shaped endpoints highlight the current folder',
			'settings.breadcrumbAncestors' => 'Show parent folders',
			'settings.fileManagerSectionView' => 'Browsing view',
			'settings.fileManagerRememberViewState' => 'Remember view and sort per folder',
			'settings.fileManagerRememberViewStateSubtitle' => 'Each folder keeps its own view mode, sort and filter. When off, browsing works as usual but nothing is remembered',
			'settings.fileManagerWrapGridTitle' => 'Wrap file names in cover grid',
			'settings.fileManagerWrapGridTitleSubtitle' => 'In the cover grid, file names wrap onto up to 6 lines. The tile keeps its height, so more lines squeeze the cover. When off, names are cut to 2 lines with an ellipsis. Either way, hovering anywhere on the tile reveals the full name',
			'settings.fileManagerSectionSearch' => 'Search',
			'settings.fileManagerSearchSubfoldersDefault' => 'Include subfolders by default',
			'settings.fileManagerSearchSubfoldersDefaultSubtitle' => 'New tabs start with subfolder search switched on. A whole-library scan takes tens of seconds on a slow drive, so the default stays the current folder; turn this on to skip clicking the chip every time',
			'settings.fileManagerSectionTabs' => 'Tabs',
			'settings.fileManagerRestoreTabs' => 'Restore the tabs from last time',
			'settings.fileManagerRestoreTabsSubtitle' => 'Puts last session\'s tabs back when the file manager opens. Only recorded from two tabs up, and only the folders - no back history, no search results. A folder that is gone falls back to the nearest parent that still exists. When the last session had two or more tabs, this wins over \'Open the home folder on start\'',
			'settings.fileManagerSectionFileOps' => 'File operations',
			'settings.fileManagerFileOperations' => 'Allow modifying files',
			'settings.fileManagerFileOperationsSubtitle' => 'Copy, move, rename, create and delete. When off, the context menu, multi-select and the action bar all disappear and the file manager goes back to read-only',
			'settings.fileManagerHomePathSet' => 'Home updated',
			'settings.shellIntegration' => 'System integration',
			'settings.shellIntegrationContextMenu' => 'Show “Open with Rossi” in the context menu',
			'settings.shellIntegrationContextMenuSubtitle' => 'Writes to the current user\'s registry (HKCU), no administrator needed. The entry appears on files, on folders and on a folder\'s background. While Rossi is already running a new folder is not handed to it yet - open a second window instead.',
			'settings.shellIntegrationRegistered' => 'Added to the context menu',
			'settings.shellIntegrationUnregistered' => 'Removed from the context menu',
			'settings.shellIntegrationStalePath' => 'The menu entry points at a different Rossi build; switch it off and on again to fix it',
			'settings.shellIntegrationRepair' => 'Repair path',
			'settings.shellIntegrationMacHint' => 'On macOS “Open With ‣ Rossi” comes from the document types the app bundle declares - always available, no switch. This toggle only affects Windows.',
			'settings.openIntentMissing' => ({required Object path}) => 'This path no longer exists: ${path}',
			'settings.openIntentMultiSkipped' => ({required Object count}) => 'Only the first item opens; ${count} others were skipped',
			'settings.operationBinding' => 'Operation bindings',
			'settings.operationBindingEntrySubtitle' => 'Keys, tap zones and binding bundles',
			'settings.operationBindingSubtitle' => 'This table decides which action a key or a click triggers. Saving takes effect immediately, no restart needed.',
			'settings.operationBindingSectionSwitch' => 'How bindings apply',
			'settings.operationBindingRuntime' => 'Resolve keys and taps through the binding table',
			'settings.operationBindingRuntimeSubtitle' => 'When off, the reader falls back to the built-in fixed keys (arrows, WASD, numpad and F11), and the edits below do not affect reading.',
			'settings.operationBindingInvertWheel' => 'Wheel follows the hand, not the content',
			'settings.operationBindingInvertWheelSubtitle' => 'When on: roll up = previous page, roll down = next page, named after how your hand moves. macOS already inverts scroll deltas for natural scrolling, so this is on by default there; when off, direction follows content movement. Recording bindings and the legacy fallback use the same rule.',
			'settings.operationBindingSectionKeyboard' => 'Keyboard',
			'settings.operationBindingSectionTap' => 'Tap zones',
			'settings.operationBindingTapSubtitle' => 'The reader only tells three zones apart: left half, center cell, right half. The top and bottom rows behave like the middle one.',
			'settings.operationBindingAreaMiddleLeft' => 'Left half',
			'settings.operationBindingAreaMiddleCenter' => 'Center',
			'settings.operationBindingAreaMiddleRight' => 'Right half',
			'settings.operationBindingBoundAction' => 'Bound action',
			'settings.operationBindingUnbound' => 'Unbound',
			'settings.operationBindingSectionBundle' => 'Binding bundle',
			'settings.operationBindingImport' => 'Import JSON',
			'settings.operationBindingImportSubtitle' => 'Import a bindings object or array, preserving every input type, context and action sequence.',
			'settings.operationBindingImportConfirm' => 'Load',
			'settings.operationBindingImportLoaded' => ({required Object count}) => 'Loaded ${count} bindings — save to apply them',
			'settings.operationBindingExport' => 'Export JSON',
			'settings.operationBindingExportSubtitle' => 'Copy the whole table you are editing.',
			'settings.operationBindingCopy' => 'Copy',
			'settings.operationBindingCopied' => 'Binding table copied to clipboard',
			'settings.operationBindingJsonHint' => 'Validation and conflict checks run before saving. Imported text is written only once you press Save.',
			'settings.operationBindingSave' => 'Save',
			'settings.operationBindingSaved' => 'Binding table saved — effective immediately',
			'settings.operationBindingDiscard' => 'Discard',
			'settings.operationBindingDiscarded' => 'Unsaved changes discarded',
			'settings.operationBindingDirtyHint' => 'You have unsaved changes.',
			'settings.operationBindingRestoreFactory' => 'Restore factory presets',
			'settings.operationBindingRestoreFactorySubtitle' => 'Restore Neo\'s default grid, wheel, keyboard and mouse bindings, and reset the radial menu. Existing custom bindings will be replaced.',
			'settings.operationBindingAddKey' => 'Add key',
			'settings.operationBindingNoKeys' => 'No keys bound',
			'settings.operationBindingDisabledRow' => 'Disabled (does not count as a conflict)',
			'settings.operationBindingRemove' => 'Delete this binding',
			'settings.operationBindingUnimplemented' => 'This action has no executor in this build yet',
			'settings.operationBindingRecordTitle' => 'Press the key to bind',
			'settings.operationBindingRecordHint' => 'Hold Ctrl / Alt / Shift / Win to bind a chord. Press Esc to cancel.',
			'settings.operationBindingRecordUnsupported' => ({required Object label}) => 'No platform-neutral key name for ${label}, so it cannot be bound',
			'settings.operationBindingConflictTitle' => 'Conflicting bindings',
			'settings.operationBindingConflictBody' => 'One input may have only one enabled binding. Remove or disable one of them, then save again.',
			'settings.operationBindingInvalidTable' => 'This binding table could not be parsed, so the save was refused',
			'settings.operationBindingCategoryNavigation' => 'Navigation',
			'settings.operationBindingCategoryZoom' => 'Zoom',
			'settings.operationBindingCategoryView' => 'View',
			'settings.operationBindingCategorySession' => 'Session',
			'settings.operationBindingActionNextPage' => 'Next page',
			'settings.operationBindingActionPreviousPage' => 'Previous page',
			'settings.operationBindingActionFirstPage' => 'First page',
			'settings.operationBindingActionLastPage' => 'Last page',
			'settings.operationBindingActionPageLeft' => 'Page left',
			'settings.operationBindingActionPageRight' => 'Page right',
			'settings.operationBindingActionFullscreen' => 'Fullscreen',
			'settings.operationBindingActionToggleDirection' => 'Toggle reading direction',
			'settings.operationBindingActionBookMode' => 'Book mode',
			'settings.operationBindingActionResetView' => 'Reset view',
			'settings.operationBindingActionToggleBars' => 'Show or hide the bars',
			'settings.operationBindingActionOpenSettings' => 'Open settings',
			'settings.operationBindingActionZoomIn' => 'Zoom in',
			_ => null,
		} ?? switch (path) {
			'settings.operationBindingActionZoomOut' => 'Zoom out',
			'settings.operationBindingActionFitWindow' => 'Fit to window',
			'settings.operationBindingActionActualSize' => 'Actual size',
			'settings.operationBindingActionRotateClockwise' => 'Rotate clockwise',
			'settings.operationBindingActionRotate180' => 'Rotate 180 degrees',
			'settings.workspaceLayout' => 'Layout',
			'settings.workspaceLayoutSubtitle' => 'Startup view · lane focus & solo · hover reveal zones',
			'settings.laneAndLayout' => 'Lanes & Layout',
			'settings.defaultStartupView' => 'Default startup view',
			'settings.startupViewEdges' => 'Workhole',
			'settings.startupViewSwimlane' => 'Swimlane',
			'settings.startupViewHint' => 'Which presentation the workspace opens with. Both share one set of records, so switching never reopens the current book.',
			'settings.laneFocusSolo' => 'Lane focus & solo',
			'settings.laneFocusSoloSubtitle' => 'Controls when the main lane takes over, the switcher rail and edge reveal respond.',
			'settings.autoFocusReaderOnOpen' => 'Jump to the reader lane on read',
			'settings.autoFocusReaderOnOpenSubtitle' => 'Tapping "Read" (on the cover or in the comic info page — the same action) hands the viewport and interaction to the central reader lane. When off, the book still opens in that lane but the strip does not move: keep browsing the lane you were in, and click over to the reader when you want it.',
			'settings.readerSoloOnFocus' => 'Auto-solo Reader on focus',
			'settings.readerSoloOnFocusSubtitle' => 'Handing interaction to Reader also lets it take the full available width, without clicking the solo button again.',
			'settings.showLaneNavigatorInSolo' => 'Show lane switcher while Reader is solo',
			'settings.showLaneNavigatorInSoloSubtitle' => 'Other lanes stay in the strip as compact rails you can click; turn it off and only Reader remains, with other lanes brought back by the side reveal zones.',
			'settings.manualScrollEnabled' => 'Allow manual horizontal scroll',
			'settings.manualScrollEnabledSubtitle' => 'When off the strip still scrolls itself to the active or revealed lane; only your own drags and the wheel are ignored.',
			'settings.blockManualScrollInReaderFullscreen' => 'Block horizontal lane dragging in fullscreen',
			'settings.blockManualScrollInReaderFullscreenSubtitle' => 'While the Reader is fullscreen, horizontal gestures only turn pages and no longer pan the swimlane strip (which drags the Reader along). Turn it off to keep dragging available, same as usual.',
			'settings.laneHeaderChrome' => 'Lane header',
			'settings.laneHeaderChromeSubtitle' => 'What the lane header row draws. Only the header itself — nothing inside the lane changes.',
			'settings.showLaneWidthBadge' => 'Show lane width badge',
			'settings.showLaneWidthBadgeSubtitle' => 'Draws the current width as a "400px" badge next to the lane title. Off by default — set the width from the lane menu\'s "Lane width" field; while off, that width goes back to the title and tab strip.',
			'settings.panelTabSortMode' => 'Panel tab sort mode',
			'settings.panelTabSortModeSubtitle' => 'When on, long-press a tab to drag it to reorder or move it to another lane; when off, dragging across the strip switches panels and the selection follows your finger.',
			'settings.edgeRevealDelay' => 'Side lane reveal delay',
			'settings.readerHoverFocusDelay' => 'Reader hover refocus delay',
			'settings.readerHoverFocusEnable' => 'Enable Reader hover refocus',
			'settings.revealFocusesLane' => 'Focus lane after edge reveal',
			'settings.revealFocusesLaneSubtitle' => 'Once the pointer has dwelled at the left or right edge long enough, the revealed lane also takes over interaction — no extra click. Reader keeps a narrow sliver, so one click returns to solo. When off, a reveal is only a peek and folds back to Reader after a while.',
			'settings.panelLaneHoverFocus' => 'Hover focus for panel lanes',
			'settings.panelLaneHoverFocusSubtitle' => 'Dwelling inside the left or right lane activates it too, sharing the delay above. Lanes collapsed to a rail are excluded, so brushing past them while reading won\'t steal focus.',
			'settings.delayRangeHint' => 'Dwell time in milliseconds before it fires. The three delays are independent — changing one never drags another along.',
			'settings.hoverRevealZones' => 'Hover reveal zones',
			'settings.hoverRevealZonesSubtitle' => 'Drag rectangles on the canvas to decide where the pointer brings content up.',
			'settings.hoverRevealZonesHint' => 'Left and right drive lane reveal, top drives the workspace chrome, bottom drives the reader\'s bottom bar. Drag to draw, then drag the corners to fine-tune.',
			'settings.revealEdgeLeft' => 'Left',
			'settings.revealEdgeRight' => 'Right',
			'settings.revealEdgeTop' => 'Top',
			'settings.revealEdgeBottom' => 'Bottom',
			'settings.revealLinkHorizontal' => 'Link L/R',
			'settings.revealLinkVertical' => 'Link T/B',
			'settings.revealReset' => 'Reset reveal zones',
			'settings.revealFieldX' => 'X',
			'settings.revealFieldY' => 'Y',
			'settings.revealFieldWidth' => 'W',
			'settings.revealFieldHeight' => 'H',
			'settings.revealZoneResetDone' => 'Reveal zones restored to defaults',
			'settings.operationBindingTabKeyboard' => 'Shortcuts',
			'settings.operationBindingTabRadial' => 'Radial menu',
			'settings.operationBindingActionOpenRadial' => 'Open radial menu',
			'settings.operationBindingActionConfirmRadial' => 'Confirm radial selection',
			'settings.operationBindingActionToggleLibrary' => 'Toggle library',
			'settings.operationBindingRadialEnable' => 'Enable radial menu',
			'settings.operationBindingRadialEnableSubtitle' => 'When off the wheel never opens; slot bindings are kept',
			'settings.operationBindingRadialActiveWheel' => 'Default wheel',
			'settings.operationBindingRadialLayerUnit' => ({required Object count}) => '${count} layers',
			'settings.operationBindingRadialNew' => 'New wheel',
			'settings.operationBindingRadialDelete' => 'Delete wheel',
			'settings.operationBindingRadialPreview' => 'Preview',
			'settings.operationBindingRadialReset' => 'Reset slots',
			'settings.operationBindingRadialResetSubtitle' => 'Rewrites only this wheel\'s factory slots; your own bindings stay',
			'settings.operationBindingRadialHint' => ({required Object layers}) => 'On · ${layers} layers · tap an empty slot to add, a filled one to edit',
			'settings.operationBindingRadialHintDisabled' => 'Off · the wheel will not open while reading',
			'settings.operationBindingRadialAppearance' => 'Appearance & geometry',
			'settings.operationBindingRadialGeometrySummary' => ({required Object radius, required Object inner, required Object variant}) => 'r${radius} · inner ${inner} · ${variant}',
			'settings.operationBindingRadialRadius' => 'Wheel size',
			'settings.operationBindingRadialInnerRadius' => 'Inner radius (hole)',
			'settings.operationBindingRadialSectors' => 'Sectors per layer',
			'settings.operationBindingRadialSlots' => 'Slots',
			'settings.operationBindingRadialSlotsSubtitle' => 'Tap an empty or filled slot on the wheel',
			'settings.operationBindingRadialName' => 'Wheel name',
			'settings.operationBindingRadialSlotLabel' => ({required Object layer, required Object sector}) => 'Layer ${layer} · slot ${sector}',
			'settings.operationBindingRadialEmptySlot' => 'Empty slot',
			'settings.operationBindingRadialUnbindSlot' => 'Unbind this slot',
			'settings.operationBindingRadialMaxMenus' => ({required Object max}) => 'Up to ${max} wheels',
			'settings.operationBindingRadialDeleteConfirm' => ({required Object name}) => 'Delete wheel "${name}"? Its slot bindings are removed too.',
			'settings.operationBindingRadialDeleteLast' => 'At least one wheel must stay',
			'settings.operationBindingRadialInvalid' => 'The wheel layout is invalid, saving was refused',
			'settings.operationBindingRadialResetDone' => 'Factory slots restored',
			'settings.operationBindingRadialNewName' => ({required Object index}) => 'Wheel ${index}',
			'settings.operationBindingRadialEmptyWheel' => 'A new wheel is empty: bind its slot by slot',
			'settings.operationBindingCategoryRadial' => 'Radial',
			'settings.operationBindingRadialItemKind' => 'Kind',
			'settings.operationBindingRadialKindAction' => 'Run action',
			'settings.operationBindingRadialKindMove' => 'Jump to wheel',
			'settings.operationBindingRadialTargetWheel' => 'Target wheel',
			'settings.operationBindingRadialIcon' => 'Icon',
			'settings.operationBindingRadialIconAuto' => 'Match action automatically',
			'settings.operationBindingRadialLabel' => 'Label',
			'settings.operationBindingRadialSlotIndex' => 'Slot',
			'settings.operationBindingRadialItemEnabled' => 'This slot is enabled',
			'settings.operationBindingRadialMoveUp' => 'Move earlier',
			'settings.operationBindingRadialMoveDown' => 'Move later',
			'settings.operationBindingRadialDeleteItem' => 'Delete this slot',
			'settings.operationBindingRadialStartAngle' => 'Rotation',
			'settings.operationBindingRadialSweepAngle' => 'Sweep angle',
			'settings.operationBindingRadialVariant' => 'Style',
			'settings.operationBindingRadialVariantSlice' => 'Rounded buttons',
			'settings.operationBindingRadialVariantBubble' => 'Round buttons',
			'settings.operationBindingRadialLayerN' => ({required Object n}) => 'Layer ${n}',
			'settings.operationBindingRadialSelectedSlot' => 'Selected slot',
			'settings.operationBindingRadialPickHint' => 'Tap a sector on the wheel to pick it; empty ones show +',
			'settings.operationBindingRadialEmptySlotRow' => '(empty)',
			'settings.operationBindingRadialActionLabel' => 'Action',
			'bookshelf.collectedWorks' => 'Collected',
			'bookshelf.readingNow' => 'Reading',
			'bookshelf.unreadWorks' => 'Unread',
			'bookshelf.createFolderHint' => 'Groups related comics together so you can find them again later.',
			'bookshelf.title' => 'Bookshelf',
			'bookshelf.favorite' => 'Favorites',
			'bookshelf.history' => 'History',
			'bookshelf.download' => 'Downloads',
			'bookshelf.filter' => 'Filter',
			'bookshelf.searchList' => 'Search list',
			'bookshelf.newFolder' => 'New folder',
			'bookshelf.manage' => 'Manage',
			'bookshelf.importComic' => 'Import comic',
			'bookshelf.folderHint' => 'Bookshelf hints',
			'bookshelf.removeFromFolder' => 'Remove from folder',
			'bookshelf.deleteFavorite' => 'Remove favorite',
			'bookshelf.deleteHistory' => 'Delete history',
			'bookshelf.deleteDownload' => 'Delete download record',
			'bookshelf.confirmDeleteSelected' => ({required Object count}) => 'Are you sure you want to delete the selected ${count} records?',
			'bookshelf.deletedRecords' => ({required Object count}) => 'Deleted ${count} records',
			'bookshelf.noFilterSource' => 'No filterable plugin sources',
			'bookshelf.sort' => 'Sort',
			'bookshelf.sortDesc' => 'Time (newest first)',
			'bookshelf.sortAsc' => 'Time (oldest first)',
			'bookshelf.viewSortDesc' => 'View time (newest first)',
			'bookshelf.viewSortAsc' => 'View time (oldest first)',
			'bookshelf.source' => 'Comic source',
			'bookshelf.deselectAll' => 'Deselect all',
			'bookshelf.renameFolder' => 'Rename folder',
			'bookshelf.createFolder' => 'Create folder',
			'bookshelf.multiSelect' => 'Multi-select',
			'bookshelf.copyTo' => 'Copy to',
			'bookshelf.batchExport' => 'Batch export',
			'bookshelf.batchDeleteFailed' => 'Batch delete failed',
			'bookshelf.deleteSelected' => 'Delete selected',
			'bookshelf.cancel' => 'Cancel selection',
			'bookshelf.selectedCount' => ({required Object count}) => 'Selected ${count} items',
			'bookshelf.folderComicCount' => ({required Object count}) => '${count} items',
			'bookshelf.selectTargetFolder' => 'Select target folders (multiple)',
			'bookshelf.confirmDeleteFolderTitle' => 'Confirm delete',
			'bookshelf.confirmDeleteFolderContent' => 'Delete this folder? Contents will be deleted recursively.',
			'bookshelf.confirmRemoveComicTitle' => 'Remove from folder',
			'bookshelf.confirmRemoveComicContent' => ({required Object title}) => 'Remove "${title}" from current folder?',
			'bookshelf.importComicZipOnly' => 'Importing comics (zip only)',
			'bookshelf.importStarted' => 'Importing comics (zip only)',
			'bookshelf.importCompleted' => ({required Object title}) => 'Import completed: ${title}',
			'bookshelf.comicExists' => 'Comic already exists',
			'bookshelf.confirmOverwriteImport' => ({required Object title}) => '${title} already exists in download list. Overwrite?',
			'bookshelf.noExportableComics' => 'No exportable comics in selection',
			'bookshelf.batchExportCompleted' => ({required Object success, required Object total}) => 'Batch export completed: ${success}/${total}',
			'bookshelf.batchExportDeleted' => ({required Object count}) => 'Deleted local downloads for ${count} comic(s)',
			'bookshelf.batchExportKeptIncomplete' => ({required Object count}) => '${count} comic(s) had pages missing from the export; their local downloads were kept',
			'bookshelf.batchExportFailed' => ({required Object error}) => 'Batch export failed: ${error}',
			'bookshelf.confirmDeleteSelectedTitle' => 'Confirm delete',
			'bookshelf.confirmDeleteSelectedContent' => 'Delete selected folders and comics? Folders will be deleted recursively.',
			'bookshelf.cancelSelect' => 'Cancel selection',
			'bookshelf.selectAll' => 'Select all',
			'bookshelf.moveTo' => 'Move to',
			'bookshelf.addToFolder' => 'Add to folder',
			'bookshelf.folderName' => 'Folder name',
			'bookshelf.helpContent' => '• Favorites and bookshelf are linked: favoriting a comic adds it to the bookshelf; only removing it from all favorite folders unfavorites it.\n• On comic detail page, unfavorite removes it from all favorite folders at once.\n• Same for downloads: only removing a comic from all download folders deletes its downloaded files.',
			'bookshelf.folderCreated' => 'Folder created',
			'bookshelf.noComic' => 'No comics yet',
			'bookshelf.noHistory' => 'No reading history yet',
			'bookshelf.noDownload' => 'No downloads yet',
			'bookshelf.nothingHere' => 'Nothing here',
			'bookshelf.deleteAllDownloadRecordsAndFiles' => 'Delete all download records and files',
			'bookshelf.clearHistoryRecords' => 'Clear history records',
			'bookshelf.confirmDeleteAllDownloadsContent' => 'Delete all download records and their files? This action cannot be undone!',
			'bookshelf.confirmClearHistoryContent' => 'Clear all history records? This action cannot be undone!',
			'bookshelf.allDownloadRecordsAndFilesDeleted' => 'All download records and files deleted',
			'bookshelf.historyRecordsCleared' => 'History records cleared',
			'bookshelf.batchExportTitle' => 'Choose export method',
			'bookshelf.batchExportSubtitle' => 'Please choose batch export as zip or folder',
			'bookshelf.importCancelled' => 'Import cancelled',
			'bookshelf.importEpisodeFallback' => ({required Object index}) => 'Ep. ${index}',
			'bookshelf.importMissingJson' => 'Import directory is missing required JSON files',
			'bookshelf.importVersionUnsupported' => 'This version cannot be imported, please export with a newer app version',
			'bookshelf.importMissingSource' => 'Export file is missing source info, please re-export with a newer app version',
			'bookshelf.importMissingComicId' => 'Cannot get comic ID',
			'bookshelf.importNoComicDir' => 'No importable comic directory found in the archive',
			'bookshelf.importMultipleComicDirs' => 'Archive contains multiple comic directories, please import one at a time',
			'bookshelf.importComicExistsUncovered' => ({required Object title}) => 'Comic "${title}" already exists, import skipped',
			'bookshelf.folderNameEmpty' => 'Folder name cannot be empty',
			'bookshelf.folderNameSlash' => 'Folder name cannot contain /',
			'bookshelf.folderNameExists' => 'A folder with the same name already exists in this path',
			'bookshelf.targetFolderNameExists' => ({required Object name}) => 'A folder with the same name already exists at target: ${name}',
			'bookshelf.cannotMoveFolderToSelf' => 'Cannot move a folder into itself',
			'bookshelf.cannotMoveParentToChild' => 'Cannot move a parent folder into its subfolder',
			'bookshelf.cannotCopyFolderToSelfOrChild' => 'Cannot copy a folder into itself or its subfolders',
			'bookshelf.moveFoldersOnlyOneTarget' => 'Only one target folder can be selected when moving folders',
			'bookshelf.confirmDeleteSelectedFavorites' => ({required Object count}) => 'Delete selected ${count} favorite records?',
			'bookshelf.confirmDeleteSelectedHistory' => ({required Object count}) => 'Delete selected ${count} history records?',
			'bookshelf.confirmDeleteSelectedDownloads' => ({required Object count}) => 'Delete selected ${count} download records and files?',
			'comicInfo.chapterCount' => ({required Object count}) => 'Chapters · ${count}',
			'comicInfo.pageClosedFavoriteCancelled' => 'The page closed; the favourite action was cancelled',
			'comicInfo.previewLoadFailed' => 'Preview failed to load',
			'comicInfo.showMoreChapters' => 'Show more chapters',
			'comicInfo.noChaptersYet' => 'No chapters yet',
			'comicInfo.reverseOrderLabel' => 'Reverse',
			'comicInfo.restoreForwardOrder' => 'Restore forward order',
			'comicInfo.imagePreview' => 'Image preview',
			'comicInfo.collapseDetails' => 'Collapse details',
			'comicInfo.workTools' => 'Work tools',
			'comicInfo.refreshInformation' => 'Refresh info',
			'comicInfo.cloudFavoriteIncomplete' => 'The cloud favourite operation didn\'t finish',
			'comicInfo.follow' => 'Follow updates',
			'comicInfo.unfollow' => 'Unfollow',
			'comicInfo.exportComic' => 'Export comic',
			'comicInfo.cloudCollect' => 'Cloud collect',
			'comicInfo.cloudCollected' => 'Cloud collected',
			'comicInfo.cloudCollectDisabled' => 'This plugin does not support this feature',
			'comicInfo.collectingToCloud' => 'Adding to cloud collection...',
			'comicInfo.removingCloudCollection' => 'Removing cloud collection...',
			'comicInfo.cloudCollectSuccess' => 'Added to cloud collection',
			'comicInfo.cloudUncollectSuccess' => 'Removed from cloud collection',
			'comicInfo.cloudCollectIncomplete' => 'Cloud collection operation incomplete',
			'comicInfo.discontinued' => 'This comic is discontinued',
			'comicInfo.likes' => ({required Object count}) => 'Likes ${count}',
			'comicInfo.comments' => ({required Object count}) => 'Comments ${count}',
			'comicInfo.collected' => 'Collected',
			'comicInfo.collect' => 'Collect',
			'comicInfo.download' => 'Download',
			'comicInfo.markRead' => 'Mark as read',
			'comicInfo.markUnread' => 'Mark as unread',
			'comicInfo.markThroughRead' => 'Mark up to here as read',
			'comicInfo.clearReadMark' => 'Clear mark',
			'comicInfo.readStateMenu' => 'Reading state',
			'comicInfo.readStateMenuHint' => 'Marks only record your own judgement. They never change reading progress or where “Continue reading” takes you.',
			'comicInfo.markReadDone' => ({required Object count}) => 'Marked ${count} chapters as read',
			'comicInfo.markUnreadDone' => ({required Object count}) => 'Marked ${count} chapters as unread',
			'comicInfo.markThroughReadDone' => ({required Object count}) => 'Marked ${count} earlier chapters as read',
			'comicInfo.readStateUnread' => 'Unread',
			'comicInfo.readStateInferred' => 'Read before',
			'comicInfo.readStateManualRead' => 'Marked read',
			'comicInfo.readStateManualUnread' => 'Marked unread',
			'comicInfo.downloadForbidden' => 'This plugin does not support this feature',
			'comicInfo.addedToCollection' => 'Added to collection',
			'comicInfo.removedFromCollection' => 'Removed from collection',
			'comicInfo.confirmUncollectTitle' => 'Remove collection',
			'comicInfo.confirmUncollectContent' => 'This will delete the comic from all folders. Continue?',
			'comicInfo.commentForbidden' => 'This plugin does not support this feature',
			'comicInfo.commentForbiddenTitle' => 'Comments disabled',
			'comicInfo.back' => 'Back',
			'comicInfo.exportTitle' => 'Choose export format',
			'comicInfo.exportSubtitle' => 'Export as folder or zip archive:',
			'comicInfo.folder' => 'Folder',
			'comicInfo.zip' => 'Zip archive',
			'comicInfo.exportSuccess' => 'Export successful',
			'comicInfo.detailsNotLoaded' => 'Comic details not fully loaded',
			'comicInfo.followed' => 'Following updates',
			'comicInfo.unfollowed' => 'Unfollowed',
			'comicInfo.confirmUnfollowTitle' => 'Unfollow',
			'comicInfo.confirmUnfollowContent' => ({required Object title}) => 'Stop following "${title}"?',
			'comicInfo.noChapters' => 'No chapter information',
			'comicInfo.chapterList' => 'Chapters',
			'comicInfo.preview' => 'Preview',
			'comicInfo.episodeCount' => ({required Object count}) => '${count} Episodes',
			'comicInfo.episodeFallback' => ({required Object index}) => '${index}',
			'comicInfo.episodeLabel' => ({required Object index}) => '${index}',
			'comicInfo.groupEpisodeCount' => ({required Object count}) => '${count} Episodes',
			'comicInfo.untitledGroup' => 'Ungrouped',
			'comicInfo.downloadGroup' => 'Download group',
			'comicInfo.author' => 'Author',
			'comicInfo.tags' => 'Tags',
			'comicInfo.works' => 'Works',
			'comicInfo.views' => ({required Object count}) => 'Views: ${count}',
			'comicInfo.updateTime' => ({required Object time}) => 'Updated: ${time}',
			'comicInfo.startRead' => 'Start reading',
			'comicInfo.continueRead' => 'Continue reading',
			'comicInfo.lastRead' => 'Last read',
			'comicInfo.chapters' => 'Chapters',
			'comicInfo.related' => 'Related',
			'comicInfo.description' => 'Description',
			'comicInfo.collapse' => 'Collapse',
			'comicInfo.expandFullText' => 'Read more',
			'comicInfo.readHistory' => 'Reading history',
			'comicInfo.copied' => ({required Object label}) => 'Copied: ${label}',
			'comicInfo.copiedToClipboard' => ({required Object name}) => 'Copied ${name} to clipboard',
			'comicInfo.openOnSource' => 'Open on source',
			'comicInfo.liking' => 'Liking...',
			'comicInfo.unliking' => 'Unliking...',
			'comicInfo.likeSuccess' => 'Liked',
			'comicInfo.unlikeSuccess' => 'Unliked',
			'comicInfo.likeDisabled' => 'This plugin does not support this feature',
			'comicInfo.localCollectFailed' => ({required Object error}) => 'Local favorite failed: ${error}',
			'comicInfo.likeFailed' => ({required Object error}) => 'Like failed: ${error}',
			'comicInfo.loadFailedWithError' => ({required Object error}) => '${error}\nLoading failed, please retry.',
			'comicInfo.exportPermissionDenied' => 'All files access permission not granted, export cancelled',
			'comicInfo.exportFailedWithError' => ({required Object error}) => 'Export failed, please retry.\n${error}',
			'comicInfo.exportDirectory' => ({required Object displayPath}) => 'Export directory: ${displayPath}',
			'comicInfo.exportPathTooLong' => 'Export directory path is too long to create a valid structure',
			'comicInfo.zipExportPathTooLong' => 'Specified zip export path exceeds system path length limit',
			'comicInfo.downloadPathTooLong' => 'Download directory path is too long to create a valid zip file path',
			'comicInfo.uniqueFileNameTooLong' => 'Cannot create a unique file name for chapter: path length limit exceeded',
			'comicInfo.exportFolderComplete' => ({required Object title}) => 'Exported "${title}" as folder',
			'comicInfo.exportZipComplete' => ({required Object title}) => 'Exported "${title}" as zip',
			'comicInfo.exportComicNotFound' => ({required Object comicId}) => 'No downloadable comic found for export: ${comicId}',
			'comicInfo.exportDeleteAfter' => 'Delete local download after a successful export',
			'comicInfo.exportDeleteAfterSubtitle' => 'Only deleted once every page made it into the archive and the file is verified on disk. Otherwise the download is kept and the reason is shown.',
			'comicInfo.exportedAndDeleted' => ({required Object title}) => 'Exported and deleted local download: ${title}',
			'comicInfo.exportDeleteSkippedIncomplete' => ({required Object count, required Object chapters}) => '${count} page(s) did not make it into the export (${chapters}); local download kept',
			'comicInfo.exportDeleteSkippedEmpty' => 'No downloadable pages found locally; local download kept',
			'comicInfo.exportDeleteSkippedArtifact' => 'Exported file failed the integrity check; local download kept',
			'comicInfo.exportDeleteSkippedInsideRoot' => 'Export target is inside the download folder, deleting would remove the export too; local download kept',
			'comicInfo.exportDeleteFailed' => ({required Object error}) => 'Export finished, but deleting the local download failed: ${error}',
			'comicInfo.pluginInvalidFavorited' => 'Plugin did not return a valid favorited status',
			'comicInfo.pluginInvalidLiked' => 'Plugin did not return a valid liked status',
			'comicInfo.addToCustomFolder' => 'Add to custom folder',
			'comicInfo.addedToFolder' => ({required Object name}) => 'Added to folder: ${name}',
			'comicInfo.skipAdd' => 'Skip / Don\'t add',
			'comicInfo.confirmAdd' => 'Confirm add',
			'comicInfo.resolveComicIdFailed' => ({required Object type}) => 'Cannot resolve comic ID for reading: ${type}',
			'comicInfo.resolveEpsCountFailed' => ({required Object type}) => 'Cannot resolve episode count for reading: ${type}',
			'comicInfo.collectToCloud' => 'Collect to cloud',
			'comicInfo.collectToLocal' => 'Collect locally',
			'comicInfo.removeCloudCollection' => 'Remove cloud collection',
			'comicInfo.removeLocalCollection' => 'Remove local collection',
			'reader.switchBookFailed' => ({required Object error}) => 'Switching books failed: ${error}',
			'reader.pageDecodeFailed' => ({required Object n}) => 'Page ${n} could not be decoded',
			'reader.cannotOpenPath' => ({required Object path}) => 'Can\'t open: ${path}',
			'reader.aiJpegDenoise' => 'AI JPEG denoise',
			'reader.noMatchingOfflineComics' => 'No downloaded comics match',
			'reader.searchOfflineComics' => 'Search downloaded comics',
			'reader.stateNotDownloadedAsk' => 'Not downloaded (it asks first when you turn this on)',
			'reader.stateDownloaded' => 'Downloaded',
			'reader.stateOff' => 'Off',
			'reader.stateOn' => 'On',
			'reader.cannotOpenLocalComic' => ({required Object error}) => 'Can\'t open the local comic: ${error}',
			'reader.cachedPages' => ({required Object count}) => '${count} pages cached',
			'reader.targetLanguageLabel' => ({required Object lang}) => 'Target ${lang}',
			'reader.bottomRevealPx' => ({required Object px}) => 'Bottom reveal (${px}px)',
			'reader.topRevealPx' => ({required Object px}) => 'Top reveal (${px}px)',
			'reader.sourcePageOf' => ({required Object index, required Object total}) => 'Source page ${index} of ${total}',
			'reader.manualPageOrderFor' => ({required Object name}) => 'Manual page order · ${name}',
			'reader.tapToSwitchMode' => ({required Object from, required Object to}) => '${from} (tap to switch to ${to})',
			'reader.modelState' => ({required Object state}) => 'Model: ${state}',
			'reader.modelDownloadFailed' => ({required Object error}) => 'Model download failed: ${error}',
			'reader.activeThreshold' => ({required Object value}) => 'Effective threshold: ${value}',
			'reader.globalDefaultState' => ({required Object state}) => 'Global (default for all books): ${state}',
			'reader.thisBookState' => ({required Object state}) => 'This book: ${state}',
			'reader.upscaleChipTail' => ({required Object tooltip}) => '${tooltip}\nTap to toggle; hold to peek at the original; the power button on the right affects this book only',
			'reader.notWiredIntoReader' => ({required Object name}) => '${name} isn\'t wired into this repo\'s reader yet',
			'reader.notImplementedYet' => ({required Object name}) => '${name} (not implemented in this repo yet)',
			'reader.oneScreenPercent' => ({required Object percent}) => '${percent}% of a screen',
			'reader.slideshowDwellHint' => ({required Object step, required Object min, required Object max}) => 'How long each page stays: ${step} per step, between ${min} and ${max}',
			'reader.manualRotationDeg' => ({required Object deg}) => 'Manual rotation ${deg}°',
			'reader.loupeSizeRange' => ({required Object min, required Object max}) => 'Window edge, logical pixels (${min}–${max}, 20 per step)',
			'reader.loupeZoomRange' => ({required Object min, required Object max}) => 'Magnification (${min}%–${max}%, 25% per step, doubling steps from 400%)',
			'reader.intervalSeconds' => ({required Object seconds}) => 'Interval ${seconds}s',
			'reader.tapToExpandPanel' => ({required Object label}) => '${label} (tap to open the panel)',
			'reader.zoomModeValue' => ({required Object mode}) => 'Zoom mode: ${mode}',
			'reader.imageProcessingOffReaderHint' => 'Image processing is off; turn it on in the reader settings',
			'reader.gpuTextureUnsupported' => 'This platform doesn\'t support GPU texture processing',
			'reader.thisPage' => 'This page',
			'reader.pendingUpscale' => 'Awaiting upscale',
			'reader.upscaleFailedState' => 'Upscale failed',
			'reader.noUpscaleNeeded' => 'No upscaling needed',
			'reader.upscaledState' => 'Upscaled',
			'reader.generatedState' => 'Generated',
			'reader.upscalingState' => 'Upscaling',
			'reader.queuedState' => 'Queued',
			'reader.originalCompareChip' => 'Comparing original',
			'reader.upscaleOff' => 'Upscale off',
			'reader.notSupported' => 'Not supported',
			'reader.noProcessingNeeded' => 'No processing needed',
			'reader.denoiseFailed' => 'Denoise failed',
			'reader.enhanceFailed' => 'Enhance failed',
			'reader.pendingDenoise' => 'Awaiting denoise',
			'reader.pendingEnhance' => 'Awaiting enhance',
			'reader.denoisedDone' => 'Denoised',
			'reader.enhancedDone' => 'Enhanced',
			'reader.denoising' => 'Denoising',
			'reader.enhancing' => 'Enhancing',
			'reader.upscaleShort' => 'Upscale',
			'reader.jpegDenoise' => 'JPEG denoise',
			'reader.denoisePlusUpscale' => 'Denoise + upscale',
			'reader.tooltipIdle' => ({required Object page, required Object process, required Object hint}) => '${page} hasn\'t started ${process} yet${hint}',
			'reader.tooltipFailed' => ({required Object page, required Object process, required Object hint}) => '${page} · ${process} failed, still showing the original${hint}',
			'reader.tooltipSkipped' => ({required Object page, required Object hint}) => '${page} needs no processing${hint}',
			'reader.tooltipApplied' => ({required Object page, required Object process, required Object hint}) => '${page} already uses the ${process} image${hint}; tap here to compare with the original',
			'reader.tooltipReady' => ({required Object page, required Object hint}) => '${page}\'s processed image is ready, waiting to be shown${hint}',
			'reader.tooltipRunning' => ({required Object page, required Object process, required Object hint}) => '${page} · ${process}…${hint}',
			'reader.tooltipQueued' => ({required Object page, required Object process, required Object hint}) => '${page} is queued, waiting for ${process}${hint}',
			'reader.tooltipComparing' => ({required Object hint}) => 'Comparing with the original; tap here to return to the processed image${hint}',
			'reader.sizeHintSource' => ({required Object source}) => '(original ${source})',
			'reader.sizeHintEnhanced' => ({required Object enhanced}) => '(processed ${enhanced})',
			'reader.sizeHintBoth' => ({required Object source, required Object enhanced}) => '(original ${source} → processed ${enhanced})',
			'reader.pageNumberN' => ({required Object page}) => 'Page ${page}',
			'reader.missingWeightsCount' => ({required Object count}) => 'missing ${count} weights',
			'reader.noMissingWeights' => '(nothing missing, proceeding as-is)',
			'reader.fitWindow' => 'Fit to window',
			'reader.autoTrimEnabledByDefault' => 'Enable auto-trim by default',
			'reader.alignHeight' => 'Align height (two pages share one height)',
			'reader.dwellIndicatorOff' => 'The dwell indicator is off; you can only guess which page is showing',
			'reader.firstPageAloneOn' => 'Show the first page alone: on',
			'reader.firstPageAloneOff' => 'Show the first page alone: off',
			'reader.rotateClockwise90' => 'Rotate 90° clockwise',
			'reader.pageSorting' => 'Page sorting',
			'reader.pageLayout' => 'Page layout',
			'reader.pageOrder' => 'Page order',
			'reader.trimSideLimitHint' => 'Caps how much of each side may be trimmed; 0% keeps the full page',
			'reader.denoiseAdvancedSettings' => 'Advanced denoise settings',
			'reader.denoiseBlockSize' => 'Denoise block size',
			'reader.denoiseShort' => 'Denoise',
			'reader.thresholdLabel' => 'Threshold',
			'reader.startWeightsInReaderSettings' => 'Start downloading the weights in the reader settings:',
			'reader.readerSafeMarginBothSides' => 'Whether the reader keeps a moderate safety margin on both sides',
			'reader.intervalLabel' => 'Interval',
			'reader.lockLoupe' => 'Lock',
			'reader.fillWholeWindow' => 'Fill the whole window',
			'reader.resetViewTransform' => 'Reset zoom, rotation and wide-page policy (keeps page mode and reading direction)',
			'reader.rotateCounterclockwise90' => 'Rotate 90° counter-clockwise',
			'reader.fitHeight' => 'Fit to height',
			'reader.fitWidth' => 'Fit to width',
			'reader.pageNotLoadedYet' => 'This page has not loaded yet; wait a moment and translate again',
			'reader.loadingSettings' => 'Loading settings…',
			'reader.translationHiddenByCompare' => 'The translation is generated and injected but hidden by "compare with original"; switch back to upscaling to see it',
			'reader.trigger' => 'Trigger',
			'reader.trimAdvancedSettings' => 'Advanced trim settings',
			'reader.pointerTypeAuto' => 'Auto: decided by the pointer itself — mouse and trackpad follow hover, finger and stylus need a press (platform-independent, so touch laptops plus an external mouse both resolve correctly)',
			'reader.autoTranslateShort' => 'Auto-translate',
			'reader.autoRotate' => 'Auto-rotate',
			'reader.autoSplitLandscapeOn' => 'Auto-split landscape pages: on',
			'reader.autoSplitLandscapeOff' => 'Auto-split landscape pages: off',
			'reader.backgroundTolerance' => 'Background detection tolerance',
			'reader.autoTranslateEnabled' => 'Auto-translate on page turn is enabled',
			'reader.zoomMode' => 'Zoom mode',
			'reader.editManualOrder' => 'Edit this chapter\'s manual order',
			'reader.rotatePortraitLeft' => 'Rotate portrait pages left',
			'reader.rotatePortraitRight' => 'Rotate portrait pages right',
			'reader.chapterShort' => 'Chapter',
			'reader.downloadNow' => 'Download now',
			'reader.confirmResetAndRedownload' => 'Reset the progress and download this comic again?',
			'reader.zoomShortReset' => 'Short press resets to 100%; press and hold to enter a percentage',
			'reader.marginWhitespace' => 'Whitespace',
			'reader.noBookOpenYet' => 'No book is open now — open one before this can be set per book',
			'reader.layoutTools' => 'Layout tools',
			'reader.autoScroll' => 'Auto-scroll',
			'reader.clearManualOrder' => 'Clear this chapter\'s manual order',
			'reader.removeTwoPageSeam' => 'Removes the seam between the two pages',
			'reader.downloadingUpscaleInBackground' => 'Downloading the upscale model in the background...',
			'reader.landscape' => 'Landscape',
			'reader.rotateLandscapeLeft' => 'Rotate landscape pages left',
			'reader.rotateLandscapeRight' => 'Rotate landscape pages right',
			'reader.formatLabel' => 'Format',
			'reader.webtoonStepScreens' => 'How many screens a webtoon advances per tick: webtoons only; paginated books move a whole page',
			'reader.webtoonTrimSidesOnly' => 'Webtoons trim only the sides, keeping the vertical seam. Full-bleed or unreliable detections stay as-is.',
			'reader.weights' => 'Weights',
			'reader.noManualOrderHere' => 'This chapter has no manual order to clear',
			'reader.bookImageProcessing' => 'This book: image processing',
			'reader.bookEnableAiUpscale' => 'This book: enable AI super-resolution',
			'reader.bookUpscaleOnFetch' => 'Upscaling is on for this book (later fetches are processed at the fetch layer)',
			'reader.bookAiUpscaleOn' => 'AI upscaling is enabled for this book',
			'reader.bookTrimOnOverride' => 'Trim is on for this book alone · global is off',
			'reader.bookTrimOffOverride' => 'Trim is off for this book alone · global is on, so this session will not trim',
			'reader.bookUpscaleOff' => 'Upscaling is off for this book (other books follow the global setting)',
			'reader.bookAiUpscaleOff' => 'AI upscaling is off for this book (other books follow the global setting)',
			'reader.bookEnableJpegDenoise' => 'Enable JPEG denoise for this book',
			'reader.loupeUnlockedFollows' => 'Unlocked: the window closes as soon as the pointer leaves or the finger lifts; when locked it stays put, so you can drag it aside and then aim',
			'reader.notDownloaded' => 'Not downloaded',
			'reader.pauseResumeAutoScroll' => 'Pause / resume auto-scroll',
			'reader.logLabel' => 'Log',
			'reader.alignNone' => 'No alignment (keep original ratios)',
			'reader.rotationSettings' => 'Rotation settings',
			'reader.fileSize' => 'File size',
			'reader.pageOrderNatural' => 'Natural file-name order (page2 before page10)',
			'reader.fileLabel' => 'File',
			'reader.slideshowOffTapStart' => 'The slideshow is off: tap to start it',
			'reader.slideshowDwellIndicator' => 'Show which page is up and whether it is paused during the slideshow',
			'reader.slideshowOnButIdle' => 'The slideshow is on but not ticking: tap to continue',
			'reader.slideshowStoppedAtEnd' => 'The slideshow stopped at the chapter end',
			'reader.slideshowPlayingTapPause' => 'Playing; tap to pause',
			'reader.slideshowPlaying' => 'Playing',
			'reader.slideshowFinished' => 'Finished',
			'reader.loupeTooltip' => 'Loupe: magnifies a small patch of pixels under the pointer as-is into the side window (checking screentone and edge detail)',
			'reader.loupeEnabled' => 'Loupe is on: a small patch of pixels under the pointer is magnified as-is into the side window',
			'reader.loupe' => 'Loupe',
			'reader.slideshowAdvanceChapter' => 'At chapter end, go on to the next chapter; stop when there is none',
			'reader.slideshowLoopInChapter' => 'At chapter end, jump back to the first page and keep playing',
			'reader.slideshowStopAtChapterEnd' => 'Stop at the last page of the chapter and turn the slideshow off',
			'reader.inference' => 'Inference',
			'reader.onDemandTranslateOcr' => 'On-demand inset translation and on-device OCR',
			'reader.detectByFileHeader' => 'Detected by file header. PNG, WebP and similar pages stay as-is.',
			'reader.dragReorderStaysOnPage' => 'Drag to change the display order; applying keeps you on the current page',
			'reader.openChapterListToDrag' => 'Open this chapter\'s page list and drag to reorder (starting from the current order)',
			'reader.perBookAfterOpening' => 'Set per book after opening an online or local comic',
			'reader.touchHoldToShow' => 'Touch: press and hold to open the window, release to close it (with lock you can drag it)',
			'reader.manualOrderDragList' => 'Manual order (drag in the page list)',
			'reader.manualZoom' => 'Manual zoom',
			'reader.denoiseDefaultForAll' => 'Enable denoise for all comics by default',
			'reader.allBooksDefaultCurrentlyOff' => 'Default for all books, currently off; when on, every book without its own setting follows',
			'reader.allBooksDefaultShared' => 'Default for all books (the same entry as in the settings page)',
			'reader.hoverFollowsMouse' => 'Hover: follows the mouse only and closes when the pointer leaves the page',
			'reader.hoverScroll' => 'Hover scroll',
			'reader.restoreDefaultParams' => 'Restore default parameters',
			'reader.restoreConservativeDefaults' => 'Restore conservative defaults',
			'reader.mimageModelMissingPrompt' => 'This device has not downloaded the mImage ONNX upscale model (about 5.4 MB). Download and enable it now?',
			'reader.noImageInfoAvailable' => 'No image information available to read right now',
			'reader.noRealPlksrBackendHere' => 'This platform has no RealPLKSR inference backend yet',
			'reader.pageAnimationOn' => 'Smooth page-turn animation is currently on',
			'reader.pageAnimationOff' => 'Page-turn animation is currently off',
			_ => null,
		} ?? switch (path) {
			'reader.currentImage' => 'Current image',
			'reader.translateOnDeviceNow' => 'Using an on-device offline engine right now; translated pages need no network',
			'reader.translateCloudEndpointNow' => 'Translating through a cloud API endpoint right now; erases the original bubbles and fills in the translation',
			'reader.force' => 'Force',
			'reader.engine' => 'Engine',
			'reader.enableAutoScroll' => 'Enable auto-scroll',
			'reader.enableBookUpscale' => 'Turn on upscaling for this book',
			'reader.slideshow' => 'Slideshow',
			'reader.loupeLockedOn' => 'Locked: the window stays after the pointer leaves and the finger lifts; drag the window itself to move it; double-tap it to unlock',
			'reader.requeuedToDownload' => 'Added back to the download queue',
			'reader.alreadyDisabled' => 'Disabled',
			'reader.manualOrderClearedDone' => 'Cleared this chapter\'s manual order',
			'reader.slideshowPausedTapResume' => 'Paused; tap to resume the slideshow (settings unchanged)',
			'reader.autoScrollEnabled' => 'Auto-scroll enabled',
			'reader.trimOnAutoDetect' => 'On · white and black edges auto-detected',
			'reader.denoiseOnRealPlksr' => 'On · RealPLKSR 1×',
			'reader.switchedToOriginalCompare' => 'Switched to the original comparison',
			'reader.switchedBackToProcessed' => 'Switched back to the processed image',
			'reader.trimOffFullPage' => 'Off · the full page is shown',
			'reader.trimOffOriginalKept' => 'Off · original left unchanged',
			'reader.fitWindowLeft' => 'Fit to window, aligned left',
			'reader.fitWindowRight' => 'Fit to window, aligned right',
			'reader.compareOriginal' => 'Compare with the original',
			'reader.widePagePolicy' => 'Wide page policy',
			'reader.alignWidth' => 'Align width (two pages share one width)',
			'reader.safeMargin' => 'Safe margin',
			'reader.processingStatus' => 'Processing status',
			'reader.bgToleranceHint' => 'Raising it tolerates paper tint and light noise; use a smaller value when pale detail is common',
			'reader.onlineUpscaleAtFetchLayer' => 'Online sources: upscaling happens at the fetch/decode layer, so this is the per-book switch (no per-page state)',
			'reader.sharedUpscaleEnlarge' => 'Shared by online and local comics; enlarges content while reading',
			'reader.sharedDenoiseThenUpscale' => 'Shared by online and local comics; keeps resolution, denoises then upscales',
			'reader.trimSafeMarginKeeps' => 'Keeps extra space around detected content to protect text, page numbers and linework',
			'reader.pageOrderSource' => 'Source order (as the plugin or archive provides it)',
			'reader.imageProcessing' => 'Image processing',
			'reader.readback' => 'Read-back',
			'reader.backend' => 'Backend',
			'reader.onlyThisBookAskFirst' => 'Affects this book only; the model is not downloaded, so it asks first when you enable it',
			'reader.onlyThisBookGlobalOthers' => 'Affects this book only; other books follow the global setting',
			'reader.onlyThisComicUpscaleOwn' => 'Affects this comic only; upscaling has its own switch',
			'reader.twoPagesIndependent' => 'Two pages independent',
			'reader.twoPageModeTap' => 'Two-page mode (tap for single page)',
			'reader.twoPages' => 'Two pages',
			'reader.originalSize' => 'Original size',
			'reader.comparingOriginal' => 'Comparing with the original',
			'reader.singlePageModeTap' => 'Single page mode (tap for two pages)',
			'reader.singlePage' => 'Single page',
			'reader.trimSideLimit' => 'Max trim per side',
			'reader.animatedNotProcessed' => 'Animated pages are not processed. Model strength is fixed; original, denoised and upscaled results are cached separately.',
			'reader.animated' => 'Animated',
			'reader.toggleReaderFilter' => 'Toggle the reading filter and eye-comfort overlay',
			'reader.resolution' => 'Resolution',
			'reader.blockLabel' => 'Blocks',
			'reader.disableAutoScroll' => 'Turn off auto-scroll',
			'reader.disableAutoRotate' => 'Turn off auto-rotate',
			'reader.disableBookUpscale' => 'Turn off upscaling for this book',
			'reader.wholeBook' => 'Whole book',
			'reader.panoramaMode' => 'Panorama mode',
			'reader.pageOrderReversed' => 'Reversed (the whole chapter page list flipped)',
			'reader.scaleLabel' => 'Scale',
			'reader.notWiredBelow' => 'Not yet wired into this repo',
			'reader.jpegPagesOnly' => 'Processes JPEG pages only',
			'reader.peekOriginalBriefly' => 'Briefly view the original; the processed result returns when it closes',
			'reader.peekBackToOriginal' => 'Temporarily switch back to the original; the processed result returns when it closes',
			'reader.denoiseBlockIndependentHint' => 'Independent of upscaling. Smaller blocks cut inference memory; fixed-input models use their own size',
			'reader.denoiseOriginalSafeBefore' => 'Originals untouched; denoise runs before upscaling',
			'reader.denoiseOriginalSafeBookOverride' => 'Originals untouched; the per-book switch can still override it in reader settings',
			'reader.downloadPreference' => 'Download preference',
			'reader.downloadAiUpscaleModel' => 'Download AI upscale model',
			'reader.rotateAlwaysLeft' => 'Always rotate left',
			'reader.rotateAlwaysRight' => 'Always rotate right',
			'reader.ocrWeightsReady' => 'OCR weights ready',
			'reader.neoviewViewportDemo' => 'NeoView viewport-aware interaction sketch',
			'reader.denoiseModelMissing' => 'JPEG denoise model not installed',
			'reader.aiSuperResolution' => 'AI super-resolution',
			'reader.downloadManage' => 'Download Manager',
			'reader.startDownload' => 'Start Download',
			'reader.pauseDownload' => 'Pause Download',
			'reader.resumeDownload' => 'Resume Download',
			'reader.restartDownload' => 'Restart Download',
			'reader.deleteDownload' => 'Delete Download',
			'reader.retryFailedParts' => 'Retry Failed Parts',
			'reader.retryFailedPartsSubtitle' => 'Only redownload incomplete or failed chapters and images',
			'reader.restartDownloadSmart' => 'Incremental (Recommended)',
			'reader.restartDownloadSmartDesc' => 'Check local downloaded files and only download missing or failed images',
			'reader.restartDownloadFull' => 'Full Redownload',
			'reader.restartDownloadFullDesc' => 'Reset all chapters and download everything from scratch',
			'reader.pickAndExtract' => 'Pick & Extract',
			'reader.pickAndExtractSubtitle' => 'Select specific images to export or save',
			'reader.saveToAlbum' => 'Save to Photos',
			'reader.saveToDirectory' => 'Export to Folder',
			'reader.exportZip' => 'Export as ZIP',
			'reader.downloadSelected' => 'Download Selected',
			'reader.selectAll' => 'Select All',
			'reader.deselectAll' => 'Deselect All',
			'reader.invertSelection' => 'Invert Selection',
			'reader.rangeSelect' => 'Range Select',
			'reader.rangeSelectPrompt' => 'Enter page range, e.g. 1-5, 8, 12',
			'reader.selectedCount' => ({required Object selected, required Object total}) => 'Selected ${selected} / ${total} pages',
			'reader.extractingProgress' => ({required Object current, required Object total}) => 'Processing: ${current} / ${total}',
			'reader.extractSuccess' => 'Extraction completed',
			'reader.extractFailed' => ({required Object error}) => 'Extraction failed: ${error}',
			'reader.viewAllTasks' => 'View All Tasks',
			'reader.downloadStatusDownloading' => 'Downloading',
			'reader.downloadStatusPaused' => 'Paused',
			'reader.downloadStatusCompleted' => 'Completed',
			'reader.downloadStatusFailed' => 'Failed',
			'reader.downloadStatusQueued' => 'Queued',
			'reader.confirmDeleteDownloadTitle' => 'Delete Download',
			'reader.confirmDeleteDownload' => 'Are you sure you want to delete this comic\'s download task and local files?',
			'reader.downloadStartedToast' => 'Download started for this comic',
			'reader.autoCollectedToast' => 'Added to collection',
			'reader.readWhileDownloading' => 'Download while reading',
			'reader.readWhileDownloadingSubtitle' => 'Automatically save read content to local download directory',
			'reader.pageMode' => 'Page turn mode',
			'reader.fullscreen' => 'Fullscreen',
			'reader.leftHandMode' => 'Left-hand mode',
			'reader.rightHandMode' => 'Right-hand mode',
			'reader.reverseHorizontalPageTurn' => 'Reverse arrow keys',
			'reader.reverseHorizontalPageTurnSubtitle' => 'Swap left/right arrow keys for page turning, useful for right-to-left manga',
			'reader.webtoonTapPageTurn' => 'Webtoon tap navigation',
			'reader.enableWebtoonTapPageTurn' => 'Allow tapping to turn vertically',
			'reader.webtoonTapPageTurnSubtitle' => 'Tap the upper/lower area in webtoon mode; the center still opens the controls',
			'reader.readingMode' => 'Reading mode',
			'reader.perComicReadMode' => 'Enable per-comic settings',
			'reader.perComicReadModeSubtitle' => 'Only applies to the current comic',
			'reader.perComicFollowGlobal' => 'Follow global',
			'reader.perComicGlobalIs' => 'Global is',
			'reader.perComicThisComic' => 'This comic',
			'reader.infoDisplay' => 'Info display',
			'reader.pageNumber' => 'Page number',
			'reader.pageNumberSubtitle' => 'Show current/total page count',
			'reader.networkStatus' => 'Network status',
			'reader.networkStatusSubtitle' => 'May be inaccurate on Linux',
			'reader.battery' => 'Battery',
			'reader.time' => 'Time',
			'reader.verticalPositionTop' => 'Top',
			'reader.verticalPositionBottom' => 'Bottom',
			'reader.horizontalPositionLeft' => 'Left',
			'reader.horizontalPositionCenter' => 'Center',
			'reader.horizontalPositionRight' => 'Right',
			'reader.readingDirectionLtr' => 'Left to right',
			'reader.readingDirectionRtl' => 'Right to left',
			'reader.readingDirectionVertical' => 'Top to bottom',
			'reader.webtoon' => 'Webtoon',
			'reader.singlePageRow' => 'Single page (horizontal)',
			'reader.readingDirectionLeftOpen' => 'Left-opening · next page on the left',
			'reader.readingDirectionRightOpen' => 'Right-opening · next page on the right',
			'reader.readingDirectionToggle' => 'Reading direction',
			'reader.readingDirectionToggleLeftOpen' => 'Left-opening now (next page on the left) · tap for right-opening',
			'reader.readingDirectionToggleRightOpen' => 'Right-opening now (next page on the right) · tap for left-opening',
			'reader.readingDirectionToggleDisabled' => 'Webtoon mode has no horizontal reading direction',
			'reader.readingDirectionToggleSetting' => 'Show reading direction toggle in top bar',
			'reader.swipePreview' => 'Page-turn preview',
			'reader.swipePreviewSubtitle' => 'Show the actual image on both sides while turning, instead of a large page-number placeholder (decodes one extra viewport-width bitmap per page)',
			'reader.doublePage' => 'Double page',
			'reader.doublePageSubtitle' => 'Enable double-page spread in current reading mode',
			'reader.doublePageSeamless' => 'Seamless double page',
			'reader.doublePageSeamlessSubtitle' => 'Give each page half the width, preserve its aspect ratio, and remove the gap between them',
			'reader.doublePageLeadingBlank' => 'Leading blank',
			'reader.doublePageLeadingBlankSubtitle' => 'Insert a blank page at the start of each chapter to shift page pairing',
			'reader.splitLandscapePages' => 'Split landscape pages',
			'reader.splitLandscapePagesSubtitle' => 'Automatically split wide double-page images into left and right halves',
			'reader.landscapeSplitDirection' => 'Split reading order',
			'reader.splitDirectionAuto' => 'Follow reading direction',
			'reader.splitDirectionLtr' => 'Left to right (left first)',
			'reader.splitDirectionRtl' => 'Right to left (right first)',
			'reader.hoverReveal' => 'Hover Reveal',
			'reader.hoverRevealEnabled' => 'Edge Hover Reveal Toolbars',
			'reader.hoverRevealEnabledSubtitle' => 'Automatically show toolbars when mouse moves to top or bottom edge (NeoView style)',
			'reader.thumbnailStrip' => 'Bottom thumbnail strip',
			'reader.thumbnailStripSubtitle' => 'Expand per-page thumbnails in the control bar, fused with the progress bar; stays on across books, chapters and restarts',
			'reader.transparentTopBar' => 'Transparent top bar',
			'reader.transparentTopBarSubtitle' => 'Drop the glass material for a translucent scrim so the page shows through (JHenTai style)',
			'reader.transparentTopBarOpacity' => 'Top bar scrim opacity',
			'reader.thumbnailStripExpand' => 'Show thumbnails',
			'reader.thumbnailStripCollapse' => 'Hide thumbnails',
			'reader.thumbnailStripOriginalAspectRatio' => 'Use original thumbnail proportions',
			'reader.thumbnailStripOriginalAspectRatioSubtitle' => 'Off: uniform portrait thumbnails. On: show each image fully at its original proportions',
			'reader.thumbnailStripCurrent' => 'Now',
			'reader.thumbnailStripJumpToPage' => ({required Object page}) => 'Jump to page ${page}',
			'reader.hoverRevealTop' => 'Top Edge Reveals Header',
			'reader.hoverRevealBottom' => 'Bottom Edge Reveals Footer',
			'reader.hoverTriggerAreaTop' => 'Top Trigger Area Height',
			'reader.hoverTriggerAreaBottom' => 'Bottom Trigger Area Height',
			'reader.hoverHideDelay' => 'Auto Hide Delay on Leave',
			'reader.hoverShowVisualIndicator' => 'Show Edge Sensing Indicator',
			'reader.hoverShowVisualIndicatorSubtitle' => 'Display a subtle indicator line in the trigger area to preview sensing bounds',
			'reader.hoverAreaPreview' => 'Trigger Area Preview (NeoView style)',
			'reader.hoverAreaTopHint' => 'Top sensing area: {height}px',
			'reader.hoverAreaBottomHint' => 'Bottom sensing area: {height}px',
			'reader.pinTopBar' => 'Pin the top bar (stops auto-hide)',
			'reader.unpinTopBar' => 'Unpin the top bar',
			'reader.pinBottomBar' => 'Pin the bottom bar (stops auto-hide)',
			'reader.unpinBottomBar' => 'Unpin the bottom bar',
			'reader.landscapeReader' => 'Landscape reading',
			'reader.landscapeReaderSubtitle' => 'Switch to landscape while reading and restore the previous direction when you leave',
			'reader.themeMode' => 'Theme mode',
			'reader.autoRead' => 'Auto read',
			'reader.autoReadSubtitle' => 'Automatically scroll the reader',
			'reader.autoReadHidePauseButton' => 'Hide pause button',
			'reader.autoReadHidePauseButtonSubtitle' => 'Keep auto-read running without showing the pause/play button',
			'reader.autoReadSmooth' => 'Smooth scroll',
			'reader.autoReadSmoothSubtitle' => 'Continuous scroll in webtoon mode; off uses interval jumps',
			'reader.webtoonScrollDistance' => 'Webtoon scroll distance',
			'reader.webtoonScrollInterval' => 'Webtoon scroll interval',
			'reader.singlePageScrollInterval' => 'Single page scroll interval',
			'reader.preload' => 'Preload',
			'reader.preloadImageCount' => 'Preloaded image count',
			'reader.preloadImageCountSubtitle' => 'Download images after the current reading position in advance',
			'reader.preloadChapterCount' => 'Preloaded chapter count',
			'reader.preloadChapterCountSubtitle' => 'Load following chapter information in advance',
			'reader.background' => 'Background',
			'reader.auto' => 'Auto',
			'reader.black' => 'Black',
			'reader.white' => 'White',
			'reader.grey' => 'Grey',
			'reader.adaptive' => 'Adaptive',
			'reader.adaptiveEdge' => 'Edge gradient',
			'reader.ambientDim' => 'Background dimming',
			'reader.ambientDimSubtitle' => 'Dim the colour sampled from the page before using it as the backdrop; higher is easier on the eyes. Local comics only',
			'reader.readingExperience' => 'Reading experience',
			'reader.keyboardPageTurnSpeed' => 'Continuous page turn speed',
			'reader.keyboardPageTurnSpeedSubtitle' => 'In horizontal reading, pressing turns one page immediately. Holding a page turn key then repeats at this speed. Animation adapts to the speed; releasing only finishes the current turn. Each turn advances one spread in double-page mode.',
			'reader.pagesPerSecond' => 'pages/s',
			'reader.keyboardPageTurnAdvanced' => 'Advanced key hold options',
			'reader.keyboardPageTurnHoldDelay' => 'Hold start delay',
			'reader.keyboardPageTurnHoldDelaySubtitle' => 'How long to hold a key before continuous page turning starts. This only changes the initial wait; pages/s controls the continuous speed.',
			'reader.disableAnimation' => 'Disable page animation',
			'reader.disableAnimationSubtitle' => 'Disable full-page turn animation',
			'reader.readFilter' => 'Read filter (dark mode only)',
			'reader.readFilterSubtitle' => 'Only effective in reader, reduces brightness at night',
			'reader.filterIntensity' => 'Filter intensity',
			'reader.einkOptimization' => 'E-ink optimization (landscape)',
			'reader.einkOptimizationSubtitle' => 'Show white screen before image after page turn',
			'reader.einkDelay' => 'White screen duration',
			'reader.sidePadding' => 'Side padding',
			'reader.sidePaddingSubtitle' => 'Customize left/right padding ratio',
			'reader.sidePaddingPercent' => 'Padding per side',
			'reader.batterySubtitle' => 'Off by default, enable as needed',
			'reader.timeSubtitle' => 'Show current time',
			'reader.infoBarPosition' => 'Info bar position',
			'reader.showInStatusBar' => 'Show in status bar',
			'reader.showInStatusBarSubtitle' => 'Top info bar enters system status bar area',
			'reader.edgePadding' => 'Edge padding',
			'reader.infoBarStyle' => 'Info bar style',
			'reader.backgroundOpacity' => 'Background opacity',
			'reader.fontSize' => 'Font size',
			'reader.allHiddenNotice' => 'All hidden, info bar will be completely hidden',
			'reader.edgePaddingDisabled' => 'Edge padding has no effect when horizontally centered',
			'reader.bottomProgressBar' => 'Bottom progress bar',
			'reader.bottomProgressBarSubtitle' => 'Draw a thin always-on bar at the bottom edge of the page. It stays while the top/bottom bars are hidden, and is independent of the info pill',
			'reader.bottomProgressBarGlow' => 'Progress bar glow',
			'reader.bottomProgressBarGlowSubtitle' => 'Add a halo to the part already read',
			'reader.settings' => 'Reader settings',
			'reader.previousChapter' => 'Previous chapter',
			'reader.nextChapter' => 'Next chapter',
			'reader.backToHome' => 'Back to home',
			'reader.jumpToChapterTitle' => 'Jump',
			'reader.jumpToChapterMessage' => ({required Object chapter}) => 'Jump to ${chapter}?',
			'reader.selectChapter' => 'Select chapter',
			'reader.enterFullscreen' => 'Fullscreen (F11)',
			'reader.exitFullscreen' => 'Exit fullscreen',
			'reader.chapterTransition' => 'Chapter transition',
			'reader.transitionSwipeToLoad' => 'Swipe to load',
			'reader.transitionLoaded' => 'Load complete',
			'reader.transitionLoadFailedRetry' => 'Load failed, tap to retry',
			'reader.pullDownToPrevChapter' => 'Pull down to previous chapter',
			'reader.releaseToJumpPrevChapter' => 'Release to jump to previous chapter',
			'reader.releaseToLoadPrevChapter' => 'Release to load previous chapter',
			'reader.pullUpToNextChapter' => 'Pull up to next chapter',
			'reader.releaseToJumpNextChapter' => 'Release to jump to next chapter',
			'reader.releaseToLoadNextChapter' => 'Release to load next chapter',
			'reader.chapterNotDownloaded' => 'Chapter not downloaded',
			'reader.loadFailedWithResult' => ({required Object result}) => '${result}\nLoad failed',
			'reader.chapterOrder' => ({required Object order}) => 'Chapter ${order}',
			'reader.doubleTapAction' => 'Double-tap action',
			'reader.doubleTapZoom' => 'Double-tap zoom',
			'reader.doubleTapZoomSubtitle' => 'Double-tap image to toggle zoom',
			'reader.doubleTapOpenMenu' => 'Double-tap to open menu',
			'reader.doubleTapOpenMenuSubtitle' => 'Double-tap page to open menu (exclusive with zoom)',
			'reader.centerTapBar' => 'Tap to reveal bars',
			'reader.centerTapToggleBars' => 'Tap center to toggle top/bottom bars',
			'reader.centerTapToggleBarsSubtitle' => 'When off, tapping the reader no longer shows or hides the top/bottom bars (in webtoon mode this covers tap-anywhere too). Reveal them with edge hover on desktop or a double tap instead.',
			'reader.volumeKeyPageTurn' => 'Volume key page turn',
			'reader.enableVolumeKeyPageTurn' => 'Enable volume key page turn',
			'reader.volumeKeyPageTurnSubtitle' => 'Use volume keys to turn pages/scroll',
			'reader.screenHeightPercent' => '% screen height',
			'reader.milliseconds' => 'ms',
			'reader.percent' => '%',
			'reader.pixels' => 'px',
			'reader.gesture' => 'Gestures & Hover',
			'reader.infoBar' => 'Info Bar',
			'reader.tabRead' => 'Reading',
			'reader.tabGesture' => 'Gestures',
			'reader.tabScreen' => 'Interface',
			'reader.tabPicture' => 'Picture',
			'reader.tabTranslate' => 'Translate',
			'reader.chromeSection' => 'Bars & margins',
			'reader.tuningSection' => 'Picture tuning',
			'reader.autoTrimMargins' => 'Auto-trim margins',
			'reader.autoTrimMarginsSubtitle' => 'Detect each page\'s content area and zoom to it; original pixels untouched',
			'reader.pauseAutoRead' => 'Pause auto read',
			'reader.resumeAutoRead' => 'Resume auto read',
			'reader.imageLoadFailedRetry' => ({required Object error}) => '${error}\nLoad failed, tap to retry',
			'reader.imageSavedTo' => ({required Object path}) => 'Image saved to: ${path}',
			'reader.imageSavedToAlbum' => 'Image saved to album',
			'reader.imageSaveFailed' => 'Image save failed',
			'reader.saveImagePermissionDenied' => 'Save failed: please grant album access in settings',
			'reader.imageSaveFailedWithError' => ({required Object error}) => 'Save failed: ${error}',
			'reader.radialMenuHint' => 'Release to run · centre or Esc to cancel',
			'reader.radialMenuHintMove' => 'Move to choose',
			'reader.radialMenuHintRelease' => 'Release to run',
			'reader.radialMenuHintSwitch' => 'Release to switch wheel',
			'reader.singlePageLtr' => 'Left to right',
			'reader.singlePageRtl' => 'Right to left',
			'plugin.getInfoJsonBadFormat' => 'getInfoJson returned malformed data',
			'plugin.getInfoBadFormat' => 'getInfo returned malformed data',
			'plugin.badResponseFormat' => 'The plugin returned a malformed response',
			'plugin.advancedCapabilityLoading' => 'Loading advanced capabilities...',
			'plugin.store' => 'Plugin Store',
			'plugin.searchHint' => 'Search plugin name or author...',
			'plugin.localInstall' => 'Local install',
			'plugin.networkInstall' => 'Network install',
			'plugin.cloudComponents' => 'Cloud components',
			'plugin.restrictedSourceBlocked' => 'This source is not available. Enable "Full source list" in Settings → Content & Network first',
			'plugin.restrictedSourcesHidden' => ({required Object count}) => '${count} source(s) hidden',
			'plugin.loginSuccess' => 'Please complete login in the browser, the host will sync cookies automatically',
			'plugin.chromiumFallbackUnsupported' => 'External Chromium auto-login fallback is not supported on this platform',
			'plugin.switchingToExternalBrowser' => 'Built-in WebView login is limited, switching to external browser...',
			'plugin.chromiumNotFound' => 'No Chromium browser detected, please install Chrome first',
			'plugin.browserSwitched' => ({required Object browser}) => 'Switched to ${browser}, cookies will be synced automatically after login',
			'plugin.invalidLink' => ({required Object url}) => 'Invalid link: ${url}',
			'plugin.cannotOpenLink' => ({required Object url}) => 'Cannot open link: ${url}',
			'plugin.readLocalPluginFailed' => ({required Object error}) => 'Failed to read local plugin: ${error}',
			'plugin.unsupportedLocalFileType' => ({required Object fileName}) => 'Unsupported local file type, only .js / .cjs / .br are supported: ${fileName}',
			'plugin.addFromNetwork' => 'Add plugin from network',
			'plugin.urlCannotBeEmpty' => 'URL cannot be empty',
			'plugin.startInstall' => 'Start install',
			'plugin.pluginSettingsTitle' => ({required Object name}) => '${name} settings',
			'plugin.debugConfigUpdated' => 'Plugin debug config updated',
			'plugin.deletePlugin' => 'Delete plugin',
			'plugin.confirmDeletePlugin' => 'Delete this plugin? This will delete plugin and related data.',
			'plugin.deleteFailed' => ({required Object error}) => 'Delete failed: ${error}',
			'plugin.pluginDeleted' => 'Plugin deleted',
			'plugin.executeFailed' => ({required Object error}) => 'Execute failed: ${error}',
			'plugin.deletePluginSubtitle' => 'Delete plugin and related data permanently',
			'plugin.debugMode' => 'Debug mode',
			'plugin.debugAddress' => 'Debug address',
			'plugin.accountLoginSubtitle' => 'Go to login',
			'plugin.accountLogin' => 'Account login',
			'plugin.pluginDetail' => 'Plugin detail',
			'plugin.pluginDetailSubtitle' => 'View description and homepage',
			'plugin.pluginSettings' => 'Plugin settings',
			'plugin.noUserInfo' => 'No user info',
			'plugin.operations' => 'Operations',
			'plugin.management' => 'Plugin management',
			'plugin.installed' => 'Installed',
			'plugin.notInstalled' => 'Not installed',
			'plugin.update' => 'Update',
			'plugin.install' => 'Install',
			'plugin.uninstall' => 'Uninstall',
			'plugin.author' => 'Author',
			'plugin.version' => 'Version',
			'plugin.description' => 'Description',
			'plugin.repo' => 'Repository',
			'plugin.homepage' => 'Homepage',
			'plugin.githubRepo' => 'GitHub Repo',
			'plugin.download' => 'Download',
			'plugin.downloadUpdate' => 'Download update',
			'plugin.noCloudPlugins' => 'No cloud components',
			'plugin.noMatchingPlugins' => 'No matching plugins',
			'plugin.networkInstallHint' => 'Enter plugin script URL',
			'plugin.cloudPluginsLoadFailed' => ({required Object error}) => 'Failed to load cloud components: ${error}',
			'plugin.installingFromCloud' => ({required Object name}) => 'Downloading and installing ${name}...',
			'plugin.installingFromLocal' => 'Installing local plugin...',
			'plugin.installingFromNetwork' => 'Downloading network plugin...',
			'plugin.cloudDownloadFailed' => ({required Object error}) => 'Cloud download failed: ${error}',
			'plugin.networkDownloadFailed' => ({required Object error}) => 'Network plugin download failed: ${error}',
			'plugin.remoteAssetNotFound' => 'Remote plugin file not found (404). It may have been removed or the version updated. Please check the update URL or retry later',
			'plugin.githubRateLimited' => 'GitHub access is rate limited (likely IP-based). Please retry later or switch networks; a truly missing plugin still reports 404',
			'plugin.remoteReturnedWebPage' => 'Remote returned a web page instead of a plugin file. The remote file may be missing or the link expired. Please check the plugin update URL',
			'plugin.remoteEmptyResponse' => 'Remote returned empty content. Please retry later or check the update URL',
			'plugin.remoteAccessDenied' => ({required Object status}) => 'Remote access denied (HTTP ${status}). Please check your network or retry later',
			'plugin.remoteServerError' => ({required Object status}) => 'Remote server error (HTTP ${status}). Please retry later',
			'plugin.remoteHttpError' => ({required Object status}) => 'Remote request failed (HTTP ${status}). Please retry later',
			'plugin.downloadedScriptInvalid' => 'Downloaded file is not a valid plugin script (looks like a web or error page). Please verify the remote file exists and retry',
			'plugin.downloadedScriptCorrupted' => 'Downloaded plugin file is corrupted or failed to decompress. Please retry later',
			'plugin.networkUnstableRetry' => 'Unstable network, download failed. Please check your connection and retry',
			'plugin.cloudVersion' => ({required Object version}) => 'Cloud ${version}',
			'plugin.localVersion' => ({required Object version}) => 'Local ${version}',
			'plugin.loginTitle' => ({required Object name}) => '${name} Login',
			'plugin.cookieSynced' => 'Login cookie synced',
			'plugin.executeSuccess' => 'Executed successfully',
			'plugin.userInfoTitle' => 'User info',
			'plugin.userInfoLoadFailed' => 'Failed to load user info',
			'plugin.unnamedAction' => 'Unnamed action',
			'plugin.pluginSettingsLoading' => 'Loading plugin settings...',
			'plugin.pluginSettingsLoadFailed' => 'Failed to load plugin settings',
			'plugin.actionNotExecutable' => 'Action not executable: missing fnPath',
			'plugin.saved' => 'Saved',
			'plugin.close' => 'Close',
			'plugin.sync' => 'Sync',
			'plugin.syncSubtitle' => 'Check and update via npm / updateUrl',
			'plugin.syncing' => 'Syncing plugin...',
			'plugin.syncSuccess' => 'Sync successful',
			'plugin.syncFailed' => ({required Object error}) => 'Sync failed: ${error}',
			'plugin.updateSubtitle' => 'Manually reinstall this plugin from a network URL or local file',
			'plugin.updateFromNetwork' => 'Install from network',
			'plugin.updateFromLocal' => 'Install from local',
			'plugin.updateChooseSource' => 'Choose install method',
			'plugin.updating' => 'Updating plugin...',
			'plugin.updateSuccess' => 'Update successful',
			'plugin.updateFailed' => ({required Object error}) => 'Update failed: ${error}',
			'plugin.uuidMismatch' => 'Plugin id mismatch, install rejected',
			'plugin.currentVersion' => ({required Object version}) => 'Current version ${version}',
			'plugin.alreadyLatest' => 'Already up to date',
			'gestureLock.gestureTitle' => 'Gesture unlock',
			'gestureLock.gestureHint' => 'Draw gesture password',
			'gestureLock.pinTitle' => 'Enter PIN',
			'gestureLock.pinHint' => 'Enter reset PIN',
			'gestureLock.atLeast4Points' => 'Connect at least 4 points',
			'gestureLock.confirmGesture' => 'Please draw again to confirm',
			'gestureLock.gestureNotMatch' => 'The two drawings do not match',
			'gestureLock.setSuccess' => 'Set successfully',
			'gestureLock.forgotPassword' => 'Forgot password',
			'gestureLock.incorrectPassword' => 'Incorrect gesture password, please try again',
			'gestureLock.resetPin' => 'Reset PIN',
			'gestureLock.pin' => 'PIN',
			'gestureLock.pinDescription' => 'PIN can reset gesture password. If both are forgotten, you cannot enter the app. Please keep it safe.',
			'gestureLock.pinMinLength' => 'PIN must be at least 4 digits',
			'gestureLock.pinNotMatch' => 'The two PINs do not match',
			'gestureLock.pinIncorrect' => 'Incorrect PIN, please try again',
			'gestureLock.appLocked' => 'App is locked',
			'gestureLock.verifyToUnlock' => 'Please complete gesture verification',
			'gestureLock.resetGesturePassword' => 'Reset gesture password',
			'gestureLock.resetPinHint' => 'Enter the reset PIN you saved',
			'gestureLock.passwordCleared' => 'Password cleared, please set again',
			'gestureLock.setupHintFirst' => 'Please connect at least 4 points',
			'gestureLock.setupHintConfirm' => 'Please draw the same gesture again',
			'gestureLock.setupErrorMinPoints' => 'Connect at least 4 points',
			'gestureLock.setupErrorMismatch' => 'Gestures do not match, please set again',
			'gestureLock.pinHintMinDigits' => 'At least 4 digits',
			'appBootstrap.initializing' => 'Initializing....',
			'appBootstrap.verifyGesture' => 'Please verify gesture password',
			'appBootstrap.pinVerifyFailed' => 'PIN verification failed',
			'appBootstrap.unlockCancelled' => 'Unlock cancelled',
			'appBootstrap.enteringApp' => 'Verification successful, entering app',
			'comments.retry' => 'Retry',
			'comments.noComments' => 'No comments yet',
			'comments.loadMore' => 'Load more',
			'comments.collapseReplies' => 'Collapse replies',
			'comments.replyCount' => ({required Object count}) => '${count} replies',
			'comments.noReplies' => 'No replies yet',
			'comments.loadMoreReplies' => 'Load more replies',
			'comments.postComment' => 'Post comment',
			'comments.postCommentHint' => 'Enter comment content',
			'comments.postReply' => 'Reply',
			'comments.postReplyHint' => 'Enter reply content',
			'comments.cancel' => 'Cancel',
			'comments.confirm' => 'Confirm',
			'comments.postSuccess' => 'Posted successfully',
			'comments.postFailed' => ({required Object error}) => 'Failed to post: ${error}',
			'comments.anonymous' => 'Anonymous',
			'cache.title' => 'Cache settings',
			'cache.currentCache' => 'Current cache',
			'cache.clearCache' => 'Clear cache',
			'cache.clearCacheConfirm' => 'Are you sure you want to clear all cache files? This action cannot be undone.',
			'cache.cleared' => 'Cache cleared',
			'cache.clearFailed' => 'Clear failed',
			'cache.cacheSize' => 'Cache size',
			'cache.recalculate' => 'Recalculate',
			'cache.manualClear' => 'Manual clear cache',
			'cache.manualClearSubtitle' => 'Delete all cache files immediately',
			'cache.clear' => 'Clear',
			'cache.cacheLimit' => 'Cache limit',
			'cache.sizeLimit' => 'Cache size limit',
			'cache.sizeLimitSubtitle' => 'Old cache will be automatically cleared when the limit is reached',
			'cache.autoClean' => 'Auto clean cache',
			'cache.autoCleanSubtitle' => 'Automatically clean old cache when exceeding limit',
			'cache.calculating' => 'Calculating...',
			'cache.calculateFailed' => 'Calculate failed',
			'dataBackup.title' => 'Local Import/Export',
			'dataBackup.exportSection' => 'Export',
			'dataBackup.importSection' => 'Import',
			'dataBackup.includeDownloads' => 'Include downloaded comics',
			'dataBackup.includeDownloadsSubtitle' => 'Pack downloaded comic files when exporting',
			'dataBackup.exportData' => 'Export data',
			'dataBackup.exportDataSubtitle' => 'Pack settings and data into zip',
			'dataBackup.importData' => 'Import data',
			'dataBackup.importDataSubtitle' => 'Restore data from zip file',
			'dataBackup.selectExportDirFailed' => 'Failed to select export directory',
			'dataBackup.exporting' => 'Exporting, please wait…',
			'dataBackup.exportSuccess' => 'Export successful',
			'dataBackup.savedTo' => ({required Object path}) => 'Saved to: ${path}',
			'dataBackup.exportShareHint' => 'Use the share sheet and choose "Save to Files" to keep the backup.',
			'dataBackup.exportFailed' => 'Export failed',
			'dataBackup.processingBackup' => 'Processing backup file…',
			'dataBackup.selectBackupFailed' => 'Failed to select backup file',
			'dataBackup.readingBackup' => 'Reading backup info…',
			'dataBackup.readBackupFailed' => 'Failed to read backup',
			'dataBackup.importing' => 'Importing, please wait…',
			'dataBackup.importFailed' => 'Import failed',
			'dataBackup.importTitle' => 'Import data',
			'dataBackup.importConfirm' => 'Import will replace backed-up settings and app data. Local paths, proxy, app lock and sync configuration will be kept. Continue?',
			'dataBackup.includesDownloadsWarning' => 'This backup contains downloaded comic files. Existing downloads will be deleted before import.',
			'dataBackup.versionMismatch' => 'Version mismatch. Data import may have issues. Continue?',
			'dataBackup.exportedVersion' => ({required Object version}) => 'Exported version: ${version}',
			'dataBackup.currentVersion' => ({required Object version}) => 'Current app version: ${version}',
			'dataBackup.kContinue' => 'Continue',
			'dataBackup.importSuccess' => 'Import successful',
			'dataBackup.restartPrompt' => 'Data imported successfully. Please restart the app to apply.',
			'webdavSync.title' => 'Cloud Sync Config',
			_ => null,
		} ?? switch (path) {
			'webdavSync.serviceTitle' => ({required Object service}) => '${service} Sync Config',
			'webdavSync.noneTip' => 'Please select a sync service in Settings first, then return here to fill in the configuration.',
			'webdavSync.deleteConfig' => 'Delete Config',
			'webdavSync.testAndSave' => 'Test & Save',
			'webdavSync.faq' => 'FAQ',
			'webdavSync.webdavHost' => 'WebDAV URL',
			'webdavSync.username' => 'Username',
			'webdavSync.password' => 'Password',
			'webdavSync.s3Endpoint' => 'Endpoint',
			'webdavSync.s3EndpointHint' => 'e.g. s3.amazonaws.com',
			'webdavSync.s3AccessKey' => 'Access Key',
			'webdavSync.s3SecretKey' => 'Secret Key',
			'webdavSync.s3Bucket' => 'Bucket Name',
			'webdavSync.s3Region' => 'Region (optional)',
			'webdavSync.s3Port' => 'Port (optional)',
			'webdavSync.useSsl' => 'Use HTTPS/SSL',
			'webdavSync.pathStyle' => 'Path-Style',
			'webdavSync.pathStyleSubtitle' => 'Self-hosted MinIO usually requires this option',
			'webdavSync.connectingWebdav' => 'Connecting to WebDAV server...',
			'webdavSync.webdavConnected' => 'WebDAV connected and settings saved.',
			'webdavSync.webdavConnectFailed' => ({required Object error}) => 'Connection failed. Please check network or WebDAV address.\n${error}',
			'webdavSync.invalidPort' => 'Invalid port. Please enter a number between 0 and 65535.',
			'webdavSync.connectingS3' => 'Connecting to S3 service...',
			'webdavSync.s3Connected' => 'S3 connected and settings saved.',
			'webdavSync.s3ConnectFailed' => ({required Object error}) => 'Connection failed. Please check S3 configuration.\n${error}',
			'webdavSync.close' => 'Close',
			'webdavSync.success' => 'Success',
			'webdavSync.error' => 'Error',
			'webdavSync.faqMarkdown' => '### What can be synced?\n- Currently syncs Bika history, JM favorites, and JM history.\n\n### How to configure WebDAV?\n- Fill in WebDAV URL, username, password, then tap Test & Save.\n\n### How to configure S3?\n- Endpoint examples: `s3.amazonaws.com`, `s3.filebase.com`, `play.min.io`.\n- For self-hosted MinIO, fill in a custom port and disable SSL if necessary.\n\n### How often does auto-sync run?\n- Every 5 minutes.\n\n### How to trigger a manual sync?\n- Tap Test & Save on the sync config page.\n- Or toggle the auto-sync switch in Settings.',
			'ocr.title' => 'Manga Translation (Finished Pages)',
			'ocr.endpointSection' => 'Translation endpoint',
			'ocr.baseUrl' => 'Base URL',
			'ocr.baseUrlHint' => 'https://api.deepseek.com/v1 or http://127.0.0.1:11434/v1',
			'ocr.baseUrlNone' => 'Not configured',
			'ocr.model' => 'Model name',
			'ocr.modelHint' => 'e.g. deepseek-chat, qwen2.5:14b',
			'ocr.apiKey' => 'API key',
			'ocr.apiKeySubtitle' => 'Stored locally only, never exported; leave empty for local Ollama',
			'ocr.targetLanguage' => 'Target language',
			'ocr.glossary' => 'Glossary',
			'ocr.glossarySubtitle' => 'One per line: source=target; changing it re-translates finished pages',
			'ocr.glossaryHint' => 'トカゲ=stone skink',
			'ocr.saved' => 'Saved',
			'ocr.notConfigured' => 'Base URL or model name is missing',
			'ocr.epSection' => 'Inference backend',
			'ocr.ep' => 'Inference backend',
			'ocr.epSubtitle' => 'Measured: both models are slower on CoreML, so CPU is the default',
			'ocr.epPlan' => ({required Object detect, required Object recognize, required Object inpaint}) => 'Per stage on this machine: detect ${detect} · recognize ${recognize} · inpaint ${inpaint}',
			'ocr.epPlanUnsupported' => ({required Object ep}) => 'This platform\'s build has no ${ep} — picking it fails as analysis starts; it never silently falls back to CPU',
			'ocr.displaySection' => 'Finished-page display',
			'ocr.displayChoice' => 'Display mode',
			'ocr.displayChoiceSubtitle' => 'Only pages translated afterwards follow the new mode; tap translate again on a page to rebuild it (a dozen seconds each).',
			'ocr.displayBaked' => 'Bake into the image (replaces upscaling on that page)',
			'ocr.displayOverlay' => 'Draw as an overlay (text on the erased base)',
			'ocr.displayOverlayHint' => 'Overlay only paints the text on top of the base; but the base has to be the erased one, so such a page claims the enhanced track and upscaling yields for it. The "every bubble has a flat fill, so no inpaint needed" shortcut has never fired: 0 of 121 boxes across 8 real pages (see ADR-0018 §4).',
			'ocr.modelSection' => 'Model weights',
			'ocr.weightsReady' => ({required Object count}) => 'Weights ready (${count} files)',
			'ocr.weightsMissing' => ({required Object missing}) => 'Missing: ${missing}',
			'ocr.download' => 'Download weights',
			'ocr.downloading' => 'Downloading',
			'ocr.downloadDone' => 'Weights downloaded',
			'ocr.downloadFailed' => 'Weight download failed',
			'ocr.cacheSection' => 'Finished-page cache',
			'ocr.cacheCount' => ({required Object count}) => '${count} finished pages generated',
			'ocr.cacheEmpty' => 'No finished pages yet',
			'ocr.clearCache' => 'Clear finished-page cache',
			'ocr.clearCacheSubtitle' => 'Use after changing the model or the font; original images are untouched',
			'ocr.cacheCleared' => 'Finished-page cache cleared',
			'ocr.logSection' => 'Diagnostics',
			'ocr.viewLog' => 'Translation log',
			'ocr.logHint' => 'One line per gate for each page: endpoint, inference (with the EP actually used per stage), translation request, typesetting, write, presenter check.',
			'ocr.logDialogTitle' => 'Manga translation log',
			'ocr.logEmpty' => 'No translation log yet. Tap translate in the reader, or run Settings → Debug → OCR page smoke, and steps will show up here.',
			'ocr.copyLog' => 'Copy log',
			'ocr.logCopied' => 'Translation log copied',
			'ocr.openLogLocation' => 'Reveal log file',
			'ocr.readerHint' => 'Tap the translate button in the reader toolbar to switch this page only',
			'ocr.chipOff' => 'Translate',
			'ocr.chipOn' => 'Translated',
			'ocr.chipOnOverlay' => 'Translated · overlay',
			'ocr.building' => 'Working',
			'ocr.failedShort' => 'Failed',
			'ocr.busyToast' => 'This page is still being translated',
			'ocr.needWeights' => 'Weights are incomplete; download them in Settings',
			'ocr.engine' => 'Translation engine',
			'ocr.engineSubtitle' => 'API endpoint bills per token and needs network; Apple system translation runs on-device, free and offline',
			'ocr.autoTranslatePage' => 'Auto-translate each new page',
			'ocr.autoTranslatePageSubtitle' => 'A finished page takes 10s+, so leaving this on means waiting on every page. Turning it off only affects later pages; already built pages stay.',
			'ocr.engineAppleInstalled' => 'Language pack installed — active now (15 blocks measured at ~300 ms)',
			'ocr.engineAppleMissing' => 'The ja → target translation language pack is not installed. There is no API for an app to download it — install it in System Settings › General › Language & Region, then come back',
			'ocr.engineAppleUnsupportedPair' => 'The system does not know this language pair; change the target language or use an endpoint',
			'ocr.engineAppleUnavailable' => 'No system translation on this machine (macOS 15+ / iOS 18+ only)',
			'ocr.glossaryIgnoredOnApple' => 'System translation has no glossary API: in this mode the glossary is ignored and proper nouns get generic translations',
			'ocr.engineHunyuanHint' => 'This engine needs a local server first, e.g. llama-server -m Hy-MT2-1.8B-Q4_K_M.gguf --device MTL0 -ngl 99 --port 8080\nSet base URL to http://127.0.0.1:8080/v1 and use the same model name as --model. The glossary takes effect via its native Terminology mode.\nMeasured: 1.8B is enough (~158 ms/line, ~2.4 s/page) — the glossary fixes ヤモリ/危機契約 line by line and 7B is no better at 4x the size. On macOS --device must be MTL0, otherwise llama.cpp silently uses the CPU (4.8x slower).',
			'realSr.openedUpscaleCache' => ({required Object dir}) => 'No upscale output yet; opened the upscale cache folder: ${dir}',
			'realSr.openedRecentLocation' => ({required Object output}) => 'Opened the folder holding the latest output: ${output}',
			'realSr.openFolderFailed' => ({required Object error}) => 'Opening the folder failed: ${error}',
			'realSr.openFolderUnsupported' => ({required Object dir}) => 'This platform can\'t open folders: ${dir}',
			'realSr.coremlModelPhoto' => 'Real-ESRGAN x4plus · photo / CG',
			'realSr.mimageInferenceFailed' => ({required Object error}) => 'mImage ONNX inference failed: ${error}',
			'realSr.modelUnavailableHint' => ({required Object engine}) => 'Model unavailable: ${engine}. Download it in the upscale settings first.',
			'realSr.archiveMissingOnnx' => ({required Object file}) => 'Archive is missing the mImage ONNX model ${file}',
			'realSr.archiveContentMismatch' => ({required Object missing}) => 'Archive contents don\'t meet this engine\'s requirements: ${missing}',
			'realSr.modelFileNameMismatch' => ({required Object expected, required Object actual}) => 'File name doesn\'t match the current model: expected ${expected}, got ${actual}',
			'realSr.missingOnnxDownload' => ({required Object file}) => 'Missing mImage ONNX model ${file}; download it in the settings',
			'realSr.importJsonInvalid' => ({required Object error}) => 'Invalid JSON: ${error}',
			'realSr.copyLog' => 'Copy log',
			'realSr.blockInfoDetail' => ({required Object contentSize, required Object blockSize, required Object shrink}) => 'Tiling: content block ${contentSize}×${contentSize}, model input ${blockSize}×${blockSize} (includes ${shrink} px reflection padding); fixed by the model',
			'realSr.deleteModelConfirmNamed' => ({required Object name}) => 'Delete ${name}? You can download it again if needed.',
			'realSr.actionFailedDetail' => ({required Object error}) => 'Operation failed: ${error}',
			'realSr.importConditionSuccess' => ({required Object count}) => 'Successfully imported ${count} conditions',
			'realSr.logEmptyText' => 'No upscale log yet. Once upscaling runs, inference and replacement are logged here.',
			'realSr.upscaleLogCopied' => 'Upscale log copied',
			'realSr.expandEditor' => 'Expand editor',
			'realSr.collapseEditor' => 'Collapse editor',
			'realSr.conditionListSummary' => ({required Object total, required Object enabled}) => 'Conditions (${total}, ${enabled} enabled)',
			'realSr.conditionNeedsAutoUpscale' => 'Enable [Auto upscaling] above first; only then do conditions apply while reading and preloading.',
			'realSr.conditionUpscaleSubtitle' => 'Dispatch upscale actions and skip rules by image size, path regex and metadata',
			'realSr.conditionUpscaleTitle' => 'Condition upscaling (neo)',
			'realSr.advancedOptionsTitle' => 'Advanced upscale options (pre-upscale / log)',
			'realSr.ncnnCliDesc' => 'Runs the waifu2x / Real-CUGAN ncnn-vulkan executables; mode, scale, concurrency and tiling are set at the bottom of the “Image upscaling” page.',
			'realSr.coremlDesc' => 'Swift calls Apple CoreML directly and reuses the loaded model.',
			'realSr.nativeScaleLabel' => ({required Object x}) => 'Native ${x}×',
			'realSr.modeCuganQuality' => 'Real-CUGAN · quality first',
			'realSr.modeWaifuFast' => 'waifu2x · speed first',
			'realSr.nativeModel' => 'Rossi native model',
			'realSr.engineSwitchHint' => 'Switching reprocesses the current page; each engine keeps its own model choice.',
			'realSr.hardwareAcceleration' => 'Hardware acceleration',
			'realSr.upscaleEngine' => 'Upscale engine',
			'realSr.preUpscaleHint' => 'One page at a time to avoid memory contention; set both to 0 to disable pre-upscaling.',
			'realSr.pageCount' => ({required Object n}) => '${n} pages',
			'realSr.preUpscaleCurrentFirst' => 'Pre-upscale (current page first)',
			'realSr.enableTta' => 'Enable TTA',
			'realSr.writeResultCache' => 'Write results to cache',
			'realSr.enableTile' => 'Enable tiling (Tile)',
			'realSr.actionUpscaleHit' => 'When matched: run upscaling',
			'realSr.actionSkipHit' => 'When matched: skip upscaling (no processing)',
			'realSr.actionSectionTitle' => 'Trigger action (Action)',
			'realSr.excludePreUpscale' => 'Exclude from the pre-upscale queue',
			'realSr.matchArchivePath' => 'Match paths inside the archive',
			'realSr.regexExampleOr' => 'or',
			'realSr.regexExamplePrefix' => 'e.g. ',
			'realSr.matchSectionTitle' => 'Size and rule matching (Match)',
			'realSr.enableThisCondition' => 'Enable this condition',
			'realSr.conditionEnabledBadge' => 'Enabled',
			'realSr.importSuccessSkipped' => ({required Object imported, required Object skipped}) => 'Imported ${imported} conditions, skipped ${skipped} incompatible ones',
			'realSr.importContentEmpty' => 'Import content cannot be empty',
			'realSr.importJsonSample' => '[\n  {\n    "name": "Example condition",\n    ...\n  }\n]',
			'realSr.pasteExportedJson' => 'Paste the exported JSON array or backup object text:',
			'realSr.conditionJsonCopied' => 'Condition JSON copied to clipboard',
			'realSr.conditionsRestored' => 'Default conditions restored',
			'realSr.keepAtLeastOneCondition' => 'Keep at least one upscale condition',
			'realSr.conditionCopy' => ({required Object name}) => '${name} (copy)',
			'realSr.importLocalHint' => 'For local import, pick the mImage ONNX model matching the file name above. After switching, the current page is re-upscaled.',
			'realSr.modelNotInstalled' => 'Current model not installed; download or import it before use',
			'realSr.modelInstalled' => 'Current model installed',
			'realSr.modelRuntime' => ({required Object runtime}) => 'Runtime: ${runtime}',
			'realSr.modelDenoiseFixed' => 'Denoise: fixed by the model, no separate strength control',
			'realSr.modelDenoiseCugan' => 'Denoise: Real-CUGAN conservative repair, strength fixed by the model',
			'realSr.modelScaleNote' => ({required Object scale}) => 'Scale: native ${scale}× (set by the model)',
			'realSr.exampleBuiltinHint' => 'No page is being read, so the built-in sample is shown; open a comic and expand again to see the current page.',
			'realSr.exampleSemantics' => ({required Object title, required Object before, required Object after, required Object description}) => '${title} sample. ${before} compared with ${after}. Tap to view full size. ${description}',
			'realSr.exampleTitleSuffix' => ({required Object title}) => '${title} (sample)',
			'realSr.exampleLiveSource' => 'Taken from the page you are reading; released as soon as the preview closes.',
			'realSr.beforeUnchanged' => ({required Object before}) => '${before} (kept as-is)',
			'realSr.beforeTrimmedShadow' => ({required Object before}) => '${before} (shaded area is what gets trimmed)',
			'realSr.loadingTrimResult' => 'Reading the current page\'s trim result…',
			'realSr.loadingDenoiseResult' => 'Reading the current page\'s denoise result…',
			'realSr.exampleImageNotReadyRetry' => 'The current page image is not ready yet; turn the page or try again shortly',
			'realSr.previewFailed' => ({required Object error}) => 'Preview failed: ${error}',
			'realSr.afterDenoise' => 'Denoised',
			'realSr.afterTrim' => 'Trimmed',
			'realSr.exampleDenoiseDesc' => 'The same JPEG crop actually processed by RealPLKSR 1×; resolution stays the same. Results vary with the source image.',
			'realSr.exampleTrimDesc' => 'Removes the surrounding margins so the comic fills more of the screen. The sample image does not change with the settings.',
			'realSr.exampleDenoiseTitle' => 'Denoise preview',
			'realSr.exampleTrimTitle' => 'Auto-trim preview',
			'realSr.denoiseAttribution' => 'From mImageViewer · CC BY 4.0\nDownloaded on first use; installed once size and SHA-256 check out.',
			'realSr.retryDownload' => 'Retry download',
			'realSr.denoiseProgressTooltip' => 'Model download progress',
			'realSr.denoiseVerifyTooltip' => 'Verify model integrity',
			'realSr.denoiseSubtitle' => 'RealPLKSR · JPEG denoise · 1×',
			'realSr.denoiseUpdateFailed' => 'Update failed · the installed model still works',
			'realSr.denoiseInstalled' => ({required Object size}) => 'Model installed · ${size}',
			'realSr.denoiseVerifying' => 'Verifying model',
			'realSr.denoiseMissing' => 'Model not installed',
			'realSr.denoiseChecking' => 'Checking model',
			'realSr.modelIncomplete' => 'Model is incomplete',
			'realSr.modelDownloadDone' => 'Model download finished',
			'realSr.manualImportUnsupported' => 'This platform does not support manual upscale-model import',
			'realSr.missingModelDirs' => 'Missing model directories (models-pro / models-se etc.)',
			'realSr.missingExecutable' => 'Missing waifu2x / Real-CUGAN executable',
			'realSr.missingModelFile' => ({required Object file}) => 'Missing model file ${file}',
			'realSr.missingModelDir' => ({required Object dir}) => 'Missing model directory ${dir}',
			'realSr.missingOnnxModel' => ({required Object file}) => 'Missing mImage ONNX model ${file}',
			'realSr.previewEnhancedUnreadable' => 'The enhanced result can\'t be read right now, so no comparison is shown',
			'realSr.previewDenoiseOriginal' => 'Denoise not applied · the page shown is still the original',
			'realSr.previewDenoiseCompare' => 'Denoise applied · compared against the enhanced page the reader shows',
			'realSr.previewDenoisePending' => ({required Object phase}) => 'Denoise not applied yet · ${phase}',
			'realSr.previewDenoiseApplied' => 'JPEG denoise applied · RealPLKSR 1×',
			'realSr.previewBothApplied' => 'Denoise and upscale applied · compared against the enhanced page on screen',
			'realSr.previewDenoiseOff' => 'This image is not denoised · denoise is off for this comic',
			'realSr.previewDenoiseJpegOnly' => 'This image is not denoised · only JPEG pages are processed, this one stays as-is',
			'realSr.trimInsets' => ({required Object left, required Object top, required Object right, required Object bottom}) => 'left ${left} · top ${top} · right ${right} · bottom ${bottom}',
			'realSr.previewTrimApplied' => ({required Object summary}) => 'Display trim applied · ${summary}',
			'realSr.previewTrimNotNeeded' => 'This image is not trimmed · nothing to trim, kept as-is',
			'realSr.previewTrimPending' => 'Trim detection not finished · waiting for the result',
			'realSr.previewTrimSplitPage' => 'This image is not trimmed · split double pages stay as-is',
			'realSr.previewTrimOff' => 'This image is not trimmed · auto-trim is off for this comic',
			'realSr.tileSizeHint' => 'Lower this if it crashes; “Auto” uses the model\'s recommended block size, and a model that declares a fixed input size takes precedence',
			'realSr.conditionN' => ({required Object index}) => 'Condition ${index}',
			'realSr.importItemFailed' => ({required Object index, required Object error}) => 'Failed to parse item ${index}: ${error}',
			'realSr.importSkipNotObject' => ({required Object index}) => 'Skipped item ${index}: entry is not an object',
			'realSr.defaultCondition' => 'Default condition',
			'realSr.engineDesktopNcnn' => 'Desktop NCNN (waifu2x / Real-CUGAN)',
			'realSr.engineNativeCoreML' => 'Rossi native CoreML',
			'realSr.modelFast' => 'Fast general (Real-ESR General 4x)',
			'realSr.modelPhoto' => 'Photo / CG (Real-ESRGAN 4x)',
			'realSr.modelAnime' => 'Illustration / anime (Real-ESRGAN Anime 6B 4x)',
			'realSr.modelComic' => 'Comic (Real-CUGAN 4x)',
			'realSr.modeDenoiseThenUpscale' => 'Denoise then upscale',
			'realSr.modeUpscaleOnly' => 'Upscale only',
			'realSr.modeDenoiseOnly' => 'JPEG denoise only',
			'realSr.modeOriginal' => 'Original',
			'realSr.deleteCondition' => 'Delete condition',
			'realSr.lowerPriority' => 'Lower priority',
			'realSr.raisePriority' => 'Raise priority',
			'realSr.addCondition' => 'Add condition',
			'realSr.openImageFolderHint' => 'Reveals the most recent upscaled image; opens the upscale cache folder when there is none yet.',
			'realSr.openImageFolder' => 'Open image folder',
			'realSr.viewUpscaleLog' => 'View upscale log',
			'realSr.upscaleLog' => 'Upscale log',
			'realSr.downloadNativeModel' => 'Download Rossi native model',
			'realSr.pagesBefore' => 'Pages before:',
			'realSr.pagesAfter' => 'Pages after:',
			'realSr.blockSizeLabel' => 'Block size:',
			'realSr.outputScaleLabel' => 'Output scale:',
			'realSr.imagePathRegex' => 'Image path regex (imagePathRegex)',
			'realSr.bookPathRegex' => 'Book path regex (bookPathRegex)',
			'realSr.matchAnyOr' => 'Any matches (OR)',
			'realSr.matchAllAnd' => 'All must match (AND)',
			'realSr.sizeMatchLogic' => 'Size match logic:',
			'realSr.maxPixelsMpx' => 'Max pixels (MPx)',
			'realSr.minPixelsMpx' => 'Min pixels (MPx)',
			'realSr.maxHeightPx' => 'Max height (px)',
			'realSr.minHeightPx' => 'Min height (px)',
			'realSr.maxWidthPx' => 'Max width (px)',
			'realSr.minWidthPx' => 'Min width (px)',
			'realSr.conditionName' => 'Condition name',
			'realSr.applyImport' => 'Apply import',
			'realSr.importConditions' => 'Import condition config',
			'realSr.copyToClipboard' => 'Copy to clipboard',
			'realSr.exportConditions' => 'Export condition config (JSON)',
			'realSr.resetConditionsContent' => 'Restore every condition to its factory default? Existing rules will be cleared.',
			'realSr.resetConditions' => 'Reset condition upscaling',
			'realSr.downloadInBrowser' => 'Download in browser',
			'realSr.importLocalOnnx' => 'Import local ONNX',
			'realSr.deleteCurrentModel' => 'Delete current model',
			'realSr.redownloadCurrentModel' => 'Re-download current model',
			'realSr.downloadCurrentModel' => 'Download current model',
			'realSr.customModel' => 'Custom upscale model',
			'realSr.onnxModel' => 'ONNX model',
			'realSr.exampleCollapsedHint' => 'Collapsed by default; the image loads once expanded',
			'realSr.exampleImageNotReady' => 'The current page image is not ready yet',
			'realSr.closeExample' => 'Close example',
			'realSr.removeModel' => 'Remove model',
			'realSr.noOutputYet' => 'not generated yet',
			'realSr.logWindowTitle' => 'Rossi upscale log (this run)',
			'realSr.logCategory' => 'Upscaling',
			'realSr.outputScaleSubtitle' => 'Actual scale settings for desktop NCNN models',
			'realSr.outputScale' => 'Output scale',
			'realSr.unnamedCondition' => 'Unnamed condition',
			'realSr.title' => 'Image Super-Resolution (Experimental)',
			'realSr.unlimited' => 'Unlimited',
			'realSr.modelDownloadFailed' => 'Model download failed',
			'realSr.generalSection' => 'General',
			'realSr.autoUpscaleSection' => 'Auto Upscale',
			'realSr.autoUpscale' => 'Auto Upscale',
			'realSr.autoUpscaleSubtitleUnavailable' => 'Model not downloaded; auto upscale will not work',
			'realSr.autoUpscaleSubtitleAvailable' => 'Automatically upscale when downloading or loading images',
			'realSr.conditionSection' => 'Condition',
			'realSr.resolutionThreshold' => 'Resolution Threshold',
			'realSr.resolutionThresholdSubtitle' => 'Only auto-upscale when image width is below this value',
			'realSr.performanceSection' => 'Performance',
			'realSr.concurrency' => 'Concurrency',
			'realSr.concurrencySubtitle' => 'Higher values suit high-end GPUs; mobile/low-end devices should keep it at 1',
			'realSr.tileSize' => 'Tile Size',
			'realSr.tileSizeSubtitle' => 'Set smaller if crashes occur; 0 means no tiling; desktop can try 0',
			'realSr.modelSection' => 'Model',
			'realSr.model' => 'Model',
			'realSr.modelSubtitle' => 'Switching model family resets variant options',
			'realSr.noiseLevel' => 'Denoise Level',
			'realSr.noiseLevelSubtitle' => 'This option varies with the selected model',
			'realSr.blockInfo' => 'Tile Info',
			'realSr.blockInfoTooltip' => 'blockSize is the model input size including reflection padding;\ncontent block = blockSize - 2×shrinkSize, which is the actual拼接 output region.',
			'realSr.blockInfoFormat' => ({required Object contentSize, required Object blockSize, required Object shrinkSize}) => 'Content block ${contentSize}×${contentSize}, model input ${blockSize}×${blockSize} (with ${shrinkSize}px reflection padding)',
			'realSr.androidSuperResolution' => 'Android Super-Resolution',
			'realSr.androidSuperResolutionSubtitle' => 'Currently uses waifu2x upconv anime model, 2x upscale',
			'realSr.androidEngine' => 'Upscale engine',
			'realSr.androidEngineSubtitle' => 'Choose the Android super-resolution backend',
			'realSr.androidEngineVulkan' => 'Vulkan (waifu2x CLI)',
			'realSr.androidEngineVulkanSubtitle' => 'ncnn + Vulkan GPU, works on all Android devices',
			'realSr.androidEngineQnnNpu' => 'NPU (Qualcomm QNN)',
			'realSr.androidEngineQnnNpuSubtitle' => 'Hexagon HTP NPU inference, Snapdragon 8 series only (experimental)',
			'realSr.androidEngineQnnExperimental' => 'The NPU backend is experimental: failures keep the original image and surface the reason; no silent fallback to Vulkan',
			'realSr.qnnModel' => 'NPU model',
			'realSr.qnnModelSubtitle' => 'Real-CUGAN FP16 model, 2x upscale',
			'realSr.qnnModelSeX2NoDenoise' => 'Real-CUGAN SE 2x (no denoise)',
			'realSr.qnnModelProX2Denoise3x' => 'Real-CUGAN Pro 2x (denoise level 3)',
			'realSr.qnnProbing' => 'Detecting NPU…',
			'realSr.qnnSupported' => ({required Object arch}) => 'Qualcomm HTP ${arch} detected, NPU available',
			'realSr.qnnSupportedSubtitle' => 'First use compiles the model context on device (~1-2 s) and caches it',
			'realSr.qnnUnsupported' => 'NPU unavailable on this device',
			'realSr.qnnUnsupportedSubtitle' => 'No supported Qualcomm HTP runtime detected (or this build ships without NPU support)',
			'realSr.qnnUnsupportedArchSubtitle' => ({required Object arch}) => 'HTP ${arch} detected, but this build does not bundle its runtime libraries',
			'realSr.qnnIdle' => 'Context not prepared',
			'realSr.qnnIdleSubtitle' => 'Download the model, then tap "Prepare" to compile the NPU context; reading also prepares it automatically',
			'realSr.qnnPreparing' => 'Compiling NPU context…',
			'realSr.qnnReady' => 'NPU context ready',
			'realSr.qnnFailed' => 'NPU context preparation failed',
			'realSr.qnnPrepare' => 'Prepare',
			'realSr.qnnRetry' => 'Retry',
			'realSr.missingQnnModel' => ({required Object file}) => 'Missing NPU model file ${file}',
			'realSr.missingQnnManifest' => 'Missing NPU model manifest.json',
			'realSr.desktopStrategy' => 'Upscale Strategy',
			'realSr.desktopStrategySubtitle' => 'Efficiency priority uses waifu2x; quality priority uses Real-CUGAN',
			'realSr.desktopNoiseLevel' => 'Denoise Level',
			'realSr.desktopNoiseLevelSubtitle' => 'Conservative suits normal comics; higher levels produce stronger smearing',
			'realSr.modelManagementSection' => 'Model Management',
			'realSr.downloadingModel' => 'Downloading model',
			'realSr.modelReady' => 'Model ready',
			'realSr.redownload' => 'Redownload',
			'realSr.deleteModel' => 'Delete Model',
			'realSr.deleteModelConfirm' => 'Delete the downloaded super-resolution model? You will need to download it again before use.',
			'realSr.modelDeleted' => 'Model deleted',
			'realSr.modelDeleteFailed' => 'Failed to delete model',
			'realSr.modelNotDownloaded' => 'Model not downloaded',
			'realSr.modelNotDownloadedSubtitle' => 'Download model before using super-resolution',
			'realSr.downloadModel' => 'Download Model',
			'realSr.manualDownload' => 'Manual model download',
			'realSr.manualDownloadUnsupported' => 'Manual model download is not supported on this platform',
			'realSr.openDownloadUrl' => 'Open URL',
			'realSr.openDownloadUrlFailed' => 'Failed to open URL',
			'realSr.importModel' => 'Import model archive',
			'realSr.importModelSubtitle' => 'Pick a manually downloaded 7z archive; the format and model content are validated before import',
			'realSr.importModelAction' => 'Pick file',
			'realSr.modelImportSuccess' => 'Model imported',
			'realSr.modelImportFailed' => 'Model import failed',
			'realSr.modeEfficiency' => 'Efficiency priority',
			'realSr.modeQuality' => 'Quality priority',
			'realSr.noiseConservative' => 'Conservative',
			'realSr.noise0' => 'No denoise',
			'realSr.noise1' => 'Denoise 1',
			'realSr.noise2' => 'Denoise 2',
			'realSr.noise3' => 'Denoise 3',
			'realSr.variantWaifu2xAnime' => 'waifu2x upconv anime',
			'realSr.variantRealCuganDenoise' => ({required Object noise}) => 'Real-CUGAN denoise ${noise}',
			'realSr.coremlSpeed' => 'Speed priority (waifu2x)',
			'realSr.coremlQuality' => 'Quality priority (Real-CUGAN)',
			'realSr.coremlNoise0' => 'Denoise 0',
			'realSr.coremlNoDenoise' => 'No denoise',
			'realSr.coremlInputHint' => 'Enter input image absolute path or asset path',
			'realSr.coremlStartUpscale' => 'Start upscale',
			'realSr.coremlStatusFillInput' => 'Please fill in the input image path',
			'realSr.coremlStatusNoModelFile' => 'No model files available for current family',
			'realSr.coremlStatusPreparing' => 'Preparing resources...',
			'realSr.coremlStatusUpscaling' => 'Upscaling...',
			'realSr.coremlStatusDone' => ({required Object outputPath, required Object size}) => 'Done\n${outputPath}\nsize: ${size} bytes',
			'realSr.coremlStatusFailed' => ({required Object error}) => 'Failed: ${error}',
			'realSr.coremlModelOption' => 'Model option (denoise level)',
			'realSr.coremlGeneralOption' => 'General option (scale)',
			'realSr.coremlTileInfo' => 'Tile info',
			'about.title' => 'About app',
			'about.version' => ({required Object version}) => 'Version: ${version}',
			'about.loading' => 'Loading...',
			'about.fetchFailed' => 'Failed to load',
			'about.networkError' => 'Network error',
			'about.tagline' => 'Cross-platform comic reader',
			'about.projectAddress' => 'Project',
			'about.projectAddressDesc' => 'Like this project? Give it a star on GitHub!',
			'about.projectLink' => 'Go to GitHub repo (HibernalGlow/rossi) ⭐',
			'about.feedback' => 'Feedback',
			'about.feedbackDesc' => 'Found a bug or have a new idea?',
			'about.feedbackLink' => 'Open a GitHub Issue',
			'about.upstream' => 'Upstream',
			'about.upstreamDesc' => 'Rossi continues development on top of Breeze. Thanks to the upstream author and community.',
			'about.upstreamLink' => 'Go to upstream repo (deretame/Breeze)',
			'about.licenseDesc' => 'This project is released under the Mozilla Public License 2.0.',
			'about.licenseLink' => 'Read the full license text',
			'about.contributors' => 'Contributors',
			'about.contributorsCount' => ({required Object count}) => '${count}',
			'about.contributionsTooltip' => ({required Object login, required Object count}) => '${login} (${count} commits)',
			'about.disclaimer' => 'Disclaimer',
			'about.disclaimerTitle' => 'Open Source Disclaimer',
			'about.disclaimerItem1Title' => '1. Nature and Statement',
			'about.disclaimerItem1Content' => 'This project is open-source software, developed and maintained jointly by community contributors. It is provided "as-is". The developer makes no express or implied warranties regarding functionality, stability, security, or fitness for purpose.',
			'about.disclaimerItem2Title' => '2. Limitation of Liability',
			'about.disclaimerItem2Content' => 'The developer shall not be liable for any direct, indirect, special, incidental, or consequential damages arising from use, modification, or distribution of this project (including but not limited to direct use, secondary development, or integration into other projects). These damages may include but are not limited to data loss, device damage, business interruption, lost profits, or other economic losses.',
			'about.disclaimerItem3Title' => '3. User Responsibility',
			'about.disclaimerItem3Content' => 'Users should evaluate suitability and assume all risks when using this project. Users must ensure their use complies with applicable laws, regulations, and ethical standards. The developer is not responsible for consequences resulting from violations of laws or misuse.',
			'about.disclaimerItem4Title' => '4. Third-Party Dependencies and Resources',
			'about.disclaimerItem4Content' => 'This project may depend on or reference third-party libraries, tools, services, or other resources. The developer is not responsible for the content, functionality, security, or legality of these third-party resources. Users should evaluate and assume risks themselves.',
			'about.disclaimerItem5Title' => '5. No Warranty',
			'about.disclaimerItem5Content' => 'The developer expressly disclaims all warranties, including but not limited to: merchantability; fitness for a particular purpose; non-infringement; and error-free or uninterrupted operation.',
			'about.disclaimerItem6Title' => '6. Modification and Termination',
			'about.disclaimerItem6Content' => 'The developer reserves the right to modify, suspend, or terminate this project at any time without prior notice. The developer is not responsible for any consequences arising from such changes.',
			'about.disclaimerItem7Title' => '7. Contributor Responsibility',
			'about.disclaimerItem7Content' => 'External contributors act in their personal capacity and do not represent the project maintainers\' views or positions. The maintainers are not responsible for contributor actions or content.',
			'about.disclaimerItem8Title' => '8. Legal Compliance',
			'about.disclaimerItem8Content' => 'Users must ensure their use complies with applicable laws and regulations. The developer is not responsible for consequences resulting from legal violations.',
			'about.disclaimerImportant' => 'Important Notice',
			'about.disclaimerImportantContent' => 'Please read and understand this disclaimer before using this project. If you do not agree with any term, stop using it immediately. Continued use constitutes acceptance of the entire disclaimer.',
			'about.checkUpdate' => 'Check update',
			'about.alreadyLatest' => 'Already latest version',
			'about.updateAvailable' => 'New version available',
			'about.license' => 'Open source licenses',
			'about.privacy' => 'Privacy policy',
			'oldHome.title' => 'Home',
			'oldHome.search' => 'Search',
			'oldHome.hotSearch' => 'Hot Search',
			'oldHome.navigation' => 'Navigation',
			'oldHome.recommend' => 'Recommend',
			'oldHome.latest' => 'Latest',
			'oldHome.cloudFavorite' => 'Cloud Favorites',
			'oldHome.list' => 'List',
			'oldHome.function' => 'Function',
			'oldHome.close' => 'Close',
			'oldHome.loadFailedRetry' => 'Load failed, please retry.',
			'oldHome.loadSectionFailed' => ({required Object title, required Object error}) => 'Failed to load ${title}\n${error}',
			'oldHome.empty' => 'No content',
			'oldHome.loadMoreFailed' => 'Failed to load more, tap to retry',
			'oldHome.loadMore' => 'Load more',
			'oldHome.noMore' => 'No more',
			'more.common' => 'Common',
			'more.others' => 'Others',
			'more.downloadTasks' => 'Download Tasks',
			'more.sync' => 'Sync',
			'more.comicFollow' => 'Updates',
			'more.changelog' => 'Changelog',
			'search.title' => 'Search',
			'search.searchHint' => 'Search...',
			'search.selectSource' => 'Select Source',
			'search.advancedSearchNotSupported' => 'Current plugin does not support advanced search',
			'search.advancedSearchOptions' => 'Advanced Search Options',
			'search.notSelected' => 'Not selected',
			'search.selectedCount' => ({required Object count}) => '${count} selected',
			'search.history' => 'Search History',
			'search.clearHistory' => 'Clear History',
			'search.newestFirst' => 'Current: newest first',
			'search.oldestFirst' => 'Current: oldest first',
			'search.descending' => 'Newest first',
			'search.ascending' => 'Oldest first',
			'search.noHistory' => 'No search history',
			'search.groupByPluginTooltipOn' => 'Grouped by plugin. Tap to merge into one timeline',
			'search.groupByPluginTooltipOff' => 'One merged timeline. Tap to group by plugin',
			'search.historyGroupAggregate' => 'Aggregate search',
			'search.historyGroupUncategorized' => 'Uncategorized',
			'search.tipsTitle' => '🔍 Search Tips',
			'search.exactSearchTitle' => 'Exact search (AND)',
			'search.exactSearchExample' => 'colorful + married',
			'search.exactSearchDesc' => 'Show results containing both keywords',
			'search.excludeSearchTitle' => 'Exclude search',
			'search.excludeSearchExample' => 'colorful - married',
			'search.excludeSearchDesc' => 'Show \'colorful\' results excluding \'married\'',
			'search.fuzzySearchTitle' => 'Fuzzy search (OR)',
			'search.fuzzySearchExample' => 'colorful married',
			'search.fuzzySearchDesc' => 'Show results containing any keyword',
			'search.selectCategory' => 'Select Category',
			'search.dataSource' => 'Data Source',
			'search.sortBy' => 'Sort By',
			'search.newestToOldest' => 'Newest to oldest',
			'search.oldestToNewest' => 'Oldest to newest',
			'search.mostLikes' => 'Most likes',
			'search.mostViews' => 'Most views',
			'search.selectSourceTooltip' => 'Select source',
			'search.hasResults' => 'With results',
			'search.showErrors' => 'Show errors',
			'search.resultCount' => ({required Object count}) => '${count} results',
			'search.noResults' => 'No results',
			'search.loadFailedForSource' => ({required Object source}) => 'Failed to load ${source}',
			'discover.title' => 'Discover',
			'discover.search' => 'Search',
			'discover.settings' => 'Settings',
			'discover.pluginManagement' => 'Plugin Management',
			'discover.customOrder' => 'Custom plugin order',
			'discover.resetOrder' => 'Reset order',
			'discover.noPlugins' => 'No plugins available. Go to the plugin store to install one~',
			'discover.pluginStore' => 'Plugin Store',
			'discover.browseInstall' => 'Browse & Install',
			'discover.noPluginForSearch' => 'No plugins available, cannot search',
			'discover.pluginInfoLoadFailed' => ({required Object error}) => 'Failed to load plugin info: ${error}',
			'discover.pluginCapability' => 'Plugin Capability',
			'discover.disabled' => 'Disabled',
			'discover.unnamed' => 'Unnamed',
			'discover.pluginEnableFailed' => ({required Object error}) => 'Failed to enable plugin: ${error}',
			'discover.pluginCloseFailed' => ({required Object error}) => 'Failed to disable plugin: ${error}',
			'discover.pluginDebugLoadFailed' => ({required Object error}) => 'Plugin debug load failed, reverted to database: ${error}',
			'discover.closeTab' => 'Close tab',
			'discover.tabDisplay' => 'Tab display',
			'discover.tabShowIcon' => 'Show plugin icon',
			'discover.tabShowPluginShort' => 'Show plugin short name',
			'discover.tabDoubleClickClose' => 'Double-click to close tab',
			'discover.tabCoverMode' => 'Cover tab mode',
			'discover.tabCoverModeDesc' => 'Display tabs as book covers with information overlay',
			'discover.webPage' => 'Web page',
			'discover.comicDetail' => 'Details',
			'searchResult.enterPageNumber' => 'Enter page number',
			'searchResult.pleaseEnterNumber' => 'Please enter a number',
			'searchResult.returnToTop' => 'Return to top',
			'searchResult.jumpToPage' => 'Jump to page',
			'searchResult.jump' => 'Jump',
			'searchResult.retry' => 'Tap to retry',
			'comicList.browseMenu' => 'Browse menu',
			_ => null,
		} ?? switch (path) {
			'comicList.currentPage' => ({required Object page}) => 'Page ${page}',
			'comicList.pageOfTotal' => ({required Object page, required Object total}) => 'Page ${page} of ${total}',
			'comicList.jumpToPage' => 'Jump to page',
			'comicList.pageInput' => 'Page number',
			'comicList.invalidPage' => 'Enter a positive whole number',
			'comicList.pageOutOfRange' => ({required Object total}) => 'Page cannot exceed ${total}',
			'comicList.restorePosition' => 'Restore last position',
			'comicList.restorePage' => ({required Object page}) => 'Last viewed page ${page}',
			'comicList.noSavedPosition' => 'No saved position yet',
			'comicList.positionSavedAutomatically' => 'Position is saved automatically after scrolling',
			'comicList.previousPage' => 'Previous page',
			'comicList.nextPage' => 'Next page',
			'comicList.chineseLocalized' => 'CN-localised',
			'comicList.downloadedAtLabel' => 'Downloaded at',
			'comicList.likedArtists' => 'Favourite artists',
			'comicList.likedTags' => 'Favourite tags',
			'comicList.defaultTitle' => 'Comic List',
			'comicList.missingSource' => 'Missing plugin source, cannot load list',
			'comicList.reload' => 'Reload',
			'comicList.loadFailedRetry' => 'Load failed, please retry.',
			'comicList.nothingHere' => 'Nothing here',
			'comicList.filter' => 'Filter',
			'comicList.subCategory' => 'Subcategory',
			'comicList.levelCategory' => ({required Object level}) => 'Level ${level}',
			'comicList.missingListConfig' => 'Missing list request configuration',
			'comicList.missingFnPath' => 'List request missing fnPath',
			'comicEntry.seenAtPage' => ({required Object page}) => 'Read up to page ${page}',
			'comicEntry.updatedAt' => ({required Object time}) => 'Updated: ${time}',
			'comicEntry.finished' => 'Finished',
			'comicEntry.ongoing' => 'Ongoing',
			'comicEntry.likes' => ({required Object count}) => 'Likes ${count}',
			'comicEntry.views' => ({required Object count}) => 'Views ${count}',
			'comicEntry.deleteFavorite' => 'Delete Favorite',
			'comicEntry.deleteFavoriteConfirm' => ({required Object title}) => 'Delete favorite record for "${title}"?',
			'comicEntry.deleteHistory' => 'Delete History',
			'comicEntry.deleteHistoryConfirm' => ({required Object title}) => 'Delete history record for "${title}"?',
			'comicEntry.deleteDownload' => 'Delete Download',
			'comicEntry.deleteDownloadConfirm' => ({required Object title}) => 'Delete download record and files for "${title}"?',
			'comicEntry.deleteFailed' => 'Delete failed',
			'comicEntry.translationBadgeTranslated' => 'Translated',
			'comicEntry.translationBadgeChinese' => 'Chinese',
			'comicEntry.translationBadgeRaw' => 'Raw',
			'comicEntry.unread' => 'Unread',
			'comicEntry.translationTooltipTag' => ({required Object label, required Object keyword}) => '${label} · matched tag "${keyword}"',
			'comicEntry.translationTooltipTitle' => ({required Object label, required Object keyword}) => '${label} · matched title "${keyword}"',
			'comicEntry.resumeRead' => 'Resume reading',
			'comicEntry.readFailed' => 'Could not start reading. Please try again later.',
			'comicFollow.title' => 'Updates',
			'comicFollow.loadFailed' => ({required Object result}) => 'Load failed: ${result}',
			'comicFollow.empty' => 'No followed comics',
			'comicFollow.emptyHint' => 'Tap the follow button on a comic detail page to add it here',
			'comicFollow.unfollow' => 'Unfollow',
			'comicFollow.unfollowConfirm' => ({required Object title}) => 'Stop following "${title}"?',
			'comicFollow.unfollowed' => 'Unfollowed',
			'comicFollow.all' => 'All',
			'comicFollow.unread' => 'Updated and unread',
			'comicFollow.sort' => 'Sort',
			'comicFollow.lastRead' => 'Last read',
			'comicFollow.lastUpdate' => 'Latest check',
			'comicFollow.checkTime' => ({required Object time}) => 'Check time: ${time}',
			'comicFollow.notRead' => 'Not read yet',
			'comicFollow.lastReadChapter' => ({required Object chapter}) => 'Read to: ${chapter}',
			'comicFollow.latestChapter' => ({required Object count, required Object chapter}) => 'Latest: ${count} / ${chapter}',
			'comicFollow.noUnread' => 'No updated unread comics',
			'comicFollow.showAll' => 'Show all',
			'comicFollow.latestChapterFailed' => 'Failed to get latest chapter',
			'comicFollow.newChapters' => ({required Object diff, required Object total}) => '${diff} new chapters, ${total} total',
			'comicFollow.newUnreadChapters' => ({required Object diff, required Object total}) => '${diff} new unread chapters, ${total} total',
			'comicFollow.latestCount' => ({required Object count}) => 'Latest ${count} chapters',
			'comicFollow.fetchFailed' => 'Fetch failed',
			'comicFollow.newChaptersShort' => ({required Object diff}) => '${diff} new',
			'comicFollow.newUnreadChaptersShort' => ({required Object diff}) => '${diff} unread',
			'comicFollow.update' => 'Update',
			'comicFollow.retry' => 'Retry',
			'comicFollow.readProgress' => ({required Object read, required Object total}) => '${read} of ${total} read',
			'comicFollow.readProgressUnknown' => ({required Object total}) => '${total} total',
			'comicFollow.updatedJustNow' => 'Just checked',
			'comicFollow.updatedMinutesAgo' => ({required Object minutes}) => 'Checked ${minutes} min ago',
			'comicFollow.updatedHoursAgo' => ({required Object hours}) => 'Checked ${hours} h ago',
			'comicFollow.updatedDaysAgo' => ({required Object days}) => 'Checked ${days} d ago',
			'comicFollow.lastReadMinutesAgo' => ({required Object minutes}) => 'Read ${minutes} min ago',
			'comicFollow.lastReadHoursAgo' => ({required Object hours}) => 'Read ${hours} h ago',
			'comicFollow.lastReadDaysAgo' => ({required Object days}) => 'Read ${days} d ago',
			'comicFollow.checkFailedTapRetry' => 'Check failed, tap to retry',
			'comicFollow.unreadCountBadge' => ({required Object count}) => '${count} unread',
			'comicFollow.markAllReadHint' => 'Mark all as read',
			'comicFollow.markAllReadDone' => 'All marked as read',
			'comicFollow.updateChannelName' => 'Comic update reminder',
			'comicFollow.updateChannelDesc' => 'Pushed when followed comics have new chapters',
			'comicFollow.updateTitle' => 'Follow update',
			'comicFollow.updatedComicsSingle' => '1 followed comic updated',
			'comicFollow.updatedComicsMultiple' => ({required Object count}) => '${count} followed comics updated',
			'comicFollow.updateBodyMultiple' => ({required Object count}) => '${count} followed comics have updates',
			'comicFollow.updateBodySingle' => '1 followed comic has updates',
			'changelog.title' => 'Changelog',
			'changelog.loadFailed' => 'Load failed',
			'changelog.loadFailedWithError' => ({required Object error}) => 'Load failed: ${error}',
			'changelog.cannotOpenLink' => ({required Object url}) => 'Cannot open link: ${url}',
			'changelog.checkNetwork' => 'Load failed, please check network',
			'changelog.retry' => 'Retry',
			'changelog.empty' => 'No changelog',
			'changelog.publishedAt' => ({required Object date}) => 'Published at ${date}',
			'changelog.viewInBrowser' => 'View in browser',
			'changelog.attachments' => 'Attachments',
			'webview.title' => 'Webpage',
			'webview.cannotOpenLink' => ({required Object uri}) => 'Cannot open link: ${uri}',
			'webview.invalidLink' => 'Invalid link, cannot open webpage',
			'webview.emptyLink' => '(empty link)',
			'webview.loadFailed' => 'Webpage load failed',
			'webview.retry' => 'Retry',
			'webview.openInExternalBrowser' => 'Open in external browser',
			'webview.windowClosed' => 'WebView window closed',
			'webview.openedInExternalWindow' => 'Webpage opened in external window',
			'webview.back' => 'Back',
			'webview.closeWindow' => 'Close WebView window',
			'webview.loadError' => ({required Object error}) => 'Load failed (${error})',
			'webview.httpErrorStatus' => ({required Object statusCode}) => 'Server returned abnormal status code: ${statusCode}',
			'oldRanking.bikaRanking' => 'Bika Ranking',
			'oldRanking.jmRanking' => 'JM Ranking',
			'oldRanking.switchSource' => 'Switch',
			'login.title' => 'Login',
			'login.missingPluginId' => 'Missing plugin identifier, cannot open login page',
			'login.loadConfigFailed' => ({required Object error}) => 'Failed to load login config: ${error}',
			'login.insufficientFields' => 'Plugin returned insufficient login fields',
			'login.invalidCredentials' => 'Invalid username or password, please try again',
			'login.configNotReady' => 'Login config not ready, please retry later',
			'login.loggingIn' => 'Logging in, please wait...',
			'login.loginSuccess' => 'Login successful',
			'login.loginFailed' => 'Login failed',
			'login.loginButton' => 'Login',
			'login.retry' => 'Retry',
			'login.requiredFieldEmpty' => ({required Object label}) => 'Please fill in ${label}',
			'login.loginNotSupported' => 'This plugin doesn\'t support the new login page yet. Please fill in your account in plugin settings.',
			'login.captchaTapToRefresh' => 'Can\'t see? Tap to refresh',
			'login.captchaLoading' => 'Loading captcha...',
			'login.captchaLoadFailed' => 'Failed to load captcha, tap to retry',
			'fontSetting.title' => 'Font Settings',
			'fontSetting.clear' => 'Clear',
			'fontSetting.hint' => 'Pick one default font to apply everywhere; override individual weights only when needed.',
			'fontSetting.modeSystem' => 'System default',
			'fontSetting.modeSystemHint' => 'Use the app\'s default font stack — no setup needed.',
			'fontSetting.modeFamily' => 'Installed font',
			'fontSetting.modeFamilyHint' => 'Reference a font already installed in the system by family name (e.g. LXGW WenKai); falls back to system default if not found. Most reliable on desktop.',
			'fontSetting.modeFile' => 'Font file',
			'fontSetting.modeFileHint' => 'One file for the whole app; bolder weights are synthesized by the system.',
			'fontSetting.familyPickPrompt' => 'Pick a font family',
			'fontSetting.familyPickerTitle' => 'Choose a system font',
			'fontSetting.familySearchHint' => 'Search font families…',
			'fontSetting.familyManualUse' => ({required Object name}) => 'Use "${name}"',
			'fontSetting.familyEmpty' => 'No matching fonts',
			'fontSetting.familyLoading' => 'Reading system fonts…',
			'fontSetting.defaultFont' => 'Default font',
			'fontSetting.defaultFontHint' => 'One file for the whole app; bolder weights are synthesized by the system.',
			'fontSetting.overrides' => 'Weight overrides',
			'fontSetting.overridesHint' => 'Optional: assign different files to specific weights; uncovered weights fall back to the nearest configured one.',
			'fontSetting.loadFailed' => 'Font load failed',
			'fontSetting.cleared' => 'Cleared',
			'fontSetting.saved' => 'Saved',
			'fontSetting.allCleared' => 'All cleared',
			'fontSetting.noFileSelected' => 'No file selected',
			'fontSetting.clearFile' => 'Clear',
			'fontSetting.selectFile' => 'Select File',
			'fontSetting.sampleText' => 'Innovation in China 中国智造，慧及全球 0123456789',
			'download.title' => 'Download tasks',
			'download.startDownload' => 'Start Download',
			'download.selectChaptersPrompt' => 'Please select chapters to download',
			'download.selectedCount' => ({required Object selected, required Object total}) => '${selected} / ${total} chapters selected',
			'download.downloadedCount' => ({required Object count}) => '${count} chapters already downloaded',
			'download.skipDownloaded' => 'Skip downloaded',
			'download.skippedAlreadyDownloaded' => ({required Object count}) => 'Skipped ${count} chapters already downloaded',
			'download.startedWithSkipped' => ({required Object started, required Object skipped}) => 'Started ${started} chapters, skipped ${skipped} already downloaded',
			'download.optionsTitle' => 'Download this comic',
			'download.optionWholeBook' => 'Whole book',
			'download.optionWholeBookCounted' => ({required Object count}) => 'All ${count} chapters',
			'download.optionWholeBookPlain' => 'Every chapter',
			'download.optionLatest' => ({required Object count}) => 'Latest ${count} chapters',
			'download.optionLatestSubtitle' => 'The newest chapters by chapter order',
			'download.optionPicker' => 'Pick chapters',
			'download.optionPickerPlain' => 'Tick chapters one by one',
			'download.optionSkipHint' => 'Whole book and latest-N skip chapters already on disk',
			'download.filterAll' => 'All',
			'download.filterNoMatches' => 'No tasks match this filter',
			'download.overviewRemaining' => ({required Object count}) => '${count} chapters left',
			'download.overviewPages' => ({required Object done, required Object total}) => '${done}/${total} pages done',
			'download.overviewFailed' => ({required Object count}) => '${count} failed',
			'download.comicScopeAll' => 'All comics',
			'download.comicScopeCounted' => ({required Object name, required Object count}) => '${name} (${count})',
			'download.taskStarted' => 'Download task started',
			'download.taskStartFailed' => ({required Object error}) => 'Failed to start download task: ${error}',
			'download.noTasks' => 'No download tasks',
			'download.downloading' => 'Downloading',
			'download.pending' => ({required Object count}) => 'Pending (${count})',
			'download.failedTasks' => ({required Object count}) => 'Failed (${count})',
			'download.pausedTasks' => ({required Object count}) => 'Paused (${count})',
			'download.pinTask' => 'Prioritize',
			'download.unpinTask' => 'Remove priority',
			'download.taskPinned' => 'Moved to the front of the queue',
			'download.taskUnpinned' => 'Priority removed',
			'download.taskDeleted' => 'Task deleted',
			'download.deleteLastChapterContent' => 'Deleting this chapter will also delete the download record. Continue?',
			'download.cancelTask' => 'Cancel Task',
			'download.cancelTaskConfirm' => ({required Object comicName}) => 'Cancel download of ${comicName}?',
			'download.paused' => 'Paused',
			'download.completed' => 'Completed',
			'download.failed' => 'Failed',
			'download.startAll' => 'Start all',
			'download.pauseAll' => 'Pause all',
			'download.cancelAll' => 'Cancel all',
			'download.cancelAllConfirm' => ({required Object count}) => 'Cancel all ${count} download tasks? Their downloaded chapter images will be deleted too.',
			'download.clearCompleted' => 'Clear completed',
			'download.viewModeCompact' => 'Compact view',
			'download.viewModeComfortable' => 'Full view',
			'download.statusFetchingComicInfo' => 'Fetching comic info...',
			'download.statusDownloadingCover' => 'Downloading cover...',
			'download.statusFetchingChapterInfo' => 'Fetching chapter info...',
			'download.statusFetchingChapterInfoProgress' => ({required Object completed, required Object total, required Object percent}) => 'Fetching chapter info... (${completed}/${total}, ${percent}%)',
			'download.statusDownloadProgress' => ({required Object percent}) => 'Current chapter download progress: ${percent}%',
			'download.statusDownloadProgressComplete' => 'Current chapter download progress: 100%',
			'download.progressPages' => ({required Object completed, required Object total}) => 'Downloaded ${completed}/${total} pages',
			'download.progressPagesWithSpeed' => ({required Object completed, required Object total, required Object speed}) => 'Downloaded ${completed}/${total} pages · ${speed}',
			'download.parallelTaskProgress' => ({required Object count, required Object message}) => '${count} tasks downloading · ${message}',
			'download.settingsTitle' => 'Download settings',
			'download.settingsValueSummary' => ({required Object chapters, required Object images, required Object delayMs}) => '${chapters} chapters · ${images} images each · ${delayMs} ms apart',
			'download.settingsBudgetHint' => ({required Object count}) => 'Up to ${count} images download at once (chapters at once × images per chapter)',
			'download.offlineTitle' => 'Offline comics',
			'download.offlineEmpty' => 'Nothing downloaded yet',
			'download.offlineMeasureSize' => 'Measure size',
			'download.offlineMeasuring' => 'Measuring…',
			'download.offlineTotalSize' => ({required Object size}) => '${size} total',
			'download.offlineChapterCount' => ({required Object completed, required Object total}) => '${completed}/${total} chapters downloaded',
			'download.offlineChapterCountOnly' => ({required Object count}) => '${count} chapters downloaded',
			'download.statusComicProgress' => ({required Object completedChapters, required Object totalChapters, required Object currentChapterCompletedImages, required Object currentChapterTotalImages}) => 'Comic progress: ${completedChapters}/${totalChapters} chapters, current chapter: ${currentChapterCompletedImages}/${currentChapterTotalImages} pages',
			'download.statusComicProgressChaptersOnly' => ({required Object completedChapters, required Object totalChapters}) => 'Comic progress: ${completedChapters}/${totalChapters} chapters',
			'download.statusStartDownload' => 'Start downloading...',
			'download.statusWaiting' => 'Waiting',
			'download.statusCancelling' => 'Cancelling...',
			'download.statusAutoRetrying' => ({required Object seconds, required Object attempt, required Object max}) => 'Network error, retrying automatically in ${seconds} s (${attempt}/${max})...',
			'download.statusThrottling' => 'Rate limited by source, cooling down...',
			'download.retryFailedParts' => 'Retry Failed',
			'download.toastDownloadComplete' => ({required Object comicName}) => '${comicName} download complete',
			'download.toastDownloadFailed' => ({required Object comicName, required Object error}) => '${comicName} download failed ${error}',
			'download.toastTaskAlreadyExists' => ({required Object comicName}) => '${comicName} task already exists',
			'download.notificationCompleteTitle' => 'Download complete',
			'download.notificationFailedTitle' => 'Download failed',
			'foregroundTask.channelName' => 'Foreground task',
			'foregroundTask.channelDescription' => 'Keeps downloads and the app running in the background',
			'foregroundTask.waitingForTask' => 'Waiting for download tasks...',
			'foregroundTask.keepAliveRunning' => 'Keeping the app running in the background',
			'foregroundTask.cancel' => 'Cancel',
			'foregroundTask.notificationPermissionRequired' => 'Notification permission is required to start the foreground task, please allow in the system dialog',
			'foregroundTask.cannotStartWithoutPermission' => 'Cannot start foreground task: please enable notification permission in system settings',
			'foregroundTask.startFailed' => ({required Object error}) => 'Foreground service start failed: ${error}',
			'notification.permissionRequired' => 'Please enable notification permission',
			'notification.macPermissionRequired' => 'Please enable notification permission in system settings',
			'update.newVersion' => 'New version available',
			'update.goToGitHub' => 'Go to GitHub',
			'update.downloadInstall' => 'Download & install',
			'update.apkDownloadFailed' => 'Download failed, please try again later',
			'update.installPermissionRequired' => 'Please grant install app permission',
			'update.unknownArch' => 'Unknown',
			'dialog.hideOrClose' => 'Hide to tray or close app',
			'dialog.rememberChoice' => 'Remember my choice',
			'shelfMenu.open' => 'Open',
			'shelfMenu.resumeReading' => 'Resume reading',
			'shelfMenu.openInFileManagerTab' => 'Open in a new file manager tab',
			'shelfMenu.copyTitle' => 'Copy title',
			'shelfMenu.copyLink' => 'Copy link',
			'shelfMenu.addFavorite' => 'Add to favorites',
			'shelfMenu.alreadyFavorite' => 'Already in favorites',
			'shelfMenu.removeFavorite' => 'Remove from favorites',
			'shelfMenu.removeHistory' => 'Remove from history',
			'shelfMenu.copiedTitle' => ({required Object title}) => 'Copied title “${title}”',
			'shelfMenu.copiedLink' => ({required Object link}) => 'Copied link “${link}”',
			'shelfMenu.fileManagerTabOpened' => 'Opened in a new file manager tab',
			'shelfMenu.fileManagerTabUnavailable' => 'The file manager panel is not ready yet, try again in a moment',
			'shelfMenu.fileManagerTabNoLocalPath' => 'This comic has no local folder, so it cannot be opened in the file manager',
			'shelfMenu.favoriteAdded' => ({required Object title}) => 'Added “${title}” to favorites',
			'shelfMenu.favoriteRemoved' => ({required Object title}) => 'Removed “${title}” from favorites',
			'shelfMenu.historyRemoved' => ({required Object title}) => 'Removed “${title}” from history',
			'shelfMenu.removeFavoriteConfirmTitle' => 'Remove from favorites?',
			'shelfMenu.removeFavoriteConfirmBody' => ({required Object title}) => '“${title}” will be removed from your favorites. The files and the reading history are untouched.',
			'shelfMenu.removeHistoryConfirmTitle' => 'Remove from history?',
			'shelfMenu.removeHistoryConfirmBody' => ({required Object title}) => '“${title}” will be removed from your reading history. The files will not be deleted.',
			'video.play' => 'Play',
			'video.pause' => 'Pause',
			'video.backward' => 'Back 10 s',
			'video.forward' => 'Forward 10 s',
			'video.loop' => 'Loop: next page',
			'video.loopSingle' => 'Loop: repeat page',
			'video.loopOff' => 'Loop: off',
			'video.speed' => 'Speed',
			'video.volume' => 'Volume',
			'video.muted' => 'Muted',
			'video.subtitles' => 'Subtitles',
			'video.subtitleOff' => 'No subtitles',
			'video.audio' => 'Audio track',
			'video.audioOff' => 'Mute track',
			'video.filters' => 'Filters',
			'video.resetFilters' => 'Reset filters',
			'video.brightness' => 'Brightness',
			'video.contrast' => 'Contrast',
			'video.saturation' => 'Saturation',
			'video.abLoop' => 'A-B loop',
			'video.abClear' => 'Clear A-B',
			'video.screenshot' => 'Screenshot',
			'video.audioOnly' => 'Audio only',
			'video.seekMode' => 'Seek mode (page turns seek)',
			'video.fullscreen' => 'Fullscreen',
			'video.pin' => 'Pin controls',
			'video.info' => 'Info',
			'video.frameStepForward' => 'Next frame',
			'video.frameStepBackward' => 'Previous frame',
			'video.pip' => 'Picture in picture',
			'video.settingsSection' => 'Video playback',
			'video.autoPlay' => 'Auto play',
			'video.autoPlayDesc' => 'Start playing when a video page is reached',
			'video.hwDecode' => 'Hardware decoding',
			'video.hwDecodeDesc' => 'Turn off to work around green/torn frames, at the cost of CPU',
			'video.deinterlace' => 'Deinterlace',
			'video.deinterlaceDesc' => 'Enable for interlaced DVD / tape sources with combing',
			'video.integrateBottomBar' => 'Integrate video controls into bottom bar',
			'video.integrateBottomBarDesc' => 'Show playback progress and video controls inside the reader bottom bar',
			'video.pinDesc' => 'Keep the control bar visible instead of hiding it after a few seconds',
			'video.animatedVideo' => 'Play animated images as video',
			'video.animatedVideoDesc' => 'Hand GIF / APNG to the video controller for pause, frame stepping and scrubbing',
			'video.autoHide' => 'Auto-hide controls',
			'video.maxRate' => 'Max playback rate',
			'video.defaultVolume' => 'Default volume',
			'video.aliases' => 'Custom video extensions',
			'video.aliasesEmpty' => 'None',
			'video.aliasesHint' => 'Comma separated, e.g. myvid, cbr-video',
			'video.aliasesDialogHint' => 'Lowercase, at most 128 entries, at most 16 characters each',
			'video.mediaSection' => 'Media formats',
			'video.imageFormats' => 'Image format table',
			'video.videoFormats' => 'Video format table',
			'video.formatsHint' => 'Filling this replaces the built-in table, so suffixes you leave out stop counting as pages at all; leave it empty to keep the defaults',
			'video.subSize' => 'Font size',
			'video.subBg' => 'Background',
			'video.subBottom' => 'Bottom offset',
			'video.subLargeYellow' => 'Large yellow',
			'video.reset' => 'Reset',
			'video.duration' => 'Duration',
			'video.position' => 'Position',
			'video.size' => 'Size',
			'video.dar' => 'Display aspect',
			'video.fps' => 'Frame rate',
			'video.bitrate' => 'Bitrate',
			'video.videoCodec' => 'Video codec',
			'video.audioCodec' => 'Audio codec',
			'video.avDrift' => 'A/V drift',
			'video.loopMode' => 'Loop',
			'video.playbackRate' => 'Rate',
			'video.abRange' => 'A-B',
			'video.sidecarSubtitles' => 'External subtitles',
			'video.notAvailable' => '—',
			'video.noBytes' => 'No bytes available for this video page',
			'video.cannotPlay' => 'This page cannot be played',
			'video.animatedKeywords' => 'Motion keywords',
			'video.animatedKeywordsHint' => 'Comma separated, e.g. [#dyna], [#motion]',
			'video.rotation' => 'Rotation',
			'bindingEditor.anyArea' => 'Any area',
			'bindingEditor.migrationFailed' => 'The old bindings could not be migrated. Your original configuration is preserved. Export it for inspection or import a valid configuration.',
			'bindingEditor.groupNavigation' => 'Pages',
			'bindingEditor.groupView' => 'View',
			'bindingEditor.groupInterface' => 'Interface',
			'bindingEditor.videoPlayback' => 'Playback',
			'bindingEditor.videoAudio' => 'Audio',
			'bindingEditor.videoDisplay' => 'Picture & subtitles',
			'bindingEditor.allActions' => 'All',
			'bindingEditor.boundOnly' => 'Assigned',
			'bindingEditor.unassigned' => 'Unassigned',
			'bindingEditor.spaceKey' => 'Space',
			'bindingEditor.searchAll' => 'Search all actions or keys',
			'bindingEditor.disabled' => 'Disabled',
			'bindingEditor.moreBindings' => ({required Object count}) => '${count} more bindings',
			'bindingEditor.search' => 'Search actions, categories, contexts or inputs',
			'bindingEditor.allCategories' => 'All categories',
			'bindingEditor.allContexts' => 'All contexts',
			'bindingEditor.noResults' => 'No matching actions',
			'bindingEditor.addBinding' => 'Add binding',
			'bindingEditor.noBindings' => 'No bindings. Add an input to get started.',
			'bindingEditor.device' => 'Input device',
			'bindingEditor.context' => 'Context',
			'bindingEditor.ignoreRepeat' => 'Ignore repeated input',
			'bindingEditor.followUps' => 'Follow-up actions',
			'bindingEditor.add' => 'Add',
			'bindingEditor.copyTo' => 'Copy to',
			'bindingEditor.conflict' => 'Binding conflict',
			'bindingEditor.conflictHint' => 'An input is repeated in the same context. Change or disable one binding to resume autosave.',
			'bindingEditor.saved' => 'Saved automatically',
			'bindingEditor.pending' => 'Waiting to save',
			'bindingEditor.invalid' => 'Not saved. Check the input settings.',
			'bindingEditor.record' => 'Record',
			'bindingEditor.recordHint' => 'Use this area, then confirm the captured input. Escape cancels; use the cancel button to bind Escape manually.',
			'bindingEditor.recordWaiting' => 'Waiting for input…',
			'bindingEditor.keyCode' => 'Keyboard code',
			'bindingEditor.trigger' => 'Trigger',
			'bindingEditor.down' => 'Key down',
			'bindingEditor.hold' => 'Hold',
			'bindingEditor.instant' => 'On release',
			'bindingEditor.click' => 'Click',
			'bindingEditor.doubleClick' => 'Double click',
			'bindingEditor.press' => 'Press',
			'bindingEditor.duration' => 'Hold duration (ms)',
			'bindingEditor.tolerance' => 'Movement tolerance (px)',
			'bindingEditor.button' => 'Mouse button',
			'bindingEditor.leftButton' => 'Left button',
			'bindingEditor.middleButton' => 'Middle button',
			'bindingEditor.rightButton' => 'Right button',
			'bindingEditor.backButton' => 'Back button',
			'bindingEditor.forwardButton' => 'Forward button',
			'bindingEditor.up' => 'Up',
			'bindingEditor.downDirection' => 'Down',
			'bindingEditor.left' => 'Left',
			'bindingEditor.right' => 'Right',
			'bindingEditor.swipeLeft' => 'Swipe left',
			'bindingEditor.swipeRight' => 'Swipe right',
			'bindingEditor.swipeUp' => 'Swipe up',
			'bindingEditor.swipeDown' => 'Swipe down',
			'bindingEditor.tap' => 'Tap',
			'bindingEditor.longPress' => 'Long press',
			'bindingEditor.fingers' => 'Fingers',
			'bindingEditor.gesture' => 'Touch gesture',
			'bindingEditor.directions' => 'Gesture direction sequence',
			'bindingEditor.undoDirection' => 'Remove last direction',
			'bindingEditor.gamepadButton' => 'Gamepad button number',
			'bindingEditor.gamepadHint' => 'Gamepad bindings can be edited and transferred; gamepad events are not connected on this platform yet.',
			'bindingEditor.managedInput' => 'This input is managed by its radial menu or system command',
			'bindingEditor.area' => 'View area',
			'bindingEditor.topLeft' => 'Top left',
			'bindingEditor.topCenter' => 'Top center',
			'bindingEditor.topRight' => 'Top right',
			'bindingEditor.middleLeft' => 'Middle left',
			'bindingEditor.middleCenter' => 'Center',
			'bindingEditor.middleRight' => 'Middle right',
			'bindingEditor.bottomLeft' => 'Bottom left',
			'bindingEditor.bottomCenter' => 'Bottom center',
			'bindingEditor.bottomRight' => 'Bottom right',
			'bindingEditor.keyboard' => 'Keyboard',
			'bindingEditor.mouse' => 'Mouse',
			'bindingEditor.mouseGesture' => 'Mouse gesture',
			'bindingEditor.wheel' => 'Wheel',
			'bindingEditor.touch' => 'Touch',
			'bindingEditor.gamepad' => 'Gamepad',
			'bindingEditor.radial' => 'Radial',
			'bindingEditor.command' => 'Command',
			'bindingEditor.global' => 'Global',
			'bindingEditor.reader' => 'Reader',
			'bindingEditor.video' => 'Video',
			'bindingEditor.panel' => 'Panel',
			'bindingEditor.shell' => 'Shell',
			'bindingEditor.editor' => 'Editor',
			'bindingEditor.modal' => 'Dialog',
			'bindingEditor.moveUp' => 'Move up',
			'bindingEditor.moveDown' => 'Move down',
			'bindingEditor.collapse' => 'Collapse binding',
			'bindingEditor.expand' => 'Expand binding',
			'bindingEditor.actions' => 'Actions',
			'bindingEditor.actionList' => 'Actions',
			'bindingEditor.bindingDetails' => 'Bindings',
			'bindingEditor.bindings' => 'Bindings',
			'bindingEditor.restore' => 'Restore defaults',
			'bindingEditor.resetFilters' => 'Clear filters',
			'plat.openAbove' => 'Open above',
			'plat.openBelow' => 'Open below',
			'plat.openLeft' => 'Open left',
			'plat.openRight' => 'Open right',
			'plat.closeTab' => 'Close tab',
			_ => null,
		};
	}
}
