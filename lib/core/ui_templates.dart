/// ════════════════════════════════════════════════════════════════════════
/// UI 模板库 —— 把现有优质界面「拆解、理解」成可复用模板
/// ════════════════════════════════════════════════════════════════════════
///
/// 模板 = 「起步素材」：每个模板带
///   1. `toNodes()` —— 可编辑节点树（进编辑器自由改，实时预览）
///   2. `build()`   —— 实时预览 Widget（画廊 / 编辑器画布直接渲染）
///   3. 分类 / 标签 / 描述 —— 便于检索
///
/// 模板来源（全部从本项目现有界面拆解，非凭空设计）：
///   · 页面级：星璃世界主菜单、设置页 Master-Detail、场景页工具条、
///             全局通知 toast、状态页（载入/错误/空）、网易云登录 sheet
///   · 区块级：顶栏 chips、折叠面板、动作键区、设置项列表、卡片网格、HUD 信息条
///   · 控件级：玻璃圆钮、大动作键、菜单按钮、发光入口钮、开关行、滑块行
///
/// 设计 tokens 全部走既有体系：AppThemeColors（语义色）/ AppRadius /
/// AppSpace / AppTextStyles / DesignTokens —— 模板自动适配明暗主题。
library;

import 'package:flutter/material.dart';
import '../widgets/notification/app_notify.dart';

import 'theme/app_theme_colors.dart';
import 'theme/design_tokens.dart';
import 'theme/light_tokens.dart';
import 'ui_editor_model.dart';

/// 模板分类。
enum UiTemplateCategory {
  page('页面级 · 整页骨架'),
  block('区块级 · 页面片段'),
  control('控件级 · 原子组件'),
  ;

  const UiTemplateCategory(this.label);
  final String label;
}

/// 一个可复用 UI 模板。
class UiTemplate {
  const UiTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.tags = const <String>[],
    required this.nodes,
    required this.build,
  });

  final String id;
  final String name;
  final UiTemplateCategory category;
  final String description;
  final List<String> tags;

  /// 编辑器起步节点树。
  final List<UiNode> Function() nodes;

  /// 画廊实时预览 Widget。
  final Widget Function(BuildContext) build;
}

// ─────────────────────────────────────────────────────────────────────────
// 公开控件（复刻现有私有控件 · 走设计 tokens）
// ─────────────────────────────────────────────────────────────────────────

/// 玻璃圆钮（voxel _GlassCircleButton 公开版）。
class UiGlassButton extends StatelessWidget {
  const UiGlassButton({super.key, required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final Color ink = context.appColors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x59000000),
          border: Border.all(color: const Color(0x40FFFFFF)),
        ),
        child: Icon(icon, size: 20, color: ink),
      ),
    );
  }
}

/// 大动作键（voxel _BigActionButton 公开版）。
class UiActionButton extends StatelessWidget {
  const UiActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: const Color(0x30FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: context.appColors.textPrimary),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: context.appColors.textPrimary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主菜单按钮（voxel_main_menu _MenuButton 公开版）。
class UiMenuButton extends StatelessWidget {
  const UiMenuButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool trailing;
  @override
  Widget build(BuildContext context) {
    final Color ink = context.appColors.textPrimary;
    final Color accent = context.appColors.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 13,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: const Color(0x2EFFFFFF)),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: ink),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(label, style: AppTextStyles.body.copyWith(color: ink)),
                ),
                if (trailing) Icon(Icons.chevron_right, size: 18, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 发光入口按钮（scene _GlowEntryButton 公开版）。
class UiGlowEntryButton extends StatelessWidget {
  const UiGlowEntryButton({super.key, required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[accent.withValues(alpha: 0.85), accent.withValues(alpha: 0.35)],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.5),
              blurRadius: 18,
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0B1220), size: 24),
      ),
    );
  }
}

/// 图标按钮（场景工具条 _SceneIconButton 公开版）。
class UiIconButton extends StatelessWidget {
  const UiIconButton({super.key, required this.icon, this.label, this.onTap});
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: label == null ? 44 : null,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: const Color(0x18FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: context.appColors.textPrimary),
            if (label != null) ...<Widget>[
              const SizedBox(width: 6),
              Text(label!, style: AppTextStyles.caption.copyWith(color: context.appColors.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 开关行（设置项 toggle 行）。
class UiToggleRow extends StatelessWidget {
  const UiToggleRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value = false,
    this.onChanged,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
      decoration: BoxDecoration(
        color: context.appColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.body.copyWith(color: context.appColors.textPrimary)),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTextStyles.caption.copyWith(color: context.appColors.textSecondary)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.appColors.accent,
          ),
        ],
      ),
    );
  }
}

