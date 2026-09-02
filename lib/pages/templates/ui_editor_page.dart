/// ════════════════════════════════════════════════════════════════════════
/// UI 编辑器 —— 实时编辑中预览 + 资产面板 + 自动纠错
/// ════════════════════════════════════════════════════════════════════════
///
/// 布局：左（资产面板：基础控件可拖入 + 模板起步）｜ 中（画布：节点树
/// 实时渲染、点击选中、虚线高亮）｜ 右（属性面板：改选中节点属性即时生效）
/// ｜ 底（纠错面板：runUiRules 结果，点击定位）。
///
/// 用法：
///   1. 从资产面板拖「基础控件」入画布，或点「模板」以优质模板起步；
///   2. 点画布节点选中 → 右侧改属性（实时预览）；
///   3. 开「纠错」跑规则 → 问题列表点击定位 → 修复 → 导出 JSON 固化。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/ui_editor_model.dart';
import '../../core/ui_editor_rules.dart';
import '../../core/ui_templates.dart';
import '../../widgets/notification/app_notify.dart';

/// 编辑器页。
class UiEditorPage extends StatefulWidget {
  const UiEditorPage({super.key, this.initialTemplate});

  /// 以某个模板起步（画廊传入）；null = 空白画布。
  final UiTemplate? initialTemplate;

  @override
  State<UiEditorPage> createState() => _UiEditorPageState();
}

class _UiEditorPageState extends State<UiEditorPage> {
  late UiNode _root;
  // cl45：多选集合 + 主选中（兼容既有单选取值逻辑）。
  String? _selectedId;
  final Set<String> _selectedIds = <String>{};
  bool _showIssues = true;
  List<UiIssue> _issues = <UiIssue>[];
  // cl45：撤销/重做历史 + 剪贴板（复制/粘贴用）。
  final List<UiNode> _history = <UiNode>[];
  final List<UiNode> _future = <UiNode>[];
  List<UiNode> _clipboard = <UiNode>[];
  // cl45：多选模式开关（工具栏）——开时点击切换选中集。
  bool _multiSelect = false;

  @override
  void initState() {
    super.initState();
    final UiTemplate? t = widget.initialTemplate;
    _root = UiNode.container(
      'root',
      t?.name ?? '画布',
      gap: 12,
      padding: 16,
      children: t != null ? t.nodes() : const <UiNode>[],
    );
    _recomputeIssues();
  }

  void _recomputeIssues() => _issues = runUiRules(_root);

  /// cl45：统一选择入口（清多选 + 设主选中；additive=true 为 shift 切换多选）。
  void _select(String? id, {bool additive = false}) {
    setState(() {
      if (id == null) {
        _selectedIds.clear();
        _selectedId = null;
        return;
      }
      if (additive) {
        if (!_selectedIds.remove(id)) _selectedIds.add(id);
      } else {
        _selectedIds
          ..clear()
          ..add(id);
      }
      _selectedId = _selectedIds.isEmpty ? null : _selectedIds.last;
    });
  }

  /// cl45：提交一次修改——入撤销栈（上限 100）、清重做栈、重建。
  void _commit(UiNode next) {
    _history.add(_root);
    if (_history.length > 100) _history.removeAt(0);
    _future.clear();
    setState(() {
      _root = next;
      _recomputeIssues();
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _future.add(_root);
      _root = _history.removeLast();
      _selectedIds.clear();
      _selectedId = null;
      _recomputeIssues();
    });
  }

  void _redo() {
    if (_future.isEmpty) return;
    setState(() {
      _history.add(_root);
      _root = _future.removeLast();
      _selectedIds.clear();
      _selectedId = null;
      _recomputeIssues();
    });
  }

  void _updateSelected(UiNode newNode) {
    final String? id = _selectedId;
    if (id == null) return;
    _commit(_root.replace(id, newNode));
  }

  UiNode? get _selected => _root.find(_selectedId ?? '');

