/// ════════════════════════════════════════════════════════════════════════
/// 应用外壳导航状态
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据 `docs/PRD_UI_重构.md` §5.2「Tab 索引与页面索引的映射」：
/// Dock 只有 4 个 Tab，但 `IndexedStack` 有 5 个子页面，因此需要两个状态，
/// 且**唯一真源是 [shellPageIndexProvider]**，Tab 高亮由其派生。
///
/// ```
/// selectedTabIndex = (shellPageIndex <= 3) ? shellPageIndex : null
/// ```
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';


/// Shell 页面索引常量（对应 `IndexedStack.children` 顺序）。
///
/// | index | 页面           | Dock          |
/// |-------|----------------|---------------|
/// | 0     | `ScenePage`    | Tab 0（默认） |
/// | 1     | `ExplorePage`  | Tab 1         |
/// | 2     | `LibraryPage`  | Tab 2         |
/// | 3     | `SettingsPage` | Tab 3         |
/// | 4     | `HomePage`     | 无 Tab 高亮   |
abstract final class ShellPage {
  /// 场景页 —— Tab 0，冷启动默认页（P0-B7）。
  static const int scene = 0;

  /// 探索页 —— Tab 1。
  static const int explore = 1;

  /// 曲库页 —— Tab 2。
  static const int library = 2;

  /// 设置页 —— Tab 3。
  static const int settings = 3;

  /// 首页 —— 隐藏页，无 Tab 高亮（P0-B8 / B9 / G5）。
  static const int home = 4;

  /// `IndexedStack` 子页面总数。
  static const int count = 5;

  /// Dock Tab 数量（P0-B2：有且仅有 4 个）。
  static const int tabCount = 4;

  /// 该页面索引是否对应一个 Dock Tab。
  static bool isTab(int index) => index >= 0 && index < tabCount;
}

/// 当前展示的页面索引（0..4），驱动 `IndexedStack.index`。
///
/// **唯一真源**。冷启动默认为「场景」（P0-B7）。
final StateProvider<int> shellPageIndexProvider =
    StateProvider<int>((Ref ref) => ShellPage.scene);

/// 当前高亮的 Dock Tab（0..3）；处于首页（index 4）时为 `null`。
///
/// 派生自 [shellPageIndexProvider]，**不可单独赋值**，避免双真源不同步。
final Provider<int?> selectedTabIndexProvider = Provider<int?>((Ref ref) {
  final int page = ref.watch(shellPageIndexProvider);
  return ShellPage.isTab(page) ? page : null;
});

/// 各页搜索关键词（按页面索引隔离）。
///
/// P0-C3 / P1-02：搜索栏搜的是**当前页的东西**——曲库页过滤曲目、
/// 设置页过滤设置项，因此按 `pageIndex` 分槽存储，切 Tab 不互相污染。
final StateProviderFamily<String, int> searchQueryProvider =
    StateProvider.family<String, int>((Ref ref, int pageIndex) => '');

/// 切换 Shell 页面的统一入口。
///
/// 集中在此可以保证「切页」这一动作只有一个写入点，便于后续加埋点 / 转场。
void setShellPage(WidgetRef ref, int pageIndex) {
  if (pageIndex < 0 || pageIndex >= ShellPage.count) return;
  final StateController<int> controller =
      ref.read(shellPageIndexProvider.notifier);
  if (controller.state == pageIndex) return;
  controller.state = pageIndex;
}
