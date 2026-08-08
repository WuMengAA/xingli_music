import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';

/// 圆角胶囊搜索栏（PRD P0-C1 / C2 / C3）
///
/// 几何：高 40 / 完全圆角 / 底色 `#E8E8E8`（Q3 已裁决）/ 左侧放大镜。
///
/// **受控组件**：不持有业务状态，`query` 由外部 provider 提供，
/// 变更经 [onChanged] 回抛。这样同一个组件可以服务曲库（搜歌）与设置（搜设置项）
/// 两套完全不同的语义（P0-C3），而组件自身保持纯粹。
///
/// 首页（`HomePage`）**不渲染**本组件（P0-C4）。
class AppSearchBar extends StatefulWidget {
  const AppSearchBar({
    super.key,
    required this.hintText,
    required this.query,
    required this.onChanged,
  });

  /// 占位文字。曲库/场景/探索 =「搜索歌曲、歌手、专辑」；设置 =「搜索设置项」
  final String hintText;

  /// 当前关键词（外部真源）
  final String query;

  /// 关键词变更回调
  final ValueChanged<String> onChanged;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant AppSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部 provider 被其它入口重置（如清空搜索）时同步回输入框，
    // 但要避开「用户正在输入」造成的光标跳动。
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasText = widget.query.isNotEmpty;

    return Container(
      height: AppSize.heightSearch,
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.search,
            size: 18,
            color: AppColors.iconInactive,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              style: AppText.body,
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hintText,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
          if (hasText)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clear,
              child: const SizedBox(
                width: 28,
                height: AppSize.heightSearch,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.iconInactive,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
