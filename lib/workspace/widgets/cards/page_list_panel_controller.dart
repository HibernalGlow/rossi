import 'package:material_ui/material_ui.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/service/reader/reader_session_coordinator.dart';
import 'package:zephyr/workspace/widgets/library_view/editorial/library_editorial_canvas.dart';

enum PageListViewMode { thumbnails, details, list }

/// 页面导航面板三组件（搜索栏 / 中间展示栏 / 底部跳转栏）共享的状态控制器。
///
/// 将搜索过滤词、跟随阅读进度开关、视图模式与展墙画布 Key 从单个卡片状态中解耦出来，
/// 使三个小组件可以自由重排、独立折叠或隐藏，同时保持跨组件联动。
class PageListPanelController extends ChangeNotifier {
  PageListPanelController() {
    searchController.addListener(_onSearchTextChanged);
  }

  static final PageListPanelController instance = PageListPanelController();

  final TextEditingController searchController = TextEditingController();
  final TextEditingController jumpPageController = TextEditingController();
  final GlobalKey<LibraryEditorialCanvasState> canvasKey =
      GlobalKey<LibraryEditorialCanvasState>();

  PageListViewMode _viewMode = PageListViewMode.thumbnails;
  PageListViewMode get viewMode => _viewMode;

  bool _followProgress = true;
  bool get followProgress => _followProgress;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool _pageEditorial = false;
  bool get pageEditorial => _pageEditorial;

  /// 每次需要让中间展示栏重新居中到当前页时递增。
  int _followSignal = 0;
  int get followSignal => _followSignal;

  bool _forceFollow = false;
  bool get forceFollow => _forceFollow;

  void _onSearchTextChanged() {
    final query = searchController.text.trim().toLowerCase();
    if (_searchQuery != query) {
      _searchQuery = query;
      notifyListeners();
    }
  }

  void toggleFollowProgress() {
    _followProgress = !_followProgress;
    if (_followProgress) {
      requestFollow(force: true);
    } else {
      notifyListeners();
    }
  }

  void cycleViewMode() {
    canvasKey.currentState?.showLegacyView();
    switch (_viewMode) {
      case PageListViewMode.thumbnails:
        _viewMode = PageListViewMode.details;
        break;
      case PageListViewMode.details:
        _viewMode = PageListViewMode.list;
        break;
      case PageListViewMode.list:
        _viewMode = PageListViewMode.thumbnails;
        break;
    }
    requestFollow(force: true);
  }

  void setPageEditorial(bool value) {
    _pageEditorial = value;
    requestFollow(force: true);
  }

  void requestFollow({bool force = false}) {
    _followSignal++;
    _forceFollow = force;
    notifyListeners();
  }

  Glyph get viewModeIcon {
    switch (_viewMode) {
      case PageListViewMode.thumbnails:
        return AppGlyphs.dashboard;
      case PageListViewMode.details:
        return AppGlyphs.viewAgenda;
      case PageListViewMode.list:
        return AppGlyphs.layoutList;
    }
  }

  String get viewModeLabel {
    switch (_viewMode) {
      case PageListViewMode.thumbnails:
        return '缩略图';
      case PageListViewMode.details:
        return '详细';
      case PageListViewMode.list:
        return '列表';
    }
  }

  void jumpToPageInput([BuildContext? context]) {
    final text = jumpPageController.text.trim();
    final pageNumber = int.tryParse(text);
    final coordinator = ReaderSessionCoordinator.instance;
    if (pageNumber != null &&
        pageNumber >= 1 &&
        pageNumber <= coordinator.totalSlots) {
      coordinator.jumpTo(pageNumber - 1);
      if (context != null) {
        FocusScope.of(context).unfocus();
      }
    }
  }

  /// 重置控制器状态（供测试环境复位）。
  void reset() {
    searchController.clear();
    jumpPageController.clear();
    _viewMode = PageListViewMode.thumbnails;
    _followProgress = true;
    _searchQuery = '';
    _pageEditorial = false;
    _followSignal = 0;
    _forceFollow = false;
    notifyListeners();
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchTextChanged);
    searchController.dispose();
    jumpPageController.dispose();
    super.dispose();
  }
}
