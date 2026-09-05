/// ════════════════════════════════════════════════════════════════════════
/// 应用外壳导航状态
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据底部导航重构（主页 / 曲库 / 世界 / 探索 / 校园电台 / 设置，共 6 Tab）：
/// `IndexedStack` 有 5 个子页面、Dock 也有 5 个 Tab；**唯一真源是
/// [shellPageIndexProvider]**，Tab 高亮由其派生。
///
/// ```
/// selectedTabIndex = isTab(shellPageIndex) ? shellPageIndex : null
/// ```
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';


/// Shell 页面索引常量（对应 `IndexedStack.children` 顺序）。
///
/// | index | 页面           | Dock          |
/// |-------|----------------|---------------|
/// | 0     | `HomePage`     | Tab 0（默认） |
/// | 1     | `LibraryPage`  | Tab 1         |
/// | 2     | `WorldPage`    | Tab 2         |
/// | 3     | `ExplorePage`  | Tab 3         |
/// | 4     | `VoiceHubPage` | Tab 4（校园电台 · 点歌）|
/// | 5     | `SettingsPage` | Tab 5         |
abstract final class ShellPage {
  /// 主页 —— Tab 0，冷启动默认页（合并原场景页内容）。
  static const int home = 0;

  /// 曲库页 —— Tab 1。
  static const int library = 1;

  /// 世界页（星璃世界入口）—— Tab 2。
  static const int world = 2;

  /// 探索页 —— Tab 3。
  static const int explore = 3;

  /// VoiceHub 校园电台（点歌）—— Tab 4，内嵌的一级功能入口。
  static const int voicehub = 4;

  /// 设置页 —— Tab 5。
  static const int settings = 5;

  /// `IndexedStack` 子页面总数。
  static const int count = 6;

  /// Dock Tab 数量（重构后：主页 / 曲库 / 世界 / 探索 / 校园电台 / 设置，共 6 个）。
  static const int tabCount = 6;

  /// 该页面索引是否对应一个 Dock Tab。
  static bool isTab(int index) => index >= 0 && index < tabCount;
}

/// 当前展示的页面索引（0..4），驱动 `IndexedStack.index`。
///
/// **唯一真源**。冷启动默认为「场景」（P0-B7）。
final StateProvider<int> shellPageIndexProvider =
    StateProvider<int>((Ref ref) => ShellPage.home);

/// 当前高亮的 Dock Tab（0..4）；处于非 Tab 页时为 `null`。
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