  /// cl45：编辑器快捷键（撤销/重做/复制/粘贴/删除/方向键微调）。
  Widget _editorShortcuts(BuildContext context, Widget child) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            const _CopyIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const _PasteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyX, control: true):
            const _CutIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _NudgeIntent(-1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _NudgeIntent(1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _NudgeIntent(0, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _NudgeIntent(0, 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            const _NudgeIntent(-8, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            const _NudgeIntent(8, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
            const _NudgeIntent(0, -8),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
            const _NudgeIntent(0, 8),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) => _undo()),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) => _redo()),
          _CopyIntent:
              CallbackAction<_CopyIntent>(onInvoke: (_) => _copySelected()),
          _PasteIntent:
              CallbackAction<_PasteIntent>(onInvoke: (_) => _paste()),
          _CutIntent: CallbackAction<_CutIntent>(onInvoke: (_) {
            _copySelected();
            _deleteSelected();
            return null;
          }),
          _DeleteIntent:
              CallbackAction<_DeleteIntent>(onInvoke: (_) => _deleteSelected()),
          _NudgeIntent: CallbackAction<_NudgeIntent>(
              onInvoke: (_NudgeIntent i) => _nudgeSelected(i.dx, i.dy)),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }

  // ── 资产面板：基础控件 payload ──────────────────────

  static UiNode _spawn(UiNodeType type) {
    final String id = 'n${DateTime.now().microsecondsSinceEpoch}';
    switch (type) {
      case UiNodeType.container:
        return UiNode.container(id, '容器', color: '#262634', radius: 18, gap: 8, padding: 12);
      case UiNodeType.text:
        return UiNode.txt(id, '文本', '双击改文字', size: 14, color: '#F2F2F7');
      case UiNodeType.button:
        return UiNode.button(id, '按钮', '按钮', icon: 'e145', accent: '#9B7BFF');
      case UiNodeType.icon:
        return UiNode.iconNode(id, '图标', 'e145', color: '#F2F2F7');
      case UiNodeType.spacer:
        return UiNode.spacer(id, '间距', height: 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _editorShortcuts(
      context,
      Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        title: const Text('UI 编辑器'),
        backgroundColor: context.appColors.bgSurface,
        actions: <Widget>[
          // 模板起步（下拉）。
          PopupMenuButton<UiTemplate>(
            tooltip: '以模板起步',
            icon: const Icon(Icons.widgets_outlined),
            onSelected: (UiTemplate t) {
              _commit(UiNode.container(
                  'root', t.name, gap: 12, padding: 16, children: t.nodes()));
              _select(null);
            },
            itemBuilder: (BuildContext c) => <PopupMenuEntry<UiTemplate>>[
              for (final UiTemplate t in kUiTemplates)
                PopupMenuItem<UiTemplate>(
                  value: t,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        t.category == UiTemplateCategory.page
                            ? Icons.article_outlined
                            : t.category == UiTemplateCategory.block
                                ? Icons.dashboard_customize_outlined
                                : Icons.circle_outlined,
                        size: 16,
                        color: context.appColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(t.name, style: context.appText.body),
                    ],
                  ),
                ),
            ],
          ),
          // ── cl45：编辑器工具（撤销/重做/复制/粘贴/多选/删除）──
          IconButton(
            tooltip: '撤销 (Ctrl+Z)',
            icon: const Icon(Icons.undo_rounded),
            onPressed: _history.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: '重做 (Ctrl+Y)',
            icon: const Icon(Icons.redo_rounded),
            onPressed: _future.isEmpty ? null : _redo,
          ),
          IconButton(
            tooltip: '复制选中 (Ctrl+C)',
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: _selectedIds.isEmpty ? null : _copySelected,
          ),
          IconButton(
            tooltip: '粘贴 (Ctrl+V)',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _clipboard.isEmpty ? null : _paste,
          ),
          IconButton(
            tooltip: '多选模式（开时点击切换选中集）',
            icon: Icon(
              _multiSelect ? Icons.select_all_rounded : Icons.select_all_outlined,
            ),
            onPressed: () => setState(() => _multiSelect = !_multiSelect),
          ),
          IconButton(
            tooltip: '删除选中 (Delete)',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
          ),
          IconButton(
            tooltip: '纠错 ${_showIssues ? '开' : '关'}（${_issues.length} 项）',
            icon: Badge(
              isLabelVisible: _showIssues && _issues.isNotEmpty,
              label: Text('${_issues.length}'),
              child: Icon(_showIssues ? Icons.rule_rounded : Icons.rule_folder_outlined),
            ),
            onPressed: () => setState(() {
              _showIssues = !_showIssues;
              if (_showIssues) _recomputeIssues();
            }),
          ),
          IconButton(
            tooltip: '导出节点 JSON',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _root.toJsonString()));
              appNotify(context, '已复制节点树 JSON 到剪贴板');
            },
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _assetPanel(context),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: _canvas(context),
                ),
                if (_showIssues) _issuesPanel(context),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          _propertyPanel(context),
        ],
      ),
      ),
    );
  }

  // ── 左：资产面板 ────────────────────────────────────

  Widget _assetPanel(BuildContext context) {
    Widget tile(IconData icon, String label, UiNode payload) => Draggable<UiNode>(
          data: payload,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.appColors.accent.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(label, style: context.appText.body.copyWith(color: context.appColors.onAccent)),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: _assetTile(context, icon, label)),
          child: _assetTile(context, icon, label),
        );

    return Container(
      width: 168,
      color: context.appColors.bgSurface,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.sm),
        children: <Widget>[
          Text('基础控件（拖入画布）', style: context.appText.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          tile(Icons.crop_square_rounded, '容器', _spawn(UiNodeType.container)),
          tile(Icons.text_fields_rounded, '文本', _spawn(UiNodeType.text)),
          tile(Icons.smart_button_rounded, '按钮', _spawn(UiNodeType.button)),
          tile(Icons.emoji_symbols_rounded, '图标', _spawn(UiNodeType.icon)),
          tile(Icons.space_bar_rounded, '间距', _spawn(UiNodeType.spacer)),
          const SizedBox(height: 12),
          Text('模板（点击起步）', style: context.appText.caption.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final UiTemplate t in kUiTemplates)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                t.category == UiTemplateCategory.page
                    ? Icons.article_outlined
                    : t.category == UiTemplateCategory.block
                        ? Icons.dashboard_customize_outlined
                        : Icons.circle_outlined,
                size: 16,
                color: context.appColors.textSecondary,
              ),
              title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.appText.caption),
              onTap: () {
                _commit(UiNode.container(
                    'root', t.name, gap: 12, padding: 16, children: t.nodes()));
                _select(null);
              },
            ),
        ],
      ),
    );
  }

  Widget _assetTile(BuildContext context, IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: context.appColors.bgTile,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.appColors.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: context.appColors.textSecondary),
              const SizedBox(width: 8),
              Text(label, style: context.appText.caption),
            ],
          ),
        ),
      );

  // ── 中：画布 ────────────────────────────────────────

  Widget _canvas(BuildContext context) {
    return DragTarget<UiNode>(
      onAcceptWithDetails: (DragTargetDetails<UiNode> d) {
        final UiNode newNode = d.data.clone()
          ..id = 'n${DateTime.now().microsecondsSinceEpoch}';
        _commit(UiNode.container(
          _root.id,
          _root.name,
          layout: _root.layout,
          align: _root.align,
          gap: _root.gap,
          padding: _root.padding,
          radius: _root.cornerRadius,
          width: _root.width,
          height: _root.height,
          color: _root.color,
          border: _root.borderColor,
          children: <UiNode>[..._root.children, newNode],
        ));
        _select(newNode.id);
      },
      builder: (BuildContext c, List<UiNode?> cand, List<dynamic> rej) {
        final bool hovering = cand.isNotEmpty;
        return Container(
          color: hovering
              ? context.appColors.accent.withValues(alpha: 0.06)
              : const Color(0xFF0B1220),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _select(null),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _nodeWidget(context, _root),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 递归渲染节点 → Widget（选中节点包虚线框；可拖拽；容器可接收拖入）。
  Widget _nodeWidget(BuildContext context, UiNode n) {
    final Widget inner = switch (n.type) {
      UiNodeType.container => _containerWidget(context, n),
      UiNodeType.text => Text(
          n.text.isEmpty ? '（空文本）' : n.text,
          style: TextStyle(
            fontSize: n.fontSize,
            fontWeight: _fw(n.fontWeight),
            color: _colorOf(n.textColor, context.appColors.textPrimary),
          ),
        ),
      UiNodeType.button => _buttonWidget(context, n),
      UiNodeType.icon => Icon(
          resolveIcon(n.icon) ?? Icons.circle_outlined,
          size: n.iconSize,
          color: _colorOf(n.textColor, context.appColors.iconPrimary),
        ),
      UiNodeType.spacer => SizedBox(height: n.height ?? 12),
    };

    final bool selNow = _selectedIds.contains(n.id);
    // cl45：预览动画包装（fade 淡入 / scale 缩放；none 直通）。
    final Widget innerW = _animWrap(n, inner);
    Widget wrapped = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // cl45：多选模式（工具栏开关）下点击切换选中集；默认单选。
      onTap: () => _select(n.id, additive: _multiSelect),
      child: Container(
        foregroundDecoration: selNow
            ? BoxDecoration(
                border: Border.all(color: context.appColors.accent, width: 1.5),
                borderRadius: BorderRadius.circular(n.cornerRadius + 2),
              )
            : null,
        child: innerW,
      ),
    );

    // 可拖拽（root 除外）：长按拖动节点到任意容器。
    if (n.id != 'root') {
      wrapped = LongPressDraggable<UiNode>(
        data: n,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.appColors.accent.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '移动「${n.name}」',
                style: context.appText.caption.copyWith(color: context.appColors.onAccent),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: wrapped),
        child: wrapped,
      );
    }

    // 容器 = 拖入目标：把拖入的节点移入本容器末尾。
    if (n.type == UiNodeType.container) {
      wrapped = DragTarget<UiNode>(
        onAcceptWithDetails: (DragTargetDetails<UiNode> d) {
          if (d.data.id == n.id) return;
          _commit(moveNode(_root, d.data.id, n.id));
          _select(d.data.id);
        },
        builder: (BuildContext c, List<UiNode?> cand, List<dynamic> rej) => Container(
          foregroundDecoration: cand.isNotEmpty
              ? BoxDecoration(
                  border: Border.all(
                    color: context.appColors.accent.withValues(alpha: 0.6),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(n.cornerRadius + 4),
                )
              : null,
          child: wrapped,
        ),
      );
    }

    if (!selNow && n.children.isEmpty) return wrapped;
    return wrapped;
  }

  Widget _containerWidget(BuildContext context, UiNode n) {
    final List<Widget> kids = n.children
        .map((UiNode c) => _nodeWidget(context, c))
        .toList();
    final int? bg = parseHexColor(n.color);
    final int? brd = parseHexColor(n.borderColor);
    final LinearGradient? grad = gradientOf(n);
    final Widget box = Container(
      width: n.width,
      height: n.height,
      padding: EdgeInsets.all(n.padding),
      decoration: BoxDecoration(
        color: grad == null && bg != null ? Color(bg) : null,
        gradient: grad,
        borderRadius: BorderRadius.circular(n.cornerRadius),
        border: brd != null ? Border.all(color: Color(brd)) : null,
      ),
      // cl45：自由定位模式（root 开关）→ Stack + Positioned(x,y) 画布，
      // 对齐/分布/方向键微调在此模式下有意义。
      child: n.freePos
          ? Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                for (final UiNode c in n.children)
                  Positioned(
                    left: c.x ?? 0,
                    top: c.y ?? 0,
                    child: _nodeWidget(context, c),
                  ),
              ],
            )
          : switch (n.layout) {
              UiLayout.horizontal => Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: _mainAxis(n.align),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: _withGaps(kids, n.gap),
                ),
              UiLayout.vertical => Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: _mainAxis(n.align),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _withGaps(kids, n.gap),
                ),
              UiLayout.wrap => Wrap(
                  spacing: n.gap,
                  runSpacing: n.gap,
                  children: kids,
                ),
            },
    );
    return n.children.isEmpty
        ? SizedBox(width: n.width ?? 120, height: n.height ?? 40, child: box)
        : box;
  }

  /// cl45：预览动画包装（fade 淡入 / scale 缩放；none 直通）。
  Widget _animWrap(UiNode n, Widget child) {
    switch (n.anim) {
      case 'fade':
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 350),
          builder: (BuildContext c, double v, Widget? w) =>
              Opacity(opacity: v, child: w),
          child: child,
        );
      case 'scale':
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 350),
          builder: (BuildContext c, double v, Widget? w) =>
              Transform.scale(scale: v, child: w),
          child: child,
        );
      default:
        return child;
    }
  }

  Widget _buttonWidget(BuildContext context, UiNode n) {
    final int? bg = parseHexColor(n.accentColor);
    final LinearGradient? grad = gradientOf(n);
    final Color base = bg != null ? Color(bg) : context.appColors.accent;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: n.padding + 8, vertical: 10),
      decoration: BoxDecoration(
        gradient: grad,
        color: grad == null ? base : null,
        borderRadius: BorderRadius.circular(n.cornerRadius <= 0 ? AppRadius.md : n.cornerRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (n.icon != null && n.icon!.isNotEmpty) ...<Widget>[
            Icon(resolveIcon(n.icon), size: n.iconSize - 4, color: context.appColors.onAccent),
            const SizedBox(width: 6),
          ],
          if (n.text.isNotEmpty)
            Text(
              n.text,
              style: TextStyle(
                fontSize: n.fontSize,
                fontWeight: _fw(n.fontWeight),
                color: context.appColors.onAccent,
              ),
            ),
        ],
      ),
    );
  }

  /// 字号粗细字符串 → FontWeight。
  static FontWeight _fw(String w) => switch (w) {
        '100' => FontWeight.w100,
        '200' => FontWeight.w200,
        '300' => FontWeight.w300,
        '500' => FontWeight.w500,
        '600' => FontWeight.w600,
        '700' => FontWeight.w700,
        '800' => FontWeight.w800,
        '900' => FontWeight.w900,
        _ => FontWeight.w400,
      };

  /// 色串 → Color（非法回退默认）。
  static Color _colorOf(String? hex, Color fallback) {
    final int? v = parseHexColor(hex);
    return v != null ? Color(v) : fallback;
  }

  List<Widget> _withGaps(List<Widget> kids, double gap) {
    if (kids.isEmpty) return kids;
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i < kids.length - 1) out.add(SizedBox(width: gap));
    }
    return out;
  }

  MainAxisAlignment _mainAxis(UiAlign a) => switch (a) {
        UiAlign.min => MainAxisAlignment.start,
        UiAlign.center => MainAxisAlignment.center,
        UiAlign.max => MainAxisAlignment.end,
        UiAlign.spaceBetween => MainAxisAlignment.spaceBetween,
      };

  // ── 底：纠错面板 ────────────────────────────────────

  Widget _issuesPanel(BuildContext context) {
    final Color bg = context.appColors.bgSurface;
    final Color danger = context.appColors.danger;
    final Color accent = context.appColors.accent;
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 8, AppSpace.md, 4),
            child: Row(
              children: <Widget>[
                Icon(_issues.isEmpty ? Icons.verified_rounded : Icons.rule_rounded,
                    size: 16, color: _issues.isEmpty ? accent : danger),
                const SizedBox(width: 6),
                Text(
                  _issues.isEmpty
                      ? '纠错：未发现问题 ✓'
                      : '纠错：${_issues.length} 项（点击定位）',
                  style: context.appText.caption.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_issues.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _recomputeIssues()),
                    child: const Text('重新检查'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _issues.isEmpty
                ? Center(
                    child: Text('所有设计规则通过：对比度 / 溢出 / 间距 / 重叠 / 语义',
                        style: context.appText.artist.copyWith(fontSize: 11)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    itemCount: _issues.length,
                    itemBuilder: (BuildContext c, int i) {
                      final UiIssue it = _issues[i];
                      final Color dot = switch (it.severity) {
                        UiIssueSeverity.error => danger,
                        UiIssueSeverity.warning => const Color(0xFFF5A623),
                        UiIssueSeverity.info => context.appColors.textTertiary,
                      };
                      return InkWell(
                        onTap: () {
                          if (it.nodeId != null) {
                            _select(it.nodeId);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.circle, size: 8, color: dot),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  it.message,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.appText.artist.copyWith(fontSize: 11),
                                ),
                              ),
                              if (it.fix != null) ...<Widget>[
                                const SizedBox(width: 6),
                                Icon(Icons.tips_and_updates_outlined, size: 13, color: context.appColors.textTertiary),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── 右：属性面板 ────────────────────────────────────

  Widget _propertyPanel(BuildContext context) {
    final UiNode? n = _selected;
    if (n == null) {
      return Container(
        width: 230,
        color: context.appColors.bgSurface,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('属性', style: context.appText.caption.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('点击画布中的节点查看/编辑属性。\n\n从左侧拖入控件，或选模板起步。', style: context.appText.artist),
          ],
        ),
      );
    }

    return Container(
      width: 250,
      color: context.appColors.bgSurface,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('属性 · ${n.type.name}', style: context.appText.caption.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (n.id != 'root') ...<Widget>[
                // 排序：容器内上移/下移（可视化编辑）。
                _moveBtn(Icons.arrow_upward_rounded, '上移', () => _moveSibling(n.id, -1)),
                _moveBtn(Icons.arrow_downward_rounded, '下移', () => _moveSibling(n.id, 1)),
                _moveBtn(Icons.vertical_align_top_rounded, '移到最前', () => _moveSibling(n.id, -999)),
                _moveBtn(Icons.vertical_align_bottom_rounded, '移到最后', () => _moveSibling(n.id, 999)),
              ],
              IconButton(
                tooltip: '删除节点',
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: () => _deleteSelected(),
              ),
            ],
          ),
          // ── cl45：自由定位（root）+ 对齐/分布/吸附 ──
          if (n.id == 'root') ...<Widget>[
            _label(context, '自由定位（Stack 画布）'),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('自由定位模式',
                  style: context.appText.body.copyWith(fontSize: 12)),
              value: n.freePos,
              onChanged: (bool v) => _updateSelected(n.clone()..freePos = v),
            ),
            if (_selectedIds.length >= 2) ...<Widget>[
              _label(context, '对齐 / 分布（已选 ${_selectedIds.length} 个）'),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  _miniBtn(Icons.format_align_left_rounded, '左对齐',
                      () => _alignSelected(_AlignAxis.left)),
                  _miniBtn(Icons.format_align_center_rounded, '水平居中',
                      () => _alignSelected(_AlignAxis.hCenter)),
                  _miniBtn(Icons.format_align_right_rounded, '右对齐',
                      () => _alignSelected(_AlignAxis.right)),
                  _miniBtn(Icons.vertical_align_top_rounded, '上对齐',
                      () => _alignSelected(_AlignAxis.top)),
                  _miniBtn(Icons.vertical_align_center_rounded, '垂直居中',
                      () => _alignSelected(_AlignAxis.vCenter)),
                  _miniBtn(Icons.vertical_align_bottom_rounded, '下对齐',
                      () => _alignSelected(_AlignAxis.bottom)),
                  _miniBtn(Icons.view_column_rounded, '水平等距分布',
                      () => _distributeSelected(true)),
                  _miniBtn(Icons.view_day_rounded, '垂直等距分布',
                      () => _distributeSelected(false)),
                  _miniBtn(Icons.grid_on_rounded, '吸附 4px 网格', _snapSelected),
                ],
              ),
              _label(context, '提示：方向键微调 1px（Shift=8px）'),
            ],
          ],
          // ── cl45：层级树 ──
          _label(context, '层级树（点击选中，多选模式可加选）'),
          _layerTree(context, _root),
          const Divider(height: 14),
          // ── 一体成型预设（配色+圆角+间距+字号一次到位）──
          _label(context, '一体成型预设（一键全局风格）'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kUiPresets.map((UiPreset p) {
              final int? a = parseHexColor(p.palette.accent);
              return Tooltip(
                message: p.description,
                child: GestureDetector(
                  onTap: () => _commit(applyPreset(_root, p, nodeId: _selectedId)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.appColors.bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: a != null ? Color(a) : context.appColors.border,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: a != null ? Color(a) : context.appColors.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(p.name, style: context.appText.caption.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 18),
          // ── 预设配色（一键换色）──────────────────────
          _label(context, '预设配色（点一下换色）'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kUiPalettes.map((UiPalette p) {
              final int? a = parseHexColor(p.accent);
              final int? s = parseHexColor(p.surface);
              return Tooltip(
                message: '${p.name}配色（套用到${_selectedId == null || _selectedId == 'root' ? '整个画布' : '选中子树'}）',
                child: GestureDetector(
                  onTap: () => _commit(applyPalette(_root, p, nodeId: _selectedId)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: s != null ? Color(s) : context.appColors.bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: a != null ? Color(a) : context.appColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: a != null ? Color(a) : context.appColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(p.name, style: context.appText.caption.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 18),
          _label(context, '名称'),
          _textField(context, n.name, (String v) => _updateSelected(n.clone()..name = v)),
          if (n.type == UiNodeType.text || n.type == UiNodeType.button) ...<Widget>[
            _label(context, '文本'),
            _textField(context, n.text, (String v) => _updateSelected(n.clone()..text = v)),
          ],
          if (n.type == UiNodeType.text || n.type == UiNodeType.button) ...<Widget>[
            _label(context, '字号 ${n.fontSize.toStringAsFixed(0)}'),
            Slider(
              value: n.fontSize.clamp(8, 48),
              max: 48,
              onChanged: (double v) => _updateSelected(n.clone()..fontSize = v),
            ),
          ],
          if (n.type == UiNodeType.icon) ...<Widget>[
            _label(context, '图标 codePoint（如 e145 / e8b8）'),
            _textField(context, n.icon ?? '', (String v) => _updateSelected(n.clone()..icon = v)),
            _label(context, '大小 ${n.iconSize.toStringAsFixed(0)}'),
            Slider(
              value: n.iconSize.clamp(10, 80),
              max: 80,
              onChanged: (double v) => _updateSelected(n.clone()..iconSize = v),
            ),
          ],
          if (n.type == UiNodeType.container) ...<Widget>[
            _label(context, '布局'),
            DropdownButton<UiLayout>(
              value: n.layout,
              isExpanded: true,
              items: UiLayout.values
                  .map((UiLayout l) => DropdownMenuItem<UiLayout>(value: l, child: Text(l.name)))
                  .toList(),
              onChanged: (UiLayout? v) => v == null ? null : _updateSelected(n.clone()..layout = v),
            ),
            _label(context, '间距 gap ${n.gap.toStringAsFixed(0)}'),
            Slider(
              value: n.gap.clamp(0, 48),
              max: 48,
              onChanged: (double v) => _updateSelected(n.clone()..gap = v),
            ),
            _label(context, '内边距 ${n.padding.toStringAsFixed(0)}'),
            Slider(
              value: n.padding.clamp(0, 48),
              max: 48,
              onChanged: (double v) => _updateSelected(n.clone()..padding = v),
            ),
          ],
          _label(context, '圆角 ${n.cornerRadius.toStringAsFixed(0)}'),
          Slider(
            value: n.cornerRadius.clamp(0, 48),
            max: 48,
            onChanged: (double v) => _updateSelected(n.clone()..cornerRadius = v),
          ),
          _label(context, '填充色'),
          _colorField(context, n.color, (String? v) => _updateSelected(n.clone()..color = v)),
          // ── 渐变（容器/按钮支持）──────────────────────
          if (n.type == UiNodeType.container || n.type == UiNodeType.button) ...<Widget>[
            _label(context, '渐变（起色 / 止色）'),
            Row(
              children: <Widget>[
                Expanded(
                  child: _colorField(context, n.gradientStart,
                      (String? v) => _updateSelected(n.clone()..gradientStart = v)),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: _colorField(context, n.gradientEnd,
                      (String? v) => _updateSelected(n.clone()..gradientEnd = v)),
                ),
                IconButton(
                  tooltip: '清除渐变（改纯色）',
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  onPressed: () => _updateSelected(n.clone()
                    ..gradientStart = null
                    ..gradientEnd = null),
                ),
                IconButton(
                  tooltip: '一键套用内置渐变',
                  icon: const Icon(Icons.gradient_rounded, size: 18),
                  onPressed: () {
                    final String a = n.gradientStart ?? n.color ?? '#2E2E4A';
                    final String b = n.gradientEnd ?? '#0B1220';
                    _updateSelected(n.clone()
                      ..gradientStart = a
                      ..gradientEnd = b);
                  },
                ),
              ],
            ),
            _label(context, '方向'),
            DropdownButton<String>(
              value: n.gradientDirection,
              isExpanded: true,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'down', child: Text('↓ 向下')),
                DropdownMenuItem<String>(value: 'up', child: Text('↑ 向上')),
                DropdownMenuItem<String>(value: 'left', child: Text('← 向左')),
                DropdownMenuItem<String>(value: 'right', child: Text('→ 向右')),
                DropdownMenuItem<String>(value: 'diagonal', child: Text('↘ 对角')),
              ],
              onChanged: (String? v) => v == null
                  ? null
                  : _updateSelected(n.clone()..gradientDirection = v),
            ),
          ],
          _label(context, '强调色（按钮底）'),
          _colorField(context, n.accentColor, (String? v) => _updateSelected(n.clone()..accentColor = v)),
          if (n.type == UiNodeType.text || n.type == UiNodeType.icon) ...<Widget>[
            _label(context, '前景色'),
            _colorField(context, n.textColor, (String? v) => _updateSelected(n.clone()..textColor = v)),
          ],
          _label(context, '宽（留空=自适应）'),
          _numField(context, n.width, (double? v) => _updateSelected(n.clone()..width = v)),
          _label(context, '高（留空=自适应）'),
          _numField(context, n.height, (double? v) => _updateSelected(n.clone()..height = v)),
          const Divider(height: 14),
          // ── cl45：预览动画 + 可点击反馈 ──
          _label(context, '预览动画'),
          DropdownButton<String>(
            value: n.anim,
            isExpanded: true,
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: 'none', child: Text('无')),
              DropdownMenuItem<String>(value: 'fade', child: Text('淡入')),
              DropdownMenuItem<String>(value: 'scale', child: Text('缩放进入')),
            ],
            onChanged: (String? v) => v == null
                ? null
                : _updateSelected(n.clone()..anim = v),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('可点击（预览反馈）',
                style: context.appText.body.copyWith(fontSize: 12)),
            value: n.tappable,
            onChanged: (bool v) => _updateSelected(n.clone()..tappable = v),
          ),
          const SizedBox(height: 8),
          Text('提示：改属性即时预览；开「纠错」检查对比度/溢出/间距/重叠。',
              style: context.appText.artist.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _moveBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: IconButton(
          icon: Icon(icon, size: 16),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
        ),
      );

  /// cl45：对齐/分布工具小按钮。
  Widget _miniBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: context.appColors.bgCard,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.appColors.border),
            ),
            child: Icon(icon, size: 14, color: context.appColors.textSecondary),
          ),
        ),
      );

  /// cl45：层级树（缩进列表，点击选中；多选模式可加选）。
  Widget _layerTree(BuildContext context, UiNode node, {int depth = 0}) {
    final bool sel = _selectedIds.contains(node.id);
    final Widget row = InkWell(
      onTap: () => _select(node.id, additive: _multiSelect),
      child: Container(
        color: sel ? context.appColors.accent.withValues(alpha: 0.15) : null,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            SizedBox(width: depth * 12.0),
            Icon(
              switch (node.type) {
                UiNodeType.container => Icons.crop_square_rounded,
                UiNodeType.text => Icons.text_fields_rounded,
                UiNodeType.button => Icons.smart_button_rounded,
                UiNodeType.icon => Icons.emoji_symbols_rounded,
                UiNodeType.spacer => Icons.space_bar_rounded,
              },
              size: 12,
              color: context.appColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.appText.caption.copyWith(fontSize: 11),
              ),
            ),
            if (node.id == 'root')
              Text('root',
                  style: context.appText.artist.copyWith(fontSize: 9)),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        row,
        for (final UiNode c in node.children)
          _layerTree(context, c, depth: depth + 1),
      ],
    );
  }

  /// 在父容器内移动选中节点（delta<0 上移/最前，>0 下移/最后）。
  void _moveSibling(String childId, int delta) {
    final String? parentId = _parentOf(_root, childId);
    if (parentId == null) return;
    final UiNode? parent = _root.find(parentId);
    if (parent == null) return;
    final int cur = parent.children.indexWhere((UiNode c) => c.id == childId);
    if (cur < 0) return;
    int target = delta == -999
        ? 0
        : delta == 999
            ? parent.children.length - 1
            : cur + delta;
    target = target.clamp(0, parent.children.length - 1);
    if (target == cur) return;
    _commit(reorderChild(_root, parentId, childId, target));
  }

  /// 返回 [childId] 的直接父容器 id（root 无父 → null）。
  String? _parentOf(UiNode node, String childId) {
    if (node.children.any((UiNode c) => c.id == childId)) return node.id;
    for (final UiNode c in node.children) {
      final String? r = _parentOf(c, childId);
      if (r != null) return r;
    }
    return null;
  }

  /// cl45：批量删除选中（多选集合；root 不可删）。
  void _deleteSelected() {
    final Set<String> ids = Set<String>.of(_selectedIds)..remove('root');
    if (ids.isEmpty) return;
    UiNode removeByIds(UiNode node) {
      final UiNode c = node.clone();
      c.children = c.children
          .where((UiNode x) => !ids.contains(x.id))
          .map(removeByIds)
          .toList();
      return c;
    }

    _commit(removeByIds(_root));
    _select(null);
  }

  // ── cl45：复制 / 粘贴 / 对齐 / 分布 / 吸附 / 微调 ─────────

  void _copySelected() {
    if (_selectedIds.isEmpty) return;
    _clipboard = _nodesByIds(_selectedIds).map((UiNode n) => n.clone()).toList();
    appNotify(context, '已复制 ${_clipboard.length} 个节点');
  }

  void _paste() {
    if (_clipboard.isEmpty) return;
    _commit(UiNode.container(
      _root.id,
      _root.name,
      layout: _root.layout,
      align: _root.align,
      gap: _root.gap,
      padding: _root.padding,
      radius: _root.cornerRadius,
      width: _root.width,
      height: _root.height,
      color: _root.color,
      border: _root.borderColor,
      children: <UiNode>[
        ..._root.children,
        for (final UiNode c in _clipboard) c.remapIds(),
      ],
    ));
    appNotify(context, '已粘贴 ${_clipboard.length} 个节点');
  }

  void _alignSelected(_AlignAxis axis) {
    final List<UiNode> ns = _nodesByIds(_selectedIds);
    if (ns.length < 2) return;
    final double minX = ns.map((UiNode n) => n.x ?? 0).reduce(math.min);
    final double maxX = ns
        .map((UiNode n) => (n.x ?? 0) + (n.width ?? 0))
        .reduce(math.max);
    final double minY = ns.map((UiNode n) => n.y ?? 0).reduce(math.min);
    final double maxY = ns
        .map((UiNode n) => (n.y ?? 0) + (n.height ?? 0))
        .reduce(math.max);
    final double cx = (minX + maxX) / 2;
    final double cy = (minY + maxY) / 2;
    _commit(_applyToIds(_selectedIds, (UiNode n) {
      final UiNode c = n.clone();
      switch (axis) {
        case _AlignAxis.left:
          c.x = minX;
        case _AlignAxis.hCenter:
          c.x = cx - (n.width ?? 0) / 2;
        case _AlignAxis.right:
          c.x = maxX - (n.width ?? 0);
        case _AlignAxis.top:
          c.y = minY;
        case _AlignAxis.vCenter:
          c.y = cy - (n.height ?? 0) / 2;
        case _AlignAxis.bottom:
          c.y = maxY - (n.height ?? 0);
      }
      return c;
    }));
  }

  void _distributeSelected(bool horizontal) {
    final List<UiNode> ns = _nodesByIds(_selectedIds);
    if (ns.length < 3) return;
    ns.sort((UiNode a, UiNode b) => (horizontal ? (a.x ?? 0) : (a.y ?? 0))
        .compareTo(horizontal ? (b.x ?? 0) : (b.y ?? 0)));
    final double first = horizontal ? (ns.first.x ?? 0) : (ns.first.y ?? 0);
    final double last = horizontal
        ? (ns.last.x ?? 0) + (ns.last.width ?? 0)
        : (ns.last.y ?? 0) + (ns.last.height ?? 0);
    final double step = (last - first) / (ns.length - 1);
    final Map<String, double> pos = <String, double>{};
    for (int i = 0; i < ns.length; i++) {
      pos[ns[i].id] = first + step * i;
    }
    _commit(_applyToIds(_selectedIds, (UiNode n) {
      final UiNode c = n.clone();
      if (horizontal) {
        c.x = pos[n.id];
      } else {
        c.y = pos[n.id];
      }
      return c;
    }));
  }

  void _snapSelected() {
    _commit(_applyToIds(_selectedIds, (UiNode n) {
      final UiNode c = n.clone();
      if (c.x != null) c.x = (c.x! / 4).round() * 4.0;
      if (c.y != null) c.y = (c.y! / 4).round() * 4.0;
      return c;
    }));
  }

  void _nudgeSelected(double dx, double dy) {
    _commit(_applyToIds(_selectedIds, (UiNode n) {
      final UiNode c = n.clone();
      c.x = (c.x ?? 0) + dx;
      c.y = (c.y ?? 0) + dy;
      return c;
    }));
  }

  List<UiNode> _nodesByIds(Iterable<String> ids) => <UiNode>[
        for (final String id in ids)
          if (_root.find(id) != null) _root.find(id)!,
      ];

  /// 对选中的节点逐个应用 [fn]，返回新树（clone 保字段）。
  UiNode _applyToIds(Set<String> ids, UiNode Function(UiNode) fn) {
    final Set<String> s = Set<String>.of(ids);
    UiNode rec(UiNode n) {
      final UiNode c = n.clone();
      c.children = c.children.map(rec).toList();
      return s.contains(c.id) ? fn(c) : c;
    }

    return rec(_root);
  }

  Widget _label(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(s, style: context.appText.caption.copyWith(fontSize: 11, color: context.appColors.textSecondary)),
      );

  Widget _textField(BuildContext context, String v, ValueChanged<String> onChanged) => TextField(
        controller: TextEditingController(text: v),
        style: context.appText.body.copyWith(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: context.appColors.bgInput,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
        ),
        onChanged: onChanged,
      );

  Widget _numField(BuildContext context, double? v, ValueChanged<double?> onChanged) => TextField(
        controller: TextEditingController(text: v?.toStringAsFixed(0) ?? ''),
        keyboardType: TextInputType.number,
        style: context.appText.body.copyWith(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: context.appColors.bgInput,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
        ),
        onChanged: (String s) => onChanged(double.tryParse(s)),
      );

  static const List<String> _palette = <String>[
    '',
    '#9B7BFF', '#F5D98F', '#5AC8FA', '#30D158', '#FF453A',
    '#1C1C26', '#262634', '#121218', '#F2F2F7', '#B8B8C8', '#8A8A9C',
    '#59000000', '#151D2E', '#C0392B', '#2E86C1', '#27AE60',
  ];

  Widget _colorField(BuildContext context, String? v, ValueChanged<String?> onChanged) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _palette.map((String hex) {
          final bool sel = (v ?? '') == hex;
          final int? parsed = hex.isEmpty ? null : parseHexColor(hex);
          final Color? color = parsed != null ? Color(parsed) : null;
          return GestureDetector(
            onTap: () => onChanged(hex.isEmpty ? null : hex),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color ?? Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: sel ? context.appColors.accent : context.appColors.border,
                  width: sel ? 2.5 : 1,
                ),
              ),
              child: hex.isEmpty
                  ? Icon(Icons.close, size: 14, color: context.appColors.textTertiary)
                  : null,
            ),
          );
        }).toList(),
      );
}

/// cl45：对齐轴（对齐工具）。
enum _AlignAxis { left, hCenter, right, top, vCenter, bottom }

/// cl45：编辑器快捷键意图。
class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _CutIntent extends Intent {
  const _CutIntent();
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.dx, this.dy);
  final double dx;
  final double dy;
}