/// 滑块行（设置项 slider 行）。
class UiSliderRow extends StatelessWidget {
  const UiSliderRow({
    super.key,
    required this.title,
    this.value = 0.6,
    this.onChanged,
  });
  final String title;
  final double value;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title, style: AppTextStyles.body.copyWith(color: context.appColors.textPrimary)),
          ),
          SizedBox(
            width: 160,
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
              activeColor: context.appColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// chips 行（设置项单选）。
class UiChipRow extends StatelessWidget {
  const UiChipRow({super.key, required this.title, this.options = const <String>['A', 'B', 'C']});
  final String title;
  final List<String> options;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
      decoration: BoxDecoration(
        color: context.appColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: AppTextStyles.body.copyWith(color: context.appColors.textPrimary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options
                .map((String o) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.appColors.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: context.appColors.accent.withValues(alpha: 0.5)),
                      ),
                      child: Text(o, style: AppTextStyles.caption.copyWith(color: context.appColors.textPrimary)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// 顶栏 chips 组（voxel 顶栏公开版）。
class UiTopBar extends StatelessWidget {
  const UiTopBar({super.key, this.items = const <IconData>[Icons.menu, Icons.visibility, Icons.photo_camera, Icons.save, Icons.pause, Icons.settings]});
  final List<IconData> items;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((IconData i) => UiGlassButton(icon: i)).toList(),
    );
  }
}

/// 折叠面板（voxel _FoldPanel 公开版）。
class UiFoldPanel extends StatelessWidget {
  const UiFoldPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final Color ink = context.appColors.textPrimary;
    Widget row(IconData icon, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: 6),
              Text(label, style: AppTextStyles.caption.copyWith(color: ink)),
              const Spacer(),
              Switch(
                value: true,
                onChanged: null,
                activeThumbColor: context.appColors.accent,
              ),
            ],
          ),
        );
    return Container(
      width: 210,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF3A3055), Color(0xFF151D2E)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          row(Icons.pin, '显示坐标'),
          row(Icons.self_improvement, '自动跳跃'),
          row(Icons.visibility_off, 'HUD 折叠'),
          row(Icons.graphic_eq, '沉浸模式'),
        ],
      ),
    );
  }
}

/// 动作键区（攻击/放置/蹲/跳）。
class UiActionPad extends StatelessWidget {
  const UiActionPad({super.key});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const <Widget>[
        UiActionButton(icon: Icons.sports_martial_arts, label: '攻击'),
        SizedBox(width: 10),
        UiActionButton(icon: Icons.add_box_rounded, label: '放置'),
        SizedBox(width: 10),
        UiActionButton(icon: Icons.vertical_align_bottom, label: '蹲'),
        SizedBox(width: 10),
        UiActionButton(icon: Icons.arrow_upward_rounded, label: '跳'),
      ],
    );
  }
}

/// 设置项列表（entry / toggle / slider / chips 混合）。
class UiSettingsList extends StatelessWidget {
  const UiSettingsList({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        UiToggleRow(title: '后台播放', subtitle: '退出应用后继续播放', value: true),
        const SizedBox(height: 8),
        UiSliderRow(title: '主音量', value: 0.6),
        const SizedBox(height: 8),
        const UiChipRow(title: '播放引擎', options: <String>['media_kit', 'exo', '系统']),
        const SizedBox(height: 8),
        UiMenuButton(icon: Icons.audio_file_outlined, label: '音源管理', trailing: true),
      ],
    );
  }
}

