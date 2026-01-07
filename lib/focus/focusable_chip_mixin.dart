import 'package:flutter/material.dart';

import 'dpad_navigator.dart';

/// Chip 按键事件处理的回调。
class ChipKeyCallbacks {
  /// 当按下选择（SELECT）键时调用。
  final VoidCallback? onSelect;

  /// 当按下向下方向键时调用。
  final VoidCallback? onNavigateDown;

  /// 当按下向上方向键时调用。
  final VoidCallback? onNavigateUp;

  /// 当按下向左方向键时调用。
  final VoidCallback? onNavigateLeft;

  /// 当按下向右方向键时调用。
  final VoidCallback? onNavigateRight;

  /// 当按下返回（BACK）键时调用。
  final VoidCallback? onBack;

  const ChipKeyCallbacks({
    this.onSelect,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });
}

/// 一个混入（mixin），为 Chip 小部件提供常见的 FocusNode 生命周期管理。
///
/// 此混入处理：
/// - 内部/外部 FocusNode 模式
/// - `_isFocused` 状态跟踪
/// - 在 `initState` 中设置监听器
/// - 在 `didUpdateWidget` 中进行监听器交接
/// - 在 `dispose` 中清理
///
/// 如何使用此混入：
/// 1. 在你的 State 类中添加 `with FocusableChipStateMixin<YourWidget>`
/// 2. 实现 [widgetFocusNode] 以返回小部件的可选 focusNode
/// 3. 实现 [debugLabel] 以返回内部节点的调试标签
/// 4. 在你的 `initState` 中调用 [initFocusNode]
/// 5. 在你的 `didUpdateWidget` 中调用 [updateFocusNode]
/// 6. 在你的 `dispose` 中调用 [disposeFocusNode]
/// 7. 在 build 方法中使用 [focusNode] 和 [isFocused]
mixin FocusableChipStateMixin<T extends StatefulWidget> on State<T> {
  FocusNode? _internalFocusNode;
  bool _isFocused = false;

  /// 重写以返回小部件的可选外部焦点节点。
  FocusNode? get widgetFocusNode;

  /// 重写以返回内部焦点节点的调试标签。
  String get debugLabel;

  /// 活动焦点节点（如果提供了外部则使用外部，否则使用内部）。
  FocusNode get focusNode {
    return widgetFocusNode ?? (_internalFocusNode ??= FocusNode(debugLabel: debugLabel));
  }

  /// 此小部件当前是否获得焦点。
  bool get isFocused => _isFocused;

  /// 在你的 `initState` 中调用此方法以设置焦点监听器。
  void initFocusNode() {
    focusNode.addListener(_onFocusChange);
  }

  /// 在你的 `didUpdateWidget` 中调用此方法，并传入旧小部件的 focusNode。
  void updateFocusNode(FocusNode? oldFocusNode) {
    if (oldFocusNode != widgetFocusNode) {
      oldFocusNode?.removeListener(_onFocusChange);
      focusNode.addListener(_onFocusChange);
    }
  }

  /// 在你的 `dispose` 中调用此方法以清理焦点监听器。
  void disposeFocusNode() {
    focusNode.removeListener(_onFocusChange);
    _internalFocusNode?.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = focusNode.hasFocus);
    }
  }

  /// Chip 小部件的共享按键事件处理器。
  ///
  /// 处理常见的按键模式：
  /// - 选择键 -> onSelect
  /// - 方向键 -> 导航回调
  /// - 返回键 -> onBack
  ///
  /// 如果事件被消耗则返回 [KeyEventResult.handled]，
  /// 否则返回 [KeyEventResult.ignored]。
  KeyEventResult handleChipKeyEvent(FocusNode node, KeyEvent event, ChipKeyCallbacks callbacks) {
    if (!event.isActionable) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // 选择键激活 chip
    if (key.isSelectKey && callbacks.onSelect != null) {
      callbacks.onSelect!();
      return KeyEventResult.handled;
    }

    // 左方向键
    if (key.isLeftKey && callbacks.onNavigateLeft != null) {
      callbacks.onNavigateLeft!();
      return KeyEventResult.handled;
    }

    // 右方向键
    if (key.isRightKey && callbacks.onNavigateRight != null) {
      callbacks.onNavigateRight!();
      return KeyEventResult.handled;
    }

    // 下方向键
    if (key.isDownKey) {
      callbacks.onNavigateDown?.call();
      return KeyEventResult.handled;
    }

    // 上方向键
    if (key.isUpKey && callbacks.onNavigateUp != null) {
      callbacks.onNavigateUp!();
      return KeyEventResult.handled;
    }

    // 返回键
    if (key.isBackKey && callbacks.onBack != null) {
      callbacks.onBack!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}
