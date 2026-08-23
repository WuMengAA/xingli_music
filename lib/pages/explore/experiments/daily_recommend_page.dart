import 'package:flutter/material.dart';

import '../../../providers/sources/netease_provider.dart';
import '../../../widgets/sources/netease_track_list_page.dart';

/// 网易云 · 每日推荐（需登录）。
///
/// 薄壳：真实逻辑（tile / 三态 / 登录引导 / 登录失效引导）统一在
/// [NeteaseTrackListPage]，本页只提供标题、provider 与文案差异。
class DailyRecommendPage extends StatelessWidget {
  const DailyRecommendPage({super.key});

  @override
  Widget build(BuildContext context) => NeteaseTrackListPage(
        title: '每日推荐',
        firstProvider: neteaseDailyRecommendProvider,
        showReason: true,
        emptyTitle: '暂无可推荐曲目',
        emptyMessage: '稍后回来，网易云会为你更新每日推荐',
        loginHintTitle: '每日推荐需要登录网易云',
        loginHintMessage: '登录后为你推送每日精选曲目',
      );
}