/// 卡片网格（AlbumCard 网格）。
class UiCardGrid extends StatelessWidget {
  const UiCardGrid({super.key, this.count = 6});
  final int count;
  @override
  Widget build(BuildContext context) {
    final Color card = context.appColors.bgCard;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: count,
      itemBuilder: (BuildContext c, int i) => Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: DesignTokens.accent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.album_outlined, color: context.appColors.textTertiary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '示例卡片 $i',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: context.appColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// HUD 信息条（voxel _WorldInfoBar 公开版）。
class UiInfoBar extends StatelessWidget {
  const UiInfoBar({super.key, this.text = '坐标 64, 32, 64 · 生存 · 白天'});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.place_outlined, size: 13, color: context.appColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: context.appColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// 全局通知 toast（右上角 ≤1/3 宽）。
class UiToast extends StatelessWidget {
  const UiToast({super.key, this.message = '已保存', this.title = '通知'});
  final String message;
  final String title;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width / 3),
        margin: const EdgeInsets.only(top: 60, right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.appColors.bgSurfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.appColors.border),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle, size: 16, color: context.appColors.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(color: context.appColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 星璃世界主菜单（深色渐变 + 中央菜单卡）。
class UiMainMenu extends StatelessWidget {
  const UiMainMenu({super.key});
  @override
  Widget build(BuildContext context) {
    const Color ink = Color(0xFFF2F5FA);
    final Color accent = context.appColors.accent;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF2A2440), Color(0xFF151D2E)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: const Color(0x40FFFFFF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.view_in_ar_rounded, size: 22, color: ink),
              const SizedBox(width: 8),
              Text('星璃世界', style: AppTextStyles.title.copyWith(color: ink)),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          UiMenuButton(
            icon: Icons.folder_open_outlined,
            label: '世界存档',
            trailing: false,
            onTap: () => appNotify(context, '进入存档管理器'),
          ),
          UiMenuButton(
            icon: Icons.public_outlined,
            label: '开放世界',
            trailing: false,
            onTap: () => appNotify(context, '开放世界开发中'),
          ),
          UiMenuButton(
            icon: Icons.settings_outlined,
            label: '游戏设置',
            trailing: false,
            onTap: () => appNotify(context, '进入设置'),
          ),
          const SizedBox(height: 4),
          Text(
            '样本 · 实际按钮已接跳转',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: const Color(0x88F2F5FA)),
          ),
        ],
      ),
    );
  }
}

/// 状态页（载入 / 错误 / 空）。
class UiStatePage extends StatelessWidget {
  const UiStatePage({super.key, this.mode = 'empty'});
  final String mode;
  @override
  Widget build(BuildContext context) {
    final (IconData, String, String) m = switch (mode) {
      'loading' => (Icons.hourglass_top_rounded, '加载中', '正在载入内容…'),
      'error' => (Icons.error_outline_rounded, '出错了', '请检查网络后重试'),
      _ => (Icons.inbox_outlined, '空空如也', '这里还没有内容'),
    };
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(m.$1, size: 52, color: context.appColors.textTertiary),
          const SizedBox(height: 12),
          Text(m.$2, style: AppTextStyles.title.copyWith(color: context.appColors.textPrimary)),
          const SizedBox(height: 6),
          Text(m.$3, style: AppTextStyles.body.copyWith(color: context.appColors.textSecondary)),
          const SizedBox(height: 16),
          UiMenuButton(icon: Icons.refresh_rounded, label: '重试', trailing: false),
        ],
      ),
    );
  }
}

