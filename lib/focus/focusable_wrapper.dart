import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dpad_navigator.dart';
import 'focus_theme.dart';
import 'input_mode_tracker.dart';

/// 一个包装小部件，使其子组件可获得焦点并支持 D-pad 导航。
///
/// 提供：
/// - 视觉焦点指示器（边框 + 缩放动画）
/// - 键盘/D-pad 事件处理（按下 Enter/Select 激活）
/// - 可选的自动滚动以保持焦点项可见
/// - SELECT 键的长按检测
/// - 导航回调（向上、返回）
class FocusableWrapper extends StatefulWidget {
  /// 要包装的子小部件。
  final Widget child;

  /// 当项目被选中时调用（Enter/Select/GamepadA）。
  /// 当 [enableLongPress] 为 true 时，用于短按。
  final VoidCallback? onSelect;

  /// 当触发长按时调用（按住 SELECT 键或上下文菜单键）。
  /// 仅在 [enableLongPress] 为 true 时触发。
  final VoidCallback? onLongPress;

  /// 当焦点改变时调用。
  final ValueChanged<bool>? onFocusChange;

  /// 当用户按下“上”且上方没有可聚焦项目时调用。
  final VoidCallback? onNavigateUp;

  /// 当用户按下“返回”时调用。
  final VoidCallback? onBack;

  /// 此小部件在首次构建时是否应自动获取焦点。
  final bool autofocus;

  /// 用于程序化焦点控制的可选外部 FocusNode。
  final FocusNode? focusNode;

  /// 焦点指示器的边框半径。
  final double borderRadius;

  /// 获得焦点时是否将小部件滚动到视图中。
  final bool autoScroll;

  /// 自动滚动的对齐方式（0.0 = 开始，0.5 = 居中，1.0 = 结束）。
  final double scrollAlignment;

  /// 是否使用舒适区滚动（仅当项目位于中间 60% 区域外时才滚动）。
  /// 如果为 false，则始终滚动到 [scrollAlignment]。
  final bool useComfortableZone;

  /// 用于辅助功能的可选语义标签。
  final String? semanticLabel;

  /// 该包装器是否可以接收焦点。
  final bool canRequestFocus;

  /// 自定义按键事件处理器。返回 KeyEventResult.handled 以消耗事件。
  /// 此方法在默认按键处理之前调用。
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  /// 是否启用 SELECT 键的长按检测。
  /// 启用后，按住 SELECT 500 毫秒后触发 [onLongPress]。
  /// 短按触发 [onSelect]。
  final bool enableLongPress;

  /// 长按检测的持续时间。
  final Duration longPressDuration;

  /// 焦点指示器是否使用背景颜色而非边框。
  /// 适用于边框效果不佳的视频控件。
  final bool useBackgroundFocus;

  /// 是否在获得焦点时禁用缩放动画。
  /// 适用于滑块等缩放效果奇怪的元素。
  final bool disableScale;

  const FocusableWrapper({
    super.key,
    required this.child,
    this.onSelect,
    this.onLongPress,
    this.onFocusChange,
    this.onNavigateUp,
    this.onBack,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = FocusTheme.defaultBorderRadius,
    this.autoScroll = true,
    this.scrollAlignment = 0.5,
    this.useComfortableZone = false,
    this.semanticLabel,
    this.canRequestFocus = true,
    this.onKeyEvent,
    this.enableLongPress = false,
    this.longPressDuration = const Duration(milliseconds: 500),
    this.useBackgroundFocus = false,
    this.disableScale = false,
  });

  @override
  State<FocusableWrapper> createState() => _FocusableWrapperState();
}

class _FocusableWrapperState extends State<FocusableWrapper> with SingleTickerProviderStateMixin {
  late FocusNode _focusNode;
  bool _ownsNode = false;
  bool _isFocused = false;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  // Long-press detection for SELECT key
  Timer? _longPressTimer;
  bool _isSelectKeyDown = false;

  @override
  void initState() {
    super.initState();
    _initFocusNode();
    _initAnimations();
  }

