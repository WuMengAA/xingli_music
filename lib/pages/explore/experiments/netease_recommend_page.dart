import 'package:flutter/material.dart';

import '../../../providers/sources/netease_provider.dart';
import '../../../widgets/sources/netease_track_list_page.dart';
import '../../../core/theme/app_theme_colors.dart';

/// 网易云 · 推荐（每日推荐 + 私人漫游 合并入口）。
///
/// 两者原为「探索页实验区」的独立入口，功能高度重叠（均为网易云推荐流，
/// 一个是固定每日推荐，一个是个性化无限漫游），故合并为单页，页内用
/// `SegmentedButton` 切换。底层复用 [NeteaseTrackListPage]，切换段时用不同
/// `key` 强制重建 State（[NeteaseTrackListPage] 的 `_loaded` 列表与 `_loadingMore`
/// 状态需按 segment 复位，不能跨段共享）。
class NeteaseRecommendPage extends StatefulWidget {
  const NeteaseRecommendPage({super.key});

  @override
  State<NeteaseRecommendPage> createState() => _NeteaseRecommendPageState();
}

class _NeteaseRecommendPageState extends State<NeteaseRecommendPage> {
  /// 0 = 每日推荐；1 = 私人漫游。
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Scaffold(
      backgroundColor: c.bgPage,
      appBar: AppBar(
        title: const Text('网易云推荐'),
        backgroundColor: c.bgPage,
        foregroundColor: c.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  label: Text('每日推荐'),
                  icon: Icon(Icons.today_rounded),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('私人漫游'),
                  icon: Icon(Icons.explore_outlined),
                ),
              ],
              selected: <int>{_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
          Expanded(
            // 用 key 区分段：切换时整个子页 State 重建，_loaded 列表复位。
            child: _segment == 0
                ? NeteaseTrackListPage(
                    key: const ValueKey<int>(0),
                    title: '每日推荐',
                    firstProvider: neteaseDailyRecommendProvider,
                    showReason: true,
                    emptyTitle: '暂无可推荐曲目',
                    emptyMessage: '稍后回来，网易云会为你更新每日推荐',
                    loginHintTitle: '每日推荐需要登录网易云',
                    loginHintMessage: '登录后为你推送每日精选曲目',
                  )
                : NeteaseTrackListPage(
                    key: const ValueKey<int>(1),
                    title: '私人漫游',
                    firstProvider: neteaseRoamProvider,
                    infinite: true,
                    showReason: false,
                    emptyTitle: '暂无漫游推荐',
                    emptyMessage: '漫游随你试听偏好实时更新',
                    loginHintTitle: '私人漫游需要登录网易云',
                    loginHintMessage: '登录后为你开启个性化无限推荐流',
                  ),
          ),
        ],
      ),
    );
  }
}
