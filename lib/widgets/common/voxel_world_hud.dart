/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 HUD（预设组件 · Task #525）
/// ════════════════════════════════════════════════════════════════════════
///
/// 还原 Ardot 设计 `ui-游戏内HUD-体素世界`（3:577）：
///   - 居中准星（圆环 + 圆点）
///   - 左上坐标面板（坐标 / 群系 / 游戏时间）+ FPS·延迟
///   - 右上 设置 / 菜单 圆按钮 + 顶部居中「模式」药丸
///   - 右上小地图
///   - 底部居中 9 格快捷栏（slot-0 选中高亮）
///   - 左侧建造工具栏（tool-1 选中高亮）
///
/// 所有面板均为 [LiquidGlass]，颜色取自 `context.appColors`，不写死任何品牌色；
/// 内容通过构造参数注入（坐标 / 帧率 / 快捷栏 / 工具 / 回调），可作为游戏内 HUD 的
/// 复用基础件。
///
/// 用法：
/// ```dart
/// VoxelWorldHud(
///   coordX: 128, coordY: 24, coordZ: -64,
///   biome: '樱花林', gameTime: '18:42',
///   fps: 60, ping: 28,
///   modeLabel: '建造模式',
///   hotbarChildren: List<Widget>.generate(9, (_) => const Icon(Icons.cube)),
///   buildToolChildren: const <Widget>[Icon(Icons.edit), Icon(Icons.brush), Icon(Icons.delete)],
///   onSettings: () => openSettings(),
///   onMenu: () => openMenu(),
/// )
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../widgets/liquid_glass.dart';

/// 体素世界 HUD 覆盖层（预设）。
class VoxelWorldHud extends StatelessWidget {
  const VoxelWorldHud({
    super.key,
    this.coordX,
    this.coordY,
    this.coordZ,
    this.biome,
    this.gameTime,
    this.fps,
    this.ping,
    this.modeLabel,
    this.hotbarChildren = const <Widget>[],
    this.activeHotbarIndex = 0,
    this.buildToolChildren = const <Widget>[],
    this.activeToolIndex = 0,
    this.minimap,
    this.onSettings,
    this.onMenu,
    this.onHotbarTap,
    this.onBuildToolTap,
  });

  /// 坐标 X / Y / Z（整数）。
  final int? coordX;
  final int? coordY;
  final int? coordZ;

  /// 当前群系名。
  final String? biome;

  /// 游戏内时间（如 "18:42"）。
  final String? gameTime;

  /// 帧率 / 网络延迟（毫秒）。
  final int? fps;
  final int? ping;

  /// 顶部模式药丸文案（如 "建造模式"）。
  final String? modeLabel;

  /// 底部 9 格快捷栏内容（不足 9 个时按实际数量渲染）。
  final List<Widget> hotbarChildren;

  /// 当前选中的快捷栏下标。
  final int activeHotbarIndex;

  /// 左侧建造工具栏内容。
  final List<Widget> buildToolChildren;

  /// 当前选中的工具下标。
  final int activeToolIndex;

  /// 小地图内容（默认渐变占位）。
  final Widget? minimap;

  final VoidCallback? onSettings;
  final VoidCallback? onMenu;
  final ValueChanged<int>? onHotbarTap;
  final ValueChanged<int>? onBuildToolTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return Stack(
      children: <Widget>[
        // 准星（居中）
        const Center(child: _Crosshair()),
        // 左上坐标面板 + FPS
        Positioned(
          top: 16,
          left: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CoordsPanel(
                colors: colors,
                coordX: coordX,
                coordY: coordY,
                coordZ: coordZ,
                biome: biome,
                gameTime: gameTime,
              ),
              const SizedBox(height: 8),
              _FpsPing(colors: colors, fps: fps, ping: ping),
            ],
          ),
        ),
        // 右上 菜单 + 设置
        Positioned(
          top: 16,
          right: 16,
          child: Row(
            children: <Widget>[
              _RoundIconButton(
                colors: colors,
                icon: Icons.menu,
                onTap: onMenu,
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                colors: colors,
                icon: Icons.settings,
                onTap: onSettings,
              ),
            ],
          ),
        ),
        // 顶部居中模式药丸
        if (modeLabel != null)
          Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: Center(
              child: _ModePill(colors: colors, label: modeLabel!),
            ),
          ),
        // 右上小地图
        Positioned(
          top: 64,
          right: 16,
          child: _Minimap(colors: colors, child: minimap),
        ),
        // 左侧建造工具栏
        if (buildToolChildren.isNotEmpty)
          Positioned(
            top: 680,
            left: 16,
            child: _BuildToolbar(
              colors: colors,
              tools: buildToolChildren,
              activeIndex: activeToolIndex,
              onTap: onBuildToolTap,
            ),
          ),
        // 底部 9 格快捷栏
        if (hotbarChildren.isNotEmpty)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: _Hotbar(
                colors: colors,
                slots: hotbarChildren,
                activeIndex: activeHotbarIndex,
                onTap: onHotbarTap,
              ),
            ),
          ),
      ],
    );
  }
}