/// 网易云登录 sheet（QR + cookie 双输入）。
class UiLoginSheet extends StatelessWidget {
  const UiLoginSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final Color card = context.appColors.bgCard;
    Widget field(String label, String hint) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: AppTextStyles.caption.copyWith(color: context.appColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.appColors.border),
              ),
              child: Text(hint, style: AppTextStyles.body.copyWith(color: context.appColors.textTertiary)),
            ),
          ],
        );
    return Container(
      width: 320,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.qr_code_2_rounded, color: context.appColors.accent),
              const SizedBox(width: 8),
              Text('登录网易云音乐', style: AppTextStyles.title.copyWith(color: context.appColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.appColors.border),
              ),
              child: Icon(Icons.qr_code_rounded, size: 72, color: context.appColors.textTertiary),
            ),
          ),
          const SizedBox(height: 14),
          field('MUSIC_U', '粘贴 MUSIC_U 值'),
          const SizedBox(height: 10),
          field('__csrf（可选）', '粘贴 __csrf 值'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  context.appColors.accent,
                  Color.lerp(context.appColors.accent, Colors.black, 0.25)!,
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              '登录',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: context.appColors.onAccent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 节点树生成器（编辑器起步素材）
// ─────────────────────────────────────────────────────────────────────────

List<UiNode> _mainMenuNodes() => <UiNode>[
      UiNode.container(
        'mm_card',
        '主菜单卡',
        gradientStart: '#2A2440',
        gradientEnd: '#151D2E',
        gradientDirection: 'diagonal',
        radius: 36,
        padding: 18,
        gap: 5,
        width: 300,
        children: <UiNode>[
          UiNode.container(
            'mm_title_row',
            '标题行',
            layout: UiLayout.horizontal,
            align: UiAlign.center,
            gap: 8,
            children: <UiNode>[
              UiNode.iconNode('mm_icon', 'Logo', 'e145', color: '#F2F5FA', size: 22),
              UiNode.txt('mm_title', '标题', '星璃世界', size: 18, weight: '700', color: '#F2F5FA'),
            ],
          ),
          UiNode.spacer('mm_sp1', '间距', height: 18),
          UiNode.button('mm_btn1', '按钮', '世界存档', icon: 'e2c7', accent: '#9B7BFF'),
          UiNode.button('mm_btn2', '按钮', '开放世界', icon: 'e80b', accent: '#9B7BFF'),
          UiNode.button('mm_btn3', '按钮', '游戏设置', icon: 'e8b8', accent: '#9B7BFF'),
        ],
      ),
    ];

List<UiNode> _settingsListNodes() => <UiNode>[
      UiNode.container(
        'sl_root',
        '设置项列表',
        gradientStart: '#1E1E2C',
        gradientEnd: '#12121A',
        radius: 18,
        padding: 0,
        gap: 8,
        width: 320,
        children: <UiNode>[
          UiNode.container(
            'sl_toggle',
            '开关行',
            layout: UiLayout.horizontal,
            align: UiAlign.spaceBetween,
            color: '#262634',
            radius: 18,
            padding: 12,
            children: <UiNode>[
              UiNode.txt('sl_toggle_t', '标题', '后台播放', color: '#F2F2F7'),
              UiNode.iconNode('sl_toggle_i', '开关', 'e8e0', color: '#9B7BFF'),
            ],
          ),
          UiNode.container(
            'sl_slider',
            '滑块行',
            layout: UiLayout.horizontal,
            align: UiAlign.spaceBetween,
            color: '#262634',
            radius: 18,
            padding: 10,
            children: <UiNode>[
              UiNode.txt('sl_slider_t', '标题', '主音量', color: '#F2F2F7'),
              UiNode.txt('sl_slider_v', '值', '60%', color: '#B8B8C8', size: 12),
            ],
          ),
          UiNode.container(
            'sl_chips',
            'chips 行',
            color: '#262634',
            radius: 18,
            padding: 12,
            gap: 6,
            children: <UiNode>[
              UiNode.txt('sl_chips_t', '标题', '播放引擎', color: '#F2F2F7'),
              UiNode.container(
                'sl_chips_row',
                'chips',
                layout: UiLayout.horizontal,
                gap: 6,
                children: <UiNode>[
                  UiNode.button('sl_chip1', 'chip', 'media_kit', accent: '#9B7BFF'),
                  UiNode.button('sl_chip2', 'chip', 'exo', accent: '#3A3A4A'),
                ],
              ),
            ],
          ),
        ],
      ),
    ];

List<UiNode> _actionPadNodes() => <UiNode>[
      UiNode.container(
        'ap_row',
        '动作键区',
        layout: UiLayout.horizontal,
        gap: 10,
        children: <UiNode>[
          UiNode.button('ap_attack', '攻击', '攻击', icon: 'e8e8', accent: '#C0392B'),
          UiNode.button('ap_place', '放置', '放置', icon: 'e147', accent: '#9B7BFF'),
          UiNode.button('ap_sneak', '蹲', '蹲', icon: 'e5d2', accent: '#2E86C1'),
          UiNode.button('ap_jump', '跳', '跳', icon: 'e5d8', accent: '#27AE60'),
        ],
      ),
    ];

List<UiNode> _topBarNodes() => <UiNode>[
      UiNode.container(
        'tb_row',
        '顶栏 chips',
        layout: UiLayout.horizontal,
        gap: 6,
        children: <UiNode>[
          UiNode.button('tb_1', 'chips', '', icon: 'e5d2', accent: '#59000000'),
          UiNode.button('tb_2', 'chips', '', icon: 'e8f4', accent: '#59000000'),
          UiNode.button('tb_3', 'chips', '', icon: 'e251', accent: '#59000000'),
          UiNode.button('tb_4', 'chips', '', icon: 'e161', accent: '#59000000'),
        ],
      ),
    ];

List<UiNode> _foldPanelNodes() => <UiNode>[
      UiNode.container(
        'fp_card',
        '折叠面板',
        gradientStart: '#3A3055',
        gradientEnd: '#151D2E',
        radius: 36,
        padding: 14,
        gap: 6,
        width: 210,
        children: <UiNode>[
          _rowNode('fp_r1', '显示坐标', 'e80e'),
          _rowNode('fp_r2', '自动跳跃', 'e05e'),
          _rowNode('fp_r3', 'HUD 折叠', 'e8f4'),
          _rowNode('fp_r4', '沉浸模式', 'e242'),
        ],
      ),
    ];

UiNode _rowNode(String id, String label, String icon) => UiNode.container(
      id,
      label,
      layout: UiLayout.horizontal,
      align: UiAlign.spaceBetween,
      gap: 6,
      children: <UiNode>[
        UiNode.iconNode('${id}_i', '图标', icon, color: '#F2F2F7', size: 16),
        UiNode.txt('${id}_t', '文本', label, color: '#F2F2F7', size: 12),
        UiNode.iconNode('${id}_sw', '开关', 'e8e0', color: '#9B7BFF', size: 18),
      ],
    );

List<UiNode> _cardGridNodes() => <UiNode>[
      UiNode.container(
        'cg_root',
        '卡片网格',
        layout: UiLayout.wrap,
        gap: 10,
        width: 320,
        children: <UiNode>[
          _cardNode('cg_1', '示例卡片 1'),
          _cardNode('cg_2', '示例卡片 2'),
          _cardNode('cg_3', '示例卡片 3'),
        ],
      ),
    ];

UiNode _cardNode(String id, String name) => UiNode.container(
      id,
      name,
      color: '#262634',
      radius: 24,
      padding: 8,
      gap: 6,
      width: 100,
      height: 128,
      children: <UiNode>[
        UiNode.container(
          '${id}_img',
          '封面',
          color: '#4A3F78',
          radius: 18,
          height: 72,
          children: <UiNode>[
            UiNode.iconNode('${id}_ic', '图标', 'e145', color: '#8A8A9C', size: 24),
          ],
        ),
        UiNode.txt('${id}_t', '名称', name, color: '#F2F2F7', size: 11),
      ],
    );

List<UiNode> _toastNodes() => <UiNode>[
      UiNode.container(
        'toast',
        '通知 toast',
        layout: UiLayout.horizontal,
        align: UiAlign.min,
        color: '#262634',
        radius: 18,
        padding: 10,
        gap: 6,
        children: <UiNode>[
          UiNode.iconNode('toast_ic', '图标', 'e86c', color: '#9B7BFF', size: 16),
          UiNode.txt('toast_t', '消息', '已保存', color: '#F2F2F7', size: 12),
        ],
      ),
    ];

List<UiNode> _loginSheetNodes() => <UiNode>[
      UiNode.container(
        'ls_card',
        '登录 sheet',
        color: '#1C1C26',
        radius: 36,
        padding: 18,
        gap: 10,
        width: 320,
        children: <UiNode>[
          UiNode.container(
            'ls_title',
            '标题行',
            layout: UiLayout.horizontal,
            gap: 8,
            children: <UiNode>[
              UiNode.iconNode('ls_ic', '二维码', 'e896', color: '#9B7BFF', size: 22),
              UiNode.txt('ls_t', '标题', '登录网易云音乐', size: 16, weight: '600', color: '#F2F2F7'),
            ],
          ),
          UiNode.container(
            'ls_qr',
            '二维码',
            color: '#262634',
            radius: 18,
            height: 120,
            children: <UiNode>[
              UiNode.iconNode('ls_qr_ic', '码', 'e7c4', color: '#8A8A9C', size: 64),
            ],
          ),
          UiNode.container(
            'ls_f1',
            '输入框',
            color: '#262634',
            radius: 18,
            padding: 10,
            children: <UiNode>[UiNode.txt('ls_f1_t', '占位', 'MUSIC_U', color: '#8A8A9C', size: 13)],
          ),
          UiNode.container(
            'ls_f2',
            '输入框',
            color: '#262634',
            radius: 18,
            padding: 10,
            children: <UiNode>[UiNode.txt('ls_f2_t', '占位', '__csrf（可选）', color: '#8A8A9C', size: 13)],
          ),
          UiNode.button('ls_login', '登录', '登录',
              gradientStart: '#9B7BFF', gradientEnd: '#7B5BFF'),
        ],
      ),
    ];

List<UiNode> _infoBarNodes() => <UiNode>[
      UiNode.container(
        'ib',
        '信息条',
        layout: UiLayout.horizontal,
        color: '#66000000',
        radius: 999,
        padding: 6,
        gap: 5,
        children: <UiNode>[
          UiNode.iconNode('ib_ic', '坐标', 'e567', color: '#B8B8C8', size: 13),
          UiNode.txt('ib_t', '文本', '坐标 64, 32, 64 · 生存 · 白天', color: '#B8B8C8', size: 11),
        ],
      ),
    ];

List<UiNode> _glassButtonNodes() => <UiNode>[
      UiNode.button('gb', '玻璃圆钮', '', icon: 'e5d2', accent: '#59000000', color: '#59000000'),
    ];

List<UiNode> _menuButtonNodes() => <UiNode>[
      UiNode.button('mb', '菜单按钮', '世界存档', icon: 'e2c7', accent: '#9B7BFF', color: '#9B7BFF'),
    ];

List<UiNode> _glowEntryNodes() => <UiNode>[
      UiNode.button('ge', '发光入口钮', '', icon: 'e80b', accent: '#9B7BFF', color: '#9B7BFF'),
    ];

List<UiNode> _toggleRowNodes() => <UiNode>[
      UiNode.container(
        'tr',
        '开关行',
        layout: UiLayout.horizontal,
        align: UiAlign.spaceBetween,
        color: '#262634',
        radius: 18,
        padding: 12,
        children: <UiNode>[
          UiNode.txt('tr_t', '标题', '后台播放', color: '#F2F2F7'),
          UiNode.iconNode('tr_sw', '开关', 'e8e0', color: '#9B7BFF', size: 20),
        ],
      ),
    ];

List<UiNode> _sliderRowNodes() => <UiNode>[
      UiNode.container(
        'sr',
        '滑块行',
        layout: UiLayout.horizontal,
        align: UiAlign.spaceBetween,
        color: '#262634',
        radius: 18,
        padding: 10,
        children: <UiNode>[
          UiNode.txt('sr_t', '标题', '主音量', color: '#F2F2F7'),
          UiNode.txt('sr_v', '值', '60%', color: '#B8B8C8', size: 12),
        ],
      ),
    ];

List<UiNode> _statePageNodes() => <UiNode>[
      UiNode.container(
        'st',
        '状态页',
        align: UiAlign.center,
        gap: 6,
        width: 240,
        padding: 24,
        children: <UiNode>[
          UiNode.iconNode('st_ic', '图标', 'e036', color: '#8A8A9C', size: 52),
          UiNode.txt('st_t', '标题', '空空如也', size: 18, weight: '700', color: '#F2F2F7'),
          UiNode.txt('st_d', '描述', '这里还没有内容', color: '#B8B8C8', size: 14),
          UiNode.button('st_btn', '重试', '重试', icon: 'e042', accent: '#9B7BFF'),
        ],
      ),
    ];

List<UiNode> _sceneToolbarNodes() => <UiNode>[
      UiNode.container(
        'sc',
        '场景工具条',
        layout: UiLayout.horizontal,
        gap: 10,
        children: <UiNode>[
          UiNode.button('sc_glow', '发光入口', '', icon: 'e80b', accent: '#9B7BFF', color: '#9B7BFF'),
          UiNode.button('sc_1', '图标钮', '拍照取景', icon: 'e251', accent: '#1FFFFFFF'),
          UiNode.button('sc_2', '图标钮', '场景音效', icon: 'e050', accent: '#1FFFFFFF'),
        ],
      ),
    ];

// ─────────────────────────────────────────────────────────────────────────
// 模板注册表
// ─────────────────────────────────────────────────────────────────────────

/// 全部内置 UI 模板（画廊 / 编辑器资产面板共用）。
final List<UiTemplate> kUiTemplates = <UiTemplate>[
  // ── 页面级 ──────────────────────────────────────────
  UiTemplate(
    id: 'tpl_main_menu',
    name: '星璃世界主菜单',
    category: UiTemplateCategory.page,
    description: '深色渐变底 + 玻璃菜单卡（世界存档 / 开放世界 / 游戏设置）。拆自 voxel_main_menu_page。',
    tags: <String>['菜单', '深色', '玻璃'],
    nodes: _mainMenuNodes,
    build: (BuildContext c) => UiMainMenu(),
  ),
  UiTemplate(
    id: 'tpl_settings_list',
    name: '设置项列表',
    category: UiTemplateCategory.page,
    description: '开关行 + 滑块行 + chips 行混合列表。拆自 settings 各 Detail 的通用行模式。',
    tags: <String>['设置', '列表', '表单'],
    nodes: _settingsListNodes,
    build: (BuildContext c) => UiSettingsList(),
  ),
  UiTemplate(
    id: 'tpl_scene_toolbar',
    name: '场景页工具条',
    category: UiTemplateCategory.page,
    description: '发光入口按钮 + 图标按钮组。拆自 scene_page 顶部工具条。',
    tags: <String>['工具条', '发光', '图标'],
    nodes: _sceneToolbarNodes,
    build: (BuildContext c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            UiGlowEntryButton(icon: Icons.auto_awesome_rounded),
            SizedBox(width: 10),
            UiIconButton(icon: Icons.camera_alt_outlined, label: '拍照取景'),
            SizedBox(width: 8),
            UiIconButton(icon: Icons.audio_file_outlined, label: '场景音效'),
          ],
        ),
  ),
  UiTemplate(
    id: 'tpl_toast',
    name: '全局通知 toast',
    category: UiTemplateCategory.page,
    description: '右上角 ≤1/3 宽、不占全屏的全局通知。拆自 GlobalNotificationToast。',
    tags: <String>['通知', 'toast', '右上'],
    nodes: _toastNodes,
    build: (BuildContext c) => SizedBox(width: 320, child: UiToast()),
  ),
  UiTemplate(
    id: 'tpl_state_page',
    name: '状态页（载入/错误/空）',
    category: UiTemplateCategory.page,
    description: '图标 + 标题 + 描述 + 操作按钮的三种状态页。拆自 state_views。',
    tags: <String>['状态', '空态', '错误'],
    nodes: _statePageNodes,
    build: (BuildContext c) => UiStatePage(),
  ),
  UiTemplate(
    id: 'tpl_login_sheet',
    name: '网易云登录 sheet',
    category: UiTemplateCategory.page,
    description: '二维码 + MUSIC_U/__csrf 双输入框 + 登录按钮。拆自 netease_login_sheet。',
    tags: <String>['登录', '二维码', '表单'],
    nodes: _loginSheetNodes,
    build: (BuildContext c) => UiLoginSheet(),
  ),
  // ── 区块级 ──────────────────────────────────────────
  UiTemplate(
    id: 'tpl_top_bar',
    name: '顶栏 chips 组',
    category: UiTemplateCategory.block,
    description: '玻璃圆钮横向排布（菜单/视角/相机/存档/暂停/设置）。拆自 voxel 顶栏。',
    tags: <String>['顶栏', 'chips', '玻璃'],
    nodes: _topBarNodes,
    build: (BuildContext c) => UiTopBar(),
  ),
  UiTemplate(
    id: 'tpl_fold_panel',
    name: '折叠面板',
    category: UiTemplateCategory.block,
    description: '坐标/自动跳/HUD/沉浸四项开关面板。拆自 voxel _FoldPanel。',
    tags: <String>['面板', '开关', 'HUD'],
    nodes: _foldPanelNodes,
    build: (BuildContext c) => UiFoldPanel(),
  ),
  UiTemplate(
    id: 'tpl_action_pad',
    name: '动作键区',
    category: UiTemplateCategory.block,
    description: '攻击/放置/蹲/跳大动作键组（移动端）。拆自 voxel 动作键区。',
    tags: <String>['动作', '移动端', '按钮'],
    nodes: _actionPadNodes,
    build: (BuildContext c) => UiActionPad(),
  ),
  UiTemplate(
    id: 'tpl_card_grid',
    name: '卡片网格',
    category: UiTemplateCategory.block,
    description: '封面 + 名称的响应式卡片网格。拆自 AlbumCard 网格。',
    tags: <String>['网格', '卡片', '专辑'],
    nodes: _cardGridNodes,
    build: (BuildContext c) => SizedBox(width: 340, child: UiCardGrid(count: 3)),
  ),
  UiTemplate(
    id: 'tpl_info_bar',
    name: 'HUD 信息条',
    category: UiTemplateCategory.block,
    description: '胶囊信息条（坐标/模式/时段）。拆自 voxel _WorldInfoBar。',
    tags: <String>['HUD', '胶囊', '信息'],
    nodes: _infoBarNodes,
    build: (BuildContext c) => UiInfoBar(),
  ),
  UiTemplate(
    id: 'tpl_master_detail',
    name: '设置页 Master-Detail',
    category: UiTemplateCategory.block,
    description: '左侧分类导航 + 右侧详情区的双栏骨架。拆自 settings_page。',
    tags: <String>['双栏', '导航', '设置'],
    nodes: () => <UiNode>[
          UiNode.container(
            'md_root',
            'Master-Detail',
            layout: UiLayout.horizontal,
            gap: 14,
            width: 420,
            children: <UiNode>[
              UiNode.container(
                'md_rail',
                '分类栏',
                color: '#1C1C26',
                radius: 18,
                padding: 8,
                gap: 6,
                width: 120,
                children: <UiNode>[
                  UiNode.button('md_c1', '分类', '音频', accent: '#9B7BFF'),
                  UiNode.button('md_c2', '分类', '画面', accent: '#262634'),
                  UiNode.button('md_c3', '分类', '机制', accent: '#262634'),
                ],
              ),
              UiNode.container(
                'md_detail',
                '详情区',
                color: '#1C1C26',
                radius: 18,
                padding: 12,
                gap: 8,
                children: <UiNode>[
                  UiNode.txt('md_t', '标题', '音频 · 音量与音源', size: 16, weight: '600', color: '#F2F2F7'),
                  UiNode.button('md_i1', '项', '主音量', accent: '#262634'),
                  UiNode.button('md_i2', '项', '均衡器', accent: '#262634'),
                ],
              ),
            ],
          ),
        ],
    build: (BuildContext c) => Container(
          width: 420,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.appColors.bgPage,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 120,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.appColors.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: const <Widget>[
                    UiMenuButton(icon: Icons.audiotrack, label: '音频', trailing: false),
                    UiMenuButton(icon: Icons.image_outlined, label: '画面', trailing: false),
                    UiMenuButton(icon: Icons.tune, label: '机制', trailing: false),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.appColors.bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('音频 · 音量与音源', style: AppTextStyles.subtitle),
                      SizedBox(height: 10),
                      UiSliderRow(title: '主音量'),
                      SizedBox(height: 8),
                      UiToggleRow(title: '后台播放', value: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
  ),
  // ── 控件级 ──────────────────────────────────────────
  UiTemplate(
    id: 'tpl_glass_button',
    name: '玻璃圆钮',
    category: UiTemplateCategory.control,
    description: '半透明圆形图标按钮（40dp）。拆自 voxel _GlassCircleButton。',
    tags: <String>['按钮', '玻璃', '圆形'],
    nodes: _glassButtonNodes,
    build: (BuildContext c) => UiGlassButton(icon: Icons.settings),
  ),
  UiTemplate(
    id: 'tpl_action_button',
    name: '大动作键',
    category: UiTemplateCategory.control,
    description: '图标 + 小字的移动端大按钮（56dp）。拆自 voxel _BigActionButton。',
    tags: <String>['按钮', '移动端', '大键'],
    nodes: () => <UiNode>[UiNode.button('ab', '大动作键', '攻击', icon: 'e8e8', accent: '#66000000')],
    build: (BuildContext c) => UiActionButton(icon: Icons.sports_martial_arts, label: '攻击'),
  ),
  UiTemplate(
    id: 'tpl_menu_button',
    name: '菜单按钮',
    category: UiTemplateCategory.control,
    description: '图标 + 文本 + 箭头的主菜单按钮。拆自 voxel_main_menu _MenuButton。',
    tags: <String>['按钮', '菜单', '行'],
    nodes: _menuButtonNodes,
    build: (BuildContext c) => UiMenuButton(icon: Icons.folder_open_outlined, label: '世界存档'),
  ),
  UiTemplate(
    id: 'tpl_glow_entry',
    name: '发光入口钮',
    category: UiTemplateCategory.control,
    description: '径向渐变 + 外发光圆形按钮。拆自 scene _GlowEntryButton。',
    tags: <String>['按钮', '发光', '圆形'],
    nodes: _glowEntryNodes,
    build: (BuildContext c) => UiGlowEntryButton(icon: Icons.auto_awesome_rounded),
  ),
  UiTemplate(
    id: 'tpl_toggle_row',
    name: '开关行',
    category: UiTemplateCategory.control,
    description: '标题 + 副标题 + Switch 的设置行。拆自设置页通用开关行。',
    tags: <String>['开关', '设置', '行'],
    nodes: _toggleRowNodes,
    build: (BuildContext c) => UiToggleRow(title: '后台播放', subtitle: '退出应用后继续播放', value: true),
  ),
  UiTemplate(
    id: 'tpl_slider_row',
    name: '滑块行',
    category: UiTemplateCategory.control,
    description: '标题 + Slider 的设置行。拆自设置页通用滑块行。',
    tags: <String>['滑块', '设置', '行'],
    nodes: _sliderRowNodes,
    build: (BuildContext c) => UiSliderRow(title: '主音量', value: 0.6),
  ),
];
