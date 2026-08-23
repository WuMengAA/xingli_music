import 'package:flutter/material.dart';

import '../../../providers/sources/netease_provider.dart';
import '../../../widgets/sources/netease_track_list_page.dart';

/// 网易云 · 私人漫游（需登录，无限推荐流）。
///
/// 薄壳：真实逻辑（tile / 三态 / 登录引导 / 无限流自动加载）统一在
/// [NeteaseTrackListPage]，本页只提供标题、provider 与文案差异。
class RoamPage extends StatelessWidget {
  const RoamPage({super.key});

  @override
  Widget build(BuildContext context) => NeteaseTrackListPage(
        title: '漫游',
        firstProvider: neteaseRoamProvider,
        infinite: true,
        emptyTitle: '暂无可漫游曲目',
        emptyMessage: '稍后回来，网易云会为你更新漫游流',
        loginHintTitle: '漫游需要登录网易云',
        loginHintMessage: '登录后开启个性化无限推荐流',
      );
}