  void _initFocusNode() {
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
      _ownsNode = false;
    } else {
      _focusNode = FocusNode(
        debugLabel: widget.semanticLabel ?? 'FocusableWrapper',
        canRequestFocus: widget.canRequestFocus,
      );
      _ownsNode = true;
    }
  }

  void _initAnimations() {
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: FocusTheme.focusScale,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(FocusableWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle focusNode changes
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsNode) {
        _focusNode.dispose();
      }
      _initFocusNode();
    }

    // Update canRequestFocus
    if (widget.canRequestFocus != oldWidget.canRequestFocus) {
      _focusNode.canRequestFocus = widget.canRequestFocus;
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _animationController.dispose();
    if (_ownsNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    if (_isFocused != hasFocus) {
      setState(() {
        _isFocused = hasFocus;
      });

      // Animate scale
      if (hasFocus) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }

      // Auto-scroll into view
      if (hasFocus && widget.autoScroll) {
        _scrollIntoView();
      }

      // Notify listener
      widget.onFocusChange?.call(hasFocus);
    }
  }

  void _scrollIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isFocused) return;

      final renderObject = context.findRenderObject();
      if (renderObject == null) return;

      if (widget.useComfortableZone) {
        // Check if item is already in the comfortable zone
        final scrollable = Scrollable.maybeOf(context);
        if (scrollable == null) return;

        final viewport = scrollable.context.findRenderObject() as RenderBox?;
        if (viewport == null) return;

        // Get item's position relative to viewport
        final itemBox = renderObject as RenderBox;
        final itemPosition = itemBox.localToGlobal(Offset.zero, ancestor: viewport);

        // Check if item is already in the comfortable zone
        final viewportHeight = viewport.size.height;
        final itemHeight = itemBox.size.height;
        final itemVerticalCenter = itemPosition.dy + itemHeight / 2;

        // Define comfortable zone - if item center is within middle 60% of viewport, don't scroll
        final comfortZoneTop = viewportHeight * 0.2;
        final comfortZoneBottom = viewportHeight * 0.8;

        if (itemVerticalCenter >= comfortZoneTop && itemVerticalCenter <= comfortZoneBottom) {
          // Item is in comfortable zone, no need to scroll
          return;
        }
      }

      // Item is outside comfortable zone or comfortable zone disabled, scroll to alignment
      Scrollable.ensureVisible(
        context,
        alignment: widget.scrollAlignment,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    // Call custom key handler first
    if (widget.onKeyEvent != null) {
      final result = widget.onKeyEvent!(node, event);
      if (result == KeyEventResult.handled) {
        return result;
      }
    }

    // Handle SELECT key with optional long-press detection
    if (key.isSelectKey) {
      if (widget.enableLongPress) {
        if (event is KeyDownEvent) {
          // Only start timer on initial press, not repeats
          if (!_isSelectKeyDown) {
            _isSelectKeyDown = true;
            _longPressTimer?.cancel();
            _longPressTimer = Timer(widget.longPressDuration, () {
              // Long press detected
              if (mounted) {
                widget.onLongPress?.call();
              }
            });
          }
          return KeyEventResult.handled;
        } else if (event is KeyRepeatEvent) {
          // Consume repeat events to prevent system sounds
          return KeyEventResult.handled;
        } else if (event is KeyUpEvent) {
          final timerWasActive = _longPressTimer?.isActive ?? false;
          _longPressTimer?.cancel();
          if (timerWasActive && _isSelectKeyDown) {
            // Timer still active - short press
            widget.onSelect?.call();
          }
          // If timer already fired, long press was triggered - do nothing on key up
          _isSelectKeyDown = false;
          return KeyEventResult.handled;
        }
      } else {
        // Simple select handling without long-press
        if (event is KeyDownEvent) {
          widget.onSelect?.call();
          return KeyEventResult.handled;
        }
      }
    }

    // Ignore key up events for other keys
    if (!event.isActionable) {
      return KeyEventResult.ignored;
    }

    // Context menu key
    if (key.isContextMenuKey) {
      widget.onLongPress?.call();
      return KeyEventResult.handled;
    }

    // UP arrow - if callback provided, navigate up
    if (key == LogicalKeyboardKey.arrowUp && widget.onNavigateUp != null) {
      widget.onNavigateUp!();
      return KeyEventResult.handled;
    }

    // BACK key
    if (key.isBackKey && widget.onBack != null) {
      widget.onBack!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final duration = FocusTheme.getAnimationDuration(context);
    // Only show focus effects during keyboard/d-pad navigation
    final showFocus = _isFocused && InputModeTracker.isKeyboardMode(context);

    // Update animation duration if theme changes
    if (_animationController.duration != duration) {
      _animationController.duration = duration;
    }

    // Choose decoration based on useBackgroundFocus
    final decoration = widget.useBackgroundFocus
        ? FocusTheme.focusBackgroundDecoration(isFocused: showFocus, borderRadius: widget.borderRadius)
        : FocusTheme.focusDecoration(context, isFocused: showFocus, borderRadius: widget.borderRadius);

    Widget result = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _handleFocusChange,
      onKeyEvent: _handleKeyEvent,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          final shouldScale = showFocus && !widget.disableScale;
          return Transform.scale(
            scale: shouldScale ? _scaleAnimation.value : 1.0,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: decoration,
              child: widget.child,
            ),
          );
        },
      ),
    );

    // Add semantics if label provided
    if (widget.semanticLabel != null) {
      result = Semantics(label: widget.semanticLabel, button: widget.onSelect != null, child: result);
    }

    return result;
  }
}
