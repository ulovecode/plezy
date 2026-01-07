import 'package:flutter/material.dart';
import '../theme/mono_tokens.dart';

/// D-pad 导航的焦点样式常量。
class FocusTheme {
  FocusTheme._();

  /// 元素获得焦点时的缩放比例。
  static const double focusScale = 1.02;

  /// 焦点指示器的边框宽度。
  static const double focusBorderWidth = 2.5;

  /// 默认边框半径（匹配 MonoTokens.radiusSm）。
  static const double defaultBorderRadius = 8.0;

  /// 从主题中获取焦点边框颜色。
  static Color getFocusBorderColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  /// 从 MonoTokens 获取动画持续时间。
  static Duration getAnimationDuration(BuildContext context) {
    return Theme.of(context).extension<MonoTokens>()?.fast ?? const Duration(milliseconds: 150);
  }

  /// 构建焦点边框装饰。
  static BoxDecoration focusDecoration(
    BuildContext context, {
    required bool isFocused,
    double borderRadius = defaultBorderRadius,
  }) {
    final focusColor = getFocusBorderColor(context);

    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: isFocused ? focusColor : Colors.transparent, width: focusBorderWidth),
    );
  }

  /// 构建带有背景颜色而非边框的焦点装饰。
  /// 适用于需要匹配原生悬停样式的视频控件。
  static BoxDecoration focusBackgroundDecoration({required bool isFocused, double borderRadius = defaultBorderRadius}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: isFocused ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
    );
  }
}