/// 居中准星（圆环 + 圆点）。
class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              border: Border.all(
                color: colors.textPrimary.withValues(alpha: 0.55),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textPrimary.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 左上坐标面板。
class _CoordsPanel extends StatelessWidget {
  const _CoordsPanel({
    required this.colors,
    this.coordX,
    this.coordY,
    this.coordZ,
    this.biome,
    this.gameTime,
  });

  final AppThemeColors colors;
  final int? coordX;
  final int? coordY;
  final int? coordZ;
  final String? biome;
  final String? gameTime;

  @override
  Widget build(BuildContext context) {
    final String xyz = '${coordX ?? 0} / ${coordY ?? 0} / ${coordZ ?? 0}';
    return LiquidGlass(
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '坐标 X · Y · Z',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              xyz,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: colors.textPrimary,
              ),
            ),
            if (biome != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                biome!,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
            if (gameTime != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '游戏时间 $gameTime',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// FPS · 延迟 文本。
class _FpsPing extends StatelessWidget {
  const _FpsPing({required this.colors, this.fps, this.ping});
  final AppThemeColors colors;
  final int? fps;
  final int? ping;

  @override
  Widget build(BuildContext context) {
    final String text =
        'FPS ${fps ?? 0} · 延迟 ${ping ?? 0}ms';
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: colors.textSecondary,
      ),
    );
  }
}

/// 右上圆形图标按钮（设置 / 菜单）。
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.colors,
    required this.icon,
    this.onTap,
  });

  final AppThemeColors colors;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.bgSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border, width: 1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(icon, size: 18, color: colors.iconPrimary),
          ),
        ),
      ),
    );
  }
}

/// 顶部居中模式药丸（强调色）。
class _ModePill extends StatelessWidget {
  const _ModePill({required this.colors, required this.label});
  final AppThemeColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.onAccent,
          ),
        ),
      ),
    );
  }
}

/// 小地图（默认渐变占位，可注入内容）。
class _Minimap extends StatelessWidget {
  const _Minimap({required this.colors, this.child});
  final AppThemeColors colors;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 18,
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 92,
        height: 92,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: child ??
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[colors.accentSoft, colors.bgSurface],
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

/// 底部 9 格快捷栏。
class _Hotbar extends StatelessWidget {
  const _Hotbar({
    required this.colors,
    required this.slots,
    required this.activeIndex,
    this.onTap,
  });

  final AppThemeColors colors;
  final List<Widget> slots;
  final int activeIndex;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 16,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < slots.length; i++) ...<Widget>[
            _HotbarSlot(
              colors: colors,
              active: i == activeIndex,
              onTap: onTap == null ? null : () => onTap!(i),
              child: slots[i],
            ),
            if (i < slots.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// 单个快捷栏槽位（28×28）。
class _HotbarSlot extends StatelessWidget {
  const _HotbarSlot({
    required this.colors,
    required this.active,
    required this.child,
    this.onTap,
  });

  final AppThemeColors colors;
  final bool active;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? colors.accent.withValues(alpha: 0.18)
          : colors.bgSurface.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: active ? colors.accent : colors.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// 左侧建造工具栏。
class _BuildToolbar extends StatelessWidget {
  const _BuildToolbar({
    required this.colors,
    required this.tools,
    required this.activeIndex,
    this.onTap,
  });

  final AppThemeColors colors;
  final List<Widget> tools;
  final int activeIndex;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 16,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < tools.length; i++) ...<Widget>[
            _ToolSlot(
              colors: colors,
              active: i == activeIndex,
              onTap: onTap == null ? null : () => onTap!(i),
              child: tools[i],
            ),
            if (i < tools.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// 单个工具槽位（44×44）。
class _ToolSlot extends StatelessWidget {
  const _ToolSlot({
    required this.colors,
    required this.active,
    required this.child,
    this.onTap,
  });

  final AppThemeColors colors;
  final bool active;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? colors.accent.withValues(alpha: 0.18)
          : colors.bgSurface.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: active ? colors.accent : colors.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: child),
        ),
      ),
    );
  }
}
